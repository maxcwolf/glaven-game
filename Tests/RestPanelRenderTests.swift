import XCTest
import SwiftUI
@testable import GlavenGameLib

/// `REST_RENDER_OUT=/tmp/r.png swift test --filter testRenderRestPanel` renders the board with a
/// long rest (REST_KIND=short: a short rest) waiting.
@MainActor
final class RestPanelRenderTests: XCTestCase {
    func testRenderRestPanel() async throws {
        guard let out = ProcessInfo.processInfo.environment["REST_RENDER_OUT"] else {
            throw XCTSkip("set REST_RENDER_OUT to render the rest panel")
        }
        GlavenFont.registerFonts()
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 2)
        sim.coord.briefPresentation = nil
        let character = sim.gm.game.characters[0]
        if ProcessInfo.processInfo.environment["REST_KIND"] == "short" {
            sim.coord.pendingShortRest = BoardCoordinator.PendingShortRest(characterID: character.id,
                                                                           randomCardId: character.discardedCards.first ?? 0)
        } else {
            sim.coord.pendingLongRest = BoardCoordinator.PendingLongRest(characterID: character.id)
        }
        let renderer = ImageRenderer(content: BoardView(coordinator: sim.coord).environment(sim.gm).frame(width: 1376, height: 1032))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
