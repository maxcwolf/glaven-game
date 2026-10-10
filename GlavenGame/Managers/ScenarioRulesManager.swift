import Foundation

/// When scenario rules are evaluated.
///
/// In the Gloomhaven Secretariat data format a rule with `"start": true` is resolved at the
/// START of a round and a rule without it at the END of a round. Rules with `"always": true`
/// are re-checked on every evaluation (any phase), which is how mid-round triggers such as
/// "when the door is destroyed" or "when room 3 is revealed" fire promptly.
enum RulePhase: String, CaseIterable {
    /// Start of a round: `game.round` already holds the new round number.
    /// Evaluates `start` rules (and `always` rules).
    case roundStart
    /// End of a round: `game.round` still holds the round that is ending.
    /// Evaluates rules without `start` (and `always` rules).
    case roundEnd
    /// Any mid-round board change (a figure died, a room was revealed, ...).
    /// Evaluates `always` rules and condition-only rules that have no `round` expression.
    case figureChange
}

/// Timing of per-turn rules (`alwaysApplyTurn` in scenario data).
enum TurnRuleTiming: String {
    /// `"alwaysApplyTurn": "turn"` — at the start of a figure's turn.
    case turnStart = "turn"
    /// `"alwaysApplyTurn": "after"` — at the end of a figure's turn.
    case turnEnd = "after"
}

@Observable
final class ScenarioRulesManager {
    private let game: GameState
    private let monsterManager: MonsterManager
    private let entityManager: EntityManager

    /// Called when a rule's `rooms` effect should reveal rooms. Wired from GameManager.
    var onOpenRooms: (([Int]) -> Void)?
    /// Places a rule-spawned monster on the board (entity + piece). Returns false when the board
    /// isn't active, in which case only the game-state entity is created.
    /// `placed`: set up late rather than spawned (it drops money).
    var onSpawnMonster: ((_ name: String, _ type: MonsterType, _ marker: String?, _ health: String?, _ placed: Bool) -> Bool)?
    /// Sets up monster types the scenario held back. Wired from GameManager.
    var onSetUpMonsters: (([String]) -> Void)?
    /// Whether something has happened on the board (a rule's `when`); nothing has without a board.
    var boardFactHolds: ((BoardFact) -> Bool)?
    /// Whether a figure stands where an identifier's `near`/`tile` asks.
    var standsWhere: ((any Entity, ScenarioFigureRuleIdentifier) -> Bool)?
    /// Damage and healing a rule gives a monster, summon or objective, offered to the board
    /// (true: the board does it, with all that follows — a death, Poison stopping a heal).
    var takesFigureDamage: ((_ entity: any Entity, _ amount: Int) -> Bool)?
    var healsFigure: ((_ entity: any Entity, _ amount: Int) -> Bool)?
    /// Damage a rule deals a character, offered to the board (true: the board takes it, so the
    /// character may lose cards to negate it, p.22).
    var takesCharacterDamage: ((_ character: GameCharacter, _ amount: Int) -> Bool)?

    /// Re-entrancy guard: effects (e.g. `onOpenRooms`) may cause callers to request another
    /// evaluation while one is running; that request is folded into a follow-up pass.
    @ObservationIgnored private var isEvaluating = false
    @ObservationIgnored private var reentrantRequest = false

    /// Bound on follow-up passes after a pass that applied rules (cascading triggers).
    private static let maxPasses = 5

    init(game: GameState, monsterManager: MonsterManager, entityManager: EntityManager) {
        self.game = game
        self.monsterManager = monsterManager
        self.entityManager = entityManager
    }

    // MARK: - Rule Evaluation

    /// Backwards-compatible entry point for mid-round re-checks (e.g. after a kill).
    /// Equivalent to `evaluateRules(phase: .figureChange)`.
    func evaluateRules() {
        evaluateRules(phase: .figureChange)
    }

