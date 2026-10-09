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
