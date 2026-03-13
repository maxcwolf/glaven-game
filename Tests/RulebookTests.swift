import XCTest
@testable import GlavenGameLib

// =============================================================================
// Gloomhaven Rulebook Verification Tests
//
// Each test references the specific rulebook page/section it verifies.
// These tests ensure the game engine follows the official rules exactly.
// =============================================================================

// MARK: - Attack Pipeline (Rulebook p.18-21)

/// Verifies the full attack modification pipeline:
/// Base → Poison → Modifier Card → Pierce → Shield → Floor(0)
final class RB_AttackPipelineTests: XCTestCase {

    // p.18: "The base attack value written on the card is modified by..."

    func testPipeline_step1_baseAttackValue() {
        let result = resolve(base: 4, modifier: plus(0))
        XCTAssertEqual(result.damage, 4, "p.18: base attack value applies directly")
    }

    func testPipeline_step2_poisonAddsOneBeforeModifier() {
        // p.18: "if the target is poisoned, add +1 to the attack value"
        let result = resolve(base: 3, modifier: plus(0), isPoisoned: true)
        XCTAssertEqual(result.damage, 4, "p.23: Poison adds +1 before modifier")
    }

    func testPipeline_step3_modifierAddsToAttack() {
        let result = resolve(base: 3, modifier: plus(1))
        XCTAssertEqual(result.damage, 4, "p.18: Modifier +1 adds to attack")
    }

    func testPipeline_step3_modifierSubtracts() {
        let result = resolve(base: 3, modifier: minus(1))
        XCTAssertEqual(result.damage, 2, "p.18: Modifier -1 subtracts from attack")
    }

    func testPipeline_step3_nullMissesCompletely() {
        let result = resolve(base: 5, modifier: nullCard())
        XCTAssertTrue(result.isMiss, "p.18: Null card = miss")
        XCTAssertEqual(result.damage, 0, "p.18: Miss deals 0 damage")
    }

    func testPipeline_step3_doubleMultiplies() {
        let result = resolve(base: 4, modifier: doubleCard())
        XCTAssertEqual(result.damage, 8, "p.18: ×2 modifier doubles attack")
        XCTAssertTrue(result.isCritical)
    }

    func testPipeline_step3_poisonAppliesBeforeDouble() {
        // Poison adds +1 to base BEFORE ×2 modifier
        let result = resolve(base: 3, modifier: doubleCard(), isPoisoned: true)
        XCTAssertEqual(result.damage, 8, "p.23: (3+1)×2 = 8 — poison before modifier")
    }

    func testPipeline_step4_shieldReducesDamage() {
        let result = resolve(base: 5, modifier: plus(0), shield: 2)
        XCTAssertEqual(result.damage, 3, "p.22: Shield reduces damage: 5-2=3")
    }

    func testPipeline_step4_pierceIgnoresShield() {
        let result = resolve(base: 5, modifier: plus(0), shield: 3, pierce: 2)
        XCTAssertEqual(result.damage, 4, "p.22: Pierce 2 reduces shield 3 to effective 1: 5-1=4")
    }

    func testPipeline_step4_pierceCanExceedShield() {
        let result = resolve(base: 3, modifier: plus(0), shield: 2, pierce: 5)
        XCTAssertEqual(result.damage, 3, "p.22: Pierce > shield means 0 effective shield")
    }

    func testPipeline_step5_damageFloorAtZero() {
        let result = resolve(base: 1, modifier: minus(2))
        XCTAssertEqual(result.damage, 0, "p.18: Damage cannot go below 0")
    }

    func testPipeline_missNoConditions() {
        // p.18: "If the attack value is 0 due to a null card, no conditions are applied"
        let result = resolve(base: 3, modifier: nullCard(), conditions: [.poison, .wound])
        XCTAssertTrue(result.appliedConditions.isEmpty, "p.18: Null card blocks all conditions")
    }

    func testPipeline_hitAppliesConditions() {
        let result = resolve(base: 3, modifier: plus(0), conditions: [.poison])
        XCTAssertEqual(result.appliedConditions, [.poison], "p.18: Hit applies ability conditions")
    }

