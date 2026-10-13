import XCTest
@testable import GlavenGameLib

/// Monsters that carry an objective instead of acting (`ScenarioPlacements.Carry`,
/// `BoardCoordinator+Carry`): the two Cultists of the Sacrifice Pit and their victim (#78).
@MainActor
final class CarrierTests: XCTestCase {

    private func simulator(revealTheAltar: Bool = false) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "78", options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        let first = try XCTUnwrap(sim.coord.boardState.doors.first { $0.childTileRef.lowercased() == "m1a" })
        sim.coord.openDoor(at: first.coord)
        if revealTheAltar, let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) { sim.coord.openDoor(at: door.coord) }
        // Only the carriers and the victim are left; the party waits by the first door.
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster(let name, _) = piece, name != "cultist-scenario-78" { sim.coord.removePieceFromBoard(piece) }
        }
        return sim
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func carriersTurn(_ sim: ScenarioSimulator) async throws {
        let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "cultist-scenario-78" })
        if !monster.abilityDrawn { sim.gm.monsterManager.drawAbility(for: monster) }
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(monster)
    }

    private func move(_ sim: ScenarioSimulator) throws -> Int {
        let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "cultist-scenario-78" })
        return try XCTUnwrap(monster.stat(for: .elite)?.movement?.intValue)
    }

    /// "The victim a, represented by a numbered token": there from the moment the room is seen,
    /// no one's enemy and nothing anyone can harm or shift.
    func testTheVictimKneelsInTheMiddleOfTheRoom() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let victim = try XCTUnwrap(coord.carriedVictim())
        XCTAssertEqual(coord.boardState.cells[victim.hex]?.tileRef.lowercased(), "m1a")
        XCTAssertEqual(coord.carriers().count, 2)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        XCTAssertFalse(coord.areEnemies(brute, victim.piece))
        for carrier in coord.carriers() { XCTAssertFalse(coord.areEnemies(carrier, victim.piece)) }
        coord.sufferDamage(5, to: victim.piece)
        XCTAssertEqual(coord.boardState.piecePositions[victim.piece], victim.hex)
        await coord.performPushPull(target: victim.piece, attackerPos: victim.hex.neighbors[0], steps: 2, isPush: true)
        XCTAssertEqual(coord.boardState.piecePositions[victim.piece], victim.hex, "immune to forced movement")
        // With every enemy dead the scenario is won, victim or no victim.
        for carrier in coord.carriers() { coord.sufferDamage(99, to: carrier) }
        coord.boardState.lockedDoors.removeAll()
        for _ in 0..<5 { if let door = coord.boardState.doors.first(where: { !$0.isOpen }) { coord.openDoor(at: door.coord) } }
        for piece in coord.boardState.piecePositions.keys.sorted() { if case .monster = piece { coord.sufferDamage(99, to: piece) } }
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// "The Cultists will first move to a hex adjacent to the victim": "Move+0" each, and nothing
    /// else — no attack on a character beside them — while the victim stays where he is.
    func testTheCarriersGoToTheVictimFirst() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let victim = try XCTUnwrap(coord.carriedVictim())
        let carriers = coord.carriers()
        let started = carriers.compactMap { coord.boardState.piecePositions[$0] }
        let reach = try move(sim)
        // The Brute stands beside one of them.
        let brute = sim.gm.game.characters[0]
        stand(sim, .character(brute.id), on: try XCTUnwrap(coord.boardState.neighbors(of: started[0]).sorted().first {
            coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil && coord.boardState.range(from: $0, to: victim.hex) ?? 0 > 2 }))
        let health = brute.health
        try await carriersTurn(sim)
        for (carrier, from) in zip(carriers, started) {
            let now = try XCTUnwrap(coord.boardState.piecePositions[carrier])
            let before = try XCTUnwrap(coord.boardState.range(from: from, to: victim.hex)), after = try XCTUnwrap(coord.boardState.range(from: now, to: victim.hex))
            XCTAssertEqual(after, max(1, before - reach), "\(carrier): its Move nearer, no further than beside him")
        }
        XCTAssertEqual(brute.health, health, "they don't attack")
        XCTAssertEqual(coord.boardState.piecePositions[victim.piece], victim.hex, "no one has hold of him yet")
        XCTAssertNil(coord.pendingResult)
    }

    /// "…then move to c or the nearest hex adjacent to the altar. After the cultists move, the
    /// victim will then move the same number of hexes to be adjacent to them, preferably to the
    /// left of the right Cultist and to the right of the left Cultist." They open the doors in
    /// their way; and "if a Cultist starts its turn adjacent to the altars, and the victim is
    /// also adjacent to the altars, the victim is sacrificed and the scenario is lost."
    func testTheVictimIsCarriedToTheAltarAndSacrificed() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let victim = try XCTUnwrap(coord.carriedVictim()).piece
        let reach = try move(sim)
        XCTAssertTrue(coord.boardState.doors.contains { !$0.isOpen }, "the altar room is shut")
        var rounds = 0, carriedOnce = false
        while coord.pendingResult == nil, rounds < 30 {
            rounds += 1
            let before = try XCTUnwrap(coord.boardState.piecePositions[victim])
            let held = coord.carriers().contains { coord.boardState.areAdjacent(coord.boardState.piecePositions[$0]!, before) }
            let stood = coord.carriers().map { coord.boardState.piecePositions[$0]! }
            try await carriersTurn(sim)
            guard coord.pendingResult == nil else { break }
            let after = try XCTUnwrap(coord.boardState.piecePositions[victim])
            let went = zip(coord.carriers(), stood).map { coord.boardState.range(from: $1, to: coord.boardState.piecePositions[$0]!) ?? 0 }.max() ?? 0
            XCTAssertLessThanOrEqual(coord.boardState.range(from: before, to: after) ?? 0, went, "no further than he was carried")
            if !held { XCTAssertEqual(after, before, "round \(rounds): not moved before a Cultist has hold of him") }
            if after != before {
                carriedOnce = true
                XCTAssertTrue(coord.carriers().contains { coord.boardState.areAdjacent(coord.boardState.piecePositions[$0]!, after) }, "he ends beside them")
            }
            for carrier in coord.carriers() { XCTAssertLessThanOrEqual(coord.boardState.range(from: stood[coord.carriers().firstIndex(of: carrier)!], to: coord.boardState.piecePositions[carrier]!) ?? 0, reach) }
        }
        XCTAssertTrue(carriedOnce)
        XCTAssertTrue(coord.boardState.doors.allSatisfy(\.isOpen) || coord.boardState.doors.filter { !$0.isOpen }.count < 3, "they opened the way to the altar")
        XCTAssertEqual(coord.pendingResult, .defeat, "after \(rounds) turns")
        if case .ruleLost(let why) = coord.endReason { XCTAssertEqual(why, "The victim is sacrificed.") } else { XCTFail("\(String(describing: coord.endReason))") }
        // As it happens: the Cultists on the two hexes before the altar, the victim between them.
        let before = Set(coord.boardState.markerHexes["c"] ?? [])
        XCTAssertEqual(Set(coord.carriers().compactMap { coord.boardState.piecePositions[$0] }), before)
        let between = try XCTUnwrap(coord.boardState.piecePositions[victim])
        XCTAssertTrue(before.allSatisfy { coord.boardState.areAdjacent($0, between) })
        XCTAssertTrue((coord.boardState.markerHexes["d"] ?? []).allSatisfy { coord.boardState.areAdjacent($0, between) }, "beside both altars")
    }

    /// One Cultist can make the sacrifice alone; with both dead the victim stays where he was left.
    func testTheSacrificeNeedsACarrier() async throws {
        let sim = try simulator(revealTheAltar: true)
        let coord = sim.coord
        let victim = try XCTUnwrap(coord.carriedVictim()).piece
        let carriers = coord.carriers()
        coord.sufferDamage(99, to: carriers[0])
        XCTAssertEqual(coord.carriers(), [carriers[1]])
        // The survivor beside the victim, two hexes from the altar's side.
        let before = (coord.boardState.markerHexes["c"] ?? []).sorted()
        let altars = coord.boardState.markerHexes["d"] ?? []
        let between = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { hex in altars.allSatisfy { coord.boardState.areAdjacent($0, hex) } })
        stand(sim, victim, on: between)
        stand(sim, carriers[1], on: before[0])
        XCTAssertTrue(coord.sacrificeIsMade(by: carriers[1]))
        // The victim away from the altar: no sacrifice, wherever the Cultist stands.
        let away = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { hex in
            coord.boardState.isPassable(hex) && coord.boardState.piece(at: hex) == nil && !altars.contains { coord.boardState.areAdjacent($0, hex) }
                && coord.boardState.cells[hex]?.tileRef.lowercased() == "i1b"
        })
        stand(sim, victim, on: away)
        XCTAssertFalse(coord.sacrificeIsMade(by: carriers[1]))
        // The victim beside the altar but the Cultist not: none either.
        stand(sim, victim, on: between)
        stand(sim, carriers[1], on: away)
        XCTAssertFalse(coord.sacrificeIsMade(by: carriers[1]))
        stand(sim, carriers[1], on: before[0])
        try await carriersTurn(sim)
        XCTAssertEqual(coord.pendingResult, .defeat)

        // Both dead: nothing happens on their turn.
        let other = try simulator(revealTheAltar: true)
        let left = try XCTUnwrap(other.coord.carriedVictim())
        for carrier in other.coord.carriers() { other.coord.sufferDamage(99, to: carrier) }
        try await carriersTurn(other)
        XCTAssertEqual(other.coord.boardState.piecePositions[left.piece], left.hex)
        XCTAssertNil(other.coord.pendingResult)
    }
}
