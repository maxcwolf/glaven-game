import XCTest
import SwiftData
@testable import GlavenGameLib

/// Resting (GH p.17, FAQ "Resting"): the long rest is a turn on initiative 99 — Wound first, then
/// one discard lost, the rest back in hand, an optional Heal 2, spent items refreshed — and the
/// short rest at the end of the round, in the last round too.
@MainActor
final class RestRuleTests: XCTestCase {

    /// A real board (so the game's turn hooks are in place), in round 1's card selection.
    private func board(autoResolve: Bool = true) throws -> (ScenarioSimulator, GameCharacter) {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 1, autoResolvePrompts: autoResolve))
        sim.coord.autoResolvePrompts = autoResolve
        let brute = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "brute" })
        return (sim, brute)
    }

    /// Give `character` the next turn, as the only figure left to act this round.
    private func takeTurn(_ character: GameCharacter, _ sim: ScenarioSimulator, initiative: Double = 98.6) {
        sim.coord.boardPhase = .execution
        sim.gm.game.state = .next
        sim.coord.turnOrder = [TurnOrderEntry(figure: .character(character), initiative: initiative)]
        sim.coord.currentTurnIndex = -1
        sim.coord.advanceToNextFigure()
    }

    private func rest(_ character: GameCharacter, discards: [Int] = [1, 2, 3]) {
        let all = character.handCards
        character.longRest = true
        character.initiative = 99
        character.discardedCards = Array(all.prefix(discards.count))
        character.handCards = Array(all.dropFirst(discards.count))
    }

    private func settle(_ condition: @autoclosure () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(nanoseconds: 2_000_000) }
    }

    // MARK: - Long rest

    func testALongRestLosesOneDiscardTakesBackTheRestHealsTwoAndRefreshesSpentItems() async throws {
        let (sim, brute) = try board()
        rest(brute)
        let discards = brute.discardedCards, hand = brute.handCards.count
        brute.health = 5
        brute.items = ["gh-1", "gh-12", "gh-3"]
        brute.spentItems = ["gh-1"]
        brute.consumedItems = ["gh-12"]
        brute.itemSlotsUsed = ["gh-3": 1]   // Hide Armor with one of its two uses marked: not spent

        takeTurn(brute, sim)
        XCTAssertEqual(sim.coord.pendingLongRest?.characterID, brute.id, "the rest asks which card to lose")
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 1)

        XCTAssertEqual(brute.lostCards, [discards[1]], "the chosen card is lost")
        XCTAssertTrue(brute.discardedCards.isEmpty)
        XCTAssertEqual(brute.handCards.count, hand + 2, "the other two come back")
        XCTAssertEqual(brute.health, 7, "Heal 2, once")
        XCTAssertTrue(brute.spentItems.isEmpty, "spent items are refreshed")
        XCTAssertEqual(brute.consumedItems, ["gh-12"], "consumed ones are not")
        XCTAssertEqual(brute.itemSlotsUsed["gh-3"], 1, "an item with uses left isn't spent: its marks stay (FAQ)")
        XCTAssertNil(sim.coord.activePlayerTurn, "and the turn is over")
    }

    /// FAQ: the heal is the player's to take; only losing a card and taking back the rest is not.
    func testTheRestsHealMayBeDeclined() throws {
        let (sim, brute) = try board()
        rest(brute)
        brute.health = 5
        takeTurn(brute, sim)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0, heal: false)
        XCTAssertEqual(brute.health, 5)
        XCTAssertEqual(brute.lostCards.count, 1)
    }

    /// The heal is a heal: on a poisoned character it removes the Poison and heals nothing.
    func testPoisonTakesTheRestsHeal() throws {
        let (sim, brute) = try board()
        rest(brute)
        brute.health = 5
        brute.entityConditions = [EntityCondition(name: .poison, state: .normal)]
        takeTurn(brute, sim)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0)
        XCTAssertEqual(brute.health, 5)
        XCTAssertFalse(brute.entityConditions.contains { $0.name == .poison && !$0.expired })
    }

    /// FAQ: "Wound damage occurs before the rest's effects" — and it is damage like any other,
    /// so a resting character on 1 hit point may lose a card to it rather than be exhausted.
    func testARestingCharactersWoundCanBeNegatedBeforeTheRestHeals() async throws {
        let (sim, brute) = try board(autoResolve: false)
        rest(brute)
        brute.health = 1
        brute.entityConditions = [EntityCondition(name: .wound, state: .normal)]
        takeTurn(brute, sim)
        await settle(sim.coord.pendingDamage != nil)
        let pending = try XCTUnwrap(sim.coord.pendingDamage, "the wound's damage offers the choice")
        XCTAssertEqual(pending.damage, 1)
        XCTAssertNil(sim.coord.pendingLongRest, "before the rest")
        let card = try XCTUnwrap(sim.coord.losableHandCards(of: brute).first)
        sim.coord.resolvePendingDamage(choice: .loseHandCard(cardId: card))
        await settle(sim.coord.pendingLongRest != nil)
        XCTAssertFalse(brute.exhausted)
        XCTAssertEqual(brute.health, 1)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0)
        XCTAssertEqual(brute.health, 3)
        XCTAssertFalse(brute.entityConditions.contains { $0.name == .wound && !$0.expired }, "the heal removes the Wound")
    }

    /// Not negated, the wound hurts first and the heal follows.
    func testAWoundHurtsARestingCharacterBeforeTheHeal() async throws {
        let (sim, brute) = try board()
        rest(brute)
        brute.health = 4
        brute.entityConditions = [EntityCondition(name: .wound, state: .normal)]
        takeTurn(brute, sim)
        await settle(sim.coord.pendingLongRest != nil)
        XCTAssertEqual(brute.health, 3)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0)
        XCTAssertEqual(brute.health, 5)
    }

    /// FAQ: a long rest "is considered a turn, so you can still use items" — unless stunned.
    func testItemsCanBeUsedOnALongRestTurnUnlessStunned() async throws {
        let (sim, brute) = try board()
        rest(brute)
        brute.health = 3
        brute.items = ["gh-12"]   // Minor Healing Potion: Heal 3
        takeTurn(brute, sim)
        let potion = try XCTUnwrap(sim.coord.usableItems().first { $0.itemKey == "gh-12" }, "the potion is offered")
        XCTAssertTrue(sim.coord.useItem(potion))
        await settle(brute.health == 6)
        XCTAssertEqual(brute.health, 6)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0)
        XCTAssertEqual(brute.health, 8)

        let (stunnedSim, stunned) = try board()
        rest(stunned)
        stunned.items = ["gh-12"]
        stunned.entityConditions = [EntityCondition(name: .stun, state: .normal)]
        takeTurn(stunned, stunnedSim)
        XCTAssertNotNil(stunnedSim.coord.pendingLongRest, "stunned, the rest itself still happens")
        XCTAssertTrue(stunnedSim.coord.usableItems().isEmpty, "but no items")
    }

    // MARK: - Bonuses that act as a turn starts or ends

    /// Lumbering Bash ("At the start of your next five turns, perform Heal 2, Range 2"): a long
    /// rest is a turn (FAQ), so the heal comes on it too, before the rest's card is chosen, and
    /// marks a charge.
    func testAStartOfTurnBonusActsOnARestTurn() async throws {
        let (sim, _) = try board()
        let cragheart = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "cragheart" })
        rest(cragheart)
        cragheart.activeCards = [143]
        cragheart.health = 3
        takeTurn(cragheart, sim)
        guard case .selectingHealTarget(_, let value, let targets) = sim.coord.interactionMode else {
            return XCTFail("the heal waits for its target as the turn starts")
        }
        XCTAssertEqual(value, 2)
        XCTAssertNil(sim.coord.pendingLongRest, "before the rest's card is asked for")
        XCTAssertEqual(cragheart.bonusChargesUsed[143], 1, "the charge is marked")
        XCTAssertTrue(targets.contains(.character(cragheart.id)))
        sim.coord.handlePieceTap(.character(cragheart.id))
        await settle(sim.coord.pendingLongRest != nil)
        XCTAssertEqual(cragheart.health, 5, "Heal 2")
        XCTAssertEqual(sim.coord.pendingLongRest?.characterID, cragheart.id, "then the rest")
        sim.coord.resolveLongRest(characterID: cragheart.id, discardIndex: 0)
        XCTAssertEqual(cragheart.health, 7, "and the rest's own Heal 2")
        XCTAssertNil(sim.coord.activePlayerTurn, "the turn is over")
    }

    /// The heal may be left out (from the instruction's Skip); the rest follows all the same.
    func testAStartOfTurnBonusOnARestTurnMayBeSkipped() async throws {
        let (sim, _) = try board()
        let cragheart = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "cragheart" })
        rest(cragheart)
        cragheart.activeCards = [143]
        cragheart.health = 3
        takeTurn(cragheart, sim)
        guard case .selectingHealTarget = sim.coord.interactionMode else { return XCTFail("the heal waits for its target") }
        sim.coord.activePlayerTurn?.skipCurrentAction()
        await settle(sim.coord.pendingLongRest != nil)
        XCTAssertNotNil(sim.coord.pendingLongRest)
        XCTAssertEqual(cragheart.health, 3)
        guard case .idle = sim.coord.interactionMode else { return XCTFail("nothing left to choose on the board") }
    }

    /// Auto Turret ("At the end of your next five turns, perform Attack 2, Range 5"): on a rest
    /// turn the attack is made once the rest is done, and then the turn ends.
    func testAnEndOfTurnBonusActsOnARestTurn() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "tinkerer"], seed: 1,
                                                                       autoResolvePrompts: true))
        let tinkerer = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "tinkerer" })
        let me = PieceID.character(tinkerer.id)
        // Beside a monster, so the turret has something to shoot at.
        let enemy = try XCTUnwrap(sim.coord.boardState.piecePositions.keys.sorted().first {
            if case .monster = $0 { return true }; return false })
        let enemyHex = try XCTUnwrap(sim.coord.boardState.piecePositions[enemy])
        let beside = try XCTUnwrap(enemyHex.neighbors.sorted().first { sim.coord.isEmptyHex($0) })
        sim.coord.boardState.removePiece(me)
        sim.coord.boardState.placePiece(me, at: beside)
        rest(tinkerer)
        tinkerer.activeCards = [54]
        takeTurn(tinkerer, sim)
        XCTAssertNotNil(sim.coord.pendingLongRest, "nothing comes before the rest")
        XCTAssertNil(tinkerer.bonusChargesUsed[54])
        sim.coord.resolveLongRest(characterID: tinkerer.id, discardIndex: 0)

        guard case .selectingAttackTarget(let attacker, _, let targets) = sim.coord.interactionMode else {
            return XCTFail("the turret's attack waits for its target before the turn ends")
        }
        XCTAssertEqual(attacker, me)
        XCTAssertEqual(tinkerer.bonusChargesUsed[54], 1, "the charge is marked")
        XCTAssertNotNil(sim.coord.activePlayerTurn, "the turn isn't over yet")
        XCTAssertTrue(targets.contains(enemy))
        sim.coord.handlePieceTap(enemy)
        await settle(sim.coord.activePlayerTurn == nil)
        XCTAssertNil(sim.coord.activePlayerTurn, "the attack made, the turn ends")
        XCTAssertTrue(sim.coord.turnLog.contains { $0.message.contains("attacks") && $0.message.contains("Tinkerer") },
                      "the attack was made")
    }

    /// A rest turn ends like any turn: the money token under the character is looted.
    func testARestTurnEndsWithLooting() throws {
        let (sim, brute) = try board()
        rest(brute)
        let hex = try XCTUnwrap(sim.coord.boardState.piecePositions[.character(brute.id)])
        sim.coord.boardState.placeLoot(at: hex)
        let loot = brute.loot
        takeTurn(brute, sim)
        sim.coord.resolveLongRest(characterID: brute.id, discardIndex: 0)
        XCTAssertNil(sim.coord.boardState.lootTokens[hex])
        XCTAssertGreaterThan(brute.loot, loot)
    }

    /// FAQ: between a character whose initiative is 99 and one long resting, "the character
    /// doing the long rest goes later"; both go before a monster type on 99 (GH p.16).
    func testALongRestGoesAfterACharacterOnNinetyNine() throws {
        let (sim, brute) = try board()
        let other = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "scoundrel" })
        for character in sim.gm.game.characters where character !== brute && character !== other { character.absent = true }
        rest(brute)
        other.initiative = 99
        other.longRest = false
        sim.gm.game.state = .next
        sim.coord.buildTurnOrderAndStart()
        let order = sim.coord.turnOrder.compactMap { entry -> String? in
            if case .character(let c) = entry.figure { return c.name }
            return nil
        }
        XCTAssertEqual(order, ["scoundrel", "brute"])
        let resting = try XCTUnwrap(sim.coord.turnOrder.first { if case .character(let c) = $0.figure { return c === brute }; return false })
        XCTAssertLessThan(resting.initiative, 99, "still before a monster type that drew 99")
    }

    // MARK: - Short rest

    private func endRound(_ sim: ScenarioSimulator) {
        sim.coord.boardPhase = .execution
        sim.gm.game.state = .next
        sim.coord.turnOrder = []
        sim.coord.currentTurnIndex = -1
        sim.coord.advanceToNextFigure()
    }

    /// FAQ: a short rest may be taken in the last round of a scenario (it can decide a battle goal).
    func testAShortRestIsOfferedInTheScenariosLastRound() throws {
        let (sim, brute) = try board(autoResolve: false)
        for character in sim.gm.game.characters where character !== brute { character.absent = true }
        let all = brute.handCards
        brute.discardedCards = Array(all.prefix(2))
        brute.handCards = Array(all.dropFirst(2))
        sim.coord.pendingResult = .victory
        endRound(sim)
        let pending = try XCTUnwrap(sim.coord.pendingShortRest, "the rest is offered though the scenario is won")
        XCTAssertEqual(pending.characterID, brute.id)
        XCTAssertNil(sim.coord.scenarioResult, "the round isn't over until the rest is decided")
        sim.coord.commitShortRest()
        sim.coord.resolveShortRest()
        XCTAssertEqual(brute.lostCards.count, 1)
        XCTAssertTrue(brute.discardedCards.isEmpty)
        XCTAssertEqual(sim.coord.scenarioResult, .victory)
    }

    /// The card lost is one of the discards, the rest return; once per rest the player may
    /// suffer 1 damage to lose a different one instead.
    func testAShortRestLosesARandomDiscardAndMayRedrawOnceForOneDamage() async throws {
        let (sim, brute) = try board()
        sim.coord.autoResolvePrompts = true
        for character in sim.gm.game.characters where character !== brute { character.absent = true }
        let all = brute.handCards
        brute.discardedCards = Array(all.prefix(3))
        brute.handCards = Array(all.dropFirst(3))
        let health = brute.health, hand = brute.handCards.count
        endRound(sim)
        var pending = try XCTUnwrap(sim.coord.pendingShortRest)
        let first = pending.randomCardId
        XCTAssertTrue(brute.discardedCards.contains(first))
        sim.coord.rerollShortRest()
        XCTAssertEqual(brute.health, health, "no redraw before the rest is committed to")
        sim.coord.commitShortRest()
        sim.coord.rerollShortRest()
        await settle(sim.coord.pendingShortRest?.randomCardId != first)
        pending = try XCTUnwrap(sim.coord.pendingShortRest)
        XCTAssertEqual(brute.health, health - 1)
        XCTAssertNotEqual(pending.randomCardId, first, "a different card")
        XCTAssertTrue(pending.rerollUsed)
        let second = pending.randomCardId
        sim.coord.rerollShortRest()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(brute.health, health - 1, "only once per rest")
        XCTAssertEqual(sim.coord.pendingShortRest?.randomCardId, second)
        sim.coord.resolveShortRest()
        XCTAssertEqual(brute.lostCards, [second])
        XCTAssertEqual(brute.handCards.count, hand + 2, "the first card is back in hand with the other")
        XCTAssertTrue(brute.handCards.contains(first))
    }

    /// FAQ: the redraw's 1 damage is damage like any other, so it may be negated by losing a card.
    func testTheRedrawsDamageCanBeNegated() async throws {
        let (sim, brute) = try board(autoResolve: false)
        for character in sim.gm.game.characters where character !== brute { character.absent = true }
        let all = brute.handCards
        brute.discardedCards = Array(all.prefix(3))
        brute.handCards = Array(all.dropFirst(3))
        let health = brute.health
        endRound(sim)
        sim.coord.commitShortRest()
        sim.coord.rerollShortRest()
        await settle(sim.coord.pendingDamage != nil)
        XCTAssertEqual(sim.coord.pendingDamage?.damage, 1)
        let card = try XCTUnwrap(sim.coord.losableHandCards(of: brute).first)
        sim.coord.resolvePendingDamage(choice: .loseHandCard(cardId: card))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(brute.health, health)
        XCTAssertTrue(brute.lostCards.contains(card))
        XCTAssertNotNil(sim.coord.pendingShortRest, "the rest goes on")
    }

    // MARK: - Who must rest, and who is exhausted (GH p.17, p.28)

    /// With fewer than two cards in hand a character must long rest; with fewer than two in the
    /// discard pile as well, they can do neither and are exhausted.
    func testTooFewCardsMeansAForcedRestOrExhaustion() throws {
        let (sim, brute) = try board()
        let scoundrel = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "scoundrel" })
        // The others would be asked for their cards first.
        for character in sim.gm.game.characters where character !== brute && character !== scoundrel { character.absent = true }
        let bruteCards = brute.handCards, scoundrelCards = scoundrel.handCards
        brute.handCards = [bruteCards[0]]
        brute.discardedCards = [bruteCards[1], bruteCards[2]]
        brute.lostCards = Array(bruteCards.dropFirst(3))
        scoundrel.handCards = [scoundrelCards[0]]
        scoundrel.discardedCards = [scoundrelCards[1]]
        scoundrel.lostCards = Array(scoundrelCards.dropFirst(2))
        sim.coord.beginCardSelection()
        XCTAssertTrue(brute.longRest, "one card in hand, two discards: a long rest is the only choice")
        XCTAssertFalse(brute.exhausted)
        XCTAssertTrue(scoundrel.exhausted, "one in hand and one discard: exhausted")
        XCTAssertEqual(scoundrel.handCards.count + scoundrel.discardedCards.count, 0, "all its cards are lost")
    }
}
