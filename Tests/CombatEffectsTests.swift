import XCTest
import SwiftData
@testable import GlavenGameLib

/// Combat rules found in the October 2026 audit: what attack modifier cards give the attacker,
/// damage from every source being negatable, and bonuses that last the round.
@MainActor
final class CombatEffectsTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

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

    @discardableResult
    private func addCharacter(_ name: String = "brute", at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    @discardableResult
    private func addMonster(_ name: String, type: MonsterType = .normal, at hex: HexCoord) -> GameMonsterEntity {
        let piece = coord.spawnMonster(name: name, type: type, at: hex, origin: .placed)!
        guard case .monster(_, let standee) = piece else { fatalError() }
        return coord.monsterEntity(name: name, standee: standee)!
    }

    private func sequence(_ cards: [AttackModifier]) -> () -> AttackModifier? {
        var queue = cards
        return { queue.isEmpty ? nil : queue.removeFirst() }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - Modifier cards' effects for the attacker (p.19)

    /// The Scoundrel's "+0 rolling, Invisible" makes the Scoundrel invisible, not the target.
    func testAnInvisibleModifierGoesToTheAttacker() async {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 20
        let invisible = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .condition, value: .string("invisible"))],
                                       rolling: true)
        let banditPiece = PieceID.monster(name: "bandit-guard", standee: bandit.number)
        await coord.performAttack(attacker: .character(scoundrel.id), target: banditPiece, attack: AttackParameters(value: 2),
                                  drawCard: sequence([invisible, AttackModifier(type: .plus0)]))
        XCTAssertTrue(coord.isConditionActive(.invisible, on: .character(scoundrel.id)))
        XCTAssertFalse(coord.isConditionActive(.invisible, on: banditPiece))
    }

    /// "+0 rolling, Heal 1 self", "+1 Shield 1 self", "+0 rolling Fire": the attacker heals, is
    /// shielded for the round, and infuses — even when the attack kills.
    func testHealShieldAndElementModifiersGoToTheAttacker() async {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.health = 5
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 1
        let selfTarget = [AttackModifierEffect(type: .specialTarget, value: .string("self"))]
        let heal = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .heal, value: .int(2), effects: selfTarget)],
                                  rolling: true)
        let fire = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .element, value: .string("fire"))], rolling: true)
        let shield = AttackModifier(type: .plus1, value: 1,
                                    effects: [AttackModifierEffect(type: .shield, value: .int(1), effects: selfTarget)])
        await coord.performAttack(attacker: .character(brute.id), target: .monster(name: "bandit-guard", standee: bandit.number),
                                  attack: AttackParameters(value: 2), drawCard: sequence([heal, fire, shield]))
        XCTAssertTrue(bandit.dead || !coord.isOnBoard(.monster(name: "bandit-guard", standee: bandit.number)), "the attack kills")
        XCTAssertEqual(brute.health, 7)
        XCTAssertEqual(brute.shield?.value?.intValue, 1)
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .fire }?.state, .new)
    }

    /// "Refresh an item" refreshes the attacker's spent item.
    func testARefreshItemModifierRefreshesASpentItem() async {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.items = ["gh-1"]
        brute.spentItems = ["gh-1"]
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 20
        let refresh = AttackModifier(type: .plus1, value: 1, effects: [AttackModifierEffect(type: .refreshItem)])
        await coord.performAttack(attacker: .character(brute.id), target: .monster(name: "bandit-guard", standee: bandit.number),
                                  attack: AttackParameters(value: 2), drawCard: sequence([refresh]))
        XCTAssertTrue(brute.spentItems.isEmpty)
    }

    // MARK: - Damage from every source can be negated (p.22)

    /// Wound's damage as the turn starts is damage like any other: the character may lose a hand
    /// card to negate it.
    func testWoundDamageCanBeNegatedByLosingACard() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)
        let brute = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "brute" })
        XCTAssertFalse(brute.longRest)
        brute.entityConditions.append(EntityCondition(name: .wound))
        var lostCard: Int?
        var healthAtPrompt = 0
        await sim.play(rounds: 2) {
            guard lostCard == nil, let pending = sim.coord.pendingDamage, pending.sourceDescription == "Wound",
                  let card = sim.coord.losableHandCards(of: brute).first else { return }
            healthAtPrompt = brute.health
            lostCard = card
            sim.coord.resolvePendingDamage(choice: .loseHandCard(cardId: card))
        }
        let card = try XCTUnwrap(lostCard, "the wound's damage offered the choice")
        XCTAssertTrue(brute.lostCards.contains(card))
        XCTAssertTrue(sim.coord.turnLog.contains { $0.message.contains("loses a card from hand to prevent 1 damage") })
        XCTAssertGreaterThan(healthAtPrompt, 0)
        XCTAssertEqual(sim.violations, [])
    }

    /// Damage printed outside an attack (a Flame Demon's "all adjacent enemies suffer 2 damage")
    /// can be negated too.
    func testPrintedDamageCanBeNegated() async throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.handCards = [1, 2, 3]
        let demon = addMonster("flame-demon", at: HexCoord(4, 3))
        coord.autoResolvePrompts = false
        let health = brute.health
        let damage = Task { @MainActor in
            await self.coord.printedDamage("all adjacent enemies suffer 2 damage", amount: 2,
                                           by: .monster(name: "flame-demon", standee: demon.number), around: HexCoord(4, 3))
        }
        let asked = await waitUntil { self.coord.pendingDamage != nil }
        XCTAssertTrue(asked, "the Brute is asked whether to lose a card")
        XCTAssertEqual(coord.pendingDamage?.damage, 2)
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: 1))
        _ = await damage.value
        XCTAssertEqual(brute.health, health)
        XCTAssertEqual(brute.lostCards, [1])
    }

    // MARK: - Round bonuses

    /// A Shield and Retaliate a monster gained this round (a consumed element) last the round:
    /// another of its type entering play doesn't wipe them, and the newcomer gets its card's.
    func testAMonsterKeepsItsRoundBonusesWhenAnotherOfItsTypeArrives() throws {
        let first = addMonster("bandit-guard", at: HexCoord(5, 5))
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "bandit-guard" })
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 524 })]   // Shield 1, Retaliate 2
        monster.ability = 0
        monster.abilityDrawn = true
        gm.monsterManager.applyStatEffects(for: monster)
        first.retaliate.append(ActionModel(type: .retaliate, value: .int(3)))
        first.shield = ActionModel(type: .shield, value: .int((first.shield?.value?.intValue ?? 0) + 2))
        let (retaliates, shield) = (first.retaliate.count, first.shield?.value?.intValue)

        let second = addMonster("bandit-guard", at: HexCoord(8, 8))
        XCTAssertEqual(first.retaliate.count, retaliates, "the round's Retaliate stays")
        XCTAssertEqual(first.shield?.value?.intValue, shield, "the round's Shield stays")
        XCTAssertEqual(second.shield?.value?.intValue, 1, "the newcomer has its card's Shield 1")
    }

    // MARK: - Bless and Curse cards (p.23)

    /// There are 10 Bless cards in the box for every deck, 10 Curses for the players' decks and
    /// 10 for the monsters': once they're all shuffled in, no more can be given.
    func testBlessAndCurseCardsAreSharedBetweenDecks() {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        let tinkerer = addCharacter("tinkerer", at: HexCoord(5, 5))
        let bandit = addMonster("bandit-guard", at: HexCoord(8, 8))
        let banditPiece = PieceID.monster(name: "bandit-guard", standee: bandit.number)
        for _ in 0..<7 { coord.applyCondition(.bless, to: .character(brute.id)) }
        for _ in 0..<5 { coord.applyCondition(.bless, to: .character(tinkerer.id)) }
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .bless), 7)
        XCTAssertEqual(tinkerer.attackModifierDeck.undrawnCount(of: .bless), 3, "only 10 Bless cards in all")
        coord.applyCondition(.bless, to: banditPiece)
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.undrawnCount(of: .bless), 0)

        for _ in 0..<12 { coord.applyCondition(.curse, to: .character(tinkerer.id)) }
        for _ in 0..<12 { coord.applyCondition(.curse, to: banditPiece) }
        XCTAssertEqual(tinkerer.attackModifierDeck.undrawnCount(of: .curse), 10)
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse), 10, "the monsters' Curses are their own")
        coord.applyCondition(.curse, to: .character(brute.id))
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .curse), 0, "the players' 10 are all in use")
    }

    // MARK: - +1 Target (perk cards)

    /// "+0 rolling, +1 Target" (the Brute's perk): after the attack, the Brute may attack another
    /// enemy in range with the same ability, drawing for it; never the same target again.
    func testAPlusOneTargetCardAddsATarget() async throws {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        let first = addMonster("bandit-guard", at: HexCoord(4, 3)), second = addMonster("bandit-guard", at: HexCoord(2, 3))
        for bandit in [first, second] { bandit.health = 20; bandit.maxHealth = 20 }
        let target = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .target, value: .int(1))], rolling: true)
        let zeros = (0..<10).map { _ in AttackModifier.standard(.plus0) }
        brute.attackModifierDeck = AttackModifierDeck(attackModifiers: [target] + zeros, cards: [target] + zeros)

        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let trample = try XCTUnwrap(deck.first { $0.name == "Trample" }), blow = try XCTUnwrap(deck.first { $0.name == "Sweeping Blow" })
        brute.handCards = [trample.cardId!, blow.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: blow)
        turn.executeCurrentAction()   // Trample's Attack 3
        let firstPiece = PieceID.monster(name: "bandit-guard", standee: first.number)
        let secondPiece = PieceID.monster(name: "bandit-guard", standee: second.number)
        coord.handlePieceTap(firstPiece)
        _ = await waitUntil {
            if case .selectingAttackTarget(_, _, let targets) = self.coord.interactionMode { return targets == [secondPiece] }
            return false
        }
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode else {
            return XCTFail("another target is offered, got \(coord.interactionMode)")
        }
        XCTAssertEqual(targets, [secondPiece], "not the enemy already attacked")
        XCTAssertEqual(turn.currentActionIndex, 0, "still the same attack")
        coord.handlePieceTap(secondPiece)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        XCTAssertLessThan(second.health, 20, "the added target is attacked")
        XCTAssertEqual(turn.currentActionIndex, 1, "then the turn moves on")
    }
}
