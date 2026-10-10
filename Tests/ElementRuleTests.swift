import XCTest
import SwiftData
@testable import GlavenGameLib

/// The elemental infusion table (GH p.23–24, FAQ "Elements"): an element made during a turn is
/// strong only when the turn ends, so it can't be consumed in the turn that made it; one that was
/// already there can be consumed and made again in either order, and ends the turn strong; a
/// consumed element is inert; every element steps down as the round ends.
@MainActor
final class ElementRuleTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var game: GameState { gm.game }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    private func state(_ element: ElementType) -> ElementState { game.elementBoard.first { $0.type == element }!.state }
    private func set(_ element: ElementType, _ state: ElementState) {
        game.elementBoard[game.elementBoard.firstIndex { $0.type == element }!].state = state
    }

    func testAnElementMadeThisTurnCannotBeConsumedThisTurn() {
        game.infuseElement(.fire)
        XCTAssertFalse(game.isElementAvailable(.fire))
        XCTAssertNil(game.consumeElements([.fire]))
        game.settleElementsAtEndOfTurn()
        XCTAssertEqual(state(.fire), .strong)
        XCTAssertTrue(game.isElementAvailable(.fire), "another figure can consume it later this round")
    }

    /// FAQ: "If the element was already strong or waning at the start of your turn, you can
    /// recreate it with one action, consume the existing one with another, and it will still
    /// rise to strong at end of turn" — in either order.
    func testAnElementAlreadyThereCanBeInfusedAndConsumedInEitherOrder() {
        for start in [ElementState.strong, .waning] {
            set(.ice, start)
            game.infuseElement(.ice)
            XCTAssertNotNil(game.consumeElements([.ice]), "infused, then the \(start) Ice that was there is consumed")
            XCTAssertFalse(game.isElementAvailable(.ice), "one Ice, consumed once")
            game.settleElementsAtEndOfTurn()
            XCTAssertEqual(state(.ice), .strong, "from \(start): infuse, consume → strong")

            set(.ice, start)
            XCTAssertNotNil(game.consumeElements([.ice]))
            game.infuseElement(.ice)
            XCTAssertFalse(game.isElementAvailable(.ice), "the new Ice isn't there until the turn ends")
            game.settleElementsAtEndOfTurn()
            XCTAssertEqual(state(.ice), .strong, "from \(start): consume, infuse → strong")
        }
    }

    func testAConsumedElementIsInert() {
        set(.earth, .strong)
        XCTAssertEqual(game.consumeElements([.earth]), [.earth])
        game.settleElementsAtEndOfTurn()
        XCTAssertEqual(state(.earth), .inert, "always to inert, strong or waning (FAQ)")
    }

    func testAnInfusionRenewsAWaningElement() {
        set(.air, .waning)
        game.infuseElement(.air)
        game.settleElementsAtEndOfTurn()
        XCTAssertEqual(state(.air), .strong)
    }

    /// Every element steps down as the round ends, including one made in the round's last turn.
    func testElementsWaneAtTheEndOfTheRound() {
        set(.light, .strong)
        set(.dark, .waning)
        game.infuseElement(.fire)
        game.settleElementsAtEndOfTurn()
        game.state = .next
        gm.roundManager.nextGameState()   // play → draw: the round ends
        XCTAssertEqual(state(.light), .waning)
        XCTAssertEqual(state(.dark), .inert)
        XCTAssertEqual(state(.fire), .waning)
        XCTAssertEqual(state(.ice), .inert)
    }

    /// Through a turn: with Earth waning, the Cragheart moves with Rumbling Advance (Move 2,
    /// Earth) and then attacks with Earthen Clod, consuming the Earth that was there for its
    /// Immobilize. The turn ends with Earth strong.
    func testInfusingAndConsumingAnElementInOneTurn() async throws {
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let cragheart = game.characters[0]
        coord.boardState.placePiece(.character(cragheart.id), at: HexCoord(3, 3))
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(6, 3), origin: .placed))
        let guardEntity = try XCTUnwrap(coord.entity(for: piece))
        guardEntity.maxHealth = 30
        guardEntity.health = 30
        set(.earth, .waning)
        let deck = gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
        let clod = try XCTUnwrap(deck.first { $0.name == "Earthen Clod" })
        let advance = try XCTUnwrap(deck.first { $0.name == "Rumbling Advance" })
        cragheart.handCards = [clod.cardId!, advance.cardId!]
        let turn = PlayerTurnController(characterID: cragheart.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: clod, bottom: advance)
        turn.setBottomFirst(true)

        turn.executeCurrentAction()   // Move 2: stay put
        coord.handleHexTap(HexCoord(3, 3))
        try await Task.sleep(nanoseconds: 50_000_000)
        while turn.phase == .executeBottomAction && !turn.isWaiting { turn.executeCurrentAction() }
        XCTAssertEqual(state(.earth), .waning, "the Earth that was there is still there to consume")

        turn.executeCurrentAction()   // Attack 2, Range 5 — Earth: Immobilize
        XCTAssertEqual(state(.earth), .consumed)
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.first else {
            return XCTFail("the attack waits for a target")
        }
        coord.handlePieceTap(target)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(coord.isConditionActive(.immobilize, on: piece), "the bonus the Earth paid for")

        game.settleElementsAtEndOfTurn()
        XCTAssertEqual(state(.earth), .strong, "and the Earth infused this turn is strong at its end")
    }
}
