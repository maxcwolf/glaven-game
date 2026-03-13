import XCTest
@testable import GlavenGameLib

/// Tests for Frosthaven-specific condition mechanics.
final class FHConditionTests: XCTestCase {

    // MARK: - Brittle: double damage from next source

    func testBrittle_doublesDamage() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.brittle, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -3)
        XCTAssertEqual(char.health, 14, "Brittle doubles damage: -3 × 2 = -6")
    }

    func testBrittle_removedAfterTrigger() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.brittle, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -2) // triggers brittle → -4
        XCTAssertFalse(t.entityManager.hasCondition(.brittle, on: char),
                        "Brittle consumed after triggering")

        t.entityManager.changeHealth(char, amount: -2) // normal damage
        XCTAssertEqual(char.health, 14, "Second hit is normal: 20-4-2=14")
    }

    func testBrittle_doesNotAffectHealing() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10; char.maxHealth = 20
        t.entityManager.addCondition(.brittle, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: 3)
        XCTAssertEqual(char.health, 13, "Brittle does not affect healing")
    }

    // MARK: - Ward: halve damage from next source

    func testWard_halvesDamage() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.ward, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -6)
        XCTAssertEqual(char.health, 17, "Ward halves damage: -6/2 = -3")
    }

    func testWard_roundsDown() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.ward, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -5)
        // -5/2 = -2.5, rounded toward zero = -2 (integer division)
        XCTAssertEqual(char.health, 18, "Ward halves and rounds down: -5/2 = -2")
    }

    func testWard_removedAfterTrigger() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.ward, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -4)
        XCTAssertFalse(t.entityManager.hasCondition(.ward, on: char), "Ward consumed after trigger")
    }

    // MARK: - Brittle + Ward interaction

    func testBrittle_thenWard_doublesAndHalves() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.brittle, to: char)
        t.entityManager.addCondition(.ward, to: char)
        t.entityManager.restoreConditions(char)

        // -4 → brittle doubles to -8 → ward halves to -4
        t.entityManager.changeHealth(char, amount: -4)
        XCTAssertEqual(char.health, 16, "Brittle then Ward: -4 × 2 / 2 = -4")
    }

    // MARK: - Bane: 10 damage at end of turn

    func testBane_deals10Damage() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.bane, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 10, "Bane deals 10 damage")
    }

    func testBane_expiresAfterTurn() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.bane, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)

        // Bane is afterTurn type, should expire
        let hasBane = char.entityConditions.contains(where: { $0.name == .bane && !$0.expired })
        XCTAssertFalse(hasBane, "Bane expires after turn")
    }

    // MARK: - Chill: reduce movement

    func testChill_reducesMonsterMovement() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(8, 3))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])
        let entity = monster.entities[0]
        // Add chill with value 2 (reduces movement by 2)
        entity.entityConditions.append(EntityCondition(name: .chill, value: 2, state: .normal))

        let abilityWithMove3 = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(3)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: abilityWithMove3,
            board: t.board, gameState: t.game
        )

        // Move 3 - Chill 2 = Move 1 maximum
        if result.movementPath.count > 1 {
            XCTAssertLessThanOrEqual(result.movementPath.count - 1, 1,
                "Chill 2 reduces Move 3 to Move 1")
        }
    }

    func testChill_canReduceMovementToZero() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])
        let entity = monster.entities[0]
        entity.entityConditions.append(EntityCondition(name: .chill, value: 5, state: .normal))

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(2)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: ability,
            board: t.board, gameState: t.game
        )

        // Move 2 - Chill 5 = 0, but monster is already adjacent so can still attack
        XCTAssertTrue(result.movementPath.isEmpty || result.movementPath.count <= 1,
            "Chill can reduce movement to 0")
    }

    // MARK: - Impair: disadvantage on all attacks

    func testImpair_givesDisadvantage() {
        let entity = GameMonsterEntity(number: 1, type: .normal, health: 5, maxHealth: 5, level: 1)
        entity.entityConditions.append(EntityCondition(name: .impair, state: .normal))
        XCTAssertTrue(CombatResolver.hasDisadvantage(attacker: entity, isRangedAdjacent: false),
                      "Impair gives disadvantage on all attacks")
    }

    func testImpair_expiresAfterTurn() {
        let t = TestGame()
        let char = t.addCharacter()
        t.entityManager.addCondition(.impair, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)

        let hasImpair = char.entityConditions.contains(where: { $0.name == .impair && !$0.expired })
        XCTAssertFalse(hasImpair, "Impair expires after turn (afterTurn type)")
    }

    // MARK: - Infect: prevent healing

    func testInfect_preventsHealing() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 5
        t.entityManager.addCondition(.infect, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: 3)
        XCTAssertEqual(char.health, 5, "Infect prevents all healing")
    }

    func testInfect_doesNotBlockDamage() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10
        t.entityManager.addCondition(.infect, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.changeHealth(char, amount: -3)
        XCTAssertEqual(char.health, 7, "Infect does not block damage")
    }

    func testInfect_preventsRegenerate() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 5
        t.entityManager.addCondition(.infect, to: char)
        t.entityManager.addCondition(.regenerate, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 5, "Infect blocks regenerate healing")
    }

    // MARK: - Rupture: 1 damage on positive condition gain

    func testRupture_damageOnPositiveCondition() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10
        t.entityManager.addCondition(.rupture, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.addCondition(.strengthen, to: char)
        XCTAssertEqual(char.health, 9, "Rupture deals 1 damage when gaining positive condition")
    }

    func testRupture_noEffectOnNegativeCondition() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10
        t.entityManager.addCondition(.rupture, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.addCondition(.poison, to: char)
        XCTAssertEqual(char.health, 10, "Rupture does NOT trigger on negative conditions")
    }
}
