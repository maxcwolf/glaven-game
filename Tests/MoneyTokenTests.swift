import XCTest
@testable import GlavenGameLib

/// Who drops a money token on dying (GH p.21, FAQ): a monster that was set up, a boss included;
/// not one that was summoned or spawned, and not an ally of the party.
@MainActor
final class MoneyTokenTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    /// Kill a monster of `name` standing at `hex`; the money tokens left there.
    private func tokensLeft(by name: String, at hex: HexCoord, origin: BoardCoordinator.SpawnOrigin = .placed,
                            ally: Bool = false) throws -> Int {
        let piece = try XCTUnwrap(coord.spawnMonster(name: name, type: .normal, at: hex, origin: origin))
        try XCTUnwrap(gm.game.monsters.first { $0.name == name }).isAlly = ally
        XCTAssertTrue(coord.sufferDamage(999, to: piece), "it dies")
        return coord.boardState.lootTokens[hex] ?? 0
    }

    func testAMonsterSetUpWithTheRoomDropsAMoneyToken() throws {
        XCTAssertEqual(try tokensLeft(by: "bandit-guard", at: HexCoord(3, 3)), 1)
    }

    /// FAQ: "Do allied monsters drop loot? No" (the City Guards of #11, #35 and #36).
    func testAnAlliedMonsterDropsNoMoneyToken() throws {
        XCTAssertEqual(try tokensLeft(by: "city-guard", at: HexCoord(3, 3), ally: true), 0)
    }

    /// No rule sets a boss apart: one set up with its room drops a token like any monster.
    func testABossDropsAMoneyToken() throws {
        XCTAssertEqual(try tokensLeft(by: "bandit-commander", at: HexCoord(3, 3)), 1)
    }

    func testASummonedOrSpawnedMonsterDropsNone() throws {
        XCTAssertEqual(try tokensLeft(by: "living-bones", at: HexCoord(3, 3), origin: .summoned), 0)
        XCTAssertEqual(try tokensLeft(by: "living-corpse", at: HexCoord(6, 6), origin: .spawned), 0)
    }
}
