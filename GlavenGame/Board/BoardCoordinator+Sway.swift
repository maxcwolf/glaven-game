import Foundation

/// A boss whose specials drive the party off, draw it in and turn one of them
/// (`ScenarioPlacements.Sway`): the Betrayer of the Lost Temple.
extension BoardCoordinator {

    var scenarioSway: ScenarioPlacements.Sway? { scenarioData?.placements?.sway }

    /// The characters still standing and their summons, in initiative order: a summon before its
    /// owner, the characters as the round's turn order has them.
    func partyInInitiativeOrder() -> [PieceID] {
        guard let gameManager else { return [] }
        let turns = turnOrder.compactMap { entry -> String? in
            if case .character(let character) = entry.figure { return character.id }
            return nil
        }
        func place(_ character: GameCharacter) -> (Int, Double, String) {
            (turns.firstIndex(of: character.id) ?? turns.count, character.longRest ? 99 : character.effectiveInitiative, character.id)
        }
        return gameManager.game.characters.filter { !$0.exhausted && !$0.absent }.sorted { place($0) < place($1) }
            .flatMap { character in character.summons.filter { !$0.dead }.map { PieceID.summon(id: $0.id) } + [.character(character.id)] }
            .filter { boardState.piecePositions[$0] != nil }
    }

    /// "All characters and character summons are forced to perform 'Move 4' in initiative order
    /// such that they end the movement as far away from the Betrayer as possible."
    @MainActor func driveOff(from boss: PieceID) async {
        guard let sway = scenarioSway, let bossHex = boardState.piecePositions[boss] else { return }
        let generation = boardGeneration
        log("\(name(boss)) drives everyone from it: Move \(sway.flee), as far away as each can get", category: .move)
        for piece in partyInInitiativeOrder() {
            guard isCurrentBoard(generation), scenarioResult == nil, isOnBoard(piece), let here = boardState.piecePositions[piece] else { continue }
            // (FAQ: "The boss's two abilities can affect invisible characters. They also require LOS.")
            guard LineOfSight.hasLOS(from: bossHex, to: here, board: boardState) else {
                log("\(name(piece)) is out of \(name(boss))\u{2019}s sight", category: .move)
                continue
            }
            if isConditionActive(.immobilize, on: piece) {
                log("\(name(piece)) is immobilized and can\u{2019}t move", category: .condition)
                continue
            }
            let (enemies, allies) = movementSets(for: piece)
            let move = max(0, sway.flee + scenarioMoveBonus(of: piece))
            let reach = Pathfinder.reachableHexes(board: boardState, from: here, range: move, mode: .normal, avoidTraps: true,
                                                  canOpenDoors: false, occupiedByEnemy: enemies, occupiedByAlly: allies)
            func far(_ hex: HexCoord) -> Int { boardState.range(from: hex, to: bossHex) ?? 99 }
            let places = ([here] + reach.keys.filter { $0 != here && boardState.piece(at: $0) == nil && !boardState.isClosedDoor($0) })
            guard let farthest = places.map(far).max(), farthest > far(here) else {
                log("\(name(piece)) can get no further from \(name(boss))", category: .move)
                continue
            }
            let options = places.filter { far($0) == farthest }.sorted()
            var destination = options[0]
            if options.count > 1 {
                destination = await chooseHex(options, for: piece, title: "Driven from \(name(boss))",
                                              detail: "Tap the hex \(name(piece)) ends on: as far away as they can get") ?? options[0]
                guard isCurrentBoard(generation) else { return }
            }
            guard let path = Pathfinder.findPath(board: boardState, from: here, to: destination, avoidTraps: true, canOpenDoors: false,
                                                 occupiedByEnemy: enemies, occupiedByAlly: allies), path.count > 1 else { continue }
            log("\(name(piece)) moves \(path.count - 1) hex\(path.count == 2 ? "" : "es") away", category: .move, trace: "to \(destination)")
            _ = await moveAlong(piece, path: path, style: .normal)
        }
    }

