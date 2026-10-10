import XCTest
@testable import GlavenGameLib

/// #90 Demonic Rift (scenario book p.113): two rooms that lie apart, joined only by their altars.
/// A character beside one altar may spend 1 movement to stand beside the other; summons and
/// monsters can't. The Living Spirits come when every demon is dead and a character stands in
/// each room; the left room may never be empty, nor the right one once the spirits have come,
/// and the scenario is lost when only one character is left.
@MainActor
final class DemonicRiftTests: XCTestCase {

    private let rightRoom: Set<String> = ["d1b", "c2a"]

    private func rift(characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "90", options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func settle(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    private func monsters(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    private func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func tile(_ sim: ScenarioSimulator, _ piece: PieceID) -> String? {
        sim.coord.boardState.piecePositions[piece].flatMap { sim.coord.boardState.cells[$0]?.tileRef.lowercased() }
    }

    /// The empty hexes beside the right-hand altar.
    private func farSide(_ sim: ScenarioSimulator) -> [HexCoord] {
        let board = sim.coord.boardState
        return board.neighbors(of: board.crossings[1]).filter { board.isPassable($0) && !board.isOccupied($0) }.sorted()
    }

    /// Put a character across, beside the right-hand altar.
    private func cross(_ sim: ScenarioSimulator, _ piece: PieceID) throws {
        sim.coord.boardState.piecePositions[piece] = try XCTUnwrap(farSide(sim).first)
    }

    func testBothRoomsAreSetUpWithOnlyTheAltarsBetweenThem() throws {
        let sim = try rift()
        let board = sim.coord.boardState
        XCTAssertTrue(board.doors.isEmpty, "the altar is no door")
        XCTAssertEqual(Set(board.cells.values.map { $0.tileRef.lowercased() }), ["m1b", "d1b", "c2a"], "the whole map is laid out")
        XCTAssertEqual(board.crossings.compactMap { board.cells[$0]?.tileRef.lowercased() }, ["m1b", "d1b"], "an altar in each room")
        for altar in board.crossings {
            XCTAssertEqual(board.cells[altar]?.overlay, .obstacle)
            XCTAssertFalse(board.isPassable(altar), "no one stands on an altar")
            XCTAssertFalse(sim.coord.isDestructibleObstacle(altar), "nor destroys one")
        }
        XCTAssertEqual(board.markerHexes["a"].map(Set.init), Set(board.crossings), "the book's (a)")
        XCTAssertEqual(sim.gm.game.scenario?.revealedRooms.sorted(), [1, 2])
        let there = monsters(sim).filter { rightRoom.contains(tile(sim, $0) ?? "") }
        XCTAssertEqual(there.count, 3, "two Night Demons and a Wind Demon wait in the right room (2 characters)")
        XCTAssertEqual(monsters(sim, named: "night-demon").count, 2)
        // Nothing reaches from room to room: not range, not sight.
        let here = try XCTUnwrap(board.piecePositions[character(sim, 0)])
        for piece in there {
            let hex = try XCTUnwrap(board.piecePositions[piece])
            XCTAssertNil(board.range(from: hex, to: here))
            XCTAssertFalse(LineOfSight.hasLOS(from: hex, to: here, board: board))
        }
    }

    func testACharacterBesideOneAltarStepsBesideTheOtherForOneMovement() async throws {
        let sim = try rift()
        let coord = sim.coord
        let board = coord.boardState
        let me = character(sim, 0)
        let from = try XCTUnwrap(board.markerHexes["b"]?.sorted().first, "a hex beside the left altar")
        for piece in board.pieces(at: from) { coord.removePieceFromBoard(piece) }
        board.piecePositions[me] = from
        XCTAssertTrue(board.areAdjacent(from, board.crossings[0]))
        let exits = Set(farSide(sim))
        XCTAssertGreaterThanOrEqual(exits.count, 2)

        let enemies = Set(monsters(sim).compactMap { board.piecePositions[$0] })
        let reach = Pathfinder.reachableHexes(board: board, from: from, range: 1, occupiedByEnemy: enemies)
        for exit in exits { XCTAssertEqual(reach[exit], 1, "\(exit) is one movement away") }
        let twoBack = try XCTUnwrap(board.neighbors(of: from).first { board.isPassable($0) && !board.areAdjacent($0, board.crossings[0]) && !board.isOccupied($0) })
        XCTAssertEqual(Pathfinder.pathCost(board: board, from: twoBack, to: try XCTUnwrap(exits.sorted().first), occupiedByEnemy: enemies), 2,
                       "a step to the altar and one across")

        // A summon or a monster can't cross, whatever its Move.
        let onFoot = Pathfinder.reachableHexes(board: board, from: from, range: 30, canOpenDoors: false, occupiedByEnemy: enemies)
        XCTAssertTrue(exits.isDisjoint(with: onFoot.keys))
        let flying = Pathfinder.reachableHexes(board: board, from: from, range: 30, mode: .fly, canOpenDoors: false)
        XCTAssertTrue(exits.isDisjoint(with: flying.keys))

        // On the board: a Move 1 offers the hexes across, and takes the character there.
        coord.boardPhase = .execution
        coord.beginMoveAction(pieceID: me, moveRange: 1)
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("a Move to make") }
        XCTAssertTrue(exits.isSubset(of: hexes))
        let exit = try XCTUnwrap(exits.sorted().first)
        coord.handleHexTap(exit)
        await settle(board.piecePositions[me] == exit)
        XCTAssertEqual(board.piecePositions[me], exit)
        XCTAssertTrue(rightRoom.contains(tile(sim, me) ?? ""))
        XCTAssertEqual(sim.violations, [])
    }

    func testTheSpiritsComeWhenTheDemonsAreDeadAndACharacterStandsInEachRoom() throws {
        let sim = try rift()
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertTrue(monsters(sim, named: "living-spirit").isEmpty)
        for piece in monsters(sim) { sim.coord.handleDeath(of: piece) }
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertTrue(monsters(sim, named: "living-spirit").isEmpty, "every demon is dead, but no one is in the right room")
        XCTAssertNil(sim.coord.pendingResult)

        try cross(sim, character(sim, 1))
        sim.gm.scenarioRulesManager.evaluateRules()
        let spirits = monsters(sim, named: "living-spirit")
        XCTAssertEqual(spirits.count, 4, "two at (b), two at (c)")
        XCTAssertEqual(Set(spirits.compactMap { tile(sim, $0) }), ["m1b", "d1b"])
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult)
        for piece in monsters(sim) { sim.coord.handleDeath(of: piece) }
        XCTAssertEqual(sim.coord.pendingResult, .victory, "the rift is closed")
    }

    func testTheLeftRoomMayNeverBeEmpty() throws {
        let sim = try rift()
        XCTAssertNotEqual(sim.coord.boardPhase, .setup)
        try cross(sim, character(sim, 0))
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "one has crossed, one stays")
        try cross(sim, character(sim, 1))
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    func testTheRightRoomMayNotBeEmptyOnceTheSpiritsHaveCome() throws {
        let sim = try rift()
        let home = try XCTUnwrap(sim.coord.boardState.piecePositions[character(sim, 1)])
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "before the spirits, everyone may be in the left room")
        for piece in monsters(sim) { sim.coord.handleDeath(of: piece) }
        try cross(sim, character(sim, 1))
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertEqual(monsters(sim, named: "living-spirit").count, 4)
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult)
        for piece in sim.coord.boardState.pieces(at: home) { sim.coord.removePieceFromBoard(piece) }
        sim.coord.boardState.piecePositions[character(sim, 1)] = home
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    func testOnlyOneCharacterLeftLosesTheScenario() throws {
        let sim = try rift(characters: ["brute", "spellweaver", "cragheart"])
        sim.gm.game.characters[2].exhausted = true
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "two are left")
        sim.gm.game.characters[1].exhausted = true
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }
}
