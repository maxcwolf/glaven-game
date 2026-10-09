import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Opening a door draws the new room into the board as it stands: nothing already there is
/// redrawn or moved, effects in flight carry on, and the result is the same board a full
/// rebuild would draw.
@MainActor
final class RoomRevealTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    private func start(_ index: String) throws -> BoardScene {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
        coord.placeCharacter(characterID: gm.game.characters[0].id, at: free)
        return try XCTUnwrap(coord.boardScene)
    }

    private var brute: PieceID { .character(gm.game.characters[0].id) }

    private func openFirstDoor() throws {
        let door = try XCTUnwrap(coord.boardState.doors.sorted { $0.coord < $1.coord }.first { !$0.isOpen })
        coord.openDoor(at: door.coord)
    }

    /// The tokens already on the board are the same tokens after the door opens, in the same
    /// places, and a damage number in flight is still showing.
    func testOpeningADoorLeavesTheBoardAsItWas() throws {
        let scene = try start("1")
        let before = Dictionary(uniqueKeysWithValues: coord.boardState.piecePositions.keys.map { ($0, scene.pieceNode(for: $0)!) })
        let positions = before.mapValues(\.position)
        scene.floatText("\u{2212}2", over: brute, style: .damage)

        try openFirstDoor()
        XCTAssertGreaterThan(scene.drawnRooms.count, 1, "a room opened")
        for (piece, node) in before {
            XCTAssertTrue(scene.pieceNode(for: piece) === node, "\(piece) keeps its token")
            XCTAssertEqual(node.position, positions[piece], "\(piece) doesn't move")
        }
        XCTAssertEqual(scene.floatingTexts(over: brute), ["\u{2212}2"], "the number in flight survives")
    }

    /// After every door has opened, the board holds exactly what a full rebuild would draw.
    func testRevealedRoomsMatchAFullRebuild() throws {
        for index in ["1", "2", "6", "21", "32"] {
            let scene = try start(index)
            var opened = 0
            while coord.boardState.doors.contains(where: { !$0.isOpen }), opened < 30 {
                try openFirstDoor()
                opened += 1
            }
            XCTAssertEqual(scene.drawnRooms, coord.boardState.visibleRooms, "scenario \(index): every room's tiles")
            let overlays = scene.overlaySpriteNames.sorted()
            let tokens = coord.boardState.piecePositions.keys.sorted().map { scene.pieceNode(for: $0)?.position }
            XCTAssertFalse(tokens.contains(nil), "scenario \(index): every figure has a token")

            coord.restore(from: coord.snapshot())   // a full rebuild of the same board
            XCTAssertEqual(scene.overlaySpriteNames.sorted(), overlays, "scenario \(index): the same overlays")
            XCTAssertEqual(coord.boardState.piecePositions.keys.sorted().map { scene.pieceNode(for: $0)?.position },
                           tokens, "scenario \(index): the same tokens in the same places")
        }
    }
}
