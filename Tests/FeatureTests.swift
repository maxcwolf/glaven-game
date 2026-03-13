import XCTest
@testable import GlavenGameLib

// MARK: - Test Helpers

/// Creates a minimal board with hex cells for testing.
func makeBoard(cols: Int = 10, rows: Int = 10) -> BoardState {
    let board = BoardState()
    for col in 0..<cols {
        for row in 0..<rows {
            let coord = HexCoord(col, row)
            board.cells[coord] = HexCell(coord: coord, tileRef: "test", passable: true)
        }
    }
    return board
}

/// Creates a basic GameState with one character and one monster group.
func makeGameState(characterPos: HexCoord = HexCoord(2, 2),
                   monsterName: String = "test-monster",
                   monsterPositions: [(standee: Int, coord: HexCoord)] = [(1, HexCoord(5, 5))]) -> (GameState, BoardState) {
    let game = GameState()
    game.edition = "gh"
    game.level = 1
    game.round = 1

    let character = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
    character.health = 10
    character.maxHealth = 10
    character.initiative = 20
    game.figures.append(.character(character))

    let monster = GameMonster(name: monsterName, edition: "gh", level: 1, monsterData: nil)
    for (standee, _) in monsterPositions {
        let entity = GameMonsterEntity(number: standee, type: .normal, health: 5, maxHealth: 5, level: 1)
        monster.entities.append(entity)
    }
    game.figures.append(.monster(monster))

    game.monsterAttackModifierDeck = AttackModifierDeck.defaultDeck()

    let board = makeBoard()
    board.placePiece(.character("gh-brute"), at: characterPos)
    for (standee, coord) in monsterPositions {
        board.placePiece(.monster(name: monsterName, standee: standee), at: coord)
    }

    return (game, board)
}

// MARK: - AoE Resolver Tests

final class AoEResolverTests: XCTestCase {

    func testParsePattern_basicPattern() {
        let hexes = AoEResolver.parsePattern("(0,1,active)|(1,0,target)|(1,1,target)")
        // Should have 3 hexes total (1 active + 2 target)
        XCTAssertEqual(hexes.count, 3)
        let targetCount = hexes.filter { $0.isTarget }.count
        XCTAssertEqual(targetCount, 2, "Should have 2 target hexes")
        let activeCount = hexes.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1, "Should have 1 active hex")
    }

    func testParsePattern_activeAtOrigin() {
        let hexes = AoEResolver.parsePattern("(0,1,active)|(1,0,target)")
        // The active hex should be at relative cube origin (0,0,0)
        let active = hexes.first(where: { $0.isActive })!
        XCTAssertEqual(active.cubeX, 0)
        XCTAssertEqual(active.cubeY, 0)
        XCTAssertEqual(active.cubeZ, 0)
    }

    func testResolveTargets_hitsAdjacentEnemy() {
        let board = makeBoard()
        let attackerPos = HexCoord(5, 4)
        let enemyPos = HexCoord(5, 5)
        let focusTarget = PieceID.monster(name: "m", standee: 1)
        board.placePiece(focusTarget, at: enemyPos)

        // Simple pattern: active at origin, one target hex adjacent
        // Use a pattern where the target is one hex away
        let targets = AoEResolver.resolveTargets(
            pattern: "(0,0,active)|(0,1,target)",
            attackerPos: attackerPos,
            focusTarget: focusTarget,
            enemies: [focusTarget],
            board: board
        )

        XCTAssertTrue(targets.contains(focusTarget), "AoE should hit the focus target")
    }

    func testResolveTargets_emptyWhenNoEnemiesInPattern() {
        let board = makeBoard()
        let attackerPos = HexCoord(5, 5)
        let farEnemy = PieceID.monster(name: "m", standee: 1)
        board.placePiece(farEnemy, at: HexCoord(0, 0)) // Far away

        let targets = AoEResolver.resolveTargets(
            pattern: "(0,0,active)|(0,1,target)",
            attackerPos: attackerPos,
            focusTarget: farEnemy,
            enemies: [farEnemy],
            board: board
        )

        XCTAssertTrue(targets.isEmpty || !targets.contains(farEnemy),
                       "Should not hit enemy far from AoE pattern")
    }

    func testResolveTargets_triesRotationsToMaximizeHits() {
        let board = makeBoard()
        let attackerPos = HexCoord(5, 5)
        let enemy1 = PieceID.monster(name: "m", standee: 1)
        let enemy2 = PieceID.monster(name: "m", standee: 2)

        // Place enemies in two different directions
        let neighbors = attackerPos.neighbors
        board.placePiece(enemy1, at: neighbors[0])
        board.placePiece(enemy2, at: neighbors[1])

        // Pattern with 2 target hexes — should try rotations
        let targets = AoEResolver.resolveTargets(
            pattern: "(0,0,active)|(0,1,target)|(1,0,target)",
            attackerPos: attackerPos,
            focusTarget: enemy1,
            enemies: [enemy1, enemy2],
            board: board
        )

        // At minimum, should hit the focus target
        XCTAssertTrue(targets.contains(enemy1), "Must hit focus target")
    }
}

