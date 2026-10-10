import XCTest
@testable import GlavenGameLib

// MARK: - Test Game Builder

/// Sets up a full game environment for integration/e2e tests without UI or SwiftData.
final class TestGame {
    let game: GameState
    let editionStore: EditionDataStore
    let entityManager: EntityManager
    let attackModifierManager: AttackModifierManager
    let monsterManager: MonsterManager
    let characterManager: CharacterManager
    let roundManager: RoundManager
    let levelManager: LevelManager
    let board: BoardState

    init(edition: String = "gh", level: Int = 1) {
        game = GameState()
        game.edition = edition
        game.level = level
        game.monsterAttackModifierDeck = AttackModifierDeck.defaultDeck()
        game.allyAttackModifierDeck = AttackModifierDeck.defaultDeck()

        editionStore = EditionDataStore()
        editionStore.loadAllEditions()

        entityManager = EntityManager(game: game)
        attackModifierManager = AttackModifierManager(game: game)
        levelManager = LevelManager(game: game)
        monsterManager = MonsterManager(game: game, editionStore: editionStore)
        characterManager = CharacterManager(game: game, editionStore: editionStore,
                                             entityManager: entityManager,
                                             attackModifierManager: attackModifierManager)
        roundManager = RoundManager(game: game, entityManager: entityManager,
                                     monsterManager: monsterManager,
                                     attackModifierManager: attackModifierManager)

        board = makeBoard(cols: 12, rows: 12)
    }

    /// Add a character to the game and place it on the board.
    @discardableResult
    func addCharacter(name: String = "brute", pos: HexCoord = HexCoord(2, 2),
                      initiative: Int = 20) -> GameCharacter {
        let char = GameCharacter(name: name, edition: game.edition ?? "gh", level: game.level, characterData: nil)
        char.health = 10
        char.maxHealth = 10
        char.initiative = initiative
        char.handCards = Array(1...10)  // 10 cards in hand
        char.attackModifierDeck = AttackModifierDeck.defaultDeck()
        game.figures.append(.character(char))
        board.placePiece(.character(char.id), at: pos)
        return char
    }

    /// Add a monster group using edition data and place standees on the board.
    @discardableResult
    func addMonster(name: String, positions: [(type: MonsterType, coord: HexCoord)]) -> GameMonster? {
        monsterManager.addMonster(name: name, edition: game.edition ?? "gh")
        guard let monster = game.monsters.first(where: { $0.name == name }) else { return nil }
        for (type, coord) in positions {
            monsterManager.addEntity(type: type, to: monster)
            if let entity = monster.entities.last {
                board.placePiece(.monster(name: name, standee: entity.number), at: coord)
            }
        }
        return monster
    }

    /// Add a simple monster without edition data (for isolated tests).
    @discardableResult
    func addSimpleMonster(name: String = "test-monster",
                          positions: [(standee: Int, coord: HexCoord, hp: Int)] = [(1, HexCoord(5, 5), 5)]) -> GameMonster {
        let monster = GameMonster(name: name, edition: "gh", level: game.level, monsterData: nil)
        for (standee, coord, hp) in positions {
            let entity = GameMonsterEntity(number: standee, type: .normal, health: hp, maxHealth: hp, level: game.level)
            monster.entities.append(entity)
            board.placePiece(.monster(name: name, standee: standee), at: coord)
        }
        game.figures.append(.monster(monster))
        return monster
    }

    /// Advance from draw phase to next phase (simulates clicking "play").
    func advanceRound() {
        if game.state == .draw {
            roundManager.nextGameState()
        }
    }

    /// Complete a full round cycle: draw → next → draw.
    func completeRound() {
        if game.state == .draw {
            roundManager.nextGameState() // → .next
        }
        roundManager.nextGameState() // → .draw
    }
}

// MARK: - E2E: Full Round Flow

final class E2ERoundFlowTests: XCTestCase {

