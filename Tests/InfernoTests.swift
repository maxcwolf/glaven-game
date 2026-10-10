import XCTest
@testable import GlavenGameLib

/// Inferno (Spellweaver, level 9): "Attack 3. Target all enemies in the same room as you. … All
/// allies in the same room as you suffer 2 damage." A room is what walls and doorways bound;
/// every attack still needs line of sight, and with no range printed it is a melee attack (FAQ).
@MainActor
final class InfernoTests: XCTestCase {

    private func settle(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    private struct Table {
        let sim: ScenarioSimulator
        let weaver: GameCharacter
        let brute: GameCharacter
        let turn: PlayerTurnController
        var coord: BoardCoordinator { sim.coord }
        var me: PieceID { .character(weaver.id) }
    }

    /// Black Barrow with both rooms open, every monster hardy, and Inferno in the Spellweaver's hand.
    private func table() throws -> Table {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["spellweaver", "brute"], seed: 3, autoResolvePrompts: true))
        let coord = sim.coord
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen }).coord
        coord.openDoor(at: door)
        for monster in sim.gm.game.monsters { for entity in monster.entities { entity.maxHealth = 40; entity.health = 40; entity.shield = nil } }
        let weaver = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "spellweaver" })
        let brute = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "brute" })
        let deck = sim.gm.editionStore.abilities(forDeck: "spellweaver", edition: "gh")
        let inferno = try XCTUnwrap(deck.first { $0.name == "Inferno" })
        let other = try XCTUnwrap(deck.first { $0.name == "Mana Bolt" })
        weaver.handCards = [inferno.cardId!, other.cardId!]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: weaver.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: inferno, bottom: other)
        return Table(sim: sim, weaver: weaver, brute: brute, turn: turn)
    }

    private func monsters(_ t: Table) -> [PieceID] {
        t.coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
    }

    private func attacked(_ t: Table) -> Set<String> {
        Set(t.coord.turnLog.map(\.message).filter { $0.hasPrefix("Spellweaver attacks ") }
            .compactMap { $0.dropFirst("Spellweaver attacks ".count).split(separator: ":").first.map(String.init) })
    }

    func testARoomIsBoundedByItsWallsAndDoorways() throws {
        let t = try table()
        let board = t.coord.boardState
        let here = try XCTUnwrap(board.piecePositions[t.me])
        let room = board.room(of: here)
        let door = try XCTUnwrap(board.doors.first).coord
        XCTAssertEqual(Set(room.compactMap { board.cells[$0]?.tileRef }).count, 1, "one tile: the first room")
        XCTAssertFalse(room.contains(door), "the doorway is in neither room")
        XCTAssertEqual(board.room(of: door), [], "and a figure in it is in no room")
        let beyond = try XCTUnwrap(board.neighbors(of: door).first { board.cells[$0] != nil && !room.contains($0) })
        XCTAssertTrue(board.room(of: beyond).isDisjoint(with: room))
    }

    func testInfernoAttacksEveryEnemyInTheRoomAndNoneBeyondIt() async throws {
        let t = try table()
        let board = t.coord.boardState
        let room = board.room(of: try XCTUnwrap(board.piecePositions[t.me]))
        let inside = monsters(t).filter { room.contains(board.piecePositions[$0]!) }
        let outside = monsters(t).filter { !room.contains(board.piecePositions[$0]!) }
        XCTAssertGreaterThan(inside.count, 1, "several enemies share the room, most of them not adjacent")
        XCTAssertFalse(outside.isEmpty, "and others stand in the next room")
        XCTAssertEqual(Set(t.coord.enemiesInRoom(of: t.me)), Set(inside), "all in the room are in sight")

        t.turn.executeCurrentAction()
        await settle(!t.turn.isWaiting)
        XCTAssertEqual(attacked(t), Set(inside.map(t.coord.name)), "one attack on each enemy in the room")
        XCTAssertEqual(t.sim.violations, [])
    }

    func testInfernoHurtsAlliesInTheRoomOnly() async throws {
        // The Brute starts in the same room.
        var t = try table()
        var before = t.brute.health
        t.turn.executeCurrentAction()
        await settle(!t.turn.isWaiting)
        XCTAssertEqual(t.brute.health, before - 2, "an ally in the room suffers 2 damage")
        XCTAssertEqual(t.weaver.health, t.weaver.maxHealth, "the Spellweaver herself doesn't")

        // In the next room he is spared.
        t = try table()
        let board = t.coord.boardState
        let room = board.room(of: try XCTUnwrap(board.piecePositions[t.me]))
        let away = try XCTUnwrap(board.cells.keys.sorted().first { !room.contains($0) && board.isPassable($0) && !board.isOccupied($0) && board.cells[$0]?.overlay == nil })
        board.piecePositions[.character(t.brute.id)] = away
        before = t.brute.health
        t.turn.executeCurrentAction()
        await settle(!t.turn.isWaiting)
        XCTAssertEqual(t.brute.health, before)
    }

    /// From a doorway the Spellweaver is in no room: Inferno reaches no one.
    func testInfernoFromADoorwayReachesNoOne() async throws {
        let t = try table()
        let board = t.coord.boardState
        let door = try XCTUnwrap(board.doors.first).coord
        for piece in board.pieces(at: door) { t.coord.removePieceFromBoard(piece) }
        board.piecePositions[t.me] = door
        let before = t.brute.health
        XCTAssertEqual(t.coord.enemiesInRoom(of: t.me), [])
        t.turn.executeCurrentAction()
        await settle(!t.turn.isWaiting)
        XCTAssertEqual(attacked(t), [])
        XCTAssertEqual(t.brute.health, before)
    }
}
