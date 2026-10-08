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

    init(coordinator: BoardCoordinator, gameManager: GameManager) {
        self.coordinator = coordinator
        self.gameManager = gameManager
    }

    // MARK: - Group Turn

    /// Execute a monster type's turn. `only` restricts it to specific standees (used when monsters
    /// revealed mid-round must act after their type has already gone).
    func executeMonsterGroup(_ monster: GameMonster, only: Set<Int>? = nil) async {
        guard let coordinator, let gameManager else { return }
        guard !monster.off, !monster.aliveEntities.isEmpty else { return }

        guard let ability = gameManager.monsterManager.currentAbility(for: monster) else {
            coordinator.log("\(monster.name): No ability card drawn", category: .info)
            return
        }

        isExecuting = true
        defer { isExecuting = false }
        coordinator.log("\(monster.name) — \(ability.name ?? "ability") (initiative \(ability.initiative))", category: .round)

        let actions = ability.actions ?? []

        // Monsters always consume elements if they can, and every monster of the type activated
        // this turn gains the benefit (p.24) — paid when the first monster performs the card.
        var consumed: Set<UUID>?

        let sortedEntities = monster.aliveEntities
            .filter { only?.contains($0.number) ?? true }
            // Monsters summoned this round don't act until the next round (p.31).
            .filter { $0.summonState != .new }
            .sorted { a, b in
                if a.type != b.type { return a.type == .elite || a.type == .boss }
                return a.number < b.number
            }

        var anyActed = false
        for entity in sortedEntities {
            let pieceID = PieceID.monster(name: monster.name, standee: entity.number)
            guard !entity.dead, coordinator.isOnBoard(pieceID) else { continue }

            // Start of this monster's turn: its conditions become active and tick (wound).
            gameManager.entityManager.restoreConditions(entity)
            gameManager.entityManager.applyConditionsTurn(entity)
            coordinator.sweepDeadFigures()
            guard !entity.dead, coordinator.isOnBoard(pieceID) else { continue }

            if MonsterAI.isActive(.stun, on: entity) {
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): Stunned — no actions", category: .condition)
            } else {
                anyActed = true
                if consumed == nil { consumed = consumeElements(in: actions) }
                var turn = MonsterTurnState()
                await executeCard(actions, pieceID: pieceID, entity: entity, monster: monster,
                                  ability: ability, consumed: consumed ?? [], turn: &turn)
            }
            // End of this monster's turn: conditions that last "until the end of its next turn" expire.
            if !entity.dead {
                gameManager.entityManager.expireConditions(entity)
            }
            coordinator.sweepDeadFigures()
            if coordinator.scenarioResult != nil { return }
            try? await Task.sleep(nanoseconds: coordinator.turnDelayNanoseconds)
        }

        // Infusions on the card become strong at the end of the type's turn.
        if anyActed {
            for element in MonsterAbility.elementInfusions(in: actions, consumed: consumed ?? []) {
                gameManager.game.infuseElement(element)
                coordinator.log("  \(monster.name): Infused \(element.rawValue)", category: .element)
            }
        }
    }

    /// Consume every element the card asks for that is available; returns the paid-for actions.
    private func consumeElements(in actions: [ActionModel]) -> Set<UUID> {
        guard let coordinator, let game = gameManager?.game else { return [] }
        var paid = Set<UUID>()
        for action in MonsterAbility.elementConsumes(in: actions) {
            if let used = game.consumeElements(MonsterAbility.elements(of: action)) {
                paid.insert(action.id)
                coordinator.log("  Consumed \(used.map(\.rawValue).joined(separator: " + "))", category: .element)
            }
        }
        return paid
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
    private func executeCard(_ actions: [ActionModel], pieceID: PieceID, entity: GameMonsterEntity,
                             monster: GameMonster, ability: AbilityModel, consumed: Set<UUID>,
                             turn state: inout MonsterTurnState) async {
        guard let coordinator, let gameManager else { return }
        let game = gameManager.game
        let stat = monster.attackStat(for: entity.type)
        let characterCount = max(2, game.characters.filter { !$0.absent }.count)
        let baseRange = stat?.rangeValue(characterCount: characterCount, level: monster.level) ?? 0
        func baseAttack() -> Int {
            stat?.attackValue(characterCount: characterCount, level: monster.level,
                              variables: MonsterAI.attackVariables(for: monster, gameState: game,
                                                                   hexesMoved: state.hexesMoved)) ?? 0
        }

        func currentTurn() -> MonsterTurnResult {
            MonsterAI.computeTurn(pieceID: pieceID, monster: monster, entity: entity, ability: ability,
                                  board: coordinator.boardState, gameState: game, consumed: consumed)
        }
        func stillHere() -> Bool { !entity.dead && coordinator.isOnBoard(pieceID) }

        // Focus is chosen before performing any action (p.30).
        if !state.focusChosen {
            state.focusChosen = true
            state.focus = currentTurn().focusTarget
            if state.focus == nil && (MonsterAbility.hasAttack(actions) || actions.contains { $0.type == .move }) {
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): No focus", category: .info)
            }
        }

        for action in actions {
            guard stillHere(), coordinator.scenarioResult == nil else { return }

            switch action.type {
            case .move:
                guard state.focus != nil else { continue }
                if MonsterAI.isActive(.immobilize, on: entity) {
                    coordinator.log("  \(coordinator.pieceLabel(pieceID)): Immobilized", category: .condition)
                    continue
                }
                let plan = currentTurn()
                if let newFocus = plan.focusTarget { state.focus = newFocus }
                guard plan.movementPath.count > 1 else { continue }
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): Move \(plan.movementPath.count - 1)", category: .move)
                let style: MovementStyle = monster.monsterData?.flying == true ? .fly : (plan.jumping ? .jump : .normal)
                await coordinator.moveAlong(pieceID, path: plan.movementPath, style: style)
                state.hexesMoved += plan.movementPath.count - 1

            case .attack:
                if MonsterAI.isActive(.disarm, on: entity) {
                    if !state.reportedDisarm {
                        coordinator.log("  \(coordinator.pieceLabel(pieceID)): Disarmed — no attack", category: .condition)
                        state.reportedDisarm = true
                    }
                    continue
                }
                // Re-find the focus if it died or left the board since the last action.
                if state.focus == nil || !coordinator.isOnBoard(state.focus!) { state.focus = currentTurn().focusTarget }
                guard let target = state.focus,
                      let position = coordinator.boardState.piecePositions[pieceID],
                      let focusPos = coordinator.boardState.piecePositions[target] else { continue }
                let spec = MonsterAbility.attack(action, stat: stat, baseAttack: baseAttack(),
                                                 baseRange: baseRange, consumed: consumed)
                let enemies = MonsterAI.gatherEnemies(board: coordinator.boardState, monster: monster, gameState: game)
                let targets = MonsterAI.targets(for: spec, from: position, focus: target, focusPos: focusPos,
                                                enemies: enemies, board: coordinator.boardState, gameState: game)
                if targets.isEmpty {
                    coordinator.log("  \(coordinator.pieceLabel(pieceID)): Focus out of reach", category: .move)
                    continue
                }
                for victim in targets {
                    guard stillHere(), coordinator.scenarioResult == nil else { return }
                    await coordinator.performAttack(
                        attacker: pieceID, target: victim,
                        attack: AttackParameters(value: spec.value, isRanged: spec.isRanged, pierce: spec.pierce,
                                                 conditions: spec.conditions, push: spec.push, pull: spec.pull,
                                                 advantage: spec.advantage))
                }

            case .heal:
                performHeal(action, pieceID: pieceID, entity: entity, monster: monster, consumed: consumed)

            case .condition, .push, .pull, .concatenation:
                await performTargetedEffect(action, pieceID: pieceID, monster: monster, baseRange: baseRange)

            case .element where MonsterAbility.isConsume(action):
                // An element-consume block with its own effects ("Ice: Heal 3", "Earth: Immobilize
                // all enemies within range 3", "Fire: Retaliate 3"…). Infusions inside it happen
                // with the type's other infusions after its turn.
                guard consumed.contains(action.id) else { continue }
                let block = (action.subActions ?? []).filter { $0.type != .element }
                if block.contains(where: { $0.type == .specialTarget }) {
                    await performTargetedEffect(ActionModel(type: .concatenation, subActions: block),
                                                pieceID: pieceID, monster: monster, baseRange: baseRange)
                    let others = block.filter { ![.condition, .push, .pull, .specialTarget].contains($0.type) }
                    await executeCard(others, pieceID: pieceID, entity: entity, monster: monster,
                                      ability: ability, consumed: consumed, turn: &state)
                } else {
                    for bonus in block where bonus.type == .shield || bonus.type == .retaliate {
                        applyRoundBonus(bonus, to: entity)
                    }
                    await executeCard(block.filter { $0.type != .shield && $0.type != .retaliate },
                                      pieceID: pieceID, entity: entity, monster: monster,
                                      ability: ability, consumed: consumed, turn: &state)
                }

            case .sufferDamage, .suffer:
                let amount = action.value?.intValue ?? 0
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): Suffers \(amount) damage", category: .damage)
                coordinator.sufferDamage(amount, to: pieceID)

            case .loot:
                performLoot(range: action.value?.intValue ?? 1, pieceID: pieceID)

            case .summon:
                performSummon(action, pieceID: pieceID)

            case .special:
                // Boss special abilities: run the structured actions as if they were the card
                // (so their Move/Attack drive focus and movement); scenario-specific text must be
                // resolved by the players.
                let index = (action.value?.intValue ?? 1) - 1
                guard let special = stat?.special, index >= 0, index < special.count else { continue }
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): Special \(index + 1)", category: .info)
                if special[index].contains(where: { $0.type == .custom }) {
                    coordinator.log("  Resolve the boss's special ability \(index + 1) as printed on its stat card",
                                    category: .info)
                }
                let specialActions = special[index].filter { $0.type != .custom }
                let specialCard = AbilityModel(cardId: ability.cardId, name: ability.name,
                                               initiative: ability.initiative, actions: specialActions)
                var specialState = MonsterTurnState(hexesMoved: state.hexesMoved)
                await executeCard(specialActions, pieceID: pieceID, entity: entity, monster: monster,
                                  ability: specialCard, consumed: consumed, turn: &specialState)
                state.hexesMoved = specialState.hexesMoved

            default:
                // Shield/retaliate are applied for the whole round when the card is revealed;
                // element infusions happen after the type's turn; hints/custom text are display-only.
                break
            }
        }
    }

    /// A shield/retaliate gained mid-turn (e.g. from a consumed element) lasts until the end of the round.
    private func applyRoundBonus(_ action: ActionModel, to entity: GameMonsterEntity) {
        if action.type == .shield {
            let total = (entity.shield?.value?.intValue ?? 0) + (action.value?.intValue ?? 0)
            entity.shield = ActionModel(type: .shield, value: .int(total))
        } else {
            entity.retaliate.append(action)
        }
    }

    // MARK: - Non-attack actions

    /// Heal X: the monster heals itself or an ally within range, whichever has lost the most HP (p.31).
    private func performHeal(_ action: ActionModel, pieceID: PieceID, entity: GameMonsterEntity,
                             monster: GameMonster, consumed: Set<UUID>) {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID] else { return }
        var amount = action.value?.intValue ?? 0
        var range: Int?
        var selfOnly = false
        for sub in action.subActions ?? [] {
            switch sub.type {
            case .range: range = sub.value?.intValue
            case .specialTarget: selfOnly = sub.value?.stringValue == "self"
            case .element where consumed.contains(sub.id):
                for bonus in sub.subActions ?? [] where bonus.type == .heal {
                    amount += MonsterAbility.signedValue(bonus)
                }
            default: break
            }
        }

        var candidates: [PieceID] = [pieceID]
        if let range, !selfOnly {
            for (other, coord) in coordinator.boardState.piecePositions where other != pieceID {
                guard case .monster = other, !coordinator.areEnemies(pieceID, other),
                      position.distance(to: coord) <= range,
                      LineOfSight.hasLOS(from: position, to: coord, board: coordinator.boardState) else { continue }
                candidates.append(other)
            }
        }
        let target = candidates.max { a, b in
            let lostA = coordinator.entity(for: a).map { $0.maxHealth - $0.health } ?? 0
            let lostB = coordinator.entity(for: b).map { $0.maxHealth - $0.health } ?? 0
            return lostA < lostB
        } ?? pieceID
        let healed = coordinator.heal(target, amount: amount, source: pieceID)
        coordinator.log("  \(coordinator.pieceLabel(pieceID)) → \(coordinator.pieceLabel(target)): Heal \(amount) (+\(healed))",
                        category: .heal)
    }

    /// Conditions, push or pull applied to the figures named by a `specialTarget`
    /// (self, adjacent enemies, enemies within range N, allies within range N…).
    private func performTargetedEffect(_ action: ActionModel, pieceID: PieceID, monster: GameMonster,
                                       baseRange: Int) async {
        guard let coordinator else { return }
        let parts = action.type == .concatenation ? (action.subActions ?? []) : [action] + (action.subActions ?? [])
        let spec = parts.first { $0.type == .specialTarget }?.value?.stringValue
        let targets = figures(for: spec, from: pieceID, monster: monster, baseRange: baseRange)

        for part in parts {
            switch part.type {
            case .condition:
                guard let name = part.value?.stringValue, let condition = ConditionName(rawValue: name) else { continue }
                for target in targets where coordinator.isOnBoard(target) {
                    coordinator.applyCondition(condition, to: target)
                }
            case .push, .pull:
                let steps = part.value?.intValue ?? 0
                guard steps > 0, let origin = coordinator.boardState.piecePositions[pieceID] else { continue }
                for target in targets where target != pieceID && coordinator.isOnBoard(target) {
                    await coordinator.performPushPull(target: target, attackerPos: origin, steps: steps,
                                                      isPush: part.type == .push)
                }
            default:
                break
            }
        }
    }

    /// Resolve a `specialTarget` value to the affected figures.
    private func figures(for spec: String?, from pieceID: PieceID, monster: GameMonster, baseRange: Int) -> [PieceID] {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID],
              let game = gameManager?.game else { return [] }
        let raw = (spec ?? "self").lowercased()
        if raw == "self" { return [pieceID] }

        let wantsEnemies = raw.hasPrefix("enem")
        let range: Int = {
            if raw.contains("adjacent") { return 1 }
            if let colon = raw.firstIndex(of: ":"), let n = Int(raw[raw.index(after: colon)...]) { return n }
            return max(1, baseRange)
        }()
        let pool: [PieceID] = wantsEnemies
            ? MonsterAI.gatherEnemies(board: coordinator.boardState, monster: monster, gameState: game)
            : coordinator.boardState.piecePositions.keys.filter {
                $0 != pieceID && !coordinator.areEnemies(pieceID, $0)
            }
        let inRange = pool.filter { id in
            guard let coord = coordinator.boardState.piecePositions[id] else { return false }
            return position.distance(to: coord) <= range
                && LineOfSight.hasLOS(from: position, to: coord, board: coordinator.boardState)
        }
        if raw.hasPrefix("enemyadjacent") || raw.hasPrefix("allyadjacent") {
            return Array(inRange.prefix(1))
        }
        return inRange
    }

    /// Monster loot: pick up every money token within range; those tokens are lost (p.31).
    private func performLoot(range: Int, pieceID: PieceID) {
        guard let coordinator, let position = coordinator.boardState.piecePositions[pieceID] else { return }
        var taken = 0
        for coord in Array(coordinator.boardState.lootTokens.keys) where position.distance(to: coord) <= range {
            taken += coordinator.boardState.takeLoot(at: coord)
            coordinator.boardScene?.removeLootSprite(at: coord, offsetCol: coordinator.offsetCol,
                                                     offsetRow: coordinator.offsetRow)
        }
        if taken > 0 {
            coordinator.log("  \(coordinator.pieceLabel(pieceID)): Looted \(taken) money token(s)", category: .loot)
        }
    }

    /// Monster summon: place the summoned monster in an empty adjacent hex, as close to an enemy
    /// as possible. It doesn't act this round and drops no money token (p.31).
    private func performSummon(_ action: ActionModel, pieceID: PieceID) {
        guard let coordinator, let game = gameManager?.game,
              let specs = action.monsterSummons else { return }
        let characterCount = max(2, game.characters.filter { !$0.absent }.count)
        for spec in specs {
            let type = spec.type(forPlayerCount: characterCount)
            if !coordinator.summonMonster(name: spec.name, type: type, near: pieceID) {
                coordinator.log("  \(coordinator.pieceLabel(pieceID)): Summon \(spec.name) failed", category: .info)
            }
        }
    }
}