    func testFullRoundCycle_drawToNextToDraw() {
        let t = TestGame()
        let char = t.addCharacter(initiative: 30)

        XCTAssertEqual(t.game.state, .draw)
        XCTAssertEqual(t.game.round, 0)

        // Set initiative (simulates card selection)
        char.initiative = 30

        // Advance: draw → next
        t.roundManager.nextGameState()
        XCTAssertEqual(t.game.state, .next)
        XCTAssertEqual(t.game.round, 1, "Round should increment on transition to .next")

        // Advance: next → draw
        t.roundManager.nextGameState()
        XCTAssertEqual(t.game.state, .draw)
        XCTAssertEqual(t.game.round, 1, "Round stays same on transition to .draw")

        // Character initiative should be reset
        XCTAssertEqual(char.initiative, 0, "Initiative resets on draw transition")
    }

    func testMultipleRounds_roundCountIncrements() {
        let t = TestGame()
        t.addCharacter()

        for expected in 1...3 {
            t.game.characters.first!.initiative = 20
            t.completeRound()
            XCTAssertEqual(t.game.round, expected, "After \(expected) round(s)")
        }
    }

    // Initiative order and its ties (a character before a monster type, the second card between
    // characters) are tested through the coordinator's turn order:
    // RoundRuleTests.testInitiativeOrderAndItsTies, RestRuleTests.testALongRestGoesAfterACharacterOnNinetyNine.
}

// MARK: - E2E: Monster AI Combat

final class E2EMonsterCombatTests: XCTestCase {

    func testMonsterAI_movesTowardCharacter() throws {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(2, 2))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(6, 2), 5)])

        // Create ability: Move 2, Attack 2
        let ability = AbilityModel(cardId: 1, initiative: 50,
                                    actions: [
                                        ActionModel(type: .move, value: .int(2)),
                                        ActionModel(type: .attack, value: .int(2))
                                    ])

        let entity = monster.entities[0]
        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster,
            entity: entity,
            ability: ability,
            board: t.board,
            gameState: t.game
        )

        XCTAssertEqual(result.focusTarget, .character("gh-brute"), "Monster should have a focus target")
        // Four hexes away with Move 2: it can't attack this turn, so it uses all its movement
        // along the shortest way and ends two hexes nearer.
        XCTAssertEqual(result.movementPath.first, HexCoord(6, 2))
        XCTAssertEqual(result.movementPath.count - 1, 2, "both points of movement")
        let end = try XCTUnwrap(result.movementPath.last)
        XCTAssertEqual(end.distance(to: HexCoord(2, 2)), 2, "Monster should be two hexes closer after moving")
        XCTAssertTrue(result.attackTargets.isEmpty, "still out of reach")
    }

    func testMonsterAI_attacksWhenAdjacent() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50,
                                    actions: [
                                        ActionModel(type: .move, value: .int(2)),
                                        ActionModel(type: .attack, value: .int(3))
                                    ])

        let entity = monster.entities[0]
        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster,
            entity: entity,
            ability: ability,
            board: t.board,
            gameState: t.game
        )

        XCTAssertEqual(result.attackTargets, [.character("gh-brute")], "Adjacent monster should attack the Brute, once")
        XCTAssertTrue(result.movementPath.count <= 1, "beside its focus already: it stays")
    }

    func testMonsterAI_stunnedSkipsTurn() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])
        let entity = monster.entities[0]
        entity.entityConditions.append(EntityCondition(name: .stun, state: .normal))

        let ability = AbilityModel(cardId: 1, initiative: 50,
                                    actions: [ActionModel(type: .attack, value: .int(3))])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: ability,
            board: t.board, gameState: t.game
        )

        XCTAssertTrue(result.stunned, "Stunned monster should skip turn")
        XCTAssertTrue(result.movementPath.isEmpty)
        XCTAssertTrue(result.attackTargets.isEmpty)
    }

    func testMonsterAI_disarmedMovesButDoesntAttack() throws {
        let t = TestGame()
        let character = t.addCharacter(pos: HexCoord(2, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(6, 5), 5)])
        let entity = monster.entities[0]
        entity.entityConditions.append(EntityCondition(name: .disarm, state: .normal))

        let ability = AbilityModel(cardId: 1, initiative: 50,
                                    actions: [
                                        ActionModel(type: .move, value: .int(2)),
                                        ActionModel(type: .attack, value: .int(3))
                                    ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: ability,
            board: t.board, gameState: t.game
        )

        XCTAssertTrue(result.disarmed, "Monster should be disarmed")
        XCTAssertEqual(result.focusTarget, .character(character.id), "it still has a focus")
        XCTAssertEqual(result.movementPath.count - 1, 2, "and moves toward it")
        XCTAssertEqual(try XCTUnwrap(result.movementPath.last).distance(to: HexCoord(2, 5)), 2)
        XCTAssertTrue(result.attackTargets.isEmpty, "Disarmed monster should not attack")

        // A ranged attack it can't make doesn't hold it at range: disarmed, it moves as for a
        // melee attack, as near its focus as it can (FAQ) — where armed it would stay and shoot.
        let ranged = AbilityModel(cardId: 2, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(2)),
            ActionModel(type: .attack, value: .int(3), subActions: [ActionModel(type: .range, value: .int(4))])
        ])
        let closing = MonsterAI.computeTurn(pieceID: .monster(name: "test-monster", standee: 1), monster: monster,
                                            entity: entity, ability: ranged, board: t.board, gameState: t.game)
        XCTAssertEqual(try XCTUnwrap(closing.movementPath.last).distance(to: HexCoord(2, 5)), 2, "two hexes nearer")
        XCTAssertTrue(closing.attackTargets.isEmpty)
        entity.entityConditions = []
        let armed = MonsterAI.computeTurn(pieceID: .monster(name: "test-monster", standee: 1), monster: monster,
                                          entity: entity, ability: ranged, board: t.board, gameState: t.game)
        XCTAssertTrue(armed.movementPath.isEmpty, "in range already")
        XCTAssertEqual(armed.attackTargets, [.character(character.id)])
    }
}

