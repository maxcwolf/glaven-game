import XCTest
@testable import GlavenGameLib

/// Every printed text the game shows resolves: class cards (the locked classes' come from the
/// spoiler labels) and items' effects.
@MainActor
final class LabelTests: XCTestCase {

    /// Regression: the spoiler labels weren't loaded, so the locked classes' custom card text and
    /// every item's effect text were missing.
    func testEveryCardAndItemTextResolves() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let store = gm.editionStore
        var missing: [String] = []
        func check(_ actions: [ActionModel], _ owner: String) {
            for action in actions {
                if action.type == .custom, let key = action.value?.stringValue, key.hasPrefix("%data.") {
                    let text = store.resolveCustomText(key, edition: "gh")
                    if text == nil || text?.contains("%data.") == true { missing.append("\(owner): \(key)") }
                }
                check(action.subActions ?? [], owner)
            }
        }
        for character in store.characters(for: "gh") {
            for card in store.abilities(forDeck: character.deck ?? character.name, edition: "gh") {
                check((card.actions ?? []) + (card.bottomActions ?? []), "\(character.name) \(card.name ?? "")")
            }
        }
        for item in store.items(for: "gh") {
            check(item.actions ?? [], item.name)
        }
        // Two lines the upstream data doesn't have at all.
        let absentFromData: Set = ["three-spears Portable Ballista: %data.custom.gh.three-spears.abilities.229.2%",
                                   "angry-face Wild Command: %data.custom.gh.angry-face.abilities.398.4%"]
        XCTAssertEqual(missing.filter { !absentFromData.contains($0) }, [], "\(missing.count) texts unresolved")
    }
}