    /// Evaluates every rule of the current scenario that belongs to `phase` and applies the
    /// ones whose conditions hold.
    ///
    /// Firing limits:
    /// - `once` rules fire at most once per scenario.
    /// - Other rules fire at most once per round (tracked in `scenario.appliedRules` with a
    ///   per-round key, so undo/redo snapshots restore it).
    /// - `alwaysApply` rules whose only effect is `statEffects` are persistent modifiers and are
    ///   re-applied (idempotently) on every evaluation so newly spawned monsters pick them up.
    /// - Rules with `alwaysApplyTurn` are skipped here; see `evaluateTurnRules(_:for:)`.
    ///
    /// After a pass that applied something, further `.figureChange` passes run (bounded) so that
    /// rules triggered by those effects (e.g. a room opened by another rule) fire immediately.
    func evaluateRules(phase: RulePhase) {
        if isEvaluating {
            reentrantRequest = true
            return
        }
        isEvaluating = true
        defer { isEvaluating = false }

        var currentPhase = phase
        for _ in 0..<Self.maxPasses {
            reentrantRequest = false
            let appliedSomething = runPass(phase: currentPhase)
            guard appliedSomething || reentrantRequest else { break }
            currentPhase = .figureChange
        }
    }

    /// Applies per-turn rules (`alwaysApplyTurn`) to the figure whose turn is starting/ending.
    /// Only figure effects are applied, and only to `entity` (if it matches the rule's identifier).
    func evaluateTurnRules(_ timing: TurnRuleTiming, for entity: any Entity) {
        guard let scenario = game.scenario, let rules = scenario.data.rules else { return }
        for (index, rule) in rules.enumerated() where rule.alwaysApplyTurn == timing.rawValue {
            if rule.isOnce && scenario.appliedRules.contains(scenario.ruleKey(index: index)) { continue }
            guard conditionsHold(rule, index: index, scenario: scenario, round: game.round) else { continue }
            let effects = (rule.figures ?? []).filter { !Self.isTriggerType($0.type) }
            var applied = false
            for figureRule in effects {
                guard let type = figureRule.type, let identifier = figureRule.identifier else { continue }
                let targets = findTargets(identifier: identifier)
                guard targets.contains(where: { $0 === entity }) else { continue }
                applyFigureEffect(type, value: figureRule.value, to: entity)
                applied = true
            }
            if applied {
                markApplied(scenario.ruleKey(index: index), in: scenario)
            }
        }
    }

    // MARK: - Pass

    /// Runs one evaluation pass. Returns true if a (non-persistent) rule was applied.
    private func runPass(phase: RulePhase) -> Bool {
        guard let scenario = game.scenario, let rules = scenario.data.rules else { return false }
        let round = game.round
        var appliedSomething = false

        for (index, rule) in rules.enumerated() {
            guard rule.alwaysApplyTurn == nil else { continue }
            guard Self.isEligible(rule, in: phase) else { continue }
            let persistent = Self.isPersistentStatEffectRule(rule)
            if !persistent && hasFired(rule, index: index, round: round, scenario: scenario) { continue }
            guard conditionsHold(rule, index: index, scenario: scenario, round: round) else { continue }
            applyRule(rule, index: index, scenario: scenario, round: round)
            if !persistent { appliedSomething = true }
        }
        return appliedSomething
    }

    // MARK: - Phase & Firing Limits

    /// Whether `rule` is evaluated during `phase`.
    static func isEligible(_ rule: ScenarioRule, in phase: RulePhase) -> Bool {
        if rule.isAlways { return true }
        guard rule.round != nil else {
            // No round expression: a purely condition-driven rule (figure triggers / required
            // rooms) is re-checked on every evaluation. Without any condition it never fires
            // automatically.
            let hasFigureTrigger = (rule.figures ?? []).contains { isTriggerType($0.type) }
            let hasRoomRequirement = !(rule.requiredRooms ?? []).isEmpty
            return hasFigureTrigger || hasRoomRequirement || !(rule.when ?? []).isEmpty
        }
        switch phase {
        case .roundStart: return rule.isStart
        case .roundEnd: return !rule.isStart
        case .figureChange: return false
        }
    }