// MARK: - E2E: Combat Resolution

final class E2ECombatTests: XCTestCase {

    func testCombatResolver_basicAttack() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            advantage: false,
            disadvantage: false,
            isPoisoned: false,
            shield: 0,
            retaliateValue: 0,
            retaliateRange: 0,
            attackerDefenderDistance: 1,
            preDrawnCards: [AttackModifier(type: .plus0, value: 0)],
            drawModifier: { nil },
            defenderHealth: 10
        )

        XCTAssertEqual(result.damage, 3, "Base attack 3 with +0 modifier = 3 damage")
        XCTAssertFalse(result.isMiss)
    }

    func testCombatResolver_shieldReducesDamage() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 5,
            advantage: false, disadvantage: false,
            isPoisoned: false,
            shield: 2,
            retaliateValue: 0, retaliateRange: 0,
            attackerDefenderDistance: 1,
            preDrawnCards: [AttackModifier(type: .plus0, value: 0)],
            drawModifier: { nil },
            defenderHealth: 10
        )

        XCTAssertEqual(result.damage, 3, "5 attack - 2 shield = 3 damage")
    }

    func testCombatResolver_nullCardMisses() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 5,
            advantage: false, disadvantage: false,
            isPoisoned: false,
            shield: 0,
            retaliateValue: 0, retaliateRange: 0,
            attackerDefenderDistance: 1,
            preDrawnCards: [AttackModifier(type: .null_, value: 0, valueType: .multiply)],
            drawModifier: { nil },
            defenderHealth: 10
        )

        XCTAssertTrue(result.isMiss, "Null card should miss")
        XCTAssertEqual(result.damage, 0, "Miss should deal 0 damage")
    }

    func testCombatResolver_doubleCard() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 4,
            advantage: false, disadvantage: false,
            isPoisoned: false,
            shield: 0,
            retaliateValue: 0, retaliateRange: 0,
            attackerDefenderDistance: 1,
            preDrawnCards: [AttackModifier(type: .double_, value: 2, valueType: .multiply)],
            drawModifier: { nil },
            defenderHealth: 10
        )

        XCTAssertEqual(result.damage, 8, "4 attack × 2 = 8 damage")
    }

    func testCombatResolver_poisonAddsOne() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            advantage: false, disadvantage: false,
            isPoisoned: true,
            shield: 0,
            retaliateValue: 0, retaliateRange: 0,
            attackerDefenderDistance: 1,
            preDrawnCards: [AttackModifier(type: .plus0, value: 0)],
            drawModifier: { nil },
            defenderHealth: 10
        )

        XCTAssertEqual(result.damage, 4, "3 attack + 1 poison = 4 damage")
    }

    // Retaliate: ForcedMovementTests and AttackRuleTests (performAttack resolves it, not the
    // AttackResult these tests used to read).

    func testDamageKillsCharacter() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 3

        t.entityManager.changeHealth(char, amount: -5)
        XCTAssertTrue(char.exhausted, "Character at 0 HP should be exhausted")
        XCTAssertEqual(char.health, 0, "Health floors at 0")
    }

    func testDamageKillsMonster() {
        let t = TestGame()
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 5), 3)])
        let entity = monster.entities[0]

        t.entityManager.changeHealth(entity, amount: -5)
        XCTAssertTrue(entity.dead, "Monster at 0 HP should be dead")
        XCTAssertEqual(entity.health, 0)
    }
}