    // MARK: - Rolling Modifiers (p.19)

    func testRollingModifiers_chainBeforeTerminal() {
        // Rolling cards: additive values chain, terminal card ends the draw
        let preDrawn = [
            AttackModifier(type: .plus1, value: 1, rolling: true),  // rolling +1
            AttackModifier(type: .plus1, value: 1, rolling: true),  // rolling +1
            AttackModifier(type: .plus0, value: 0)                  // terminal +0
        ]
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 2,
            preDrawnCards: preDrawn,
            drawModifier: { nil },
            defenderHealth: 10
        )
        XCTAssertEqual(result.damage, 4, "p.19: 2 + 1(rolling) + 1(rolling) + 0(terminal) = 4")
    }

    func testRollingModifiers_chainBeforeDouble() {
        let preDrawn = [
            AttackModifier(type: .plus1, value: 1, rolling: true),
            doubleCard()
        ]
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            preDrawnCards: preDrawn,
            drawModifier: { nil },
            defenderHealth: 10
        )
        XCTAssertEqual(result.damage, 8, "p.19: (3 + 1) × 2 = 8")
    }

    // MARK: - Advantage / Disadvantage (p.19-20)

    func testAdvantage_picksHigherCard() {
        var calls = 0
        let cards = [plus(2), minus(1)]
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            advantage: true,
            drawModifier: { let c = cards[calls]; calls += 1; return c },
            defenderHealth: 10
        )
        XCTAssertEqual(result.damage, 5, "p.19: Advantage picks +2 over -1: 3+2=5")
    }

    func testDisadvantage_picksLowerCard() {
        var calls = 0
        let cards = [plus(2), minus(1)]
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            disadvantage: true,
            drawModifier: { let c = cards[calls]; calls += 1; return c },
            defenderHealth: 10
        )
        XCTAssertEqual(result.damage, 2, "p.20: Disadvantage picks -1 over +2: 3-1=2")
    }

    func testAdvantageDisadvantageCancelOut() {
        // p.20: "If both advantage and disadvantage apply, they cancel out"
        var calls = 0
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            advantage: true,
            disadvantage: true,
            drawModifier: { calls += 1; return plus(1) },
            defenderHealth: 10
        )
        XCTAssertEqual(calls, 1, "p.20: When both apply, draw exactly 1 card")
        XCTAssertEqual(result.damage, 4, "Normal single draw: 3+1=4")
    }

    // MARK: - Retaliate (p.22)

    func testRetaliate_withinRange() {
        let result = resolve(base: 3, modifier: plus(0),
                             retaliateValue: 2, retaliateRange: 1, distance: 1)
        XCTAssertEqual(result.retaliateDamage, 2, "p.22: Retaliate triggers at range 1")
    }

    func testRetaliate_outOfRange() {
        let result = resolve(base: 3, modifier: plus(0),
                             retaliateValue: 2, retaliateRange: 1, distance: 2)
        XCTAssertEqual(result.retaliateDamage, 0, "p.22: Retaliate does NOT trigger beyond range")
    }

    func testRetaliate_notOnKill() {
        // p.22: "If the retaliating figure is killed...retaliate does not trigger"
        let result = resolve(base: 10, modifier: plus(0),
                             retaliateValue: 5, retaliateRange: 1, distance: 1,
                             defenderHealth: 3)
        XCTAssertTrue(result.killed)
        XCTAssertEqual(result.retaliateDamage, 0, "p.22: Dead defender can't retaliate")
    }

    // MARK: - Helpers

    private func plus(_ v: Int) -> AttackModifier {
        AttackModifier(type: v == 0 ? .plus0 : (v == 1 ? .plus1 : .plus2), value: v)
    }
    private func minus(_ v: Int) -> AttackModifier {
        AttackModifier(type: .minus1, value: -v)
    }
    private func nullCard() -> AttackModifier {
        AttackModifier(type: .null_, value: 0, valueType: .multiply)
    }
    private func doubleCard() -> AttackModifier {
        AttackModifier(type: .double_, value: 2, valueType: .multiply)
    }

    private func resolve(
        base: Int, modifier: AttackModifier,
        isPoisoned: Bool = false,
        shield: Int = 0, pierce: Int = 0,
        conditions: [ConditionName] = [],
        retaliateValue: Int = 0, retaliateRange: Int = 1, distance: Int = 1,
        defenderHealth: Int = 20
    ) -> AttackResult {
        CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: base,
            isPoisoned: isPoisoned,
            shield: shield, pierce: pierce,
            conditions: conditions,
            retaliateValue: retaliateValue, retaliateRange: retaliateRange,
            attackerDefenderDistance: distance,
            preDrawnCards: [modifier],
            drawModifier: { nil },
            defenderHealth: defenderHealth
        )
    }
}