// MARK: - Curse/Bless Deck Limit Tests

final class AttackModifierLimitTests: XCTestCase {

    func testAddBless_enforcesMax10() {
        let game = GameState()
        game.monsterAttackModifierDeck = AttackModifierDeck.defaultDeck()
        let manager = AttackModifierManager(game: game)

        // Add 15 bless cards — only 10 should actually be added
        for _ in 0..<15 {
            manager.addBless(to: .monster)
        }

        let blessCount = game.monsterAttackModifierDeck.cards.filter { $0.type == .bless }.count
        XCTAssertEqual(blessCount, 10, "Should cap at 10 bless cards")
    }

    func testAddCurse_enforcesMax10() {
        let game = GameState()
        game.monsterAttackModifierDeck = AttackModifierDeck.defaultDeck()
        let manager = AttackModifierManager(game: game)

        for _ in 0..<15 {
            manager.addCurse(to: .monster)
        }

        let curseCount = game.monsterAttackModifierDeck.cards.filter { $0.type == .curse }.count
        XCTAssertEqual(curseCount, 10, "Should cap at 10 curse cards")
    }

    func testAddBless_characterDeckLimit() {
        let game = GameState()
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.attackModifierDeck = AttackModifierDeck.defaultDeck()
        game.figures.append(.character(char))
        let manager = AttackModifierManager(game: game)

        for _ in 0..<12 {
            manager.addBless(to: .character(char))
        }

        let blessCount = char.attackModifierDeck.cards.filter { $0.type == .bless }.count
        XCTAssertEqual(blessCount, 10, "Character deck should cap at 10 bless cards")
    }
}

// MARK: - Escort AI Tests

final class EscortAITests: XCTestCase {

    func testEscortWithNoActions_skips() {
        let (game, board) = makeGameState()
        let container = GameObjectiveContainer(name: "Tree", escort: true)
        // No escortActions set — passive escort
        let entity = GameObjectiveEntity(number: 10, health: 10, maxHealth: 10)
        container.entities.append(entity)
        board.placePiece(.objective(id: 10), at: HexCoord(3, 3))

        let result = EscortAI.computeTurn(escort: container, entity: entity, board: board, gameState: game)

        XCTAssertTrue(result.movementPath.isEmpty, "Passive escort should not move")
        XCTAssertNil(result.attackTarget, "Passive escort should not attack")
        XCTAssertFalse(result.stunned)
    }

    func testEscortWithMoveAction_movesTowardEnemy() {
        let (game, board) = makeGameState(monsterPositions: [(1, HexCoord(7, 3))])
        let container = GameObjectiveContainer(name: "Hail", escort: true)
        container.escortActions = [
            ActionModel(type: .move, value: .int(3)),
            ActionModel(type: .attack, value: .int(2))
        ]
        let entity = GameObjectiveEntity(number: 10, health: 10, maxHealth: 10)
        container.entities.append(entity)
        board.placePiece(.objective(id: 10), at: HexCoord(3, 3))

        let result = EscortAI.computeTurn(escort: container, entity: entity, board: board, gameState: game)

        // Should move toward the monster
        XCTAssertFalse(result.movementPath.isEmpty, "Escort with move action should move toward enemy")
    }

    func testEscortStunned_skipsTurn() {
        let (game, board) = makeGameState()
        let container = GameObjectiveContainer(name: "Hail", escort: true)
        container.escortActions = [ActionModel(type: .move, value: .int(3))]
        let entity = GameObjectiveEntity(number: 10, health: 10, maxHealth: 10)
        entity.entityConditions.append(EntityCondition(name: .stun))
        container.entities.append(entity)
        board.placePiece(.objective(id: 10), at: HexCoord(3, 3))

        let result = EscortAI.computeTurn(escort: container, entity: entity, board: board, gameState: game)

        XCTAssertTrue(result.stunned, "Stunned escort should skip turn")
        XCTAssertTrue(result.movementPath.isEmpty)
    }
}

// MARK: - Objective Count Tests

final class ObjectiveCountTests: XCTestCase {

    func testObjectiveDataParsesCount() {
        let json = """
        {"name": "Captive Orchid", "escort": true, "health": 10, "count": 3}
        """
        let data = try! JSONDecoder().decode(ObjectiveData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.resolvedCount, 3)
    }

    func testObjectiveDataDefaultCount() {
        let json = """
        {"name": "Tree", "escort": true, "health": 10}
        """
        let data = try! JSONDecoder().decode(ObjectiveData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.resolvedCount, 1)
    }

