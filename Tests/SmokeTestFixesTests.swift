import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Fixes from playing the iPad build by hand (2026-10-08).
@MainActor
final class SmokeTestFixesTests: XCTestCase {
    private var gm: GameManager!

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
    }

    /// The rest prompts said "spellweaver — Short Rest", the class id.
    func testRestPromptsNameTheCharacter() {
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let title = BoardView.restTitle("Short Rest", for: gm.game.characters[0], labels: gm.editionStore)
        XCTAssertEqual(title, "Spellweaver — Short Rest")
        XCTAssertEqual(PlayerTextTests.lint(title), [])
    }

    /// After Accept the event's card leaves the deck; the sheet showed the next card's number.
    func testAResolvedEventKeepsShowingItsOwnCard() throws {
        let events = gm.editionStore.events(for: "gh").filter { $0.type == "city" }
        let resolved = try XCTUnwrap(events.first), next = try XCTUnwrap(events.dropFirst().first)
        XCTAssertEqual(EventSheet.shownEvent(resolved: true, kept: resolved, top: next)?.cardId, resolved.cardId)
        XCTAssertEqual(EventSheet.shownEvent(resolved: false, kept: resolved, top: next)?.cardId, next.cardId,
                       "before it's resolved, the top of the deck")
        XCTAssertEqual(EventSheet.shownEvent(resolved: false, kept: resolved, top: nil)?.cardId, resolved.cardId)
    }

    /// Setup readies each character to place in turn, its starting hexes lit, instead of
    /// waiting for the player to find the character's button first.
    func testSetupReadiesEachCharacterToPlace() throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let (brute, spellweaver) = (gm.game.characters[0].id, gm.game.characters[1].id)
        guard case .placingCharacter(let first) = coord.interactionMode else { return XCTFail("\(coord.interactionMode)") }
        XCTAssertEqual(first, brute)
        let hexes = coord.boardState.startingLocations.sorted()
        coord.handleHexTap(hexes[0])
        guard case .placingCharacter(let second) = coord.interactionMode else { return XCTFail("the next one") }
        XCTAssertEqual(second, spellweaver)
        coord.handleHexTap(hexes[1])
        XCTAssertTrue({ if case .idle = coord.interactionMode { return true }; return false }(), "everyone is placed")
    }

    /// With one scenario to play (a new campaign's), it's chosen for the party.
    func testTheOnlyScenarioIsChosen() throws {
        let scenarios = gm.editionStore.scenarios(for: "gh")
        XCTAssertEqual(GameSetupView.onlyChoice(Array(scenarios.prefix(1)))?.id, scenarios.first?.id)
        XCTAssertNil(GameSetupView.onlyChoice(Array(scenarios.prefix(2))))
        XCTAssertNil(GameSetupView.onlyChoice([]))
    }

    /// The board keeps clear of the largest the bottom-left bar has been, so it doesn't jump
    /// when the bar shrinks to an End Turn button.
    func testTheBoardDoesNotChaseTheActionBar() {
        var frames = BoardView.HUDFrames()
        frames.board = CGRect(x: 0, y: 0, width: 1000, height: 800)
        frames.reportBottomLeading(CGRect(x: 0, y: 500, width: 500, height: 300))
        let tall = frames.obstacles(showingSidePanels: true)
        frames.reportBottomLeading(CGRect(x: 0, y: 700, width: 200, height: 100))
        XCTAssertEqual(frames.obstacles(showingSidePanels: true), tall)
        XCTAssertEqual(frames.bottomLeading, CGRect(x: 0, y: 500, width: 500, height: 300))
    }

    private func bruteTurn(monsterAt hex: HexCoord) throws -> (BoardCoordinator, PlayerTurnController) {
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(3, 3))
        _ = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let trample = try XCTUnwrap(deck.first { $0.name == "Trample" }), blow = try XCTUnwrap(deck.first { $0.name == "Sweeping Blow" })
        brute.handCards = [trample.cardId!, blow.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: blow)
        return (coord, turn)
    }

    /// An attack with no enemy in reach says so on its button.
    func testAnAttackWithNoTargetSaysSo() throws {
        let (_, far) = try bruteTurn(monsterAt: HexCoord(8, 3))
        let attack = try XCTUnwrap(far.topActions.first { $0.type == .attack })
        XCTAssertTrue(far.attackHasNoTarget(attack))
        gm.boardCoordinator.boardState.movePiece(try XCTUnwrap(gm.boardCoordinator.boardState.piecePositions.keys.first {
            if case .monster = $0 { return true }; return false
        }), to: HexCoord(4, 3))
        XCTAssertFalse(far.attackHasNoTarget(attack), "an adjacent enemy")
    }

    /// The basic Move 2 can be cancelled while it waits for a hex, like a printed ability.
    func testABasicMoveCanBeCancelled() throws {
        let (coord, turn) = try bruteTurn(monsterAt: HexCoord(8, 3))
        defer { withExtendedLifetime(gm) {} }
        turn.setBottomFirst(true)
        turn.useDefaultAction()
        guard case .selectingMove = coord.interactionMode else { return XCTFail("a hex to move to") }
        XCTAssertTrue(turn.canCancelChoice)
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canCancel, true)
        // With a card shown full size on top, Escape is for closing it, not for the choice.
        coord.showCardPreview(cardId: 1)
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canCancel, false)
        coord.dismissCardPreview()
        turn.cancelChoice()
        XCTAssertTrue({ if case .idle = coord.interactionMode { return true }; return false }())
        XCTAssertFalse(turn.bottomUsedAsDefault, "the card isn't spent as a basic move")
        XCTAssertFalse(turn.hasActed)
        XCTAssertFalse(turn.isWaiting)
        turn.executeCurrentAction()
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("the printed Move 3") }
        XCTAssertEqual(range, 3)
    }

    /// A character's long rest asks in its own panel; the banner said "Brute is acting · Monsters
    /// and summons take their turns on their own". Summons acting on a character's turn say so.
    func testTheBannerDuringACharactersTurn() {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        let coord = gm.boardCoordinator
        coord.boardPhase = .execution
        coord.turnOrder = [TurnOrderEntry(figure: .character(brute), initiative: 99)]
        coord.currentTurnIndex = 0
        XCTAssertEqual(coord.instruction(for: .watchingMonsterTurn)?.title, "Brute\u{2019}s summons are acting")
        coord.pendingLongRest = BoardCoordinator.PendingLongRest(characterID: brute.id)
        XCTAssertNil(coord.instruction(for: .watchingMonsterTurn))
    }

    /// The long rest panel is as wide as its cards, not the screen.
    func testTheLongRestPanelFitsItsCards() {
        XCTAssertEqual(BoardView.longRestWidth(cards: 2), 440, "room for the heading")
        XCTAssertEqual(BoardView.longRestWidth(cards: 4), 648)
        XCTAssertEqual(BoardView.longRestWidth(cards: 9), 760, "more scroll")
    }
}
