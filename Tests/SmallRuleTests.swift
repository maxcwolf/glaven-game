import XCTest
@testable import GlavenGameLib

/// Slave Pens (#38): the Orchid "performs Move 3 toward the shaman on the D tile, opening doors
/// and springing traps if needed" (`ScenarioPlacements.seeks`).
@MainActor
final class OrchidTests: XCTestCase {

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "38", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func orchid(_ sim: ScenarioSimulator) throws -> (container: GameObjectiveContainer, piece: PieceID) {
        let container = try XCTUnwrap(sim.gm.game.objectives.first { $0.escort })
        let entity = try XCTUnwrap(container.entities.first)
        return (container, .objective(id: entity.number))
    }

    private func shamans(_ sim: ScenarioSimulator, on tile: String) -> [PieceID] {
        sim.coord.boardState.piecePositions.filter { piece, hex in
            guard case .monster("inox-shaman", _) = piece else { return false }
            return sim.coord.boardState.cells[hex]?.tileRef.lowercased() == tile
        }.map(\.key).sorted()
    }

    private func turn(_ sim: ScenarioSimulator) async throws {
        let (container, _) = try orchid(sim)
        await EscortTurnController(coordinator: sim.coord, gameManager: sim.gm).executeEscortTurns(for: container)
    }

    /// Before the D tile is seen he makes for the doors on the way to it, and opens them.
    func testHeMakesForTheDoorsOnTheWayToTheDTile() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        for monster in coord.boardState.piecePositions.keys.sorted() {
            if case .monster = monster { coord.sufferDamage(999, to: monster, killer: .character(sim.gm.game.characters[0].id)) }
        }
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen })
        XCTAssertEqual(controller.destination(of: container, from: coord.boardState.piecePositions[piece]), [door.coord])
        var turns = 0
        while !coord.boardState.visibleRooms.contains(where: { $0.lowercased() == "a4a" }), turns < 6 {
            try await turn(sim)
            turns += 1
        }
        XCTAssertTrue(coord.boardState.visibleRooms.contains { $0.lowercased() == "a4a" }, "he walked into the door and opened it")
    }

    /// With the D tile in sight he heads for its shaman — not for a nearer enemy, nor the shaman
    /// of the M tile — and stops beside him.
    func testHeHeadsForTheShamanOnTheDTile() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        let target = try XCTUnwrap(shamans(sim, on: "d1b").first)
        XCTAssertFalse(shamans(sim, on: "m1b").isEmpty, "a shaman on the M tile too")
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        let goal = try XCTUnwrap(coord.boardState.piecePositions[target])
        XCTAssertEqual(controller.destination(of: container, from: coord.boardState.piecePositions[piece]), [goal])

        // Every other monster out of his way; none of them draws him.
        for monster in coord.boardState.piecePositions.keys.sorted() where monster != target {
            if case .monster = monster { coord.removePieceFromBoard(monster) }
        }
        var last = try XCTUnwrap(coord.boardState.piecePositions[piece])
        for _ in 0..<20 {
            try await turn(sim)
            let now = try XCTUnwrap(coord.boardState.piecePositions[piece])
            if now == last { break }
            XCTAssertLessThan(coord.boardState.steps(from: now, to: goal), coord.boardState.steps(from: last, to: goal), "each move nearer")
            XCTAssertLessThanOrEqual(last.distance(to: now), 3)
            last = now
        }
        XCTAssertTrue(coord.boardState.areAdjacent(last, goal), "he ends beside the shaman")
    }

    /// Once the D tile's shaman is dead he has nowhere to go: he stays.
    func testWithTheShamanDeadHeStays() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        for shaman in shamans(sim, on: "d1b") { coord.sufferDamage(999, to: shaman, killer: .character(sim.gm.game.characters[0].id)) }
        let here = try XCTUnwrap(coord.boardState.piecePositions[piece])
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        XCTAssertEqual(controller.destination(of: container, from: here), [here])
        try await turn(sim)
        XCTAssertEqual(coord.boardState.piecePositions[piece], here)
    }
}
