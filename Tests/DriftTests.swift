import XCTest
@testable import GlavenGameLib

/// A board that moves the party as the round ends (`ScenarioPlacements.Drift`,
/// `BoardCoordinator+Drift`): the wind of the Windswept Highlands (#71) and the current of the
/// Plane of Water (#88).
@MainActor
final class DriftTests: XCTestCase {

    private func simulator(_ index: String, prompts: Bool = false) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: !prompts))
        sim.gm.game.round = 1
        return sim
    }

    private func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<40 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            sim.coord.boardState.lockedDoors.removeAll()
            sim.coord.openDoor(at: door.coord)
        }
    }

    private func clearMonsters(_ sim: ScenarioSimulator) {
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster = piece { sim.coord.removePieceFromBoard(piece) }
        }
    }

    private func piece(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func hex(_ sim: ScenarioSimulator, _ piece: PieceID) -> HexCoord? { sim.coord.boardState.piecePositions[piece] }

    private func side(_ hex: HexCoord, _ name: String) -> HexCoord {
        hex.neighbors[BoardCoordinator.hexSides.firstIndex(of: name)!]
    }

    /// Plain floor: no overlay, no figure, on one of `tiles` (any tile when nil).
    private func isFloor(_ sim: ScenarioSimulator, _ hex: HexCoord, tiles: [String]? = nil) -> Bool {
        let board = sim.coord.boardState
        guard let cell = board.cells[hex], cell.passable, cell.overlay == nil, board.piece(at: hex) == nil,
              !board.doors.contains(where: { $0.coord == hex }) else { return false }
        return tiles.map { $0.contains(cell.tileRef.lowercased()) } ?? true
    }

    /// A hex of plain floor whose six neighbours are plain floor too, with no wall line between.
    private func openGround(_ sim: ScenarioSimulator, tiles: [String]? = nil, not taken: Set<HexCoord> = []) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { hex in
            !taken.contains(hex) && isFloor(sim, hex, tiles: tiles)
                && hex.neighbors.allSatisfy { isFloor(sim, $0) && !board.isWalled(hex, $0) && !taken.contains($0) }
        }, "no open ground")
    }

    /// A hex of plain floor with two more in a row beyond it on the side named.
    private func openLine(_ sim: ScenarioSimulator, toward name: String, tiles: [String]? = nil) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { hex in
            let next = side(hex, name), last = side(next, name)
            return [hex, next, last].allSatisfy { isFloor(sim, $0, tiles: tiles) } && !board.isWalled(hex, next) && !board.isWalled(next, last)
        }, "no three hexes of floor in a row")
    }

    private func drift(_ sim: ScenarioSimulator, round: Int) async throws {
        sim.gm.game.round = round
        let coming = try XCTUnwrap(sim.coord.driftToCome(), "nothing moves in round \(round)")
        await sim.coord.driftAsTheRoundEnds(coming)
    }

    // MARK: - #71: the wind

    /// "Strong winds will force characters and character summons to move one hex in a different
    /// direction at the end of every round … in the order of left, up, right, down, and then back
    /// to left." The book prints the map a quarter turn round: its left is up on our map, its up
    /// our right, its right our down and its down our left.
    func testTheWindTurnsWithTheRounds() async throws {
        let sim = try simulator("71")
        revealAll(sim)
        clearMonsters(sim)
        let brute = piece(sim, 0), weaver = piece(sim, 1)
        let start = try openGround(sim)
        sim.coord.boardState.removePiece(weaver)
        func blown(round: Int) async throws -> HexCoord? {
            stand(sim, brute, on: start)
            try await drift(sim, round: round)
            return hex(sim, brute)
        }
        // Headless, the first of two hexes in map order is taken.
        let first = try await blown(round: 1)
        XCTAssertEqual(first, [side(start, "NW"), side(start, "NE")].sorted()[0], "round 1: the book's left, up here")
        let second = try await blown(round: 2)
        XCTAssertEqual(second, side(start, "E"), "round 2: the book's up, our right")
        let third = try await blown(round: 3)
        XCTAssertEqual(third, [side(start, "SW"), side(start, "SE")].sorted()[0], "round 3: the book's right, down here")
        let fourth = try await blown(round: 4)
        XCTAssertEqual(fourth, side(start, "W"), "round 4: the book's down, our left")
        let fifth = try await blown(round: 5)
        XCTAssertEqual(fifth, first, "and round again")
    }

    /// "When forced to move left or right, players may choose either of the two available hexes
    /// to move into": asked on the board when both are open, not when only one is.
    func testThePlayersChooseBetweenTwoHexes() async throws {
        let sim = try simulator("71", prompts: true)
        let coord = sim.coord
        revealAll(sim)
        clearMonsters(sim)
        let brute = piece(sim, 0), weaver = piece(sim, 1)
        let start = try openGround(sim)
        coord.boardState.removePiece(weaver)
        stand(sim, brute, on: start)
        sim.gm.game.round = 1
        let coming = try XCTUnwrap(coord.driftToCome())
        let blowing = Task { @MainActor in await coord.driftAsTheRoundEnds(coming) }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingHexChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        guard case .choosingHex(let asked, _, _, let hexes) = coord.interactionMode else {
            blowing.cancel()
            return XCTFail("asked which hex: \(coord.interactionMode)")
        }
        XCTAssertEqual(asked, brute)
        XCTAssertEqual(hexes, [side(start, "NW"), side(start, "NE")])
        XCTAssertNotNil(coord.instruction(for: coord.interactionMode), "the board says what is asked")
        coord.handleHexTap(side(start, "W"))
        XCTAssertNotNil(coord.pendingHexChoice, "a hex that isn't offered is no answer")
        let chosen = [side(start, "NW"), side(start, "NE")].sorted()[1]
        coord.handleHexTap(chosen)
        await blowing.value
        XCTAssertEqual(hex(sim, brute), chosen)
        if case .idle = coord.interactionMode {} else { XCTFail("the prompt is gone: \(coord.interactionMode)") }

        // One of the two shut (FAQ): "the player may choose to either be blocked (not move) or
        // move to the open hex."
        func blownWithOneWayShut(answer: (Set<HexCoord>) -> Void) async throws -> Set<HexCoord> {
            stand(sim, brute, on: start)
            let coming = try XCTUnwrap(coord.driftToCome())
            let blowing = Task { @MainActor in await coord.driftAsTheRoundEnds(coming) }
            let deadline = Date().addingTimeInterval(3)
            while coord.pendingHexChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
            guard case .choosingHex(_, _, _, let offered) = coord.interactionMode else {
                blowing.cancel()
                XCTFail("asked whether to stay: \(coord.interactionMode)")
                return []
            }
            answer(offered)
            // (Whatever was offered, the question is answered: nothing is left waiting.)
            if let pending = coord.pendingHexChoice { coord.resolveHexChoice(pending.options[0]) }
            await blowing.value
            return offered
        }
        coord.boardState.cells[side(start, "NE")]?.overlay = .obstacle
        coord.boardState.cells[side(start, "NE")]?.passable = false
        var offered = try await blownWithOneWayShut { _ in coord.handlePieceTap(brute) }
        XCTAssertEqual(offered, [side(start, "NW"), start], "the open hex, or their own to stay")
        XCTAssertEqual(hex(sim, brute), start, "tapping the figure: it stays")
        offered = try await blownWithOneWayShut { _ in coord.handleHexTap(self.side(start, "NW")) }
        XCTAssertEqual(hex(sim, brute), side(start, "NW"))
        // Another figure in one of the two is in the way just the same.
        coord.boardState.cells[side(start, "NE")]?.overlay = nil
        coord.boardState.cells[side(start, "NE")]?.passable = true
        stand(sim, weaver, on: side(start, "NE"))
        coord.gameManager?.game.characters[1].exhausted = true   // (stands there, but isn't blown about)
        offered = try await blownWithOneWayShut { _ in coord.handleHexTap(self.side(start, "NW")) }
        XCTAssertEqual(offered, [side(start, "NW"), start])
        XCTAssertEqual(hex(sim, brute), side(start, "NW"))
        XCTAssertNil(coord.pendingHexChoice)
    }

    /// "This movement is resolved in initiative order", summons with their owners: whoever goes
    /// first may clear the way for the next, or stand in it. A figure with nowhere to go stays,
    /// unharmed.
    func testTheWindGoesInInitiativeOrderAndIsStoppedByWhatIsInTheWay() async throws {
        let sim = try simulator("71")
        let coord = sim.coord
        revealAll(sim)
        clearMonsters(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let start = try openLine(sim, toward: "E")
        let east = side(start, "E")
        // Round 2 blows to the right. The Brute stands left of the Spellweaver.
        func blow(bruteFirst: Bool) async throws {
            stand(sim, .character(brute.id), on: start)
            stand(sim, .character(weaver.id), on: east)
            brute.initiative = bruteFirst ? 10 : 80
            weaver.initiative = bruteFirst ? 80 : 10
            try await drift(sim, round: 2)
        }
        let health = brute.health
        try await blow(bruteFirst: true)
        XCTAssertEqual(hex(sim, .character(brute.id)), start, "the Spellweaver was still in the way")
        XCTAssertEqual(brute.health, health, "the wind does no harm")
        XCTAssertEqual(hex(sim, .character(weaver.id)), side(east, "E"))
        try await blow(bruteFirst: false)
        XCTAssertEqual(hex(sim, .character(brute.id)), east, "the Spellweaver went first and made room")

        // A summon is blown too, before its owner.
        stand(sim, .character(brute.id), on: start)
        coord.boardState.removePiece(.character(weaver.id))
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: 1, health: 5, maxHealth: 5, level: 1,
                                attack: .int(1), movement: 2, range: 0)
        summon.state = .active
        brute.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: east)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .summon(id: summon.id)), side(east, "E"))
        XCTAssertEqual(hex(sim, .character(brute.id)), east, "its owner follows into the hex it left")

        // An obstacle in the way: no move.
        stand(sim, .character(brute.id), on: start)
        coord.boardState.removePiece(.summon(id: summon.id))
        brute.summons.removeAll()
        coord.boardState.cells[east]?.overlay = .obstacle
        coord.boardState.cells[east]?.passable = false
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), start)
        XCTAssertEqual(brute.health, health)
    }

    /// Forced into a trap, a figure springs it.
    func testTheWindBlowsAFigureIntoATrap() async throws {
        let sim = try simulator("71")
        let coord = sim.coord
        revealAll(sim)
        clearMonsters(sim)
        let brute = sim.gm.game.characters[0]
        let trap = try XCTUnwrap(coord.boardState.cells.values.filter { $0.isTrap }.map(\.coord).sorted().first { trap in
            isFloor(sim, side(trap, "E")) && !coord.boardState.isWalled(trap, side(trap, "E"))
        })
        coord.boardState.removePiece(piece(sim, 1))
        stand(sim, piece(sim, 0), on: side(trap, "E"))
        let health = brute.health
        try await drift(sim, round: 4)   // to the left
        XCTAssertEqual(hex(sim, piece(sim, 0)), trap)
        XCTAssertLessThan(brute.health, health, "the trap is sprung")
        XCTAssertFalse(coord.boardState.cells[trap]?.isTrap ?? true)
    }

    /// A whole round played: the wind comes after the last turn and before the next round's cards.
    func testTheWindBlowsAsARoundOfPlayEnds() async throws {
        let sim = try ScenarioSimulator(scenario: "71", options: .init(characters: ["brute", "spellweaver"], seed: 3))
        _ = await sim.play(rounds: 2)
        let lines = sim.transcript
        let first = try XCTUnwrap(lines.firstIndex { $0.contains("The wind moves the party up") }, "round 1's wind")
        let roundOne = try XCTUnwrap(lines.firstIndex { $0.contains("Round 1 complete") })
        XCTAssertLessThan(first, roundOne)
        XCTAssertTrue(lines[first...roundOne].contains { $0.contains("The wind moves Brute") })
        XCTAssertTrue(lines[roundOne...].contains { $0.contains("The wind moves the party to the right") }, "round 2's")
        XCTAssertTrue(sim.violations.isEmpty, "\(sim.violations)")
    }

    // MARK: - #88: the current

    private func setLurkerInitiative(_ sim: ScenarioSimulator, even: Bool) throws -> Int {
        let lurker = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "lurker" })
        let cards = sim.gm.monsterManager.abilities(for: lurker)
        let index = try XCTUnwrap(cards.firstIndex { ($0.initiative % 2 == 0) == even })
        for monster in sim.gm.game.monsters where monster.name == "lurker" || monster.name == "lurker-king" {
            monster.abilities = Array(cards.indices)
            monster.ability = index
            monster.abilityDrawn = true
        }
        return cards[index].initiative
    }

    private let largeRoom = ["g2a", "n1a"]

    /// "The direction of the current is determined by the Lurker initiative each round, even or
    /// odd": up and to the left on an even card, up and to the right on an odd one — and only
    /// "in the large room".
    func testTheCurrentFollowsTheLurkersInitiative() async throws {
        let sim = try simulator("88")
        let coord = sim.coord
        XCTAssertNil(coord.driftToCome(), "no one is in the large room yet")
        revealAll(sim)
        clearMonsters(sim)
        let brute = piece(sim, 0), weaver = piece(sim, 1)
        let start = try openGround(sim, tiles: largeRoom)
        let outside = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { isFloor(sim, $0, tiles: ["d2b"]) })
        stand(sim, weaver, on: outside)

        stand(sim, brute, on: start)
        XCTAssertEqual(try setLurkerInitiative(sim, even: true) % 2, 0)
        try await drift(sim, round: 3)
        XCTAssertEqual(hex(sim, brute), side(start, "NW"), "even: up and to the left")
        XCTAssertEqual(hex(sim, weaver), outside, "the starting room has no current")

        stand(sim, brute, on: start)
        XCTAssertEqual(try setLurkerInitiative(sim, even: false) % 2, 1)
        try await drift(sim, round: 3)
        XCTAssertEqual(hex(sim, brute), side(start, "NE"), "odd: up and to the right")

        // No Lurker acted this round: a card of theirs is drawn for the current.
        stand(sim, brute, on: start)
        for monster in sim.gm.game.monsters where monster.name == "lurker" || monster.name == "lurker-king" {
            monster.abilityDrawn = false
            monster.ability = -1
        }
        try await drift(sim, round: 3)
        XCTAssertTrue([side(start, "NW"), side(start, "NE")].contains(try XCTUnwrap(hex(sim, brute))))
        let lurker = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "lurker" })
        let drawn = try XCTUnwrap(sim.gm.monsterManager.currentAbilityInitiative(for: lurker))
        XCTAssertEqual(hex(sim, brute), side(start, drawn % 2 == 0 ? "NW" : "NE"))
    }

    /// "…unless they are occupying a hex directly behind an obstacle or wall hex in the direction
    /// of the current. If they cannot move because of another figure, an obstacle, or a wall,
    /// they suffer 3 damage instead."
    func testShelterFromTheCurrentAndWhatItCostsToBeInItsWay() async throws {
        let sim = try simulator("88")
        let coord = sim.coord
        revealAll(sim)
        clearMonsters(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        coord.boardState.removePiece(.character(weaver.id))
        _ = try setLurkerInitiative(sim, even: true)   // up and to the left: it comes from the lower right
        let start = try openGround(sim, tiles: largeRoom)
        let health = brute.health
        func obstacle(_ hex: HexCoord, _ on: Bool) {
            coord.boardState.cells[hex]?.overlay = on ? .obstacle : nil
            coord.boardState.cells[hex]?.passable = !on
        }

        // An obstacle on the side the current comes from: no move, no damage.
        stand(sim, .character(brute.id), on: start)
        obstacle(side(start, "SE"), true)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), start)
        XCTAssertEqual(brute.health, health)
        obstacle(side(start, "SE"), false)

        // The wall of the room behind one: sheltered as well.
        let bottom = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { hex in
            isFloor(sim, hex, tiles: largeRoom) && coord.boardState.cells[side(hex, "SE")] == nil && isFloor(sim, side(hex, "NW"))
        })
        stand(sim, .character(brute.id), on: bottom)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), bottom)
        XCTAssertEqual(brute.health, health)

        // An obstacle in the way: 3 damage instead.
        stand(sim, .character(brute.id), on: start)
        obstacle(side(start, "NW"), true)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), start)
        XCTAssertEqual(brute.health, health - 3)
        obstacle(side(start, "NW"), false)

        // The wall in the way: 3 more.
        let top = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { hex in
            isFloor(sim, hex, tiles: largeRoom) && coord.boardState.cells[side(hex, "NW")] == nil && isFloor(sim, side(hex, "SE"))
        })
        stand(sim, .character(brute.id), on: top)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), top)
        XCTAssertEqual(brute.health, health - 6)
    }

    /// "Current movement is resolved from the top of the map to the bottom": of two figures in
    /// the current's line the upper is moved first, so the lower has room — whatever their
    /// initiative.
    func testTheCurrentIsResolvedFromTheTopOfTheMap() async throws {
        let sim = try simulator("88")
        let coord = sim.coord
        revealAll(sim)
        clearMonsters(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        _ = try setLurkerInitiative(sim, even: true)
        let lower = try openLine(sim, toward: "NW", tiles: largeRoom)
        let upper = side(lower, "NW")
        stand(sim, .character(brute.id), on: lower)
        stand(sim, .character(weaver.id), on: upper)
        brute.initiative = 5
        weaver.initiative = 90
        let health = (brute.health, weaver.health)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(weaver.id)), side(upper, "NW"))
        XCTAssertEqual(hex(sim, .character(brute.id)), upper, "the hex above was free by then")
        XCTAssertEqual(brute.health, health.0)
        XCTAssertEqual(weaver.health, health.1)

        // Another figure in the way that isn't moved (a monster): 3 damage.
        stand(sim, .character(brute.id), on: lower)
        coord.boardState.removePiece(.character(weaver.id))
        let lurker = try XCTUnwrap(coord.spawnMonster(name: "lurker", type: .normal, at: upper, origin: .placed))
        XCTAssertEqual(coord.boardState.piecePositions[lurker], upper)
        _ = try setLurkerInitiative(sim, even: true)
        try await drift(sim, round: 2)
        XCTAssertEqual(hex(sim, .character(brute.id)), lower)
        XCTAssertEqual(brute.health, health.0 - 3)
        XCTAssertEqual(coord.boardState.piecePositions[lurker], upper, "monsters stay")
    }
}

