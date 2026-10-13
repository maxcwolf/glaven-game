import XCTest
@testable import GlavenGameLib

/// Doorways shut to some monsters (`ScenarioPlacements.barred`): the Arcane Golem of the Arcane
/// Library (#67) and the Inox of Rockslide Ridge's cave (#73).
@MainActor
final class BarredDoorTests: XCTestCase {

    private func simulator(_ index: String) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<20 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            sim.coord.boardState.lockedDoors.removeAll()
            sim.coord.openDoor(at: door.coord)
        }
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        if let other = sim.coord.boardState.piece(at: hex), other != piece { sim.coord.removePieceFromBoard(other) }
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func door(_ sim: ScenarioSimulator, into tile: String) throws -> HexCoord {
        try XCTUnwrap(sim.coord.boardState.doors.first { $0.childTileRef.lowercased() == tile }?.coord)
    }

    private func floor(_ sim: ScenarioSimulator, beside hex: HexCoord, on tile: String) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.neighbors(of: hex).sorted().first {
            board.isPassable($0) && board.cells[$0]?.tileRef.lowercased() == tile && board.cells[$0]?.overlay == nil
        }, "no floor of \(tile) beside \(hex)")
    }

    /// "It is the Arcane Golem. It cannot enter or pass through door 2": with the door held open
    /// and a character just beyond it, the golem stays in the library — walking or pulled.
    func testTheArcaneGolemNeverGoesThroughTheLibraryDoor() async throws {
        let sim = try simulator("67")
        let coord = sim.coord
        revealAll(sim)
        let doorway = try door(sim, into: "m1a")
        let golem = try XCTUnwrap(coord.boardState.piecePositions.keys.sorted().first { if case .monster("stone-golem", _) = $0 { return true }; return false })
        for piece in coord.boardState.piecePositions.keys.sorted() where piece != golem {
            if case .monster = piece { coord.removePieceFromBoard(piece) }
        }
        let inside = try floor(sim, beside: doorway, on: "m1a")
        let outside = try XCTUnwrap(coord.boardState.neighbors(of: doorway).sorted().first {
            coord.boardState.isPassable($0) && coord.boardState.cells[$0]?.tileRef.lowercased() != "m1a" && $0 != inside
        })
        let brute = PieceID.character(sim.gm.game.characters[0].id), weaver = PieceID.character(sim.gm.game.characters[1].id)
        // The Spellweaver holds the door open from the plate in the library; the Brute stands outside it.
        let plate = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first { coord.boardState.cells[$0]?.tileRef.lowercased() == "m1a" })
        stand(sim, weaver, on: plate)
        sim.gm.game.characters[1].entityConditions.append(EntityCondition(name: .invisible))
        stand(sim, brute, on: outside)
        stand(sim, golem, on: inside)
        coord.updateLocks()
        XCTAssertFalse(coord.boardState.isClosedDoor(doorway), "held open")
        XCTAssertEqual(coord.boardState.barredHexes(for: golem), [doorway])
        XCTAssertTrue(coord.boardState.barredHexes(for: brute).isEmpty)

        // Its turn, on a card that moves and attacks: the Brute is two hexes off through the door.
        let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "stone-golem" })
        let cards = sim.gm.monsterManager.abilities(for: monster)
        let index = try XCTUnwrap(cards.firstIndex { card in
            let actions = MonsterAbility.flattened(card.actions ?? [])
            return actions.contains { $0.type == .move } && actions.contains { $0.type == .attack } && !actions.contains { $0.type == .range }
        })
        monster.abilities = Array(cards.indices)
        monster.ability = index
        monster.abilityDrawn = true
        let health = sim.gm.game.characters[0].health
        await MonsterTurnController(coordinator: coord, gameManager: sim.gm).executeMonsterGroup(monster)
        let ended = try XCTUnwrap(coord.boardState.piecePositions[golem])
        XCTAssertNotEqual(ended, doorway)
        XCTAssertEqual(coord.boardState.cells[ended]?.tileRef.lowercased(), "m1a", "it stays in the library")
        XCTAssertEqual(sim.gm.game.characters[0].health, health, "and can't reach the Brute")

        // Pulled toward the Brute, it has nowhere to go; pushed away from the Spellweaver neither.
        stand(sim, golem, on: inside)
        XCTAssertFalse(coord.forcedMoveSteps(for: golem, from: inside, attackerPos: outside, stepsLeft: 2, isPush: false).contains(doorway))
        XCTAssertFalse(coord.movementSets(for: brute).enemies.contains(doorway))
        XCTAssertTrue(coord.movementSets(for: golem).enemies.contains(doorway))
    }

    /// "The Inox on tile E cannot enter or pass through door 1": those of the cave, not the
    /// archers who start on the slope.
    func testTheInoxOfTheCaveStayInIt() throws {
        let sim = try simulator("73")
        let coord = sim.coord
        revealAll(sim)
        coord.updateLocks()
        let doorway = try door(sim, into: "e1b")
        let inox = coord.boardState.piecePositions.keys.sorted().filter { if case .monster(let name, _) = $0 { return name.hasPrefix("inox") }; return false }
        let inCave = inox.filter { coord.boardState.cells[coord.boardState.piecePositions[$0]!]?.tileRef.lowercased() == "e1b" }
        XCTAssertFalse(inCave.isEmpty)
        XCTAssertLessThan(inCave.count, inox.count, "Inox Archers start outside too")
        for piece in inox {
            XCTAssertEqual(coord.boardState.barredHexes(for: piece), inCave.contains(piece) ? [doorway] : [], "\(piece)")
        }
        let hound = try XCTUnwrap(coord.spawnMonster(name: "hound", type: .normal, at: try floor(sim, beside: doorway, on: "e1b"), origin: .spawned))
        XCTAssertTrue(coord.boardState.barredHexes(for: hound).isEmpty, "the door is shut to the Inox only")
    }
}
