import XCTest
import SwiftData
@testable import GlavenGameLib

/// Obstacles a character creates (GH p.15): never where one would cut one area of the map off
/// from another — whether or not anyone could fly or jump over it.
@MainActor
final class ObstaclePlacementRuleTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        coord.autoResolvePrompts = true
    }

    /// Two rooms three hexes wide joined by a neck one hex wide at (3,1).
    private func twoRoomsAndANeck() -> BoardState {
        let board = makeBoard(cols: 7, rows: 3)
        for row in [0, 2] { board.cells[HexCoord(3, row)] = nil }
        return board
    }

    func testAnObstacleInTheNeckBetweenTwoRoomsWouldDivideTheMap() {
        let board = twoRoomsAndANeck()
        XCTAssertTrue(board.obstacleWouldDivideMap(at: HexCoord(3, 1)), "the only way between the rooms")
        XCTAssertFalse(board.obstacleWouldDivideMap(at: HexCoord(1, 1)), "the middle of a room")
        XCTAssertFalse(board.obstacleWouldDivideMap(at: HexCoord(0, 0)), "a corner")
        // With a second way round, the neck may be blocked.
        board.cells[HexCoord(3, 2)] = HexCell(coord: HexCoord(3, 2), tileRef: "test", passable: true)
        XCTAssertFalse(board.obstacleWouldDivideMap(at: HexCoord(3, 1)))
        // An obstacle already standing in that second way closes it again.
        board.placeObstacle(at: HexCoord(3, 2))
        XCTAssertTrue(board.obstacleWouldDivideMap(at: HexCoord(3, 1)))
    }

    /// The hex in front of a closed door is the way into the room behind it.
    func testAnObstacleMayNotSealADoor() {
        let board = BoardState()
        for col in 0..<4 { for row in 0..<3 { board.cells[HexCoord(col, row)] = HexCell(coord: HexCoord(col, row), tileRef: "test", passable: true) } }
        // A door hex sticking out of the room, reached only from (3,1)… and its two row-mates.
        let door = HexCoord(4, 1)
        board.cells[door] = HexCell(coord: door, tileRef: "test", passable: true)
        board.cells[door]?.overlay = .door
        board.doors = [DoorInfo(coord: door, childTileRef: "next", subType: "stone", refPoint: HexCoord(0, 0), origin: HexCoord(0, 0))]
        let before = board.neighbors(of: door).filter { board.cells[$0] != nil }
        XCTAssertFalse(before.isEmpty)
        if before.count == 1 {
            XCTAssertTrue(board.obstacleWouldDivideMap(at: before[0]))
        } else {
            // Close all but one approach: the last one may not be blocked.
            for hex in before.dropLast() { board.placeObstacle(at: hex) }
            XCTAssertTrue(board.obstacleWouldDivideMap(at: before[before.count - 1]), "the last way to the door")
        }
    }

    /// The hexes offered for a created obstacle leave out the one that would divide the map.
    func testTheNeckIsNotOfferedForACreatedObstacle() throws {
        coord.boardState = twoRoomsAndANeck()
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let me = PieceID.character(try XCTUnwrap(gm.game.characters.last).id)
        coord.boardState.placePiece(me, at: HexCoord(2, 1))
        XCTAssertTrue(coord.beginPlacingTokens(.obstacle, count: 1, by: me))
        guard case .placingToken(_, _, _, let hexes) = coord.interactionMode else { return XCTFail("placing an obstacle") }
        XCTAssertFalse(hexes.contains(HexCoord(3, 1)), "not the neck")
        XCTAssertFalse(hexes.isEmpty, "the hexes of the room are offered")
        XCTAssertTrue(hexes.allSatisfy { HexCoord(2, 1).isAdjacent(to: $0) })
        // A trap is no obstacle: it may go in the neck.
        coord.interactionMode = .idle
        XCTAssertTrue(coord.beginPlacingTokens(.trap(damage: 2, subType: nil, experience: 0), count: 1, by: me))
        guard case .placingToken(_, _, _, let trapHexes) = coord.interactionMode else { return XCTFail("placing a trap") }
        XCTAssertTrue(trapHexes.contains(HexCoord(3, 1)))
    }
}
