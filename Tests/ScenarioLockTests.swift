import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Locked doors (`ScenarioPlacements.Lock`): shut to anyone walking in until their key is turned
/// — a pressure plate, a round, treasure, elite kills — or open only while a plate is held.
@MainActor
final class ScenarioLockTests: XCTestCase {

    private func simulator(_ index: String, characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != character(sim, index) { board.removePiece(other) }
        board.removePiece(character(sim, index))
        board.placePiece(character(sim, index), at: hex)
    }

    /// The doors between two tiles, as the board has them.
    private func doors(_ sim: ScenarioSimulator, _ a: String, _ b: String) -> [DoorInfo] {
        sim.coord.boardState.doors.filter { Set([($0.fromTileRef ?? "").lowercased(), $0.childTileRef.lowercased()]) == [a, b] }
    }

    private func plate(_ sim: ScenarioSimulator, _ letter: String, on tile: String? = nil) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap((board.markerHexes[letter] ?? []).first { tile == nil || board.cells[$0]?.tileRef == tile }, "plate \(letter)")
    }

    private func revealed(_ sim: ScenarioSimulator, _ tile: String) -> Bool {
        sim.coord.boardState.visibleRooms.contains { $0.lowercased() == tile }
    }

    /// A character's way to a hex, as a move would find it.
    private func way(_ sim: ScenarioSimulator, _ index: Int, to hex: HexCoord) -> [HexCoord]? {
        guard let from = sim.coord.boardState.piecePositions[character(sim, index)] else { return nil }
        return Pathfinder.findPath(board: sim.coord.boardState, from: from, to: hex, canOpenDoors: true)
    }

    // MARK: - The written data

    /// Every lock is on a real door of its map, and has at most one key.
    func testEveryLockIsOnADoorOfItsMap() throws {
        var scenarios = 0
        for (index, placements) in ScenarioPlacementStore.shared.all().sorted(by: { $0.key < $1.key }) {
            guard let locks = placements.locks else { continue }
            scenarios += 1
            let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index))
            var joined: Set<Set<String>> = []
            for placement in BoardBuilder.findPlacements(in: map.mapTileData) {
                for door in placement.tile.doors where door.subType != "corridor" {
                    joined.insert([placement.tile.ref.lowercased(), door.mapTileData.ref.lowercased()])
                }
            }
            let letters = Set(placements.tiles.values.flatMap { ($0.markers ?? [:]).keys })
            for lock in locks {
                XCTAssertEqual(lock.between.count, 2, index)
                XCTAssertTrue(joined.contains(Set(lock.between)), "\(index): no door between \(lock.between)")
                XCTAssertFalse((lock.note ?? "").isEmpty, "\(index): \(lock.between) says why it is locked")
                let keys = [lock.plate != nil, lock.allOnPlates != nil, lock.afterRound != nil, lock.looted != nil,
                            lock.eliteKills != nil, lock.held != nil].filter { $0 }.count
                XCTAssertLessThanOrEqual(keys, 1, "\(index): \(lock.between)")
                let plates = (lock.plate ?? []) + (lock.held ?? [])
                    + (lock.allOnPlates.map { $0.markers + ($0.more ?? [:]).values.flatMap { $0 } } ?? [])
                for letter in plates { XCTAssertTrue(letters.contains(letter), "\(index): no plate \(letter)") }
            }
            for letter in placements.plates ?? [] { XCTAssertTrue(letters.contains(letter), "\(index): no plate \(letter)") }
        }
        XCTAssertEqual(scenarios, 13)
    }

    // MARK: - Locked

    /// Shrine of Strength: the side doors don't open to a character walking in — there is no
    /// way through them — while the ordinary door behind the party does.
    func testALockedDoorDoesNotOpenToWalkingIn() async throws {
        let sim = try simulator("15")
        let coord = sim.coord
        for door in doors(sim, "l1a", "d1a") { coord.openDoor(at: door.coord) }
        let side = try XCTUnwrap(doors(sim, "d1a", "h3b").first)
        XCTAssertTrue(coord.boardState.isLockedDoor(side.coord))
        let beside = try XCTUnwrap(side.coord.neighbors.first { coord.boardState.cells[$0]?.tileRef == "d1a" && coord.isEmptyHex($0) })
        stand(sim, 0, on: beside)
        XCTAssertNil(way(sim, 0, to: side.coord), "no path into a locked door")
        _ = await coord.moveAlong(character(sim, 0), path: [beside, side.coord], style: .normal)
        XCTAssertTrue(coord.boardState.isClosedDoor(side.coord), "and being pushed into it opens nothing")
        XCTAssertFalse(revealed(sim, "h3b"))
        XCTAssertFalse(coord.adjacentDoors(from: beside).contains { $0.coord == side.coord })
    }

    /// Asked about, a locked door says what opens it.
    func testALockedDoorSaysWhatOpensIt() throws {
        let sim = try simulator("15")
        for door in doors(sim, "l1a", "d1a") { sim.coord.openDoor(at: door.coord) }
        let side = try XCTUnwrap(doors(sim, "d1a", "h3b").first)
        sim.coord.explainHex(at: side.coord)
        XCTAssertEqual(sim.coord.explanation?.title, "Locked door")
        XCTAssertEqual(sim.coord.explanation?.paragraphs.first,
                       "Locked: it opens when a character ends their turn on the pressure plate (c).")
    }

    // MARK: - Keys

    /// There, a character ending a turn on plate (c) opens both side doors and reveals their rooms.
    func testAPressurePlateOpensItsDoors() throws {
        let sim = try simulator("15")
        let coord = sim.coord
        for door in doors(sim, "l1a", "d1a") { coord.openDoor(at: door.coord) }
        stand(sim, 0, on: try plate(sim, "c"))
        coord.updateLocks()
        XCTAssertFalse(revealed(sim, "h3b"), "standing on it mid-turn isn't enough")
        coord.updateLocks(turnEnded: true)
        XCTAssertTrue(revealed(sim, "h3b"))
        XCTAssertTrue(revealed(sim, "h1b"))
        XCTAssertFalse(revealed(sim, "c1a"), "the treasure room has its own lock")
    }

    /// And the treasure room opens when every character stands on a plate in the side rooms.
    func testEveryoneOnAPlateOpensTheDoor() throws {
        for party in [["brute", "spellweaver"], ["brute", "spellweaver", "cragheart"]] {
            let sim = try simulator("15", characters: party)
            let coord = sim.coord
            for door in doors(sim, "l1a", "d1a") { coord.openDoor(at: door.coord) }
            stand(sim, 0, on: try plate(sim, "c"))
            coord.updateLocks(turnEnded: true)
            let plates = [try plate(sim, "d", on: "h3b"), try plate(sim, "d", on: "h1b")]
                + (party.count > 2 ? [try plate(sim, "e")] : [])
            for index in 0..<(party.count - 1) { stand(sim, index, on: plates[index]) }
            coord.updateLocks(turnEnded: true)
            XCTAssertFalse(revealed(sim, "c1a"), "one of \(party.count) isn't on a plate")
            stand(sim, party.count - 1, on: plates[party.count - 1])
            coord.updateLocks(turnEnded: true)
            XCTAssertTrue(revealed(sim, "c1a"), "\(party.count) characters")
        }
    }

    /// Crypt Basement: the doors open by the round — the first pair as round 2 begins.
    func testDoorsThatOpenByTheRound() throws {
        let sim = try simulator("53")
        let coord = sim.coord
        XCTAssertEqual(coord.boardState.lockedDoors.count, 6, "every door is locked")
        coord.updateLocks()
        XCTAssertFalse(revealed(sim, "j1a"), "round 1 isn't over")
        coord.updateLocks(roundEnded: true)
        XCTAssertTrue(revealed(sim, "j1a"))
        XCTAssertFalse(revealed(sim, "j2a"))
        sim.gm.game.round = 3
        coord.updateLocks(roundEnded: true)
        XCTAssertTrue(revealed(sim, "j2a"))
        XCTAssertFalse(revealed(sim, "d2a"))
        XCTAssertEqual(coord.boardState.lockedDoors.count, 2)
    }

    /// Windswept Highlands: each treasure tile looted opens the next door.
    func testLootedTreasureOpensDoors() throws {
        let sim = try simulator("71")
        let coord = sim.coord
        func chest() throws -> HexCoord {
            try XCTUnwrap(coord.boardState.cells.values.filter { $0.treasureID == BoardCoordinator.goalTreasureID }.map(\.coord).sorted().first)
        }
        XCTAssertFalse(revealed(sim, "a2b"))
        coord.lootHexes(for: character(sim, 0), coords: [try chest()])
        XCTAssertTrue(revealed(sim, "a2b"), "the first treasure opens door b")
        XCTAssertFalse(revealed(sim, "a3a"))
        coord.lootHexes(for: character(sim, 0), coords: [try chest()])
        XCTAssertTrue(revealed(sim, "a3a"))
        XCTAssertFalse(revealed(sim, "g2a"), "the exit waits for the third")
    }

    /// Burning Mountain: each elite killed opens the next door in order; a normal monster's
    /// death opens nothing.
    func testEliteKillsOpenDoorsInOrder() throws {
        let sim = try simulator("82", characters: ["brute", "spellweaver", "cragheart"])
        let coord = sim.coord
        func kill(_ type: MonsterType) throws {
            let piece = try XCTUnwrap(coord.boardState.piecePositions.keys.sorted().first {
                if case .monster(let name, let standee) = $0 { return coord.monsterEntity(name: name, standee: standee)?.type == type }
                return false
            }, "a \(type) monster on the board")
            coord.handleDeath(of: piece)
        }
        XCTAssertEqual(coord.boardState.lockedDoors.count, 2, "both doors out of the first room")
        try kill(.normal)
        XCTAssertFalse(revealed(sim, "c1a"), "a normal monster is no key")
        try kill(.elite)
        XCTAssertTrue(revealed(sim, "c1a"), "door a")
        XCTAssertFalse(revealed(sim, "d1a"))
        try kill(.elite)
        XCTAssertTrue(revealed(sim, "d1a"), "door b")
        XCTAssertFalse(revealed(sim, "i1b"), "door c waits for a third")
    }

    /// Timeworn Tomb: the plate unlocks the last door; a character still has to walk in.
    func testAKeyThatOnlyUnlocks() async throws {
        let sim = try simulator("41")
        let coord = sim.coord
        coord.openDoor(at: try XCTUnwrap(doors(sim, "m1a", "l1a").first).coord)
        let door = try XCTUnwrap(doors(sim, "l1a", "e1a").first)
        XCTAssertTrue(coord.boardState.isLockedDoor(door.coord))
        stand(sim, 0, on: try plate(sim, "b"))
        coord.updateLocks(turnEnded: true)
        XCTAssertFalse(coord.boardState.isLockedDoor(door.coord))
        XCTAssertFalse(revealed(sim, "e1a"), "unlocked, not opened")
        let beside = try XCTUnwrap(door.coord.neighbors.first { coord.boardState.cells[$0]?.tileRef == "l1a" && coord.isEmptyHex($0) })
        stand(sim, 1, on: beside)
        XCTAssertNotNil(way(sim, 1, to: door.coord))
        _ = await coord.moveAlong(character(sim, 1), path: [beside, door.coord], style: .normal)
        XCTAssertTrue(revealed(sim, "e1a"))
    }

    // MARK: - Held doors

    /// Arcane Library: door 2 is open only while a character stands on a plate. Stepping off
    /// shuts it again — the library stays revealed — and whoever is in the doorway is hurt and
    /// put out of it.
    func testADoorHeldOpenByAPlate() async throws {
        let sim = try simulator("67")
        let coord = sim.coord
        coord.openDoor(at: try XCTUnwrap(doors(sim, "l3a", "g1b").first).coord)
        let door = try XCTUnwrap(doors(sim, "a2a", "m1a").first)
        let tunnelPlate = try plate(sim, "a")
        XCTAssertTrue(coord.boardState.isLockedDoor(door.coord))

        // Walking onto the plate opens it.
        let beside = try XCTUnwrap(tunnelPlate.neighbors.first(where: coord.isEmptyHex))
        stand(sim, 0, on: beside)
        _ = await coord.moveAlong(character(sim, 0), path: [beside, tunnelPlate], style: .normal)
        XCTAssertTrue(revealed(sim, "m1a"))
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))

        // The other stands in the doorway as the first steps off.
        stand(sim, 1, on: door.coord)
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        let health = spellweaver.health
        _ = await coord.moveAlong(character(sim, 0), path: [tunnelPlate, beside], style: .normal)
        XCTAssertTrue(coord.boardState.isClosedDoor(door.coord), "shut again")
        XCTAssertTrue(coord.boardState.isLockedDoor(door.coord))
        XCTAssertTrue(revealed(sim, "m1a"), "the room stays revealed")
        XCTAssertEqual(spellweaver.health, health - sim.gm.levelManager.trap(), "caught in the doorway")
        XCTAssertNotEqual(coord.boardState.piecePositions[character(sim, 1)], door.coord)
        XCTAssertNil(way(sim, 0, to: door.coord), "and no way through while it is shut")
        XCTAssertFalse(brute.exhausted)

        // A monster can't come through a shut door either.
        let golem = try XCTUnwrap(coord.boardState.piecePositions.first { if case .monster("stone-golem", _) = $0.key { return true }; return false })
        XCTAssertNil(Pathfinder.findPath(board: coord.boardState, from: golem.value, to: beside, canOpenDoors: false))

        // Back on the plate, it opens.
        _ = await coord.moveAlong(character(sim, 0), path: [beside, tunnelPlate], style: .normal)
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))
    }

    // MARK: - Doors only a rule or a monster opens

    /// Barrow Lair: the side rooms are locked to the party; the Bandit Commander goes through.
    func testOnlyTheCommanderOpensTheSideRooms() throws {
        let sim = try simulator("2")
        let coord = sim.coord
        coord.openDoor(at: try XCTUnwrap(doors(sim, "b3b", "m1a").first).coord)
        XCTAssertEqual(coord.boardState.lockedDoors.count, 4)
        let door = try XCTUnwrap(doors(sim, "m1a", "a1a").first)
        let from = try XCTUnwrap(coord.boardState.piecePositions[character(sim, 0)])
        XCTAssertNil(Pathfinder.findPath(board: coord.boardState, from: from, to: door.coord, canOpenDoors: true))
        XCTAssertNotNil(Pathfinder.findPath(board: coord.boardState, from: from, to: door.coord, canOpenDoors: true,
                                            opensLockedDoors: true), "the Commander's way")
        coord.updateLocks(turnEnded: true, roundEnded: true)
        XCTAssertEqual(coord.boardState.lockedDoors.count, 4, "nothing the party does turns a key")
    }

    /// Lost Temple: the boss room is locked until the rule that every Stone Golem is dead opens
    /// it — the room is a corridor past the door's own tile.
    func testARuleOpensALockedRoom() throws {
        let sim = try simulator("79")
        let coord = sim.coord
        let door = try XCTUnwrap(doors(sim, "d2a", "m1a").first)
        XCTAssertTrue(coord.boardState.isLockedDoor(door.coord))
        coord.openScenarioRooms([2])
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))
        XCTAssertTrue(revealed(sim, "m1a"))
        XCTAssertTrue(coord.boardState.piecePositions.keys.contains { if case .monster("the-betrayer", _) = $0 { return true }; return false },
                      "the Betrayer is in his room")
    }

    // MARK: - On the board, and in a save

    /// Locked doors carry a padlock and pressure plates are drawn; both follow the board.
    func testPadlocksAndPlatesAreDrawn() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "15" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let scene = try XCTUnwrap(coord.boardScene)
        XCTAssertTrue(scene.lockedHexes.isEmpty, "the first door isn't locked")
        while let door = coord.boardState.doors.first(where: { !$0.isOpen && !coord.boardState.isLockedDoor($0.coord) }) {
            coord.openDoor(at: door.coord)
        }
        XCTAssertEqual(scene.lockedHexes, coord.boardState.lockedDoors)
        XCTAssertEqual(scene.lockedHexes.count, 4)
        XCTAssertEqual(scene.plateHexes, Set(coord.boardState.markerHexes["c"] ?? []), "plate (c); the others are behind doors")
        gm.game.round = 1
        let plate = try XCTUnwrap(coord.boardState.markerHexes["c"]?.first)
        coord.boardState.placePiece(.character(gm.game.characters[0].id), at: plate)
        coord.updateLocks(turnEnded: true)
        XCTAssertEqual(scene.lockedHexes.count, 2, "the side doors opened")
        XCTAssertEqual(scene.plateHexes.count, 3, "and their plates are in sight")
        coord.explainHex(at: try XCTUnwrap(coord.boardState.markerHexes["d"]?.first))
        XCTAssertEqual(coord.explanation?.title, "Pressure plate")
    }

    /// A save keeps which locks are open, which doors are shut and the counts that open more.
    func testASaveKeepsTheLocks() throws {
        let sim = try simulator("53")
        let board = sim.coord.boardState
        sim.coord.updateLocks(roundEnded: true)
        board.shutDoors = [HexCoord(1, 1)]
        board.goalTreasuresLooted = 2
        board.eliteKills = 3
        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(board))).restore(to: restored)
        XCTAssertEqual(restored.releasedLocks, [0])
        XCTAssertEqual(restored.lockedDoors, board.lockedDoors)
        XCTAssertEqual(restored.shutDoors, [HexCoord(1, 1)])
        XCTAssertEqual(restored.goalTreasuresLooted, 2)
        XCTAssertEqual(restored.eliteKills, 3)
        XCTAssertEqual(restored.doors.compactMap(\.fromTileRef).count, restored.doors.count, "each door knows both its tiles")
    }
}
