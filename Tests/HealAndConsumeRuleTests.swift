import XCTest
@testable import GlavenGameLib

/// Heals and element consumes as the board performs them. (This file used to test
/// `ActionsManager.applyInteractiveAction`, which nothing in the game calls: the same rules are
/// tested here through `BoardCoordinator.heal` and `GameState.consumeElements`, the calls a
/// card, a monster and an item make. What a heal removes — Wound, Poison, both — is in
/// ConditionRuleTests.testWhatAHealRemoves and RestRuleTests.testPoisonTakesTheRestsHeal.)
@MainActor
final class HealAndConsumeRuleTests: XCTestCase {

    private func state(_ type: ElementType, _ game: GameState) -> ElementState {
        game.elementBoard.first { $0.type == type }!.state
    }

    private func set(_ type: ElementType, _ state: ElementState, _ game: GameState) {
        game.elementBoard[game.elementBoard.firstIndex { $0.type == type }!].state = state
    }

    /// A heal through a card: Restorative Mist's top (Heal 3, Range 3) played by the Tinkerer
    /// on the poisoned and wounded Brute at full health removes both and heals nothing; the
    /// Brute's Immobilize is not a heal's to remove.
    func testAHealCardRemovesPoisonAndWoundAndNothingElse() throws {
        let board = try RuleBoard()
        let tinkerer = board.character("tinkerer", at: HexCoord(3, 3))
        let brute = board.character(at: HexCoord(4, 3), health: 10)
        brute.entityConditions = [EntityCondition(name: .poison, state: .normal), EntityCondition(name: .wound, state: .normal),
                                  EntityCondition(name: .immobilize, state: .normal)]
        board.play(try board.card("Restorative Mist", of: "tinkerer"), try board.card("Stun Shot", of: "tinkerer"), for: tinkerer)
        board.startTurns([TurnOrderEntry(figure: .character(tinkerer), initiative: 17)])
        let turn = try XCTUnwrap(board.coord.activePlayerTurn)
        turn.executeCurrentAction()
        guard case .selectingHealTarget(_, let value, let targets) = board.coord.interactionMode else {
            return XCTFail("the heal asks whom: \(board.coord.interactionMode)")
        }
        XCTAssertEqual(value, 3)
        XCTAssertTrue(targets.contains(.character(brute.id)), "an ally with Poison to remove is worth healing at full health")
        board.coord.handlePieceTap(.character(brute.id))
        XCTAssertEqual(brute.entityConditions.map(\.name), [.immobilize], "Poison and Wound are gone; the Immobilize stays")
        XCTAssertEqual(brute.health, 10)
    }

    /// "If a single augment lists multiple element uses, all elements must be used" (p.24): a
    /// consume of Fire and Earth takes both, and takes neither when one of them is inert.
    func testAConsumeOfTwoElementsNeedsAndTakesBoth() throws {
        let game = try SaveAndContinueTestsSupport.manager().game
        set(.fire, .strong, game)
        XCTAssertFalse(game.canConsumeElements([.fire, .earth]))
        XCTAssertNil(game.consumeElements([.fire, .earth]), "Earth is inert: the consume can't be paid")
        XCTAssertEqual(state(.fire, game), .strong, "and Fire is not taken")

        set(.earth, .waning, game)
        XCTAssertTrue(game.canConsumeElements([.fire, .earth]))
        XCTAssertNotNil(game.consumeElements([.fire, .earth]))
        game.settleElementsAtEndOfTurn()
        XCTAssertEqual(state(.fire, game), .inert)
        XCTAssertEqual(state(.earth, game), .inert)
    }
}
