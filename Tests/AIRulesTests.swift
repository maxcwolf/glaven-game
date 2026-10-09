import XCTest
import SwiftData
@testable import GlavenGameLib

/// Monster and summon AI rules found in the October 2026 audit (GH p.29–31 and the monster AI
/// FAQ), on the board.
@MainActor
final class AIRulesBoardTests: XCTestCase {

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

    /// A summon stopped short by a bear trap attacks only what it can reach from where it stands,
    /// not from the hex it meant to reach.
    func testASummonStoppedByATrapAttacksFromWhereItStands() async throws {
        // A corridor along row 3.
        for col in 0..<12 { for row in 0..<12 where row != 3 { coord.boardState.cells[HexCoord(col, row)]!.passable = false } }
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(0, 3))
        var data = SummonDataModel(name: "rat", health: .int(5))
        data.attack = .int(2)
        data.movement = .int(3)
        data.range = .int(0)
        gm.characterManager.addSummon(from: data, for: brute)
        let summon = try XCTUnwrap(brute.summons.first)
        summon.state = .active
        coord.boardState.placePiece(.summon(id: summon.id), at: HexCoord(1, 3))
        coord.boardState.placeTrap(at: HexCoord(2, 3), damage: 1, subType: "bear")
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed)
        var attacks = 0
        coord.attackObserver = { _, _ in attacks += 1 }

        await SummonTurnController(coordinator: coord, gameManager: gm).executeSummonTurns(for: brute)
        XCTAssertEqual(coord.boardState.piecePositions[.summon(id: summon.id)], HexCoord(2, 3), "the trap stops it")
        XCTAssertEqual(attacks, 0, "the bandit is out of its reach")
    }
}

/// Monster focus and movement on a plain board (`TestGame`).
final class AIRulesTests: XCTestCase {

    private func card(_ actions: [ActionModel]) -> AbilityModel {
        AbilityModel(cardId: 1, initiative: 50, actions: actions)
    }

    /// The six hexes `steps` away from `center` straight along each axis.
    private func axisHexes(from center: HexCoord, steps: Int) -> [HexCoord] {
        center.neighbors.map { neighbor in
            let (c, n) = (center.cube, neighbor.cube)
            return HexCoord.fromCube(x: c.x + (n.x - c.x) * steps, y: c.y + (n.y - c.y) * steps, z: c.z + (n.z - c.z) * steps)
        }
    }

    /// A melee area reaching 3 hexes in a line attacks an enemy only from where the line can be
    /// turned onto it. The enemy 2 hexes away off every axis is out of the line's reach; the one
    /// 3 hexes away on an axis is in it, so that one is the focus and is attacked from where the
    /// monster stands (Harrower Infester, Deep Terror, Earth and Wind Demons, Savvas).
    func testAMeleeAreaFocusesOnAnEnemyItsPatternCovers() {
        let t = TestGame()
        let monsterHex = HexCoord(5, 5)
        let line = Set((1...3).flatMap { axisHexes(from: monsterHex, steps: $0) })
        let offAxis = t.board.cells.keys.filter { $0.distance(to: monsterHex) == 2 && !line.contains($0) }.sorted()[0]
        let onAxis = axisHexes(from: monsterHex, steps: 3).sorted().first { $0.distance(to: offAxis) > 2 }!
        t.addCharacter(name: "brute", pos: offAxis, initiative: 10)
        t.addCharacter(name: "spellweaver", pos: onAxis, initiative: 20)
        let monster = t.addSimpleMonster(positions: [(1, monsterHex, 5)])
        let ability = card([ActionModel(type: .attack, value: .int(2), subActions: [
            ActionModel(type: .area, value: .string("(1,0,active)|(1,1,target)|(2,2,target)|(2,3,target)"))])])
        let turn = MonsterAI.computeTurn(pieceID: .monster(name: "test-monster", standee: 1), monster: monster,
                                         entity: monster.entities[0], ability: ability, board: t.board, gameState: t.game)
        XCTAssertEqual(turn.focusTarget, .character("gh-spellweaver"))
        XCTAssertEqual(turn.attackTargets, [.character("gh-spellweaver")])
    }