/// Obstacles that roll as the round ends (`ScenarioPlacements.Rolling`, `BoardCoordinator+Rolling`):
/// the boulders of Rockslide Ridge (#73).
@MainActor
final class RollingBoulderTests: XCTestCase {

    private func simulator(prompts: Bool = false) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "73", options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: !prompts))
        sim.gm.game.round = 1
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster = piece { sim.coord.removePieceFromBoard(piece) }
        }
        return sim
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func isBoulder(_ sim: ScenarioSimulator, _ hex: HexCoord) -> Bool {
        let cell = sim.coord.boardState.cells[hex]
        return cell?.overlay == .obstacle && cell?.overlaySubType == "boulder-1" && cell?.passable == false
    }

    /// "The boulders at a and b are rolling down the mountain toward the left side of the map":
    /// three rows, each from (b) across the slope and the tile the party starts on to the map's
    /// left edge, with a boulder at (a) and one at (b).
    func testTheBouldersLieTwoToARowThatRunsToTheLeftEdgeOfTheMap() throws {
        let sim = try simulator()
        let coord = sim.coord
        let rows = coord.rollerRows()
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(coord.rollers().count, 6)
        let a = Set(coord.boardState.markerHexes["a"] ?? []), b = Set(coord.boardState.markerHexes["b"] ?? [])
        XCTAssertEqual(Set(coord.rollers()), a.union(b), "the boulders of the map lie on the lettered hexes")
        for row in rows {
            XCTAssertTrue(b.contains(row[0]))
            XCTAssertEqual(row.filter(coord.rollers().contains).count, 2)
            XCTAssertEqual(row.firstIndex(where: a.contains), 5, "(a) is six hexes along from (b)")
            XCTAssertEqual(Set(row.map(\.row)).count, 1, "one row of the map")
            XCTAssertEqual(coord.boardState.cells[row[row.count - 1]]?.tileRef.lowercased(), "l3a", "to the far edge of the starting tile")
            XCTAssertNil(coord.boardState.cells[row[row.count - 1].neighbor(toward: "W")!])
        }
        XCTAssertEqual(rows.map(\.count), [11, 10, 11])
        XCTAssertTrue(rows.contains { row in coord.boardState.startingLocations.contains { row.contains($0) } }, "the party starts in their path")
        // "These boulders are not affected by any ability."
        XCTAssertFalse(coord.isDestructibleObstacle(rows[0][0]))
    }

    /// "Both boulders in each row will move one, two, or three hexes to the left"; they "destroy
    /// any obstacle in their way, but do not affect traps."
    func testEachRowRollsItsOwnNumberOfHexesOverTrapsAndThroughObstacles() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let rows = coord.rollerRows()
        for hex in coord.boardState.startingLocations { _ = hex }
        for index in 0..<2 { coord.boardState.removePiece(.character(sim.gm.game.characters[index].id)) }
        // What lies between the boulders of the top row: rubble, floor, a trap, rubble.
        let top = rows[0]
        let trap = try XCTUnwrap(top.first { coord.boardState.cells[$0]?.isTrap == true })
        XCTAssertEqual(top.firstIndex(of: trap), 2)
        // An obstacle someone put in the bottom row's way.
        let bottom = rows[2]
        coord.boardState.cells[bottom[7]]?.overlay = .obstacle
        coord.boardState.cells[bottom[7]]?.overlaySubType = "crate"
        coord.boardState.cells[bottom[7]]?.passable = false

        await coord.rollBoulders(by: [2, 1, 3])
        XCTAssertEqual(coord.rollers().sorted(), [top[2], top[7], rows[1][1], rows[1][6], bottom[3], bottom[8]].sorted())
        for hex in coord.rollers() { XCTAssertTrue(isBoulder(sim, hex), "\(hex)") }
        XCTAssertFalse(isBoulder(sim, top[0]))
        XCTAssertTrue(coord.boardState.cells[top[0]]?.passable ?? false, "where a boulder lay is floor again")
        XCTAssertFalse(coord.boardState.cells[trap]?.isTrap ?? true, "the boulder lies on the trap")
        XCTAssertNil(coord.boardState.cells[bottom[7]]?.overlay, "the obstacle in the way is gone")
        XCTAssertTrue(coord.boardState.cells[bottom[7]]?.passable ?? false)

        // Rolling on, the boulder leaves the trap and the rubble as they were.
        let rubble = top[1]
        XCTAssertTrue(coord.boardState.cells[rubble]?.isDifficultTerrain ?? false)
        await coord.rollBoulders(by: [1, 2, 3])
        XCTAssertTrue(coord.boardState.cells[trap]?.isTrap ?? false, "traps are unaffected")
        XCTAssertTrue(coord.boardState.cells[trap]?.passable ?? false)
        XCTAssertTrue(isBoulder(sim, top[3]))

        // Saved with the board.
        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(coord.boardState))).restore(to: restored)
        XCTAssertEqual(restored.rollers, coord.boardState.rollers)
        XCTAssertEqual(restored.underRollers, coord.boardState.underRollers)
    }

    /// "If any boulder moves onto a hex occupied by any figure, that figure takes trap damage.
    /// If the boulder stops in any figure's hex, that figure is forced to move one hex to the left."
    func testABoulderHarmsWhoeverItRollsOverAndPushesWhoeverItStopsOn() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let rows = coord.rollerRows()
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let trapDamage = sim.gm.levelManager.trap()
        // The Brute one hex before the lower boulder of the top row, the Spellweaver two before the middle row's.
        stand(sim, .character(brute.id), on: rows[0][1])
        stand(sim, .character(weaver.id), on: rows[1][2])
        let hound = try XCTUnwrap(coord.spawnMonster(name: "hound", type: .normal, at: rows[2][7], origin: .placed))
        let houndHealth = try XCTUnwrap(coord.entity(for: hound)?.health)
        let health = (brute.health, weaver.health)

        await coord.rollBoulders(by: [2, 3, 1])
        XCTAssertEqual(brute.health, health.0 - trapDamage, "rolled over: trap damage")
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], rows[0][1], "and left where they stood")
        XCTAssertEqual(weaver.health, health.1 - trapDamage)
        XCTAssertEqual(coord.boardState.piecePositions[.character(weaver.id)], rows[1][2])
        // The bottom row rolled one hex: its upper boulder (from (a), hex 5) didn't reach the hound,
        XCTAssertEqual(coord.entity(for: hound)?.health, houndHealth)
        // …and now does, stopping on it: damage, and a hex to the left.
        await coord.rollBoulders(by: [3, 2, 1])
        XCTAssertEqual(coord.rollers().filter(rows[2].contains).sorted(), [rows[2][2], rows[2][7]].sorted())
        XCTAssertEqual(coord.entity(for: hound)?.health, houndHealth - trapDamage, "monsters as well")
        XCTAssertEqual(coord.boardState.piecePositions[hound], rows[2][8], "pushed one hex to the left")
        XCTAssertTrue(isBoulder(sim, rows[2][7]))
    }

    /// "When any boulder reaches the leftmost hex of its row, it is immediately placed at b in
    /// its row and continues any movement it has to the left."
    func testABoulderAtTheEndOfItsRowComesBackInAtB() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let rows = coord.rollerRows()
        for index in 0..<2 { coord.boardState.removePiece(.character(sim.gm.game.characters[index].id)) }
        // The middle row is ten hexes: its leading boulder starts on hex 5.
        await coord.rollBoulders(by: [1, 3, 2])     // 5 → 8, 0 → 3
        XCTAssertEqual(coord.rollers().filter(rows[1].contains).sorted(), [rows[1][3], rows[1][8]].sorted())
        // Someone standing on (b) as it comes back in is rolled over too.
        let brute = sim.gm.game.characters[0]
        stand(sim, .character(brute.id), on: rows[1][0])
        let health = brute.health
        await coord.rollBoulders(by: [1, 3, 2])     // 8 → the last hex (9) = (b), then 1 and 2; 3 → 6
        XCTAssertEqual(coord.rollers().filter(rows[1].contains).sorted(), [rows[1][2], rows[1][6]].sorted())
        XCTAssertFalse(isBoulder(sim, rows[1][9]), "it never rests on the last hex")
        XCTAssertEqual(brute.health, health - sim.gm.levelManager.trap())
        XCTAssertEqual(coord.rollPath(from: rows[1][8], along: rows[1], steps: 2), [[rows[1][9], rows[1][0]], [rows[1][1]]])
    }

    /// "The players choose the number of hexes moved, but … each row of boulders must move a
    /// different number of hexes."
    func testThePlayersChooseHowFarEachRowRolls() async throws {
        let sim = try simulator(prompts: true)
        let coord = sim.coord
        let rows = coord.rollerRows()
        XCTAssertEqual(coord.rollChoices(rows: 3), [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]])
        let brute = sim.gm.game.characters[0]
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        // The Brute two hexes before the middle row's boulder: only a roll of 1 spares them.
        stand(sim, .character(brute.id), on: rows[1][2])
        let rolling = Task { @MainActor in await coord.rollAsTheRoundEnds() }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingOptionChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        guard let asked = coord.pendingOptionChoice else {
            rolling.cancel()
            return XCTFail("asked how far each row rolls")
        }
        XCTAssertEqual(asked.options.count, 6)
        XCTAssertEqual(asked.options[3], "Top 2 \u{B7} Middle 3 \u{B7} Bottom 1")
        XCTAssertEqual(coord.rollChoices(rows: 3)[asked.suggested][1], 1, "what is suggested spares the party")
        coord.resolveOptionChoice(9)
        XCTAssertNotNil(coord.pendingOptionChoice, "not one of the answers")
        let health = brute.health
        coord.resolveOptionChoice(0)   // top 1, middle 2, bottom 3: the players' choice, not the suggestion
        // The Brute is asked whether to lose a card for the damage: they take it.
        let asking = Date().addingTimeInterval(3)
        while coord.pendingDamage == nil, Date() < asking { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertNotNil(coord.pendingDamage, "damage a character may negate")
        coord.resolvePendingDamage(choice: .takeDamage)
        await rolling.value
        XCTAssertNil(coord.pendingOptionChoice)
        XCTAssertEqual(coord.rollers().filter(rows[0].contains).sorted(), [rows[0][1], rows[0][6]].sorted())
        XCTAssertEqual(coord.rollers().filter(rows[1].contains).sorted(), [rows[1][2], rows[1][7]].sorted())
        XCTAssertEqual(brute.health, health - sim.gm.levelManager.trap())
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], rows[1][3], "stopped on: pushed left")
    }

    /// A whole round played: the boulders roll after the last turn, and the game goes on.
    func testTheBouldersRollAsARoundOfPlayEnds() async throws {
        let sim = try ScenarioSimulator(scenario: "73", options: .init(characters: ["brute", "spellweaver"], seed: 2))
        _ = await sim.play(rounds: 3)
        let lines = sim.transcript
        let first = try XCTUnwrap(lines.firstIndex { $0.contains("The boulders roll:") }, "round 1's roll")
        XCTAssertLessThan(first, try XCTUnwrap(lines.firstIndex { $0.contains("Round 1 complete") }))
        XCTAssertGreaterThanOrEqual(lines.filter { $0.contains("The boulders roll:") }.count, 2)
        XCTAssertEqual(sim.coord.rollers().count, 6)
        XCTAssertTrue(sim.violations.isEmpty, "\(sim.violations)")
    }
}

