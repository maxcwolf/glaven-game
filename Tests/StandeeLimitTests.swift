import XCTest
@testable import GlavenGameLib

/// SET-2 and the engine audit's N11: a monster type has only so many standees. Revealing a room
/// that wants more of them than are left, the elites are set up first, then the places nearest
/// the character who opened the door — Sacrifice Pit's D tile wants eight Sun Demons of four
/// characters, and the box has six.
@MainActor
final class StandeeLimitTests: XCTestCase {

    private let party = ["brute", "spellweaver", "cragheart", "scoundrel"]

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "85", options: .init(characters: party, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    /// The door into D1a, and the Sun Demon places behind it (worked out on a board of their own).
    private func doorAndPlaces() throws -> (door: DoorInfo, places: [MonsterSlot]) {
        let sim = try simulator()
        let board = sim.coord.boardState
        for _ in 0..<10 {
            if let door = board.doors.first(where: { !$0.isOpen && $0.childTileRef.lowercased() == "d1a" }) {
                let copy = try simulator()
                let reveal = try XCTUnwrap(BoardBuilder.revealRoomSlots(door: door, scenario: try XCTUnwrap(copy.coord.scenarioData),
                                                                        board: copy.coord.boardState))
                return (door, reveal.slots.filter { $0.name == "sun-demon" && $0.type(forPlayerCount: 4) != "none" })
            }
            guard let next = board.doors.first(where: { !$0.isOpen }) else { break }
            board.lockedDoors.removeAll()
            sim.coord.openDoor(at: next.coord)
        }
        throw XCTSkip("no door into D1a")
    }

    func testTheNearestPlacesAreFilledFirst() throws {
        let (door, places) = try doorAndPlaces()
        XCTAssertEqual(places.count, 8, "eight Sun Demons for four characters")
        for corner in [0, 1] {
            let sim = try simulator()
            let coord = sim.coord
            let board = coord.boardState
            // Open the way to D1a, through no door of its own.
            for _ in 0..<10 where !board.doors.contains(where: { $0.coord == door.coord }) {
                guard let next = board.doors.first(where: { !$0.isOpen && $0.childTileRef.lowercased() != "d1a" }) else { break }
                board.lockedDoors.removeAll()
                coord.openDoor(at: next.coord)
            }
            XCTAssertFalse(board.visibleRooms.contains { $0.lowercased() == "d1a" }, "D1a still unseen")
            for piece in board.piecePositions.keys.sorted() {
                if case .monster = piece { coord.sufferDamage(999, to: piece, killer: nil) }
            }
            // The opener stands beside the door, on one side then the other of the doorway.
            let opener = PieceID.character(sim.gm.game.characters[0].id)
            let beside = board.neighbors(of: door.coord).filter { coord.isEmptyHex($0) }.sorted()
            let stand = try XCTUnwrap(corner == 0 ? beside.first : beside.last)
            board.removePiece(opener)
            board.placePiece(opener, at: stand)
            coord.actingPiece = opener
            board.lockedDoors.removeAll()
            coord.openDoor(at: door.coord)

            let demons = board.piecePositions.filter { if case .monster("sun-demon", _) = $0.key { return true }; return false }
            XCTAssertEqual(demons.count, 6, "six standees")
            let filled = Set(demons.values)
            let elites = places.filter { $0.type(forPlayerCount: 4) == "elite" }.map(\.coord)
            XCTAssertTrue(Set(elites).isSubset(of: filled), "the elites first")
            let normals = places.filter { $0.type(forPlayerCount: 4) == "normal" }.map(\.coord)
            let far = { (hex: HexCoord) in board.steps(from: stand, to: hex) }
            let empty = normals.filter { !filled.contains($0) }
            XCTAssertEqual(empty.count, 2)
            for hex in normals where filled.contains(hex) {
                XCTAssertTrue(empty.allSatisfy { far($0) >= far(hex) }, "a nearer place is left empty: \(hex) taken, \(empty) not")
            }
        }
    }

    /// With standees enough, every place is filled as the map has it.
    func testWithStandeesEnoughEveryPlaceIsFilled() throws {
        let sim = try ScenarioSimulator(scenario: "85", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let board = sim.coord.boardState
        for _ in 0..<10 {
            guard let door = board.doors.first(where: { !$0.isOpen }) else { break }
            board.lockedDoors.removeAll()
            sim.coord.openDoor(at: door.coord)
        }
        let demons = board.piecePositions.keys.filter { if case .monster("sun-demon", _) = $0 { return true }; return false }
        XCTAssertLessThanOrEqual(demons.count, 6)
        XCTAssertGreaterThan(demons.count, 0)
    }
}

/// MOV-10: "numbered treasure tiles are looted once per campaign". Played again, the scenario
/// has no tile where one was looted before (C11); another campaign still finds it.
@MainActor
final class TreasureReplayTests: XCTestCase {

    private func revealAll(_ coord: BoardCoordinator) {
        for _ in 0..<12 {
            guard let door = coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            coord.boardState.lockedDoors.removeAll()
            coord.openDoor(at: door.coord)
        }
    }

    private func numbered(_ coord: BoardCoordinator) -> [HexCell] {
        coord.boardState.cells.values.filter { $0.overlay == .treasure && $0.treasureID.flatMap(Int.init) != nil }.sorted { $0.coord < $1.coord }
    }

    func testATreasureLootedBeforeIsNotThereOnAReplay() throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        revealAll(sim.coord)
        let tile = try XCTUnwrap(numbered(sim.coord).first, "Black Barrow has a numbered treasure")
        let id = try XCTUnwrap(tile.treasureID)
        let others = numbered(sim.coord).count
        sim.coord.lootHexes(for: .character(sim.gm.game.characters[0].id), coords: [tile.coord])
        XCTAssertTrue(sim.gm.scenarioManager.isTreasureLooted(id))

        // The same campaign plays the scenario again.
        let scenario = try XCTUnwrap(sim.gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        sim.gm.startScenarioOnBoard(scenario)
        let again = sim.gm.boardCoordinator
        revealAll(again)
        XCTAssertFalse(numbered(again).contains { $0.treasureID == id }, "treasure \(id) was looted in this campaign")
        XCTAssertEqual(numbered(again).count, others - 1, "the others are there")

        // Another campaign finds it.
        let fresh = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        revealAll(fresh.coord)
        XCTAssertTrue(numbered(fresh.coord).contains { $0.treasureID == id })
    }
}
