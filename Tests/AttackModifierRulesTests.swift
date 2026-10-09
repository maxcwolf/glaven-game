import XCTest
@testable import GlavenGameLib

/// Attack modifier deck and draw rules (GH rulebook p.19–20, p.23).
final class AttackModifierRulesTests: XCTestCase {

    private func card(_ value: Int, rolling: Bool = false) -> AttackModifier {
        AttackModifier(type: value >= 0 ? .plus1 : .minus1, value: value, rolling: rolling)
    }

    private func drawer(_ cards: [AttackModifier]) -> () -> AttackModifier? {
        var queue = cards
        return { queue.isEmpty ? nil : queue.removeFirst() }
    }

    // MARK: - Edition data decoding

    func testPerkCardsDecodeWithPrintedValues() throws {
        let json = #"[{"type":"plus1"},{"type":"minus2"},{"type":"plus3"},{"type":"double"},{"type":"null"}]"#
        let cards = try JSONDecoder().decode([AttackModifier].self, from: Data(json.utf8))
        XCTAssertEqual(cards.map(\.value), [1, -2, 3, 2, 0])
        XCTAssertEqual(cards[3].valueType, .multiply)
        XCTAssertEqual(cards[4].valueType, .multiply)
        XCTAssertTrue(cards[3].shuffle && cards[4].shuffle, "×2 and null trigger the end-of-round reshuffle")
    }