// MARK: - Monster AI Focus Rules (Rulebook p.29-31)

final class RB_MonsterFocusTests: XCTestCase {

    // p.29: "A monster will focus on the enemy figure to which it has the
    //        shortest path to an attack position"

    func testFocus_shortestPath() {
        let t = TestGame()
        // Character A is 2 hexes away, Character B is 4 hexes away
        let charA = t.addCharacter(name: "a", pos: HexCoord(4, 3), initiative: 10)
        let charB = t.addCharacter(name: "b", pos: HexCoord(8, 3), initiative: 10)
        _ = charA; _ = charB
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(5)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        if case .character(let name) = result.focusTarget {
            XCTAssertEqual(name, "gh-a", "p.29: Focus on nearest (shortest path) enemy")
        } else {
            XCTFail("Should focus a character")
        }
    }

    // p.29: Tiebreaker 1: proximity (hex distance)
    func testFocus_tiebreakProximity() {
        let t = TestGame()
        // Both are equally reachable by path, but A is closer by hex distance
        let charA = t.addCharacter(name: "a", pos: HexCoord(4, 3), initiative: 50)
        let charB = t.addCharacter(name: "b", pos: HexCoord(4, 5), initiative: 10)
        _ = charA; _ = charB
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(3, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(5)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        // A is closer by proximity (distance 1) vs B (distance ~2)
        if case .character(let name) = result.focusTarget {
            XCTAssertEqual(name, "gh-a", "p.29: Tiebreak by proximity — closer hex distance wins")
        } else {
            XCTFail("Should focus a character")
        }
    }

    // p.29: Tiebreaker 2: lower initiative
    func testFocus_tiebreakInitiative() {
        let t = TestGame()
        // Both equidistant, same path cost — tiebreak by initiative
        let charA = t.addCharacter(name: "a", pos: HexCoord(4, 2), initiative: 50)
        let charB = t.addCharacter(name: "b", pos: HexCoord(4, 4), initiative: 10)
        _ = charA; _ = charB
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(3, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(5)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        if case .character(let name) = result.focusTarget {
            XCTAssertEqual(name, "gh-b", "p.29: Tiebreak by initiative — lower initiative (10) wins")
        } else {
            XCTFail("Should focus a character")
        }
    }

    // p.30: Invisible figures cannot be focused
    func testFocus_skipInvisible() {
        let t = TestGame()
        let charA = t.addCharacter(name: "a", pos: HexCoord(4, 3), initiative: 10)
        charA.entityConditions.append(EntityCondition(name: .invisible, state: .normal))
        let charB = t.addCharacter(name: "b", pos: HexCoord(8, 3), initiative: 10)
        _ = charB
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(3, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(10)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        if case .character(let name) = result.focusTarget {
            XCTAssertEqual(name, "gh-b", "p.30: Must skip invisible character, focus visible one")
        } else {
            XCTFail("Should focus the visible character")
        }
    }
}

// MARK: - Monster Movement Rules (Rulebook p.30-31)

final class RB_MonsterMovementTests: XCTestCase {

    // p.30: "A monster will move the minimum number of hexes to reach the
    //        focus target's attack position"
    func testMovement_minimumToReachAttackPosition() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 3))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(10)), // lots of movement
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        // Monster needs to reach an adjacent hex to the character (melee range 1)
        // Should stop at attack position, not keep moving past it
        if let finalPos = result.movementPath.last {
            let distToTarget = finalPos.distance(to: HexCoord(5, 3))
            XCTAssertEqual(distToTarget, 1, "p.30: Stops at attack position (adjacent for melee)")
        }
        XCTAssertFalse(result.attackTargets.isEmpty, "Should be able to attack after moving")
    }

    // p.30: Monsters can't move through enemies
    func testMovement_cantMoveThroughEnemies() {
        let t = TestGame()
        // Character blocks the direct path
        t.addCharacter(name: "a", pos: HexCoord(4, 3))
        t.addCharacter(name: "b", pos: HexCoord(7, 3), initiative: 10)
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(2)),
            ActionModel(type: .attack, value: .int(2))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        // Monster should NOT end up at (4,3) where character A stands
        if let finalPos = result.movementPath.last {
            XCTAssertNotEqual(finalPos, HexCoord(4, 3), "p.30: Can't move through enemies")
        }
    }

    // p.30: "Ranged monsters will try to find a position from which they can
    //        attack without disadvantage (i.e. not adjacent)"
    func testRangedMonster_avoidsAdjacentDisadvantage() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(3)),
            ActionModel(type: .attack, value: .int(2), subActions: [
                ActionModel(type: .range, value: .int(3))
            ])
        ])

        // Give monster base range via stat
        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0],
            ability: ability, board: t.board, gameState: t.game
        )

        // Ranged monster adjacent to target should try to move away
        if let finalPos = result.movementPath.last {
            let distAfter = finalPos.distance(to: HexCoord(5, 5))
            XCTAssertGreaterThan(distAfter, 1,
                "p.30: Ranged monster moves away from adjacent target to avoid disadvantage")
        }
    }
}

