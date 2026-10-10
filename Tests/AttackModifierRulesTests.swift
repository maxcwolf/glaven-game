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

    // MARK: - Perks as they are taken in town

    /// A character with `perks` perks to take, at the level that earns them.
    @MainActor
    private func veteran(_ name: String, perks: Int) throws -> (GameManager, GameCharacter) {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.partyProsperity = 64
        gm.characterManager.addCharacter(name: name, edition: "gh", level: perks + 1)
        gm.characterManager.addCharacter(name: name == "tinkerer" ? "spellweaver" : "tinkerer", edition: "gh")
        let character = gm.game.characters[0]
        XCTAssertEqual(gm.characterManager.perksAvailable(for: character), perks)
        return (gm, character)
    }

    private func count(_ type: AttackModifierType, in character: GameCharacter) -> Int {
        character.attackModifierDeck.attackModifiers.filter { $0.type == type && !$0.rolling }.count
    }

    /// Brute: "Replace one −1 card with one +1 card" — the deck stays 20 cards.
    @MainActor
    func testAReplacePerkSwapsOneCardForAnother() throws {
        let (gm, brute) = try veteran("brute", perks: 1)
        XCTAssertEqual([count(.minus1, in: brute), count(.plus1, in: brute)], [5, 5])
        XCTAssertTrue(gm.characterManager.takePerk(at: 1, for: brute))
        XCTAssertEqual([count(.minus1, in: brute), count(.plus1, in: brute)], [4, 6])
        XCTAssertEqual(brute.attackModifierDeck.attackModifiers.count, 20)
    }

    /// Brute: "Add three rolling Push 1 cards" (twice), "Add one rolling Stun card", and "Add
    /// one +1 Shield 1, Self card": rolling cards roll, and each carries its effect.
    @MainActor
    func testRollingAndEffectPerkCardsJoinTheDeck() throws {
        let (gm, brute) = try veteran("brute", perks: 4)
        for index in [4, 4, 6, 9] { XCTAssertTrue(gm.characterManager.takePerk(at: index, for: brute), "perk \(index)") }
        let deck = brute.attackModifierDeck.attackModifiers
        XCTAssertEqual(deck.count, 20 + 6 + 1 + 1)
        let rolling = deck.filter(\.rolling)
        XCTAssertEqual(rolling.count, 7)
        XCTAssertTrue(rolling.allSatisfy { $0.value == 0 }, "a rolling card adds its effect, not a number")
        XCTAssertEqual(rolling.filter { $0.effects.first?.type == .push && $0.effects.first?.value?.intValue == 1 }.count, 6)
        XCTAssertEqual(rolling.filter { $0.effects.first?.type == .condition && $0.effects.first?.value?.stringValue == "stun" }.count, 1)
        let shield = try XCTUnwrap(deck.first { !$0.rolling && $0.effects.first?.type == .shield })
        XCTAssertEqual(shield.value, 1)
        XCTAssertEqual(shield.effects.first?.value?.intValue, 1)
        XCTAssertFalse(deck.contains { $0.rolling && $0.shuffle }, "no perk card calls a reshuffle")
    }

    /// Brute: "Ignore negative item effects and add one +1 card". Hide Armor's two −1 cards
    /// stay out of the deck as the scenario starts; without the perk they go in.
    @MainActor
    func testThePerkIgnoresAnItemsMinusOneCards() throws {
        let scenario = { (gm: GameManager) in try XCTUnwrap(gm.editionStore.scenarioData(index: "1", edition: "gh")) }
        let (plain, bare) = try veteran("brute", perks: 1)
        bare.items = ["gh-3"]   // Hide Armor: two −1 cards
        plain.startScenarioOnBoard(try scenario(plain))
        XCTAssertEqual(count(.minus1, in: bare), 7)

        let (gm, brute) = try veteran("brute", perks: 1)
        XCTAssertTrue(gm.characterManager.takePerk(at: 10, for: brute))
        XCTAssertEqual(count(.plus1, in: brute), 6, "the perk's own +1 card")
        brute.items = ["gh-3"]
        gm.startScenarioOnBoard(try scenario(gm))
        XCTAssertEqual(count(.minus1, in: brute), 5, "no −1 cards from the armor")
    }

    /// Second Skin sets two −1 cards aside for the scenario. That is the item's gift, not a
    /// negative effect: the perk that ignores negative item effects doesn't cancel it.
    @MainActor
    func testSecondSkinStillWorksWithThePerk() throws {
        let (gm, brute) = try veteran("brute", perks: 1)
        XCTAssertTrue(gm.characterManager.takePerk(at: 10, for: brute))
        brute.items = [PassiveItems.secondSkin, "gh-38"]   // with a Heavy Basinet: two −1 cards
        gm.startScenarioOnBoard(try XCTUnwrap(gm.editionStore.scenarioData(index: "1", edition: "gh")))
        XCTAssertEqual(count(.minus1, in: brute), 3, "five, less Second Skin's two, and none from the helmet")
        gm.completeScenario(success: false)
        XCTAssertEqual(count(.minus1, in: brute), 5, "back after the scenario")

        let (plain, bare) = try veteran("brute", perks: 1)
        bare.items = [PassiveItems.secondSkin, "gh-38"]
        plain.startScenarioOnBoard(try XCTUnwrap(plain.editionStore.scenarioData(index: "1", edition: "gh")))
        XCTAssertEqual(count(.minus1, in: bare), 5, "without the perk: plus the helmet's two, less Second Skin's two")
    }

    /// Doomstalker: "Ignore negative scenario effects". #6 Decaying Crypt gives every character
    /// three Curses as a scenario effect; the perk's holder gets none, their companion all three.
    @MainActor
    func testThePerkIgnoresNegativeScenarioEffects() throws {
        let (gm, doomstalker) = try veteran("angry-face", perks: 1)
        let companion = gm.game.characters[1]
        XCTAssertTrue(gm.characterManager.takePerk(at: 9, for: doomstalker))
        XCTAssertTrue(doomstalker.hasCustomPerk("ignoreNegativeScenario"))
        gm.startScenarioOnBoard(try XCTUnwrap(gm.editionStore.scenarioData(index: "6", edition: "gh")))
        // The first round begins: the scenario's effect lands.
        gm.game.round = 1
        gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        XCTAssertEqual(companion.attackModifierDeck.undrawnCount(of: .curse), 3)
        XCTAssertEqual(doomstalker.attackModifierDeck.undrawnCount(of: .curse), 0)
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

    /// The FAQ's examples for cards with effects: an effect is worth something, but how much is
    /// undefined, so a card is better beyond doubt only when it is no worse in value and has all
    /// the other's effects; otherwise the card drawn first is used.
    func testAdvantageWeighsACardsEffects() {
        func draw(_ cards: [AttackModifier]) -> () -> AttackModifier? {
            var queue = cards
            return { queue.isEmpty ? nil : queue.removeFirst() }
        }
        func card(_ type: AttackModifierType, _ id: String, _ condition: String? = nil, element: String? = nil) -> AttackModifier {
            var card = AttackModifier.standard(type)
            card.id = id
            if let condition { card.effects.append(AttackModifierEffect(type: .condition, value: .string(condition))) }
            if let element { card.effects.append(AttackModifierEffect(type: .element, value: .string(element))) }
            return card
        }
        func kept(_ cards: [AttackModifier], advantage: Bool, base: Int = 3) -> String? {
            CombatResolver.drawModifiers(advantage: advantage, disadvantage: !advantage, baseAttack: base,
                                         draw: draw(cards)).first?.id
        }
        let plus1 = card(.plus1, "+1"), plus1Stun = card(.plus1, "+1 stun", "stun"), plus2 = card(.plus2, "+2")
        let plus0Stun = card(.plus0, "+0 stun", "stun"), plus1Fire = card(.plus1, "+1 fire", element: "fire")
        let plus0Muddle = card(.plus0, "+0 muddle", "muddle"), plus2Stun = card(.plus2, "+2 stun", "stun")

        // "+1 Stun vs. +1: +1 Stun is better" — whichever is drawn first.
        XCTAssertEqual(kept([plus1, plus1Stun], advantage: true), "+1 stun")
        XCTAssertEqual(kept([plus1Stun, plus1], advantage: true), "+1 stun")
        XCTAssertEqual(kept([plus1Stun, plus1], advantage: false), "+1", "and the worse for disadvantage")
        XCTAssertEqual(kept([plus1, plus1Stun], advantage: false), "+1")

        // "+0 Stun vs. +2", "+1 Stun vs. +1 Fire", "+0 Muddle vs. +2 Stun": ambiguous — the first drawn.
        for pair in [[plus0Stun, plus2], [plus1Stun, plus1Fire], [plus0Muddle, plus2Stun]] {
            for advantage in [true, false] {
                XCTAssertEqual(kept(pair, advantage: advantage), pair[0].id)
                XCTAssertEqual(kept(pair.reversed(), advantage: advantage), pair[1].id)
            }
        }

        // The same effect on both: the value decides.
        XCTAssertEqual(kept([plus0Stun, plus2Stun], advantage: true), "+2 stun")
        XCTAssertEqual(kept([plus2Stun, plus0Stun], advantage: false), "+0 stun")

        // "2x vs. Attack 2 and +2: ambiguous" (both make 4); "2x vs. Attack 2 and +1: 2x is better".
        let double = card(.double_, "x2")
        XCTAssertEqual(kept([plus2, double], advantage: true, base: 2), "+2")
        XCTAssertEqual(kept([double, plus2], advantage: true, base: 2), "x2")
        XCTAssertEqual(kept([plus1, double], advantage: true, base: 2), "x2")
        XCTAssertEqual(kept([double, plus1], advantage: false, base: 2), "+1")

        // A null is worse than anything, effect or not.
        XCTAssertEqual(kept([card(.null_, "miss"), plus0Stun], advantage: true), "+0 stun")
        XCTAssertEqual(kept([plus0Stun, card(.null_, "miss")], advantage: false), "miss")
    }
}
