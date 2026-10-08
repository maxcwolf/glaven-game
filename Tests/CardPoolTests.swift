import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Ability cards between scenarios (GH p.44): a character's pool is their level 1 and X cards plus
/// one card chosen per level gained, of that level or lower; they bring a hand from that pool.
@MainActor
final class CardPoolTests: XCTestCase {

    private var gm: GameManager!
    private var brute: GameCharacter { gm.game.characters[0] }
    private var manager: CharacterManager { gm.characterManager }

    override func setUpWithError() throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
    }

    private func cards(level: Int) -> [AbilityModel] {
        manager.abilities(for: brute).filter { CardPool.level(of: $0) == level }
    }

    func testALevelOneCharacterHasTheirStartingCardsAndNothingToChoose() {
        let pool = manager.cardPool(for: brute)
        XCTAssertTrue(pool.allSatisfy(CardPool.isStarting), "level 1 and X cards only")
        XCTAssertEqual(pool.count, cards(level: 1).count + manager.abilities(for: brute).filter { CardPool.level(of: $0) == nil }.count)
        XCTAssertEqual(manager.pendingCardChoices(for: brute), 0)
        XCTAssertTrue(manager.choosableCards(for: brute).isEmpty)
    }

    func testEachLevelAddsOneCardOfThatLevelOrLower() throws {
        brute.experience = 95   // enough for level 3
        manager.levelUp(brute)
        XCTAssertEqual(manager.pendingCardChoices(for: brute), 1)
        XCTAssertEqual(Set(manager.choosableCards(for: brute).compactMap { CardPool.level(of: $0) }), [2])
        let levelTwo = try XCTUnwrap(cards(level: 2).first?.cardId)
        XCTAssertTrue(manager.chooseCard(levelTwo, for: brute))
        XCTAssertFalse(manager.chooseCard(try XCTUnwrap(cards(level: 2).last?.cardId), for: brute),
                       "one card per level")

        manager.levelUp(brute)
        XCTAssertEqual(Set(manager.choosableCards(for: brute).compactMap { CardPool.level(of: $0) }), [2, 3],
                       "level 3 may take a level 3 card or the other level 2 card")
        XCTAssertFalse(manager.choosableCards(for: brute).contains { $0.cardId == levelTwo }, "not one already chosen")
        let levelThree = try XCTUnwrap(cards(level: 3).first?.cardId)
        XCTAssertTrue(manager.chooseCard(levelThree, for: brute))
        XCTAssertTrue(manager.cardPool(for: brute).contains { $0.cardId == levelThree })
        XCTAssertFalse(manager.cardPool(for: brute).contains { $0.cardId == cards(level: 2).last?.cardId },
                       "cards not chosen stay out of the pool")
    }

    func testAHandComesFromThePoolAndFillsTheHandSize() throws {
        let pool = manager.cardPool(for: brute).compactMap(\.cardId)
        XCTAssertGreaterThan(pool.count, brute.handSize, "the X cards make the pool bigger than the hand")
        let hand = Array(pool.suffix(brute.handSize))
        XCTAssertTrue(manager.setHand(hand, for: brute))
        XCTAssertEqual(brute.handCards, hand)
        XCTAssertFalse(manager.setHand(Array(hand.dropLast()), for: brute), "a full hand")
        let notInPool = try XCTUnwrap(cards(level: 2).first?.cardId)
        XCTAssertFalse(manager.setHand(Array(hand.dropLast()) + [notInPool], for: brute), "only cards from the pool")
    }

    /// Entering a scenario with no hand chosen brings the level 1 cards, as before.
    func testTheDefaultHandIsTheLevelOneCards() {
        let hand = CardPool.defaultHand(manager.abilities(for: brute), chosen: [], handSize: brute.handSize)
        XCTAssertEqual(Set(hand), Set(cards(level: 1).compactMap(\.cardId).prefix(brute.handSize)))
    }

    /// Saves from before cards were chosen keep the higher-level cards the character carries.
    func testOlderSavesKeepTheCardsTheyCarry() throws {
        brute.level = 3
        let carried = [try XCTUnwrap(cards(level: 2).first?.cardId), try XCTUnwrap(cards(level: 3).first?.cardId)]
        brute.handCards = cards(level: 1).compactMap(\.cardId).prefix(8) + carried
        var snapshot = brute.toSnapshot()
        snapshot.chosenCards = nil   // as an older save has it
        let restored = snapshot.toRuntime(editionStore: gm.editionStore)
        XCTAssertEqual(Set(restored.chosenCards), Set(carried))
        XCTAssertEqual(CardPool.pendingChoices(level: 3, chosen: restored.chosenCards), 0)

        brute.chosenCards = [carried[0]]
        XCTAssertEqual(brute.toSnapshot().toRuntime(editionStore: gm.editionStore).chosenCards, [carried[0]],
                       "a newer save keeps exactly what was chosen")
    }

    /// `CARDS_RENDER_OUT=/tmp/c swift test --filter testRenderCardChoice` renders the level-up choice.
    func testRenderCardChoice() throws {
        guard let out = ProcessInfo.processInfo.environment["CARDS_RENDER_OUT"] else {
            throw XCTSkip("set CARDS_RENDER_OUT to render the card choice")
        }
        GlavenFont.registerFonts()
        brute.experience = 95
        manager.levelUp(brute)
        manager.levelUp(brute)
        let character = brute
        let cards = manager.choosableCards(for: character)
        let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(cards) { card in
                AbilityCardTile(card: card, character: character, selected: card.cardId == cards.first?.cardId)
            }
        }
        .padding(20).frame(width: 1000).background(Color(red: 0.09, green: 0.075, blue: 0.065)).environment(gm)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
