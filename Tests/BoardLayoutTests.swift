import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The board's HUD fits the screen in every phase: nothing is pushed off the top or bottom.
/// (A rigid side column once pushed the top bar and the action card off an iPad screen.)
@MainActor
final class BoardLayoutTests: XCTestCase {

    /// iPad Pro 13" and iPad mini, landscape, minus status bar and home indicator.
    private let screens: [CGSize] = [CGSize(width: 1376, height: 1032 - 44), CGSize(width: 1133, height: 744 - 44)]

    private func assertFits(_ gm: GameManager, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for screen in screens {
            let view = BoardView(coordinator: gm.boardCoordinator).environment(gm)
            let host = NSHostingController(rootView: view)
            let size = host.sizeThatFits(in: screen)
            XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(context): HUD taller than \(screen)", file: file, line: line)
            XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(context): HUD wider than \(screen)", file: file, line: line)
        }
    }

    func testHUDFitsThroughARound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        assertFits(sim.gm, "card selection")
        var checked = Set<String>()
        await sim.play(rounds: 2) {
            let key = "\(sim.coord.boardPhase)-\(sim.coord.activePlayerTurn != nil)"
            guard !checked.contains(key) else { return }
            checked.insert(key)
            self.assertFits(sim.gm, key)
        }
        XCTAssertGreaterThan(checked.count, 1)
    }

    func testHUDFitsDuringSetupWithAFullParty() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        for name in ["brute", "tinkerer", "spellweaver", "cragheart"] {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "2" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        assertFits(gm, "setup, four characters")
    }
}
