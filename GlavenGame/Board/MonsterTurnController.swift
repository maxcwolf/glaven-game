import Foundation

/// Controls the automated execution of monster turns (GH p.29–31).
///
/// Each monster of a type performs the actions on its type's drawn ability card, in order:
/// elites first, then normals, in ascending standee order.
@Observable
final class MonsterTurnController {

    private weak var coordinator: BoardCoordinator?
    private weak var gameManager: GameManager?
    var isExecuting: Bool = false

    /// The board this turn belongs to; a turn that outlives it (the board left or restarted
    /// while it waited) stops without touching the game.
    private let generation: Int
    private var isStale: Bool { coordinator?.isCurrentBoard(generation) != true }

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
        self.generation = coordinator.boardGeneration
    }

    // MARK: - Group Turn

    /// Execute a monster type's turn. `only` restricts it to specific standees (used when monsters
    /// revealed mid-round must act after their type has already gone).
    @MainActor func executeMonsterGroup(_ monster: GameMonster, only: Set<Int>? = nil) async {
        guard let coordinator, let gameManager else { return }
        guard !monster.off, !monster.aliveEntities.isEmpty,
              !MonsterAI.inactiveMonsters(gameManager.game).contains(monster.name) else { return }
        coordinator.teach(.monstersAct, at: .monsterCard(monster.name))

        guard let ability = gameManager.monsterManager.currentAbility(for: monster) else {
            coordinator.log("\(coordinator.monsterTypeName(monster.name)) has no ability card", category: .info)
            return
        }

        isExecuting = true
        defer { isExecuting = false }
        coordinator.log("\(coordinator.monsterTypeName(monster.name))\u{2019}s turn: \(ability.name ?? "ability card") (\(ability.initiative))", category: .round)

        // Groupings on the card (a grid) are only layout: its abilities, in order.
        let actions = MonsterAbility.flattened(ability.actions ?? [])
        let card = AbilityModel(cardId: ability.cardId, name: ability.name, initiative: ability.initiative, actions: actions)

        // Monsters always consume elements if they can: the first monster to perform the ability
        // a consume belongs to pays for it, and every monster of the type acting after it this
        // turn gains the benefit (p.24, FAQ).
        let payments = ElementPayments()

        let sortedEntities = monster.aliveEntities
            .filter { only?.contains($0.number) ?? true }
            // One still asleep does nothing (Windswept Highlands).
            .filter { !coordinator.isAsleep(.monster(name: monster.name, standee: $0.number)) }
            // Monsters summoned this round don't act until the next round (p.31).
            .filter { $0.summonState != .new }
            .sorted { a, b in
                if a.type != b.type { return a.type == .elite || a.type == .boss }
                return a.number < b.number
            }

        var anyActed = false
        for entity in sortedEntities {
            guard !isStale else { return }
            let pieceID = PieceID.monster(name: monster.name, standee: entity.number)
            // One that comes and goes (the Dark Rider) appears as its turn starts.
            guard !entity.dead, coordinator.appearIfOffMap(pieceID) else { continue }
            coordinator.setActing(pieceID)

            // Start of this monster's turn: its conditions become active and tick (wound).
            gameManager.entityManager.restoreConditions(entity)
            gameManager.entityManager.applyConditionsTurn(entity)
            // Scenario rules that act as a turn starts (the totems of Rebel Swamp).
            gameManager.scenarioRulesManager.evaluateTurnRules(.turnStart, for: entity)
            // Race to the Grave: a doomed monster suffers damage as its turn starts.
            await coordinator.applyDoomTurnStart(pieceID)
            guard !isStale else { return }
            coordinator.sweepDeadFigures()
            guard !entity.dead, coordinator.isOnBoard(pieceID) else { continue }

            if MonsterAI.isActive(.stun, on: entity) {
                coordinator.log("\(coordinator.name(pieceID)) is stunned and loses the turn", category: .condition)
            } else {
                anyActed = true
                var turn = MonsterTurnState()
                if coordinator.march(of: monster.name) != nil {
                    // It marches where the scenario sends it, then does the rest of its card.
                    await coordinator.marchStep(pieceID)
                    guard !isStale else { return }
                    guard !entity.dead, coordinator.isOnBoard(pieceID), coordinator.scenarioResult == nil else { continue }
                    let rest = actions.filter { $0.type != .move }
                    let marching = AbilityModel(cardId: ability.cardId, name: ability.name, initiative: ability.initiative, actions: rest)
                    await executeCard(rest, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: marching, payments: payments, turn: &turn)
                } else {
                    await executeCard(actions, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: card, payments: payments, turn: &turn)
                }
                coordinator.endWhy()
                guard !isStale else { return }
            }
            // End of this monster's turn: conditions that last "until the end of its next turn" expire.
            if !entity.dead {
                gameManager.entityManager.expireConditions(entity)
                coordinator.sufferWaterAtTurnEnd(pieceID)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            await coordinator.beat()
        }

        // Infusions on the card become strong at the end of the type's turn.
        if anyActed && !isStale {
            for element in MonsterAbility.elementInfusions(in: actions, consumed: payments.paid) {
                gameManager.game.infuseElement(element)
                coordinator.log("\(coordinator.monsterTypeName(monster.name)) infuses \(GameText.elementName(element))", category: .element)
            }
        }
    }

    // MARK: - Elements

    /// The elements a monster type has consumed on its turn. A consume is offered once, to the
    /// first monster that performs the ability it is printed with (one printed on its own: the
    /// first to come to it); a monster that doesn't perform the ability consumes nothing (FAQ).
    private final class ElementPayments {
        /// The consumes paid for: every monster of the type acting from then on has them.
        var paid = Set<UUID>()
        /// The consumes a monster has come to, paid or not (the element wasn't there).
        var offered = Set<UUID>()
    }

    /// Consume the elements these consumes ask for, where they are available and not yet offered.
    @MainActor private func pay(_ consumes: [ActionModel], by pieceID: PieceID, into payments: ElementPayments) async {
        guard let coordinator, let game = gameManager?.game else { return }
        for action in consumes where !payments.offered.contains(action.id) {
            payments.offered.insert(action.id)
            // Dampening Ring: a character may consume it first, for nothing.
            if await coordinator.dampenedConsume(MonsterAbility.elements(of: action), by: pieceID) { continue }
            guard !isStale else { return }
            if let used = game.consumeElements(MonsterAbility.elements(of: action)) {
                payments.paid.insert(action.id)
                coordinator.log("\(GameText.list(used.map(GameText.elementName))) consumed", category: .element)
            }
        }
    }

    /// The consumes an ability will have when it is performed now: those paid for, and those
    /// printed with it that are there to be consumed — monsters always consume when they can.
    private func expected(for action: ActionModel?, payments: ElementPayments) -> Set<UUID> {
        guard let action, let game = gameManager?.game else { return payments.paid }
        let open = MonsterAbility.attachedConsumes(of: action).filter {
            !payments.offered.contains($0.id) && game.canConsumeElements(MonsterAbility.elements(of: $0))
        }
        return payments.paid.union(open.map(\.id))
    }

    // MARK: - Single Monster

    /// What a monster has done so far this turn.
    private struct MonsterTurnState {
        var focus: PieceID?
        var focusChosen = false
        var reportedDisarm = false
        /// Hexes moved this turn (the "X" in Dark Rider's attack).
        var hexesMoved = 0
    }

    /// Perform a card's actions, in order, for one monster.
    @MainActor private func executeCard(_ actions: [ActionModel], pieceID: PieceID, entity: GameMonsterEntity,
                             monster: GameMonster, ability: AbilityModel, payments: ElementPayments,
                             turn state: inout MonsterTurnState) async {
        guard let coordinator, let gameManager else { return }
        let game = gameManager.game
        let actions = MonsterAbility.flattened(actions)
        let stat = monster.attackStat(for: entity.type)
        let characterCount = game.characterCount
        let baseRange = stat?.rangeValue(characterCount: characterCount, level: monster.level) ?? 0
        func baseAttack() -> Int {
            stat?.attackValue(characterCount: characterCount, level: monster.level,
                              variables: MonsterAI.attackVariables(for: monster, gameState: game,
                                                                   hexesMoved: state.hexesMoved)) ?? 0
        }

        func currentTurn() -> MonsterTurnResult {
            // It plans with the attack it will make: an element its attack consumes counts, though
            // it is consumed only as the attack is made (never by a disarmed monster).
            let attack = MonsterAI.isActive(.disarm, on: entity) ? nil
                : MonsterAbility.flattened(ability.actions ?? []).first { $0.type == .attack }
            return MonsterAI.computeTurn(pieceID: pieceID, monster: monster, entity: entity, ability: ability,
                                         board: coordinator.boardState, gameState: game,
                                         consumed: expected(for: attack, payments: payments))
        }
        func stillHere() -> Bool { !isStale && !entity.dead && coordinator.isOnBoard(pieceID) }

        // Focus is chosen before performing any action (p.30).
        if !state.focusChosen {
            state.focusChosen = true
            let plan = currentTurn()
            state.focus = plan.focusTarget
            // What it weighed, for "Why?" on the lines it logs.
            coordinator.beginWhy(for: pieceID, candidates: plan.focusCandidates, ranged: plan.attack?.isRanged ?? false)
            if state.focus == nil && (MonsterAbility.hasAttack(actions) || actions.contains { $0.type == .move }) {
                coordinator.log("\(coordinator.name(pieceID)) finds no enemy to focus on", category: .info)
            }
        }

        for action in actions {
            guard stillHere(), coordinator.scenarioResult == nil else { return }
            // Stunned in the middle of its turn (a Stun trap on its way): no more abilities (p.22).
            if MonsterAI.isActive(.stun, on: entity) { return }

            switch action.type {
            case .move:
                guard state.focus != nil else { continue }
                if MonsterAI.isActive(.immobilize, on: entity) {
                    coordinator.log("\(coordinator.name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
                    continue
                }
                let plan = currentTurn()
                if let newFocus = plan.focusTarget { state.focus = newFocus }
                if plan.movementPath.count > 1 {
                    let steps = plan.movementPath.count - 1
                    coordinator.log("\(coordinator.name(pieceID)) moves \(steps) hex\(steps == 1 ? "" : "es")",
                                    category: .move, trace: "to \(plan.movementPath.last!)")
                    let style: MovementStyle = monster.monsterData?.flying == true ? .fly : (plan.jumping ? .jump : .normal)
                    coordinator.noteWhyMove(steps)
                    await coordinator.moveAlong(pieceID, path: plan.movementPath, style: style)
                    state.hexesMoved += plan.movementPath.count - 1
                    if MonsterAI.isActive(.stun, on: entity) { continue }
                }
                // Text printed with the move happens whether or not it moved.
                if !isStale { await performPrintedText(texts(in: action, monster: monster), pieceID: pieceID) }

            case .attack:
                if MonsterAI.isActive(.disarm, on: entity) {
                    if !state.reportedDisarm {
                        coordinator.log("\(coordinator.name(pieceID)) is disarmed and can\u{2019}t attack", category: .condition)
                        state.reportedDisarm = true
                    }
                    continue
                }
                // Re-find the focus if it died or left the board since the last action.
                if state.focus == nil || !coordinator.isOnBoard(state.focus!) { state.focus = currentTurn().focusTarget }
                guard let target = state.focus,
                      let position = coordinator.boardState.piecePositions[pieceID],
                      let focusPos = coordinator.boardState.piecePositions[target] else { continue }
                let enemies = MonsterAI.gatherEnemies(board: coordinator.boardState, monster: monster, gameState: game)
                func resolved(_ consumed: Set<UUID>) -> (spec: MonsterAttackSpec, targets: [PieceID]) {
                    let spec = MonsterAbility.attack(action, stat: stat, baseAttack: baseAttack(),
                                                     baseRange: baseRange, consumed: consumed)
                        .reduced(by: entity.doomPenalty)
                    return (spec, MonsterAI.targets(for: spec, from: position, focus: target, focusPos: focusPos,
                                                    enemies: enemies, board: coordinator.boardState, gameState: game))
                }
                // An attack it can't make consumes nothing (FAQ): the elements printed with the
                // attack are paid for once it has someone to attack.
                var (spec, targets) = resolved(expected(for: action, payments: payments))
                if !targets.isEmpty {
                    await pay(MonsterAbility.attachedConsumes(of: action), by: pieceID, into: payments)
                    guard stillHere() else { return }
                    (spec, targets) = resolved(payments.paid)
                }
                if targets.isEmpty {
                    coordinator.log("\(coordinator.name(pieceID)) can\u{2019}t reach its focus", category: .move)
                    continue
                }
                let printed = texts(in: action, monster: monster)
                // Text inside a paid element consume (the Harrower's "Heal 2, self for each target damaged").
                let paid = (action.subActions ?? []).filter { MonsterAbility.isConsume($0) && payments.paid.contains($0.id) }
                    .flatMap { texts(in: $0, monster: monster) }
                var damaged = 0
                for victim in targets {
                    guard stillHere(), coordinator.scenarioResult == nil else { return }
                    let victimHex = coordinator.boardState.piecePositions[victim]
                    let healthBefore = coordinator.entity(for: victim)?.health ?? 0
                    await coordinator.performAttack(
                        attacker: pieceID, target: victim,
                        attack: AttackParameters(value: spec.value + bonus(printed, against: victim, pieceID: pieceID)
                                                     + roundAttackBonus(of: entity),
                                                 isRanged: spec.isRanged, pierce: spec.pierce,
                                                 conditions: spec.conditions, push: spec.push, pull: spec.pull,
                                                 advantage: spec.advantage, range: max(1, spec.range)))
                    guard !isStale else { return }
                    coordinator.noteWhyAttack(on: victim)
                    if (coordinator.entity(for: victim)?.health ?? 0) < healthBefore || !coordinator.isOnBoard(victim) { damaged += 1 }
                    // Savvas Lavaflow: "All allies and enemies adjacent to the target suffer 2 damage."
                    for text in printed where text.contains("adjacent to the target suffer") {
                        await coordinator.printedDamage(text, amount: PlayerTurnController.damageAmount(in: text), by: pieceID,
                                                  around: victimHex)
                    }
                }
                for text in paid where text.contains("for each target damaged") && damaged > 0 && stillHere() {
                    let amount = (text.firstMatch(of: #/heal (\d+)/#).flatMap { Int($0.1) } ?? 0) * damaged
                    let healed = coordinator.heal(pieceID, amount: amount, source: pieceID)
                    coordinator.log("\(coordinator.name(pieceID)) heals for \(healed)", category: .heal)
                }
                if stillHere() { await performPrintedText(printed.filter { !$0.contains("adjacent to the target") }, pieceID: pieceID) }
                // The Dark Rider is gone the moment it has made a melee attack.
                if !spec.isRanged, stillHere() { coordinator.leaveAfterMeleeAttack(pieceID) }
                // Deep Terror: "Summon a Deep Terror in a hex adjacent to the target."
                for summon in (action.subActions ?? []) where summon.type == .summon {
                    guard let near = targets.first(where: { coordinator.isOnBoard($0) }) ?? (stillHere() ? pieceID : nil) else { continue }
                    performSummon(summon, pieceID: near, summoner: entity, monster: monster)
                }

            case .heal:
                await pay(MonsterAbility.attachedConsumes(of: action), by: pieceID, into: payments)
                guard stillHere() else { return }
                performHeal(action, pieceID: pieceID, entity: entity, monster: monster, consumed: payments.paid)

            case .teleport:
                // The Gloom: to the next marked hex, from where it looks for its focus anew.
                await coordinator.jumpAlongCycle(pieceID)
                guard stillHere() else { return }
                state.focus = currentTurn().focusTarget

            case .condition, .push, .pull, .concatenation:
                await performTargetedEffect(action, pieceID: pieceID, monster: monster, baseRange: baseRange,
                                            focus: state.focus, payments: payments)

            case .element where MonsterAbility.isConsume(action):
                // An element-consume block with its own effects ("Ice: Heal 3", "Earth: Immobilize
                // all enemies within range 3", "Fire: Retaliate 3"…), consumed by the first monster
                // to come to it. Infusions inside it happen with the type's other infusions after
                // its turn.
                await pay([action], by: pieceID, into: payments)
                guard stillHere() else { return }
                guard payments.paid.contains(action.id) else { continue }
                let block = (action.subActions ?? []).filter { $0.type != .element }
                if block.contains(where: { $0.type == .specialTarget }) {
                    await performTargetedEffect(ActionModel(type: .concatenation, subActions: block),
                                                pieceID: pieceID, monster: monster, baseRange: baseRange,
                                                focus: state.focus, payments: payments)
                    let others = block.filter { ![.condition, .push, .pull, .specialTarget].contains($0.type) }
                    await executeCard(others, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: ability, payments: payments, turn: &state)
                } else {
                    await executeCard(block, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: ability, payments: payments, turn: &state)
                }

            case .sufferDamage, .suffer:
                let amount = action.value?.intValue ?? 0
                coordinator.log("\(coordinator.name(pieceID)) suffers \(amount) damage", category: .damage)
                coordinator.sufferDamage(amount, to: pieceID)

            case .loot:
                performLoot(range: action.value?.intValue ?? 1, pieceID: pieceID)

            case .summon:
                performSummon(action, pieceID: pieceID, summoner: entity, monster: monster)

            case .shield, .retaliate:
                // A Shield or Retaliate on the card (or in a boss special) is gained as the monster
                // performs it, and lasts until the end of the round (FAQ). A paid element inside
                // adds to it, or replaces it ("Shield 2 instead", the Lurker).
                await pay(MonsterAbility.attachedConsumes(of: action), by: pieceID, into: payments)
                guard stillHere() else { return }
                var value = action.value?.intValue ?? 0
                for paid in (action.subActions ?? []) where MonsterAbility.isConsume(paid) && payments.paid.contains(paid.id) {
                    for reward in paid.subActions ?? [] where reward.type == action.type {
                        value = isInstead(reward) ? (reward.value?.intValue ?? 0) : value + (reward.value?.intValue ?? 0)
                    }
                }
                guard value > 0 else { continue }
                // Its range (Retaliate 2, Range 3) stays with it.
                let bonus = ActionModel(type: action.type, value: .int(value),
                                        subActions: action.subActions?.filter { $0.type == .range })
                // "Shield 1, affect self and all allies within Range 2" (Savvas Icestorm).
                let spec = action.subActions?.first { $0.type == .specialTarget }?.value?.stringValue
                for figure in figures(for: spec, from: pieceID, monster: monster, baseRange: baseRange, focus: state.focus)
                where coordinator.isOnBoard(figure) {
                    guard let gaining = coordinator.entity(for: figure) else { continue }
                    applyRoundBonus(bonus, to: gaining)
                    coordinator.log("\(coordinator.name(figure)) gains \(action.type == .shield ? "Shield" : "Retaliate") \(value) this round",
                                    category: .condition)
                }

            case .custom where action.value?.stringValue.contains("ondeath") == true:
                // "On death: …" (Cultists) is made when the monster dies, not on its turn.
                continue

            case .custom:
                // Text printed as its own line ("All enemies suffer 2 damage"), and what it wraps.
                await performPrintedText(texts(in: ActionModel(type: .concatenation, subActions: [action]), monster: monster), pieceID: pieceID)
                let wrapped = (action.subActions ?? []).filter { $0.type != .custom }
                if !wrapped.isEmpty {
                    await executeCard(wrapped, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: ability, payments: payments, turn: &state)
                }

            case .special:
                // Boss special abilities: run the structured actions as if they were the card
                // (so their Move/Attack drive focus and movement); scenario-specific text must be
                // resolved by the players.
                let index = (action.value?.intValue ?? 1) - 1
                // The scenario may print its own in place of the stat card's.
                guard let special = coordinator.scenarioData?.placements?.specials?[monster.name] ?? stat?.special,
                      index >= 0, index < special.count else { continue }
                coordinator.log("\(coordinator.name(pieceID)) uses special ability \(index + 1)", category: .info)
                let specialTexts = texts(in: ActionModel(type: .concatenation, subActions: special[index]), monster: monster)
                var unresolved = false
                var hatches = false, lays = false
                for text in specialTexts {
                    if text.contains("move to next door and reveal room") {
                        // Barrow Lair's doors are jumped to, in order, however far away.
                        if await !coordinator.jumpToNextDoor(pieceID) {
                            await moveToNextDoor(pieceID: pieceID, entity: entity, monster: monster)
                        }
                    } else if text.contains("all allies add") && text.contains("attack") && text.contains("this round") {
                        // Captain of the Guard: "All allies add +1 Attack to all attacks this round."
                        // His allies: not himself, and not the monsters fighting him.
                        let extra = text.firstMatch(of: #/\+(\d+) attack/#).flatMap { Int($0.1) } ?? 1
                        for ally in coordinator.boardState.piecePositions.keys.sorted()
                        where ally != pieceID && coordinator.areAllies(pieceID, ally) {
                            guard case .monster = ally, let gaining = coordinator.entity(for: ally) else { continue }
                            gaining.tags.append("\(MonsterAbility.roundAttackTag)\(extra)")
                        }
                        coordinator.log("\(coordinator.name(pieceID))\u{2019}s allies add +\(extra) Attack to their attacks this round",
                                        category: .attack)
                    } else if text.contains("scouts act again") {
                        // Merciless Overseer: every Vermling Scout takes another turn.
                        if let scouts = gameManager.game.monsters.first(where: { $0.name.contains("scout") }), scouts !== monster {
                            coordinator.log("The Vermling Scouts act again", category: .round)
                            await executeMonsterGroup(scouts)
                        }
                    } else if text.contains("hatch eggs") {
                        hatches = true   // the Winged Horror, once it has attacked
                    } else if text.hasSuffix("eggs") {
                        lays = true
                    } else {
                        unresolved = true
                    }
                }
                if unresolved {
                    coordinator.log("Resolve the boss\u{2019}s special ability \(index + 1) as printed on its stat card",
                                    category: .info)
                }
                let specialActions = MonsterAbility.flattened(special[index].filter { $0.type != .custom })
                let specialCard = AbilityModel(cardId: ability.cardId, name: ability.name,
                                               initiative: ability.initiative, actions: specialActions)
                var specialState = MonsterTurnState(hexesMoved: state.hexesMoved)
                // What the special pays for with an element (the Colorless: Dark for a Night
                // Demon) is consumed as it comes to it.
                await executeCard(specialActions, pieceID: pieceID, entity: entity, monster: monster,
                                  ability: specialCard, payments: payments, turn: &specialState)
                state.hexesMoved = specialState.hexesMoved
                if hatches, !isStale { coordinator.hatchEggs() }
                if lays, stillHere() { coordinator.layEggs(by: pieceID, count: characterCount) }

            default:
                // Element infusions happen after the type's turn; a hint is a note for the players.
                // Anything else is an ability this turn doesn't know: say so rather than skip it.
                if !MonsterAbility.performedKinds.contains(action.type) {
                    coordinator.log("\(coordinator.name(pieceID)): resolve \u{201C}\(action.type.rawValue)\u{201D} as printed on its card",
                                    category: .info)
                }
            }
        }
    }

    /// "+1 Attack to all attacks this round", given by an ally's ability (the Captain of the Guard).
    private func roundAttackBonus(of entity: any Entity) -> Int {
        entity.tags.reduce(0) { total, tag in
            tag.hasPrefix(MonsterAbility.roundAttackTag) ? total + (Int(tag.dropFirst(MonsterAbility.roundAttackTag.count)) ?? 0) : total
        }
    }

    /// A consume's reward printed "instead" of the ability's own value ("Ice: Shield 2 instead").
    private func isInstead(_ reward: ActionModel) -> Bool {
        reward.subActions?.contains { $0.value?.stringValue.contains("instead") == true } == true
    }

    /// Bandit Commander: "Move to next door and reveal room": toward the nearest closed door, with
    /// its Move, opening the door if it gets there.
    @MainActor private func moveToNextDoor(pieceID: PieceID, entity: GameMonsterEntity, monster: GameMonster) async {
        guard let coordinator, let game = gameManager?.game, let start = coordinator.boardState.piecePositions[pieceID] else { return }
        if MonsterAI.isActive(.immobilize, on: entity) {
            coordinator.log("\(coordinator.name(pieceID)) is immobilized and can\u{2019}t move", category: .condition)
            return
        }
        let characterCount = game.characterCount
        let movement = monster.stat(for: entity.type)?.movementValue(characterCount: characterCount, level: monster.level) ?? 0
        let (enemies, allies) = coordinator.movementSets(for: pieceID)
        let paths = coordinator.boardState.doors.filter { !$0.isOpen }.compactMap { door in
            // It opens the doors no one else can (Barrow Lair's are locked to the party).
            Pathfinder.findPath(board: coordinator.boardState, from: start, to: door.coord, avoidTraps: true, canOpenDoors: true,
                                occupiedByEnemy: enemies, occupiedByAlly: allies, opensLockedDoors: true)
        }
        let board = coordinator.boardState
        // The nearest door by movement (difficult terrain costs 2), not by hexes.
        guard let path = paths.min(by: { Pathfinder.movementCost(of: $0, board: board) < Pathfinder.movementCost(of: $1, board: board) }),
              path.count > 1 else {
            coordinator.log("\(coordinator.name(pieceID)) has no door to reach", category: .move)
            return
        }
        // Up to the first closed door on the way: it opens as the Commander reaches it.
        let doorIndex = path.firstIndex { hex in coordinator.boardState.doors.contains { $0.coord == hex && !$0.isOpen } } ?? path.count - 1
        // How far along the path its Move takes it.
        let reach = (0...doorIndex).last { Pathfinder.movementCost(of: Array(path.prefix($0 + 1)), board: board) <= movement } ?? 0
        coordinator.log("\(coordinator.name(pieceID)) heads for the door", category: .move)
        // It may pass allies, but must stop on a free hex.
        func lastFree(upTo index: Int) -> Int {
            var i = index
            while i > 0 && coordinator.boardState.isOccupied(path[i]) { i -= 1 }
            return i
        }
        if reach >= doorIndex && lastFree(upTo: doorIndex - 1) == doorIndex - 1 {
            if doorIndex > 1 { await coordinator.moveAlong(pieceID, path: Array(path.prefix(doorIndex)), style: .normal) }
            guard !isStale else { return }
            coordinator.openDoor(at: path[doorIndex])
            // The room it reveals may put a figure in the doorway.
            if !coordinator.boardState.isOccupied(path[doorIndex]),
               coordinator.boardState.piecePositions[pieceID] == path[doorIndex - 1] {
                await coordinator.moveAlong(pieceID, path: [path[doorIndex - 1], path[doorIndex]], style: .normal)
            }
        } else {
            let stop = lastFree(upTo: min(reach, doorIndex - 1))
            if stop > 0 { await coordinator.moveAlong(pieceID, path: Array(path.prefix(stop + 1)), style: .normal) }
        }
    }

    // MARK: - Printed text

    /// The text printed in an action (its custom lines), resolved and lowercased.
    private func texts(in action: ActionModel, monster: GameMonster) -> [String] {
        guard let store = gameManager?.editionStore else { return [] }
        return (action.subActions ?? []).filter { $0.type == .custom }.compactMap { $0.value?.stringValue }
            .compactMap { store.resolveCustomText($0, edition: monster.edition) }.map { $0.lowercased() }
    }

    /// "+2 Attack if the target is adjacent to any of the Hound's allies" (Hound, Giant Viper).
    private func bonus(_ texts: [String], against target: PieceID, pieceID: PieceID) -> Int {
        guard let coordinator, let hex = coordinator.boardState.piecePositions[target] else { return 0 }
        var extra = 0
        for text in texts where text.contains("if the target is adjacent to any of") {
            let flanked = coordinator.boardState.neighbors(of: hex).compactMap { coordinator.boardState.piece(at: $0) }
                .contains { $0 != pieceID && $0 != target && coordinator.areAllies(pieceID, $0) }
            if flanked { extra += text.firstMatch(of: #/\+(\d+) attack/#).flatMap { Int($0.1) } ?? 0 }
        }
        return extra
    }

    /// What a monster's printed text does, after its attack or move: damage around it ("All
    /// adjacent enemies suffer 2 damage"), a trap ("Create a 3 damage trap in an adjacent empty
    /// hex closest to an enemy"), disadvantage against it this round (Giant Viper).
    @MainActor private func performPrintedText(_ texts: [String], pieceID: PieceID) async {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID] else { return }
        for text in texts {
            if text.contains("trap in an adjacent empty hex") {
                let enemies = coordinator.boardState.piecePositions.filter { coordinator.areEnemies(pieceID, $0.key) }.map(\.value)
                let hexes = coordinator.boardState.neighbors(of: position).filter(coordinator.isEmptyHex)
                guard let hex = hexes.min(by: { a, b in
                    let board = coordinator.boardState
                    let da = enemies.map { board.range(from: a, to: $0) ?? 99 }.min() ?? 99, db = enemies.map { board.range(from: b, to: $0) ?? 99 }.min() ?? 99
                    return da == db ? a < b : da < db
                }) else { continue }
                coordinator.placeTrap(damage: PlayerTurnController.damageAmount(in: text), at: hex, by: pieceID)
            } else if text.contains("attacks targeting") && text.contains("disadvantage") {
                coordinator.disadvantagedThisRound.insert(pieceID)
                coordinator.log("Attacks on \(coordinator.name(pieceID)) have disadvantage this round", category: .condition)
            } else if text.contains("suffer") && text.contains("damage") {
                let amount = PlayerTurnController.damageAmount(in: text)
                if text.contains("all enemies suffer") {
                    for enemy in coordinator.boardState.piecePositions.keys.filter({ coordinator.areEnemies(pieceID, $0) }).sorted()
                    where coordinator.isOnBoard(enemy) && !isStale {
                        coordinator.log("\(coordinator.name(enemy)) suffers \(amount) damage", category: .damage)
                        await coordinator.sufferDamageWithMitigation(amount, to: enemy, source: coordinator.name(pieceID),
                                                                     killer: pieceID)
                    }
                } else {
                    await coordinator.printedDamage(text, amount: amount, by: pieceID, around: position)
                }
            }
        }
    }

    /// A shield/retaliate gained on a turn (the card's own, a consumed element's, an ally's
    /// "affect all allies") lasts until the end of the round. Several add.
    private func applyRoundBonus(_ action: ActionModel, to entity: any Entity) {
        if action.type == .shield {
            let total = (entity.shield?.value?.intValue ?? 0) + (action.value?.intValue ?? 0)
            entity.shield = ActionModel(type: .shield, value: .int(total))
        } else {
            entity.retaliate.append(action)
        }
    }

    // MARK: - Non-attack actions

    /// Heal X: the monster heals itself or an ally within range, whichever has lost the most HP
    /// (p.31) — or everyone the card names: "affect all adjacent allies" (the Shamans), "affect
    /// self and all allies" (the Captain of the Guard), and with a consumed element "all allies
    /// within range instead" (Sun Demon) or "Target 3" (Savvas Lavaflow).
    private func performHeal(_ action: ActionModel, pieceID: PieceID, entity: GameMonsterEntity,
                             monster: GameMonster, consumed: Set<UUID>) {
        guard let coordinator else { return }
        var amount = action.value?.intValue ?? 0
        var range: Int?
        var spec: String?
        var count = 1
        func read(_ subs: [ActionModel]) {
            for sub in subs {
                switch sub.type {
                case .range: range = sub.value?.intValue
                case .specialTarget: spec = sub.value?.stringValue
                case .target: count = max(count, sub.value?.intValue ?? 1)
                case .heal: amount += MonsterAbility.signedValue(sub)
                case .element where consumed.contains(sub.id): read(sub.subActions ?? [])
                default: break
                }
            }
        }
        read(action.subActions ?? [])

        func lost(_ piece: PieceID) -> Int { coordinator.entity(for: piece).map { $0.maxHealth - $0.health } ?? 0 }
        let targets: [PieceID]
        if let spec, MonsterAbility.affected(by: spec, baseRange: range ?? 1).side != nil {
            // Everyone the card names.
            targets = figures(for: spec, from: pieceID, monster: monster, baseRange: range ?? 1, focus: nil)
                .filter { $0 == pieceID || isMonster($0) }
        } else if let range, spec == nil {
            // Itself or allies within range: those who have lost the most, one unless "Target N".
            let within = [pieceID] + figures(for: "alliesRange:\(range)", from: pieceID, monster: monster,
                                             baseRange: range, focus: nil).filter(isMonster)
            // (Stable: of two as badly hurt, the monster itself, then the lower piece.)
            let worst = within.enumerated().sorted { a, b in
                lost(a.element) != lost(b.element) ? lost(a.element) > lost(b.element) : a.offset < b.offset
            }.map(\.element)
            targets = Array(worst.prefix(count))
        } else {
            targets = [pieceID]
        }
        for target in targets where coordinator.isOnBoard(target) {
            let healed = coordinator.heal(target, amount: amount, source: pieceID)
            coordinator.log(coordinator.healLine(pieceID, healed: target, for: healed),
                            category: .heal, trace: "Heal \(amount)")
        }
    }

    private func isMonster(_ piece: PieceID) -> Bool {
        if case .monster = piece { return true }
        return false
    }

    /// Conditions, push or pull applied to the figures named by a `specialTarget`
    /// (self, adjacent enemies, enemies within range N, allies within range N…). With no one to
    /// affect the ability isn't performed, and an element printed with it isn't consumed.
    @MainActor private func performTargetedEffect(_ action: ActionModel, pieceID: PieceID, monster: GameMonster,
                                       baseRange: Int, focus: PieceID?, payments: ElementPayments) async {
        guard let coordinator else { return }
        let parts = action.type == .concatenation ? (action.subActions ?? []) : [action] + (action.subActions ?? [])
        let spec = parts.first { $0.type == .specialTarget }?.value?.stringValue
        let targets = figures(for: spec, from: pieceID, monster: monster, baseRange: baseRange, focus: focus)
        guard !targets.isEmpty else { return }
        await pay(parts.flatMap(MonsterAbility.attachedConsumes) + parts.filter(MonsterAbility.isConsume),
                  by: pieceID, into: payments)
        guard !isStale else { return }
        // What a paid element gives a part: more of it, or another value instead ("Air: Push 4 instead").
        let rewards = parts.filter { MonsterAbility.isConsume($0) && payments.paid.contains($0.id) }.flatMap { $0.subActions ?? [] }

        for part in parts {
            switch part.type {
            case .condition:
                guard let name = part.value?.stringValue, let condition = ConditionName(rawValue: name) else { continue }
                for target in targets where coordinator.isOnBoard(target) {
                    coordinator.applyCondition(condition, to: target)
                }
            case .push, .pull:
                var steps = part.value?.intValue ?? 0
                for reward in rewards where reward.type == part.type {
                    steps = isInstead(reward) ? (reward.value?.intValue ?? 0) : steps + (reward.value?.intValue ?? 0)
                }
                guard steps > 0, let origin = coordinator.boardState.piecePositions[pieceID] else { continue }
                for target in targets where target != pieceID && coordinator.isOnBoard(target) && !isStale {
                    await coordinator.performPushPull(target: target, attackerPos: origin, steps: steps,
                                                      isPush: part.type == .push)
                }
            default:
                break
            }
        }
    }

    /// Resolve a `specialTarget` value to the affected figures.
    /// - Parameter focus: the monster's focus: "one adjacent enemy" is the focus when it is adjacent.
    private func figures(for spec: String?, from pieceID: PieceID, monster: GameMonster, baseRange: Int,
                         focus: PieceID?) -> [PieceID] {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID],
              let game = gameManager?.game else { return [] }
        let named = MonsterAbility.affected(by: spec, baseRange: baseRange)
        var result: [PieceID] = named.includesSelf ? [pieceID] : []
        guard let side = named.side else { return result }

        // "All enemies", with no range, is no targeting: it reaches the invisible too.
        let pool: [PieceID] = side == .enemies
            ? MonsterAI.gatherEnemies(board: coordinator.boardState, monster: monster, gameState: game,
                                      includeInvisible: named.range == nil)
            : coordinator.boardState.piecePositions.keys.sorted().filter {
                $0 != pieceID && coordinator.areAllies(pieceID, $0)
            }
        var others = pool
        if let range = named.range {
            others = pool.filter { id in
                guard let coord = coordinator.boardState.piecePositions[id] else { return false }
                return coordinator.boardState.isWithin(range, from: position, to: coord)
                    && LineOfSight.hasLOS(from: position, to: coord, board: coordinator.boardState)
            }
        }
        if named.onlyOne {
            // The focus if it is one of them; otherwise as a focus is chosen among them: all as
            // near, so the one acting first (p.30).
            if let focus, others.contains(focus) {
                others = [focus]
            } else {
                others = Array(others.sorted {
                    MonsterAI.enemyInitiative($0, gameState: game) < MonsterAI.enemyInitiative($1, gameState: game)
                }.prefix(1))
            }
        }
        result += others
        return result
    }

    /// Monster loot: pick up every money token within range and line of sight; those tokens are
    /// lost (p.31).
    private func performLoot(range: Int, pieceID: PieceID) {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID] else { return }
        var taken = 0
        for coord in coordinator.boardState.lootTokens.keys.sorted()
        where coordinator.boardState.isWithin(range, from: position, to: coord) && LineOfSight.hasLOS(from: position, to: coord, board: coordinator.boardState) {
            taken += coordinator.boardState.takeLoot(at: coord)
            coordinator.boardScene?.removeLootSprite(at: coord, offsetCol: coordinator.offsetCol,
                                                     offsetRow: coordinator.offsetRow)
        }
        if taken > 0 {
            coordinator.log("\(coordinator.name(pieceID)) loots \(taken) money token\(taken == 1 ? "" : "s")", category: .loot)
        }
    }

    /// Monster summon: place the summoned monster in an empty adjacent hex, as close to an enemy
    /// as possible. It doesn't act this round and drops no money token (p.31).
    private func performSummon(_ action: ActionModel, pieceID: PieceID, summoner: GameMonsterEntity, monster: GameMonster) {
        guard let coordinator, let game = gameManager?.game,
              let specs = action.monsterSummons else { return }
        let characterCount = game.characterCount
        for spec in specs {
          for type in spec.summoned(forPlayerCount: characterCount) {
            let before = Set(game.monsters.first { $0.name == spec.name }?.aliveEntities.map(\.number) ?? [])
            if !coordinator.summonMonster(name: spec.name, type: type, near: pieceID) {
                coordinator.log("\(coordinator.name(pieceID)) can\u{2019}t summon \(coordinator.monsterTypeName(spec.name)): no room", category: .info)
                continue
            }
            // The Ooze splits: "with H equal to the summoning Ooze's current hit point value
            // (limited by a normal Ooze's maximum)".
            if spec.health?.stringValue == "H",
               let summoned = game.monsters.first(where: { $0.name == spec.name })?.aliveEntities
                .first(where: { !before.contains($0.number) }) {
                summoned.health = min(summoner.health, summoned.maxHealth)
            }
          }
        }
    }
}
