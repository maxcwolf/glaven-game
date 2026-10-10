import XCTest
@testable import GlavenGameLib

/// A monster's Summon ability: how many it brings, and of which rank, by character count.
final class MonsterSummonTests: XCTestCase {

    private func summons(_ json: String, players: Int) throws -> [MonsterType] {
        let action = try JSONDecoder().decode(ActionModel.self, from: Data(json.utf8))
        return try XCTUnwrap(action.monsterSummons).flatMap { $0.summoned(forPlayerCount: players) }
    }

    /// Jekserah's special, as the monster data writes it: two normal Living Bones for two
    /// characters, one normal and one elite for three, two elite for four. (It used to bring
    /// three at every count: the "count" was dropped and every entry was summoned, the ones for
    /// other counts as normals — rules audit 2026-10-09.)
    func testABossSummonsWhatItsPlayerCountSays() throws {
        let jekserah = """
        {"type": "summon", "valueObject": [
          {"monster": {"name": "living-bones", "player3": "normal"}},
          {"monster": {"name": "living-bones", "player3": "elite"}},
          {"monster": {"name": "living-bones", "player2": "normal", "player4": "elite"}, "count": 2}]}
        """
        XCTAssertEqual(try summons(jekserah, players: 2), [.normal, .normal])
        XCTAssertEqual(try summons(jekserah, players: 3), [.normal, .elite])
        XCTAssertEqual(try summons(jekserah, players: 4), [.elite, .elite])
    }

    /// The Betrayer's first special, from the monster data: one elite Giant Viper for two
    /// characters, a normal and an elite for three, two elite for four (scenario book #79; the
    /// data had a normal one for two).
    @MainActor func testTheBetrayerSummonsItsVipers() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let special = try XCTUnwrap(gm.editionStore.monsterData(name: "the-betrayer", edition: "gh")?.stat(for: .boss, at: 1)?.special?.first)
        let summon = try XCTUnwrap(special.first { $0.type == .summon }?.monsterSummons)
        func vipers(_ players: Int) -> [MonsterType] { summon.flatMap { $0.summoned(forPlayerCount: players) }.sorted { $0.rawValue < $1.rawValue } }
        XCTAssertEqual(vipers(2), [.elite])
        XCTAssertEqual(vipers(3), [.elite, .normal])
        XCTAssertEqual(vipers(4), [.elite, .elite])
    }

    /// A plain summon (a Cultist's Living Bones) is one of its type at any count.
    func testAPlainSummonIsOne() throws {
        let cultist = #"{"type": "summon", "valueObject": [{"monster": {"name": "living-bones", "type": "normal"}}]}"#
        for players in 2...4 { XCTAssertEqual(try summons(cultist, players: players), [.normal]) }
    }

    /// The count survives a save.
    func testTheCountIsKept() throws {
        let rider = #"{"type": "summon", "valueObject": [{"monster": {"name": "forest-imp", "player3": "normal", "player4": "normal"}, "count": 2}]}"#
        let action = try JSONDecoder().decode(ActionModel.self, from: Data(rider.utf8))
        let again = try JSONDecoder().decode(ActionModel.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(again.monsterSummons?.first?.count, 2)
        XCTAssertEqual(again.monsterSummons?.first?.summoned(forPlayerCount: 2), [])
        XCTAssertEqual(again.monsterSummons?.first?.summoned(forPlayerCount: 3), [.normal, .normal])
    }

    /// Every boss summon in the monster data brings something at every character count.
    func testEveryBossSummonBringsSomethingAtEveryCount() throws {
        let monsters = ["EditionData/gh/monster", "EditionData/gh/monster/deck"].flatMap {
            appResourceBundle.urls(forResourcesWithExtension: "json", subdirectory: $0) ?? []
        }
        var checked = 0
        for url in monsters {
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            var actions: [[String: Any]] = []
            func walk(_ value: Any) {
                if let dict = value as? [String: Any] {
                    if dict["type"] as? String == "summon", dict["valueObject"] is [Any] { actions.append(dict) }
                    dict.values.forEach(walk)
                } else if let list = value as? [Any] { list.forEach(walk) }
            }
            walk(object)
            for raw in actions {
                guard let action = try? JSONDecoder().decode(ActionModel.self, from: JSONSerialization.data(withJSONObject: raw)),
                      let specs = action.monsterSummons else { continue }
                checked += 1
                for players in 2...4 {
                    XCTAssertFalse(specs.flatMap { $0.summoned(forPlayerCount: players) }.isEmpty,
                                   "\(url.lastPathComponent): nothing summoned for \(players) characters")
                }
            }
        }
        XCTAssertGreaterThan(checked, 15)
    }
}
