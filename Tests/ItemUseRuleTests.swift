import XCTest
import SwiftData
@testable import GlavenGameLib

/// When items work and who decides (GH p.22, 26 and the FAQ's "Item Use"): an armour with use
/// circles is used whenever its trigger applies, like a persistent bonus, and the player isn't
/// asked; other items are the player's to use, which a stunned character can't; and damage a
/// character brings on themself — an item's price, a printed "suffer damage" — may be negated by
/// losing cards like any other.
@MainActor
final class ItemUseRuleTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var brute: GameCharacter { gm.game.characters[0] }
    private var me: PieceID { .character(brute.id) }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(me, at: HexCoord(3, 3))
        brute.handCards = []
        brute.discardedCards = []
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.game.scenario = Scenario(data: data)
    }

    private func bandit(at hex: HexCoord = HexCoord(4, 3), type: MonsterType = .normal) throws -> PieceID {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: type, at: hex, origin: .placed))
        let entity = try XCTUnwrap(coord.entity(for: piece))
        entity.health = 50
        entity.maxHealth = 50
        return piece
    }

    private func attack(from piece: PieceID, value: Int = 3) -> Task<Bool, Never> {
        Task { @MainActor in
            await self.coord.performAttack(attacker: piece, target: self.me, attack: AttackParameters(value: value),
                                           drawCard: { AttackModifier(type: .plus0) })
        }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    private func stun() {
        brute.entityConditions = [EntityCondition(name: .stun, state: .normal)]
    }

    private func card(_ name: String, of deck: String = "brute") throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
    }

    /// A turn with the two cards played, as the board sets it up: they are no longer in the hand
    /// to be lost.
    private func turn(for character: GameCharacter, top: AbilityModel, bottom: AbilityModel) -> PlayerTurnController {
        character.handCards += [top.cardId!, bottom.cardId!]
        coord.selectedCardPairs[character.id] = (top: top, bottom: bottom)
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        return turn
    }

    // MARK: - Armour with use circles

    /// Hide Armor ("on the next two sources of damage from attacks targeting you, gain Shield
    /// 1") isn't offered: it is used on each attack that would damage its wearer — in headless
    /// play too, where no one answers an offer — and is spent with its second circle.
    func testAnArmourWithUseCirclesIsUsedWithoutAsking() async throws {
        brute.items = ["gh-3"]
        let health = brute.health
        let piece = try bandit()
        for headless in [true, false] {
            coord.autoResolvePrompts = headless
            let before = brute.health
            _ = await attack(from: piece).value
            XCTAssertNil(coord.pendingItemUse, "no question is asked")
            XCTAssertEqual(brute.health, before - 2, "Attack 3, +0, Shield 1")
        }
        XCTAssertEqual(brute.health, health - 4)
        XCTAssertTrue(brute.spentItems.contains("gh-3"), "both circles marked: spent")
        XCTAssertNil(brute.itemSlotsUsed["gh-3"])
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: brute.name).itemUses, 2)

        _ = await attack(from: piece).value
        XCTAssertEqual(brute.health, health - 7, "spent: no shield for the third attack")
    }

    /// Every armour with circles in the box, and none of the single-use shields.
    func testWhichArmoursWorkByThemselves() throws {
        let charged = ["gh-3", "gh-23", "gh-44", "gh-65", "gh-74", "gh-104"]
        for item in DefenseItem.all {
            brute.items = [item.key]
            XCTAssertEqual(coord.isChargedArmour(item, wornBy: me), charged.contains(item.key),
                           coord.itemData(item.key)?.name ?? item.key)
        }
        // Every item printed with several circles is one of them: none is left to be offered.
        let circled = gm.editionStore.items(for: "gh").filter { $0.slots > 1 }.map(\.itemKey).sorted()
        XCTAssertEqual(circled, charged.sorted())
    }

    /// "The next sources of damage": an attack that does no damage isn't one, and marks no circle.
    func testAnAttackThatDoesNoDamageMarksNoCircle() async throws {
        brute.items = ["gh-23"]   // Chainmail
        let health = brute.health
        _ = await attack(from: try bandit(), value: 0).value
        XCTAssertEqual(brute.health, health)
        XCTAssertNil(brute.itemSlotsUsed["gh-23"])
        XCTAssertFalse(brute.spentItems.contains("gh-23"))
    }

    /// Swordedge Armor: Shield 1 and Retaliate 1 with each circle.
    func testSwordedgeArmorShieldsAndRetaliates() async throws {
        brute.items = ["gh-74"]
        let health = brute.health
        let piece = try bandit()
        _ = await attack(from: piece).value
        XCTAssertEqual(brute.health, health - 2)
        XCTAssertEqual(coord.entity(for: piece)?.health, 49, "Retaliate 1")
        XCTAssertEqual(brute.itemSlotsUsed["gh-74"], 1)
    }

    /// FAQ: cards may be lost to resolve the damage before a defence item comes to it. Asked
    /// about the damage the armour would leave, the player loses a card instead, and the
    /// armour's circle stays unmarked.
    func testLosingACardInsteadLeavesTheArmourUnused() async throws {
        brute.items = ["gh-3"]
        brute.handCards = [try card("Trample").cardId!]
        coord.autoResolvePrompts = false
        let health = brute.health
        let hit = attack(from: try bandit())
        let asked = await waitUntil { coord.pendingDamage != nil }
        XCTAssertTrue(asked)
        XCTAssertEqual(coord.pendingDamage?.damage, 2, "what the armour would leave")
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: brute.handCards[0]))
        _ = await hit.value
        XCTAssertEqual(brute.health, health)
        XCTAssertEqual(brute.lostCards.count, 1)
        XCTAssertNil(brute.itemSlotsUsed["gh-3"], "the armour wasn't used")

        brute.handCards = [try card("Spare Dagger").cardId!]
        let second = attack(from: try XCTUnwrap(coord.boardState.piece(at: HexCoord(4, 3))))
        _ = await waitUntil { coord.pendingDamage != nil }
        coord.resolvePendingDamage(choice: .takeDamage)
        _ = await second.value
        XCTAssertEqual(brute.health, health - 2)
        XCTAssertEqual(brute.itemSlotsUsed["gh-3"], 1, "taking the damage, the armour took its part")
    }

    // MARK: - Stun

    /// A stunned character uses no items: no shield is offered as they are attacked. The armour
    /// with circles is no choice of theirs and still works, as passive items do (FAQ).
    func testAStunnedCharacterIsOfferedNoShieldButKeepsTheirArmour() async throws {
        brute.items = ["gh-8"]   // Heater Shield
        coord.autoResolvePrompts = false
        let piece = try bandit()
        let health = brute.health

        let offered = attack(from: piece)
        let asked = await waitUntil { coord.pendingItemUse != nil }
        XCTAssertTrue(asked, "not stunned, the shield is offered")
        coord.resolvePendingItemUse(false)
        _ = await offered.value
        XCTAssertEqual(brute.health, health - 3)

        stun()
        _ = await attack(from: piece).value
        XCTAssertNil(coord.pendingItemUse)
        XCTAssertEqual(brute.health, health - 6, "stunned: nothing was offered")
        XCTAssertFalse(brute.spentItems.contains("gh-8"))

        brute.items = ["gh-8", "gh-3"]
        _ = await attack(from: piece).value
        XCTAssertEqual(brute.health, health - 8, "the Hide Armor's Shield 1 all the same")
        XCTAssertEqual(brute.itemSlotsUsed["gh-3"], 1)
    }

    /// Leather Armor (before the draw), Boots of Speed (as cards are revealed), the Dampening
    /// Ring (as a monster consumes) and Heart of the Betrayer (as a normal enemy attacks) are
    /// all uses of an item.
    func testAStunnedCharacterIsOfferedNoItemOutsideTheirTurn() async throws {
        brute.items = ["gh-4", "gh-15", "gh-92", "gh-131"]
        coord.autoResolvePrompts = false
        brute.initiative = 45
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .fire }!].state = .strong
        let piece = try bandit()
        try bandit(at: HexCoord(5, 3))   // an ally of the attacker within its range, for the Heart
        XCTAssertEqual(coord.initiativeItemOffers().count, 1, "not stunned, the boots are offered")

        stun()
        XCTAssertTrue(coord.initiativeItemOffers().isEmpty, "Boots of Speed")
        let dampened = await coord.dampenedConsume([.fire], by: piece)
        XCTAssertFalse(dampened, "Dampening Ring")
        XCTAssertNil(coord.pendingItemUse)

        let health = brute.health
        _ = await attack(from: piece).value
        XCTAssertNil(coord.pendingItemUse, "neither Heart of the Betrayer nor Leather Armor")
        XCTAssertEqual(brute.health, health - 3)
        XCTAssertTrue(brute.spentItems.isEmpty && brute.consumedItems.isEmpty)
    }

    /// Vengeful Barrage's attack back is an attack: a stunned Berserker doesn't make it (FAQ:
    /// Stun stops abilities granted outside the figure's turn too). The charge is marked all the
    /// same — the bonus was triggered.
    func testAStunnedCharacterMakesNoAttackBack() async throws {
        gm.characterManager.addCharacter(name: "lightning", edition: "gh")
        let berserker = gm.game.characters[1]
        coord.boardState.placePiece(.character(berserker.id), at: HexCoord(6, 6))
        berserker.health = 20
        berserker.maxHealth = 20
        berserker.activeCards = [345]
        berserker.entityConditions = [EntityCondition(name: .stun, state: .normal)]
        let piece = try bandit(at: HexCoord(7, 6))
        await coord.performAttack(attacker: piece, target: .character(berserker.id), attack: AttackParameters(value: 3),
                                  drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(berserker.health, 17)
        XCTAssertEqual(coord.entity(for: piece)?.health, 50, "no attack back while stunned")
        XCTAssertEqual(berserker.bonusChargesUsed[345], 1)
    }

    // MARK: - Damage of one's own making

    /// The Bloody Axe's price ("suffer 2 damage") may be negated by losing a card; the axe's +1
    /// is had either way.
    func testAnItemsDamageCanBeNegated() async throws {
        brute.items = ["gh-117"]
        try bandit()
        coord.autoResolvePrompts = false
        let turn = turn(for: brute, top: try card("Trample"), bottom: try card("Spare Dagger"))
        let spare = try card("Shield Bash").cardId!
        brute.handCards.append(spare)
        turn.executeCurrentAction()
        let health = brute.health
        XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-117" })))
        XCTAssertEqual(coord.pendingDamage?.damage ?? 0, 0, "asked on the next beat")
        let asked = await waitUntil { coord.pendingDamage != nil }
        XCTAssertTrue(asked, "the player is asked")
        XCTAssertEqual(coord.pendingDamage?.damage, 2)
        XCTAssertEqual(coord.pendingDamage?.sourceDescription, "Bloody Axe")
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: spare))
        let settled = await waitUntil { brute.lostCards == [spare] }
        XCTAssertTrue(settled)
        XCTAssertEqual(brute.health, health, "negated")
        XCTAssertEqual(turn.currentAttackValue(), 4, "Attack 3, +1 from the axe")
    }

    /// With no card to lose there is nothing to ask: the damage is taken at once.
    func testAnItemsDamageIsTakenAtOnceWithNoCardToLose() throws {
        brute.items = ["gh-117"]
        try bandit()
        coord.autoResolvePrompts = false
        let turn = turn(for: brute, top: try card("Trample"), bottom: try card("Spare Dagger"))
        turn.executeCurrentAction()
        let health = brute.health
        XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-117" })))
        XCTAssertEqual(brute.health, health - 2, "the two cards played aren't in the hand to be lost")
        XCTAssertNil(coord.pendingDamage)
    }

    /// Flurry of Axes: "You may suffer up to 4 damage … X is the amount you suffered". The
    /// damage may be negated like any other, and then none was suffered.
    func testTheBerserkersChosenDamageCanBeNegatedAndThenCountsForNothing() async throws {
        gm.characterManager.addCharacter(name: "lightning", edition: "gh")
        let berserker = gm.game.characters[1]
        coord.boardState.placePiece(.character(berserker.id), at: HexCoord(6, 6))
        berserker.handCards = []
        try bandit(at: HexCoord(7, 6))
        coord.autoResolvePrompts = false
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "lightning", edition: "gh").first { $0.name != "Flurry of Axes" })
        let spare = try XCTUnwrap(gm.editionStore.abilities(forDeck: "lightning", edition: "gh")
            .first { $0.name != "Flurry of Axes" && $0.cardId != other.cardId }?.cardId)
        let turn = turn(for: berserker, top: try card("Flurry of Axes", of: "lightning"), bottom: other)
        berserker.handCards.append(spare)
        let health = berserker.health
        turn.executeCurrentAction()
        XCTAssertEqual(coord.pendingSufferChoice?.most, 4)
        coord.resolveSufferChoice(3)
        let asked = await waitUntil { coord.pendingDamage != nil }
        XCTAssertTrue(asked, "3 damage: take it or lose a card")
        XCTAssertEqual(turn.currentActionIndex, 0, "the turn waits for the answer")
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: spare))
        let moved = await waitUntil { turn.currentActionIndex == 1 }
        XCTAssertTrue(moved)
        XCTAssertEqual(berserker.health, health)
        XCTAssertEqual(turn.damageSuffered, 0, "nothing was suffered")
    }

    /// Blood Transfusion's printed "suffer 2 damage" (Sawbones): asked, and the turn goes on
    /// once the player has answered.
    func testAPrintedSufferDamageCanBeNegated() async throws {
        gm.characterManager.addCharacter(name: "saw", edition: "gh")
        let sawbones = gm.game.characters[1]
        coord.boardState.placePiece(.character(sawbones.id), at: HexCoord(6, 6))
        sawbones.handCards = []
        brute.health = 3   // someone to heal
        coord.boardState.removePiece(me)
        coord.boardState.placePiece(me, at: HexCoord(7, 6))
        coord.autoResolvePrompts = false
        let deck = gm.editionStore.abilities(forDeck: "saw", edition: "gh")
        let transfusion = try card("Blood Transfusion", of: "saw")
        let other = try XCTUnwrap(deck.first { $0.cardId != transfusion.cardId })
        let spare = try XCTUnwrap(deck.first { $0.cardId != transfusion.cardId && $0.cardId != other.cardId }?.cardId)
        let turn = turn(for: sawbones, top: transfusion, bottom: other)
        sawbones.handCards.append(spare)
        let health = sawbones.health
        let suffer = try XCTUnwrap(turn.currentSteps.firstIndex { $0.type == .suffer || $0.type == .sufferDamage })
        var guardCount = 0
        while turn.currentActionIndex < suffer, guardCount < 20 {
            guardCount += 1
            turn.executeCurrentAction()
            if case .selectingHealTarget(_, _, let targets) = coord.interactionMode, let target = targets.sorted().first {
                coord.handlePieceTap(target)
                _ = await waitUntil { turn.currentActionIndex > 0 }
            }
        }
        XCTAssertEqual(turn.currentActionIndex, suffer, "at the step that hurts")
        if coord.pendingDamage == nil { turn.executeCurrentAction() }
        let asked = await waitUntil { coord.pendingDamage != nil }
        XCTAssertTrue(asked, "the player is asked")
        XCTAssertEqual(coord.pendingDamage?.damage, 2)
        XCTAssertEqual(coord.pendingDamage?.sourceDescription, "Blood Transfusion")
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: spare))
        let moved = await waitUntil { turn.currentActionIndex > suffer }
        XCTAssertTrue(moved, "and the turn goes on")
        XCTAssertEqual(sawbones.health, health)
        XCTAssertEqual(sawbones.lostCards, [spare])
    }

    // MARK: - A bonus that would take the damage

    /// Frost Armor ("on the next two sources of damage to you, suffer no damage instead"): the
    /// player may lose a card first and keep the charge (FAQ); left alone, the charge takes it.
    func testCardsMayBeLostBeforeANegatingChargeIsSpent() async throws {
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let spellweaver = gm.game.characters[1]
        let piece = PieceID.character(spellweaver.id)
        coord.boardState.placePiece(piece, at: HexCoord(6, 6))
        let frostArmor = try card("Frost Armor", of: "spellweaver").cardId!
        spellweaver.handCards = gm.editionStore.abilities(forDeck: "spellweaver", edition: "gh")
            .filter { $0.level?.intValue == 1 }.compactMap(\.cardId).filter { $0 != frostArmor }
        spellweaver.activeCards = [frostArmor]
        coord.autoResolvePrompts = false
        let health = spellweaver.health

        let first = Task { @MainActor in await self.coord.sufferDamageWithMitigation(3, to: piece, source: "a trap") }
        let asked = await waitUntil { coord.pendingDamage != nil }
        XCTAssertTrue(asked, "the choice is offered though the armour would take it")
        let pending = try XCTUnwrap(coord.pendingDamage)
        XCTAssertEqual(pending.absorbedBy, "Frost Armor")
        XCTAssertEqual(DamageChoiceSheet.takeTitle(pending), "Let Frost Armor Take It")
        XCTAssertEqual(coord.damageOutcome(pending)?.healthAfter, health, "taking it costs no hit points")
        coord.resolvePendingDamage(choice: .takeDamage)
        _ = await first.value
        XCTAssertEqual(spellweaver.health, health)
        XCTAssertEqual(spellweaver.bonusChargesUsed[frostArmor], 1, "the default: a charge takes it")

        let lost = spellweaver.handCards[0]
        let second = Task { @MainActor in await self.coord.sufferDamageWithMitigation(3, to: piece, source: "a trap") }
        _ = await waitUntil { coord.pendingDamage != nil }
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: lost))
        _ = await second.value
        XCTAssertEqual(spellweaver.health, health)
        XCTAssertEqual(spellweaver.lostCards, [lost])
        XCTAssertEqual(spellweaver.bonusChargesUsed[frostArmor], 1, "a card was lost instead: the charge is kept")
        XCTAssertTrue(spellweaver.activeCards.contains(frostArmor))
    }
}
