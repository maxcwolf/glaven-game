import XCTest
@testable import GlavenGameLib

/// Cards that print a second ability under their Move — the card data has it inside the Move —
/// perform both: the Move, then the ability (N18). Each card as its scan prints it.
@MainActor
final class MoveThenAbilityTests: XCTestCase {

    private var board: RuleBoard!
    private let here = HexCoord(5, 5)

    override func setUp() async throws {
        board = try RuleBoard()
    }

    /// Play `name`'s bottom half with `character`: the Move is skipped (staying put), and what
    /// follows is performed. Returns the turn, left where it waits for a choice (or done).
    private func playBottom(_ name: String, other: String, for character: GameCharacter) throws -> PlayerTurnController {
        board.play(try board.card(other, of: character.name), try board.card(name, of: character.name), for: character)
        board.startTurns([TurnOrderEntry(figure: .character(character), initiative: 10)])
        let turn = try XCTUnwrap(board.coord.activePlayerTurn)
        turn.setBottomFirst(true)
        XCTAssertEqual(turn.bottomActions.first?.type, .move)
        turn.executeCurrentAction()
        guard case .selectingMove = board.coord.interactionMode else { XCTFail("the Move comes first"); return turn }
        turn.skipCurrentAction()
        var steps = 0
        while turn.phase == .executeBottomAction, !turn.isWaiting, steps < 6 {
            steps += 1
            turn.executeCurrentAction()
        }
        return turn
    }

    /// Tuning the Outcome: "Move 3" and "Curse, Range 3".
    func testTuningTheOutcomeCursesAnEnemyWithinThreeHexes() async throws {
        let singer = board.character("music-note", at: here)
        let foe = try board.monster(at: HexCoord(8, 5))
        let curses = board.game.monsterAttackModifierDeck.undrawnCount(of: .curse)
        let turn = try playBottom("Tuning the Outcome", other: "Singing Arrow", for: singer)
        guard case .selectingConditionTarget(_, .curse, let targets) = board.coord.interactionMode else {
            return XCTFail("a Curse to aim: \(board.coord.interactionMode)")
        }
        XCTAssertEqual(targets, [foe.piece])
        board.coord.handlePieceTap(foe.piece)
        await board.settle { !turn.isWaiting }
        XCTAssertEqual(board.game.monsterAttackModifierDeck.undrawnCount(of: .curse), curses + 1)
    }

    /// Power Ballad: "Move 2" and "Strengthen, affect all adjacent allies". Natural Remedy:
    /// "Move 4" and "Strengthen, affect one adjacent ally".
    func testAStrengthenUnderAMoveReachesTheAlliesBesideTheCharacter() async throws {
        let singer = board.character("music-note", at: here)
        let beside = board.character("brute", at: HexCoord(6, 5)), alsoBeside = board.character("tinkerer", at: HexCoord(4, 5))
        let apart = board.character("scoundrel", at: HexCoord(8, 8))
        _ = try playBottom("Power Ballad", other: "Singing Arrow", for: singer)
        XCTAssertTrue(board.has(.strengthen, beside) && board.has(.strengthen, alsoBeside), "both adjacent allies")
        XCTAssertFalse(board.has(.strengthen, apart) || board.has(.strengthen, singer), "no one else")

        board = try RuleBoard()
        let tyrant = board.character("two-mini", at: here)
        let friend = board.character("brute", at: HexCoord(6, 5))
        let turn = try playBottom("Natural Remedy", other: "Maul", for: tyrant)
        if case .selectingConditionTarget(_, .strengthen, let targets) = board.coord.interactionMode {
            XCTAssertEqual(targets, [.character(friend.id)])
            board.coord.handlePieceTap(.character(friend.id))
            await board.settle { !turn.isWaiting }
        }
        XCTAssertTrue(board.has(.strengthen, friend), "the one adjacent ally")
        XCTAssertFalse(board.has(.strengthen, tyrant))
    }

    /// Warding Dagger: "Move 4" and "Shield 2, affect all adjacent allies". Crushing Hammer:
    /// "Move 2" and "Shield 1, self". Maul: "Move 3" and "Shield 1, affect one adjacent ally".
    /// Each for the round.
    func testAShieldUnderAMoveIsGainedForTheRound() throws {
        let singer = board.character("music-note", at: here)
        var ally = board.character("brute", at: HexCoord(6, 5))
        _ = try playBottom("Warding Dagger", other: "Singing Arrow", for: singer)
        XCTAssertEqual(board.coord.shield(of: .character(ally.id)), 2)
        XCTAssertEqual(board.coord.shield(of: .character(singer.id)), 0, "allies, not the Soothsinger")

        board = try RuleBoard()
        let quartermaster = board.character("three-spears", at: here)
        _ = try playBottom("Crushing Hammer", other: "Restock", for: quartermaster)
        XCTAssertEqual(board.coord.shield(of: .character(quartermaster.id)), 1)
        XCTAssertNil(quartermaster.shieldPersistent, "for the round")

        board = try RuleBoard()
        let tyrant = board.character("two-mini", at: here)
        ally = board.character("brute", at: HexCoord(6, 5))
        _ = try playBottom("Maul", other: "Natural Remedy", for: tyrant)
        XCTAssertEqual(board.coord.shield(of: .character(ally.id)), 1)
        XCTAssertEqual(board.coord.shield(of: .character(tyrant.id)), 0)
    }

    /// Lash Out: "Move 3" and "Push 2, target all adjacent enemies". Forceful Swipe: "Move 3"
    /// and "Push 2, target one adjacent enemy".
    func testAPushUnderAMovePushesTheEnemiesBesideTheCharacter() async throws {
        var tyrant = board.character("two-mini", at: here)
        let east = try board.monster(at: HexCoord(6, 5)), west = try board.monster(at: HexCoord(4, 5))
        var turn = try playBottom("Lash Out", other: "Maul", for: tyrant)
        await board.settle { !turn.isWaiting }
        XCTAssertEqual([east, west].map { board.hex($0.piece).map { here.distance(to: $0) } }, [3, 3], "both pushed two hexes")

        board = try RuleBoard()
        tyrant = board.character("two-mini", at: here)
        let foe = try board.monster(at: HexCoord(6, 5))
        turn = try playBottom("Forceful Swipe", other: "Maul", for: tyrant)
        guard case .selectingForcedMoveTarget(_, 2, true, let targets) = board.coord.interactionMode else {
            return XCTFail("a Push to aim: \(board.coord.interactionMode)")
        }
        XCTAssertEqual(targets, [foe.piece])
        board.coord.handlePieceTap(foe.piece)
        await board.settle { !turn.isWaiting }
        XCTAssertEqual(board.hex(foe.piece).map { here.distance(to: $0) }, 3)
    }

    /// The cards whose Move carries text of its own keep their own handling: Feedback Loop's
    /// Muddle and Sinister Opportunity's Move 1 are not abilities to perform after the Move.
    func testMovesWithTextOfTheirOwnAreLeftWhole() throws {
        for (deck, name) in [("mindthief", "Feedback Loop"), ("scoundrel", "Sinister Opportunity"), ("brute", "Hook and Chain")] {
            let card = try board.card(name, of: deck)
            let steps = PlayerTurnController.steps(card.bottomActions ?? [], labels: board.gm.editionStore)
            XCTAssertEqual(steps.filter { PlayerTurnController.isAbilityStep($0) }.map(\.type), [.move], name)
        }
    }
}