    /// "All characters and character summons are forced to move to the closest hex adjacent to
    /// the Betrayer. The character who will play two cards latest in the turn order is mind
    /// controlled for this round", their summons with them.
    @MainActor func drawInAndTurn(by boss: PieceID) async {
        guard scenarioSway != nil, let bossHex = boardState.piecePositions[boss], let gameManager else { return }
        let generation = boardGeneration
        log("\(name(boss)) draws everyone to its side", category: .move)
        // Only those it sees (FAQ), invisible or not.
        let seen = Set(partyInInitiativeOrder().filter { piece in
            boardState.piecePositions[piece].map { LineOfSight.hasLOS(from: bossHex, to: $0, board: boardState) } ?? false
        })
        for piece in partyInInitiativeOrder() where seen.contains(piece) {
            guard isCurrentBoard(generation), scenarioResult == nil, isOnBoard(piece), let here = boardState.piecePositions[piece],
                  !boardState.areAdjacent(here, bossHex) else { continue }
            let (enemies, allies) = movementSets(for: piece)
            func way(to hex: HexCoord, sparingTraps: Bool) -> [HexCoord]? {
                Pathfinder.findPath(board: boardState, from: here, to: hex, avoidTraps: sparingTraps, canOpenDoors: false,
                                    occupiedByEnemy: [], occupiedByAlly: enemies.union(allies))
            }
            // The nearest free hex beside it; with none free, the nearest it can get.
            let beside = boardState.neighbors(of: bossHex).filter { boardState.isPassable($0) && boardState.piece(at: $0) == nil }.sorted()
            let goals = beside.isEmpty ? [nearestEmptyHex(to: bossHex)].compactMap { $0 } : beside
            let ways = goals.compactMap { way(to: $0, sparingTraps: true) ?? way(to: $0, sparingTraps: false) }
            guard let path = ways.min(by: { ($0.count, $0.last!) < ($1.count, $1.last!) }), path.count > 1 else {
                log("\(name(piece)) finds no way to \(name(boss))", category: .move)
                continue
            }
            log("\(name(piece)) is drawn \(path.count - 1) hex\(path.count == 2 ? "" : "es") to \(name(boss))", category: .move, trace: "to \(path.last!)")
            _ = await moveAlong(piece, path: path, style: .forced)
        }
        guard isCurrentBoard(generation), scenarioResult == nil else { return }
        // Who is still to play two cards, latest in the order, of those it sees.
        func inSight(_ character: GameCharacter) -> Bool { seen.contains(.character(character.id)) }
        let toCome = turnOrder.indices.filter { $0 > currentTurnIndex && !turnOrder[$0].completed }.compactMap { index -> GameCharacter? in
            guard case .character(let character) = turnOrder[index].figure, !character.longRest, !character.exhausted,
                  selectedCardPairs[character.id] != nil, inSight(character) else { return nil }
            return character
        }
        guard let victim = toCome.last ?? gameManager.game.characters.filter({ character in
            // (Outside a round's turn order — a test, a board set by hand — whoever has cards down.)
            turnOrder.isEmpty && !character.exhausted && !character.longRest && selectedCardPairs[character.id] != nil
                && inSight(character)
        }).max(by: { $0.effectiveInitiative < $1.effectiveInitiative }) else {
            log("No one is left to play two cards this round: \(name(boss)) controls no one", category: .info)
            return
        }
        boardState.turned.insert(.character(victim.id))
        for summon in victim.summons where !summon.dead { boardState.turned.insert(.summon(id: summon.id)) }
        log("\(name(boss)) takes control of \(characterName(victim.id)) for the round", category: .condition)
    }

    /// The mind-controlled character's turn: "a 'Move 2' and then the top action of their
    /// leading-initiative card, after which both played cards are discarded even if they would
    /// normally be lost." The Move takes them, as a monster's would, to where the top action's
    /// first attack can be made on the party. Then the top action, ability by ability, for the
    /// side they now fight on: attacks and negative conditions on the party, a heal on the most
    /// hurt of themselves and the monsters in reach, a Shield or Retaliate on themselves for the
    /// round, a Move toward the party, a Loot, an infusion. What only stays in play with its card
    /// — a persistent or round bonus, a summon — isn't performed: the card is discarded.
    @MainActor func mindControlledTurn(of character: GameCharacter) async {
        guard let sway = scenarioSway, let gameManager else { return }
        let piece = PieceID.character(character.id)
        let generation = boardGeneration
        defer {
            if let pair = selectedCardPairs[character.id] {
                for cardId in [pair.top.cardId, pair.bottom.cardId].compactMap({ $0 }) {
                    character.handCards.removeAll { $0 == cardId }
                    if !character.discardedCards.contains(cardId) { character.discardedCards.append(cardId) }
                }
            }
        }
        let who = characterName(character.id)
        let leading = selectedCardPairs[character.id]?.top
        log("\(who) is mind controlled: Move \(sway.controlled), then the top of \(leading?.name ?? "their leading card")", category: .condition)
        let steps = MonsterAbility.flattened(leading?.actions ?? [])
        // An attack of the card as a monster's card would give it.
        func spec(_ action: ActionModel) -> MonsterAttackSpec? {
            let printed = ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                      subActions: (action.subActions ?? []).filter { $0.type != .specialTarget })
            return MonsterAbility.attack(printed, stat: nil, baseAttack: max(0, action.value?.intValue ?? 0), baseRange: 0)
        }
        func firstAttack(after index: Int) -> MonsterAttackSpec? {
            steps.indices.filter { $0 > index }.lazy.map { steps[$0] }.first { $0.type == .attack }.flatMap(spec)
        }
        func plan(move: Int, attack: MonsterAttackSpec?) -> PlayerSideAI.Plan {
            PlayerSideAI.plan(pieceID: piece, entity: character, move: max(0, move + scenarioMoveBonus(of: piece)), attack: attack,
                              flying: false, board: boardState, gameState: gameManager.game)
        }
        func stillOn() -> Bool { isCurrentBoard(generation) && scenarioResult == nil && isOnBoard(piece) && !character.exhausted }
        func walk(_ path: [HexCoord]) async -> Bool {
            guard path.count > 1 else { return true }
            log("\(who) moves \(path.count - 1) hex\(path.count == 2 ? "" : "es")", category: .move, trace: "to \(path.last!)")
            return await moveAlong(piece, path: path, style: .normal) && stillOn()
        }
        func range(of action: ActionModel) -> Int? {
            (action.subActions ?? []).first { $0.type == .range }?.value?.intValue
        }
        /// Who they now fight: the party, in reach and in sight.
        func foes(within reach: Int) -> [PieceID] {
            guard let here = boardState.piecePositions[piece] else { return [] }
            return PlayerSideAI.formerAllies(of: piece, board: boardState, gameState: gameManager.game, includeInvisible: false)
                .filter { foe in boardState.piecePositions[foe].map { boardState.isWithin(max(1, reach), from: here, to: $0)
                    && LineOfSight.hasLOS(from: here, to: $0, board: boardState) } ?? false }
        }

