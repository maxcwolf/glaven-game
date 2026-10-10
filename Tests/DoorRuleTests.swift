import XCTest
@testable import GlavenGameLib

/// Doors (GH p.14): a character moving onto a closed door opens it, the room beyond is set up at
/// once, and the character goes on with the movement they have left.
@MainActor
final class DoorRuleTests: XCTestCase {

    private func settle(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    /// Black Barrow with the Brute two hexes from door 1 and a Move 4 to make.
    private func bruteBeforeTheDoor() throws -> (sim: ScenarioSimulator, brute: GameCharacter, turn: PlayerTurnController, door: HexCoord) {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 4, autoResolvePrompts: true))
        let coord = sim.coord
        let brute = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "brute" })
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen }).coord
        // The hex two steps back from the door, in the first room.
        let before = try XCTUnwrap(door.neighbors.first { coord.boardState.cells[$0] != nil && !coord.boardState.isOccupied($0) })
        let start = try XCTUnwrap(before.neighbors.first {
            coord.boardState.cells[$0] != nil && !coord.boardState.isOccupied($0) && $0 != door && $0.distance(to: door) == 2
        })
        coord.boardState.movePiece(.character(brute.id), to: start)
        let deck = sim.gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let grab = try XCTUnwrap(deck.first { $0.name == "Grab and Go" })      // bottom: Move 4
        let other = try XCTUnwrap(deck.first { $0.name == "Trample" })
        brute.handCards = [other.cardId!, grab.cardId!]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: grab)
        turn.setBottomFirst(true)
        return (sim, brute, turn, door)
    }

    func testACharacterWhoOpensADoorGoesOnWithTheMovementLeft() async throws {
        let (sim, brute, turn, door) = try bruteBeforeTheDoor()
        let coord = sim.coord
        let me = PieceID.character(brute.id)
        let cellsBefore = coord.boardState.cells.count
        turn.executeCurrentAction()
        guard case .selectingMove(_, 4, let hexes, _, _) = coord.interactionMode else { return XCTFail("Move 4") }
        XCTAssertTrue(hexes.contains(door), "the door is within reach")
        coord.handleHexTap(door)
        await settle(coord.continuedMove != nil)

        XCTAssertTrue(coord.boardState.doors.first { $0.coord == door }?.isOpen == true, "the door is open")
        XCTAssertGreaterThan(coord.boardState.cells.count, cellsBefore, "and the room beyond is on the board")
        guard case .selectingMove(let mover, let left, let onward, _, _) = coord.interactionMode else {
            return XCTFail("the move goes on, got \(coord.interactionMode)")
        }
        XCTAssertEqual(mover, me)
        XCTAssertEqual(left, 2, "two of the four movement points were spent reaching the door")
        XCTAssertTrue(onward.contains(door), "stopping in the doorway is allowed")
        XCTAssertTrue(turn.isWaiting, "the Move isn't over")
        let beyond = try XCTUnwrap(onward.filter { $0.distance(to: door) == 2 }.sorted().first, "a hex two steps into the new room")

        coord.handleHexTap(beyond)
        await settle(!turn.isWaiting)
        XCTAssertEqual(coord.boardState.piecePositions[me], beyond)
        XCTAssertEqual(turn.hexesMoved, 4, "one move of four hexes")
        XCTAssertNil(coord.continuedMove)
        XCTAssertEqual(sim.violations, [])
    }

    /// The rest of the move may be left: Skip stops in the doorway.
    func testTheRestOfTheMoveCanBeLeftInTheDoorway() async throws {
        let (sim, brute, turn, door) = try bruteBeforeTheDoor()
        let coord = sim.coord
        turn.executeCurrentAction()
        coord.handleHexTap(door)
        await settle(coord.continuedMove != nil)
        turn.skipCurrentAction()
        await settle(!turn.isWaiting)
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], door)
        XCTAssertEqual(turn.hexesMoved, 2)
        XCTAssertNil(coord.continuedMove)
        XCTAssertFalse(turn.isWaiting)
    }
}
