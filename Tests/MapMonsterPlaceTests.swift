import XCTest
@testable import GlavenGameLib

/// Who stands in a room comes from the scenario data, where from the map data (`MonsterSlot`).
/// The two are separate sources, so they are held against each other here: a monster with no
/// place of its own is put on a fallback hex, which is not where the scenario book prints it.
@MainActor
final class MapMonsterPlaceTests: XCTestCase {

    /// Rooms the comparison can't judge, "scenario:tile" (the first tile of the room, lowercased).
    /// #35: the four City Archers of the first room stand on the battlements (a) and (b), hexes
    /// of the I and B tiles behind the gate, which the game lays out from the start without
    /// revealing their room (`laidOut`). This room-by-room walk doesn't know of that;
    /// `BattlementsTests` holds the two sources together for it.
    private static let unresolved: Set<String> = ["35:l3a", "35:i1b"]

    /// One room as the game reveals it: the tiles laid out together and the map's places on them.
    private struct Room {
        var refs: [String]
        var slots: [MonsterSlot]
    }

    /// Every room of a map in the order its doors open, the starting room first.
    private func rooms(of map: VGBScenario, initialRoomRefs: [String]) -> [Room] {
        let (board, start) = BoardBuilder.buildStartingRoom(from: map, initialRoomRefs: initialRoomRefs)
        var rooms = [Room(refs: start.tileRefs.map { $0.lowercased() }, slots: start.slots)]
        var guardCount = 0
        while let door = board.doors.filter({ !$0.isOpen }).sorted(by: { $0.coord < $1.coord }).first, guardCount < 200 {
            if let reveal = BoardBuilder.revealRoomSlots(door: door, scenario: map, board: board) {
                rooms.append(Room(refs: reveal.tileRefs.map { $0.lowercased() }, slots: reveal.slots))
            }
            if let stuck = board.doors.firstIndex(where: { $0.coord == door.coord && !$0.isOpen }) { board.doors[stuck].isOpen = true }
            guardCount += 1
        }
        return rooms
    }

    /// The differences between the two sources, a line each: "scenario:tile 3p: …".
    private func differences() throws -> [String] {
        let gm = try SaveAndContinueTestsSupport.manager()
        var lines: [String] = []
        var compared = 0
        for number in 1...95 {
            let index = String(number)
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil }, index)
            // (#55 has no map of its own.)
            guard let map = ScenarioMapStore.shared.scenarioMap(for: index) else { continue }
            let dataRooms = data.rooms ?? []
            // Monsters of a room that have no place on its map by design: one that comes and
            // goes (#48's Dark Rider), and one held back that a written rule then sets up on a
            // lettered hex (#36's Prime Demon).
            let written = ScenarioPlacementStore.shared.placements(for: index)
            let setUpByRule = Set((written?.rules ?? []).flatMap { $0.spawns ?? [] }.filter { $0.placed == true }.map(\.monster.name))
            let elsewhere = Set((written?.cycles ?? [:]).filter { $0.value.appears == true }.keys)
                .union(Set(written?.later ?? []).intersection(setUpByRule))
            var opened = Set<Int>()
            for (order, room) in rooms(of: map, initialRoomRefs: dataRooms.filter(\.isInitial).compactMap(\.ref)).enumerated() {
                // As the coordinator does: the starting room is every room marked initial and
                // every room whose tile is on the map from the start; a door brings the rooms
                // of the tiles revealed with it.
                let here = dataRooms.filter { data in
                    !opened.contains(data.roomNumber)
                        && ((order == 0 && data.isInitial) || room.refs.contains((data.ref ?? "").lowercased()))
                }
                opened.formUnion(here.map(\.roomNumber))
                let key = "\(index):\(room.refs.first ?? "?")"
                guard !Self.unresolved.contains(key) else { continue }
                for count in 2...4 {
                    let wanted = here.flatMap { $0.monster ?? [] }.compactMap { standee -> String? in
                        guard !elsewhere.contains(standee.name), let type = standee.monsterType(forPlayerCount: count) else { return nil }
                        return "\(MonsterNameSpec(standee.name).name) \(type.rawValue)"
                    }.sorted()
                    var places = room.slots.compactMap { slot -> String? in
                        let type = slot.type(forPlayerCount: count)
                        return type == "none" ? nil : "\(slot.name) \(type)"
                    }
                    // The map data knows no bosses: one stands on a place under its own name, or
                    // on a stand-in's — a place of a monster the room doesn't have (as
                    // `placeRevealedMonsters` gives them out).
                    let names = Set(wanted.map { String($0.split(separator: " ")[0]) })
                    for boss in wanted where boss.hasSuffix(" boss") {
                        let name = String(boss.dropLast(" boss".count))
                        if let own = places.firstIndex(where: { $0.hasPrefix(name + " ") && $0 != boss })
                            ?? places.firstIndex(where: { !names.contains(String($0.split(separator: " ")[0])) }) {
                            places[own] = boss
                        }
                    }
                    places.sort()
                    compared += 1
                    guard wanted != places else { continue }
                    var missing = wanted
                    var unused: [String] = []
                    for place in places {
                        if let at = missing.firstIndex(of: place) { missing.remove(at: at) } else { unused.append(place) }
                    }
                    lines.append("\(key) \(count)p: no place for \(missing), unused places \(unused)")
                }
            }
            // (A room with no tile is a list of monsters a rule brings: #62's and #82's boss.)
            XCTAssertEqual(opened.count, dataRooms.filter { $0.ref != nil }.count, "scenario \(index): every room of the data is on the map")
        }
        XCTAssertGreaterThan(compared, 800, "rooms were compared")
        return lines
    }

    /// For every room and every party size, the map has exactly one place of the right rank for
    /// each monster the scenario data sets up there, and no place left over.
    func testEveryMonsterOfARoomHasItsOwnPlaceOnTheMap() throws {
        let lines = try differences()
        XCTAssertEqual(lines, [], "\n" + lines.joined(separator: "\n"))
    }

    /// A hex holds one figure: no tile has two monster places on one hex.
    func testNoTwoMonsterPlacesShareAHex() {
        for number in 1...95 {
            guard let map = ScenarioMapStore.shared.scenarioMap(for: String(number)) else { continue }
            for placement in BoardBuilder.findPlacements(in: map.mapTileData) {
                var seen: [String: String] = [:]
                for monster in placement.tile.monsters {
                    let hex = "\(monster.initialX),\(monster.initialY)"
                    XCTAssertNil(seen[hex], "scenario \(number) \(placement.tile.ref) (\(hex)): \(monster.monster) and \(seen[hex] ?? "")")
                    seen[hex] = monster.monster
                }
            }
        }
    }
}