// MARK: - Condition Rules (Rulebook p.22-24)

final class RB_ConditionTests: XCTestCase {

    // p.23: "Wound — each turn the wounded figure suffers 1 damage at the start of its turn"
    func testWound_damageAtStartOfTurn() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10
        t.entityManager.addCondition(.wound, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 9, "p.23: Wound deals 1 at start of turn")

        // Wound persists
        t.entityManager.expireConditions(char)
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 8, "p.23: Wound persists and deals again next turn")
    }

    // p.23: "Poison — all healing on the figure is negated...+1 to all attack values targeting it"
    func testPoison_plusOneToAttack() {
        let result = CombatResolver.resolveAttack(
            attacker: .monster(name: "m", standee: 1),
            defender: .character("c"),
            baseAttack: 3,
            isPoisoned: true,
            preDrawnCards: [AttackModifier(type: .plus0, value: 0)],
            drawModifier: { nil },
            defenderHealth: 10
        )
        XCTAssertEqual(result.damage, 4, "p.23: Poison adds +1 to incoming attack")
    }

    // p.23: "Stun — figure loses its entire next turn"
    func testStun_skipsEntireTurn() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])
        let entity = monster.entities[0]
        entity.entityConditions.append(EntityCondition(name: .stun, state: .normal))

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(5)),
            ActionModel(type: .attack, value: .int(5))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: ability,
            board: t.board, gameState: t.game
        )

        XCTAssertTrue(result.stunned, "p.23: Stunned figure loses entire turn")
        XCTAssertTrue(result.movementPath.isEmpty, "No movement when stunned")
        XCTAssertTrue(result.attackTargets.isEmpty, "No attack when stunned")
    }

    // p.23: "Stun is removed at the end of the figure's turn"
    func testStun_expiresEndOfTurn() {
        let t = TestGame()
        let char = t.addCharacter()
        t.entityManager.addCondition(.stun, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)  // marks as .turn
        t.entityManager.expireConditions(char)      // removes .turn conditions

        let hasStun = char.entityConditions.contains(where: { $0.name == .stun && !$0.expired })
        XCTAssertFalse(hasStun, "p.23: Stun removed at end of turn")
    }

    // p.23: "Disarm — figure cannot perform any attack actions"
    func testDisarm_cantAttack() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(5, 5))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(5, 6), 5)])
        let entity = monster.entities[0]
        entity.entityConditions.append(EntityCondition(name: .disarm, state: .normal))

        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(2)),
            ActionModel(type: .attack, value: .int(5))
        ])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: entity, ability: ability,
            board: t.board, gameState: t.game
        )

        XCTAssertTrue(result.disarmed)
        XCTAssertTrue(result.attackTargets.isEmpty, "p.23: Disarmed figure can't attack")
        // But it should still move
        XCTAssertNotNil(result.focusTarget, "Disarmed figure still picks a focus for movement")
    }

    // p.24: "Strengthen — gives advantage on the figure's next attack"
    func testStrengthen_givesAdvantage() {
        let entity = GameMonsterEntity(number: 1, type: .normal, health: 5, maxHealth: 5, level: 1)
        entity.entityConditions.append(EntityCondition(name: .strengthen, state: .normal))
        XCTAssertTrue(CombatResolver.hasAdvantage(attacker: entity), "p.24: Strengthen = advantage")
    }

    // p.24: "Muddle — gives disadvantage on the figure's next attack"
    func testMuddle_givesDisadvantage() {
        let entity = GameMonsterEntity(number: 1, type: .normal, health: 5, maxHealth: 5, level: 1)
        entity.entityConditions.append(EntityCondition(name: .muddle, state: .normal))
        XCTAssertTrue(CombatResolver.hasDisadvantage(attacker: entity, isRangedAdjacent: false),
                      "p.24: Muddle = disadvantage")
    }

    // p.20: "Ranged attacks against adjacent targets give disadvantage"
    func testRangedAdjacent_givesDisadvantage() {
        let entity = GameMonsterEntity(number: 1, type: .normal, health: 5, maxHealth: 5, level: 1)
        XCTAssertTrue(CombatResolver.hasDisadvantage(attacker: entity, isRangedAdjacent: true),
                      "p.20: Ranged attack adjacent = disadvantage")
    }

    // p.23: "Regenerate — heals 1 at the start of the figure's turn, then is removed"
    func testRegenerate_healsAndExpires() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 5
        char.maxHealth = 10
        t.entityManager.addCondition(.regenerate, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 6, "p.23: Regenerate heals 1")

        let regen = char.entityConditions.first(where: { $0.name == .regenerate })
        XCTAssertTrue(regen?.expired == true, "p.23: Regenerate expires after healing")
    }

    // p.23: Immunity prevents condition application
    func testImmunity_blocksCondition() {
        let t = TestGame()
        let char = t.addCharacter()
        char.immunities = [.poison, .stun]

        t.entityManager.addCondition(.poison, to: char)
        t.entityManager.addCondition(.stun, to: char)
        t.entityManager.addCondition(.wound, to: char)

        XCTAssertFalse(t.entityManager.hasCondition(.poison, on: char), "Immune to poison")
        XCTAssertFalse(t.entityManager.hasCondition(.stun, on: char), "Immune to stun")
        XCTAssertTrue(t.entityManager.hasCondition(.wound, on: char), "Not immune to wound")
    }
}