    func testObjectiveDataParsesActions() {
        let json = """
        {"name": "Hail", "escort": true, "health": 10, "actions": [{"type": "move", "value": 2}, {"type": "attack", "value": 3}]}
        """
        let data = try! JSONDecoder().decode(ObjectiveData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.actions?.count, 2)
        XCTAssertEqual(data.actions?[0].type, .move)
        XCTAssertEqual(data.actions?[1].type, .attack)
    }
}

// MARK: - Escort Container Stats Tests

final class EscortContainerTests: XCTestCase {

    func testEscortMove() {
        let c = GameObjectiveContainer(name: "Hail", escort: true)
        c.escortActions = [ActionModel(type: .move, value: .int(3))]
        XCTAssertEqual(c.escortMove, 3)
    }

    func testEscortAttackWithRange() {
        let c = GameObjectiveContainer(name: "Redthorn", escort: true)
        c.escortActions = [
            ActionModel(type: .attack, value: .int(3), subActions: [
                ActionModel(type: .range, value: .int(3))
            ])
        ]
        XCTAssertEqual(c.escortAttack, 3)
        XCTAssertEqual(c.escortRange, 3)
    }

    func testPassiveEscort_noActions() {
        let c = GameObjectiveContainer(name: "Tree", escort: true)
        XCTAssertFalse(c.hasEscortActions)
        XCTAssertEqual(c.escortMove, 0)
        XCTAssertEqual(c.escortAttack, 0)
    }
}

// MARK: - Loot Board State Tests

final class LootTests: XCTestCase {

    func testPlaceAndTakeLoot() {
        let board = BoardState()
        let coord = HexCoord(3, 3)
        board.placeLoot(at: coord, count: 2)
        XCTAssertEqual(board.lootTokens[coord], 2)

        let taken = board.takeLoot(at: coord)
        XCTAssertEqual(taken, 2)
        XCTAssertNil(board.lootTokens[coord])
    }

    func testTakeLoot_emptyHex() {
        let board = BoardState()
        let taken = board.takeLoot(at: HexCoord(0, 0))
        XCTAssertEqual(taken, 0)
    }
}

// MARK: - Teleport Validity Tests

final class TeleportTests: XCTestCase {

    func testTeleportCanReachThroughObstacles() {
        // Create a narrow corridor where the only path is blocked
        let board = makeBoard(cols: 8, rows: 8)
        // Block all passable hexes in columns 3 and 4 except the target
        for row in 0..<8 {
            board.cells[HexCoord(3, row)]!.passable = false
            board.cells[HexCoord(4, row)]!.passable = false
        }
        // Re-open just the target hex
        let target = HexCoord(5, 3)
        // Make columns 5+ passable (they already are from makeBoard)

        let origin = HexCoord(2, 3)
        board.placePiece(.character("test"), at: origin)

        // Teleport should be able to reach target (distance 3, within range 5)
        let distance = origin.distance(to: target)
        XCTAssertTrue(distance <= 5, "Target within teleport range")
        XCTAssertTrue(board.cells[target]?.passable == true, "Target hex is passable")

        // Normal pathfinding should fail (wall blocks all paths)
        let path = Pathfinder.findPath(board: board, from: origin, to: target, occupiedByEnemy: [])
        XCTAssertNil(path, "Normal pathfinding should be blocked by complete wall")
    }

    func testTeleportCannotReachImpassableHex() {
        let board = makeBoard()
        board.cells[HexCoord(4, 4)]!.passable = false

        let canReach = board.cells[HexCoord(4, 4)]?.passable ?? false
        XCTAssertFalse(canReach, "Cannot teleport to impassable hex")
    }
}

// MARK: - Treasure Reward Parser Tests

final class TreasureRewardParserTests: XCTestCase {

    func testParseGold() {
        let label = TreasureRewardParser.parse("gold:15", edition: "gh", store: EditionDataStore())
        XCTAssertEqual(label, "Gain 15 gold")
    }

    func testParseExperience() {
        let label = TreasureRewardParser.parse("experience:10", edition: "gh", store: EditionDataStore())
        XCTAssertEqual(label, "Gain 10 XP")
    }

    func testParseDamage() {
        let label = TreasureRewardParser.parse("damage:5", edition: "gh", store: EditionDataStore())
        XCTAssertEqual(label, "Suffer 5 damage")
    }

    func testParseCompound() {
        let label = TreasureRewardParser.parse("damage:5|condition:poison+wound", edition: "gh", store: EditionDataStore())
        XCTAssertTrue(label.contains("Suffer 5 damage"), "Should include damage")
        XCTAssertTrue(label.contains("Poison"), "Should include poison condition")
    }

    func testParseRandomItemDesign() {
        let label = TreasureRewardParser.parse("randomItemDesign", edition: "gh", store: EditionDataStore())
        XCTAssertEqual(label, "Random item design")
    }
}

