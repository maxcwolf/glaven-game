import XCTest
@testable import GlavenGameLib

/// Rooms as the map data lays them out (GH p.14: when a door opens, the room beyond is set up
/// with its overlay tiles, monsters and money). Whichever door a room is entered by, and in
/// whatever order the doors are opened, the same room appears.
final class MapRevealTests: XCTestCase {

    private struct Layout: Equatable {
        var cells: Set<HexCoord> = []
        var overlays: [HexCoord: String] = [:]
        var slots: Set<String> = []
        var rooms: Set<String> = []
    }

    /// Open every door on the map, choosing the next one with `pick`, and return what stands
    /// where at the end.
    private func revealEverything(_ scenario: VGBScenario, pick: ([DoorInfo]) -> DoorInfo) -> Layout {
        let (board, start) = BoardBuilder.buildStartingRoom(from: scenario)
        var slots = Set(start.slots.map { "\($0.name)@\($0.coord)" })
        var guardCount = 0
        while guardCount < 200 {
            let closed = board.doors.filter { !$0.isOpen }.sorted { $0.coord < $1.coord }
            guard !closed.isEmpty else { break }
            let door = pick(closed)
            if let reveal = BoardBuilder.revealRoomSlots(door: door, scenario: scenario, board: board) {
                slots.formUnion(reveal.slots.map { "\($0.name)@\($0.coord)" })
            } else if let index = board.doors.firstIndex(where: { $0.coord == door.coord }) {
                board.doors[index].isOpen = true
            }
            guardCount += 1
        }
        var layout = Layout(cells: Set(board.cells.keys), slots: slots, rooms: Set(board.visibleRooms.map { $0.lowercased() }))
        for (coord, cell) in board.cells {
            if let overlay = cell.overlay, overlay != .door { layout.overlays[coord] = "\(overlay)" }
        }
        return layout
    }

    private func maps() -> [(index: String, map: VGBScenario)] {
        (1...95).compactMap { number in
            ScenarioMapStore.shared.scenarioMap(for: String(number)).map { (String(number), $0) }
        }
    }

    /// Every tile in the map data, with its overlays and monster places, is on the board once
    /// every door has been opened.
    func testOpeningEveryDoorRevealsEverythingOnTheMap() {
        XCTAssertGreaterThan(maps().count, 80)
        for (index, scenario) in maps() {
            let layout = revealEverything(scenario) { $0[0] }
            let placements = BoardBuilder.findPlacements(in: scenario.mapTileData)
            let named = Set(placements.map { $0.tile.ref.lowercased() })
            XCTAssertEqual(layout.rooms, named, "scenario \(index): every tile is revealed")
            let traps = Set(placements.flatMap { placement in
                placement.tile.overlays.filter { $0.ref.type == "trap" || $0.ref.type == "treasure" }.flatMap { overlay in
                    overlay.cells.map { "\(placement.tile.ref.lowercased()):\(overlay.ref.type):\($0)" }
                }
            })
            let onBoard = layout.overlays.values.filter { $0 == "trap" || $0 == "treasure" }.count
            XCTAssertEqual(onBoard, traps.count, "scenario \(index): every trap and treasure tile of the map is on the board")
            // By hex: a hex holds one figure (`MapMonsterPlaceTests` checks no two places share one).
            let monsters = Set(placements.flatMap { placement in
                placement.tile.monsters.map { "\(placement.tile.ref.lowercased()):\($0.initialX),\($0.initialY)" }
            })
            XCTAssertEqual(layout.slots.count, monsters.count, "scenario \(index): every monster place of the map is found")
        }
    }

    /// With every door open, every hex of the map can still be walked to from the starting
    /// hexes without crossing a wall line: the lines the game draws between tiles never cut a
    /// room off from its door or corridor. (Obstacles aside: by the rules they never seal an
    /// area either, but that is the scenario's layout, not the walls'.)
    func testWallLinesNeverCutOffPartOfAMap() {
        var walled = 0
        for (index, scenario) in maps() {
            let (board, _) = BoardBuilder.buildStartingRoom(from: scenario)
            var guardCount = 0
            while let door = board.doors.filter({ !$0.isOpen }).sorted(by: { $0.coord < $1.coord }).first, guardCount < 200 {
                if BoardBuilder.revealRoomSlots(door: door, scenario: scenario, board: board) == nil,
                   let at = board.doors.firstIndex(where: { $0.coord == door.coord }) {
                    board.doors[at].isOpen = true
                }
                guardCount += 1
            }
            if !board.wallEdges.isEmpty { walled += 1 }
            var seen = Set(board.startingLocations)
            var frontier = Array(seen)
            while let hex = frontier.popLast() {
                // (A crossing joins rooms that lie apart: the altars of Demonic Rift.)
                for neighbor in board.neighbors(of: hex) + board.crossingExits(from: hex) where board.cells[neighbor] != nil && board.cells[neighbor]?.overlay != .wall
                    && !seen.contains(neighbor) {
                    seen.insert(neighbor)
                    frontier.append(neighbor)
                }
            }
            let unreachable = board.cells.filter { $0.value.overlay != .wall && !seen.contains($0.key) }.keys.sorted()
            XCTAssertEqual(unreachable, [], "scenario \(index): hexes no figure could ever reach")
        }
        XCTAssertGreaterThan(walled, 30, "many maps have tiles whose full hexes meet across a wall line")
    }

    /// The order the doors are opened in — so which door each room is entered by — makes no
    /// difference to what is revealed. (A room entered by its second door used to appear empty:
    /// no traps, no treasure, no monsters, in thirteen scenarios.)
    func testARoomIsTheSameWhicheverDoorItIsEnteredBy() {
        for (index, scenario) in maps() {
            let first = revealEverything(scenario) { $0[0] }
            let last = revealEverything(scenario) { $0[$0.count - 1] }
            XCTAssertEqual(first.cells, last.cells, "scenario \(index): the same hexes")
            XCTAssertEqual(first.overlays, last.overlays, "scenario \(index): the same overlays")
            XCTAssertEqual(first.slots, last.slots, "scenario \(index): the same monster places")
            GameRandom.shared = GameRandom(seed: UInt64(index) ?? 1)
            let shuffled = revealEverything(scenario) { $0.randomElement(using: &GameRandom.shared)! }
            XCTAssertEqual(first.overlays, shuffled.overlays, "scenario \(index): the same overlays in a random order")
            XCTAssertEqual(first.slots, shuffled.slots, "scenario \(index): the same monster places in a random order")
        }
    }
}