    /// `alwaysApply` rules that only carry `statEffects` are persistent, idempotent modifiers.
    static func isPersistentStatEffectRule(_ rule: ScenarioRule) -> Bool {
        guard rule.alwaysApply == true, !(rule.statEffects ?? []).isEmpty else { return false }
        let hasOtherEffects = !(rule.spawns ?? []).isEmpty
            || !(rule.objectiveSpawns ?? []).isEmpty
            || (rule.figures ?? []).contains { !isTriggerType($0.type) }
            || !(rule.elements ?? []).isEmpty
            || !(rule.rooms ?? []).isEmpty
            || !(rule.setUp ?? []).isEmpty
            || !(rule.disableRules ?? []).isEmpty
            || rule.finish != nil
        return !hasOtherEffects
    }

    /// Key recording that a non-`once` rule fired in `round`.
    static func roundKey(_ ruleKey: String, round: Int) -> String {
        "\(ruleKey)@r\(round)"
    }

    /// Inserts `key` only when missing, so repeated (persistent) applications don't churn observers.
    private func markApplied(_ key: String, in scenario: Scenario) {
        if !scenario.appliedRules.contains(key) {
            scenario.appliedRules.insert(key)
        }
    }

    private func hasFired(_ rule: ScenarioRule, index: Int, round: Int, scenario: Scenario) -> Bool {
        let key = scenario.ruleKey(index: index)
        if rule.isOnce { return scenario.appliedRules.contains(key) }
        return scenario.appliedRules.contains(Self.roundKey(key, round: round))
    }

    // MARK: - Trigger Conditions

    private func conditionsHold(_ rule: ScenarioRule, index: Int, scenario: Scenario, round: Int) -> Bool {
        if scenario.disabledRules.contains(index) { return false }

        if let requiredRooms = rule.requiredRooms, !requiredRooms.isEmpty {
            let revealed = Set(scenario.revealedRooms)
            if !Set(requiredRooms).isSubset(of: revealed) { return false }
        }

        if let roundExpr = rule.round {
            if !evaluateRoundCondition(roundExpr, round: round) { return false }
        }

        if let facts = rule.when, !facts.allSatisfy({ boardFactHolds?($0) ?? false }) { return false }

        // Figure-based trigger conditions (dead / present / killed). A rule's figures array may
        // contain both trigger entries and effect entries; all trigger entries must pass.
        let triggers = (rule.figures ?? []).filter { Self.isTriggerType($0.type) }
        if !triggers.allSatisfy({ evaluateFigureTrigger($0, scenario: scenario) }) { return false }

        return true
    }

    static func isTriggerType(_ type: String?) -> Bool {
        guard let type = type else { return false }
        return ["dead", "present", "killed"].contains(type)
    }

    /// Evaluates a rule's `round` expression with R = `round`, C = number of participating
    /// characters and L = scenario level. Unparseable expressions are treated as not triggered.
    func evaluateRoundCondition(_ expression: String, round: Int) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "start" { return round == 0 }
        if let targetRound = Int(trimmed) { return round == targetRound }

