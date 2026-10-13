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
        for piece in partyInInitiativeOrder() {
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
        // Who is still to play two cards, latest in the order.
        let toCome = turnOrder.indices.filter { $0 > currentTurnIndex && !turnOrder[$0].completed }.compactMap { index -> GameCharacter? in
            guard case .character(let character) = turnOrder[index].figure, !character.longRest, !character.exhausted,
                  selectedCardPairs[character.id] != nil, isOnBoard(.character(character.id)) else { return nil }
            return character
        }
        guard let victim = toCome.last ?? gameManager.game.characters.filter({ character in
            // (Outside a round's turn order — a test, a board set by hand — whoever has cards down.)
            turnOrder.isEmpty && !character.exhausted && !character.longRest && selectedCardPairs[character.id] != nil
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
    /// normally be lost." Of the top action its attacks are made, on those it now takes for
    /// enemies; what else it prints is left out.
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
        let leading = selectedCardPairs[character.id]?.top
        log("\(characterName(character.id)) is mind controlled: Move \(sway.controlled), then the top of \(leading?.name ?? "their leading card")", category: .condition)
        // The attacks of the top action, as a monster's card would give them.
        let attacks = MonsterAbility.flattened(leading?.actions ?? []).filter { $0.type == .attack }.compactMap { action -> MonsterAttackSpec? in
            let printed = ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                      subActions: (action.subActions ?? []).filter { $0.type != .specialTarget })
            return MonsterAbility.attack(printed, stat: nil, baseAttack: max(0, action.value?.intValue ?? 0), baseRange: 0)
        }
        let plan = PlayerSideAI.plan(pieceID: piece, entity: character, move: max(0, sway.controlled + scenarioMoveBonus(of: piece)),
                                     attack: attacks.first, flying: false, board: boardState, gameState: gameManager.game)
        guard !plan.stunned, plan.focus != nil else {
            log("\(characterName(character.id)) finds no one to turn on", category: .info)
            return
        }
        if plan.path.count > 1 {
            log("\(characterName(character.id)) moves \(plan.path.count - 1) hex\(plan.path.count == 2 ? "" : "es")", category: .move, trace: "to \(plan.path.last!)")
            guard await moveAlong(piece, path: plan.path, style: .normal), isCurrentBoard(generation) else { return }
        }
        for (index, attack) in attacks.enumerated() {
            // The first as planned; any further attack on whoever is then in reach.
            let targets = index == 0 ? plan.targets
                : PlayerSideAI.plan(pieceID: piece, entity: character, move: 0, attack: attack, flying: false,
                                    board: boardState, gameState: gameManager.game).targets
            for target in targets {
                guard isCurrentBoard(generation), scenarioResult == nil, isOnBoard(piece), isOnBoard(target) else { return }
                _ = await performAttack(attacker: piece, target: target,
                                        attack: AttackParameters(value: attack.value, isRanged: attack.isRanged, pierce: attack.pierce,
                                                                 conditions: attack.conditions, push: attack.push, pull: attack.pull))
            }
        }
        if attacks.isEmpty {
            log("The top of \(leading?.name ?? "the card") has no attack to turn on the party", category: .info)
        }
    }
}
