import XCTest
import SwiftUI
@testable import GlavenGameLib

/// City and road events (GH p.38): each deck starts as cards 01–30; after a scenario the party
/// resolves a city event, and a road event on the way to a road scenario. The first outcome whose
/// condition holds applies, its effects are applied (some carry into the next scenario), and the
/// card is removed or returned to the bottom as it says.
@MainActor
final class EventCardTests: XCTestCase {

    private var gm: GameManager!
    private var events: EventCardManager { gm.eventCardManager }
    private var game: GameState { gm.game }

    override func setUpWithError() throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
    }

    private var brute: GameCharacter { game.characters[0] }
    private var tinkerer: GameCharacter { game.characters[1] }

    /// Put a card on top of its deck.
    private func top(_ deck: EventCardManager.Deck, _ id: String) {
        var cards = events.deck(deck).filter { $0 != id }
        cards.insert(id, at: 0)
        switch deck {
        case .city: game.events.cityDeck = cards
        case .road: game.events.roadDeck = cards
        }
    }

    // MARK: - Data

    func testEveryCardDecodesWithItsOptionsAndOutcomes() {
        let cards = gm.editionStore.events(for: "gh")
        XCTAssertEqual(cards.filter { $0.type == "city" }.count, 81)
        XCTAssertEqual(cards.filter { $0.type == "road" }.count, 69)
        for card in cards {
            XCTAssertFalse(card.narrative?.isEmpty ?? true, "\(card.id)")
            XCTAssertEqual(card.options?.count, 2, "\(card.id)")
            for option in card.options ?? [] {
                XCTAssertFalse(option.outcomes?.isEmpty ?? true, "\(card.id) \(option.label ?? "")")
            }
        }
        let city01 = cards.first { $0.id == "gh-city-01" }!
        XCTAssertEqual(city01.options?[0].outcomes?[0].effects?[1].subEffects?.count, 2, "a nested choice decodes")
    }

    // MARK: - Decks

    func testEachDeckStartsWithCardsOneToThirty() {
        for deck in EventCardManager.Deck.allCases {
            XCTAssertEqual(Set(events.deck(deck)), Set((1...30).map { String(format: "%02d", $0) }))
            XCTAssertNotNil(events.topCard(deck))
        }
    }

    func testACardIsRemovedOrReturnedAsItSays() {
        top(.city, "02")
        events.resolve(.city, option: "B")   // "Refuse to pay": return to the deck
        XCTAssertEqual(events.deck(.city).last, "02", "back at the bottom")
        XCTAssertEqual(events.deck(.city).count, 30)

        top(.city, "01")
        events.resolve(.city, option: "B")   // marked "return" too
        top(.city, "16")
        events.resolve(.city, option: "B")   // "remove from the game"
        XCTAssertFalse(events.deck(.city).contains("16"))
        XCTAssertEqual(events.deck(.city).count, 29)
    }

    func testTheDecksAreSaved() throws {
        _ = events.deck(.road)
        game.events.cityEventDue = true
        game.events.nextScenario.damage = 2
        let restored = GameState()
        restored.restore(from: game.toSnapshot(), editionStore: gm.editionStore)
        XCTAssertEqual(restored.events, game.events)
    }

    // MARK: - Outcomes

    /// "Pay 10 collective gold": a party that can pays it; one that can't gets "otherwise".
    func testAPriceIsPaidWhenThePartyCanAffordIt() {
        top(.city, "16")
        brute.loot = 6; tinkerer.loot = 6
        let resolution = events.resolve(.city, option: "A")
        XCTAssertEqual(brute.loot + tinkerer.loot, 2, "10 paid")
        XCTAssertTrue(events.deck(.city).contains("70"), "the outcome shuffles city event 70 into the deck")
        XCTAssertTrue(resolution?.effects.contains("The party pays 10 gold.") == true)

        top(.city, "02")
        brute.loot = 3; tinkerer.loot = 3
        events.resolve(.city, option: "A")
        XCTAssertEqual(brute.loot + tinkerer.loot, 6, "too poor to pay: nothing taken")
    }

    func testAClassInThePartyChangesTheOutcome() throws {
        top(.road, "35")
        events.resolve(.road, option: "A")
        XCTAssertEqual(game.events.nextScenario.conditions, [.poison], "no Plagueherald: poisoned")
        XCTAssertEqual(game.events.nextScenario.damage, 3)

        game.events.nextScenario = ScenarioStartEffects()
        gm.characterManager.addCharacter(name: "squidface", edition: "gh")
        top(.road, "35")
        events.resolve(.road, option: "A")
        XCTAssertEqual(game.events.nextScenario.conditions, [], "the Plagueherald drives them off")
        XCTAssertEqual(game.events.nextScenario.damage, 1)
    }

    func testAChoiceIsTheParty() {
        top(.city, "01")
        let (gold, reputation) = (brute.loot, game.partyReputation)
        var choices = EventCardManager.Choices()
        choices.chosen = [1]   // lose reputation rather than gold
        events.resolve(.city, option: "A", choices: choices)
        XCTAssertEqual(brute.experience, 10)
        XCTAssertEqual(brute.loot, gold, "the gold is kept")
        XCTAssertEqual(game.partyReputation, reputation - 1)
    }

    /// City 31, option B: a Sunkeeper won't let the party refuse, so option A's outcome applies.
    func testAnOutcomeCanSendThePartyToTheOtherOption() {
        gm.characterManager.addCharacter(name: "sun", edition: "gh")
        top(.city, "31")
        events.resolve(.city, option: "B")
        XCTAssertTrue(game.partyAchievements.contains("bad-business"))
        XCTAssertTrue(game.manualScenarios.contains("gh-83"))
        XCTAssertEqual(game.characters.reduce(0) { $0 + $1.loot }, 20)
        XCTAssertFalse(events.deck(.city).contains("31"), "removed, as option A says")
    }

    // MARK: - Into the next scenario

    func testRoadEventsCarryIntoTheNextScenario() throws {
        top(.road, "35")
        events.resolve(.road, option: "A")          // poison and 3 damage
        top(.road, "12")
        var minus = EventCardManager.Choices()
        minus.oneCharacter = tinkerer.id
        events.resolve(.road, option: "B", choices: minus)   // three −1 cards for one character
        top(.road, "21")
        let hand = CardPool.defaultHand(gm.characterManager.abilities(for: brute), chosen: [], handSize: brute.handSize)
        brute.handCards = hand
        tinkerer.handCards = CardPool.defaultHand(gm.characterManager.abilities(for: tinkerer), chosen: [], handSize: tinkerer.handSize)
        var discard = EventCardManager.Choices()
        discard.discards = [brute.id: Array(hand.prefix(2)), tinkerer.id: Array(tinkerer.handCards.prefix(2))]
        XCTAssertEqual(events.discardRequirements(events.topCard(.road)!, option: "B"), [brute.id: 2, tinkerer.id: 2])
        events.resolve(.road, option: "B", choices: discard)   // two cards discarded each

        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        let minusOnesBefore = tinkerer.attackModifierDeck.attackModifiers.filter { $0.type == .minus1 }.count
        gm.startScenarioOnBoard(scenario)

        XCTAssertEqual(brute.health, brute.maxHealth - 3)
        XCTAssertTrue(brute.entityConditions.contains { $0.name == .poison })
        XCTAssertEqual(tinkerer.attackModifierDeck.attackModifiers.filter { $0.type == .minus1 }.count, minusOnesBefore + 3)
        XCTAssertEqual(Set(brute.discardedCards), Set(hand.prefix(2)))
        XCTAssertFalse(brute.handCards.contains(hand[0]))
        XCTAssertTrue(game.events.nextScenario.isEmpty, "applied once")
    }

    func testFinishingAScenarioOwesACityEvent() throws {
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        XCTAssertFalse(game.events.cityEventDue)
        gm.startScenarioOnBoard(scenario)
        gm.completeScenario(success: true)
        XCTAssertTrue(game.events.cityEventDue)
        XCTAssertTrue(events.needsRoadEvent(for: scenario), "Black Barrow is reached by road")
    }

    /// Every option of every card the party can take resolves, and what it reports reads
    /// cleanly. (An option with no outcome for this party, such as selling a potion they don't
    /// have, can't be taken; every card leaves at least one option open.)
    func testEveryOptionResolvesInPlainWords() throws {
        for card in gm.editionStore.events(for: "gh") {
            let deck = try XCTUnwrap(EventCardManager.Deck(rawValue: card.type))
            XCTAssertTrue((card.options ?? []).contains { events.outcome(card, option: $0.label ?? "") != nil },
                          "\(card.id): some option is open")
            for option in card.options ?? [] {
                top(deck, card.cardId)
                let label = try XCTUnwrap(option.label)
                guard events.outcome(card, option: label) != nil else {
                    XCTAssertNil(events.resolve(deck, option: label), "\(card.id) \(label) can't be taken")
                    continue
                }
                let resolution = try XCTUnwrap(events.resolve(deck, option: label), "\(card.id) \(label)")
                XCTAssertFalse(resolution.narrative.isEmpty, "\(card.id) \(label)")
                for line in resolution.effects {
                    XCTAssertEqual(PlayerTextTests.lint(line), [], "\(card.id) \(label): \(line)")
                }
            }
        }
    }

    /// `EVENT_RENDER_OUT=/tmp/e swift test --filter testRenderEvent` renders city 05 and road 28.
    func testRenderEvent() throws {
        guard let out = ProcessInfo.processInfo.environment["EVENT_RENDER_OUT"] else {
            throw XCTSkip("set EVENT_RENDER_OUT to render events")
        }
        GlavenFont.registerFonts()
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for (deck, id) in [(EventCardManager.Deck.city, "05"), (.road, "28")] {
            top(deck, id)
            let view = EventSheet(deck: deck) {}.environment(gm).frame(width: 1376, height: 1032)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "\(out)/\(deck)-\(id).png"))
        }
    }
}