/// Water that rises as rounds end and is bailed (`ScenarioPlacements.Flood`,
/// `BoardCoordinator+Flood`): the hold of the Merchant Ship (#74).
@MainActor
final class RisingWaterTests: XCTestCase {

    private func simulator(_ characters: [String] = ["brute", "spellweaver"], prompts: Bool = false) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "74", options: .init(characters: characters, seed: 1, autoResolvePrompts: !prompts))
        sim.gm.game.round = 1
        return sim
    }

    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let piece = PieceID.character(sim.gm.game.characters[index].id)
        if let other = sim.coord.boardState.piece(at: hex), other != piece { sim.coord.boardState.removePiece(other) }
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func wet(_ sim: ScenarioSimulator) -> [HexCoord] { sim.coord.floodHexes().filter(sim.coord.isFloodWater) }
    private func dry(_ sim: ScenarioSimulator) -> [HexCoord] { sim.coord.floodHexes().filter { !sim.coord.isFloodWater($0) } }

    /// "Remove water tiles d for three characters": the hold has fourteen hexes, twelve of them
    /// under water for two or four characters and ten for three.
    func testTheHoldStartsWithTwoDryHexesOrFourForThree() throws {
        let two = try simulator()
        XCTAssertEqual(two.coord.floodHexes().count, 14)
        XCTAssertEqual(wet(two).count, 12)
        XCTAssertEqual(Set(dry(two)), Set(two.coord.boardState.startingLocations.filter(two.coord.floodHexes().contains)))
        let three = try simulator(["brute", "spellweaver", "tinkerer"])
        XCTAssertEqual(wet(three).count, 10)
        XCTAssertTrue((three.coord.boardState.markerHexes["d"] ?? []).allSatisfy { !three.coord.isFloodWater($0) })
        let four = try simulator(["brute", "spellweaver", "tinkerer", "scoundrel"])
        XCTAssertEqual(wet(four).count, 12)
    }

    /// "At the end of every even round for two characters or every round for three or four
    /// characters, one water tile is added to the B tile adjacent to any existing water tile. If a
    /// water tile cannot be placed because the B tile is full, the scenario is lost."
    func testTheWaterRisesUntilTheHoldIsFullAndTheShipIsLost() async throws {
        let sim = try simulator()
        let coord = sim.coord
        sim.gm.game.round = 1
        XCTAssertFalse(coord.waterRisesThisRound, "an odd round, with two")
        sim.gm.game.round = 2
        XCTAssertTrue(coord.waterRisesThisRound)
        let three = try simulator(["brute", "spellweaver", "tinkerer"])
        three.gm.game.round = 1
        XCTAssertTrue(three.coord.waterRisesThisRound, "every round, with three")

        await coord.waterRisesAsTheRoundEnds()
        XCTAssertEqual(wet(sim).count, 13)
        XCTAssertNil(coord.pendingResult)
        await coord.waterRisesAsTheRoundEnds()
        XCTAssertEqual(wet(sim).count, 14)
        XCTAssertNil(coord.pendingResult, "full, but none had to be added yet")
        await coord.waterRisesAsTheRoundEnds()
        XCTAssertEqual(coord.pendingResult, .defeat)
        if case .ruleLost(let why) = coord.endReason { XCTAssertTrue(why.contains("hold is full"), why) } else { XCTFail("\(String(describing: coord.endReason))") }
    }

    /// "…adjacent to any existing water tile": the players are asked where, among the dry hexes
    /// beside the water.
    func testThePlayersChooseWhereTheWaterRises() async throws {
        let sim = try simulator(prompts: true)
        let coord = sim.coord
        // Bail the hold out but for one corner: only its dry neighbours can take the next tile.
        let corner = try XCTUnwrap(wet(sim).first)
        for hex in wet(sim) where hex != corner {
            coord.boardState.cells[hex]?.overlay = nil
            coord.boardState.cells[hex]?.overlaySubType = nil
        }
        let beside = Set(coord.boardState.neighbors(of: corner)).intersection(coord.floodHexes())
        XCTAssertEqual(Set(coord.risingWaterHexes()), beside)
        XCTAssertLessThan(beside.count, 13)
        let rising = Task { @MainActor in await coord.waterRisesAsTheRoundEnds() }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingHexChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        guard case .choosingHex(nil, _, _, let offered) = coord.interactionMode else {
            rising.cancel()
            return XCTFail("asked where: \(coord.interactionMode)")
        }
        XCTAssertEqual(offered, beside)
        let chosen = try XCTUnwrap(beside.sorted().last)
        coord.handleHexTap(chosen)
        await rising.value
        XCTAssertTrue(coord.isFloodWater(chosen))
        XCTAssertEqual(wet(sim).count, 2)
        XCTAssertTrue(coord.boardState.cells[chosen]?.isDifficultTerrain ?? false, "water is difficult terrain")
    }

    /// "Characters may pick up any water tile through normal looting and then get rid of it by
    /// ending their turn in one of the hexes e. Each character can only hold one water tile at a time."
    func testAWaterTileIsLootedOneAtATimeAndBailedOnTheDeck() throws {
        let sim = try simulator()
        let coord = sim.coord
        let brute = sim.gm.game.characters[0]
        let water = wet(sim)
        stand(sim, 0, on: water[0])
        coord.lootAtEndOfTurn(brute.id)
        XCTAssertTrue(coord.boardState.waterHeld.contains(brute.id))
        XCTAssertFalse(coord.isFloodWater(water[0]), "the tile is off the map")
        XCTAssertNil(coord.boardState.cells[water[0]]?.overlay)
        XCTAssertEqual(wet(sim).count, 11)
        // Holding one, they pick up no other — by ending a turn on water or by a Loot action.
        stand(sim, 0, on: water[1])
        coord.lootAtEndOfTurn(brute.id)
        _ = coord.collectLootInRange(pieceID: .character(brute.id), range: 1)
        XCTAssertEqual(wet(sim).count, 11)
        // Ending a turn anywhere else keeps it; on a bailing hex it goes overboard.
        XCTAssertTrue(coord.boardState.waterHeld.contains(brute.id))
        let bailing = try XCTUnwrap(coord.boardState.markerHexes["e"]?.sorted().first)
        stand(sim, 0, on: bailing)
        coord.lootAtEndOfTurn(brute.id)
        XCTAssertFalse(coord.boardState.waterHeld.contains(brute.id))
        XCTAssertEqual(wet(sim).count, 11, "it doesn't come back")
        // A Loot action takes one tile within its range, not all of them.
        stand(sim, 0, on: water[0])
        XCTAssertTrue(coord.collectLootInRange(pieceID: .character(brute.id), range: 1))
        XCTAssertTrue(coord.boardState.waterHeld.contains(brute.id))
        XCTAssertEqual(wet(sim).count, 10)

        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(coord.boardState))).restore(to: restored)
        XCTAssertEqual(restored.waterHeld, coord.boardState.waterHeld)
        XCTAssertTrue(restored.floodSetUp)
    }

    /// Whole rounds played: with two characters the water rises as the second round ends, and
    /// the scenario is lost once the hold can take no more.
    func testTheWaterRisesAsRoundsOfPlayEnd() async throws {
        let sim = try ScenarioSimulator(scenario: "74", options: .init(characters: ["brute", "spellweaver"], seed: 2))
        _ = await sim.play(rounds: 2)
        let lines = sim.transcript
        let rose = try XCTUnwrap(lines.firstIndex { $0.contains("The water rises") }, "round 2's water")
        XCTAssertGreaterThan(rose, try XCTUnwrap(lines.firstIndex { $0.contains("Round 1 complete") }), "not in round 1")
        XCTAssertLessThan(rose, try XCTUnwrap(lines.firstIndex { $0.contains("Round 2 complete") }))
        XCTAssertTrue(sim.violations.isEmpty, "\(sim.violations)")
    }
}
