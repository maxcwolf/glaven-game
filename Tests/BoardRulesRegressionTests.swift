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

    // MARK: - Found by the scenario simulator

    private func card(_ name: String, of deck: String) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
    }

    /// The two cards played this round are no longer in the hand (p.22): they can't be lost to
    /// negate damage. Losing one used to put the card in two piles at the end of the turn.
    func testDamageNegationCannotLoseACardPlayedThisRound() async throws {
        let character = addCharacter(at: HexCoord(3, 3))
        let played = [try card("Trample", of: "brute"), try card("Eye for an Eye", of: "brute")]
        character.handCards = [played[0].cardId!, played[1].cardId!, 3, 4]
        coord.storeSelectedCards(for: character.id, top: played[0], bottom: played[1])
        XCTAssertEqual(coord.losableHandCards(of: character), [3, 4])

        coord.autoResolvePrompts = false
        let hp = character.health
        let refused = Task { await self.coord.sufferDamageWithMitigation(2, to: .character(character.id), source: "test") }
        _ = await waitUntil { self.coord.pendingDamage != nil }
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: played[0].cardId!))
        _ = await refused.value
        XCTAssertEqual(character.health, hp - 2, "a played card can't pay for the damage")
        XCTAssertTrue(character.lostCards.isEmpty)

        let negated = Task { await self.coord.sufferDamageWithMitigation(2, to: .character(character.id), source: "test") }
        _ = await waitUntil { self.coord.pendingDamage != nil }
        coord.resolvePendingDamage(choice: .loseHandCard(cardId: 4))
        _ = await negated.value
        XCTAssertEqual(character.health, hp - 2, "losing a hand card negates the damage")
        XCTAssertEqual(character.lostCards, [4])
    }

    /// A character exhausted during its own turn (e.g. by retaliate) takes no further actions:
    /// its turn ends instead of waiting for input that can never come.
    func testCharacterExhaustedDuringItsTurnEndsTheTurn() throws {
        let character = addCharacter(at: HexCoord(3, 3))
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: try card("Shield Bash", of: "brute"), bottom: try card("Trample", of: "brute"))
        coord.exhaust(character, reason: "test")
        XCTAssertEqual(turn.phase, .turnComplete)
        turn.useDefaultAction()
        XCTAssertEqual(turn.phase, .turnComplete, "no default action after exhaustion")
        if case .selectingMove = coord.interactionMode { XCTFail("no move for an exhausted character") }
    }

    /// Infusions and XP printed on an attack come with performing it (Crushing Grasp: Attack 3,
    /// Immobilize, earth).
    func testAttackInfusionNeedsATargetAndHappensWithIt() async throws {
        let character = addCharacter("cragheart", at: HexCoord(3, 3))
        let grasp = try card("Crushing Grasp", of: "cragheart")
        let other = try card("Rumbling Advance", of: "cragheart")
        func earth() -> ElementState { gm.game.elementBoard.first { $0.type == .earth }!.state }

        let lonely = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = lonely
        lonely.selectCards(top: grasp, bottom: other)
        lonely.executeCurrentAction()
        XCTAssertEqual(earth(), .inert, "no target: the attack isn't performed, so no infusion")

        addMonster("bandit-guard", at: HexCoord(4, 3))
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: grasp, bottom: other)
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.first else {
            return XCTFail("attack waits for a target")
        }
        XCTAssertNotEqual(earth(), .inert, "performing the attack infuses earth")
        coord.handlePieceTap(target)
        _ = await waitUntil { turn.currentActionIndex > 0 }
    }

    /// XP printed on an attack (Thief's Knack bottom: Attack 3, +1 XP) and on a loot action (Hook
    /// Gun bottom: Loot 2, +1 XP) is gained.
    func testExperiencePrintedInsideAnActionIsGained() async throws {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(4, 3))
        let knack = PlayerTurnController(characterID: scoundrel.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = knack
        knack.selectCards(top: try card("Quick Hands", of: "scoundrel"), bottom: try card("Thief's Knack", of: "scoundrel"))
        knack.setBottomFirst(true)
        knack.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.first else {
            return XCTFail("attack waits for a target")
        }
        coord.handlePieceTap(target)
        _ = await waitUntil { knack.currentActionIndex > 0 }
        XCTAssertEqual(scoundrel.experience, 1)

        let tinkerer = addCharacter("tinkerer", at: HexCoord(6, 6))
        let hook = PlayerTurnController(characterID: tinkerer.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = hook
        hook.selectCards(top: try card("Stun Shot", of: "tinkerer"), bottom: try card("Hook Gun", of: "tinkerer"))
        hook.setBottomFirst(true)
        hook.executeCurrentAction()
        XCTAssertEqual(tinkerer.experience, 1)
    }

    /// An element inside a block of the card (Perverse Edge bottom: "ice, +1 XP") is infused once.
    func testBlockInfusionIsAppliedOnce() throws {
        let mindthief = addCharacter("mindthief", at: HexCoord(3, 3))
        let turn = PlayerTurnController(characterID: mindthief.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: try card("Scurry", of: "mindthief"), bottom: try card("Perverse Edge", of: "mindthief"))
        turn.setBottomFirst(true)
        turn.executeCurrentAction() // Attack 1, Range 2, Stun: no target
        turn.executeCurrentAction() // ice
        turn.executeCurrentAction() // +1 XP
        XCTAssertEqual(coord.turnLog.filter { $0.message.hasSuffix("infuses Ice") }.count, 1)
        XCTAssertEqual(mindthief.experience, 1)
    }

    /// Immobilize takes effect at once: a figure caught in a bear trap stops moving. A push is not
    /// a move ability and continues.
    func testBearTrapImmobilizeEndsTheMoveButNotAPush() async {
        let character = addCharacter(at: HexCoord(1, 3))
        character.maxHealth = 30
        character.health = 30
        coord.boardState.cells[HexCoord(2, 3)]?.overlay = .trap
        coord.boardState.cells[HexCoord(2, 3)]?.overlaySubType = "bear"
        await coord.moveAlong(.character(character.id), path: [HexCoord(1, 3), HexCoord(2, 3), HexCoord(3, 3)],
                              style: .normal)
        XCTAssertEqual(coord.boardState.piecePositions[.character(character.id)], HexCoord(2, 3))
        XCTAssertTrue(coord.isConditionActive(.immobilize, on: .character(character.id)))

        let guardEntity = addMonster("bandit-guard", at: HexCoord(5, 5))
        guardEntity.maxHealth = 30
        guardEntity.health = 30
        coord.boardState.cells[HexCoord(6, 5)]?.overlay = .trap
        coord.boardState.cells[HexCoord(6, 5)]?.overlaySubType = "bear"
        let piece = PieceID.monster(name: "bandit-guard", standee: 1)
        await coord.moveAlong(piece, path: [HexCoord(5, 5), HexCoord(6, 5), HexCoord(7, 5)], style: .forced)
        XCTAssertEqual(coord.boardState.piecePositions[piece], HexCoord(7, 5), "the push continues")
    }

    /// Every attack and every movement runs on the main actor, like the UI that observes them.
    /// Player attacks used to resolve on a background thread.
    func testAttacksAndMovesRunOnTheMainThread() async throws {
        var offMain: [String] = []
        coord.attackObserver = { attacker, _ in if !Thread.isMainThread { offMain.append("attack by \(attacker)") } }
        coord.moveObserver = { piece, _, _ in if !Thread.isMainThread { offMain.append("move of \(piece)") } }
        let character = addCharacter(at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(4, 3))
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: try card("Spare Dagger", of: "brute"), bottom: try card("Trample", of: "brute"))
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.first else {
            return XCTFail("attack waits for a target")
        }
        coord.handlePieceTap(target)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        let monster = gm.game.monsters.first { $0.name == "bandit-guard" }!
        gm.monsterManager.drawAbility(for: monster)
        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual(offMain, [])
    }

    /// Jump over a Bandit Guard with `card`'s bottom half, then perform its next action.
    private func jumpOverABandit(_ name: String, card cardName: String, other otherName: String) async throws
        -> (character: GameCharacter, bandit: GameMonsterEntity) {
        let character = addCharacter(name, at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        let played = try card(cardName, of: name), other = try card(otherName, of: name)
        character.handCards = [played.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: played)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()   // the move, with Jump
        coord.handleHexTap(HexCoord(6, 3))
        _ = await waitUntil { turn.currentActionIndex == 1 }
        turn.executeCurrentAction()
        return (character, bandit)
    }

    /// Regression: Rock Tunnel's "Immobilize, target all enemies moved through" immobilized the
    /// Cragheart (the target is only in the card's text).
    func testRockTunnelImmobilizesTheEnemiesJumpedOver() async throws {
        let (cragheart, bandit) = try await jumpOverABandit("cragheart", card: "Rock Tunnel", other: "Avalanche")
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .immobilize })
        XCTAssertFalse(cragheart.entityConditions.contains { $0.name == .immobilize })
    }

    /// Regression: Corrupting Embrace's poison asked for one adjacent enemy instead.
    func testCorruptingEmbracePoisonsTheEnemiesJumpedOver() async throws {
        let (_, bandit) = try await jumpOverABandit("mindthief", card: "Corrupting Embrace", other: "Feedback Loop")
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .poison })
        if case .selectingConditionTarget = coord.interactionMode { XCTFail("no target to pick") }
    }

    /// Feedback Loop's muddle is printed inside its move, but only for a move that ends where it
    /// started; an ordinary move muddles no one.
    func testFeedbackLoopMuddlesOnlyAfterALoop() async throws {
        let character = addCharacter("mindthief", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        let loop = try card("Feedback Loop", of: "mindthief"), other = try card("Corrupting Embrace", of: "mindthief")
        character.handCards = [loop.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: loop)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        coord.handleHexTap(HexCoord(6, 3))
        _ = await waitUntil { turn.currentActionIndex == 1 }
        XCTAssertFalse(bandit.entityConditions.contains { $0.name == .muddle }, "the move didn't end where it started")
    }

    /// Regression: a target printed beside a condition (Crippling Offensive's "Immobilize and
    /// Push 1, one adjacent enemy") left the condition with none, so it immobilized the Brute.
    func testATargetBesideAConditionIsTheConditionsTarget() throws {
        let offensive = try card("Crippling Offensive", of: "brute")
        let bottom = PlayerTurnController.attachingTargets(offensive.bottomActions ?? [])
        let immobilize = try XCTUnwrap(bottom.flatMap { $0.subActions ?? [] }.first { $0.type == .condition })
        XCTAssertEqual(immobilize.subActions?.first { $0.type == .specialTarget }?.value?.stringValue, "enemyAdjacent")

        let character = addCharacter(at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(4, 3))
        let other = try card("Trample", of: "brute")
        character.handCards = [offensive.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: offensive)
        turn.setBottomFirst(true)
        turn.skipCurrentAction()      // the move
        turn.executeCurrentAction()   // Immobilize and Push 1
        XCTAssertFalse(character.entityConditions.contains { $0.name == .immobilize }, "not the Brute")
    }

    /// Mass Extinction curses and wounds every other figure, allies included.
    func testMassExtinctionHitsEveryoneElse() throws {
        let squid = addCharacter("squidface", at: HexCoord(3, 3))
        let ally = addCharacter("brute", at: HexCoord(6, 6))
        let bandit = addMonster("bandit-guard", at: HexCoord(5, 3))
        let extinction = try card("Mass Extinction", of: "squidface")
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "squidface", edition: "gh").first { $0.cardId != extinction.cardId })
        squid.handCards = [extinction.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: squid.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: extinction, bottom: other)
        turn.executeCurrentAction()   // Curse
        turn.executeCurrentAction()   // and Wound
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .wound })
        XCTAssertTrue(ally.entityConditions.contains { $0.name == .wound })
        XCTAssertFalse(squid.entityConditions.contains { $0.name == .wound })
        XCTAssertEqual(squid.attackModifierDeck.undrawnCount(of: .curse), 0)
    }

    /// Virulent Strain: poison every enemy next to a poisoned enemy (the target is in its text).
    func testVirulentStrainSpreadsPoison() throws {
        let squid = addCharacter("squidface", at: HexCoord(3, 3))
        let sick = addMonster("bandit-guard", at: HexCoord(6, 3))
        let beside = addMonster("bandit-guard", at: HexCoord(7, 3))
        let far = addMonster("bandit-guard", at: HexCoord(9, 6))
        sick.entityConditions = [EntityCondition(name: .poison, state: .normal)]
        let strain = try card("Virulent Strain", of: "squidface")
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "squidface", edition: "gh").first { $0.cardId != strain.cardId })
        squid.handCards = [strain.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: squid.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: strain)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        XCTAssertTrue(beside.entityConditions.contains { $0.name == .poison })
        XCTAssertFalse(far.entityConditions.contains { $0.name == .poison })
        XCTAssertFalse(squid.entityConditions.contains { $0.name == .poison })
    }

    // MARK: - Printed text

    private func turn(for character: GameCharacter, top: AbilityModel, bottom: AbilityModel, bottomFirst: Bool = false)
        -> PlayerTurnController {
        character.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        if bottomFirst { turn.setBottomFirst(true) }
        return turn
    }

    /// Regression: Crater's Move 4 was wrapped in its text, so it never happened; its "all
    /// adjacent allies and enemies suffer 1 damage" didn't either.
    func testCraterHurtsItsNeighboursAndMoves() throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(4, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(2, 3))
        let (bruteHealth, banditHealth) = (brute.health, bandit.health)
        let turn = turn(for: cragheart, top: try card("Avalanche", of: "cragheart"), bottom: try card("Crater", of: "cragheart"),
                        bottomFirst: true)
        turn.executeCurrentAction()   // all adjacent allies and enemies suffer 1 damage
        XCTAssertEqual(brute.health, bruteHealth - 1)
        XCTAssertEqual(bandit.health, banditHealth - 1)
        XCTAssertEqual(cragheart.health, cragheart.maxHealth, "not the Cragheart")
        turn.executeCurrentAction()   // Move 4, Jump
        guard case .selectingMove(_, let range, _, _, let mode) = coord.interactionMode else { return XCTFail("the move happens") }
        XCTAssertEqual(range, 4)
        XCTAssertEqual(mode, .jump)
    }

    /// Regression: Unstable Upheaval's Shield 2 (for every ally) was wrapped in its text.
    func testUnstableUpheavalShieldsEveryAlly() throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(8, 8))
        let health = brute.health
        let turn = turn(for: cragheart, top: try card("Avalanche", of: "cragheart"),
                        bottom: try card("Unstable Upheaval", of: "cragheart"), bottomFirst: true)
        turn.executeCurrentAction()   // all allies suffer 1 damage
        turn.executeCurrentAction()   // Shield 2, affect all allies
        XCTAssertEqual(brute.health, health - 1)
        XCTAssertEqual(cragheart.shield?.value?.intValue, 2)
        XCTAssertEqual(brute.shield?.value?.intValue, 2)
    }

    func testRevivingEtherRecoversTheLostCards() throws {
        let spellweaver = addCharacter("spellweaver", at: HexCoord(3, 3))
        spellweaver.lostCards = [61, 62]
        let turn = turn(for: spellweaver, top: try card("Reviving Ether", of: "spellweaver"), bottom: try card("Frost Armor", of: "spellweaver"))
        turn.executeCurrentAction()
        XCTAssertTrue(spellweaver.lostCards.isEmpty)
        XCTAssertTrue(spellweaver.handCards.contains(61) && spellweaver.handCards.contains(62))
    }

    func testThiefsKnackDisarmsAnAdjacentTrap() throws {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        coord.boardState.placeTrap(at: HexCoord(4, 3), damage: 3)
        let turn = turn(for: scoundrel, top: try card("Thief's Knack", of: "scoundrel"), bottom: try card("Backstab", of: "scoundrel"))
        turn.executeCurrentAction()
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.isTrap, false)
    }

    func testMassiveBoulderHurtsThoseBesideTheTarget() async throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let target = addMonster("bandit-guard", at: HexCoord(6, 3))
        target.health = 50
        target.maxHealth = 50
        let beside = addMonster("bandit-guard", at: HexCoord(7, 3))
        let health = beside.health
        let turn = turn(for: cragheart, top: try card("Massive Boulder", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"))
        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode,
              let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(6, 3) })?.key else { return XCTFail() }
        coord.handlePieceTap(piece)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        XCTAssertEqual(beside.health, health - 1)
    }

    /// Proximity Mine: the Tinkerer places a 6 damage trap beside them; an enemy springing it
    /// gives the Tinkerer 2 experience.
    func testProximityMinePlacesATrapThatPaysExperience() async throws {
        let tinkerer = addCharacter("tinkerer", at: HexCoord(3, 3))
        let turn = turn(for: tinkerer, top: try card("Proximity Mine", of: "tinkerer"), bottom: try card("Hook Gun", of: "tinkerer"))
        turn.executeCurrentAction()
        guard case .placingToken(_, let token, _, let hexes) = coord.interactionMode else { return XCTFail("a hex to choose") }
        XCTAssertEqual(token, .trap(damage: 6, subType: nil, experience: 2))
        XCTAssertTrue(hexes.contains(HexCoord(4, 3)))
        coord.handleHexTap(HexCoord(4, 3))
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.isTrap, true)
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.trapDamage, 6)
        XCTAssertEqual(turn.currentActionIndex, 1)

        let bandit = addMonster("bandit-guard", at: HexCoord(5, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        let xp = tinkerer.experience
        guard let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(5, 3) })?.key else { return XCTFail() }
        await coord.moveAlong(piece, path: [HexCoord(5, 3), HexCoord(4, 3)], style: .normal)
        XCTAssertEqual(bandit.health, 44)
        XCTAssertEqual(tinkerer.experience, xp + 2)
    }

    /// Avalanche: two obstacles, one hex at a time.
    func testAvalanchePlacesTwoObstacles() throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let turn = turn(for: cragheart, top: try card("Crater", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        coord.handleHexTap(HexCoord(4, 3))
        guard case .placingToken(_, .obstacle, 1, let hexes) = coord.interactionMode else { return XCTFail("a second obstacle") }
        XCTAssertFalse(hexes.contains(HexCoord(4, 3)))
        coord.handleHexTap(HexCoord(2, 3))
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.passable, false)
        XCTAssertEqual(coord.boardState.cells[HexCoord(2, 3)]?.passable, false)
        XCTAssertEqual(turn.currentActionIndex, 1)
    }

    /// Regression: Balanced Measure's "X" (hexes moved; damage inflicted) was played as 2.
    func testBalancedMeasureCountsTheTurn() async throws {
        let brute = addCharacter(at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(8, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        let measure = try card("Balanced Measure", of: "brute"), other = try card("Trample", of: "brute")
        let turn = turn(for: brute, top: measure, bottom: other)
        await coord.moveAlong(.character(brute.id), path: (3...7).map { HexCoord($0, 3) }, style: .normal)
        turn.executeCurrentAction()   // Attack X: four hexes moved
        XCTAssertEqual(turn.currentAttackValue(), 4)

        let next = self.turn(for: brute, top: other, bottom: measure, bottomFirst: true)
        guard let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(8, 3) })?.key else { return XCTFail() }
        coord.sufferDamage(3, to: piece, killer: .character(brute.id))
        next.executeCurrentAction()   // Move X: three damage inflicted
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("a move") }
        XCTAssertEqual(range, 3)
    }

    /// The Berserker's X: missing hit points, lost cards, current hit points.
    func testTheBerserkersXValues() throws {
        let berserker = addCharacter("lightning", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        berserker.health = berserker.maxHealth - 6
        berserker.lostCards = [1, 2, 3]
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "lightning", edition: "gh").first { $0.name == "Spiteful Cut" }
                                  ?? gm.editionStore.abilities(forDeck: "lightning", edition: "gh").first)
        let stand = turn(for: berserker, top: try card("Resolute Stand", of: "lightning"), bottom: other)
        stand.executeCurrentAction()
        XCTAssertEqual(stand.currentAttackValue(), 6, "Resolute Stand: missing hit points")
        let rage = turn(for: berserker, top: try card("Growing Rage", of: "lightning"), bottom: other)
        rage.executeCurrentAction()
        XCTAssertEqual(rage.currentAttackValue(), 3, "Growing Rage: cards lost")
    }

    func testReinvigoratingElixirLetsAnAdjacentAllyRecoverEverything() throws {
        let tinkerer = addCharacter("tinkerer", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(4, 3))
        brute.discardedCards = [1, 2, 3]
        let turn = turn(for: tinkerer, top: try card("Hook Gun", of: "tinkerer"), bottom: try card("Reinvigorating Elixir", of: "tinkerer"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        XCTAssertTrue(brute.discardedCards.isEmpty)
        XCTAssertTrue([1, 2, 3].allSatisfy(brute.handCards.contains))
    }

    func testVolatileConcoctionAsksWhichAllyRecovers() throws {
        let tinkerer = addCharacter("tinkerer", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(4, 3))
        let spellweaver = addCharacter("spellweaver", at: HexCoord(2, 3))
        brute.discardedCards = [1, 2, 3]
        spellweaver.discardedCards = [61]
        let turn = turn(for: tinkerer, top: try card("Hook Gun", of: "tinkerer"), bottom: try card("Volatile Concoction", of: "tinkerer"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        let choice = try XCTUnwrap(coord.pendingAllyChoice)
        XCTAssertEqual(Set(choice.characterIDs), [brute.id, spellweaver.id])
        coord.resolveAllyChoice(brute.id)
        XCTAssertEqual(coord.pendingRecovery?.count, 1, "one card, without Ice to consume")
        coord.resolveRecovery([2, 3])
        XCTAssertEqual(brute.discardedCards, [1, 3])
    }

    /// Flurry of Axes: suffer up to 4 damage, then Attack X where X is what was suffered.
    func testFlurryOfAxesAttacksWithTheDamageSuffered() throws {
        let berserker = addCharacter("lightning", at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(5, 3))
        coord.autoResolvePrompts = false
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "lightning", edition: "gh").first { $0.name != "Flurry of Axes" })
        let turn = turn(for: berserker, top: try card("Flurry of Axes", of: "lightning"), bottom: other)
        let health = berserker.health
        turn.executeCurrentAction()
        XCTAssertEqual(coord.pendingSufferChoice?.most, 4)
        coord.resolveSufferChoice(3)
        XCTAssertEqual(berserker.health, health - 3)
        XCTAssertEqual(turn.currentActionIndex, 1)
        turn.executeCurrentAction()
        XCTAssertEqual(turn.currentAttackValue(), 3)
    }

    func testHexLinesRunStraight() {
        XCTAssertEqual(HexCoord(1, 3).line(to: HexCoord(5, 3)), (1...5).map { HexCoord($0, 3) })
        let diagonal = HexCoord(3, 3).line(to: HexCoord(5, 7))
        XCTAssertEqual(diagonal.count, 5)
        for (a, b) in zip(diagonal, diagonal.dropFirst()) { XCTAssertTrue(a.isAdjacent(to: b), "\(a) \(b)") }
    }

    /// Impaling Eruption: "Additionally, target all enemies on the path to the primary target."
    func testImpalingEruptionHitsEveryEnemyOnTheWay() async throws {
        let spellweaver = addCharacter("spellweaver", at: HexCoord(1, 3))
        for col in 2...4 {
            let bandit = addMonster("bandit-guard", at: HexCoord(col, 3))
            bandit.health = 50
            bandit.maxHealth = 50
        }
        let aside = addMonster("bandit-guard", at: HexCoord(3, 5))
        let turn = turn(for: spellweaver, top: try card("Impaling Eruption", of: "spellweaver"), bottom: try card("Frost Armor", of: "spellweaver"))
        turn.executeCurrentAction()
        guard let far = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(4, 3) })?.key else { return XCTFail() }
        coord.handlePieceTap(far)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        let attacked = coord.turnLog.filter { $0.message.contains("attacks Bandit Guard") }
        XCTAssertEqual(attacked.count, 3, attacked.map(\.message).joined(separator: " / "))
        XCTAssertEqual(aside.health, aside.maxHealth)
    }

    func testPrintedBonusTextBecomesActions() {
        let clod = PlayerTurnController.actions(fromText: "Immobilize, XP +1")
        XCTAssertEqual(clod.map(\.type), [.condition, .card])
        XCTAssertEqual(clod.first?.value?.stringValue, "immobilize")
        let crater = PlayerTurnController.actions(fromText: "Push 2, XP +1")
        XCTAssertEqual(crater.first?.type, .push)
        XCTAssertEqual(crater.first?.value?.intValue, 2)
        let upheaval = PlayerTurnController.actions(fromText: "Target all enemies up to two")
        XCTAssertEqual(upheaval.first?.value?.stringValue, "enemiesRange:2")
        XCTAssertEqual(PlayerTurnController.actions(fromText: "+1 Attack").first?.valueType, .plus)
    }

    /// Regression: Earthen Clod's "Immobilize, XP +1" for consuming Earth was printed text, so
    /// consuming the element gave nothing.
    func testEarthenClodsEarthImmobilizes() async throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(5, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .earth }!].state = .strong
        let turn = turn(for: cragheart, top: try card("Earthen Clod", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"))
        let xp = cragheart.experience
        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode,
              let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(5, 3) })?.key else { return XCTFail() }
        coord.handlePieceTap(piece)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .immobilize })
        XCTAssertEqual(cragheart.experience, xp + 1)
    }

    /// Actions another figure performs ("Force one enemy… to perform Attack 2", "One adjacent
    /// ally may perform Attack 6") are not the character's: they mustn't become its steps.
    func testActionsForSomeoneElseAreNotTheCharacters() throws {
        let affliction = try card("Submissive Affliction", of: "mindthief")
        let steps = PlayerTurnController.steps(affliction.bottomActions ?? [], labels: gm.editionStore, edition: "gh")
        XCTAssertFalse(steps.contains { $0.type == .attack }, "the forced Attack is the enemy's")
        let possession = try card("Possession", of: "mindthief")
        XCTAssertFalse(PlayerTurnController.steps(possession.actions ?? [], labels: gm.editionStore, edition: "gh")
            .contains { $0.type == .attack }, "the ally's Attack 6")
        let syringe = try card("Syringe", of: "saw")
        XCTAssertFalse(PlayerTurnController.steps(syringe.actions ?? [], labels: gm.editionStore, edition: "gh")
            .contains { $0.type == .shield }, "the ally's Shield 2")
    }

    /// Sinister Opportunity: after the move, an adjacent enemy moves 1, ending beside the Scoundrel.
    func testSinisterOpportunityMovesAnEnemyBesideTheScoundrel() async throws {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(6, 3))
        let turn = turn(for: scoundrel, top: try card("Backstab", of: "scoundrel"), bottom: try card("Sinister Opportunity", of: "scoundrel"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        coord.handleHexTap(HexCoord(5, 3))
        _ = await waitUntil { if case .choosingPerformer = self.coord.interactionMode { return true }; return false }
        guard case .choosingPerformer(_, _, let candidates) = coord.interactionMode, let bandit = candidates.first else {
            return XCTFail("an adjacent enemy to move")
        }
        coord.handlePieceTap(bandit)
        guard case .selectingMove(_, let range, let hexes, _, _) = coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(range, 1)
        XCTAssertFalse(hexes.isEmpty)
        XCTAssertTrue(hexes.allSatisfy { $0.isAdjacent(to: HexCoord(5, 3)) }, "ending beside the Scoundrel")
    }

    /// Regression: Sinister Opportunity's Move 3 added the forced enemy's Move 1 (Move 4).
    func testSinisterOpportunityMovesThree() throws {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        let turn = turn(for: scoundrel, top: try card("Backstab", of: "scoundrel"), bottom: try card("Sinister Opportunity", of: "scoundrel"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(range, 3)
    }

    /// Possession: "One adjacent ally may perform Attack 6": the Brute makes the attack.
    func testPossessionLetsAnAllyAttack() throws {
        let mindthief = addCharacter("mindthief", at: HexCoord(3, 3))
        let brute = addCharacter("brute", at: HexCoord(4, 3))
        addMonster("bandit-guard", at: HexCoord(5, 3))
        let turn = turn(for: mindthief, top: try card("Possession", of: "mindthief"), bottom: try card("Scurry", of: "mindthief"))
        turn.executeCurrentAction()
        guard case .choosingPerformer(_, _, let candidates) = coord.interactionMode else { return XCTFail("who performs it") }
        XCTAssertEqual(candidates, [.character(brute.id)])
        coord.handlePieceTap(.character(brute.id))
        guard case .selectingAttackTarget(let attacker, _, _) = coord.interactionMode else { return XCTFail("the Brute attacks") }
        XCTAssertEqual(attacker, .character(brute.id))
        XCTAssertEqual(turn.currentAttackValue(), 6)
    }

    /// Parasitic Influence: "Force one enemy within Range 4 to perform Move 1".
    func testParasiticInfluenceMovesAnEnemy() throws {
        let mindthief = addCharacter("mindthief", at: HexCoord(3, 3))
        addMonster("bandit-guard", at: HexCoord(6, 3))
        let turn = turn(for: mindthief, top: try card("Scurry", of: "mindthief"), bottom: try card("Parasitic Influence", of: "mindthief"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        guard case .choosingPerformer(_, _, let candidates) = coord.interactionMode, let bandit = candidates.first else {
            return XCTFail("which enemy")
        }
        coord.handlePieceTap(bandit)
        guard case .selectingMove(let mover, let range, _, _, _) = coord.interactionMode else { return XCTFail("the enemy moves") }
        XCTAssertEqual(mover, bandit)
        XCTAssertEqual(range, 1)
    }

    /// Dirt Tornado: "Muddle all allies and enemies in the targeted area."
    func testDirtTornadoMuddlesEveryoneInTheArea() async throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(1, 3))
        let target = addMonster("bandit-guard", at: HexCoord(3, 3))
        target.health = 50
        target.maxHealth = 50
        let turn = turn(for: cragheart, top: try card("Dirt Tornado", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"))
        turn.executeCurrentAction()
        guard let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(3, 3) })?.key else { return XCTFail() }
        coord.handlePieceTap(piece)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        XCTAssertTrue(target.entityConditions.contains { $0.name == .muddle })
        XCTAssertFalse(cragheart.entityConditions.contains { $0.name == .muddle }, "not the Cragheart")
    }

    func testRockTunnelDestroysAnAdjacentObstacle() throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        coord.boardState.placeObstacle(at: HexCoord(4, 3))
        let turn = turn(for: cragheart, top: try card("Rock Tunnel", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"))
        turn.executeCurrentAction()
        guard case .placingToken(_, .destroyObstacle, _, let hexes) = coord.interactionMode else { return XCTFail("an obstacle to pick") }
        XCTAssertEqual(hexes, [HexCoord(4, 3)])
        coord.handleHexTap(HexCoord(4, 3))
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.passable, true)
        XCTAssertNil(coord.boardState.cells[HexCoord(4, 3)]?.overlay)
    }

    /// Heaving Swing: a push into an obstacle destroys it, the target suffers 2, the Cragheart gains 1 XP.
    func testHeavingSwingPushesIntoAnObstacle() async throws {
        let cragheart = addCharacter("cragheart", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        let behind = HexCoord(4, 3).pushCandidates(awayFrom: HexCoord(3, 3))
        for hex in behind { coord.boardState.placeObstacle(at: hex) }   // every way back is an obstacle
        let turn = turn(for: cragheart, top: try card("Heaving Swing", of: "cragheart"), bottom: try card("Avalanche", of: "cragheart"))
        let xp = cragheart.experience
        turn.executeCurrentAction()
        guard let piece = coord.boardState.piecePositions.first(where: { $0.value == HexCoord(4, 3) })?.key else { return XCTFail() }
        coord.handlePieceTap(piece)
        _ = await waitUntil { turn.currentActionIndex > 0 }
        let landed = try XCTUnwrap(coord.boardState.piecePositions[piece])
        XCTAssertTrue(behind.contains(landed), "pushed into an obstacle hex")
        XCTAssertNil(coord.boardState.cells[landed]?.overlay, "that obstacle is gone")
        XCTAssertGreaterThanOrEqual(cragheart.experience, xp + 1)
    }

    // MARK: - Mindthief augments

    /// Play `augment`'s top (the augment, then its own Attack) against an adjacent Bandit Guard.
    private func playAugment(_ augment: String, other: String = "Corrupting Embrace") throws
        -> (mindthief: GameCharacter, turn: PlayerTurnController, bandit: GameMonsterEntity) {
        let mindthief = gm.game.characters.first { $0.name == "mindthief" } ?? addCharacter("mindthief", at: HexCoord(3, 3))
        let bandit = coord.monsterEntity(name: "bandit-guard", standee: 1) ?? addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 50
        bandit.maxHealth = 50
        let played = try card(augment, of: "mindthief"), second = try card(other, of: "mindthief")
        mindthief.handCards = [played.cardId!, second.cardId!]
        let turn = PlayerTurnController(characterID: mindthief.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: played, bottom: second)
        turn.executeCurrentAction()   // the augment
        turn.executeCurrentAction()   // its Attack
        return (mindthief, turn, bandit)
    }

    /// Regression: an augment's box was performed when played (Parasitic Influence healed at
    /// once, Withering Claw asked for a target); it now shapes the melee attacks instead.
    func testAnAugmentShapesMeleeAttacks() throws {
        let weakness = try playAugment("The Mind's Weakness")
        XCTAssertEqual(weakness.turn.currentAttackValue(), 3, "Attack 1, +2 from the augment")

        let (mindthief, claw, _) = try playAugment("Withering Claw")
        XCTAssertEqual(Set(claw.pendingConditions), [.muddle, .poison])
        if case .selectingConditionTarget = coord.interactionMode { XCTFail("the augment isn't a condition to place") }
        XCTAssertFalse(mindthief.entityConditions.contains { $0.name == .muddle })
    }

    func testParasiticInfluenceHealsOnTheAttackNotWhenPlayed() throws {
        let mindthief = addCharacter("mindthief", at: HexCoord(3, 3))
        mindthief.health = 3
        addMonster("bandit-guard", at: HexCoord(4, 3))
        let parasitic = try card("Parasitic Influence", of: "mindthief"), other = try card("Corrupting Embrace", of: "mindthief")
        mindthief.handCards = [parasitic.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: mindthief.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: parasitic, bottom: other)
        turn.executeCurrentAction()
        XCTAssertEqual(mindthief.health, 3, "playing the augment heals no one")
        turn.executeCurrentAction()
        XCTAssertEqual(mindthief.health, 5, "its melee attack: Heal 2, self")
    }

    func testANewAugmentDiscardsTheOld() throws {
        let mindthief = addCharacter("mindthief", at: HexCoord(3, 3))
        let weakness = try card("The Mind's Weakness", of: "mindthief")
        mindthief.activeCards = [weakness.cardId!]
        _ = try playAugment("Withering Claw")
        XCTAssertFalse(mindthief.activeCards.contains(weakness.cardId!))
        XCTAssertTrue(mindthief.discardedCards.contains(weakness.cardId!))
    }

    /// Regression: "Attack 2, all enemies moved through" (Trample) attacked no one.
    func testTrampleAttacksEveryEnemyJumpedOver() async throws {
        let character = addCharacter(at: HexCoord(3, 3))
        let first = addMonster("bandit-guard", at: HexCoord(4, 3))
        let second = addMonster("bandit-guard", at: HexCoord(5, 3))
        addMonster("bandit-guard", at: HexCoord(3, 5))   // not in the way
        for bandit in [first, second] { bandit.health = 50; bandit.maxHealth = 50 }
        let trample = try card("Trample", of: "brute"), other = try card("Spare Dagger", of: "brute")
        character.handCards = [trample.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: trample)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()   // Move 4, Jump
        coord.handleHexTap(HexCoord(6, 3))
        _ = await waitUntil { turn.currentActionIndex == 1 }
        XCTAssertEqual(Set(turn.hexesPassed), [HexCoord(4, 3), HexCoord(5, 3)])
        turn.executeCurrentAction()   // Attack 2, every enemy moved through
        _ = await waitUntil { turn.currentActionIndex == 2 }
        let attacked = coord.turnLog.filter { $0.message.contains("attacks Bandit Guard") }.map(\.message)
        XCTAssertEqual(attacked.count, 2, attacked.joined(separator: " / "))
        XCTAssertFalse(attacked.contains { $0.contains("Bandit Guard 3") })
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
