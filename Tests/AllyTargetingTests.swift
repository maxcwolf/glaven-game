import XCTest
@testable import GlavenGameLib

/// Regression tests: summons and escorts fight WITH the players, so allied
/// monsters (isAlly/isAllied) must not be treated as their enemies.
/// Both SummonAI and EscortAI gathered every monster on the board as an enemy,
/// causing them to focus and attack their own allied monsters.
final class AllyTargetingTests: XCTestCase {

    func testSummon_doesNotTargetAlliedMonsters() {
        let t = TestGame()
        let char = t.addCharacter(pos: HexCoord(2, 2))
        let summon = GameSummon(name: "Rat", number: 1, health: 3, maxHealth: 3, level: 1,
                                attack: .int(2), movement: 3, range: 0)
        summon.state = .active
        char.summons.append(summon)
        t.board.placePiece(.summon(id: summon.id), at: HexCoord(3, 2))

        // Allied monster adjacent to the summon (would be the "closest enemy" if mis-classified).
        let ally = t.addSimpleMonster(name: "ally-bear", positions: [(1, HexCoord(4, 2), 8)])
        ally.isAlly = true
        // A real enemy further away.
        t.addSimpleMonster(name: "enemy-imp", positions: [(1, HexCoord(8, 2), 5)])

        let result = SummonAI.computeTurn(summon: summon, ownerCharacterID: char.id,
                                          board: t.board, gameState: t.game)

        let allyPiece = PieceID.monster(name: "ally-bear", standee: 1)
        XCTAssertNotEqual(result.focusTarget, allyPiece, "summon must not focus an allied monster")
        XCTAssertNotEqual(result.attackTarget, allyPiece, "summon must not attack an allied monster")
        XCTAssertEqual(result.focusTarget, PieceID.monster(name: "enemy-imp", standee: 1),
                       "summon focuses the real enemy instead")
    }

    func testEscort_doesNotTargetAlliedMonsters() {
        let t = TestGame()
        let escort = GameObjectiveContainer(name: "captive", edition: "gh", escort: true, level: 1)
        escort.escortActions = [
            ActionModel(type: .move, value: .int(3)),
            ActionModel(type: .attack, value: .int(2))
        ]
        let entity = GameObjectiveEntity(number: 1, health: 6, maxHealth: 6)
        escort.entities.append(entity)
        t.board.placePiece(.objective(id: entity.number), at: HexCoord(3, 2))

        let ally = t.addSimpleMonster(name: "ally-bear", positions: [(1, HexCoord(4, 2), 8)])
        ally.isAlly = true
        t.addSimpleMonster(name: "enemy-imp", positions: [(1, HexCoord(8, 2), 5)])

        let result = EscortAI.computeTurn(escort: escort, entity: entity,
                                          board: t.board, gameState: t.game)

        let allyPiece = PieceID.monster(name: "ally-bear", standee: 1)
        XCTAssertNotEqual(result.focusTarget, allyPiece, "escort must not focus an allied monster")
        XCTAssertNotEqual(result.attackTarget, allyPiece, "escort must not attack an allied monster")
        XCTAssertEqual(result.focusTarget, PieceID.monster(name: "enemy-imp", standee: 1),
                       "escort focuses the real enemy instead")
    }
}
