import XCTest
@testable import GlavenGameLib

/// Regression tests for the entity condition lifecycle state machine.
///
/// These cover bugs surfaced by the bug-hunt deep dive:
///  - afterTurn conditions (immobilize/disarm/muddle/impair/strengthen/dodge/
///    invisible/safeguard) were being resurrected every turn by restoreConditions
///    because expireConditions only ever physically removed `.removed` conditions
///    while leaving afterTurn ones in a self-healing `.expire`/`expired` state.
///  - Bane was dealing its 10 damage at the START of the next turn instead of the END.
///  - Regenerate must remain a *persistent* heal (FH rules: heals 1 at the start of
///    each turn until the figure suffers damage) — it is NOT a one-shot.
///  - invisible must be classified as a positive condition.
final class ConditionLifecycleTests: XCTestCase {

    // MARK: - afterTurn conditions must clear after the figure's next turn (no resurrection)

    func testImmobilize_removedAtEndOfNextTurn_doesNotResurrect() {
        let t = TestGame()
        let char = t.addCharacter()
        t.entityManager.addCondition(.immobilize, to: char)

        // The figure's next turn: active during the turn ...
        t.entityManager.restoreConditions(char)   // .new -> .normal
        t.entityManager.applyConditionsTurn(char)
        XCTAssertTrue(t.entityManager.hasCondition(.immobilize, on: char),
                      "Immobilize is active during the figure's next turn")

        // ... then removed at the END of that turn.
        t.entityManager.expireConditions(char)
        XCTAssertFalse(t.entityManager.hasCondition(.immobilize, on: char),
                       "Immobilize is removed at the end of the figure's next turn")

        // A later turn must NOT bring it back to life.
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        XCTAssertFalse(t.entityManager.hasCondition(.immobilize, on: char),
                       "Immobilize must not resurrect on a subsequent turn")
    }

    func testAfterTurnConditions_doNotResurrectOnSecondTurn() {
        let afterTurn: [ConditionName] = [.muddle, .disarm, .strengthen, .impair, .dodge, .safeguard, .invisible]
        for cond in afterTurn {
            let t = TestGame()
            let char = t.addCharacter()
            t.entityManager.addCondition(cond, to: char)

            t.entityManager.restoreConditions(char)
            t.entityManager.applyConditionsTurn(char)
            t.entityManager.expireConditions(char)
            // Start of the following turn — the condition must already be gone.
            t.entityManager.restoreConditions(char)

            XCTAssertFalse(t.entityManager.hasCondition(cond, on: char),
                           "\(cond) must clear after the figure's next turn and not resurrect")
        }
    }

    func testStun_stillClearsAtEndOfTurn() {
        // Regression guard: the .turn-type path (stun) must keep working.
        let t = TestGame()
        let char = t.addCharacter()
        t.entityManager.addCondition(.stun, to: char)
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)
        XCTAssertFalse(t.entityManager.hasCondition(.stun, on: char), "Stun clears at end of turn")
    }

    // MARK: - Bane: 10 damage at the END of the figure's next turn

    func testBane_dealsDamageAtEndOfTurn_notStart() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.bane, to: char)
        t.entityManager.restoreConditions(char)

        // Start of the figure's next turn: no damage yet (figure acts first).
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 20, "Bane deals no damage at the start of the turn")

        // End of the figure's next turn: 10 damage, then bane is removed.
        t.entityManager.expireConditions(char)
        XCTAssertEqual(char.health, 10, "Bane deals 10 damage at the end of the figure's next turn")
        XCTAssertFalse(t.entityManager.hasCondition(.bane, on: char), "Bane is removed after it triggers")
    }

    func testBane_triggersOnlyOnce() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 20; char.maxHealth = 20
        t.entityManager.addCondition(.bane, to: char)

        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)   // -10 -> 10, removed
        // A second full turn must not deal bane damage again.
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        t.entityManager.expireConditions(char)
        XCTAssertEqual(char.health, 10, "Bane triggers exactly once")
    }

    // MARK: - Regenerate: persistent per-turn heal (FH rules), NOT one-shot

    func testRegenerate_healsEveryTurn_andPersists() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 5; char.maxHealth = 20
        t.entityManager.addCondition(.regenerate, to: char)

        // Turn 1
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 6, "Regenerate heals 1 at the start of turn 1")
        t.entityManager.expireConditions(char)

        // Turn 2 — regenerate persists and heals again (Frosthaven rules).
        t.entityManager.restoreConditions(char)
        t.entityManager.applyConditionsTurn(char)
        XCTAssertEqual(char.health, 7, "Regenerate is persistent: it heals again on turn 2")
        XCTAssertTrue(t.entityManager.hasCondition(.regenerate, on: char),
                      "Regenerate persists across turns")
    }

    // MARK: - invisible is a positive condition

    func testInvisible_isPositive_consistentWithConditionTypes() {
        XCTAssertTrue(ConditionName.invisible.isPositive, "invisible is a positive condition")
        XCTAssertFalse(ConditionName.invisible.isNegative, "invisible is not a negative condition")
        XCTAssertTrue(Condition.conditionTypes(for: .invisible).contains(.positive),
                      "conditionTypes already classifies invisible as .positive")
    }

    func testRupture_triggersOnGainingInvisible() {
        let t = TestGame()
        let char = t.addCharacter()
        char.health = 10; char.maxHealth = 10
        t.entityManager.addCondition(.rupture, to: char)
        t.entityManager.restoreConditions(char)

        t.entityManager.addCondition(.invisible, to: char)
        XCTAssertEqual(char.health, 9,
                       "Rupture deals 1 damage when gaining invisible (a positive condition)")
    }
}