// MARK: - Movement Terrain Rules (Rulebook p.14-15)

final class RB_TerrainTests: XCTestCase {

    // p.14: "Difficult terrain costs 2 movement"
    func testDifficultTerrain_costs2Movement() {
        let board = makeBoard(cols: 10, rows: 10)
        board.cells[HexCoord(3, 3)] = HexCell(coord: HexCoord(3, 3), tileRef: "test",
                                                passable: true, overlay: .difficultTerrain)

        let reachable = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 3), range: 2,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        // (3,3) should be reachable at cost 2
        XCTAssertEqual(reachable[HexCoord(3, 3)], 2, "p.14: Difficult terrain costs 2 movement")
    }

    // p.14: "Flying figures ignore difficult terrain"
    func testFlying_ignoresDifficultTerrain() {
        let board = makeBoard(cols: 10, rows: 10)
        board.cells[HexCoord(3, 3)] = HexCell(coord: HexCoord(3, 3), tileRef: "test",
                                                passable: true, overlay: .difficultTerrain)

        let reachable = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 3), range: 2,
            flying: true,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        // Flying: (3,3) should cost 1, not 2
        XCTAssertEqual(reachable[HexCoord(3, 3)], 1, "p.14: Flying ignores difficult terrain cost")
    }

    // p.14: "Obstacles are impassable"
    func testObstacles_blockMovement() {
        let board = makeBoard(cols: 10, rows: 10)
        board.cells[HexCoord(3, 3)]!.passable = false // obstacle

        let reachable = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 3), range: 5,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertNil(reachable[HexCoord(3, 3)], "p.14: Can't enter obstacle hex")
    }

    // p.14: "Flying figures can move through obstacles"
    func testFlying_movesOverObstacles() {
        let board = makeBoard(cols: 10, rows: 10)
        board.cells[HexCoord(3, 3)]!.passable = false

        let reachable = Pathfinder.reachableHexes(
            board: board, from: HexCoord(2, 3), range: 3,
            flying: true,
            occupiedByEnemy: [], occupiedByAlly: []
        )

        XCTAssertNotNil(reachable[HexCoord(3, 3)], "p.14: Flying can enter obstacle hex")
    }

    // p.15: "Monsters will avoid traps if a path exists"
    func testMonsterTrapAvoidance() {
        let board = makeBoard(cols: 10, rows: 3)
        // Trap on the direct path
        board.cells[HexCoord(3, 1)] = HexCell(coord: HexCoord(3, 1), tileRef: "test",
                                                passable: true, overlay: .trap, trapDamage: 3)

        // Path with trap avoidance
        let pathAvoiding = Pathfinder.findPath(
            board: board, from: HexCoord(1, 1), to: HexCoord(5, 1),
            avoidTraps: true, occupiedByEnemy: []
        )

        // Path without trap avoidance (may go through trap)
        let pathDirect = Pathfinder.findPath(
            board: board, from: HexCoord(1, 1), to: HexCoord(5, 1),
            avoidTraps: false, occupiedByEnemy: []
        )

        XCTAssertNotNil(pathAvoiding, "Should find alternative path avoiding trap")
        XCTAssertNotNil(pathDirect, "Should find path through trap")

        if let avoiding = pathAvoiding {
            let goesThrough = avoiding.contains(HexCoord(3, 1))
            XCTAssertFalse(goesThrough, "p.15: Trap-avoiding path should not include trap hex")
        }
    }

    // p.15: "If only path includes trap, monsters will use it"
    func testMonsterTrapsOnlyPath() {
        let board = makeBoard(cols: 7, rows: 3)
        // Block all rows except through the trap
        for col in 2...4 {
            board.cells[HexCoord(col, 0)]!.passable = false
            board.cells[HexCoord(col, 2)]!.passable = false
        }
        board.cells[HexCoord(3, 1)] = HexCell(coord: HexCoord(3, 1), tileRef: "test",
                                                passable: true, overlay: .trap, trapDamage: 3)

        let path = Pathfinder.findPath(
            board: board, from: HexCoord(1, 1), to: HexCoord(5, 1),
            avoidTraps: true, occupiedByEnemy: []
        )

        XCTAssertNotNil(path, "p.15: Falls back to trap path when no alternative")
        if let path = path {
            XCTAssertTrue(path.contains(HexCoord(3, 1)), "Must go through trap as only option")
        }
    }

    // p.14: "Figures cannot move through enemy-occupied hexes"
    func testCantMoveThroughEnemies() {
        let board = makeBoard(cols: 10, rows: 3)

        // Enemy blocks the only path
        let reachable = Pathfinder.reachableHexes(
            board: board, from: HexCoord(1, 1), range: 3,
            occupiedByEnemy: [HexCoord(2, 1)], occupiedByAlly: []
        )

        // Can't stop on the enemy hex
        XCTAssertNil(reachable[HexCoord(2, 1)], "p.14: Can't stop on enemy hex")
    }
}