    func testRemovePerkMatchesBaseDeckMinusOnes() throws {
        // Brute perk 0: "Remove two -1 cards"
        let store = EditionDataStore()
        store.loadAllEditions()
        let game = GameState()
        let data = try XCTUnwrap(store.characterData(name: "brute", edition: "gh"))
        let character = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: data)
        character.selectedPerks = [1]
        AttackModifierManager(game: game).buildCharacterDeck(for: character)
        XCTAssertEqual(character.attackModifierDeck.attackModifiers.filter { $0.type == .minus1 }.count, 3,
                       "5 base -1 cards minus 2 removed")
    }

    func testAddPerkCardsCarryTheirValue() throws {
        // Brute perk 3: "Add one +3 card"
        let store = EditionDataStore()
        store.loadAllEditions()
        let data = try XCTUnwrap(store.characterData(name: "brute", edition: "gh"))
        let character = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: data)
        character.selectedPerks = [0, 0, 0, 1]
        AttackModifierManager(game: GameState()).buildCharacterDeck(for: character)
        let plus3 = character.attackModifierDeck.attackModifiers.filter { $0.type == .plus3 }
        XCTAssertEqual(plus3.map(\.value), [3])
    }

    // MARK: - Deck behaviour

    func testEmptyDeckReshufflesOnDraw() {
        var deck = AttackModifierDeck.defaultDeck()
        for _ in 0..<deck.cards.count { _ = deck.draw() }
        XCTAssertEqual(deck.remainingCount, 0)
        XCTAssertNotNil(deck.draw(), "Drawing from an empty deck reshuffles the discards back in")
        XCTAssertEqual(deck.cards.count, 20)
    }

    func testBlessIsDoubleAndCurseIsNull() {
        var deck = AttackModifierDeck.defaultDeck()
        deck.addCard(type: .bless)
        deck.addCard(type: .curse)
        let bless = deck.cards.first { $0.type == .bless }!
        let curse = deck.cards.first { $0.type == .curse }!
        XCTAssertEqual(bless.valueType, .multiply)
        XCTAssertEqual(bless.value, 2)
        XCTAssertEqual(curse.valueType, .multiply)
        XCTAssertEqual(curse.value, 0)
    }

    func testDrawnBlessDoesNotForceReshuffle() {
        var deck = AttackModifierDeck(attackModifiers: [AttackModifier.standard(.plus0)],
                                      cards: [AttackModifier.standard(.bless), AttackModifier.standard(.plus0)])
        _ = deck.draw()
        XCTAssertFalse(deck.needsShuffle, "Only standard ×2/null cards trigger a reshuffle")
    }

    func testDrawnBlessIsRemovedOnReshuffle() {
        var deck = AttackModifierDeck.defaultDeck()
        deck.cards.insert(AttackModifier.standard(.bless), at: 0)
        _ = deck.draw()
        deck.reshuffle()
        XCTAssertFalse(deck.cards.contains { $0.type == .bless }, "A drawn Bless leaves the deck")
    }

    func testCurseCapCountsOnlyUndrawnCards() {
        var deck = AttackModifierDeck.defaultDeck()
        for _ in 0..<10 { deck.addCard(type: .curse) }
        deck.addCard(type: .curse)
        XCTAssertEqual(deck.undrawnCount(of: .curse), 10, "Max 10 curses in a deck")
        // Draw until a curse comes out, then one more can be added.
        while deck.draw()?.type != .curse {}
        deck.addCard(type: .curse)
        XCTAssertEqual(deck.undrawnCount(of: .curse), 10)
    }

    func testScenarioMinusOneSurvivesReshuffle() {
        var deck = AttackModifierDeck.defaultDeck()
        deck.addCard(type: .minus1)
        deck.reshuffle()
        XCTAssertEqual(deck.cards.count, 21)
        XCTAssertEqual(deck.cards.filter { $0.type == .minus1 }.count, 6)
        XCTAssertTrue(deck.cards.filter { $0.type == .minus1 }.allSatisfy { $0.value == -1 })
    }

    // MARK: - Advantage / disadvantage selection (p.20)

    func testAdvantagePicksBetterCard() {
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: false,
                                                 draw: drawer([card(-1), card(2)]))
        XCTAssertEqual(cards.map(\.value), [2])
    }

    func testDisadvantagePicksWorseCard() {
        let cards = CombatResolver.drawModifiers(advantage: false, disadvantage: true,
                                                 draw: drawer([card(-1), card(2)]))
        XCTAssertEqual(cards.map(\.value), [-1])
    }

    func testAdvantageAndDisadvantageCancelToSingleDraw() {
        var drawn = 0
        let draw = drawer([card(1, rolling: true), card(1), card(-2)])
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: true) {
            drawn += 1
            return draw()
        }
        XCTAssertEqual(cards.map(\.value), [1, 1], "Normal draw: rolling chain applies in full")
        XCTAssertEqual(drawn, 2, "No second card is drawn")
    }

    func testAdvantageWithRollingAddsCardsTogether() {
        // +1 rolling then +2: the rolling card is added to the other card (+3), no comparison.
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: false,
                                                 draw: drawer([card(1, rolling: true), card(2), card(5)]))
        XCTAssertEqual(cards.map(\.value), [1, 2])
    }

    func testAdvantageRollingThenNullIsAMiss() {
        let null = AttackModifier.standard(.null_)
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: false,
                                                 draw: drawer([card(1, rolling: true), null]))
        let result = CombatResolver.resolveAttack(attacker: .character("a"), defender: .monster(name: "m", standee: 1),
                                                  baseAttack: 3, preDrawnCards: cards,
                                                  drawModifier: { nil }, defenderHealth: 10)
        XCTAssertTrue(result.isMiss, "With advantage a rolling draw can still miss (p.20)")
    }

    func testAdvantageRollingThenDoubleAddsBeforeDoubling() {
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: false,
                                                 draw: drawer([card(1, rolling: true), AttackModifier.standard(.double_)]))
        let result = CombatResolver.resolveAttack(attacker: .character("a"), defender: .monster(name: "m", standee: 1),
                                                  baseAttack: 3, preDrawnCards: cards,
                                                  drawModifier: { nil }, defenderHealth: 20)
        XCTAssertEqual(result.damage, 8, "(3 + 1) × 2")
    }

    func testAdvantageBothRollingContinuesToNonRolling() {
        let cards = CombatResolver.drawModifiers(advantage: true, disadvantage: false,
                                                 draw: drawer([card(1, rolling: true), card(1, rolling: true), card(0), card(9)]))
        XCTAssertEqual(cards.map(\.value), [1, 1, 0])
    }

    func testDisadvantageIgnoresRollingCards() {
        let cards = CombatResolver.drawModifiers(advantage: false, disadvantage: true,
                                                 draw: drawer([card(2, rolling: true), card(-1), card(5)]))
        XCTAssertEqual(cards.map(\.value), [-1], "Rolling card disregarded; the other card applies")
    }

    func testDisadvantageBothRollingUsesNextNonRolling() {
        let cards = CombatResolver.drawModifiers(advantage: false, disadvantage: true,
                                                 draw: drawer([card(1, rolling: true), card(1, rolling: true), card(2)]))
        XCTAssertEqual(cards.map(\.value), [2])
    }

    func testRollingPierceReducesShield() {
        var pierceCard = card(0, rolling: true)
        pierceCard.effects = [AttackModifierEffect(type: .pierce, value: .int(2))]
        let result = CombatResolver.resolveAttack(attacker: .character("a"), defender: .monster(name: "m", standee: 1),
                                                  baseAttack: 3, shield: 2, preDrawnCards: [pierceCard, card(0)],
                                                  drawModifier: { nil }, defenderHealth: 10)
        XCTAssertEqual(result.damage, 3, "Pierce 2 from a modifier card cancels Shield 2")
    }

    /// Advantage keeps the card that makes the better attack, disadvantage the worse (p.20): on
    /// Attack 1, +2 (3) beats ×2 (2). A null is always the worst; equal attacks keep the first.
    func testAdvantageComparesTheAttacksTheCardsMake() {
        func draw(_ cards: [AttackModifier]) -> () -> AttackModifier? {
            var queue = cards
            return { queue.isEmpty ? nil : queue.removeFirst() }
        }
        let double = AttackModifier.standard(.double_), plus2 = AttackModifier.standard(.plus2)
        XCTAssertEqual(CombatResolver.drawModifiers(advantage: true, disadvantage: false, baseAttack: 1,
                                                    draw: draw([double, plus2])).map(\.type), [.plus2])
        XCTAssertEqual(CombatResolver.drawModifiers(advantage: false, disadvantage: true, baseAttack: 1,
                                                    draw: draw([plus2, double])).map(\.type), [.double_])
        XCTAssertEqual(CombatResolver.drawModifiers(advantage: true, disadvantage: false, baseAttack: 3,
                                                    draw: draw([plus2, double])).map(\.type), [.double_], "on Attack 3, ×2 is better")
        XCTAssertEqual(CombatResolver.drawModifiers(advantage: false, disadvantage: true, baseAttack: 1,
                                                    draw: draw([AttackModifier.standard(.minus2), AttackModifier.standard(.null_)])).map(\.type),
                       [.null_], "a null is the worst even when −2 also makes 0")

        // Through the whole attack: Attack 1 with advantage drawing ×2 then +2 deals 3.
        let result = CombatResolver.resolveAttack(attacker: .character("a"), defender: .monster(name: "x", standee: 1),
                                                  baseAttack: 1, advantage: true,
                                                  drawModifier: draw([double, plus2]), defenderHealth: 10)
        XCTAssertEqual(result.damage, 3)
    }
}
