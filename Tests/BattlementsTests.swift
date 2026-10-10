import XCTest
@testable import GlavenGameLib

/// #35 Gloomhaven Battlements A (scenario book p.46): the City Archers grouped at (a) and (b), on
/// the battlements behind the gate, are set up at the start; the other enemies on the tiles
/// behind it are not, until the gate is destroyed or a character or ally gets onto those tiles.
@MainActor
final class BattlementsTests: XCTestCase {

    private let yard: Set<String> = ["i1b", "b2b"]

    private func battlements(_ characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "35", options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func monsters(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    private func tile(_ sim: ScenarioSimulator, _ piece: PieceID) -> String {
        sim.coord.boardState.piecePositions[piece].flatMap { sim.coord.boardState.cells[$0]?.tileRef.lowercased() } ?? ""
    }

    private func inYard(_ sim: ScenarioSimulator) -> [PieceID] { monsters(sim).filter { yard.contains(tile(sim, $0)) } }

    private func gate(_ sim: ScenarioSimulator) throws -> PieceID {
        try XCTUnwrap(sim.coord.boardState.piecePositions.keys.first { if case .objective = $0 { return true }; return false })
    }

    func testTheArchersStandOnTheBattlementsFromTheStart() throws {
        for (party, archers) in [(["brute", "spellweaver"], 2), (["brute", "spellweaver", "cragheart"], 4),
                                 (["brute", "spellweaver", "cragheart", "scoundrel"], 4)] {
            let sim = try battlements(party)
            let board = sim.coord.boardState
            XCTAssertEqual(Set(board.cells.values.map { $0.tileRef.lowercased() }), ["l1b", "l3a", "i1b", "b2b"], "the whole map is laid out")
            XCTAssertEqual(sim.gm.game.scenario?.revealedRooms, [1], "but the yard isn't revealed")
            XCTAssertTrue(board.doors.allSatisfy { !$0.isOpen }, "the gate is shut")
            let lettered = Set((board.markerHexes["a"] ?? []) + (board.markerHexes["b"] ?? []))
            XCTAssertEqual(lettered.count, 4)
            let there = inYard(sim)
            XCTAssertEqual(there.count, archers, "\(party.count) characters: only the archers of (a) and (b) are behind the wall")
            for piece in there {
                guard case .monster("city-archer", _) = piece else { XCTFail("\(piece) is set up too early"); continue }
                XCTAssertTrue(lettered.contains(board.piecePositions[piece]!), "\(piece) stands on a lettered hex")
            }
            XCTAssertEqual(monsters(sim, named: "city-archer").count, archers, "none stands outside the wall")
            XCTAssertTrue(monsters(sim, named: "captain-of-the-guard").isEmpty)
        }
    }

    /// The wall sections are obstacles, not walls: the archers shoot over them.
    func testTheArchersSeeOverTheWall() throws {
        let sim = try battlements()
        let board = sim.coord.boardState
        let archer = try XCTUnwrap(inYard(sim).first)
        let from = try XCTUnwrap(board.piecePositions[archer])
        let outside = try XCTUnwrap(board.cells.keys.sorted().first {
            !yard.contains(board.cells[$0]!.tileRef.lowercased()) && board.isPassable($0) && $0.distance(to: from) == 3
        })
        XCTAssertTrue(LineOfSight.hasLOS(from: from, to: outside, board: board), "\(from) sees \(outside) across the wall section")
        XCTAssertEqual(board.range(from: from, to: outside), 3, "and range is counted over it")
        XCTAssertNil(Pathfinder.findPath(board: board, from: from, to: outside, canOpenDoors: false), "though no one walks through")
    }

    func testTheRestAreSetUpWhenTheGateIsDestroyed() throws {
        let sim = try battlements()
        let onTheBattlements = Set(inYard(sim))
        let places = Dictionary(uniqueKeysWithValues: onTheBattlements.map { ($0, sim.coord.boardState.piecePositions[$0]!) })
        sim.coord.sufferDamage(999, to: try gate(sim))
        XCTAssertEqual(sim.gm.game.scenario?.revealedRooms.sorted(), [1, 2])
        XCTAssertTrue(sim.coord.boardState.doors.allSatisfy(\.isOpen), "the gate is open")
        XCTAssertEqual(monsters(sim, named: "captain-of-the-guard").count, 1)
        for (piece, hex) in places { XCTAssertEqual(sim.coord.boardState.piecePositions[piece], hex, "\(piece) stays where it stood") }
        let newcomers = inYard(sim).filter { !onTheBattlements.contains($0) }
        // Two characters: the Captain, two elite archers and three guards wait in the yard.
        XCTAssertEqual(newcomers.count, 6)
        XCTAssertEqual(monsters(sim, named: "city-archer").count, 4)
        let lettered = Set((sim.coord.boardState.markerHexes["a"] ?? []) + (sim.coord.boardState.markerHexes["b"] ?? []))
        for piece in newcomers {
            XCTAssertFalse(lettered.contains(sim.coord.boardState.piecePositions[piece]!), "\(piece) isn't put on the battlements")
        }
    }

    func testTheRestAreSetUpWhenACharacterGetsOverTheWall() async throws {
        let sim = try battlements()
        let coord = sim.coord
        let board = coord.boardState
        let me = PieceID.character(sim.gm.game.characters[0].id)
        // A wall section with an empty hex outside it and one in the yard behind it.
        let section = try XCTUnwrap(board.cells.keys.sorted().first { hex in
            board.cells[hex]?.overlaySubType == "wall-section"
                && board.neighbors(of: hex).contains { !self.yard.contains(board.cells[$0]?.tileRef.lowercased() ?? "x") && board.isPassable($0) && !board.isOccupied($0) && board.cells[$0]?.overlay == nil }
                && board.neighbors(of: hex).contains { self.yard.contains(board.cells[$0]?.tileRef.lowercased() ?? "x") && board.isPassable($0) && !board.isOccupied($0) }
        })
        let outside = board.neighbors(of: section).first { !yard.contains(board.cells[$0]?.tileRef.lowercased() ?? "x") && board.isPassable($0) && !board.isOccupied($0) && board.cells[$0]?.overlay == nil }!
        let inside = board.neighbors(of: section).first { yard.contains(board.cells[$0]?.tileRef.lowercased() ?? "x") && board.isPassable($0) && !board.isOccupied($0) }!
        board.piecePositions[me] = outside
        coord.boardPhase = .execution
        XCTAssertNil(Pathfinder.findPath(board: board, from: outside, to: inside, maxCost: 2), "no walking over the wall")
        let leap = try XCTUnwrap(Pathfinder.findPath(board: board, from: outside, to: inside, mode: .jump, maxCost: 2), "but a Jump clears it")
        XCTAssertEqual(leap, [outside, section, inside])

        _ = await coord.moveAlong(me, path: leap, style: .jump)
        XCTAssertEqual(board.piecePositions[me], inside)
        XCTAssertEqual(sim.gm.game.scenario?.revealedRooms.sorted(), [1, 2], "the yard is set up")
        XCTAssertEqual(monsters(sim, named: "captain-of-the-guard").count, 1)
        XCTAssertTrue(board.doors.allSatisfy { !$0.isOpen }, "the gate still stands")
        XCTAssertNil(coord.pendingResult)
        XCTAssertNotNil(board.piecePositions[try gate(sim)], "and is still to be destroyed")
    }
}
