import XCTest
@testable import GlavenGameLib

/// Noxious Cellar (#52): "The obstacles in the center room cannot be destroyed or moved through
/// in any way. They also block line of sight for ranged abilities. Characters can only start in
/// sections of the center room that contain monsters." (`ScenarioPlacements.Indestructible.solid`,
/// `startAmongMonsters`.)
@MainActor
final class SolidObstacleTests: XCTestCase {

    private func board(_ party: [String]) throws -> (gm: GameManager, coord: BoardCoordinator) {
        let gm = try SaveAndContinueTestsSupport.manager()
        for name in party { gm.characterManager.addCharacter(name: name, edition: "gh") }
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "52" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        return (gm, gm.boardCoordinator)
    }

    /// The hexes of the centre room that can be walked to from `start` without leaving it.
    private func section(_ coord: BoardCoordinator, of start: HexCoord) -> Set<HexCoord> {
        let board = coord.boardState
        var seen: Set<HexCoord> = [start]
        var frontier = [start]
        while let hex = frontier.popLast() {
            for next in board.neighbors(of: hex) where !seen.contains(next) && board.isPassable(next) && board.cells[next]?.overlay != .door {
                seen.insert(next)
                frontier.append(next)
            }
        }
        return seen
    }

    private func monsters(_ coord: BoardCoordinator) -> [HexCoord] {
        coord.boardState.piecePositions.filter { if case .monster = $0.key { return true }; return false }.map(\.value)
    }

    /// A pair of floor hexes of the centre room with one boulder hex, and nothing else, between them.
    private func acrossABoulder(_ coord: BoardCoordinator) throws -> (from: HexCoord, boulder: HexCoord, to: HexCoord) {
        let board = coord.boardState
        for boulder in board.cells.values.filter({ $0.solid == true }).map(\.coord).sorted() {
            let beside = board.neighbors(of: boulder).filter { board.cells[$0]?.overlay == nil && board.isPassable($0) }.sorted()
            for a in beside {
                for b in beside where a < b && a.distance(to: b) == 2 && a.line(to: b) == [a, boulder, b] && !section(coord, of: a).contains(b) {
                    return (a, boulder, b)
                }
            }
        }
        throw XCTSkip("no boulder with floor on two opposite sides")
    }

    /// The boulders cut the centre room into four sections with a starting hex in each; the
    /// party starts only where the monsters of its size are.
    func testCharactersStartOnlyInSectionsThatHoldMonsters() throws {
        for (party, sections) in [(["brute", "spellweaver"], 2), (["brute", "spellweaver", "cragheart"], 3),
                                  (["brute", "spellweaver", "cragheart", "scoundrel"], 4)] {
            let (gm, coord) = try board(party)
            let starts = coord.boardState.startingLocations.sorted()
            XCTAssertEqual(starts.count, 4)
            XCTAssertEqual(Set(starts.map { section(coord, of: $0) }).count, 4, "each starting hex has a section to itself")
            let foes = monsters(coord)
            let held = starts.filter { start in !section(coord, of: start).isDisjoint(with: foes) }
            XCTAssertEqual(held.count, sections, "\(party.count) characters: monsters in \(sections) sections")
            let first = gm.game.characters[0].id
            XCTAssertEqual(coord.freeStartingHexes(for: first).sorted(), held, "\(party.count) characters")

            if let empty = starts.first(where: { !held.contains($0) }) {
                coord.placeCharacter(characterID: first, at: empty)
                XCTAssertNil(coord.boardState.piecePositions[.character(first)], "no one starts in an empty section")
            }
            coord.placeCharacter(characterID: first, at: held[0])
            XCTAssertEqual(coord.boardState.piecePositions[.character(first)], held[0])
            XCTAssertEqual(coord.freeStartingHexes(for: gm.game.characters[1].id).sorted(), Array(held.dropFirst()))
        }
    }

