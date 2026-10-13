import XCTest
import SwiftUI
@testable import GlavenGameLib

/// `INTERFACE_RENDER_OUT=/tmp/ui swift test --filter testRenderTheAuditsInterface` writes, at iPad
/// size, the screens the rules audit added and nobody had looked at (audit N16): the setup screen
/// with its Solo switch, the party panel with cards in play, the damage sheet when a bonus would
/// take the damage, and the long-rest sheet with an item to use.
@MainActor
final class AuditInterfaceRenderTests: XCTestCase {

    func testRenderTheAuditsInterface() async throws {
        guard let out = ProcessInfo.processInfo.environment["INTERFACE_RENDER_OUT"] else {
            throw XCTSkip("set INTERFACE_RENDER_OUT to render the screens")
        }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        GlavenFont.registerFonts()
        func render<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view.frame(width: 1376, height: 1032).background(Color(white: 0.2)))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }

        // The setup screen: a party of two, played solo.
        let setup = try SaveAndContinueTestsSupport.manager()
        setup.characterManager.addCharacter(name: "brute", edition: "gh")
        setup.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        setup.game.solo = true
        try render(GameSetupView().environment(setup), "setup-solo")

        // The board in round 3: the Spellweaver's Frost Armor and the Brute's Warding Strength in play.
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 2))
        await sim.play(rounds: 2)
        sim.coord.briefPresentation = nil
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        brute.activeCards = [7]
        brute.bonusChargesUsed[7] = 2
        spellweaver.activeCards = [66]
        try render(BoardView(coordinator: sim.coord).environment(sim.gm), "board-cards-in-play")

        // The damage sheet: Frost Armor would take it, or cards may be lost instead.
        sim.coord.pendingDamage = BoardCoordinator.PendingDamage(characterID: spellweaver.id, damage: 4,
                                                                 sourceDescription: "Bandit Guard 2", absorbedBy: "Frost Armor")
        try render(BoardView(coordinator: sim.coord).environment(sim.gm), "damage-sheet-bonus")
        sim.coord.pendingDamage = nil

        // The crystal about to be destroyed (Crystalline Cave): a card from either hand spares it.
        let cave = try ScenarioSimulator(scenario: "84", options: .init(characters: ["brute", "spellweaver"], seed: 2))
        cave.coord.briefPresentation = nil
        cave.coord.pendingSave = BoardCoordinator.PendingSave(objective: .objective(id: 1), name: "Crystal", damage: 4,
                                                              sourceDescription: "Frost Demon 3", health: 3, left: 1,
                                                              hands: cave.coord.savingHands())
        try render(BoardView(coordinator: cave.coord).environment(cave.gm), "save-sheet")

        // The long-rest sheet, with a potion to use on the rest turn.
        brute.items = ["gh-12"]
        if brute.discardedCards.count < 2 { brute.discardedCards.append(contentsOf: brute.handCards.suffix(2)) }
        let turn = PlayerTurnController(characterID: brute.id, coordinator: sim.coord, gameManager: sim.gm)
        turn.isLongRest = true
        turn.phase = .turnComplete
        sim.coord.activePlayerTurn = turn
        sim.coord.pendingLongRest = BoardCoordinator.PendingLongRest(characterID: brute.id)
        XCTAssertEqual(sim.coord.usableItems().map(\.itemKey), ["gh-12"], "the potion is offered on the rest turn")
        try render(BoardView(coordinator: sim.coord).environment(sim.gm), "long-rest")
    }
}
