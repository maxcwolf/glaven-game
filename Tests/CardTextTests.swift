import XCTest
import SwiftData
@testable import GlavenGameLib

/// The drawn cards' words (`CardText`): everything a card prints, so the drawn card plays as the
/// scan does.
@MainActor
final class CardTextTests: XCTestCase {
    private var store: EditionDataStore!

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        store = gm.editionStore
    }

    /// Every character deck of Gloomhaven.
    private var deckNames: [String] {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlavenGame/Resources/EditionData/gh/character/deck")
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    private func deck(_ name: String) -> [AbilityModel] { store.deckData(name: name, edition: "gh")?.abilities ?? [] }
    private func card(_ name: String, of deckName: String) -> AbilityModel { deck(deckName).first { $0.name == name }! }

    private func lines(_ actions: [ActionModel]?) -> [CardLine] {
        CardText.lines(of: actions) { self.store.resolveCustomText($0, edition: "gh") }.lines
    }

    /// The words of a half, one string a line, badges and areas marked.
    private func words(_ actions: [ActionModel]?) -> [String] {
        lines(actions).map { line in
            switch line.kind {
            case .area: return "[area]"
            case .badge: return "(\(line.text))"
            default: return String(repeating: "  ", count: line.depth) + line.text
            }
        }
    }

    func testTrampleReadsAsPrinted() {
        let trample = card("Trample", of: "brute")
        XCTAssertEqual(words(trample.actions), ["Attack 3", "  Pierce 2"])
        XCTAssertEqual(words(trample.bottomActions), ["Move 4", "  Jump", "Attack 2", "  Target all enemies moved through", "(+2 XP)"])
    }

    func testAnAreaATargetAndTheCardsOwnWordsAreShown() {
        let sweeping = card("Sweeping Blow", of: "brute")
        XCTAssertEqual(words(sweeping.actions), ["Attack 2", "[area]"])
        XCTAssertEqual(words(sweeping.bottomActions), ["Move 3", "Push 1", "  Target all adjacent enemies"])
        let roar = card("Provoking Roar", of: "brute")
        XCTAssertEqual(words(roar.actions), ["Attack 2", "  Disarm"])
        XCTAssertEqual(roar.bottomActions.map(words)?.first?.hasPrefix("Any enemy who targets one of your adjacent allies"), true,
                       "\(words(roar.bottomActions))")
        XCTAssertEqual(words(roar.bottomActions).last, "(Round bonus)")
    }

    func testAnElementConsumedLeadsWhatItGives() {
        let skewer = card("Skewer", of: "brute")
        XCTAssertEqual(words(skewer.actions), ["Attack 3", "[area]", "  Consume Air:", "    Attack +1", "    Pierce 1", "(+1 XP)"])
    }

    func testASummonShowsItsStats() {
        let swoop = card("Felling Swoop", of: "angry-face")
        let text = words(swoop.actions) + words(swoop.bottomActions)
        XCTAssertTrue(text.contains { $0.hasPrefix("Summon War Hawk") }, "\(text)")
        XCTAssertTrue(text.contains("  HP 3 · Move 3 · Attack 3"), "\(text)")
        XCTAssertTrue(text.contains("  Flying"), "what the summon card prints under its stats: \(text)")
    }

    func testUsesAndPersistenceAreMarked() {
        XCTAssertEqual(CardText.badge([ActionModel(type: .card, value: .string("persistent")),
                                       ActionModel(type: .card, value: .string("slotXp:1")),
                                       ActionModel(type: .card, value: .string("slot")),
                                       ActionModel(type: .card, value: .string("slotXp:1")),
                                       ActionModel(type: .card, value: .string("slot")),
                                       ActionModel(type: .card, value: .string("lost"))]),
                       "Persistent · 4 uses, 2 with +1 XP · Lost when used up")
    }

    func testWhoASpecialTargetReaches() {
        XCTAssertEqual(CardText.target("selfAlliesAffectRange:4"), "Affect you and all allies within Range 4")
        XCTAssertEqual(CardText.target("allyAffectAdjacent"), "Affect one adjacent ally")
        XCTAssertEqual(CardText.target("enemiesRangeExact:2"), "Target all enemies at exactly Range 2")
        XCTAssertEqual(CardText.target("alliesRangeAffect:2 instead"), "Affect all allies within Range 2 instead")
        XCTAssertEqual(CardText.target("enemyAdjacent"), "Target one adjacent enemy")
    }

    /// Every character card of Gloomhaven is read whole: nothing the drawn card can't say,
    /// no data markup left in its words.
    func testEveryCharacterCardIsReadWhole() {
        var unread: [String] = []
        var markup: [String] = []
        var cards = 0
        for name in deckNames {
            for card in deck(name) {
                cards += 1
                for half in [card.actions, card.bottomActions] {
                    let read = CardText.lines(of: half) { self.store.resolveCustomText($0, edition: "gh") }
                    unread += read.unread.map { "\(name) \(card.name ?? "?"): \($0.type.rawValue) \($0.value?.stringValue ?? "")" }
                    markup += read.lines.filter { $0.text.contains("%") || $0.text.contains("<") }
                        .map { "\(name) \(card.name ?? "?"): \($0.text)" }
                }
            }
        }
        XCTAssertGreaterThan(cards, 400, "the decks were found")
        XCTAssertEqual(unread, [], "the drawn card can't say these")
        XCTAssertEqual(markup, [], "data markup in the drawn card's words")
    }

    /// `CARD_TEXT_DECK=brute swift test --filter testPrintADeck` prints a deck's cards as the drawn cards say them.
    func testPrintADeck() throws {
        guard let name = ProcessInfo.processInfo.environment["CARD_TEXT_DECK"] else { throw XCTSkip("set CARD_TEXT_DECK") }
        for card in deck(name) {
            print("== \(card.initiative) \(card.name ?? "")")
            print(words(card.actions).joined(separator: "\n"))
            print("--")
            print(words(card.bottomActions).joined(separator: "\n"))
        }
    }
}