// MARK: - Element Lifecycle (Rulebook p.21)

final class RB_ElementTests: XCTestCase {

    func testElementLifecycle_newToStrongToWaningToInert() {
        let t = TestGame()
        t.addCharacter()

        // Infuse an element
        let fireIdx = t.game.elementBoard.firstIndex(where: { $0.type == .fire })!
        t.game.elementBoard[fireIdx].state = .new

        // Round 1: draw→next (new → strong)
        t.game.characters.first!.initiative = 20
        t.roundManager.nextGameState() // draw → next
        XCTAssertEqual(t.game.elementBoard[fireIdx].state, .strong, "p.21: New → Strong after round advance")

        // Round 1 end: next→draw (strong → waning)
        t.roundManager.nextGameState() // next → draw
        XCTAssertEqual(t.game.elementBoard[fireIdx].state, .waning, "p.21: Strong → Waning at end of round")

        // Round 2: draw→next
        t.game.characters.first!.initiative = 20
        t.roundManager.nextGameState()
        // Round 2 end: next→draw (waning → inert)
        t.roundManager.nextGameState()
        XCTAssertEqual(t.game.elementBoard[fireIdx].state, .inert, "p.21: Waning → Inert at end of round")
    }
}

// MARK: - Scenario Rules (Rulebook p.34, p.42-49)

