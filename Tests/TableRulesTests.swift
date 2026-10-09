import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Table rules: variants a group plays by, each off (the rulebook) until turned on for the
/// campaign, listed on the scenario brief while on.
@MainActor
final class TableRulesTests: XCTestCase {
    private var gm: GameManager!

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
    }

    func testTheRulebookUntilTurnedOn() {
        XCTAssertEqual(gm.game.tableRules, TableRules())
        XCTAssertEqual(gm.game.tableRules.inPlay, [])
        XCTAssertEqual(TableRulesSheet.summary(gm.game.tableRules), "Table rules: the rulebook")
        for rule in TableRules.all {
            XCTAssertEqual(PlayerTextTests.lint(rule.title), [], rule.title)
            XCTAssertEqual(PlayerTextTests.lint(rule.rulebook), [], rule.rulebook)
        }
    }

    func testEnhancerOpenFromTheStart() {
        XCTAssertFalse(gm.enhancementsManager.enhancerOpen(edition: "gh"))
        gm.setTableRule(\.enhancerFromStart, true)
        XCTAssertTrue(gm.enhancementsManager.enhancerOpen(edition: "gh"))
        XCTAssertEqual(gm.game.tableRules.inPlay, ["Enhancer open from the start"])
        XCTAssertEqual(TableRulesSheet.summary(gm.game.tableRules), "Table rules: 1 change from the rulebook")
    }

    /// Bring every item: nothing is left at home for want of room; back to the limits, what
    /// doesn't fit goes home again.
    func testBringEveryItem() {
        let brute = gm.game.characters[0]
        brute.level = 1
        gm.setTableRule(\.bringEveryItem, true)
        brute.loot = 100
        for key in ["gh-6", "gh-7"] {
            gm.itemManager.buy(gm.editionStore.itemData(key: key)!, for: brute)
        }
        XCTAssertEqual(brute.carriedItems, ["gh-6", "gh-7"], "two head items")
        gm.itemManager.setBringing("gh-7", false, for: brute)
        XCTAssertNil(gm.itemManager.setBringing("gh-7", true, for: brute))
        XCTAssertEqual(brute.carriedItems, ["gh-6", "gh-7"])

        gm.setTableRule(\.bringEveryItem, false)
        XCTAssertEqual(brute.carriedItems, ["gh-6"])
    }

    /// No road event on the way to the campaign's first scenario; the ones after draw as usual.
    func testNoRoadEventBeforeTheFirstScenario() throws {
        let barrow = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        XCTAssertTrue(gm.eventCardManager.needsRoadEvent(for: barrow), "the rulebook")
        gm.setTableRule(\.noFirstRoadEvent, true)
        XCTAssertFalse(gm.eventCardManager.needsRoadEvent(for: barrow))
        gm.game.completedScenarios.insert("gh-1")
        let next = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "2" })
        XCTAssertEqual(gm.eventCardManager.needsRoadEvent(for: next), next.eventType == "road")
        XCTAssertTrue(gm.eventCardManager.needsRoadEvent(for: barrow), "only before the first")
    }

    /// Saved with the campaign; a new campaign starts from the rulebook; an old save has none.
    func testSavedWithTheCampaign() throws {
        gm.setTableRule(\.noFirstRoadEvent, true)
        let data = try JSONEncoder().encode(gm.game.toSnapshot())
        let restored = GameState()
        restored.restore(from: try JSONDecoder().decode(GameSnapshot.self, from: data), editionStore: gm.editionStore)
        XCTAssertTrue(restored.tableRules.noFirstRoadEvent)

        var old = gm.game.toSnapshot()
        old.tableRules = nil
        restored.restore(from: old, editionStore: gm.editionStore)
        XCTAssertEqual(restored.tableRules, TableRules())

        gm.beginNewGame()
        XCTAssertEqual(gm.game.tableRules, TableRules())
    }

    /// `TABLE_RULES_RENDER_OUT=/tmp/t.png swift test --filter testRenderTableRules` renders the sheet.
    func testRenderTableRules() throws {
        guard let out = ProcessInfo.processInfo.environment["TABLE_RULES_RENDER_OUT"] else {
            throw XCTSkip("set TABLE_RULES_RENDER_OUT to render the table rules")
        }
        GlavenFont.registerFonts()
        gm.setTableRule(\.enhancerFromStart, true)
        let view = TableRulesSheet(scrolls: false).environment(gm).frame(width: 600, height: 420)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
