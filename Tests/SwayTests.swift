import XCTest
@testable import GlavenGameLib

/// A boss whose specials drive the party off, draw it in and turn one of them
/// (`ScenarioPlacements.Sway`, `BoardCoordinator+Sway`): the Betrayer of the Lost Temple (#79).
@MainActor
final class SwayTests: XCTestCase {

    private func simulator(_ characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "79", options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        for _ in 0..<10 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
            sim.coord.boardState.lockedDoors.removeAll()
            sim.coord.openDoor(at: door.coord)
        }
        // Only the Betrayer is left of the monsters.
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster(let name, _) = piece, name != "the-betrayer" { sim.coord.removePieceFromBoard(piece); (sim.coord.entity(for: piece) as? GameMonsterEntity)?.dead = true }
        }
        return sim
    }

    private func boss(_ sim: ScenarioSimulator) throws -> (piece: PieceID, hex: HexCoord) {
        let piece = try XCTUnwrap(sim.coord.boardState.piecePositions.keys.sorted().first { if case .monster("the-betrayer", _) = $0 { return true }; return false })
        return (piece, try XCTUnwrap(sim.coord.boardState.piecePositions[piece]))
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func floor(_ sim: ScenarioSimulator, where test: (HexCoord) -> Bool) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { board.isPassable($0) && board.cells[$0]?.overlay == nil && board.piece(at: $0) == nil && test($0) })
    }

    private func special(_ number: Int, _ sim: ScenarioSimulator) async throws {
        let betrayer = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "the-betrayer" })
        let deck = sim.gm.monsterManager.abilities(for: betrayer)
        let card = try XCTUnwrap(deck.firstIndex { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == number } })
        betrayer.abilities = [card]
        betrayer.ability = 0
        betrayer.abilityDrawn = true
        sim.gm.game.state = .next
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(betrayer)
    }

    private func summon(for owner: GameCharacter, at hex: HexCoord, _ sim: ScenarioSimulator) -> GameSummon {
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: owner.summons.count + 1, health: 8, maxHealth: 8, level: 1,
                                attack: .int(2), movement: 2, range: 0)
        summon.state = .active
        owner.summons.append(summon)
        sim.coord.boardState.placePiece(.summon(id: summon.id), at: hex)
        return summon
    }

    /// Special 1: "all characters and character summons are forced to perform 'Move 4' in
    /// initiative order such that they end the movement as far away from the Betrayer as possible."
    func testItsFirstSpecialDrivesThePartyAway() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        func far(_ hex: HexCoord?) -> Int { hex.flatMap { coord.boardState.range(from: $0, to: betrayer.hex) } ?? -1 }
        // The Brute three hexes off, the Spellweaver immobilized as far, a summon of the Brute's four off.
        let three = coord.boardState.cells.keys.sorted().filter { coord.boardState.isPassable($0) && coord.boardState.cells[$0]?.overlay == nil
            && coord.boardState.piece(at: $0) == nil && far($0) == 3 }
        XCTAssertGreaterThanOrEqual(three.count, 2)
        stand(sim, .character(brute.id), on: three[0])
        stand(sim, .character(weaver.id), on: three[three.count - 1])
        weaver.entityConditions.append(EntityCondition(name: .immobilize))
        let ally = summon(for: brute, at: try floor(sim) { far($0) == 4 }, sim)
        // What "as far as a Move 4 gets them" is, by the board's own measure.
        func farthest(_ piece: PieceID) throws -> Int {
            let here = try XCTUnwrap(coord.boardState.piecePositions[piece])
            let (enemies, allies) = coord.movementSets(for: piece)
            let reach = Pathfinder.reachableHexes(board: coord.boardState, from: here, range: 4, mode: .normal, avoidTraps: true,
                                                  canOpenDoors: false, occupiedByEnemy: enemies, occupiedByAlly: allies)
            return (reach.keys.filter { coord.boardState.piece(at: $0) == nil } + [here]).map(far).max() ?? 0
        }
        let allyBest = try farthest(.summon(id: ally.id))
        try await special(1, sim)
        XCTAssertFalse(coord.boardState.piecePositions.keys.filter { if case .monster("giant-viper", _) = $0 { return true }; return false }.isEmpty,
                       "its vipers are summoned first")
        XCTAssertEqual(far(coord.boardState.piecePositions[.summon(id: ally.id)]), allyBest, "the summon went first, as far as it could")
        XCTAssertGreaterThan(allyBest, 4)
        let bruteNow = far(coord.boardState.piecePositions[.character(brute.id)])
        XCTAssertGreaterThan(bruteNow, 3, "the Brute is driven off")
        XCTAssertLessThanOrEqual(bruteNow, 7, "by no more than a Move 4")
        XCTAssertEqual(far(coord.boardState.piecePositions[.character(weaver.id)]), 3, "immobilized, the Spellweaver stays")
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })

        // Alone on the board, from each of several places: always to the farthest hex a Move 4 reaches.
        coord.boardState.removePiece(.character(weaver.id))
        coord.boardState.removePiece(.summon(id: ally.id))
        brute.summons.removeAll()
        for start in three.prefix(3) {
            for piece in coord.boardState.piecePositions.keys.sorted() { if case .monster("giant-viper", _) = piece { coord.sufferDamage(999, to: piece) } }
            stand(sim, .character(brute.id), on: start)
            let best = try farthest(.character(brute.id))
            await coord.driveOff(from: betrayer.piece)
            XCTAssertEqual(far(coord.boardState.piecePositions[.character(brute.id)]), best, "from \(start)")
        }
    }

    /// Special 2: "All characters and character summons are forced to move to the closest hex
    /// adjacent to the Betrayer. The character who will play two cards latest in the turn order
    /// is mind controlled for this round", their summons with them.
    func testItsSecondSpecialDrawsThePartyInAndTurnsTheLastToAct() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        func far(_ hex: HexCoord?) -> Int { hex.flatMap { coord.boardState.range(from: $0, to: betrayer.hex) } ?? -1 }
        stand(sim, .character(brute.id), on: try floor(sim) { far($0) == 5 })
        stand(sim, .character(weaver.id), on: try floor(sim) { far($0) == 4 })
        let ally = summon(for: weaver, at: try floor(sim) { far($0) == 6 }, sim)
        // Both have two cards down; the Spellweaver's are the slower.
        for (character, initiative) in [(brute, 20), (weaver, 70)] {
            let hand = sim.hand(of: character)
            coord.selectedCardPairs[character.id] = (top: hand[0], bottom: hand[1])
            character.initiative = initiative
        }
        try await special(2, sim)
        for piece in [PieceID.character(brute.id), .character(weaver.id), .summon(id: ally.id)] {
            XCTAssertEqual(far(coord.boardState.piecePositions[piece]), 1, "\(piece) is drawn to its side")
        }
        XCTAssertEqual(coord.boardState.turned, [.character(weaver.id), .summon(id: ally.id)], "the last to play, and her summon")
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })

        // Her summon turns on the party; the Brute's wouldn't.
        let turn = SummonAI.computeTurn(summon: ally, ownerCharacterID: weaver.id, board: coord.boardState, gameState: sim.gm.game)
        XCTAssertEqual(turn.attackTargets, [.character(brute.id)])
        coord.boardState.turned = []
        XCTAssertTrue(SummonAI.computeTurn(summon: ally, ownerCharacterID: weaver.id, board: coord.boardState, gameState: sim.gm.game)
            .attackTargets.allSatisfy { if case .monster = $0 { return true }; return false })

        // A long rest plays no cards: with the Spellweaver resting it is the Brute who is taken.
        weaver.longRest = true
        coord.selectedCardPairs[weaver.id] = nil
        try await special(2, sim)
        XCTAssertEqual(coord.boardState.turned, [.character(brute.id)])
    }

    /// "On their turn, they will perform a 'Move 2' and then the top action of their
    /// leading-initiative card, after which both played cards are discarded even if they would
    /// normally be lost."
    func testAMindControlledCharacterTurnsOnTheParty() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let hand = sim.hand(of: brute)
        // A leading card whose top is an attack and is lost when played; any other for the second.
        func attacks(_ card: AbilityModel) -> Bool { MonsterAbility.flattened(card.actions ?? []).contains { $0.type == .attack } }
        let leading = try XCTUnwrap(hand.first { attacks($0) && ($0.lost ?? false) } ?? hand.first(where: attacks), "a Brute card with an attack on top")
        let second = try XCTUnwrap(hand.first { $0.cardId != leading.cardId })
        coord.selectedCardPairs[brute.id] = (top: leading, bottom: second)
        coord.boardState.turned = [.character(brute.id)]
        // The Spellweaver three hexes from the Brute, the Betrayer far from both.
        let start = try floor(sim) { (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 5 }
        stand(sim, .character(brute.id), on: start)
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: start) == 3
            && (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 5 })
        weaver.maxHealth = 40
        weaver.health = 40
        let lines = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        let said = coord.turnLog.dropFirst(lines).map(\.message)
        let now = try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])
        XCTAssertLessThanOrEqual(coord.boardState.range(from: start, to: now) ?? 9, 2, "Move 2")
        XCTAssertTrue(coord.boardState.areAdjacent(now, try XCTUnwrap(coord.boardState.piecePositions[.character(weaver.id)])), "toward the Spellweaver")
        XCTAssertTrue(said.contains { $0.hasPrefix("Brute attacks Spellweaver") }, "\(said)")
        XCTAssertFalse(said.contains { $0.contains("Betrayer") && $0.contains("attacks") })
        // Both cards in the discard pile, lost icon or not; neither in hand.
        for card in [leading, second] {
            let id = try XCTUnwrap(card.cardId)
            XCTAssertTrue(brute.discardedCards.contains(id), "\(card.name ?? "") is discarded")
            XCTAssertFalse(brute.handCards.contains(id))
            XCTAssertFalse(brute.lostCards.contains(id))
        }

        // Too far to reach in a Move 2: two hexes nearer, and no attack.
        coord.selectedCardPairs[brute.id] = (top: leading, bottom: second)
        let from = try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: from) == 6 })
        let quietly = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        XCTAssertEqual(coord.boardState.range(from: from, to: try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])), 2)
        XCTAssertFalse(coord.turnLog.dropFirst(quietly).contains { $0.message.hasPrefix("Brute attacks") })

        // A top with no attack: the Move, and nothing else.
        let quiet = try XCTUnwrap(hand.first { !attacks($0) && $0.cardId != leading.cardId && $0.cardId != second.cardId })
        coord.selectedCardPairs[brute.id] = (top: quiet, bottom: second)
        weaver.health = weaver.maxHealth
        let before = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        XCTAssertFalse(coord.turnLog.dropFirst(before).contains { $0.message.hasPrefix("Brute attacks") })
        XCTAssertEqual(weaver.health, weaver.maxHealth)
    }

    /// In a round of play: the Betrayer's second special takes someone still to act, their turn
    /// is played for them, and the control ends with the round.
    func testMindControlInARoundOfPlay() async throws {
        var controlled = 0
        for seed in 1...6 {
            let sim = try ScenarioSimulator(scenario: "79", options: .init(characters: ["brute", "spellweaver", "tinkerer"], seed: UInt64(seed)))
            for _ in 0..<10 {
                guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
                sim.coord.boardState.lockedDoors.removeAll()
                sim.coord.openDoor(at: door.coord)
            }
            let betrayer = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "the-betrayer" })
            let deck = sim.gm.monsterManager.abilities(for: betrayer)
            let card = try XCTUnwrap(deck.firstIndex { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == 2 } })
            betrayer.abilities = [card, card, card]
            betrayer.ability = -1
            _ = await sim.play(rounds: 2)
            XCTAssertTrue(sim.violations.isEmpty, "seed \(seed): \(sim.violations)")
            XCTAssertTrue(sim.coord.boardState.turned.isEmpty || sim.coord.scenarioResult != nil, "seed \(seed): the control ends with the round")
            let lines = sim.transcript
            if let taken = lines.firstIndex(where: { $0.contains("takes control of") }) {
                let who = lines[taken].components(separatedBy: "takes control of ").last?.components(separatedBy: " for the round").first ?? "?"
                XCTAssertTrue(lines[taken...].contains { $0.hasPrefix("\(who) is mind controlled") }, "seed \(seed): \(who)'s turn is played for them")
                controlled += 1
            }
        }
        XCTAssertGreaterThan(controlled, 0, "someone is taken in one of these games")
    }
}