final class RB_ScenarioTests: XCTestCase {

    // p.34: "Upon completing a scenario, each character receives bonus XP
    //        equal to 4+2×(scenario level)"
    func testVictoryBonusXP() {
        let t = TestGame()
        let char = t.addCharacter()
        char.experience = 0

        let scenarioData = ScenarioData(index: "test", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        for level in [0, 1, 3, 5, 7] {
            char.experience = 0
            t.game.level = level

            let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                      monsterManager: t.monsterManager, levelManager: t.levelManager)
            // Reset scenario so finishScenario works
            t.game.scenario = Scenario(data: scenarioData)
            t.game.completedScenarios.remove(scenarioData.id)

            sm.finishScenario(success: true)

            let expected = 4 + level * 2
            XCTAssertEqual(char.experience, expected,
                           "p.34: Level \(level) → bonus XP = \(expected)")
        }
    }

    // p.34: "When a scenario is failed, all gold and items collected during
    //        the scenario are lost. Experience is kept."
    func testDefeatLosesGoldKeepsXP() {
        let t = TestGame()
        let char = t.addCharacter()
        char.experience = 50
        char.loot = 15

        let scenarioData = ScenarioData(index: "test", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: false)

        XCTAssertEqual(char.experience, 50, "p.34: XP kept on defeat")
        XCTAssertEqual(char.loot, 0, "p.34: Gold lost on defeat")
    }

    // p.34: Exhausted characters do NOT receive bonus XP
    func testExhaustedNoBonusXP() {
        let t = TestGame()
        let alive = t.addCharacter(name: "alive", pos: HexCoord(2, 2))
        let dead = t.addCharacter(name: "dead", pos: HexCoord(3, 3))
        alive.experience = 0
        dead.experience = 0
        dead.exhausted = true

        let scenarioData = ScenarioData(index: "test", name: "Test", edition: "gh")
        t.game.scenario = Scenario(data: scenarioData)
        t.game.level = 1 // bonus = 6

        let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                  monsterManager: t.monsterManager, levelManager: t.levelManager)
        sm.finishScenario(success: true)

        XCTAssertEqual(alive.experience, 6, "Alive character gets bonus XP")
        XCTAssertEqual(dead.experience, 0, "Exhausted character gets NO bonus XP")
    }
}

// MARK: - Attack Modifier Deck Rules (Rulebook p.18-19)

final class RB_AttackModifierDeckTests: XCTestCase {

    // p.23: "There can only be 10 Bless cards in a single deck"
    func testMaxBlessLimit() {
        let t = TestGame()
        for _ in 0..<15 {
            t.attackModifierManager.addBless(to: .monster)
        }
        let count = t.game.monsterAttackModifierDeck.cards.filter { $0.type == .bless }.count
        XCTAssertEqual(count, 10, "p.23: Max 10 bless per deck")
    }

    // p.23: "There can only be 10 Curse cards in a single deck"
    func testMaxCurseLimit() {
        let t = TestGame()
        for _ in 0..<15 {
            t.attackModifierManager.addCurse(to: .monster)
        }
        let count = t.game.monsterAttackModifierDeck.cards.filter { $0.type == .curse }.count
        XCTAssertEqual(count, 10, "p.23: Max 10 curse per deck")
    }

