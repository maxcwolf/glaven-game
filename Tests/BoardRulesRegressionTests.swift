import XCTest
import SwiftData
@testable import GlavenGameLib

/// Regression tests for board-level rule fixes (monster cards, healing, conditions, deaths,
/// rests, terrain, card routing and movement), run against a real GameManager + coordinator.
@MainActor
final class BoardRulesRegressionTests: XCTestCase {

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

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - Monster ability cards

    func testMonsterCardAttackModifierAndConditionsApply() {
        // Guard-style card: "Attack +1, Poison" on a monster with base attack 3.
        let action = ActionModel(type: .attack, value: .int(1), valueType: .plus,
                                 subActions: [ActionModel(type: .condition, value: .string("poison"))])
        let spec = MonsterAbility.attack(action, stat: nil, baseAttack: 3, baseRange: 0)
        XCTAssertEqual(spec.value, 4)
        XCTAssertEqual(spec.conditions, [.poison])
        XCTAssertFalse(spec.isRanged)

        let minus = MonsterAbility.attack(ActionModel(type: .attack, value: .int(2), valueType: .minus),
                                          stat: nil, baseAttack: 1, baseRange: 0)
        XCTAssertEqual(minus.value, 0, "attack values never go below 0, but the attack still happens")
    }

    func testStatCardEffectsApplyToEveryAttack() throws {
        let stat = MonsterStatModel(type: .normal, level: 1, health: .int(5), movement: .int(2), attack: .int(2),
                                    actions: [ActionModel(type: .condition, value: .string("poison")),
                                              ActionModel(type: .pierce, value: .int(2))])
        let spec = MonsterAbility.attack(ActionModel(type: .attack, value: .int(0), valueType: .plus),
                                         stat: stat, baseAttack: 2, baseRange: 0)
        XCTAssertEqual(spec.conditions, [.poison])
        XCTAssertEqual(spec.pierce, 2)
    }

    func testCardWithoutMoveDoesNotMove() {
        addCharacter(at: HexCoord(8, 3))
        let entity = addMonster("bandit-guard", at: HexCoord(2, 3))
        let monster = gm.game.monsters.first { $0.name == "bandit-guard" }!
        let card = AbilityModel(cardId: 1, initiative: 15, actions: [ActionModel(type: .shield, value: .int(1))])
        let result = MonsterAI.computeTurn(pieceID: .monster(name: "bandit-guard", standee: entity.number),
                                           monster: monster, entity: entity, ability: card,
                                           board: coord.boardState, gameState: gm.game)
        XCTAssertTrue(result.movementPath.isEmpty, "no Move on the card → no movement")
        XCTAssertTrue(result.attackTargets.isEmpty, "no Attack on the card → no attack")
    }

    func testMonsterAbilityDeckAdvancesAndReshufflesOnlyAfterShuffleCard() {
        addMonster("bandit-guard", at: HexCoord(5, 5))
        let monster = gm.game.monsters.first { $0.name == "bandit-guard" }!
        var seen: [Int] = []
        for _ in 0..<4 {
            gm.monsterManager.drawAbility(for: monster)
            seen.append(gm.monsterManager.currentAbilityCardIndex(for: monster)!)
            let shuffles = gm.monsterManager.currentAbility(for: monster)?.shuffle == true
            let position = monster.ability
            gm.monsterManager.finishRound(for: monster)
            if !shuffles {
                XCTAssertEqual(monster.ability, position, "the draw position carries over to the next round")
            } else {
                XCTAssertEqual(monster.ability, -1, "a shuffle card reshuffles the deck at end of round")
            }
        }
        XCTAssertGreaterThan(Set(seen).count, 1, "different cards are revealed each round: \(seen)")
    }

    // MARK: - Healing and conditions

    func testHealOnPoisonedFigureOnlyRemovesPoison() {
        let character = addCharacter(at: HexCoord(3, 3))
        character.health = 4
        character.entityConditions = [EntityCondition(name: .poison, state: .normal),
                                      EntityCondition(name: .wound, state: .normal)]
        let healed = coord.heal(.character(character.id), amount: 3)
        XCTAssertEqual(healed, 0)
        XCTAssertEqual(character.health, 4, "poison blocks the healing")
        XCTAssertTrue(character.entityConditions.isEmpty, "heal removes both poison and wound")
    }

