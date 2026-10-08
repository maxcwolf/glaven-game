import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The main menu: Load picks up a named save the way Continue picks up the autosave, and the
/// credits name everyone whose work the game ships.
@MainActor
final class MainMenuTests: XCTestCase {

    /// A save made mid-scenario loads back onto the board at the start of the saved round.
    func testLoadingASaveMadeInAScenarioResumesItsRound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 2)
        let round = sim.gm.game.round
        sim.gm.saveToSlot(name: "Before the boss")
        // Play on, then load the save back.
        await sim.play(rounds: 3)
        XCTAssertNotEqual(sim.gm.game.round, round)

        sim.gm.loadSlotAndContinue(name: "Before the boss")
        XCTAssertEqual(sim.gm.appPhase, .board)
        XCTAssertEqual(sim.gm.boardCoordinator.boardPhase, .cardSelection, "at the start of a round, not mid-turn")
        XCTAssertEqual(sim.gm.game.round, round)
        let summary = try XCTUnwrap(sim.gm.autosaveSummary, "Continue now offers the loaded game")
        XCTAssertEqual(summary.scenario, "#1 Black Barrow")
        XCTAssertEqual(summary.round, sim.gm.boardCoordinator.displayedRound)
    }

    /// A save made between scenarios loads back to the party screen.
    func testLoadingASaveMadeBetweenScenariosGoesToTheParty() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.saveToSlot(name: "Town")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")

        gm.loadSlotAndContinue(name: "Town")
        XCTAssertEqual(gm.appPhase, .gameSetup)
        XCTAssertEqual(gm.game.characters.map(\.name), ["brute"])
    }

    func testCreditsNameTheGameDataArtTypeAndSound() {
        let text = CreditsSheet.credits.map { "\($0.title) \($0.detail)" }.joined(separator: " ")
        for name in ["Cephalofair", "Gloomhaven Secretariat", "gloomhaven-card-browser", "Pirata One", "Kenney"] {
            XCTAssertTrue(text.contains(name), "credits \(name)")
        }
        for credit in CreditsSheet.credits {
            XCTAssertEqual(PlayerTextTests.lint(credit.detail), [], credit.detail)
        }
    }

    /// `MENU_RENDER_OUT=/tmp/menu.png swift test --filter testRenderMainMenu` renders the menu.
    func testRenderMainMenu() throws {
        guard let out = ProcessInfo.processInfo.environment["MENU_RENDER_OUT"] else {
            throw XCTSkip("set MENU_RENDER_OUT to render the menu")
        }
        GlavenFont.registerFonts()
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.saveGame()
        let renderer = ImageRenderer(content: MainMenuView().environment(gm).frame(width: 1376, height: 1032))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