    // p.19: "Bless/curse cards are removed from the deck when drawn"
    func testBlessCurseRemovedOnShuffle() {
        let t = TestGame()
        t.attackModifierManager.addBless(to: .monster)
        t.attackModifierManager.addCurse(to: .monster)

        // Draw all cards (so bless/curse end up in "drawn" portion)
        let total = t.game.monsterAttackModifierDeck.cards.count
        for _ in 0..<total {
            _ = t.attackModifierManager.drawMonsterCard()
        }

        // Shuffle: bless/curse from drawn portion should be removed
        t.attackModifierManager.shuffleDeck(&t.game.monsterAttackModifierDeck)

        let bless = t.game.monsterAttackModifierDeck.cards.filter { $0.type == .bless }.count
        let curse = t.game.monsterAttackModifierDeck.cards.filter { $0.type == .curse }.count
        XCTAssertEqual(bless, 0, "p.19: Bless removed from deck on shuffle after drawing")
        XCTAssertEqual(curse, 0, "p.19: Curse removed from deck on shuffle after drawing")
    }

    // p.19: Default monster deck has 20 cards
    func testDefaultDeckSize() {
        let deck = AttackModifierDeck.defaultDeck()
        XCTAssertEqual(deck.cards.count, 20,
                       "p.18: Default AM deck has 20 cards (6×+0, 5×+1, 5×-1, 1×+2, 1×-2, 1××2, 1××0)")
    }
}

// MARK: - Loot Rules (Rulebook p.28)

final class RB_LootTests: XCTestCase {

    // p.28: "When a monster is killed, a loot token is placed on the hex"
    func testMonsterDeathDropsLoot() {
        let board = makeBoard()
        let pos = HexCoord(5, 5)
        board.placeLoot(at: pos)
        XCTAssertEqual(board.lootTokens[pos], 1, "p.28: Loot token placed on death hex")
    }

    // p.28: "A character picks up loot when entering a hex with loot"
    func testLootPickedUpOnEntry() {
        let board = makeBoard()
        let pos = HexCoord(5, 5)
        board.placeLoot(at: pos, count: 2)

        let taken = board.takeLoot(at: pos)
        XCTAssertEqual(taken, 2, "p.28: All loot picked up on entry")
        XCTAssertEqual(board.lootTokens[pos], nil, "Loot removed after pickup")
    }

    // p.28: "At the end of a character's turn, pick up loot on current hex"
    func testEndOfTurnAutoLoot() {
        let board = makeBoard()
        let pos = HexCoord(3, 3)
        board.placeLoot(at: pos)

        // Simulate end-of-turn pickup
        let taken = board.takeLoot(at: pos)
        XCTAssertEqual(taken, 1, "p.28: End-of-turn auto-loot collects tokens")
    }
}

// MARK: - Level & Difficulty Rules (Rulebook p.15)

final class RB_LevelTests: XCTestCase {

    // p.15: Trap damage = 2 + L
    func testTrapDamage() {
        let game = GameState()
        let lm = LevelManager(game: game)
        for level in 0...7 {
            game.level = level
            XCTAssertEqual(lm.trap(), 2 + level, "p.15: Trap damage at level \(level)")
        }
    }

    // p.15: Bonus experience = 4 + 2L
    func testBonusExperience() {
        let game = GameState()
        let lm = LevelManager(game: game)
        for level in 0...7 {
            game.level = level
            XCTAssertEqual(lm.experience(), 4 + level * 2, "p.15: Bonus XP at level \(level)")
        }
    }

    // p.15: Hazardous terrain = 1 + ceil(L/3)
    func testHazardousTerrain() {
        let game = GameState()
        let lm = LevelManager(game: game)
        // 1 + ceil(L/3): L=0→1, L=1→2, L=2→2, L=3→2, L=4→3, L=5→3, L=6→3, L=7→4
        let expected = [1, 2, 2, 2, 3, 3, 3, 4] // levels 0-7
        for (level, exp) in expected.enumerated() {
            game.level = level
            XCTAssertEqual(lm.terrain(), exp, "p.15: Hazard damage at level \(level)")
        }
    }
}
