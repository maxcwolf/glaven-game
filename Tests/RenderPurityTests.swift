import XCTest
import SwiftUI
import Observation
@testable import GlavenGameLib

/// Drawing a screen must not write the game. A write during rendering (even one that changes
/// nothing) invalidates every view reading that state, which renders again and writes again:
/// an endless loop that leaves the screen frozen and its buttons dead. The city event did this
/// (its deck was read through a mutating accessor).
@MainActor
final class RenderPurityTests: XCTestCase {
    private var gm: GameManager!

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        gm.game.events.cityEventDue = true
        gm.appPhase = .gameSetup
    }

    /// Whether `render` writes any of the game's state (top level, characters, monsters).
    private func writesTheGame(_ render: () -> Void) -> Bool {
        var wrote = false
        withObservationTracking {
            _ = gm.game.toSnapshot()   // reads every stored property, the characters' too
        } onChange: {
            wrote = true
        }
        render()
        return wrote
    }

    private func render<V: View>(_ view: V) {
        let renderer = ImageRenderer(content: view.environment(gm).frame(width: 1376, height: 1032))
        renderer.scale = 1
        _ = renderer.cgImage
    }

    /// Reading an event deck is a plain read once the deck is started.
    func testReadingAnEventDeckDoesNotWriteTheGame() {
        _ = gm.eventCardManager.topCard(.city)   // starts the deck (the one write)
        XCTAssertFalse(writesTheGame { _ = gm.eventCardManager.topCard(.city) })
        _ = gm.eventCardManager.deck(.road)   // starts the road deck
        XCTAssertFalse(writesTheGame { _ = gm.eventCardManager.deck(.road) })
    }

    /// Every town screen draws without writing the game (after a first draw, which may start a
    /// deck or deal what it shows).
    func testTownScreensDrawWithoutWritingTheGame() {
        let brute = gm.game.characters[0]
        let screens: [(String, AnyView)] = [
            ("main menu", AnyView(MainMenuView())),
            ("party and scenario", AnyView(GameSetupView())),
            ("city event", AnyView(EventSheet(deck: .city) {})),
            ("road event", AnyView(EventSheet(deck: .road) {})),
            ("city event, closable", AnyView(EventSheet(deck: .city, onDone: {}, onClose: {}))),
            ("sanctuary", AnyView(SanctuarySheet {})),
            ("battle goals", AnyView(BattleGoalPicker {})),
            ("quest", AnyView(QuestPicker(character: brute) {})),
            ("campaigns", AnyView(CampaignsSheet(scrolls: false))),
            ("table rules", AnyView(TableRulesSheet(scrolls: false))),
            ("items", AnyView(ItemLoadoutSheet(character: brute, scrolls: false))),
            ("enhancer", AnyView(EnhancementSheet(character: brute, scrolls: false))),
            ("hand", AnyView(HandSheet(character: brute))),
            ("shop", AnyView(ItemShopSheet(character: brute))),
            ("character sheet", AnyView(CharacterSheetView(character: brute, onDone: {}))),
            ("party sheet", AnyView(PartySheetView())),
            ("world map", AnyView(WorldMapView())),
        ]
        for (name, view) in screens {
            render(view)
            XCTAssertFalse(writesTheGame { render(view) }, "\(name) writes the game while drawing")
        }
    }

    /// The board, mid-scenario, draws without writing the game either.
    func testTheBoardDrawsWithoutWritingTheGame() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 2)
        gm = sim.gm
        let board = AnyView(BoardView(coordinator: sim.coord))
        render(board)
        XCTAssertFalse(writesTheGame { render(board) }, "the board writes the game while drawing")
        sim.coord.briefPresentation = .reminder
        render(board)
        XCTAssertFalse(writesTheGame { render(board) }, "the scenario brief writes the game while drawing")
    }
}
