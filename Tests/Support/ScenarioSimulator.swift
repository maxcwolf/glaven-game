import XCTest
import SwiftData
@testable import GlavenGameLib

/// Plays a real scenario headlessly through the BoardCoordinator turn loop. A `PlayerPolicy`
/// makes every player decision through the same coordinator calls the UI makes (card selection,
/// rests, hex and target picks, modifier draws, damage negation), while observers check every
/// attack, every movement and the board after each step against the rules: line of sight and
/// range, no enemy attacked twice by one ability, the order of turns, rests, the cards each
/// character holds, and the gold paid for money tokens (`PlayLedger`).
///
/// Seeded runs are fully deterministic, so a transcript (`transcript`) can be compared against a
/// golden file.
@MainActor
final class ScenarioSimulator {

    struct Options {
        var characters: [String] = ["brute", "spellweaver", "cragheart", "scoundrel"]
        var characterLevel = 1
        /// Scenario difficulty (Easy plays at scenario level - 1).
        var difficulty: DifficultyMode = .normal
        /// Seed for every shuffle and random draw; nil keeps the system-seeded generator.
        var seed: UInt64?
        /// Let the coordinator resolve modifier draws, damage negation and push choices itself
        /// instead of the policy answering the prompts.
        var autoResolvePrompts = false
        /// The scenario level the players choose, instead of the recommended one (p.15: "the
        /// scenario level is chosen by the players … any number from 0 to 7").
        var scenarioLevel: Int?
        /// Characters above level 1 bring what their levels gave them (p.44): a card chosen at
        /// each level in their hand, and a perk for each level. Without it they play their
        /// level's hit points with a first-level hand and deck.
        var veterans = false

        /// A party that should win: ninth-level characters with their cards and perks — by
        /// default the Brute, the Sunkeeper and the Berserker, three who fight at close quarters
        /// with plain attacks — playing at scenario level 0. Nothing here is outside the rules:
        /// it is the party a long campaign ends with, on a level its players chose; no hit
        /// points are added and no monster's turn is skipped.
        static func veteranParty(_ characters: [String] = veterans, seed: UInt64, scenarioLevel: Int = 0) -> Options {
            Options(characters: characters, characterLevel: 9, seed: seed, scenarioLevel: scenarioLevel, veterans: true)
        }

        static let veterans = ["brute", "sun", "lightning"]
        /// The same with a Scoundrel, who brings Invisible, Poison and single-target tricks into play.
        static let veteransWithAScoundrel = ["brute", "scoundrel", "sun", "lightning"]
    }

    enum Outcome: String {
        case victory, defeat, unfinished
    }

    let index: String
    let gm: GameManager
    let coord: BoardCoordinator
    var policy: PlayerPolicy

    /// Rule violations found by the attack/move observers and the per-step board checks.
    private(set) var violations: [String] = []
    /// The turn log, with a board summary at the end of every round.
    private(set) var transcript: [String] = []

    /// The checks that need a memory of the round: who has acted, who was attacked by what.
    private let ledger = PlayLedger()
    private var ledgerRound = -1
    /// The figures on the board when the round's first figure acted: anyone else arrived since.
    private var presentAtRoundStart: Set<AnyHashable> = []
    /// Characters whose rest for the round has been looked at ("round-id").
    private var restsChecked: Set<String> = []

    private var logCursor = 0
    private var summarizedRound = -1
    /// The turn already prepared (weak: a new controller can reuse a freed one's address).
    private weak var preparedTurn: PlayerTurnController?
    private var defaultDecided: Set<String> = []

    // MARK: - Setup

    init(scenario index: String, options: Options = Options(), policy: PlayerPolicy? = nil) throws {
        if let seed = options.seed {
            GameRandom.shared = GameRandom(seed: seed)
        }
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        for name in options.characters {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        for character in gm.game.characters where character.level != options.characterLevel {
            gm.characterManager.setLevel(options.characterLevel, for: character)
            character.health = character.maxHealth
        }

        if options.veterans {
            for character in gm.game.characters { Self.giveLevelUps(to: character, gm: gm) }
        }

        gm.game.difficulty = options.difficulty
        if let level = options.scenarioLevel {
            gm.game.levelCalculation = false
            gm.levelManager.setLevel(level)
        }
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil },
                                     "scenario \(index) exists")
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        XCTAssertEqual(coord.boardPhase, .setup, "board started for scenario \(index)")
        coord.boardScene = nil
        coord.autoResolvePrompts = options.autoResolvePrompts
        coord.turnDelayNanoseconds = 0

        self.index = index
        self.gm = gm
        self.coord = coord
        self.policy = policy ?? TacticalPolicy()

        coord.attackObserver = { [unowned self] attacker, target in self.checkAttack(attacker, target) }
        coord.moveObserver = { [unowned self] piece, path, style in self.checkMove(piece, path, style) }

