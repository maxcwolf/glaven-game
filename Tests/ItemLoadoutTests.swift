import XCTest
import SwiftUI
@testable import GlavenGameLib

/// A character brings at most one head, body and legs item, two hands' worth, and half their
/// level (rounded up) in small items (GH p.9); what's left at home does nothing on the board.
@MainActor
final class ItemLoadoutTests: XCTestCase {
    private var gm: GameManager!
    private var brute: GameCharacter!

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        brute = gm.game.characters[0]
        brute.level = 1
    }

    private func give(_ keys: String...) {
        for key in keys {
            brute.items.append(key)
            gm.editionStore.fitLoadout(brute, unlimited: false)
        }
    }

    /// A second head item bought is left at home, and can't be brought beside the first.
    func testASecondHeadItemStaysAtHome() throws {
        brute.loot = 100
        let goggles = try XCTUnwrap(gm.editionStore.itemData(key: "gh-6"))
        let helmet = try XCTUnwrap(gm.editionStore.itemData(key: "gh-7"))
        XCTAssertTrue(gm.itemManager.buy(goggles, for: brute))
        XCTAssertTrue(gm.itemManager.buy(helmet, for: brute))
        XCTAssertEqual(brute.items, ["gh-6", "gh-7"], "owned all the same")
        XCTAssertEqual(brute.carriedItems, ["gh-6"])
        XCTAssertEqual(gm.itemManager.setBringing("gh-7", true, for: brute), .slotTaken(.head))

        // Swap them: leave the goggles at home, then the helmet fits.
        XCTAssertNil(gm.itemManager.setBringing("gh-6", false, for: brute))
        XCTAssertNil(gm.itemManager.setBringing("gh-7", true, for: brute))
        XCTAssertEqual(brute.carriedItems, ["gh-7"])

        XCTAssertTrue(gm.itemManager.sell(helmet, for: brute))
        XCTAssertEqual(brute.itemsLeftBehind, ["gh-6"], "a sold item leaves the list too")
    }

    /// Two hands: a two-handed item and a one-handed one don't go together; two one-handed do.
    func testTwoHandsWorth() {
        give("gh-9", "gh-8")   // Piercing Bow (two hands), Heater Shield (one hand)
        XCTAssertEqual(brute.carriedItems, ["gh-9"])
        brute.itemsLeftBehind = []
        brute.items = []
        give("gh-8", "gh-11")  // Heater Shield, Poison Dagger
        XCTAssertEqual(brute.carriedItems, ["gh-8", "gh-11"])
        XCTAssertEqual(gm.itemManager.bringingProblem("gh-18", for: brute), .handsFull)
    }

    /// Small items: half the level, rounded up; Cloak of Pockets adds two, and leaving it at
    /// home leaves the small items it made room for.
    func testSmallItemsByLevelAndCloakOfPockets() {
        XCTAssertEqual(ItemLoadout.smallItemLimit(level: 1, carrying: []), 1)
        XCTAssertEqual(ItemLoadout.smallItemLimit(level: 4, carrying: []), 2)
        XCTAssertEqual(ItemLoadout.smallItemLimit(level: 5, carrying: []), 3)
        give("gh-12", "gh-13")
        XCTAssertEqual(brute.carriedItems, ["gh-12"], "one small item at level 1")
        brute.itemsLeftBehind = []
        brute.items = []
        give("gh-12", "gh-13", "gh-14", "gh-16")   // three potions, then Cloak of Pockets
        XCTAssertEqual(brute.carriedItems, ["gh-12", "gh-16"], "potions left home stay home until brought")
        XCTAssertNil(gm.itemManager.setBringing("gh-13", true, for: brute))
        XCTAssertNil(gm.itemManager.setBringing("gh-14", true, for: brute))
        XCTAssertEqual(brute.carriedItems, ["gh-12", "gh-13", "gh-14", "gh-16"], "the cloak makes room for three")
        brute.items = ["gh-12", "gh-13", "gh-14", "gh-15", "gh-16"]
        brute.itemsLeftBehind = []
        gm.editionStore.fitLoadout(brute, unlimited: false)
        XCTAssertEqual(brute.carriedItems, brute.items, "the cloak counts wherever it was acquired")
        brute.items.removeAll { $0 == "gh-15" }
        gm.itemManager.setBringing("gh-16", false, for: brute)
        XCTAssertEqual(brute.carriedItems, ["gh-12"])
        XCTAssertEqual(ItemLoadoutSheet.limitsLine(for: brute, store: gm.editionStore),
                       "Bringing 1 of 4 items · up to 1 small item at level 1")
    }

    /// An item at home adds no −1 cards and has no effect on the board.
    func testAnItemAtHomeDoesNothing() throws {
        give("gh-4", "gh-23", "gh-71")   // Leather Armor, Chainmail (−1 cards, also a body), Boots of Levitation
        XCTAssertEqual(brute.carriedItems, ["gh-4", "gh-71"])
        gm.itemManager.setBringing("gh-71", false, for: brute)
        XCTAssertFalse(PassiveItems.flies(brute.carriedItems))
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        let before = brute.attackModifierDeck.undrawnCount(of: .minus1)
        gm.scenarioManager.setScenario(scenario)
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .minus1), before, "the Chainmail stayed home")
    }

    /// Saved and loaded with the campaign.
    func testTheLoadoutIsSaved() throws {
        give("gh-6", "gh-7")
        let snapshot = gm.game.toSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let restored = GameState()
        restored.restore(from: try JSONDecoder().decode(GameSnapshot.self, from: data), editionStore: gm.editionStore)
        XCTAssertEqual(restored.characters.first?.itemsLeftBehind, ["gh-7"])
    }

    /// `LOADOUT_RENDER_OUT=/tmp/l.png swift test --filter testRenderLoadout` renders the sheet.
    func testRenderLoadout() throws {
        guard let out = ProcessInfo.processInfo.environment["LOADOUT_RENDER_OUT"] else {
            throw XCTSkip("set LOADOUT_RENDER_OUT to render the loadout")
        }
        GlavenFont.registerFonts()
        give("gh-6", "gh-7", "gh-4", "gh-12", "gh-13", "gh-9")
        let view = ItemLoadoutSheet(character: brute, scrolls: false).environment(gm).frame(width: 600, height: 700)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
