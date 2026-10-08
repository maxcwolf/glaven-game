import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The damage choice: taking the damage is the main action, losing a card is choose-then-confirm,
/// and a hit that would exhaust the character says so.
@MainActor
final class DamageChoiceTests: XCTestCase {

    private func pendingHit(_ damage: Int) async throws -> (GameManager, BoardCoordinator.PendingDamage, Task<Bool, Never>) {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let tinkerer = gm.game.characters[0]
        tinkerer.handCards = gm.editionStore.abilities(forDeck: "tinkerer", edition: "gh")
            .filter { $0.level?.intValue == 1 }.compactMap(\.cardId)
        coord.boardState.placePiece(.character(tinkerer.id), at: HexCoord(3, 3))
        let hit = Task { @MainActor in
            await coord.sufferDamageWithMitigation(damage, to: .character(tinkerer.id), source: "a trap")
        }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingDamage == nil && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        return (gm, try XCTUnwrap(coord.pendingDamage), hit)
    }

    func testOutcomeWarnsWhenTheHitExhausts() async throws {
        let (gm, small, hit) = try await pendingHit(3)
        let health = gm.game.characters[0].health
        XCTAssertEqual(gm.boardCoordinator.damageOutcome(small),
                       .init(healthBefore: health, healthAfter: health - 3, exhausts: false))
        gm.boardCoordinator.resolvePendingDamage(choice: .takeDamage)
        _ = await hit.value

        let (gm2, lethal, hit2) = try await pendingHit(50)
        XCTAssertEqual(gm2.boardCoordinator.damageOutcome(lethal)?.exhausts, true)
        XCTAssertEqual(gm2.boardCoordinator.damageOutcome(lethal)?.healthAfter, 0)
        gm2.boardCoordinator.resolvePendingDamage(choice: .loseHandCard(cardId: gm2.game.characters[0].handCards[0]))
        let died = await hit2.value
        XCTAssertFalse(died, "losing a card prevents all of it")
    }

    func testTheSheetFitsTheScreen() async throws {
        let (gm, pending, hit) = try await pendingHit(3)
        let character = gm.game.characters[0]
        XCTAssertFalse(gm.boardCoordinator.losableHandCards(of: character).isEmpty)
        for screen in [CGSize(width: 1376, height: 988), CGSize(width: 1133, height: 700)] {
            let sheet = DamageChoiceSheet(pending: pending, character: character, coordinator: gm.boardCoordinator)
                .environment(gm)
            let size = NSHostingController(rootView: sheet).sizeThatFits(in: screen)
            XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(screen)")
            XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(screen)")
        }
        XCTAssertNotNil(ImageLoader.abilityCardImage(edition: "gh", cardId: character.handCards[0]),
                        "the hand shows as the real card scans")
        gm.boardCoordinator.resolvePendingDamage(choice: .takeDamage)
        _ = await hit.value
    }
}