        // Characters go on free starting hexes (allies may stand on some), where the policy wants.
        for character in gm.game.characters where !character.absent {
            let free = coord.freeStartingHexes(for: character.id)
            guard !free.isEmpty else {
                XCTFail("scenario \(index): no free starting hex for \(character.name)")
                break
            }
            coord.placeCharacter(characterID: character.id, at: self.policy.startingHex(for: character, options: free, sim: self))
        }
        coord.finishSetup()
        collectLog()
    }

    /// What a character gained level by level (p.44): at each level a card of that level or
    /// lower — here the highest on offer, the first in card order — and a perk, taken in the
    /// order the perk sheet lists them. The hand is every chosen card, filled up with the
    /// class's first-level and X cards.
    static func giveLevelUps(to character: GameCharacter, gm: GameManager) {
        let manager = gm.characterManager
        while manager.pendingCardChoices(for: character) > 0 {
            let options = manager.choosableCards(for: character)
            guard let best = options.max(by: { a, b in
                let la = CardPool.level(of: a) ?? 0, lb = CardPool.level(of: b) ?? 0
                return la == lb ? (a.cardId ?? 0) > (b.cardId ?? 0) : la < lb
            }), let id = best.cardId, manager.chooseCard(id, for: character) else { break }
        }
        let perks = character.characterData?.perks ?? []
        var index = 0
        while manager.perksAvailable(for: character) > 0, index < perks.count {
            if !manager.takePerk(at: index, for: character) { index += 1 }
        }
        let pool = manager.cardPool(for: character)
        let starting = pool.filter { !character.chosenCards.contains($0.cardId ?? -1) }.compactMap(\.cardId)
        let size = min(character.handSize, pool.count)
        let hand = Array((character.chosenCards + starting).prefix(size))
        if !manager.setHand(hand, for: character) {
            XCTFail("\(character.name): the hand of chosen cards was refused")
        }
    }

    /// Keep playing a scenario that `gm` resumed from a save (it is on the board, in card selection).
    init(resuming gm: GameManager, scenario index: String, policy: PlayerPolicy? = nil) {
        let coord = gm.boardCoordinator
        coord.boardScene = nil
        coord.turnDelayNanoseconds = 0
        self.index = index
        self.gm = gm
        self.coord = coord
        self.policy = policy ?? TacticalPolicy()
        coord.attackObserver = { [unowned self] attacker, target in self.checkAttack(attacker, target) }
        coord.moveObserver = { [unowned self] piece, path, style in self.checkMove(piece, path, style) }
        collectLog()
    }

    // MARK: - Playing

    var result: Outcome {
        switch coord.scenarioResult {
        case .victory: return .victory
        case .defeat: return .defeat
        default: return .unfinished
        }
    }

    /// Play until the scenario ends or `rounds` rounds have been completed.
    /// `eachStep` runs before every step (tests use it to tweak the game).
    @discardableResult
    func play(rounds: Int, eachStep: (() -> Void)? = nil) async -> Outcome {
        var idleSteps = 0
        var lastSignature = ""
        while coord.scenarioResult == nil && !(gm.game.round >= rounds && coord.boardPhase == .cardSelection) {
            let money = moneyOnTheTable()
            let turnBefore = coord.activePlayerTurn
            eachStep?()
            step()
            await settle()
            collectLog()
            checkBoard()
            // Within one character's turn only that character takes money off the board.
            checkMoney(since: money, monstersActing: turnBefore == nil || coord.activePlayerTurn !== turnBefore)

            let signature = progressSignature()
            if signature == lastSignature {
                idleSteps += 1
                if idleSteps > 500 {
                    violations.append("scenario \(index) stalled in round \(gm.game.round): \(signature)")
                    break
                }
            } else {
                idleSteps = 0
                lastSignature = signature
            }
        }
        collectLog()
        if coord.scenarioResult != nil { summarize(final: true) }
        return result
    }

    /// Why the result is not one the rules allow, or nil if it is. A victory needs the scenario's
    /// own goal, or (without one) every enemy dead and every room revealed; a defeat needs the
    /// scenario's failure condition or every character exhausted (GH p.47).
    func outcomeProblem() -> String? {
        let scenario = gm.game.scenario
        switch result {
        case .unfinished:
            return "scenario \(index) did not finish (round \(gm.game.round))"
        case .victory:
            if scenario?.pendingFinish == "won" { return nil }
            // The book's goal for the objectives (destroy the altars, bring the escort home). Met
            // at some moment is enough: the round it was met in is played out, whatever else
            // happens in it (GH p.33).
            if let goal = coord.scenarioData?.placements?.goal, goal.replacesKillAll {
                return goalSeenMet || coord.goalMet(goal) ? nil : "scenario \(index) won without its goal met"
            }
            if scenario?.data.rules?.contains(where: { $0.finish == "won" }) == true {
                return "scenario \(index) won by killing everything, but it has its own goal"
            }
            let alive = gm.game.monsters.filter { !MonsterAI.isAllyFaction($0) && !$0.off && !$0.aliveEntities.isEmpty }
            if !alive.isEmpty { return "scenario \(index) won with \(alive.map(\.name)) still alive" }
            if coord.boardState.doors.contains(where: { !$0.isOpen }) { return "scenario \(index) won with rooms unrevealed" }
            return nil
        case .defeat:
            if scenario?.pendingFinish == "lost" { return nil }
            // What the party was to protect is lost.
            if let goal = coord.scenarioData?.placements?.goal, coord.goalLost(goal) != nil { return nil }
            if case .ruleLost = coord.endReason { return nil }
            let standing = gm.game.characters.filter { !$0.absent && !$0.exhausted }
            return standing.isEmpty ? nil : "scenario \(index) lost with \(standing.map(\.name)) still standing"
        }
    }

    /// Answer whatever the game is waiting for, if anything.
    private func step() {
        if let draw = coord.pendingModifierDraw {
            // As the draw overlay does: one draw, or two for advantage/disadvantage.
            coord.completeModifierDraw(selectedCards: CombatResolver.drawModifiers(
                advantage: draw.advantage, disadvantage: draw.disadvantage, baseAttack: draw.comparedAttack,
                draw: draw.drawCard))
            return
        }
        if coord.pendingTip != nil {
            coord.dismissTip()
            return
        }
        if coord.pendingRecovery != nil {
            coord.resolveRecovery([])
            return
        }
        if coord.pendingInitiativeChange != nil {
            coord.resolveInitiativeChange(0)
            return
        }
        if coord.pendingSufferChoice != nil {
            coord.resolveSufferChoice(0)
            return
        }
        if let pending = coord.pendingAllyChoice {
            coord.resolveAllyChoice(pending.characterIDs.first)
            return
        }
        if coord.pendingItemRefresh != nil {
            coord.resolveItemRefresh([])
            return
        }
        if coord.pendingElementChoice != nil {
            coord.resolveElementChoice([])
            return
        }
        if coord.pendingConditionRemoval != nil {
            coord.resolveConditionRemoval(nil)
            return
        }
        if coord.pendingCardPlay != nil {
            coord.resolveCardPlay([])
            return
        }
        if coord.pendingActionChoice != nil {
            coord.resolveActionChoice(nil)
            return
        }
        if coord.pendingFigureChoice != nil {
            coord.resolveFigureChoice(nil)
            return
        }
        if coord.pendingItemUse != nil {
            // Policies don't spend items, so seeded games play the same with or without them.
            coord.resolvePendingItemUse(false)
            return
        }
        if let pending = coord.pendingDamage,
           let character = character(pending.characterID) {
            // A bonus in play takes it (Frost Armor): no card is lost for that.
            coord.resolvePendingDamage(choice: pending.absorbedBy != nil
                ? .takeDamage : policy.negateDamage(pending.damage, character: character, sim: self))
            return
        }
        if let rest = coord.pendingShortRest, let character = character(rest.characterID) {
            if !rest.committed, let problem = PlayLedger.restProblem(character.name, rest: "short", discards: character.discardedCards.count) {
                violation(problem)
            }
            if !rest.committed {
                switch policy.shortRest(character: character, cardToLose: rest.randomCardId, sim: self) {
                case .skip:
                    coord.skipShortRest()
                case .rest:
                    coord.commitShortRest()
                    coord.resolveShortRest()
                case .restAndRepick:
                    coord.commitShortRest()
                    coord.rerollShortRest()
                    if coord.pendingShortRest != nil { coord.resolveShortRest() }
                }
            } else {
                coord.resolveShortRest()
            }
            return
        }
        if let rest = coord.pendingLongRest, let character = character(rest.characterID) {
            coord.resolveLongRest(characterID: rest.characterID,
                                  discardIndex: policy.longRestLoss(character: character, sim: self))
            return
        }
        if coord.boardPhase == .cardSelection {
            summarize(final: false)
            checkDeclaredRests()
            if let id = coord.cardSelectingCharacterID, let character = character(id) {
                if let pair = policy.chooseCards(for: character, hand: hand(of: character), sim: self) {
                    coord.chooseCards(for: id, leading: pair.leading, other: pair.other)
                } else {
                    coord.chooseLongRest(for: id)
                }
                // Before anyone acts: rests declared, or forced on those who chose after.
                checkDeclaredRests()
            }
            return
        }
        if answerInteraction() { return }

        guard let turn = coord.activePlayerTurn else { return }
        if turn.phase == .turnComplete {
            coord.finishPlayerTurn()
            return
        }
        guard case .idle = coord.interactionMode, !turn.awaitingAsync else { return }
        if preparedTurn !== turn {
            preparedTurn = turn
            defaultDecided = []
            if !turn.hasActed { policy.prepareTurn(turn, sim: self) }
        }
        let half = "\(turn.phase)"
        if turn.currentActionIndex == 0, !defaultDecided.contains(half) {
            defaultDecided.insert(half)
            if policy.useDefaultAction(turn, sim: self) {
                turn.useDefaultAction()
                return
            }
        }
        turn.executeCurrentAction()
    }

    /// Answer a pending hex or figure selection. Returns false if nothing was pending.
    private func answerInteraction() -> Bool {
        switch coord.interactionMode {
        case .selectingMove(let piece, _, let hexes, _, let mode):
            if let hex = policy.moveDestination(for: piece, options: hexes, mode: mode, sim: self) {
                coord.handleHexTap(hex)
            } else {
                coord.activePlayerTurn?.skipRemainingActions()
            }
        case .selectingAttackTarget(let attacker, _, let targets):
            if let target = policy.attackTarget(for: attacker, options: targets, chosen: [], sim: self) {
                coord.handlePieceTap(target)
            } else {
                coord.activePlayerTurn?.skipRemainingActions()
            }
        case .selectingMultiAttackTargets(let attacker, _, let targets, let count, let chosen):
            if chosen.count < count,
               let next = policy.attackTarget(for: attacker, options: targets.subtracting(chosen),
                                              chosen: chosen, sim: self) {
                coord.handlePieceTap(next)
            } else if chosen.isEmpty {
                coord.activePlayerTurn?.skipRemainingActions()
            } else {
                coord.confirmMultiAttack()
            }
        case .selectingConditionTarget(let piece, let condition, let targets):
            if let target = policy.conditionTarget(for: piece, condition: condition, options: targets, sim: self) {
                coord.handlePieceTap(target)
            }
        case .selectingHealTarget(let healer, _, let targets):
            coord.handlePieceTap(policy.healTarget(for: healer, options: targets, sim: self))
        case .choosingPerformer(_, _, let candidates):
            // Policies don't plan for other figures: the first in piece order.
            if let piece = candidates.sorted().first { coord.handlePieceTap(piece) }
        case .placingToken(_, _, _, let hexes):
            // Policies don't plan traps: the first free hex, in map order.
            if let hex = hexes.sorted().first { coord.handleHexTap(hex) }
        case .placingSummon(_, let owner, let hexes):
            if let hex = policy.summonHex(for: owner, options: hexes, sim: self) {
                coord.handleHexTap(hex)
            }
        case .selectingPushPullHex(let target, let origin, let hexes, _, let isPush):
            if let hex = policy.forcedMoveHex(for: target, from: origin, options: hexes, isPush: isPush, sim: self) {
                coord.handleHexTap(hex)
            }
        case .selectingForcedMoveTarget(let piece, _, let isPush, let targets):
            if let target = policy.forcedMoveTarget(for: piece, options: targets, isPush: isPush, sim: self) {
                coord.handlePieceTap(target)
            }
        case .idle, .watchingMonsterTurn, .placingCharacter:
            return false
        }
        return true
    }

    /// Let the turn loop's tasks run (all on the main actor; no wall-clock waits).
    private func settle() async {
        for _ in 0..<4 { await Task.yield() }
    }

    private func progressSignature() -> String {
        let turn = coord.activePlayerTurn.map { "\($0.characterID):\($0.phase):\($0.currentActionIndex):\($0.awaitingAsync)" }
        return [
            "\(gm.game.round)", "\(coord.boardPhase)", "\(coord.currentTurnIndex)", "\(coord.turnLog.count)",
            "\(coord.interactionMode)", turn ?? "-",
            "\(coord.pendingDamage != nil)\(coord.pendingModifierDraw != nil)\(coord.pendingShortRest != nil)\(coord.pendingLongRest != nil)\(coord.pendingItemUse != nil)",
        ].joined(separator: " ")
    }

    // MARK: - Lookups for policies

    func character(_ id: String) -> GameCharacter? {
        gm.game.characters.first { $0.id == id }
    }

    /// The ability cards in a character's hand, in hand order.
    func hand(of character: GameCharacter) -> [AbilityModel] {
        let deck = gm.editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: "gh")
        return character.handCards.compactMap { id in deck.first { $0.cardId == id } }
    }

    func card(_ id: Int, of character: GameCharacter) -> AbilityModel? {
        gm.editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: "gh")
            .first { $0.cardId == id }
    }

    func position(_ piece: PieceID) -> HexCoord? {
        coord.boardState.piecePositions[piece]
    }

    /// Enemies of `piece` on the board that can be targeted (invisible ones excluded), in a fixed order.
    func enemies(of piece: PieceID) -> [PieceID] {
        coord.boardState.piecePositions.keys.sorted().filter { other in
            other != piece && coord.areEnemies(piece, other) && coord.entity(for: other) != nil
                && !(coord.entity(for: other)?.entityConditions.contains { $0.name == .invisible && !$0.expired } ?? false)
        }
    }

    func health(_ piece: PieceID) -> (current: Int, max: Int) {
        guard let entity = coord.entity(for: piece) else { return (0, 0) }
        return (entity.health, entity.maxHealth)
    }

    // MARK: - Transcript

    private func collectLog() {
        while logCursor < coord.turnLog.count {
            let entry = coord.turnLog[logCursor]
            let line = entry.trace.map { "\(entry.message) [\($0)]" } ?? entry.message
            transcript.append(entry.isRoundHeader ? "=== \(entry.message) ===" : line)
            logCursor += 1
        }
    }

    /// A board summary once per round (when card selection starts) and at the end.
    private func summarize(final: Bool) {
        guard final || summarizedRound != gm.game.round else { return }
        summarizedRound = gm.game.round
        collectLog()
        transcript.append(final ? "--- final state (round \(gm.game.round)) ---" : "--- state after round \(gm.game.round) ---")
        transcript.append(contentsOf: stateSummary())
    }

    func stateSummary() -> [String] {
        var lines: [String] = []
        let elements = gm.game.elementBoard.filter { $0.state != .inert }
            .map { "\($0.type.rawValue) \($0.state.rawValue)" }
        lines.append("elements: \(elements.isEmpty ? "none" : elements.joined(separator: ", "))")
        for character in gm.game.characters where !character.absent {
            let where_ = position(.character(character.id)).map { "\($0)" } ?? "off board"
            let status = character.exhausted ? " EXHAUSTED" : ""
            lines.append("\(character.name) \(where_) hp \(character.health)/\(character.maxHealth)"
                + " hand \(character.handCards.count) discard \(character.discardedCards.count)"
                + " lost \(character.lostCards.count) active \(character.activeCards.count)"
                + " xp \(character.experience) gold \(character.loot)\(conditions(character))\(status)")
            for summon in character.summons where !summon.dead {
                let at = position(.summon(id: summon.id)).map { "\($0)" } ?? "off board"
                lines.append("  summon \(summon.name) \(at) hp \(summon.health)/\(summon.maxHealth)\(conditions(summon))")
            }
        }
        for piece in coord.boardState.piecePositions.keys.sorted() {
            guard case .monster(let name, let standee) = piece, let entity = coord.monsterEntity(name: name, standee: standee)
            else { continue }
            lines.append("\(name) #\(standee) \(entity.type.rawValue) \(position(piece)!) hp \(entity.health)/\(entity.maxHealth)\(conditions(entity))")
        }
        let loot = coord.boardState.lootTokens.filter { $0.value > 0 }.sorted { $0.key < $1.key }
        if !loot.isEmpty {
            lines.append("money tokens: " + loot.map { "\($0.key)x\($0.value)" }.joined(separator: " "))
        }
        let doors = coord.boardState.doors
        lines.append("doors open: \(doors.filter(\.isOpen).count)/\(doors.count)")
        return lines
    }

    private func conditions(_ entity: any Entity) -> String {
        let active = entity.entityConditions.filter { !$0.expired }
            .map { $0.value > 1 ? "\($0.name.rawValue) \($0.value)" : $0.name.rawValue }
            .sorted()
        return active.isEmpty ? "" : " [\(active.joined(separator: ", "))]"
    }

    // MARK: - Rule checks

    private func violation(_ message: String) {
        violations.append("scenario \(index) round \(gm.game.round): \(message)")
        collectLog()
        transcript.append("!! VIOLATION: \(message)")
    }

    /// Every attack: both figures on the board, enemies of each other, the target visible, in
    /// line of sight and within the attack's range; no enemy attacked twice by one attack
    /// ability; and the attacker acting at its place in the round (GH p.18–19).
    private func checkAttack(_ attacker: PieceID, _ target: PieceID) {
        // A fallen Cultist attacks from the hex it fell on.
        let fallen = coord.deathAttackInProgress.flatMap { $0.attacker == attacker ? $0.position : nil }
        guard let from = fallen ?? position(attacker), let to = position(target) else {
            violation("\(attacker) attacks \(target), but one of them is not on the board")
            return
        }
        if attacker == target { violation("\(attacker) attacks itself") }
        if coord.isInactive(attacker) { violation("\(attacker) attacks while its kind sits the round out") }
        if !coord.areEnemies(attacker, target) { violation("\(attacker) attacks its ally \(target)") }
        if coord.entity(for: target)?.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) == true {
            violation("\(attacker) attacks invisible \(target)")
        }
        // An attack drawn onto a provoking character lands whatever the range.
        if !coord.attackWasRedirected, !LineOfSight.hasLOS(from: from, to: to, board: coord.boardState) {
            violation("\(attacker) at \(from) attacks \(target) at \(to) without line of sight")
        }
        // Range is never counted through a wall: with no way round, nothing is in range.
        if !coord.attackWasRedirected, coord.boardState.range(from: from, to: to) == nil {
            violation("\(attacker) at \(from) attacks \(target) at \(to), which no range reaches round the walls")
        }
        // The rest is judged for the figure whose turn it is, making its own attack.
        guard fallen == nil, !coord.attackWasRedirected, coord.actingPiece == attacker else { return }
        noteTurn(of: attacker)
        if let reach = reach(of: attacker),
           let problem = PlayLedger.rangeProblem(attacker: attacker, target: target, from: from, to: to, reach: reach) {
            violation(problem)
        }
        if let (ability, allowed) = attackAbility(of: attacker),
           let problem = ledger.noteAttack(ability: ability, target: target, allowed: allowed) {
            violation(problem)
        }
    }

    /// How far the attack being made can reach (GH p.19), read from what prints it: the step of
    /// the character's card (and the range the game announced for it, which may hold a bonus),
    /// a summon's own range, a monster's stat card and ability card. Nil when the attack isn't
    /// one of range: an attack on everyone moved through, a boss's special, an escort's.
    private func reach(of attacker: PieceID) -> Int? {
        switch attacker {
        case .character(let id):
            guard let turn = coord.activePlayerTurn, turn.characterID == id, turn.currentActionIndex < turn.currentSteps.count
            else { return nil }
            let step = turn.currentSteps[turn.currentActionIndex]
            let subs = step.subActions ?? []
            // An attack whose own words say whom it reaches ("all enemies within 2", "every
            // enemy moved through", "a doomed enemy at any range") isn't measured by a range.
            guard step.type == .attack, turn.attackTexts.isEmpty,
                  !subs.contains(where: { $0.type == .custom || $0.type == .specialTarget }) else { return nil }
            let printed = subs.filter { $0.type == .range }.compactMap { $0.value?.intValue }.max() ?? 1
            let range = max(1, printed, turn.currentAttackRange())
            return turn.pendingAreaPattern.map { PlayLedger.areaReach($0, range: range) } ?? range
        case .summon:
            guard let summon = coord.entity(for: attacker) as? GameSummon else { return nil }
            return max(1, summon.range)
        case .monster(let name, let standee):
            guard let monster = gm.game.monsters.first(where: { $0.name == name }), !monster.isBoss,
                  let entity = coord.monsterEntity(name: name, standee: standee), entity.type != .boss,
                  let card = gm.monsterManager.currentAbility(for: monster) else { return nil }
            let statRange = monster.stat(for: entity.type)?.range?.intValue ?? 0
            return PlayLedger.monsterReach(statRange: statRange, card: card.actions ?? [])
        case .objective:
            return nil
        }
    }

    /// The attack ability an attack belongs to, and how often it may attack one enemy (ATK-9):
    /// once for a step of a character's card and for a summon's attack; for a monster once for
    /// each Attack its card prints (each is its own ability, MON-7).
    private func attackAbility(of attacker: PieceID) -> (key: String, allowed: Int)? {
        switch attacker {
        case .character(let id):
            guard let turn = coord.activePlayerTurn, turn.characterID == id else { return nil }
            return ("\(attacker) \(turn.phase) step \(turn.currentActionIndex)", 1)
        case .summon:
            return ("\(attacker)", 1)
        case .monster(let name, let standee):
            guard let monster = gm.game.monsters.first(where: { $0.name == name }), !monster.isBoss,
                  let entity = coord.monsterEntity(name: name, standee: standee),
                  let card = gm.monsterManager.currentAbility(for: monster) else { return nil }
            let statTargets = monster.stat(for: entity.type)?.actions?.first { $0.type == .target }?.value?.intValue ?? 1
            // By the monster itself: its standee number may pass to another within the round.
            return ("\(attacker) \(identity(of: attacker).hashValue)",
                    PlayLedger.attacksOnOneEnemy(card: card.actions ?? [], statTargets: statTargets))
        case .objective:
            return nil
        }
    }

    /// The figure whose turn it is has moved or attacked: its place in the round's order
    /// (RND-6, RND-8), by its own cards.
    private func noteTurn(of piece: PieceID) {
        guard coord.actingPiece == piece else { return }
        let round = gm.game.round
        if round != ledgerRound {
            ledgerRound = round
            presentAtRoundStart = Set(coord.boardState.piecePositions.keys.map(identity(of:)))
        }
        var initiative = 0.0
        var owner: PieceID?
        var summoned = false
        switch piece {
        case .character(let id):
            guard let character = character(id) else { return }
            initiative = PlayLedger.characterInitiative(character.initiative, longRest: character.longRest)
        case .summon:
            guard let summoner = coord.summonOwner(of: piece), let summon = coord.entity(for: piece) as? GameSummon else { return }
            initiative = PlayLedger.summonInitiative(
                ownerInitiative: PlayLedger.characterInitiative(summoner.initiative, longRest: summoner.longRest))
            owner = .character(summoner.id)
            summoned = summon.state == .new
        case .monster(let name, let standee):
            guard let monster = gm.game.monsters.first(where: { $0.name == name }),
                  let card = gm.monsterManager.currentAbility(for: monster) else { return }
            initiative = Double(card.initiative)
            summoned = coord.monsterEntity(name: name, standee: standee)?.summonState == .new
        case .objective:
            return
        }
        let who = identity(of: piece)
        // A boss's special that has its minions act again (GH #9): each gets one more turn,
        // taken when the boss says, not at its initiative.
        while actAgainCursor < coord.turnLog.count {
            if coord.turnLog[actAgainCursor].message.hasSuffix("act again") {
                actAgainRound = round
                lastActor = nil   // whoever acted last starts afresh too
            }
            actAgainCursor += 1
        }
        var outOfOrder = !presentAtRoundStart.contains(who)
        if case .monster = piece, actAgainRound == round {
            // Its own turn and the one the boss gives it, in either order: each time it starts
            // to act, what it did before is set aside.
            if lastActor != who { ledger.anotherTurn(for: piece, identity: who) }
            outOfOrder = true
        }
        lastActor = who
        for problem in ledger.noteAct(round: round, piece: piece, initiative: initiative,
                                      newcomer: outOfOrder, owner: owner,
                                      summonedThisRound: summoned, identity: who) {
            violation(problem)
        }
    }

    private var actAgainCursor = 0
    private var actAgainRound = -1
    private var lastActor: AnyHashable?

    /// The figure behind a piece: a monster's standee number passes to another monster when
    /// the first has died, so a monster is known by its entity.
    private func identity(of piece: PieceID) -> AnyHashable {
        if case .monster(let name, let standee) = piece, let entity = coord.monsterEntity(name: name, standee: standee) {
            // Held on to, so that no later monster can come to live at the same address.
            if knownEntities.insert(ObjectIdentifier(entity)).inserted { heldEntities.append(entity) }
            return AnyHashable(ObjectIdentifier(entity))
        }
        return AnyHashable(piece)
    }

    private var knownEntities: Set<ObjectIdentifier> = []
    private var heldEntities: [GameMonsterEntity] = []

    /// A long rest needs two discards when it is declared (RND-4) — chosen or forced.
    private func checkDeclaredRests() {
        for character in gm.game.characters where character.longRest && !character.exhausted && !character.absent {
            guard restsChecked.insert("\(gm.game.round)-\(coord.boardPhase)-\(character.id)").inserted else { continue }
            if let problem = PlayLedger.restProblem(character.name, rest: "long", discards: character.discardedCards.count) {
                violation(problem)
            }
        }
    }

    // MARK: Money

    private struct Money {
        var gold: [String: Int] = [:]
        var tokens: [HexCoord: Int] = [:]
        /// Money printed on the map (a coin tile is worth its amount in tokens).
        var coins: [HexCoord: Int] = [:]
        /// Numbered treasure tiles, by hex.
        var treasures: [HexCoord: String] = [:]
    }

    private func moneyOnTheTable() -> Money {
        var money = Money()
        for character in gm.game.characters { money.gold[character.id] = character.loot }
        money.tokens = coord.boardState.lootTokens.filter { $0.value > 0 }
        for cell in coord.boardState.cells.values where cell.overlay == .treasure {
            if cell.overlaySubType == "coin" || cell.treasureID == nil {
                money.coins[cell.coord] = max(1, cell.treasureAmount ?? 1)
            } else if let id = cell.treasureID, id != BoardCoordinator.goalTreasureID {
                money.treasures[cell.coord] = id
            }
        }
        return money
    }

    /// Gold per money token by scenario level (GH p.15).
    static let goldPerToken = [2, 2, 3, 3, 4, 4, 5, 6]

    /// Every token that left the board in a step was paid for at the level's rate, and nothing
    /// else was paid (TRN-5, SET-4) — but for the gold a numbered treasure holds.
    private func checkMoney(since before: Money, monstersActing: Bool) {
        guard coord.scenarioResult == nil else { return }
        let now = moneyOnTheTable()
        let gained = now.gold.reduce(0) { $0 + max(0, $1.value - (before.gold[$1.key] ?? $1.value)) }
        var tokensGone = before.tokens.reduce(0) { $0 + max(0, $1.value - (now.tokens[$1.key] ?? 0)) }
        tokensGone += before.coins.filter { now.coins[$0.key] == nil }.values.reduce(0, +)
        var treasureGold = 0
        for (hex, id) in before.treasures where now.treasures[hex] == nil {
            guard let index = Int(id), let reward = gm.editionStore.treasureReward(index: index, edition: "gh") else { continue }
            for part in reward.split(separator: "|") where part.hasPrefix("gold:") {
                treasureGold += Int(part.dropFirst(5)) ?? 0
            }
        }
        guard gained > 0 || tokensGone > 0 else { return }
        let rate = Self.goldPerToken[max(0, min(7, gm.game.level))]
        if let problem = PlayLedger.goldProblem(gained: gained, tokensGone: tokensGone, treasureGold: treasureGold,
                                                rate: rate, monstersActing: monstersActing) {
            violation(problem)
        }
    }

    /// Every movement: starts where the figure stands, steps between adjacent hexes on the map,
    /// never through walls; normal moves avoid obstacles and enemies; figures that can't open
    /// doors never enter a closed one; the move ends on an empty hex (GH p.17).
    private func checkMove(_ piece: PieceID, _ path: [HexCoord], _ style: MovementStyle) {
        let board = coord.boardState
        if style != .forced { noteTurn(of: piece) }
        guard path.first == position(piece) else {
            violation("\(piece) moves from \(path.first.map { "\($0)" } ?? "?") but stands at \(position(piece).map { "\($0)" } ?? "nowhere")")
            return
        }
        // Characters open doors by walking into them, and so does an escort.
        let opensDoors: Bool = {
            if case .character = piece { return true }
            if case .objective = piece { return !coord.isScenery(piece) }
            return false
        }()
        for (a, b) in zip(path, path.dropFirst()) where !board.areAdjacent(a, b) {
            // A character may cross between the two ends of a crossing (Demonic Rift's altars).
            if case .character = piece, style != .forced, board.crossingExits(from: a).contains(b) { continue }
            violation(board.isWalled(a, b) ? "\(piece) moves across the wall line between \(a) and \(b)"
                                           : "\(piece) moves from \(a) to non-adjacent \(b)")
        }
        for (i, hex) in path.enumerated().dropFirst() {
            let isLast = i == path.count - 1
            guard let cell = board.cells[hex], cell.overlay != .wall else {
                violation("\(piece) moves through \(hex), which is off the map or a wall")
                continue
            }
            if !opensDoors && board.isClosedDoor(hex) {
                violation("\(piece) moves through the closed door at \(hex)")
            }
            switch style {
            case .normal, .forced:
                // A flying figure is forced over obstacles and any figure; a walker passes only
                // its allies, as when it moves by itself (FAQ, "Push/Pull").
                let flown = style == .forced && coord.flies(piece)
                if !cell.passable && !flown { violation("\(piece) moves through the obstacle at \(hex) (\(style))") }
                if let other = board.piece(at: hex), other != piece, coord.areEnemies(piece, other), !flown {
                    violation("\(piece) moves through \(other) at \(hex) (\(style))")
                }
            case .jump:
                if isLast && !cell.passable { violation("\(piece) jumps onto the obstacle at \(hex)") }
            case .fly:
                break
            }
            if isLast, let other = board.piece(at: hex), other != piece {
                violation("\(piece) ends its move on \(other) at \(hex)")
            }
        }
    }

    /// Whether the scenario's written goal has held at the end of some step.
    private var goalSeenMet = false

    /// Board consistency after every step.
    private func checkBoard() {
        let board = coord.boardState
        if !goalSeenMet, let goal = coord.scenarioGoal, goal.replacesKillAll, coord.goalMet(goal) { goalSeenMet = true }
        var seen: [HexCoord: PieceID] = [:]
        for (piece, hex) in board.piecePositions.sorted(by: { $0.key < $1.key }) {
            if let other = seen[hex] { violation("\(piece) and \(other) share \(hex)") }
            seen[hex] = piece
            guard let cell = board.cells[hex], cell.overlay != .wall else {
                violation("\(piece) stands off the map at \(hex)")
                continue
            }
            switch piece {
            case .character(let id):
                guard let c = character(id) else { violation("piece for unknown character \(id)"); continue }
                if c.exhausted { violation("exhausted \(c.name) is still on the board") }
                if !cell.passable { violation("\(c.name) stands on an obstacle at \(hex)") }
            case .monster(let name, let standee):
                guard let entity = coord.monsterEntity(name: name, standee: standee), !entity.dead else {
                    let entities = gm.game.monsters.first { $0.name == name }?.entities
                        .map { "#\($0.number)\($0.dead ? " dead" : "")" } ?? []
                    violation("piece \(piece) at \(hex) has no living monster (\(entities.joined(separator: ", ")))"); continue
                }
                let flying = gm.game.monsters.first { $0.name == name }?.monsterData?.flying == true
                if !cell.passable && !flying { violation("\(piece) stands on an obstacle at \(hex)") }
            case .summon:
                guard let summon = coord.entity(for: piece) as? GameSummon, !summon.dead else {
                    violation("piece \(piece) has no living summon"); continue
                }
                if !cell.passable && !summon.flying { violation("\(summon.name) stands on an obstacle at \(hex)") }
            case .objective:
                continue
            }
            if let entity = coord.entity(for: piece) {
                if entity.health > entity.maxHealth { violation("\(piece) has \(entity.health)/\(entity.maxHealth) HP") }
                if entity.health <= 0 { violation("\(piece) is on the board with \(entity.health) HP") }
            }
        }
        // Cards are conserved, and an exhausted character holds none (all are lost, GH p.28).
        for character in gm.game.characters where !character.absent {
            if let problem = PlayLedger.cardProblem(character.name, exhausted: character.exhausted,
                                                    hand: character.handCards.count, discard: character.discardedCards.count,
                                                    lost: character.lostCards.count, active: character.activeCards.count,
                                                    handSize: character.handSize) {
                violation(problem)
            }
        }
        for monster in gm.game.monsters {
            let alive = monster.aliveEntities
            if alive.count > monster.maxCount {
                violation("\(alive.count) \(monster.name) alive, only \(monster.maxCount) standees")
            }
            if Set(alive.map(\.number)).count != alive.count {
                violation("\(monster.name) has duplicate standee numbers")
            }
        }
    }
}

/// How a character handles the end-of-round short rest.
enum ShortRestDecision {
    case skip, rest, restAndRepick
}
