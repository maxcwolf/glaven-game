import XCTest
import SwiftUI
import SwiftData
@testable import GlavenGameLib

/// Enhancements (GH p.42–43): bought at the Enhancer once The Power of Enhancement is earned,
/// paid in the character's gold, priced by slot, card level and earlier enhancements — and
/// played on the board as part of the card.
@MainActor
final class EnhancementTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var enhancer: EnhancementsManager { gm.enhancementsManager }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    private func card(_ name: String, of deck: String) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
    }

    @discardableResult
    private func addCharacter(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    private func slot(_ card: AbilityModel, half: String, action: Int, slot: Int = 0) throws -> CardEnhancing.Slot {
        try XCTUnwrap(CardEnhancing.slots(of: card).first {
            $0.half == half && $0.actionIndex == action && $0.slotIndex == slot
        })
    }

    // MARK: - Slots and what they take

    func testTheSlotsOfACard() throws {
        let trample = try card("Trample", of: "brute")
        let slots = CardEnhancing.slots(of: trample)
        // Attack 3 ◆, Pierce 2 ◆ | Move 4 ●, Attack 2 ◆◆
        XCTAssertEqual(slots.map(\.id), ["1-top-0-0", "1-top-100-0", "1-bottom-0-0", "1-bottom-1-0", "1-bottom-1-1"])
        XCTAssertEqual(slots[1].action.type, .pierce)
        XCTAssertEqual(slots[1].host.type, .attack, "a slot on Pierce belongs to the attack")
    }

    /// A summon's stats are slots of their own (GH p.47): +1 Move or Attack for 100 gold, +1 hit
    /// point or Range for 50, nothing else — and the summon the card makes has them.
    func testASummonsStatsAreEnhanced() throws {
        let ally = try card("Relentless Ally", of: "two-mini")   // Tattered Wolf: 4 hit points, Move 3, Attack 2
        let stats = CardEnhancing.slots(of: ally).filter(CardEnhancing.isSummonStat)
        XCTAssertEqual(stats.map(EnhancementSheet.line), ["Tattered Wolf · Attack 2", "Tattered Wolf · Move 3", "Tattered Wolf · Hit Points 4"])
        for slot in stats {
            XCTAssertEqual(CardEnhancing.options(for: slot, edition: "gh"), [.plus1])
            XCTAssertEqual(CardEnhancing.cost(.plus1, in: slot, card: ally, enhancements: [], edition: "gh"),
                           slot.action.type == .heal ? 50 : 100)
        }

        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        let tyrant = addCharacter("two-mini", at: HexCoord(5, 5))
        tyrant.loot = 500
        let attack = try XCTUnwrap(stats.first { $0.action.type == .attack })
        let health = try XCTUnwrap(stats.first { $0.action.type == .heal })
        XCTAssertTrue(enhancer.buy(.plus1, in: attack, card: ally, for: tyrant))
        XCTAssertTrue(enhancer.buy(.plus1, in: health, card: ally, for: tyrant))
        XCTAssertEqual(tyrant.loot, 500 - 100 - (50 + 75), "the second on the card costs 75 more")

        let other = try card("Venomous Ally", of: "two-mini")
        tyrant.handCards = [ally.cardId!, other.cardId!]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: tyrant.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: ally, bottom: other)
        turn.executeCurrentAction()   // summon the Tattered Wolf
        let wolf = try XCTUnwrap(tyrant.summons.last { $0.name == "tattered-wolf" })
        XCTAssertEqual(wolf.attack.intValue, 3, "Attack 2 + 1")
        XCTAssertEqual(wolf.maxHealth, 5, "4 hit points + 1")
        XCTAssertEqual(wolf.movement, 3, "Move as printed")
    }

    private static let elements: [EnhancementAction] = [.fire, .ice, .air, .earth, .light, .dark, .wild]

    /// What each kind of line takes (GH p.47): +1 on any line with a number; an element on any
    /// main line; a negative condition on a main line that targets enemies; Bless or Strengthen
    /// on one that affects allies or the character; Jump on a Move.
    func testASlotOffersWhatItsLineTakes() throws {
        let trample = try card("Trample", of: "brute")
        let attack = CardEnhancing.options(for: try slot(trample, half: "top", action: 0), edition: "gh")
        XCTAssertEqual(attack, [.plus1, .poison, .wound, .muddle, .immobilize, .curse, .disarm] + Self.elements)
        let pierce = CardEnhancing.options(for: try slot(trample, half: "top", action: 100), edition: "gh")
        XCTAssertEqual(pierce, [.plus1], "a small line under an attack takes its +1 and nothing else")
        let jumping = CardEnhancing.options(for: try slot(trample, half: "bottom", action: 0), edition: "gh")
        XCTAssertEqual(jumping, [.plus1] + Self.elements, "Trample's move jumps already")
        let grab = try card("Grab and Go", of: "brute")   // bottom: Move 4
        let moveSlot = try slot(grab, half: "bottom", action: 0)
        XCTAssertEqual(CardEnhancing.options(for: moveSlot, edition: "gh"), [.plus1] + Self.elements + [.jump])
        let jumped = CardEnhancing.apply(
            [Enhancement(cardId: grab.cardId!, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .jump)],
            to: grab.bottomActions ?? [], cardId: grab.cardId, half: "bottom")
        XCTAssertTrue(jumped[0].subActions?.contains { $0.type == .jump } == true, "the move is a jump from then on")

        let novas = try card("Freezing Nova", of: "spellweaver")
        let heal = CardEnhancing.options(for: try slot(novas, half: "bottom", action: 0), edition: "gh")
        XCTAssertEqual(heal, [.plus1, .strengthen, .bless] + Self.elements)

        let area = try XCTUnwrap(gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
            .flatMap(CardEnhancing.slots).first { $0.type == .hex })
        XCTAssertEqual(CardEnhancing.options(for: area, edition: "gh"), area.action.value?.stringValue.contains("enhance") == true ? [.hex] : [])
    }

    /// Over every Gloomhaven card: Jump is sold on Move lines that don't jump already and
    /// nowhere else, every plain Move line sells it, and nothing sells Regenerate or Ward
    /// (Frosthaven's stickers).
    func testJumpIsSoldOnEveryMoveAndNothingFromFrosthaven() throws {
        var moves = 0
        for data in gm.editionStore.characters(for: "gh") {
            for card in gm.editionStore.abilities(forDeck: data.deck ?? data.name, edition: "gh") {
                for slot in CardEnhancing.slots(of: card) {
                    let options = CardEnhancing.options(for: slot, edition: "gh")
                    XCTAssertTrue(Set(options).isDisjoint(with: [.regenerate, .ward, .bane, .brittle, .impair]),
                                  "\(card.name ?? "") \(slot.id): \(options)")
                    let plainMove = slot.actionIndex < 100 && slot.action.type == .move
                        && !(slot.action.subActions ?? []).contains { $0.type == .jump }
                    XCTAssertEqual(options.contains(.jump), plainMove, "\(card.name ?? "") \(slot.id)")
                    if plainMove { moves += 1 }
                }
            }
        }
        XCTAssertGreaterThan(moves, 150, "the Move lines were found")
    }

    /// A condition printed as an ability of its own takes a second condition and an element
    /// when it reaches everyone it names; one with a single target to choose isn't sold yet.
    func testAConditionLineTakesAnotherCondition() throws {
        let chorus = try card("Crippling Chorus", of: "music-note")   // top: Stun, all enemies within Range 3
        let stun = try slot(chorus, half: "top", action: 0)
        XCTAssertEqual(CardEnhancing.options(for: stun, edition: "gh"),
                       [.poison, .wound, .muddle, .immobilize, .curse, .disarm] + Self.elements, "no number to add one to")
        XCTAssertEqual(CardEnhancing.cost(.muddle, in: stun, card: chorus, enhancements: [], edition: "gh"), 50 * 2 + 50,
                       "double for several targets, and a level 3 card")

        let trill = try card("Tuning the Outcome", of: "music-note")   // top: Bless, all adjacent allies
        let bless = try slot(trill, half: "top", action: 0)
        XCTAssertEqual(CardEnhancing.options(for: bless, edition: "gh"), [.strengthen] + Self.elements,
                       "Strengthen beside the Bless it already gives")

        let net = try card("Net Shooter", of: "tinkerer")   // bottom: Immobilize one adjacent enemy
        let single = try XCTUnwrap(CardEnhancing.slots(of: net).first { $0.half == "bottom" && $0.action.type == .condition })
        XCTAssertEqual(CardEnhancing.options(for: single, edition: "gh"), [])

        // Played: the second condition is one more ability for the same figures.
        let enhanced = CardEnhancing.apply(
            [Enhancement(cardId: chorus.cardId!, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .muddle)],
            to: chorus.actions ?? [], cardId: chorus.cardId, half: "top")
        XCTAssertEqual(enhanced.prefix(2).map(\.type), [.condition, .condition])
        XCTAssertEqual(enhanced.prefix(2).compactMap { $0.value?.stringValue }, ["stun", "muddle"])
        XCTAssertEqual(enhanced[1].subActions?.first { $0.type == .specialTarget }?.value?.stringValue, "enemiesRange:3")
        XCTAssertEqual(enhanced.count, (chorus.actions ?? []).count + 1)
    }

    func testAnEnhancedConditionLinePlaysBothConditions() throws {
        let singer = addCharacter("music-note", at: HexCoord(3, 3))
        var bandits: [GameMonsterEntity] = []
        for hex in [HexCoord(4, 3), HexCoord(5, 3)] {
            let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
            guard case .monster(_, let standee) = piece else { return XCTFail() }
            bandits.append(try XCTUnwrap(coord.monsterEntity(name: "bandit-guard", standee: standee)))
        }
        let chorus = try card("Crippling Chorus", of: "music-note")
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "music-note", edition: "gh").first { $0.cardId != chorus.cardId })
        singer.handCards = [chorus.cardId!, other.cardId!]
        singer.enhancements = [Enhancement(cardId: chorus.cardId!, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .muddle)]
        let turn = PlayerTurnController(characterID: singer.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: chorus, bottom: other)
        XCTAssertEqual(turn.topActions.prefix(2).compactMap { $0.value?.stringValue }, ["stun", "muddle"])
        turn.executeCurrentAction()
        turn.executeCurrentAction()
        for bandit in bandits {
            XCTAssertTrue(bandit.entityConditions.contains { $0.name == .stun }, "stunned as printed")
            XCTAssertTrue(bandit.entityConditions.contains { $0.name == .muddle }, "and muddled by the enhancement")
        }
    }

    // MARK: - Prices

    private func baseCost(_ action: EnhancementAction, on line: ActionType = .attack, level: Int = 1, earlier: Int = 0,
                          several: Bool = false, summon: Bool = false) -> Int {
        EnhancementsManager.enhancementCost(action: action, slotType: .any, actionType: line, cardLevel: level,
                                            previousEnhancements: earlier, isMultiTarget: several, isLost: false,
                                            isPersistent: false, isSummon: summon, edition: "gh")
    }

    /// The Enhancer's whole chart (GH p.47, first edition).
    func testEveryPriceOnTheEnhancerChart() throws {
        let plusOne: [(ActionType, Int)] = [(.move, 30), (.attack, 50), (.range, 30), (.shield, 100), (.push, 30), (.pull, 30),
                                            (.pierce, 30), (.retaliate, 100), (.heal, 30), (.target, 50)]
        for (line, gold) in plusOne { XCTAssertEqual(baseCost(.plus1, on: line), gold, "+1 \(line)") }
        let summon: [(ActionType, Int)] = [(.move, 100), (.attack, 100), (.range, 50), (.heal, 50)]
        for (line, gold) in summon { XCTAssertEqual(baseCost(.plus1, on: line, summon: true), gold, "summon +1 \(line)") }
        let stickers: [(EnhancementAction, Int)] = [
            (.poison, 75), (.wound, 75), (.muddle, 50), (.immobilize, 100), (.disarm, 150), (.curse, 75),
            (.strengthen, 50), (.bless, 50), (.jump, 50),
            (.fire, 100), (.ice, 100), (.air, 100), (.earth, 100), (.light, 100), (.dark, 100), (.wild, 150),
        ]
        for (sticker, gold) in stickers {
            XCTAssertEqual(baseCost(sticker), gold, "\(sticker)")
            XCTAssertEqual(baseCost(sticker, several: true), gold * 2, "\(sticker), several targets")
        }
        // +25 for each level of the card above the first; +75 for each enhancement already on
        // the action.
        for level in 1...9 { XCTAssertEqual(baseCost(.plus1, level: level), 50 + 25 * (level - 1), "level \(level)") }
        for earlier in 0...3 { XCTAssertEqual(baseCost(.plus1, earlier: earlier), 50 + 75 * earlier, "\(earlier) earlier") }
        XCTAssertEqual(baseCost(.plus1, level: 3, earlier: 1, several: true), 50 * 2 + 50 + 75, "the rulebook's own example and one more")

        // What the Enhancer sells in Gloomhaven is exactly what the chart prices.
        let sold = Set(EnhancementSlotType.allCases.flatMap {
            EnhancementsManager.availableActions(for: $0, actionType: .move, isSummon: false, edition: "gh")
        })
        XCTAssertEqual(sold, Set([.plus1, .hex] + stickers.map(\.0)))
    }

    /// GH p.47: the doubling for several targets "does not apply to target, area-of-effect hex,
    /// or element enhancements"; FAQ: an ability that reaches several targets only with an
    /// element consumed is single-target.
    func testOneMoreTargetAndElementsAreNeverDoubled() throws {
        let chorus = try card("Crippling Chorus", of: "music-note")   // level 3, top: Stun, all enemies within Range 3
        let stun = try slot(chorus, half: "top", action: 0)
        XCTAssertTrue(CardEnhancing.targetsSeveral(stun.host))
        XCTAssertEqual(CardEnhancing.cost(.fire, in: stun, card: chorus, enhancements: [], edition: "gh"), 100 + 50,
                       "an element is 100 whatever the targets, plus the card's level")
        XCTAssertEqual(CardEnhancing.cost(.wild, in: stun, card: chorus, enhancements: [], edition: "gh"), 150 + 50)
        XCTAssertEqual(CardEnhancing.cost(.muddle, in: stun, card: chorus, enhancements: [], edition: "gh"), 50 * 2 + 50,
                       "a condition is doubled")

        // A +1 on a printed Target line.
        var found = 0
        for name in ["brute", "spellweaver", "scoundrel", "cragheart", "tinkerer", "mindthief"] {
            for card in gm.editionStore.abilities(forDeck: name, edition: "gh") {
                for slot in CardEnhancing.slots(of: card) where slot.action.type == .target && (slot.action.value?.intValue ?? 1) > 1 {
                    found += 1
                    let level = max(0, (card.level?.intValue ?? 1) - 1) * 25
                    XCTAssertEqual(CardEnhancing.cost(.plus1, in: slot, card: card, enhancements: [], edition: "gh"), 50 + level,
                                   "\(card.name ?? "?"): +1 Target is 50, not doubled")
                }
            }
        }
        XCTAssertGreaterThan(found, 3, "Target lines with a slot were found")
    }

    /// FAQ: "an ability that targets multiple enemies only when you use an elemental infusion"
    /// is single-target.
    func testTargetsGainedByConsumingAnElementDontDouble() {
        let attack = ActionModel(type: .attack, value: .int(2), subActions: [
            ActionModel(type: .element, value: .string("fire"), valueType: .minus,
                        subActions: [ActionModel(type: .target, value: .int(2))])
        ])
        XCTAssertFalse(CardEnhancing.targetsSeveral(attack))
        let always = ActionModel(type: .attack, value: .int(2), subActions: [ActionModel(type: .target, value: .int(2))])
        XCTAssertTrue(CardEnhancing.targetsSeveral(always))
    }

    func testPricesFollowTheEnhancerChart() throws {
        let trample = try card("Trample", of: "brute")   // level 1
        let attack = try slot(trample, half: "top", action: 0)
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: attack, card: trample, enhancements: [], edition: "gh"), 50)
        XCTAssertEqual(CardEnhancing.cost(.poison, in: attack, card: trample, enhancements: [], edition: "gh"), 75)
        XCTAssertEqual(CardEnhancing.cost(.curse, in: attack, card: trample, enhancements: [], edition: "gh"), 75)
        XCTAssertEqual(CardEnhancing.cost(.immobilize, in: attack, card: trample, enhancements: [], edition: "gh"), 100)
        let move = try slot(trample, half: "bottom", action: 0)
        XCTAssertEqual(CardEnhancing.cost(.jump, in: move, card: trample, enhancements: [], edition: "gh"), 50)
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: move, card: trample, enhancements: [], edition: "gh"), 30)

        let everyoneMovedThrough = try slot(trample, half: "bottom", action: 1)
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: everyoneMovedThrough, card: trample, enhancements: [], edition: "gh"), 100,
                       "double for an ability with several targets")

        let level3 = try XCTUnwrap(gm.editionStore.abilities(forDeck: "brute", edition: "gh").first { $0.level?.intValue == 3 })
        let slot3 = try XCTUnwrap(CardEnhancing.slots(of: level3).first { CardEnhancing.options(for: $0, edition: "gh").contains(.plus1) })
        let base = CardEnhancing.cost(.plus1, in: slot3, card: trample, enhancements: [], edition: "gh")
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: slot3, card: level3, enhancements: [], edition: "gh"), base + 50,
                       "+25 a level above the first")

        let novas = try card("Freezing Nova", of: "spellweaver")
        let heal = try slot(novas, half: "bottom", action: 0)
        XCTAssertEqual(CardEnhancing.cost(.bless, in: heal, card: novas, enhancements: [], edition: "gh"), 50)
        XCTAssertEqual(CardEnhancing.cost(.strengthen, in: heal, card: novas, enhancements: [], edition: "gh"), 50)
    }

    /// +75 for each enhancement already on the same action — the same half of the card. One on
    /// the other half costs nothing more (GH p.47).
    func testEarlierEnhancementsCountOnTheSameActionOnly() throws {
        let trample = try card("Trample", of: "brute")
        let attack = try slot(trample, half: "top", action: 0)
        func cost(_ earlier: [Enhancement]) -> Int {
            CardEnhancing.cost(.plus1, in: attack, card: trample, enhancements: earlier, edition: "gh")
        }
        let onTheBottom = Enhancement(cardId: 1, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .plus1)
        let onThePierce = Enhancement(cardId: 1, actionHalf: "top", actionIndex: 100, slotIndex: 0, action: .plus1)
        let onAnotherCard = Enhancement(cardId: 2, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .plus1)
        XCTAssertEqual(cost([onTheBottom]), 50, "the bottom action's enhancement doesn't make the top dearer")
        XCTAssertEqual(cost([onAnotherCard]), 50)
        XCTAssertEqual(cost([onThePierce]), 125, "one already on this action")
        XCTAssertEqual(cost([onThePierce, onTheBottom, onAnotherCard]), 125)

        // Three slots on the bottom: Move 4, and Attack 2 twice.
        let second = try slot(trample, half: "bottom", action: 1, slot: 1)
        let bottom = [onTheBottom, Enhancement(cardId: 1, actionHalf: "bottom", actionIndex: 1, slotIndex: 0, action: .plus1)]
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: second, card: trample, enhancements: bottom + [onThePierce], edition: "gh"),
                       50 * 2 + 150, "two on the bottom; the top's one isn't counted")

        // Bought: the gold that leaves the purse is the same sum.
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        brute.loot = 500
        XCTAssertTrue(enhancer.buy(.plus1, in: try slot(trample, half: "bottom", action: 0), card: trample, for: brute))
        XCTAssertEqual(brute.loot, 470)
        XCTAssertTrue(enhancer.buy(.plus1, in: attack, card: trample, for: brute))
        XCTAssertEqual(brute.loot, 420, "50, not 125")
        XCTAssertTrue(enhancer.buy(.plus1, in: try slot(trample, half: "top", action: 100), card: trample, for: brute))
        XCTAssertEqual(brute.loot, 420 - 30 - 75, "Pierce +1 with one already on the top")
        XCTAssertEqual(EnhancementSheet.surchargeNote(edition: "gh"),
                       "Each enhancement already on the same half of a card adds 75 gold to the next one there.")
    }

    /// A class may have as many enhanced cards as the city's prosperity level (GH p.47): more
    /// on a card already enhanced is fine, another card waits for prosperity.
    func testEnhancedCardsAreLimitedByProsperity() throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        brute.loot = 1000
        let trample = try card("Trample", of: "brute"), dagger = try card("Spare Dagger", of: "brute")
        let daggerSlot = try XCTUnwrap(CardEnhancing.slots(of: dagger).first { CardEnhancing.options(for: $0, edition: "gh").contains(.plus1) })
        XCTAssertEqual(gm.game.prosperityLevel, 1)

        XCTAssertTrue(enhancer.buy(.plus1, in: try slot(trample, half: "top", action: 0), card: trample, for: brute))
        XCTAssertTrue(enhancer.buy(.plus1, in: try slot(trample, half: "bottom", action: 0), card: trample, for: brute),
                      "the same card again")
        let gold = brute.loot
        XCTAssertEqual(enhancer.purchaseProblem(.plus1, in: daggerSlot, card: dagger, for: brute), .cardLimit)
        XCTAssertFalse(enhancer.buy(.plus1, in: daggerSlot, card: dagger, for: brute))
        XCTAssertEqual(brute.loot, gold)
        XCTAssertEqual(EnhancementSheet.cardLimitNote(enhanced: 1, prosperity: 1),
                       "1 of this class\u{2019}s cards is enhanced, as many as the city\u{2019}s prosperity level (1) allows. This card can be enhanced once prosperity rises.")

        gm.game.partyProsperity = 4   // prosperity level 2
        XCTAssertTrue(enhancer.buy(.plus1, in: daggerSlot, card: dagger, for: brute))
        XCTAssertEqual(EnhancementsManager.enhancedCards(of: brute).count, 2)
    }

    /// Enhancements are on the class's cards for good (GH p.48): the next character of the
    /// class has them, plays them, pays more beside them and counts them against the limit.
    func testANewCharacterOfTheClassKeepsItsEnhancements() throws {
        let first = addCharacter("brute", at: HexCoord(3, 3))
        addCharacter("tinkerer", at: HexCoord(5, 5))
        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        first.loot = 200
        let trample = try card("Trample", of: "brute"), dagger = try card("Spare Dagger", of: "brute")
        let attack = try slot(trample, half: "top", action: 0)
        XCTAssertTrue(enhancer.buy(.plus1, in: attack, card: trample, for: first))
        coord.boardState.removePiece(.character(first.id))
        gm.characterManager.removeCharacter(first)

        let second = addCharacter("brute", at: HexCoord(3, 3))
        XCTAssertFalse(second === first)
        XCTAssertEqual(second.enhancements.map(\.action), [.plus1])
        XCTAssertEqual(enhancer.purchaseProblem(.poison, in: attack, card: trample, for: second), .slotTaken)
        second.loot = 1000
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: try slot(trample, half: "top", action: 100), card: trample,
                                          enhancements: second.enhancements, edition: "gh"), 30 + 75)
        let daggerSlot = try XCTUnwrap(CardEnhancing.slots(of: dagger).first { CardEnhancing.options(for: $0, edition: "gh").contains(.plus1) })
        XCTAssertEqual(enhancer.purchaseProblem(.plus1, in: daggerSlot, card: dagger, for: second), .cardLimit,
                       "the earlier Brute's card counts")
        let sticker = try XCTUnwrap(second.enhancements.first)
        enhancer.removeEnhancement(sticker, from: second)
        XCTAssertEqual(second.enhancements.count, 1, "a sticker is never taken off")

        second.handCards = [trample.cardId!, dagger.cardId!]
        let turn = PlayerTurnController(characterID: second.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: dagger)
        XCTAssertEqual(turn.topActions.first?.value?.intValue, 4, "Attack 3 +1, from the first Brute's gold")

        // A retired character's class keeps them the same way, through a save.
        let tinkerer = try XCTUnwrap(gm.game.characters.first { $0.name == "tinkerer" })
        tinkerer.enhancements = [Enhancement(cardId: 40, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .plus1)]
        tinkerer.personalQuest = "512"
        tinkerer.personalQuestProgress = [200]
        XCTAssertTrue(gm.characterManager.retireCharacter(tinkerer))
        let restored = GameState()
        restored.restore(from: gm.game.toSnapshot(), editionStore: gm.editionStore)
        XCTAssertEqual(restored.classEnhancements(for: "gh-tinkerer").map(\.cardId), [40])
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        XCTAssertEqual(gm.game.characters.first { $0.name == "tinkerer" }?.enhancements.map(\.cardId), [40])
    }

    // MARK: - Buying

    func testTheEnhancerOpensWithThePowerOfEnhancement() throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.loot = 200
        let trample = try card("Trample", of: "brute")
        let attack = try slot(trample, half: "top", action: 0)
        XCTAssertEqual(enhancer.purchaseProblem(.plus1, in: attack, card: trample, for: brute), .locked)
        XCTAssertFalse(enhancer.buy(.plus1, in: attack, card: trample, for: brute))

        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        XCTAssertTrue(enhancer.buy(.plus1, in: attack, card: trample, for: brute))
        XCTAssertEqual(brute.loot, 150)
        XCTAssertEqual(brute.enhancements.map(\.action), [.plus1])
        XCTAssertEqual(enhancer.purchaseProblem(.poison, in: attack, card: trample, for: brute), .slotTaken,
                       "one enhancement to a slot")

        let move = try slot(trample, half: "bottom", action: 0)
        XCTAssertEqual(enhancer.purchaseProblem(.hex, in: move, card: trample, for: brute), .notPlayable)
        brute.loot = 30
        XCTAssertEqual(enhancer.purchaseProblem(.fire, in: move, card: trample, for: brute), .tooExpensive)
        XCTAssertFalse(enhancer.buy(.fire, in: move, card: trample, for: brute))
        XCTAssertEqual(brute.loot, 30)
    }

    func testEnhancementsAreSaved() throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.enhancements = [Enhancement(cardId: 1, actionHalf: "top", actionIndex: 1, slotIndex: 0, action: .plus1)]
        let restored = brute.toSnapshot().toRuntime(editionStore: gm.editionStore)
        XCTAssertEqual(restored.enhancements.map(\.action), [.plus1])
        XCTAssertEqual(restored.enhancements.first?.actionIndex, 1)
    }

    // MARK: - Playing an enhanced card

    func testEnhancementsChangeTheActionsAsPrinted() throws {
        let trample = try card("Trample", of: "brute")
        let enhancements = [
            Enhancement(cardId: 1, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .poison),
            Enhancement(cardId: 1, actionHalf: "top", actionIndex: 100, slotIndex: 0, action: .plus1),   // Pierce 2
            Enhancement(cardId: 1, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .fire),
            Enhancement(cardId: 2, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .plus1),    // another card
        ]
        let top = CardEnhancing.apply(enhancements, to: trample.actions ?? [], cardId: 1, half: "top")
        XCTAssertEqual(top[0].value?.intValue, 3, "the attack itself isn't +1")
        let subs = top[0].subActions ?? []
        XCTAssertEqual(subs.first { $0.type == .pierce }?.value?.intValue, 3)
        XCTAssertTrue(subs.contains { $0.type == .condition && $0.value?.stringValue == "poison" })

        let bottom = CardEnhancing.apply(enhancements, to: trample.bottomActions ?? [], cardId: 1, half: "bottom")
        XCTAssertTrue(bottom[0].subActions?.contains { $0.type == .element && $0.value?.stringValue == "fire" } == true)
        XCTAssertEqual(bottom[1], trample.bottomActions?[1], "the other attack is untouched")
    }

    func testAnEnhancedCardPlaysEnhancedOnTheBoard() async throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        let trample = try card("Trample", of: "brute")
        let other = try card("Spare Dagger", of: "brute")
        brute.handCards = [trample.cardId!, other.cardId!]
        brute.enhancements = [
            Enhancement(cardId: trample.cardId!, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .plus1),
            Enhancement(cardId: trample.cardId!, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .plus1),
            Enhancement(cardId: trample.cardId!, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .air),
        ]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: other)
        XCTAssertEqual(turn.topActions.first?.value?.intValue, 4, "Attack 3 +1")
        turn.swapCards()
        XCTAssertEqual(turn.bottomActions.first?.value?.intValue, 5, "Move 4 +1, after taking the bottom of Trample")

        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else {
            return XCTFail("the move waits for a hex, got \(coord.interactionMode)")
        }
        XCTAssertEqual(range, 5)
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .air }?.state, .new, "the air enhancement infuses")
    }

    func testAPoisonEnhancementPoisonsTheTarget() async throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        guard case .monster(_, let standee) = piece else { return XCTFail() }
        let bandit = try XCTUnwrap(coord.monsterEntity(name: "bandit-guard", standee: standee))
        bandit.health = 99
        bandit.maxHealth = 99
        let trample = try card("Trample", of: "brute")
        let other = try card("Spare Dagger", of: "brute")
        brute.handCards = [trample.cardId!, other.cardId!]
        brute.enhancements = [Enhancement(cardId: trample.cardId!, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .poison)]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: other)
        turn.executeCurrentAction()
        XCTAssertEqual(turn.pendingConditions, [.poison])
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, targets.contains(piece) else {
            return XCTFail("the attack waits for a target")
        }
        coord.handlePieceTap(piece)
        let deadline = Date().addingTimeInterval(3)
        while turn.currentActionIndex == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .poison })
    }

    /// Regression: a heal's own conditions (Amputate's stun, a bless enhancement) were dropped.
    func testAHealsConditionsReachWhoeverItHeals() throws {
        let weaver = addCharacter("spellweaver", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(4, 3))
        brute.health = 3
        let nova = try card("Freezing Nova", of: "spellweaver")   // bottom: Heal 4, Range 4 ◇+◇+
        let other = try card("Fire Orbs", of: "spellweaver")
        weaver.handCards = [nova.cardId!, other.cardId!]
        weaver.enhancements = [Enhancement(cardId: nova.cardId!, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .bless)]
        let turn = PlayerTurnController(characterID: weaver.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: nova)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .selectingHealTarget = coord.interactionMode else { return XCTFail("the heal waits for a target") }
        coord.handlePieceTap(.character(brute.id))
        XCTAssertEqual(brute.health, 7)
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .bless), 1,
                      "the healed Brute is blessed")
    }

    // MARK: - In town

    func testATilesSaysHowTheCardIsEnhanced() throws {
        let trample = try card("Trample", of: "brute")
        let enhancements = [
            Enhancement(cardId: 1, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .plus1),
            Enhancement(cardId: 1, actionHalf: "top", actionIndex: 100, slotIndex: 0, action: .plus1),
            Enhancement(cardId: 1, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .poison),
        ]
        let summary = CardEnhancing.summary(of: trample, enhancements: enhancements)
        XCTAssertEqual(summary, ["Poison", "+1 Pierce", "+1 Move"])
        for line in summary { XCTAssertEqual(PlayerTextTests.lint(line), []) }
        let slot = try slot(trample, half: "top", action: 100)
        XCTAssertEqual(EnhancementSheet.line(slot), "Attack 3 · Pierce 2")
    }

    /// `ENHANCE_RENDER_OUT=/tmp/e.png swift test --filter testRenderEnhancer` renders the Enhancer.
    func testRenderEnhancer() throws {
        guard let out = ProcessInfo.processInfo.environment["ENHANCE_RENDER_OUT"] else {
            throw XCTSkip("set ENHANCE_RENDER_OUT to render the Enhancer")
        }
        GlavenFont.registerFonts()
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.loot = 140
        gm.game.globalAchievements.insert(EnhancementsManager.enhancerAchievement)
        brute.enhancements = [Enhancement(cardId: 1, actionHalf: "top", actionIndex: 0, slotIndex: 0, action: .poison)]
        brute.level = 3
        let start = ProcessInfo.processInfo.environment["ENHANCE_RENDER_CARD"].flatMap { name in
            try? card(name, of: "brute").cardId
        }
        if let start { brute.chosenCards.append(start) }
        let view = EnhancementSheet(character: brute, scrolls: false, startCard: start).environment(gm)
            .frame(width: 1376, height: 1032)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }

    /// An any-element enhancement lets the player pick the element when the action is performed.
    func testAnAnyElementEnhancementAsksWhichElement() throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        let trample = try card("Trample", of: "brute"), other = try card("Spare Dagger", of: "brute")
        brute.handCards = [trample.cardId!, other.cardId!]
        brute.enhancements = [Enhancement(cardId: trample.cardId!, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .wild)]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: trample)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()   // Move 4: the any-element infusion
        XCTAssertEqual(coord.pendingElementChoice?.count, 1)
        coord.resolveElementChoice([.light])
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .light }?.state, .new)
    }

    /// A hex enhancement turns the area's marked hex into a target; it costs 200 gold divided by
    /// the hexes already targeted.
    func testAHexEnhancementWidensTheArea() throws {
        let sweeping = try card("Sweeping Blow", of: "brute")
        let slot = try XCTUnwrap(CardEnhancing.slots(of: sweeping).first { $0.type == .hex })
        XCTAssertEqual(CardEnhancing.options(for: slot, edition: "gh"), [.hex])
        XCTAssertEqual(CardEnhancing.cost(.hex, in: slot, card: sweeping, enhancements: [], edition: "gh"), 66, "200 / 3 hexes")
        let enhanced = CardEnhancing.apply([Enhancement(cardId: slot.cardId, actionHalf: slot.half, actionIndex: slot.actionIndex,
                                                        slotIndex: slot.slotIndex, action: .hex)],
                                           to: slot.half == "top" ? sweeping.actions ?? [] : sweeping.bottomActions ?? [],
                                           cardId: slot.cardId, half: slot.half)
        let pattern = try XCTUnwrap(enhanced.flatMap { $0.subActions ?? [] }.first { $0.type == .area }?.value?.stringValue)
        XCTAssertEqual(pattern.components(separatedBy: "target").count - 1, 4)
        XCTAssertFalse(pattern.contains("enhance"))
    }

    /// Brute Force marks two hexes, one per hex slot: each slot fills its own marked hex, and
    /// the second is priced by the hexes the area targets with the first one added.
    func testEachHexSlotFillsItsOwnMarkedHex() throws {
        let bruteForce = try card("Brute Force", of: "brute")
        let slots = CardEnhancing.slots(of: bruteForce).filter { $0.type == .hex }
        XCTAssertEqual(slots.count, 2)
        let area = try XCTUnwrap(slots[0].action.type == .area ? slots[0].action : nil)
        XCTAssertEqual(CardEnhancing.markedHexes(in: area).map { "\($0.x),\($0.y)" }, ["0,0", "0,2"])
        let second = Enhancement(cardId: slots[1].cardId, actionHalf: slots[1].half, actionIndex: slots[1].actionIndex,
                                 slotIndex: 1, action: .hex)
        func pattern(_ enhancements: [Enhancement]) throws -> String {
            let actions = CardEnhancing.apply(enhancements, to: bruteForce.actions ?? [], cardId: bruteForce.cardId, half: "top")
            return try XCTUnwrap(actions.flatMap { $0.subActions ?? [] }.first { $0.type == .area }?.value?.stringValue)
        }
        let onlySecond = try pattern([second])
        XCTAssertTrue(onlySecond.contains("(0,2,target)"), "the second slot's hex")
        XCTAssertTrue(onlySecond.contains("(0,0,enhance)"), "the first marked hex is still open")

        XCTAssertEqual(CardEnhancing.cost(.hex, in: slots[0], card: bruteForce, enhancements: [], edition: "gh"),
                       66 + 50, "200 / 3 hexes, plus 50 for a level 3 card")
        XCTAssertEqual(CardEnhancing.cost(.hex, in: slots[0], card: bruteForce, enhancements: [second], edition: "gh"),
                       50 + 50 + 75, "200 / 4 hexes, plus 75 for the enhancement already on the card")
        let both = try pattern([second, Enhancement(cardId: slots[0].cardId, actionHalf: "top", actionIndex: slots[0].actionIndex,
                                                    slotIndex: 0, action: .hex)])
        XCTAssertFalse(both.contains("enhance"))
    }
}
