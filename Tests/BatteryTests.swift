import XCTest
@testable import GlavenGameLib

/// A gun that never acts and is fired by its crew (`ScenarioPlacements.Battery`,
/// `BoardCoordinator+Battery`): the Siege Cannon of Rebel's Stand (#49).
@MainActor
final class BatteryTests: XCTestCase {

    private func simulator(reveal: Bool = true) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "49", options: .init(characters: ["brute", "spellweaver", "tinkerer"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        if reveal, let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) { sim.coord.openDoor(at: door.coord) }
        return sim
    }

    private func pieces(_ sim: ScenarioSimulator, _ name: String) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .monster(name, _) = $0 { return true }; return false }.sorted()
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        if let other = sim.coord.boardState.piece(at: hex), other != piece { sim.coord.removePieceFromBoard(other) }
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    /// The cannon, two archers of the crew kept on the board (the rest of the monsters gone), and
    /// the party out of the way on the first tile's far end.
    private func cannonAndCrew(_ sim: ScenarioSimulator) throws -> (cannon: PieceID, hex: HexCoord, archers: [PieceID]) {
        let coord = sim.coord
        let cannon = try XCTUnwrap(pieces(sim, "siege-cannon").first)
        let archers = Array(pieces(sim, "city-archer").prefix(2))
        XCTAssertEqual(archers.count, 2)
        for piece in coord.boardState.piecePositions.keys.sorted() where piece != cannon && !archers.contains(piece) {
            if case .monster = piece { coord.removePieceFromBoard(piece) }
        }
        return (cannon, try XCTUnwrap(coord.boardState.piecePositions[cannon]), archers)
    }

    private func floor(_ sim: ScenarioSimulator, where test: (HexCoord) -> Bool) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { board.isPassable($0) && board.cells[$0]?.overlay == nil && board.piece(at: $0) == nil && test($0) })
    }

    private func archersTurn(_ sim: ScenarioSimulator) async throws {
        let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "city-archer" })
        if !monster.abilityDrawn { sim.gm.monsterManager.drawAbility(for: monster) }
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(monster)
    }

    /// "The Ancient Artillery does not act": no card, no turn, whoever stands before it.
    func testTheSiegeCannonTakesNoTurn() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (_, hex, _) = try cannonAndCrew(sim)
        let cannon = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "siege-cannon" })
        XCTAssertEqual(MonsterAI.idleMonsters(sim.gm.game), ["siege-cannon"])
        let brute = sim.gm.game.characters[0]
        stand(sim, .character(brute.id), on: try floor(sim) { coord.boardState.range(from: $0, to: hex) == 3 })
        let health = brute.health
        // Even with a card of the artillery's deck in front of it.
        sim.gm.monsterManager.drawAbility(for: cannon)
        await MonsterTurnController(coordinator: coord, gameManager: sim.gm).executeMonsterGroup(cannon)
        XCTAssertEqual(brute.health, health)
        // A round of play gives it no place in the order.
        let played = try ScenarioSimulator(scenario: "49", options: .init(characters: ["brute", "spellweaver"], seed: 2))
        if let door = played.coord.boardState.doors.first(where: { !$0.isOpen }) { played.coord.openDoor(at: door.coord) }
        _ = await played.play(rounds: 2)
        XCTAssertFalse(played.transcript.contains { $0.contains("Siege Cannon\u{2019}s turn") || $0.hasPrefix("Siege Cannon draws") })
        XCTAssertTrue(played.transcript.contains { $0.contains("City Archer\u{2019}s turn") })
        XCTAssertTrue(played.violations.isEmpty, "\(played.violations)")
    }

    /// "Each round, instead of acting normally, the City Archer who is closest to the artillery
    /// (or the one who acts first in the case of a tie) performs 'Move 3' toward a hex adjacent
    /// to the artillery that is not labeled b."
    func testTheNearestArcherMakesForTheCannon() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (cannon, hex, archers) = try cannonAndCrew(sim)
        let before = Set(coord.boardState.markerHexes["b"] ?? [])
        XCTAssertEqual(before.count, 3)
        XCTAssertTrue(before.allSatisfy { coord.boardState.areAdjacent($0, hex) }, "the three hexes before the muzzle")
        XCTAssertEqual(coord.gunnerPosts().count, 3, "and the three behind it")
        XCTAssertTrue(Set(coord.gunnerPosts()).isDisjoint(with: before))

        // One archer six hexes off, the other eight: the nearer serves, the other acts as its card says.
        let near = try floor(sim) { coord.boardState.range(from: $0, to: hex) == 6 && !coord.batteryLine().contains($0) }
        let far = try floor(sim) { coord.boardState.range(from: $0, to: hex) == 8 }
        stand(sim, archers[1], on: near)
        stand(sim, archers[0], on: far)
        XCTAssertEqual(coord.gunner(ofType: "city-archer"), archers[1], "the nearer, not the lower number")
        XCTAssertNil(coord.gunner(ofType: "city-guard"))
        // The party where the archers can see it: only the one acting on its card attacks.
        for (index, character) in sim.gm.game.characters.enumerated() {
            stand(sim, .character(character.id), on: try floor(sim) { coord.boardState.range(from: $0, to: near) == 2 + index && !coord.batteryLine().contains($0) })
        }
        let attacks = sim.coord.turnLog.count
        try await archersTurn(sim)
        let ended = try XCTUnwrap(coord.boardState.piecePositions[archers[1]])
        XCTAssertEqual(coord.boardState.range(from: ended, to: hex), 3, "three hexes nearer")
        let lines = coord.turnLog.dropFirst(attacks).map(\.message)
        XCTAssertTrue(lines.contains { $0.contains("makes for the Siege Cannon") })
        XCTAssertFalse(lines.contains { $0.hasPrefix(coord.name(archers[1]) + " attacks") }, "it does nothing else")
        XCTAssertFalse(lines.contains { $0.contains("fires") }, "not beside the cannon yet")
        XCTAssertNotNil(coord.boardState.piecePositions[cannon])

        // As near as each other: the one that acts first (the elite, else the lower number).
        let posts = coord.gunnerPosts()
        let tied = try floor(sim) { coord.boardState.range(from: $0, to: hex) == 3 && $0 != ended }
        stand(sim, archers[0], on: tied)
        let first = [archers[0], archers[1]].min { a, b in
            let rank = { (piece: PieceID) -> Int in (coord.boardState.eliteStandees.contains(piece) ? 0 : 100) + (coord.entity(for: piece) as! GameMonsterEntity).number }
            return rank(a) < rank(b)
        }
        XCTAssertEqual(coord.gunner(ofType: "city-archer"), first)
        XCTAssertFalse(posts.isEmpty)
    }

    /// "If the archer is then adjacent to the artillery, it fires, causing damage equal to the
    /// elite artillery's Attack value on all characters and character summons in hexes b and the
    /// columns above those hexes (including all of the G tile)."
    func testBesideTheCannonTheArcherFiresItDownItsLine() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (_, hex, archers) = try cannonAndCrew(sim)
        coord.removePieceFromBoard(archers[0])
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1], tinkerer = sim.gm.game.characters[2]
        let before = (coord.boardState.markerHexes["b"] ?? []).sorted()
        let line = coord.batteryLine()
        // The line: the three hexes before the muzzle, their rows away from the cannon, and all of the first tile.
        XCTAssertTrue(before.allSatisfy(line.contains))
        XCTAssertTrue(coord.boardState.cells.values.filter { $0.tileRef.lowercased() == "g1a" }.allSatisfy { line.contains($0.coord) })
        XCTAssertEqual(Set(line.filter { coord.boardState.cells[$0]?.tileRef.lowercased() != "g1a" }.map(\.row)), Set(before.map(\.row)))
        XCTAssertFalse(line.contains(hex))
        XCTAssertTrue(coord.gunnerPosts().allSatisfy { !line.contains($0) }, "the crew stands clear")

        // The Brute before the muzzle, the Spellweaver on the first tile, a summon far down a row; the Tinkerer off the line.
        stand(sim, .character(brute.id), on: before[0])
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.cells[$0]?.tileRef.lowercased() == "g1a" })
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: 1, health: 9, maxHealth: 9, level: 1,
                                attack: .int(1), movement: 2, range: 0)
        summon.state = .active
        brute.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: try floor(sim) {
            line.contains($0) && coord.boardState.cells[$0]?.tileRef.lowercased() == "l1b" })
        stand(sim, .character(tinkerer.id), on: try floor(sim) { !line.contains($0) && coord.boardState.range(from: $0, to: hex) ?? 0 > 4 })
        // The archer two hexes from a post: it walks there and fires.
        let post = try XCTUnwrap(coord.gunnerPosts().first { coord.boardState.piece(at: $0) == nil })
        stand(sim, archers[1], on: try floor(sim) { coord.boardState.range(from: $0, to: post) == 2 && !line.contains($0) && !coord.boardState.areAdjacent($0, hex) })
        let cannon = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "siege-cannon" })
        let damage = try XCTUnwrap(cannon.stat(for: .boss)?.attack?.intValue)
        let elite = try XCTUnwrap(sim.gm.editionStore.monsterData(name: "ancient-artillery", edition: "gh")?
            .stats.first { $0.type == .elite && $0.level == cannon.level }?.attack?.intValue)
        XCTAssertEqual(damage, elite, "an elite Ancient Artillery's Attack")
        let health = (brute.health, weaver.health, tinkerer.health)
        try await archersTurn(sim)
        XCTAssertTrue(coord.gunnerPosts().contains(try XCTUnwrap(coord.boardState.piecePositions[archers[1]])), "beside the cannon, off the b hexes")
        XCTAssertEqual(brute.health, health.0 - damage)
        XCTAssertEqual(weaver.health, health.1 - damage)
        XCTAssertEqual(summon.health, 9 - damage)
        XCTAssertEqual(tinkerer.health, health.2, "off the line")
        // Next round it is there already: it fires again without moving.
        try await archersTurn(sim)
        XCTAssertEqual(brute.health, health.0 - 2 * damage)
    }

    /// "If, at the end of a round, no City Archers are present on the map, one normal archer
    /// spawns at a."
    func testAnArcherArrivesWhenNoneIsLeft() throws {
        let sim = try simulator()
        let coord = sim.coord
        let corner = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first)
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertNil(coord.boardState.piece(at: corner), "there are archers")
        let count = pieces(sim, "city-archer").count
        for archer in pieces(sim, "city-archer") { coord.sufferDamage(99, to: archer) }
        XCTAssertTrue(pieces(sim, "city-archer").isEmpty)
        XCTAssertGreaterThan(count, 0)
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(pieces(sim, "city-archer").count, 1)
        let arrived = try XCTUnwrap(pieces(sim, "city-archer").first)
        XCTAssertEqual(coord.boardState.piecePositions[arrived], corner)
        XCTAssertFalse(coord.boardState.eliteStandees.contains(arrived), "a normal one")
        sim.gm.game.round = 2
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(pieces(sim, "city-archer").count, 1, "one is enough")

        // Before the clearing is reached nothing arrives.
        let early = try simulator(reveal: false)
        for archer in pieces(early, "city-archer") { early.coord.sufferDamage(99, to: archer) }
        early.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertTrue(pieces(early, "city-archer").isEmpty)
    }
}