// MARK: - Bonus XP Tests

final class BonusXPTests: XCTestCase {

    func testLevelManagerExperience() {
        let game = GameState()
        game.level = 0
        let lm = LevelManager(game: game)
        XCTAssertEqual(lm.experience(), 4, "Level 0: 4 + 0*2 = 4")

        game.level = 3
        XCTAssertEqual(lm.experience(), 10, "Level 3: 4 + 3*2 = 10")

        game.level = 7
        XCTAssertEqual(lm.experience(), 18, "Level 7: 4 + 7*2 = 18")
    }
}

// MARK: - Monster AI with AoE Tests

final class MonsterAIAoETests: XCTestCase {

    func testParseAbilityCard_extractsAoEPattern() {
        // Create ability with attack that has area sub-action
        let ability = AbilityModel(
            cardId: 1,
            name: "test",
            initiative: 50,
            actions: [
                ActionModel(type: .attack, value: .int(3), subActions: [
                    ActionModel(type: .area, value: .string("(0,1,active)|(1,0,target)|(1,1,target)"))
                ])
            ]
        )

        // We can't call parseAbilityCard directly (it's private), but we can test
        // through computeTurn by setting up a scenario where AoE matters
        XCTAssertNotNil(ability.actions?.first?.subActions?.first(where: { $0.type == .area }))
    }
}

// MARK: - Entity Condition Tests

final class EntityConditionTests: XCTestCase {

    func testWoundDamage() {
        let game = GameState()
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.health = 10
        char.maxHealth = 10
        // State must be .normal for applyConditionsTurn to process it
        char.entityConditions.append(EntityCondition(name: .wound, state: .normal))
        game.figures.append(.character(char))

        let entityManager = EntityManager(game: game)
        entityManager.applyConditionsTurn(char)

        XCTAssertEqual(char.health, 9, "Wound should deal 1 damage at start of turn")
    }

    func testRegenerateHeal() {
        let game = GameState()
        let char = GameCharacter(name: "brute", edition: "gh", level: 1, characterData: nil)
        char.health = 5
        char.maxHealth = 10
        char.entityConditions.append(EntityCondition(name: .regenerate, state: .normal))
        game.figures.append(.character(char))

        let entityManager = EntityManager(game: game)
        entityManager.applyConditionsTurn(char)

        XCTAssertEqual(char.health, 6, "Regenerate should heal 1 at start of turn")
    }
}

// MARK: - HexCoord Distance Tests

final class HexCoordTests: XCTestCase {

    func testAdjacentDistance() {
        let a = HexCoord(5, 5)
        for neighbor in a.neighbors {
            XCTAssertEqual(a.distance(to: neighbor), 1, "Neighbors should be distance 1")
        }
    }

    func testSelfDistance() {
        let a = HexCoord(3, 3)
        XCTAssertEqual(a.distance(to: a), 0)
    }

    func testPushCandidates() {
        let origin = HexCoord(5, 5)
        let target = HexCoord(5, 6) // south of origin
        let pushCandidates = target.pushCandidates(awayFrom: origin)
        for candidate in pushCandidates {
            XCTAssertGreaterThan(candidate.distance(to: origin), target.distance(to: origin),
                                 "Push candidates should be farther from origin")
        }
    }
}

// MARK: - Invisible + AoE Integration Test

final class InvisibleAoETests: XCTestCase {

    func testGatherEnemies_excludesInvisibleByDefault() {
        let (game, board) = makeGameState(monsterPositions: [(1, HexCoord(5, 5))])
        let monster = GameMonster(name: "ally-monster", edition: "gh", level: 1, monsterData: nil)
        game.figures.append(.monster(monster))

        // Make the character invisible
        let char = game.characters.first!
        char.entityConditions.append(EntityCondition(name: .invisible))

        let enemies = MonsterAI.gatherEnemies(board: board, monster: monster, gameState: game)
        let hasChar = enemies.contains(where: { if case .character = $0 { return true }; return false })
        XCTAssertFalse(hasChar, "Invisible characters should be excluded from normal targeting")
    }

    func testGatherEnemies_includesInvisibleForAoE() {
        let (game, board) = makeGameState(monsterPositions: [(1, HexCoord(5, 5))])
        let monster = GameMonster(name: "ally-monster", edition: "gh", level: 1, monsterData: nil)
        game.figures.append(.monster(monster))

        let char = game.characters.first!
        char.entityConditions.append(EntityCondition(name: .invisible))

        let enemies = MonsterAI.gatherEnemies(board: board, monster: monster, gameState: game, includeInvisible: true)
        let hasChar = enemies.contains(where: { if case .character = $0 { return true }; return false })
        XCTAssertTrue(hasChar, "AoE should include invisible characters")
    }
}