    func testCurseFromAttackGoesIntoTheDeck() {
        let character = addCharacter(at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(6, 6))
        let before = character.attackModifierDeck.undrawnCount(of: .curse)
        coord.applyCondition(.curse, to: .character(character.id))
        XCTAssertEqual(character.attackModifierDeck.undrawnCount(of: .curse), before + 1)
        XCTAssertFalse(character.entityConditions.contains { $0.name == .curse }, "curse is a card, not a token")

        let monsterDeckBefore = gm.game.monsterAttackModifierDeck.undrawnCount(of: .bless)
        coord.applyCondition(.bless, to: .monster(name: "bandit-guard", standee: 1))
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.undrawnCount(of: .bless), monsterDeckBefore + 1)
    }

    // MARK: - Deaths

    func testKilledMonsterDropsMoneyButSummonedMonsterDoesNot() {
        addMonster("bandit-guard", at: HexCoord(4, 4))
        coord.sufferDamage(99, to: .monster(name: "bandit-guard", standee: 1))
        XCTAssertEqual(coord.boardState.lootTokens[HexCoord(4, 4)], 1)
        XCTAssertNil(coord.boardState.piecePositions[.monster(name: "bandit-guard", standee: 1)])

        let piece = coord.spawnMonster(name: "living-bones", type: .normal, at: HexCoord(8, 8), origin: .summoned)!
        coord.sufferDamage(99, to: piece)
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(8, 8)], "summoned monsters drop no money token")
    }

    func testExhaustedCharacterLeavesBoardWithItsSummons() {
        let character = addCharacter(at: HexCoord(3, 3))
        let summonData = SummonDataModel(name: "rat", health: .int(3))
        gm.characterManager.addSummon(from: summonData, for: character)
        let summon = character.summons[0]
        coord.boardState.placePiece(.summon(id: summon.id), at: HexCoord(3, 4))

        coord.sufferDamage(99, to: .character(character.id))
        XCTAssertTrue(character.exhausted)
        XCTAssertNil(coord.boardState.piecePositions[.character(character.id)])
        XCTAssertNil(coord.boardState.piecePositions[.summon(id: summon.id)], "summons leave with the summoner")
        XCTAssertTrue(summon.dead)
    }

    // MARK: - Terrain

    func testTrapsTriggerOnEveryHexEnteredAndDeal2PlusL() async {
        gm.game.level = 3
        let character = addCharacter(at: HexCoord(1, 3))
        character.maxHealth = 30
        character.health = 30
        coord.boardState.cells[HexCoord(2, 3)]?.overlay = .trap
        coord.boardState.cells[HexCoord(3, 3)]?.overlay = .hazard
        let alive = await coord.moveAlong(.character(character.id),
                                          path: [HexCoord(1, 3), HexCoord(2, 3), HexCoord(3, 3), HexCoord(4, 3)],
                                          style: .normal)
        XCTAssertTrue(alive)
        // Trap 2 + 3 = 5, hazard floor(5 / 2) = 2
        XCTAssertEqual(character.health, 30 - 5 - 2)
        XCTAssertFalse(coord.boardState.cells[HexCoord(2, 3)]!.isTrap, "a sprung trap is removed")
        XCTAssertTrue(coord.boardState.cells[HexCoord(3, 3)]!.isHazard, "hazardous terrain stays")
        XCTAssertEqual(coord.boardState.piecePositions[.character(character.id)], HexCoord(4, 3))
    }

    func testJumpIgnoresTrapsOnIntermediateHexes() async {
        let character = addCharacter(at: HexCoord(1, 3))
        let hp = character.health
        coord.boardState.cells[HexCoord(2, 3)]?.overlay = .trap
        await coord.moveAlong(.character(character.id), path: [HexCoord(1, 3), HexCoord(2, 3), HexCoord(3, 3)],
                              style: .jump)
        XCTAssertEqual(character.health, hp)
        XCTAssertTrue(coord.boardState.cells[HexCoord(2, 3)]!.isTrap)
    }

    // MARK: - Turns

    func testLongRestHealsTwoOnceAndRefreshesSpentItems() {
        let character = addCharacter(at: HexCoord(3, 3))
        character.health = 5
        character.longRest = true
        character.spentItems = ["gh-1"]
        character.discardedCards = [1, 2, 3]
        character.handCards = Array(4...10)
        gm.roundManager.toggleFigure(.character(character))
        coord.resolveLongRest(characterID: character.id, discardIndex: 0)
        XCTAssertEqual(character.health, 7, "a long rest heals 2, once")
        XCTAssertTrue(character.spentItems.isEmpty)
        XCTAssertEqual(character.lostCards, [1])
        XCTAssertTrue(character.discardedCards.isEmpty)
    }

    func testCardRoutingAfterTurn() throws {
        let character = addCharacter(at: HexCoord(3, 3))
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let shieldBash = try XCTUnwrap(deck.first { $0.name == "Shield Bash" })   // top lost; bottom round bonus
        let wardingStrength = try XCTUnwrap(deck.first { $0.name == "Warding Strength" }) // bottom persistent + lost
        character.handCards = [shieldBash.cardId!, wardingStrength.cardId!]

        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: shieldBash, bottom: wardingStrength)
        turn.skipRemainingActions() // top half (lost icon)
        turn.skipRemainingActions() // bottom half (persistent)
        XCTAssertEqual(turn.phase, .turnComplete)
        XCTAssertEqual(character.lostCards, [shieldBash.cardId!])
        XCTAssertEqual(character.activeCards, [wardingStrength.cardId!])
        XCTAssertEqual(character.lostWhenRemoved, [wardingStrength.cardId!])
        XCTAssertTrue(character.roundBonusCards.isEmpty)
    }

    func testDefaultActionCardIsAlwaysDiscarded() throws {
        let character = addCharacter(at: HexCoord(3, 3))
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let shieldBash = try XCTUnwrap(deck.first { $0.name == "Shield Bash" })   // top has a lost icon
        let trample = try XCTUnwrap(deck.first { $0.name == "Trample" })
        character.handCards = [shieldBash.cardId!, trample.cardId!]

        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: shieldBash, bottom: trample)
        turn.useDefaultAction() // Attack 2 — no enemies, so it ends the half
        XCTAssertEqual(turn.phase, .executeBottomAction)
        turn.skipRemainingActions()
        XCTAssertTrue(character.discardedCards.contains(shieldBash.cardId!), "default actions always discard")
        XCTAssertFalse(character.lostCards.contains(shieldBash.cardId!))
    }

    func testImmobilizedCharacterCannotMoveAndDisarmedCannotAttack() {
        let character = addCharacter(at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(4, 3))
        character.entityConditions = [EntityCondition(name: .immobilize, state: .normal),
                                      EntityCondition(name: .disarm, state: .normal)]
        coord.beginMoveAction(pieceID: .character(character.id), moveRange: 3)
        if case .selectingMove = coord.interactionMode { XCTFail("immobilized characters can't move") }
        coord.beginAttackAction(pieceID: .character(character.id), range: 1)
        if case .selectingAttackTarget = coord.interactionMode { XCTFail("disarmed characters can't attack") }
    }

    func testAttackConditionsDoNotAffectTheAttacker() async throws {
        let character = addCharacter(at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(4, 3))
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let roar = try XCTUnwrap(deck.first { $0.name == "Provoking Roar" }) // Attack 2, Disarm
        let other = try XCTUnwrap(deck.first { $0.name == "Trample" })
        character.handCards = [roar.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: roar, bottom: other)
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.first else {
            return XCTFail("attack waits for a target")
        }
        coord.handlePieceTap(target)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        XCTAssertFalse(character.entityConditions.contains { $0.name == .disarm }, "the Brute is not disarmed")
        if let guardEntity = coord.monsterEntity(name: "bandit-guard", standee: 1), !guardEntity.dead {
            XCTAssertTrue(guardEntity.entityConditions.contains { $0.name == .disarm }, "the target is disarmed")
        }
    }
}

@MainActor
final class ItemAndPerkRulesTests: XCTestCase {

    func testEquippedItemPenaltyAddsMinusOnes() throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        brute.items = ["gh-3"] // Hide Armor: two -1 cards
        let before = brute.attackModifierDeck.cards.filter { $0.type == .minus1 }.count
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.scenarioManager.setScenario(scenario)
        XCTAssertEqual(brute.attackModifierDeck.cards.filter { $0.type == .minus1 }.count, before + 2)
        gm.scenarioManager.finishScenario(success: true)
        XCTAssertEqual(brute.attackModifierDeck.cards.filter { $0.type == .minus1 }.count, before,
                       "item penalty cards leave the deck after the scenario")
    }
}