    /// A flying monster may end its move over an obstacle, so an enemy ringed by obstacles is
    /// still a focus it can reach and attack.
    func testAFlyingMonsterAttacksFromOverAnObstacle() throws {
        let t = TestGame()
        let target = HexCoord(6, 6)
        for hex in target.neighbors {
            t.board.cells[hex]!.passable = false
            t.board.cells[hex]!.overlay = .obstacle
        }
        t.addCharacter(pos: target)
        t.editionStore.loadAllEditions()
        let monster = try XCTUnwrap(t.addMonster(name: "sun-demon", positions: [(.normal, HexCoord(2, 2))]))
        XCTAssertEqual(monster.monsterData?.flying, true)
        let ability = card([ActionModel(type: .move, value: .int(8)), ActionModel(type: .attack, value: .int(2))])
        let turn = MonsterAI.computeTurn(pieceID: .monster(name: "sun-demon", standee: monster.entities[0].number),
                                         monster: monster, entity: monster.entities[0], ability: ability,
                                         board: t.board, gameState: t.game)
        XCTAssertNotNil(turn.focusTarget)
        XCTAssertEqual(turn.movementPath.last.map { $0.distance(to: target) }, 1, "it ends beside the enemy")
        XCTAssertFalse(turn.attackTargets.isEmpty)
    }

    /// A monster that can't reach its focus this turn moves as close as it can: when an ally
    /// stands where its route runs out of movement, it takes another hex just as close instead
    /// of stopping short.
    func testAnAllyOnTheRouteDoesNotShortenTheMove() {
        let t = TestGame()
        t.addCharacter(pos: HexCoord(9, 1))
        let monster = t.addSimpleMonster(positions: [(1, HexCoord(1, 9), 5)])
        let ability = card([ActionModel(type: .move, value: .int(2)), ActionModel(type: .attack, value: .int(2))])
        let piece = PieceID.monster(name: "test-monster", standee: 1)
        let first = MonsterAI.computeTurn(pieceID: piece, monster: monster, entity: monster.entities[0], ability: ability,
                                          board: t.board, gameState: t.game)
        XCTAssertEqual(first.movementPath.count - 1, 2)
        let end = first.movementPath.last!
        let closest = end.distance(to: HexCoord(9, 1))

        let ally = GameMonsterEntity(number: 2, type: .normal, health: 5, maxHealth: 5, level: 1)
        monster.entities.append(ally)
        t.board.placePiece(.monster(name: "test-monster", standee: 2), at: end)
        let second = MonsterAI.computeTurn(pieceID: piece, monster: monster, entity: monster.entities[0], ability: ability,
                                           board: t.board, gameState: t.game)
        XCTAssertEqual(second.movementPath.count - 1, 2, "it still moves 2")
        XCTAssertNotEqual(second.movementPath.last, end)
        XCTAssertEqual(second.movementPath.last.map { $0.distance(to: HexCoord(9, 1)) }, closest, "just as close")
    }

    /// Moving toward a far focus stays quick on a big map with difficult terrain: the search for
    /// a hex as close as the route's (when an ally takes the route's end) runs only then, not
    /// whenever terrain leaves a point of movement unspent. (It ran from every reachable hex.)
    func testApproachingAFarFocusStaysQuick() {
        let t = TestGame()
        for col in 0..<30 { for row in 0..<30 where t.board.cells[HexCoord(col, row)] == nil {
            t.board.cells[HexCoord(col, row)] = HexCell(coord: HexCoord(col, row), tileRef: "test", passable: true)
        } }
        for (hex, _) in t.board.cells where hex.col % 2 == 1 { t.board.cells[hex]?.overlay = .difficultTerrain }
        t.addCharacter(pos: HexCoord(28, 28))
        let monster = t.addSimpleMonster(positions: (1...8).map { ($0, HexCoord(1, $0 * 3), 5) })
        let ability = card([ActionModel(type: .move, value: .int(7)), ActionModel(type: .attack, value: .int(2))])
        let start = Date()
        for entity in monster.entities {
            _ = MonsterAI.computeTurn(pieceID: .monster(name: "test-monster", standee: entity.number), monster: monster,
                                      entity: entity, ability: ability, board: t.board, gameState: t.game)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.4, "8 monsters' turns")
    }
}
