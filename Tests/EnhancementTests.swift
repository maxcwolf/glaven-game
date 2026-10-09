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

    func testASlotOffersWhatTheBoardPlays() throws {
        let trample = try card("Trample", of: "brute")
        let attack = CardEnhancing.options(for: try slot(trample, half: "top", action: 0), edition: "gh")
        XCTAssertEqual(attack, [.plus1, .poison, .wound, .muddle, .immobilize, .curse, .disarm])
        let move = CardEnhancing.options(for: try slot(trample, half: "bottom", action: 0), edition: "gh")
        XCTAssertEqual(move, [.plus1, .fire, .ice, .air, .earth, .light, .dark, .wild])

        let novas = try card("Freezing Nova", of: "spellweaver")
        let heal = CardEnhancing.options(for: try slot(novas, half: "bottom", action: 0), edition: "gh")
        XCTAssertEqual(heal, [.plus1, .strengthen, .bless, .regenerate])

        let area = try XCTUnwrap(gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
            .flatMap(CardEnhancing.slots).first { $0.type == .hex })
        XCTAssertEqual(CardEnhancing.options(for: area, edition: "gh"), area.action.value?.stringValue.contains("enhance") == true ? [.hex] : [])
    }

    // MARK: - Prices

    func testPricesFollowTheEnhancerChart() throws {
        let trample = try card("Trample", of: "brute")   // level 1
        let attack = try slot(trample, half: "top", action: 0)
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: attack, card: trample, enhancements: [], edition: "gh"), 50)
        XCTAssertEqual(CardEnhancing.cost(.poison, in: attack, card: trample, enhancements: [], edition: "gh"), 75)

        let earlier = [Enhancement(cardId: 1, actionHalf: "bottom", actionIndex: 0, slotIndex: 0, action: .plus1)]
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: attack, card: trample, enhancements: earlier, edition: "gh"), 125,
                       "+75 for each enhancement already on the card")

        let everyoneMovedThrough = try slot(trample, half: "bottom", action: 1)
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: everyoneMovedThrough, card: trample, enhancements: [], edition: "gh"), 100,
                       "double for an ability with several targets")

        let level3 = try XCTUnwrap(gm.editionStore.abilities(forDeck: "brute", edition: "gh").first { $0.level?.intValue == 3 })
        let slot3 = try XCTUnwrap(CardEnhancing.slots(of: level3).first { CardEnhancing.options(for: $0, edition: "gh").contains(.plus1) })
        let base = CardEnhancing.cost(.plus1, in: slot3, card: trample, enhancements: [], edition: "gh")
        XCTAssertEqual(CardEnhancing.cost(.plus1, in: slot3, card: level3, enhancements: [], edition: "gh"), base + 50,
                       "+25 a level above the first")
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
        let view = EnhancementSheet(character: brute, scrolls: false).environment(gm).frame(width: 1376, height: 1032)
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
}
