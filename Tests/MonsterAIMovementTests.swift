import XCTest
@testable import GlavenGameLib

/// Regression tests for monster movement rules in MonsterAI.computeTurn.
///  - An immobilized monster must not move (it may still attack in range).
///  - Executed movement must respect the movement-point budget when crossing
///    difficult terrain (cost 2), not just a hop count.
final class MonsterAIMovementTests: XCTestCase {

    private func makeAbility(move: Int) -> AbilityModel {
        AbilityModel(cardId: 1, initiative: 50, actions: [
            ActionModel(type: .move, value: .int(move)),
            ActionModel(type: .attack, value: .int(2))
        ])
    }

    // MARK: - #3 Immobilize

    func testImmobilizedMonster_doesNotMove() {
        func movesTaken(immobilized: Bool) -> Int {
            let t = TestGame()
            t.addCharacter(pos: HexCoord(5, 3))
            let monster = t.addSimpleMonster(positions: [(1, HexCoord(2, 3), 5)])
            let entity = monster.entities[0]
            if immobilized {
                entity.entityConditions.append(EntityCondition(name: .immobilize, state: .normal))
            }
            let result = MonsterAI.computeTurn(
                pieceID: .monster(name: "test-monster", standee: 1),
                monster: monster, entity: entity, ability: makeAbility(move: 5),
                board: t.board, gameState: t.game)
            return max(0, result.movementPath.count - 1)
        }

        XCTAssertGreaterThan(movesTaken(immobilized: false), 0,
                             "control: a free monster moves toward its focus")
        XCTAssertEqual(movesTaken(immobilized: true), 0,
                       "an immobilized monster must not move")
    }

    // MARK: - #4 Difficult-terrain movement budget

    func testMonsterMovement_doesNotOvershootDifficultTerrain() {
        let t = TestGame()
        // Carve a single-row corridor along row 3 so the eastward path is forced
        // straight through the difficult-terrain hex (no cost-free detour).
        for c in 0..<12 {
            for r in 0..<12 where r != 3 {
                t.board.cells[HexCoord(c, r)]!.passable = false
            }
        }
        t.board.cells[HexCoord(2, 3)]!.overlay = .difficultTerrain

        t.addCharacter(pos: HexCoord(9, 3))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(1, 3), 5)])

        let result = MonsterAI.computeTurn(
            pieceID: .monster(name: "test-monster", standee: 1),
            monster: monster, entity: monster.entities[0], ability: makeAbility(move: 2),
            board: t.board, gameState: t.game)

        let spent = result.movementPath.dropFirst().reduce(0) {
            $0 + (t.board.cells[$1]!.isDifficultTerrain ? 2 : 1)
        }
        XCTAssertLessThanOrEqual(spent, 2,
            "monster must not spend more than its 2 movement points crossing difficult terrain")
        // It does advance into the difficult hex (cost exactly 2) and stops there —
        // it must not also step onto (3,3) which would cost a third point.
        XCTAssertEqual(result.movementPath.last, HexCoord(2, 3),
                       "monster enters the difficult hex and stops within budget")
    }
}
