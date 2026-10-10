import XCTest
@testable import GlavenGameLib

/// The trap legends written from the scenario book (`placements/gh-traps.json`) against the map
/// data: every Gloomhaven scenario with a trap has its legend, the legend accounts for every
/// trap of the map, and the board gives each trap the effect its legend names.
final class TrapLegendTests: XCTestCase {

    private struct MapTrap {
        let tile: String
        let cell: [Int]
        let art: String?
    }

    /// The traps of a scenario's map data, once per hex of a tile.
    private func mapTraps(_ index: String) throws -> [MapTrap] {
        let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index), "map \(index)")
        var traps: [MapTrap] = []
        var seen = Set<String>()
        for placement in BoardBuilder.findPlacements(in: map.mapTileData) {
            for overlay in placement.tile.overlays where overlay.ref.type == "trap" {
                for cell in overlay.cells where seen.insert("\(placement.tile.ref.lowercased()) \(cell)").inserted {
                    traps.append(MapTrap(tile: placement.tile.ref, cell: cell, art: overlay.ref.subType))
                }
            }
        }
        return traps
    }

    /// The whole map of a scenario on a board, every room revealed. A room with two doors is in
    /// the map data once per door, and only one of the copies carries what is in the room: each
    /// room is entered here through the door that leads to that copy.
    private func wholeBoard(_ index: String) throws -> BoardState {
        let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index), "map \(index)")
        let (board, _) = BoardBuilder.buildStartingRoom(from: map)
        func leadsToTheRoomsContents(_ door: DoorInfo) -> Bool {
            guard let tile = door.childPath.flatMap({ BoardBuilder.tile(at: $0, in: map.mapTileData) }) else { return true }
            return !tile.overlays.isEmpty || !tile.monsters.isEmpty || !tile.doors.isEmpty
        }
        var progress = true
        while progress {
            progress = false
            let closed = board.doors.filter { !$0.isOpen }
            for door in closed.filter(leadsToTheRoomsContents) + (closed.contains(where: leadsToTheRoomsContents) ? [] : closed) {
                guard board.doors.contains(where: { $0.coord == door.coord && !$0.isOpen }) else { continue }
                if BoardBuilder.revealRoomSlots(door: door, scenario: map, board: board) != nil { progress = true }
            }
        }
        return board
    }

    func testTheLegendsLoad() {
        let written = ScenarioTrapStore.shared.all()
        XCTAssertEqual(written.count, 75, "one legend for each of the 75 scenarios whose map has traps")
        XCTAssertEqual(written["2"]?.kinds, [.init(damage: false, conditions: [.stun], count: 2, art: "bear")])
        XCTAssertEqual(written["31"]?.kinds.first?.effect, TrapEffect(damage: true, conditions: [.curse]))
        XCTAssertNil(ScenarioTrapStore.shared.traps(for: "solo-2"), "a solo scenario isn't the scenario with its number")
    }

    /// Nothing is guessed: every Gloomhaven scenario (1–95) whose map has a trap has a legend,
    /// every trap of the map is one of the legend's kinds, and each kind counts as many traps as
    /// the legend says the map sets up. A scenario without traps has no legend.
    func testEveryScenarioWithATrapHasALegendThatCountsItsTraps() throws {
        let written = ScenarioTrapStore.shared.all()
        var withTraps = 0
        for number in 1...95 {
            let index = String(number)
            guard ScenarioMapStore.shared.hasMap(for: index) else {
                XCTAssertNil(written[index], "scenario \(index) has no map, so no legend")
                continue
            }
            let traps = try mapTraps(index)
            guard !traps.isEmpty else {
                XCTAssertNil(written[index], "scenario \(index) has no trap on its map")
                continue
            }
            withTraps += 1
            guard let legend = written[index] else {
                XCTFail("scenario \(index) has \(traps.count) traps and no legend in gh-traps.json")
                continue
            }
            XCTAssertNotNil(legend.page, "scenario \(index): the page its legend is on")
            var counts = [Int](repeating: 0, count: legend.kinds.count)
            for trap in traps {
                guard let kind = legend.kind(tile: trap.tile, cell: trap.cell, art: trap.art),
                      let position = legend.kinds.firstIndex(of: kind) else {
                    XCTFail("scenario \(index): the \(trap.art ?? "?") trap on \(trap.tile) \(trap.cell) is no kind of its legend")
                    continue
                }
                counts[position] += 1
            }
            for (kind, count) in zip(legend.kinds, counts) {
                XCTAssertEqual(count, kind.count, "scenario \(index): \(kind.effect.legendName) traps on the map")
                XCTAssertGreaterThanOrEqual(kind.legend ?? kind.count, kind.count, "scenario \(index): the legend counts no fewer")
                XCTAssertTrue(kind.damage || !kind.conditions.isEmpty, "scenario \(index): a trap does something")
                XCTAssertEqual(Set(kind.conditions).count, kind.conditions.count, "scenario \(index): each condition once")
                XCTAssertTrue(kind.conditions.allSatisfy { [.stun, .poison, .wound, .immobilize, .muddle, .disarm, .curse].contains($0) },
                              "scenario \(index): \(kind.conditions) are conditions a trap gives")
            }
            XCTAssertEqual(Set(legend.kinds.map(\.effect.legendName)).count, legend.kinds.count, "scenario \(index): kinds differ")
        }
        XCTAssertEqual(withTraps, written.count, "no legend for a scenario without traps")
    }

    /// Built from the map, every trap on the board carries its legend's effect — none is left
    /// to the guess from its art.
    func testTheBoardGivesEveryTrapItsLegendEffect() throws {
        for (index, legend) in ScenarioTrapStore.shared.all().sorted(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }) {
            let board = try wholeBoard(index)
            let traps = board.cells.values.filter(\.isTrap)
            XCTAssertEqual(traps.count, legend.kinds.map(\.count).reduce(0, +), "scenario \(index): traps on the board")
            XCTAssertTrue(traps.allSatisfy { $0.trapEffect != nil }, "scenario \(index): no trap is guessed from its art")
            XCTAssertTrue(traps.allSatisfy { $0.trapDamage == nil }, "scenario \(index): damage is 2 + L, worked out when it springs")
            for kind in legend.kinds {
                XCTAssertEqual(traps.filter { $0.trapEffect == kind.effect }.count, kind.count,
                               "scenario \(index): \(kind.effect.legendName) traps on the board")
            }
        }
    }

    /// The art doesn't decide: the same bear-trap art is a Stun trap without damage in Barrow
    /// Lair, a plain damage trap in Clockwork Cove, Immobilize and Poison in Tribal Assault and
    /// Poison and Damage in the Shrine of Strength.
    func testTheSameArtIsADifferentTrapInEachScenario() throws {
        func effects(_ index: String, art: String) throws -> Set<String> {
            Set(try wholeBoard(index).cells.values.filter { $0.isTrap && $0.overlaySubType == art }.map(\.resolvedTrapEffect.legendName))
        }
        XCTAssertEqual(try effects("2", art: "bear"), ["Stun"])
        XCTAssertEqual(try effects("66", art: "bear"), ["Damage"])
        XCTAssertEqual(try effects("44", art: "bear"), ["Immobilize and Poison"])
        XCTAssertEqual(try effects("15", art: "bear"), ["Poison and Damage"])
        XCTAssertEqual(try effects("15", art: "spike"), ["Wound and Damage"])
        XCTAssertEqual(try effects("31", art: "spike"), ["Curse and Damage"])
        XCTAssertEqual(try effects("1", art: "spike"), ["Damage"])
        XCTAssertEqual(try effects("7", art: "poison"), ["Poison and Stun"])
        XCTAssertEqual(try effects("19", art: "poison"), ["Damage"])
        XCTAssertEqual(try effects("89", art: "poison"), ["Poison"])
    }

    /// Two kinds in one scenario are told apart by art or, where the art is the same, by hex.
    func testAKindIsFoundByHexThenByArtThenAsTheRest() {
        let byHex = ScenarioTraps.Kind(damage: false, conditions: [.stun], count: 1, tiles: ["a1a": [[2, 3]]])
        let byArt = ScenarioTraps.Kind(damage: true, conditions: [.poison], count: 2, art: "poison")
        let rest = ScenarioTraps.Kind(damage: true, conditions: [], count: 3)
        let legend = ScenarioTraps(page: nil, kinds: [rest, byArt, byHex])
        XCTAssertEqual(legend.kind(tile: "A1a", cell: [2, 3], art: "poison"), byHex)
        XCTAssertEqual(legend.kind(tile: "a1a", cell: [2, 4], art: "poison"), byArt)
        XCTAssertEqual(legend.kind(tile: "b1a", cell: [2, 3], art: "spike"), rest)
        XCTAssertNil(ScenarioTraps(page: nil, kinds: [byArt]).kind(tile: "a1a", cell: [0, 0], art: "bear"),
                     "a trap no kind claims has no legend effect")
    }

    /// A saved board keeps what each trap does; a board saved before legends were read has traps
    /// without an effect, and those fall back on the guess from their art.
    func testATrapsEffectIsSavedAndAnOldSaveStillLoads() throws {
        var cell = HexCell(coord: HexCoord(1, 1), tileRef: "b3b", passable: true, overlay: .trap, overlaySubType: "bear")
        cell.trapEffect = TrapEffect(damage: false, conditions: [.stun])
        let saved = try JSONEncoder().encode(cell)
        XCTAssertEqual(try JSONDecoder().decode(HexCell.self, from: saved), cell)

        // As saved before: no word about the effect.
        let old = try JSONEncoder().encode(HexCell(coord: HexCoord(1, 1), tileRef: "b3b", passable: true,
                                                   overlay: .trap, overlaySubType: "bear"))
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("trapEffect"))
        let loaded = try JSONDecoder().decode(HexCell.self, from: old)
        XCTAssertNil(loaded.trapEffect)
        XCTAssertEqual(loaded.resolvedTrapEffect, TrapEffect(damage: true, conditions: [.immobilize]))
        XCTAssertEqual(TrapEffect.guess(fromArt: "poison"), TrapEffect(damage: true, conditions: [.poison]))
        XCTAssertEqual(TrapEffect.guess(fromArt: "spike"), .damageOnly)
    }
}
