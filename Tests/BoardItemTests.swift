import XCTest
import SwiftData
@testable import GlavenGameLib

/// Items on the board (GH p.26): usable on the character's own turn when their moment comes,
/// then spent or consumed, and counted for Professional and Purist.
@MainActor
final class BoardItemTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var brute: GameCharacter { gm.game.characters[0] }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(3, 3))
        // Boots, Goggles, Piercing Bow, War Hammer, Poison Dagger, Healing and Power Potions
        brute.items = ["gh-1", "gh-6", "gh-9", "gh-10", "gh-11", "gh-12", "gh-14"]
        // The tallies live on the scenario.
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.game.scenario = Scenario(data: data)
    }

    private func card(_ name: String) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: "brute", edition: "gh").first { $0.name == name }, name)
    }

    /// Trample on top (Attack 3), its Move 4 on the bottom.
    private func startTurn() throws -> PlayerTurnController {
        let trample = try card("Trample"), other = try card("Spare Dagger")
        brute.handCards = [trample.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: other)
        return turn
    }

    private func usable() -> [String] { coord.usableItems().map(\.itemKey).sorted() }

    func testBootsAddTwoToTheMoveAndAreSpent() throws {
        let turn = try startTurn()
        turn.swapCards()          // Trample's bottom: Move 4
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        XCTAssertEqual(usable(), ["gh-1", "gh-12"], "during a move: the boots, and the potion any time")

        let boots = try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-1" })
        XCTAssertTrue(coord.useItem(boots))
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("still moving") }
        XCTAssertEqual(range, 6)
        XCTAssertTrue(brute.spentItems.contains("gh-1"))
        XCTAssertFalse(coord.useItem(boots), "a spent item can't be used again")
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: brute.name).itemUses, 1)
    }

    func testAttackItemsJoinTheAttack() async throws {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        let bandit = try XCTUnwrap(coord.entity(for: piece))
        bandit.health = 99
        bandit.maxHealth = 99
        let turn = try startTurn()
        turn.executeCurrentAction()   // Attack 3, melee
        XCTAssertEqual(usable(), ["gh-10", "gh-11", "gh-12", "gh-14", "gh-6"],
                       "no Piercing Bow on a melee attack, no boots outside a move")

        for key in ["gh-14", "gh-11", "gh-6"] {
            XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first { $0.itemKey == key })), key)
        }
        XCTAssertEqual(turn.currentAttackValue(), 4, "Minor Power Potion: +1")
        XCTAssertEqual(turn.pendingConditions, [.poison])
        XCTAssertTrue(turn.pendingAdvantage)
        XCTAssertEqual(brute.consumedItems, ["gh-14"])
        XCTAssertEqual(brute.spentItems, ["gh-11", "gh-6"])

        coord.handlePieceTap(piece)
        let deadline = Date().addingTimeInterval(3)
        while turn.currentActionIndex == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .poison })
        XCTAssertEqual(coord.lastModifierReveal?.advantage, true, "Eagle-Eye Goggles: the attack draws with advantage")
    }

    func testAPotionHealsAnyTimeInTheTurnAndIsGone() throws {
        brute.health = 4
        _ = try startTurn()
        let potion = try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-12" })
        XCTAssertTrue(coord.useItem(potion))
        XCTAssertEqual(brute.health, 7)
        XCTAssertTrue(brute.consumedItems.contains("gh-12"))
        XCTAssertFalse(usable().contains("gh-12"))
    }

    func testNothingIsUsableOutsideTheCharactersTurn() {
        XCTAssertTrue(coord.usableItems().isEmpty)
    }

    /// Every item the board plays exists, under the name the table says.
    func testTheItemTableMatchesTheData() throws {
        for key in BoardItemEffect.byItem.keys {
            let id = try XCTUnwrap(Int(key.dropFirst(3)))
            XCTAssertNotNil(gm.editionStore.itemData(id: id, edition: "gh"), key)
        }
    }
}
