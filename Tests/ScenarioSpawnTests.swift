import XCTest
@testable import GlavenGameLib

/// Regression tests for room monster-standee spawning.
///
/// Each standee entry in scenario JSON specifies the monster type at *exact* player
/// counts (player2/player3/player4); an absent field means the standee is NOT present
/// at that count. Real data (gh/01.json) relies on this: e.g. `{player2: "elite"}`
/// (a body present only at 2 players) and `{player2: "normal", player4: "normal"}`
/// (a body absent at 3 players). The old cascading `>=` lookup over-spawned these.
/// BoardBuilder.monsterTypeForPlayerCount already uses the correct exact-count switch.
final class ScenarioSpawnTests: XCTestCase {

    func testMonsterType_exactPlayerCount_noCascade() {
        // Present at 2 and 4 players but NOT 3 (gap) — must not spawn at 3.
        let gap = MonsterStandeeData(name: "bandit-guard", marker: nil, tags: nil, type: nil,
                                     player2: "normal", player3: nil, player4: "normal",
                                     health: nil, number: nil)
        XCTAssertEqual(gap.monsterType(forPlayerCount: 2), .normal)
        XCTAssertNil(gap.monsterType(forPlayerCount: 3), "player3 absent => no spawn at 3 players")
        XCTAssertEqual(gap.monsterType(forPlayerCount: 4), .normal)

        // Present ONLY at 2 players — must not spawn at 3 or 4.
        let p2only = MonsterStandeeData(name: "bandit-guard", marker: nil, tags: nil, type: nil,
                                        player2: "elite", player3: nil, player4: nil,
                                        health: nil, number: nil)
        XCTAssertEqual(p2only.monsterType(forPlayerCount: 2), .elite)
        XCTAssertNil(p2only.monsterType(forPlayerCount: 3), "player2-only standee must not spawn at 3 players")
        XCTAssertNil(p2only.monsterType(forPlayerCount: 4), "player2-only standee must not spawn at 4 players")

        // Per-count types are honored exactly.
        let perCount = MonsterStandeeData(name: "bandit-archer", marker: nil, tags: nil, type: nil,
                                          player2: "normal", player3: "elite", player4: "normal",
                                          health: nil, number: nil)
        XCTAssertEqual(perCount.monsterType(forPlayerCount: 2), .normal)
        XCTAssertEqual(perCount.monsterType(forPlayerCount: 3), .elite)
        XCTAssertEqual(perCount.monsterType(forPlayerCount: 4), .normal)

        // Explicit type always spawns regardless of count.
        let always = MonsterStandeeData(name: "boss", marker: nil, tags: nil, type: "boss",
                                        player2: nil, player3: nil, player4: nil,
                                        health: nil, number: nil)
        XCTAssertEqual(always.monsterType(forPlayerCount: 2), .boss)
        XCTAssertEqual(always.monsterType(forPlayerCount: 4), .boss)
    }

    // The player count used for spawning is fixed at scenario setup (number of
    // non-absent characters) and must NOT shrink when a character is exhausted.
    func testOpenRoom_usesScenarioPlayerCount_notActiveCharacterCount() {
        func spawnedCount(exhaustOne: Bool) -> Int {
            let t = TestGame()
            let c1 = t.addCharacter(name: "brute", pos: HexCoord(1, 1))
            t.addCharacter(name: "tinkerer", pos: HexCoord(1, 2))
            t.addCharacter(name: "spellweaver", pos: HexCoord(1, 3))
            if exhaustOne { c1.exhausted = true }

            let scenarioData = ScenarioData(index: "1", name: "Test", edition: "gh")
            t.game.scenario = Scenario(data: scenarioData)
            let sm = ScenarioManager(game: t.game, editionStore: t.editionStore,
                                     monsterManager: t.monsterManager, levelManager: t.levelManager)

            // A room standee present at 3+ players only (player2 absent).
            let roomJSON = #"{"roomNumber": 2, "monster": [{"name":"bandit-guard","player3":"normal","player4":"normal"}]}"#
            let room = try! JSONDecoder().decode(RoomData.self, from: Data(roomJSON.utf8))

            sm.openRoom(room)
            return t.game.monsters.first(where: { $0.name == "bandit-guard" })?.entities.count ?? 0
        }

        XCTAssertEqual(spawnedCount(exhaustOne: false), 1,
                       "3 starting players: the room spawns the player3 standee")
        XCTAssertEqual(spawnedCount(exhaustOne: true), 1,
                       "exhausting a character must not lower the spawn player count (it is fixed at setup)")
    }
}