// MARK: - E2E: Condition Lifecycle

final class E2EConditionLifecycleTests: XCTestCase {

    func testConditionLifecycle_woundOverMultipleRounds() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10

        // Add wound condition
        t.entityManager.addCondition(.wound, to: char)
        XCTAssertTrue(t.entityManager.hasCondition(.wound, on: char))

        // Condition starts as .new — must be transitioned to .normal first
        t.entityManager.restoreConditions(char)
        XCTAssertEqual(char.entityConditions.first?.state, .normal)

        // Apply turn: wound deals 1 damage
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 9, "Wound should deal 1 damage")

        // Wound persists (it's not a turn-type condition)
        t.entityManager.expireConditions(char)
        XCTAssertTrue(t.entityManager.hasCondition(.wound, on: char),
                       "Wound should persist after turn")

        // Second round: wound deals 1 more damage
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 8, "Second round of wound")
    }

    func testConditionLifecycle_stunExpiresAfterTurn() {
        let t = TestGame()
        let char = t.addCharacter()

        t.entityManager.addCondition(.stun, to: char)
        t.entityManager.restoreConditions(char)

        // Apply start-of-turn
        t.entityManager.applyConditionsTurn(char)

        // Expire end-of-turn: stun should be marked for removal
        t.entityManager.expireConditions(char)

        // After restoration cycle, stun should be gone
        let hasStun = char.entityConditions.contains(where: { $0.name == .stun && !$0.expired })
        XCTAssertFalse(hasStun, "Stun should expire after one turn")
    }

    func testConditionLifecycle_poisonPersists() {
        let t = TestGame()
        let char = t.addCharacter()

        t.entityManager.addCondition(.poison, to: char)
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)

        // Poison persists (not a turn condition)
        XCTAssertTrue(t.entityManager.hasCondition(.poison, on: char),
                       "Poison should persist across turns")
    }

    func testConditionImmunity_blocksCondition() {
        let t = TestGame()
        let char = t.addCharacter()
        char.immunities = [.stun]

        t.entityManager.addCondition(.stun, to: char)
        XCTAssertFalse(t.entityManager.hasCondition(.stun, on: char),
                        "Immune entity should not receive condition")
    }
}

// MARK: - E2E: Scenario Finish and XP

final class E2EScenarioFinishTests: XCTestCase {

    func testScenarioVictory_awardsBonusXP() {
        let t = TestGame()
        let char = t.addCharacter()
        char.experience = 10

        // Set up a minimal scenario
        let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let scenarioManager = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                               monsterManager: t.monsterManager,
                                               levelManager: t.levelManager)
        t.game.level = 2
        let expectedBonusXP = t.levelManager.experience() // 4 + 2*2 = 8