        var current = plan(move: sway.controlled, attack: firstAttack(after: -1))
        guard !current.stunned else {
            log("\(who) is stunned and does nothing", category: .condition)
            return
        }
        guard await walk(current.path) else { return }
        var planFresh = true
        var left: [String] = []
        for (index, step) in steps.enumerated() {
            guard stillOn() else { return }
            switch step.type {
            case .attack:
                guard let attack = spec(step) else { continue }
                // As planned by the move before it; a further attack on whoever is then in reach.
                let targets = planFresh ? current.targets : plan(move: 0, attack: attack).targets
                planFresh = false
                if targets.isEmpty { log("\(who) has no one to attack", category: .attack) }
                for target in targets {
                    guard stillOn(), isOnBoard(target) else { return }
                    _ = await performAttack(attacker: piece, target: target,
                                            attack: AttackParameters(value: attack.value, isRanged: attack.isRanged, pierce: attack.pierce,
                                                                     conditions: attack.conditions, push: attack.push, pull: attack.pull))
                }
            case .move:
                current = plan(move: step.value?.intValue ?? 0, attack: firstAttack(after: index))
                planFresh = true
                guard await walk(current.path) else { return }
            case .heal:
                let amount = step.value?.intValue ?? 0
                let selfOnly = (step.subActions ?? []).contains { $0.type == .specialTarget && $0.value?.stringValue == "self" }
                var options: [PieceID] = [piece]
                if !selfOnly, let reach = range(of: step), let here = boardState.piecePositions[piece] {
                    options += boardState.piecePositions.keys.sorted().filter { other in
                        guard case .monster = other, side(of: other) == .monsters, !isInactive(other),
                              let there = boardState.piecePositions[other] else { return false }
                        return boardState.isWithin(reach, from: here, to: there) && LineOfSight.hasLOS(from: here, to: there, board: boardState)
                    }
                }
                func hurt(_ figure: PieceID) -> Int { entity(for: figure).map { $0.maxHealth - $0.health } ?? 0 }
                guard let target = options.max(by: { hurt($0) < hurt($1) || (hurt($0) == hurt($1) && $0 != piece && $1 == piece) }) else { continue }
                let healed = heal(target, amount: amount, source: piece)
                log("\(who) heals \(target == piece ? "themselves" : name(target)) for \(healed)", category: .heal)
            case .shield, .retaliate:
                let value = step.value?.intValue ?? 0
                if step.type == .shield {
                    character.shield = ActionModel(type: .shield, value: .int((character.shield?.value?.intValue ?? 0) + value))
                    log("\(who): Shield \(value) for the round", category: .condition)
                } else {
                    let reach = range(of: step) ?? 1
                    character.retaliate.append(ActionModel(type: .retaliate, value: .int(value),
                                                           subActions: reach > 1 ? [ActionModel(type: .range, value: .int(reach))] : nil))
                    log("\(who): Retaliate \(value) for the round", category: .condition)
                }
            case .element:
                guard !MonsterAbility.isConsume(step) else { continue }
                for element in MonsterAbility.elements(of: step) where element != .wild {
                    gameManager.game.infuseElement(element)
                    log("\(who) infuses \(GameText.elementName(element))", category: .element)
                }
            case .loot:
                guard let here = boardState.piecePositions[piece] else { continue }
                let reach = step.value?.intValue ?? 1
                let hexes = boardState.cells.keys.filter { hex in
                    boardState.isWithin(reach, from: here, to: hex) && LineOfSight.hasLOS(from: here, to: hex, board: boardState)
                }.sorted()
                lootHexes(for: piece, coords: [here] + hexes.filter { $0 != here }, byLootAction: true)
            case .condition:
                guard let name = step.value?.stringValue, let condition = ConditionName(rawValue: name) else { continue }
                if condition.isNegative {
                    guard let target = foes(within: range(of: step) ?? 1).first else { continue }
                    applyCondition(condition, to: target, by: piece)
                } else {
                    applyCondition(condition, to: piece)
                }
            default:
                left.append(step.type.rawValue)
            }
        }
        if !left.isEmpty {
            log("The rest of the top of \(leading?.name ?? "the card") isn\u{2019}t performed: what stays in play with its card goes to the discard pile with it",
                category: .info, trace: left.joined(separator: ", "))
        }
    }
}