        let variables = ["R": round, "C": scenarioCharacterCount, "L": game.level]
        guard let result = ScenarioExpression.condition(trimmed, variables: variables) else {
            print("[ScenarioRules] Cannot evaluate round expression '\(expression)'; rule not triggered")
            return false
        }
        return result
    }

    private func evaluateFigureTrigger(_ figureRule: ScenarioFigureRule, scenario: Scenario) -> Bool {
        guard let type = figureRule.type, let identifier = figureRule.identifier else { return true }

        switch type {
        case "dead":
            // All matching entities must be gone (either never existed or all dead).
            return findTargets(identifier: identifier).isEmpty

        case "present":
            // At least one matching entity must be alive.
            return !findTargets(identifier: identifier).isEmpty

        case "killed":
            let count = killCount(identifier: identifier, scenario: scenario)
            switch figureRule.value {
            case .string(let s) where s.lowercased() == "all":
                // Every spawned matching entity is dead (and at least one was killed).
                return count >= 1 && findTargets(identifier: identifier).isEmpty
            case .string(let s):
                return count >= (ScenarioExpression.integerValue(s, variables: valueVariables()) ?? 1)
            case .int(let threshold):
                return count >= threshold
            case nil:
                return count >= 1
            }

        default:
            return true
        }
    }

    /// Number of matching figures killed so far.
    private func killCount(identifier: ScenarioFigureRuleIdentifier, scenario: Scenario) -> Int {
        let targetType = identifier.type ?? "monster"
        let namePattern = identifier.name ?? ".*"
        let deadMatches = deadEntities(identifier: identifier).count

        guard targetType == "monster", identifier.marker == nil, (identifier.tags ?? []).isEmpty else {
            // Objectives, markers and tags are not in killCounts: count dead entities instead.
            return deadMatches
        }
        let recorded = scenario.killCounts
            .filter { namePattern == ".*" || matchesName($0.key, pattern: namePattern) }
            .values.reduce(0, +)
        return max(recorded, deadMatches)
    }

    // MARK: - Apply Rule Effects

    private func applyRule(_ rule: ScenarioRule, index: Int, scenario: Scenario, round: Int) {
        let ruleKey = scenario.ruleKey(index: index)
        markApplied(ruleKey, in: scenario)
        if !rule.isOnce {
            markApplied(Self.roundKey(ruleKey, round: round), in: scenario)
        }

        let edition = scenario.data.edition
        let playerCount = scenarioPlayerCount

        // Spawn monsters
        if let spawns = rule.spawns, !spawns.isEmpty {
            let figureCount = triggerFigureCount(rule)
            for spawn in spawns {
                guard let monsterType = spawn.monster.monsterType(forPlayerCount: playerCount) else { continue }
                let count = resolveCount(spawn.count, figureCount: figureCount)
                for _ in 0..<count {
                    spawnMonsterEntity(name: spawn.monster.name, type: monsterType,
                                       edition: edition, marker: spawn.marker,
                                       health: spawn.monster.health, placed: spawn.placed ?? false)
                }
            }
        }

        // Spawn objectives
        if let objectiveSpawns = rule.objectiveSpawns, !objectiveSpawns.isEmpty {
            let figureCount = triggerFigureCount(rule)
            for spawn in objectiveSpawns {
                let count = resolveCount(spawn.count, figureCount: figureCount)
                for _ in 0..<count {
                    spawnObjective(spawn.objective, edition: edition, marker: spawn.marker)
                }
            }
        }

        // Apply figure effects (non-trigger entries only); F in a value is the trigger's count
        // ("heals C−1 for each bone pile").
        if let figures = rule.figures {
            appliedFigureCount = triggerFigureCount(rule)
            defer { appliedFigureCount = nil }
            for figureRule in figures where !Self.isTriggerType(figureRule.type) {
                applyFigureRule(figureRule, edition: edition)
            }
        }

        // Set element states
        if let elements = rule.elements {
            for elementRule in elements { applyElementRule(elementRule) }
        }

        // Monsters held back until now are set up
        if let names = rule.setUp, !names.isEmpty {
            onSetUpMonsters?(names)
        }

        // Reveal rooms as an effect
        if let roomNumbers = rule.rooms, !roomNumbers.isEmpty {
            onOpenRooms?(roomNumbers)
        }

        // Disable other rules
        if let disableRules = rule.disableRules {
            for ruleId in disableRules {
                if let ruleIndex = ruleId.index {
                    let isCurrent = (ruleId.edition == nil || ruleId.edition == scenario.data.edition) &&
                                    (ruleId.scenario == nil || ruleId.scenario == scenario.data.index)
                    if isCurrent { scenario.disabledRules.insert(ruleIndex) }
                }
            }
        }

        // Apply scenario stat effects (monster renames, health overrides, immunities, actions)
        if let statEffects = rule.statEffects, !statEffects.isEmpty {
            applyScenarioStatEffects(statEffects, edition: edition, playerCount: playerCount)
        }

        // Finish condition — signal win or loss via the scenario object.
        // BoardCoordinator.checkVictoryDefeat() reads this on each call.
        if let finish = rule.finish, finish == "won" || finish == "lost" {
            scenario.pendingFinish = finish
        }
    }

    // MARK: - Counts & Variables

    /// Number of participating (non-absent) characters. Fixed for the scenario: exhausting a
    /// character does not change it (matches ScenarioManager's spawn player count).
    private var scenarioCharacterCount: Int {
        game.characters.filter { !$0.absent }.count
    }

    /// Player count used for monster-type selection (minimum 2).
    private var scenarioPlayerCount: Int {
        max(2, scenarioCharacterCount)
    }

    /// Variables for value expressions (damage, hit points, counts). C is at least 2, as in
    /// GHS entity-value formulas.
    /// F while a rule is being applied: how many figures its triggers count.
    @ObservationIgnored private var appliedFigureCount: Int?

    private func valueVariables(figureCount: Int? = nil) -> [String: Int] {
        var variables = ["C": scenarioPlayerCount, "L": game.level, "R": game.round]
        if let figureCount = figureCount ?? appliedFigureCount { variables["F"] = figureCount }
        return variables
    }

    /// Resolves a spawn `count` (number or expression such as `"F"` or `"C-1"`), clamped to 0...20.
    private func resolveCount(_ value: IntOrString?, figureCount: Int) -> Int {
        let raw: Int
        switch value {
        case nil:
            raw = 1
        case .int(let n):
            raw = n
        case .string(let s):
            if let n = ScenarioExpression.integerValue(s, variables: valueVariables(figureCount: figureCount)) {
                raw = n
            } else {
                print("[ScenarioRules] Cannot evaluate spawn count '\(s)'; spawning 1")
                raw = 1
            }
        }
        return min(max(raw, 0), 20)
    }

    /// `F` in spawn counts: the number of figures matched by the rule's trigger entries
    /// (alive figures for `present`, dead ones for `dead` / `killed`). 1 if the rule has no
    /// figure trigger.
    private func triggerFigureCount(_ rule: ScenarioRule) -> Int {
        let triggers = (rule.figures ?? []).filter { Self.isTriggerType($0.type) }
        guard !triggers.isEmpty else { return 1 }
        var total = 0
        for trigger in triggers {
            guard let identifier = trigger.identifier else { continue }
            if trigger.type == "present" {
                total += findTargets(identifier: identifier).count
            } else {
                total += deadEntities(identifier: identifier).count
            }
        }
        return total
    }

    // MARK: - Private: Stat Effects

    private func applyScenarioStatEffects(_ effects: [StatEffectRule], edition: String, playerCount: Int) {
        for effect in effects {
            guard let identifier = effect.identifier,
                  let statEffect = effect.statEffect else { continue }

            // Check reference condition (e.g. "Altar present"). An effect counted in X — "for each
            // altar that isn't destroyed" — still applies with none left, as nothing at all.
            let usesX = [statEffect.health, statEffect.attack, statEffect.movement, statEffect.range]
                .contains { $0?.contains("X") == true }
            var x = 0
            if let reference = effect.reference {
                if usesX, reference.type == "present", let counted = reference.identifier {
                    x = findTargets(identifier: counted).count
                } else {
                    guard checkStatEffectReference(reference, edition: edition) else { continue }
                }
            }

            let targetEdition = identifier.edition ?? edition
            let namePattern = identifier.name ?? ".*"

            for monster in game.monsters {
                let editionMatches = identifier.edition == nil || monster.edition == targetEdition
                guard editionMatches, matchesName(monster.name, pattern: namePattern) else { continue }
                // Re-applying a rename / deck override reshuffles the ability deck and discards the
                // drawn card, so only apply those parts once per monster group.
                var effectToApply = statEffect
                if let name = statEffect.name, monster.displayName == name { effectToApply.name = nil }
                if let deck = statEffect.deck, monster.deckOverride == deck { effectToApply.deck = nil }
                monsterManager.applyScenarioStatEffect(effectToApply, to: monster, charCount: playerCount, x: x)
            }
        }
    }

    private func checkStatEffectReference(_ reference: StatEffectReference, edition: String) -> Bool {
        guard let identifier = reference.identifier, let type = reference.type else { return true }
        let targets = findTargets(identifier: identifier)
        switch type {
        case "present": return !targets.isEmpty
        case "dead":    return targets.isEmpty
        default:        return true
        }
    }

    // MARK: - Private: Spawning

    private func spawnMonsterEntity(name: String, type: MonsterType, edition: String,
                                     marker: String? = nil, health: String? = nil, placed: Bool = false) {
        if onSpawnMonster?(name, type, marker, health, placed) == true { return }
        var monster = game.monsters.first(where: { $0.name == name && $0.edition == edition })
        if monster == nil {
            monsterManager.addMonster(name: name, edition: edition)
            monster = game.monsters.last(where: { $0.name == name && $0.edition == edition })
        }
        guard let monster = monster else { return }

        let entityCountBefore = monster.entities.count
        monster.off = false
        monsterManager.addEntity(type: type, to: monster)
        // addEntity may refuse (e.g. no standee available); never decorate an older entity.
        guard monster.entities.count > entityCountBefore, let entity = monster.entities.last else { return }

        if let marker = marker {
            entity.markers.append(marker)
        }
        if let healthExpr = health,
           let hp = ScenarioExpression.integerValue(healthExpr, variables: valueVariables()) {
            entity.health = hp
            entity.maxHealth = hp
        }
    }

    private func spawnObjective(_ objData: ObjectiveData, edition: String, marker: String?) {
        let container = GameObjectiveContainer(
            name: objData.name ?? "Objective",
            edition: edition,
            title: objData.name ?? "",
            escort: objData.isEscort,
            level: game.level
        )
        container.initiative = objData.resolvedInitiative

        if let healthValue = objData.health {
            let hp: Int
            switch healthValue {
            case .int(let n): hp = n
            case .string(let s): hp = ScenarioExpression.integerValue(s, variables: valueVariables()) ?? 1
            }
            let entity = GameObjectiveEntity(number: game.nextObjectiveNumber, health: hp, maxHealth: hp)
            if let marker = marker ?? objData.marker { entity.marker = marker }
            container.entities.append(entity)
        }

        game.figures.append(.objective(container))
    }

    // MARK: - Private: Figure Rules

    private func applyFigureRule(_ figureRule: ScenarioFigureRule, edition: String) {
        guard let ruleType = figureRule.type else { return }
        guard let identifier = figureRule.identifier else { return }

        let targets = findTargets(identifier: identifier)
        for target in targets {
            // "Ignore negative scenario effects" perk.
            if figureRule.scenarioEffect == true, let character = target as? GameCharacter,
               character.hasCustomPerk("ignoreNegativeScenario") {
                continue
            }
            applyFigureEffect(ruleType, value: figureRule.value, to: target)
        }
    }

    /// Alive (non-exhausted, non-absent) entities matching `identifier`.
    ///
    /// Identifier types: `character`, `characterWithSummon` (characters plus their summons),
    /// `summon`, `monster` (default), `objective`, and `all` (every figure on the board).
    /// Filters: `name` (exact or anchored regex), `marker`, `tags`, and `hp` (an expression over
    /// `HP` = current and `H` = maximum hit points, e.g. `"HP < H"`).
    private func findTargets(identifier: ScenarioFigureRuleIdentifier) -> [any Entity] {
        matchingEntities(identifier: identifier, alive: true)
    }

    /// Dead / exhausted entities matching `identifier` (monster entities removed from the game are
    /// not counted).
    private func deadEntities(identifier: ScenarioFigureRuleIdentifier) -> [any Entity] {
        matchingEntities(identifier: identifier, alive: false)
    }

    private func matchingEntities(identifier: ScenarioFigureRuleIdentifier, alive: Bool) -> [any Entity] {
        let targetType = identifier.type ?? "monster"
        let isAll = targetType == "all"
        let namePattern = isAll ? ".*" : (identifier.name ?? ".*")
        let requiredTags = identifier.tags ?? []
        let markerFilter = isAll ? nil : identifier.marker
        var results: [any Entity] = []

        func passesFilters(_ entity: any Entity) -> Bool {
            if !requiredTags.isEmpty && !requiredTags.allSatisfy({ entity.tags.contains($0) }) { return false }
            if let hpExpr = identifier.hp, !matchesHealthFilter(hpExpr, entity: entity) { return false }
            if identifier.isPlaced, standsWhere?(entity, identifier) != true { return false }
            return true
        }

        // Characters (and their summons)
        if isAll || ["character", "characterWithSummon", "summon"].contains(targetType) {
            for character in game.characters where !character.absent {
                let nameMatches = matchesName(character.name, pattern: namePattern)
                if targetType != "summon" && nameMatches && character.exhausted != alive
                    && markerFilter == nil && passesFilters(character) {
                    results.append(character)
                }
                guard isAll || targetType == "characterWithSummon" || targetType == "summon" else { continue }
                for summon in character.summons where summon.dead != alive {
                    // characterWithSummon matches the owner's name; summon matches the summon's.
                    let summonMatches = targetType == "summon"
                        ? matchesName(summon.name, pattern: namePattern)
                        : nameMatches
                    if summonMatches && markerFilter == nil && passesFilters(summon) {
                        results.append(summon)
                    }
                }
            }
        }

        // Monsters
        if isAll || targetType == "monster" {
            for monster in game.monsters where matchesName(monster.name, pattern: namePattern) {
                for entity in monster.entities where entity.dead != alive {
                    if let markerFilter, !entity.markers.contains(markerFilter) { continue }
                    if passesFilters(entity) { results.append(entity) }
                }
            }
        }

        // Objectives
        if isAll || targetType == "objective" {
            for figure in game.figures {
                guard case .objective(let container) = figure,
                      matchesName(container.name, pattern: namePattern) else { continue }
                for entity in container.entities where entity.dead != alive {
                    if let markerFilter, entity.marker != markerFilter && !entity.markers.contains(markerFilter) {
                        continue
                    }
                    if passesFilters(entity) { results.append(entity) }
                }
            }
        }

        return results
    }

    /// Evaluates an identifier `hp` filter such as `"HP < H"` (HP = current, H = max hit points).
    private func matchesHealthFilter(_ expression: String, entity: any Entity) -> Bool {
        let variables = ["HP": entity.health, "H": entity.maxHealth, "C": scenarioPlayerCount, "L": game.level]
        guard let result = ScenarioExpression.condition(expression, variables: variables) else {
            print("[ScenarioRules] Cannot evaluate hp filter '\(expression)'; no match")
            return false
        }
        return result
    }

    private func matchesName(_ name: String, pattern: String) -> Bool {
        if pattern == ".*" { return true }
        if pattern == name { return true }
        if let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$", options: []) {
            let range = NSRange(name.startIndex..., in: name)
            return regex.firstMatch(in: name, options: [], range: range) != nil
        }
        return false
    }

    /// Integer value of a figure-rule `value` (`2`, `"2"`, `"(2xC)+L-2"`).
    private func integerValue(_ value: IntOrString?, default defaultValue: Int) -> Int {
        switch value {
        case .int(let n):
            return n
        case .string(let s):
            if let n = ScenarioExpression.integerValue(s, variables: valueVariables()) { return n }
            print("[ScenarioRules] Cannot evaluate value '\(s)'; using \(defaultValue)")
            return defaultValue
        case nil:
            return defaultValue
        }
    }

    private func stringValue(_ value: IntOrString?) -> String? {
        switch value {
        case .int(let n): return String(n)
        case .string(let s): return s
        case nil: return nil
        }
    }

    private func applyFigureEffect(_ type: String, value: IntOrString?, to entity: any Entity) {
        switch type {
        case "damage":
            let amount = integerValue(value, default: 1)
            guard amount > 0 else { break }
            if let character = entity as? GameCharacter {
                if takesCharacterDamage?(character, amount) == true { break }
            } else if takesFigureDamage?(entity, amount) == true { break }
            entityManager.changeHealth(entity, amount: -amount)

        case "heal":
            let amount = integerValue(value, default: 1)
            guard amount > 0 else { break }
            if !(entity is GameCharacter), healsFigure?(entity, amount) == true { break }
            entityManager.changeHealth(entity, amount: amount)

        case "setHp":
            if value != nil {
                entity.health = max(0, integerValue(value, default: entity.health))
            }

        case "condition", "gainCondition":
            if let condStr = stringValue(value), let cond = ConditionName(rawValue: condStr) {
                entityManager.addCondition(cond, to: entity)
            }

        case "permanentCondition":
            if let condStr = stringValue(value), let cond = ConditionName(rawValue: condStr) {
                entityManager.addCondition(cond, to: entity, permanent: true)
            }

        case "removeCondition":
            if let condStr = stringValue(value), let cond = ConditionName(rawValue: condStr) {
                entityManager.removeCondition(cond, from: entity)
            }

        case "remove":
            if let monsterEntity = entity as? GameMonsterEntity {
                monsterEntity.dead = true
            } else if let objectiveEntity = entity as? GameObjectiveEntity {
                objectiveEntity.dead = true
            }

        case "toggleOff", "dormant":
            entity.off = true
            if type == "dormant", let monsterEntity = entity as? GameMonsterEntity {
                monsterEntity.dormant = true
            }

        case "toggleOn", "activate":
            entity.off = false
            if type == "activate", let monsterEntity = entity as? GameMonsterEntity {
                monsterEntity.dormant = false
            }

        case "amAdd":
            // value format: "type:count" e.g. "curse:3", "minus1:3", "bless:2"
            applyAmAdd(value: stringValue(value), to: entity)

        default:
            break
        }
    }

    // MARK: - amAdd helper

    /// Adds attack modifier cards to a character's AM deck, shuffled into the undrawn portion.
    /// value format: "{cardType}:{count}", e.g. "curse:3", "minus1:2".
    /// Non-special cards (e.g. -1) also join the deck's base list so they survive reshuffles;
    /// bless/curse respect the 10-card limit.
    private func applyAmAdd(value: String?, to entity: any Entity) {
        guard let character = entity as? GameCharacter,
              let value = value else { return }

        let parts = value.split(separator: ":", maxSplits: 1)
        let typeName = parts.first.map(String.init) ?? value
        let count = parts.count > 1
            ? (ScenarioExpression.integerValue(String(parts[1]), variables: valueVariables()) ?? 1)
            : 1

        guard let cardType = AttackModifierType(rawValue: typeName), count > 0 else { return }

        // Shuffled into the undrawn part of the deck with real values; scenario -1s persist
        // through reshuffles and Bless/Curse are capped at 10 (AttackModifierDeck.addCard).
        for _ in 0..<min(count, 20) {
            character.attackModifierDeck.addCard(type: cardType)
        }
    }

    // MARK: - Private: Element Rules

    private func applyElementRule(_ elementRule: ElementRuleData) {
        guard let typeName = elementRule.type,
              let stateName = elementRule.state,
              let elementType = ElementType(rawValue: typeName),
              let elementState = ElementState(rawValue: stateName) else { return }

        if let idx = game.elementBoard.firstIndex(where: { $0.type == elementType }) {
            game.elementBoard[idx].state = elementState
        }
    }
}