        scenarioManager.finishScenario(success: true)

        XCTAssertEqual(char.experience, 10 + expectedBonusXP,
                        "Should gain bonus XP (4 + level*2) on victory")
    }

    func testScenarioDefeat_keepsXPAndGold() {
        let t = TestGame()
        let char = t.addCharacter()
        char.experience = 10
        char.loot = 5

        let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let scenarioManager = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                               monsterManager: t.monsterManager,
                                               levelManager: t.levelManager)

        scenarioManager.finishScenario(success: false)

        // GH p.47: experience and looted money are kept; only the success rewards are skipped.
        XCTAssertEqual(char.experience, 10, "XP should be kept on defeat")
        XCTAssertEqual(char.loot, 5, "Looted gold should be kept on defeat")
    }

    func testExhaustedCharacter_stillGetsBonusXP() {
        let t = TestGame()
        let char = t.addCharacter()
        char.experience = 10
        char.exhausted = true

        let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let scenarioManager = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                               monsterManager: t.monsterManager,
                                               levelManager: t.levelManager)

        scenarioManager.finishScenario(success: true)

        // GH p.47: an exhausted character still earns scenario rewards on a success.
        XCTAssertEqual(char.experience, 10 + t.levelManager.experience(),
                       "Exhausted character still gets the bonus XP")
    }
}

// MARK: - E2E: Full Game Simulation (Multiple Rounds)

final class E2EGameSimulationTests: XCTestCase {

    // Rounds of real play — monster turns, attacks, conditions, deaths and their money tokens —
    // are played by the turn loop itself in BoardSimulationTests and PlaythroughTests; a monster's
    // death dropping a token is BoardRulesRegressionTests.testKilledMonsterDropsMoneyButSummonedMonsterDoesNot.

    /// Simulates summon creation and AI turn.
    func testSummonAI_attacksMonster() {
        let t = TestGame()
        let char = t.addCharacter(pos: HexCoord(2, 2))

        // Create a summon manually
        let summon = GameSummon(name: "Rat", number: 1, health: 3, maxHealth: 3,
                                level: 1, attack: .int(2), movement: 3, range: 0)
        summon.state = .active
        char.summons.append(summon)
        t.board.placePiece(.summon(id: summon.id), at: HexCoord(3, 2))

        // Add a monster nearby
        t.addSimpleMonster(positions: [(1, HexCoord(5, 2), 5)])

        let result = SummonAI.computeTurn(
            summon: summon,
            ownerCharacterID: char.id,
            board: t.board,
            gameState: t.game
        )

        let enemy = PieceID.monster(name: "test-monster", standee: 1)
        XCTAssertEqual(result.focusTarget, enemy, "Summon should find a focus target")
        XCTAssertEqual(result.movementPath, [HexCoord(3, 2), HexCoord(4, 2)], "one step: beside the monster")
        XCTAssertEqual(result.attackFromHex, HexCoord(4, 2))
        XCTAssertEqual(result.attackTargets, [enemy], "and it attacks")
        XCTAssertEqual(result.attackValue, 2, "with its own Attack 2")
        XCTAssertFalse(result.stunned)
    }

    /// Simulates an escort objective taking a turn.
    func testEscortAI_fullTurn() throws {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(2, 2))
        t.addSimpleMonster(positions: [(1, HexCoord(7, 3), 5)])

        let container = GameObjectiveContainer(name: "Hail", escort: true)
        container.escortActions = [
            ActionModel(type: .move, value: .int(3)),
            ActionModel(type: .attack, value: .int(2))
        ]
        let entity = GameObjectiveEntity(number: 10, health: 10, maxHealth: 10)
        container.entities.append(entity)
        t.board.placePiece(.objective(id: 10), at: HexCoord(4, 3))

        let result = EscortAI.computeTurn(
            escort: container, entity: entity,
            board: t.board, gameState: t.game
        )

