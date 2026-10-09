import XCTest
import SwiftData
@testable import GlavenGameLib

/// A character's turn and the round around it, as found in the October 2026 audit: skipping
/// or taking back a choice leaves nothing behind, persistent bonuses run however the halves
/// are played, and the round ends in the rulebook's order.
@MainActor
final class TurnFlowTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

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

    private func add(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    private func deck(_ name: String) -> [AbilityModel] {
        gm.editionStore.abilities(forDeck: name, edition: "gh")
    }

    private func turn(for character: GameCharacter, top: AbilityModel, bottom: AbilityModel) -> PlayerTurnController {
        character.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        return turn
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - Skipping and taking back a summon

    /// Skipping a summon's placement leaves no summon behind: none in the character's summons
    /// (counted for X, shown in the panel), the card isn't kept active for it, and later choices
    /// can still be taken back.
    func testSkippingASummonsPlacementLeavesNoSummon() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let summonCard = try XCTUnwrap(deck("tinkerer").first { $0.cardId == 31 })   // Harmless Contraption
        let other = try XCTUnwrap(deck("tinkerer").first { $0.cardId != 31 && ($0.bottomActions ?? []).contains { $0.type == .move } })
        let turn = turn(for: tinkerer, top: summonCard, bottom: other)
        while turn.phase == .executeTopAction {
            turn.executeCurrentAction()
            if case .placingSummon = coord.interactionMode { break }
        }
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the summon waits for its hex") }
        XCTAssertTrue(turn.canCancelChoice, "placing a summon can be taken back")

        turn.skipCurrentAction()
        XCTAssertNil(coord.pendingSummonPlacement)
        XCTAssertTrue(tinkerer.summons.isEmpty, "no summon that never reached the board")

        turn.skipRemainingActions()
        turn.useDefaultAction()   // a fresh choice: basic Move 2
        guard case .selectingMove = coord.interactionMode else { return XCTFail("a basic move") }
        XCTAssertTrue(turn.canCancelChoice)
    }

    /// Taking back a summon's placement takes back the summon too.
    func testCancellingASummonsPlacementTakesItBack() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let summonCard = try XCTUnwrap(deck("tinkerer").first { $0.cardId == 31 })
        let other = try XCTUnwrap(deck("tinkerer").first { $0.cardId != 31 })
        let turn = turn(for: tinkerer, top: summonCard, bottom: other)
        while turn.phase == .executeTopAction {
            turn.executeCurrentAction()
            if case .placingSummon = coord.interactionMode { break }
        }
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the summon waits for its hex") }
        turn.cancelChoice()
        XCTAssertNil(coord.pendingSummonPlacement)
        XCTAssertTrue(tinkerer.summons.isEmpty)
        XCTAssertFalse(turn.hasActed)
    }
}