    /// Elsewhere every free starting hex is offered, monsters or none.
    func testOtherScenariosOfferEveryStartingHex() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        gm.startScenarioOnBoard(try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil }))
        let coord = gm.boardCoordinator
        XCTAssertEqual(coord.freeStartingHexes(for: gm.game.characters[0].id).count, coord.boardState.startingLocations.count)
        XCTAssertTrue(coord.boardState.cells.values.allSatisfy { $0.solid != true })
    }

    /// "Cannot be … moved through in any way": a jump or a flight stops at them as a walk does.
    func testNothingJumpsOrFliesOverTheBoulders() throws {
        let (_, coord) = try board(["brute", "spellweaver"])
        let board = coord.boardState
        let solid = board.cells.values.filter { $0.solid == true }
        XCTAssertEqual(solid.count, 11, "every boulder hex of the centre room")
        XCTAssertTrue(solid.allSatisfy { $0.overlay == .obstacle && $0.tileRef.lowercased() == "m1a" })
        let (from, boulder, to) = try acrossABoulder(coord)
        let mine = section(coord, of: from)

        for (label, flying, jumping) in [("walking", false, false), ("jumping", false, true), ("flying", true, false)] {
            let reach = Pathfinder.reachableHexes(board: board, from: from, range: 6, flying: flying, jumping: jumping)
            XCTAssertNil(reach[to], "\(label) over \(boulder)")
            XCTAssertNil(reach[boulder], "\(label) onto \(boulder)")
            XCTAssertTrue(Set(reach.keys).isSubset(of: mine.union(board.doors.map(\.coord))), "\(label): \(Set(reach.keys).subtracting(mine))")
            XCTAssertNil(Pathfinder.findPath(board: board, from: from, to: to, flying: flying, jumping: jumping, canOpenDoors: false), label)
        }

        // An ordinary obstacle is jumped and flown over: without the rule, so are these.
        board.cells[boulder]?.solid = nil
        XCTAssertNotNil(Pathfinder.reachableHexes(board: board, from: from, range: 6, jumping: true)[to])
        XCTAssertNotNil(Pathfinder.reachableHexes(board: board, from: from, range: 6, flying: true)[boulder], "a flier hovers over an obstacle")
        XCTAssertNil(Pathfinder.reachableHexes(board: board, from: from, range: 6)[to].flatMap { $0 <= 2 ? $0 : nil })
    }

    /// "They also block line of sight for ranged abilities" — though range is counted across them.
    func testTheBouldersBlockLineOfSight() throws {
        let (gm, coord) = try board(["brute", "spellweaver"])
        let board = coord.boardState
        let (from, boulder, to) = try acrossABoulder(coord)
        XCTAssertFalse(LineOfSight.hasLOS(from: from, to: to, board: board), "\(from) sees \(to) past \(boulder)")
        XCTAssertFalse(LineOfSight.hasLOS(from: to, to: from, board: board))
        XCTAssertTrue(LineOfSight.blocksLineOfSight(boulder, board: board))
        XCTAssertEqual(board.range(from: from, to: to), 2, "range isn't counted round a boulder")
        // Within a section, sight is as anywhere.
        let near = try XCTUnwrap(section(coord, of: from).sorted().first { $0 != from && board.cells[$0]?.overlay == nil })
        XCTAssertTrue(LineOfSight.hasLOS(from: from, to: near, board: board))

        // A character on one side has no target on the other, at any range.
        let brute = PieceID.character(gm.game.characters[0].id)
        let foe = try XCTUnwrap(board.piecePositions.keys.sorted().first { if case .monster = $0 { return true }; return false })
        for piece in board.piecePositions.keys where piece != foe { board.removePiece(piece) }
        board.removePiece(foe)
        board.placePiece(brute, at: from)
        board.placePiece(foe, at: to)
        XCTAssertFalse(coord.targetableEnemies(of: brute, range: 4).contains(foe))

        // An ordinary obstacle doesn't block sight: without the rule, neither do these.
        for hex in board.cells.keys { board.cells[hex]?.solid = nil }
        XCTAssertTrue(LineOfSight.hasLOS(from: from, to: to, board: board))
        XCTAssertTrue(coord.targetableEnemies(of: brute, range: 4).contains(foe))
    }

    /// A flying figure isn't pushed onto one either.
    func testAFlyingFigureIsNotPushedOntoABoulder() throws {
        let (gm, coord) = try board(["brute", "spellweaver"])
        let board = coord.boardState
        let (from, boulder, to) = try acrossABoulder(coord)
        let brute = gm.game.characters[0]
        brute.items = ["gh-71"]
        let piece = PieceID.character(brute.id)
        XCTAssertTrue(coord.flies(piece))
        for other in board.piecePositions.keys { board.removePiece(other) }
        board.placePiece(piece, at: from)
        // Pushed from the far side of `from`, straight at the boulder.
        let pusher = try XCTUnwrap(from.neighbors.first { $0.distance(to: boulder) == 2 && $0.line(to: boulder) == [$0, from, boulder] })
        XCTAssertFalse(coord.forcedMoveSteps(for: piece, from: from, attackerPos: pusher, stepsLeft: 2, isPush: true).contains(boulder))
        board.cells[boulder]?.solid = nil
        XCTAssertTrue(coord.forcedMoveSteps(for: piece, from: from, attackerPos: pusher, stepsLeft: 2, isPush: true).contains(boulder),
                      "over an ordinary obstacle a flier is pushed (\(to) beyond it)")
    }

    /// The flag is part of the board: a turn undone or a save loaded keeps it.
    func testTheBouldersSurviveASnapshot() throws {
        let (gm, coord) = try board(["brute", "spellweaver"])
        let solid = Set(coord.boardState.cells.values.filter { $0.solid == true }.map(\.coord))
        // (Only the centre room's: the boulders and sarcophagi of the outer rooms are ordinary obstacles.)
        coord.openScenarioRooms((gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        XCTAssertEqual(coord.boardState.visibleRooms.count, 5)
        XCTAssertGreaterThan(coord.boardState.cells.values.filter { $0.overlay == .obstacle }.count, solid.count)
        XCTAssertEqual(Set(coord.boardState.cells.values.filter { $0.solid == true }.map(\.coord)), solid)
        let data = try JSONEncoder().encode(coord.boardState.cells.values.sorted { $0.coord < $1.coord })
        let cells = try JSONDecoder().decode([HexCell].self, from: data)
        XCTAssertEqual(Set(cells.filter { $0.solid == true }.map(\.coord)), solid)
        // A cell saved before the rule was built has no such key.
        let old = try JSONDecoder().decode(HexCell.self, from: Data(#"{"coord":{"col":1,"row":1},"tileRef":"m1a","passable":false,"overlay":"obstacle"}"#.utf8))
        XCTAssertNil(old.solid)
    }
}