        let enemy = PieceID.monster(name: "test-monster", standee: 1)
        XCTAssertFalse(result.stunned)
        XCTAssertEqual(result.focusTarget, enemy, "Escort should have a focus")
        // Three hexes from the monster with Move 3 and a melee attack: two steps bring it beside
        // its focus, and it attacks from there.
        XCTAssertEqual(result.movementPath.first, HexCoord(4, 3))
        XCTAssertEqual(result.movementPath.count - 1, 2, "no further than it needs to attack")
        XCTAssertEqual(try XCTUnwrap(result.movementPath.last).distance(to: HexCoord(7, 3)), 1)
        XCTAssertEqual(result.attackTarget, enemy)
    }
}

// MARK: - E2E: Pathfinding and Movement

final class E2EPathfindingTests: XCTestCase {

    func testPathfindingAroundObstacles() throws {
        let board = makeBoard(cols: 10, rows: 10)
        // Create a wall
        for row in 0..<8 {
            board.cells[HexCoord(4, row)]!.passable = false
        }
        // Leave a gap at row 8
        board.cells[HexCoord(4, 8)]!.passable = true

        let path = Pathfinder.findPath(board: board, from: HexCoord(3, 3), to: HexCoord(5, 3), occupiedByEnemy: [])
        let around = try XCTUnwrap(path, "Should find path around the wall")
        XCTAssertGreaterThan(around.count, 3, "Path should go around the wall (not straight through)")
        XCTAssertTrue(around.contains { $0.col == 4 && $0.row >= 8 }, "through the gap at the bottom of the wall")
        XCTAssertFalse(around.contains { $0.col == 4 && $0.row < 8 }, "and through no obstacle")
        XCTAssertEqual(around.last, HexCoord(5, 3))
    }

    // Difficult terrain costing 2 and flying ignoring it: RB_TerrainTests (exact costs).

    func testLineOfSight_adjacentAlwaysVisible() {
        let board = makeBoard(cols: 10, rows: 10)
        let from = HexCoord(5, 5)
        for neighbor in from.neighbors {
            XCTAssertTrue(LineOfSight.hasLOS(from: from, to: neighbor, board: board),
                          "Adjacent hexes should always have LOS")
        }
    }

    // An obstacle never blocks line of sight (p.15): LineOfSightTests.testLOS_notBlockedByObstacleDirectlyBetween.
    // (The test that was here was named for the opposite and asserted nothing.)
}

// MARK: - E2E: Attack Modifier Deck

final class E2EAttackModifierTests: XCTestCase {

    func testDrawAllCardsAndShuffle() {
        let t = TestGame()
        var drawnCards: [AttackModifier] = []

        // Draw all cards from the monster deck
        let deckSize = t.game.monsterAttackModifierDeck.cards.count
        for _ in 0..<deckSize {
            if let card = t.attackModifierManager.drawMonsterCard() {
                drawnCards.append(card)
            }
        }

        XCTAssertEqual(drawnCards.count, deckSize, "Should draw all cards")
        XCTAssertEqual(deckSize, 20)
        XCTAssertEqual(Set(drawnCards.map(\.id)).count, 20, "each card once: nothing is drawn twice before a shuffle")
        XCTAssertEqual(drawnCards.filter(\.shuffle).count, 2, "the ×2 and the Null are among them")
        XCTAssertTrue(t.game.monsterAttackModifierDeck.needsShuffle,
                      "Deck should need shuffle after drawing shuffle-flagged card")
        XCTAssertEqual(t.game.monsterAttackModifierDeck.remainingCount, 0)

        // One more draw finds the pile empty: the deck is shuffled then and there.
        XCTAssertNotNil(t.attackModifierManager.drawMonsterCard())
        XCTAssertEqual(t.game.monsterAttackModifierDeck.remainingCount, 19)
    }

    // Bless and Curse through a shuffle (undrawn ones stay, drawn ones go):
    // RoundRuleTests.testAnUndrawnBlessStaysInTheDeckThroughAReshuffle and
    // testBlessAndCurseAreRemovedWhenDrawnAndCauseNoReshuffle.
}

// MARK: - E2E: Real Monster Data Integration

final class E2ERealMonsterTests: XCTestCase {

    func testLoadCultistAndComputeTurn() throws {
        let t = TestGame()
        let character = t.addCharacter(pos: HexCoord(3, 3))

        // Add a real cultist from edition data
        guard let monster = t.addMonster(name: "cultist", positions: [(.normal, HexCoord(6, 3))]) else {
            XCTFail("Should load cultist from edition data")
            return
        }

        XCTAssertFalse(monster.entities.isEmpty, "Cultist should have at least one entity")
        XCTAssertGreaterThan(monster.entities[0].health, 0, "Cultist should have health")
        XCTAssertFalse(monster.abilities.isEmpty, "Cultist should have ability deck")

        // Draw an ability
        t.monsterManager.drawAbility(for: monster)
        let ability = try XCTUnwrap(t.monsterManager.currentAbility(for: monster), "Should have drawn an ability card")
        XCTAssertTrue((604...611).contains(ability.cardId ?? 0), "a card of the Cultist deck: \(ability.cardId ?? 0)")
        XCTAssertEqual(monster.drawnInitiative, ability.initiative)

        // Compute a turn
        let entity = try XCTUnwrap(monster.aliveEntities.first)
        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "cultist", standee: entity.number),
            monster: monster,
            entity: entity,
            ability: ability,
            board: t.board,
            gameState: t.game
        )

        XCTAssertEqual(result.focusTarget, .character(character.id), "Cultist should find character as focus")
        XCTAssertEqual(result.initiative, ability.initiative)
        // Three hexes away with Move 2 on its stat card: whatever the card, it moves only if
        // the card has a Move, never past the hex beside its focus, and attacks only from there.
        let hasMove = (ability.actions ?? []).contains { $0.type == .move }
        if !hasMove { XCTAssertTrue(result.movementPath.isEmpty, "no Move on card \(ability.cardId ?? 0)") }
        let end = result.movementPath.last ?? HexCoord(6, 3)
        XCTAssertGreaterThanOrEqual(end.distance(to: HexCoord(3, 3)), 1)
        XCTAssertEqual(result.attackTargets.isEmpty, end.distance(to: HexCoord(3, 3)) > 1 || !MonsterAbility.hasAttack(ability.actions ?? []),
                       "it attacks exactly when its card has an attack and it stands beside its focus")
    }

    func testLoadLivingBonesAndVerifyStats() {
        let t = TestGame()
        guard let monster = t.addMonster(name: "living-bones", positions: [(.normal, HexCoord(5, 5))]) else {
            XCTFail("Should load living-bones")
            return
        }

        XCTAssertFalse(monster.entities.isEmpty)
        let entity = monster.entities[0]
        XCTAssertGreaterThan(entity.health, 0, "Living Bones should have health")
        XCTAssertGreaterThan(entity.maxHealth, 0)

        // Verify stats are loaded: a normal Living Bones at level 1 is 5 hit points, Move 3,
        // Attack 1, Target 2 and Shield 1.
        XCTAssertEqual(entity.health, 5)
        XCTAssertEqual(entity.maxHealth, 5)
        let stat = monster.stat(for: .normal)
        XCTAssertNotNil(stat, "Should have normal stat block")
        XCTAssertEqual(stat?.attackValue(characterCount: 2, level: 1), 1, "Should have attack value")
        XCTAssertEqual(stat?.movementValue(characterCount: 2, level: 1), 3, "Should have movement value")
        XCTAssertEqual(stat?.actions?.first { $0.type == .target }?.value?.intValue, 2)
        XCTAssertEqual(stat?.actions?.first { $0.type == .shield }?.value?.intValue, 1)
        XCTAssertEqual(monster.stat(for: .elite)?.movementValue(characterCount: 2, level: 1), 4)
        // The stat card's Shield is the monster's own from the moment it is on the board.
        t.monsterManager.applyStatEffects(for: monster)
        XCTAssertEqual(entity.shieldPersistent?.value?.intValue, 1)
        XCTAssertNil(entity.shield, "nothing from an ability card")
    }
}
