import XCTest
@testable import GlavenGameLib

/// An altar that is a boss's hit points and jumps about the map (`ScenarioPlacements.Throne`,
/// `BoardCoordinator+Throne`): the Infernal Throne (#21).
@MainActor
final class ThroneTests: XCTestCase {

    private func simulator(_ characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "21", options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func open(_ sim: ScenarioSimulator, into tile: String) throws {
        let door = try XCTUnwrap(sim.coord.boardState.doors.first { !$0.isOpen && $0.childTileRef.lowercased() == tile }, "no shut door into \(tile)")
        sim.coord.openDoor(at: door.coord)
    }

    private func monsters(_ sim: ScenarioSimulator, _ name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let type, _) = $0 { return name == nil || type == name }
            return false
        }.sorted()
    }

    private func special(_ number: Int, _ sim: ScenarioSimulator) async throws {
        let boss = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "prime-demon" })
        let deck = sim.gm.monsterManager.abilities(for: boss)
        let card = try XCTUnwrap(deck.firstIndex { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == number } })
        boss.abilities = [card]
        boss.ability = 0
        boss.abilityDrawn = true
        sim.gm.game.state = .next
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(boss)
    }

    private func tile(_ sim: ScenarioSimulator, _ hex: HexCoord?) -> String? { hex.flatMap { sim.coord.boardState.cells[$0]?.tileRef.lowercased() } }

    /// "The Prime Demon and the altar share hit points … The Prime Demon cannot be damaged in any
    /// way. Instead, damage must be done to the altar."
    func testTheAltarIsThePrimeDemonsHitPoints() throws {
        let sim = try simulator()
        let coord = sim.coord
        XCTAssertNil(coord.throneAltar(), "not before its room is seen")
        try open(sim, into: "j1a")
        try open(sim, into: "d1a")
        let altar = try XCTUnwrap(coord.throneAltar())
        let boss = try XCTUnwrap(coord.throneBoss())
        XCTAssertEqual(coord.boardState.markerHexes["f"], [altar.hex], "it starts on f")
        XCTAssertGreaterThan(boss.entity.maxHealth, 0)
        XCTAssertEqual(altar.entity.maxHealth, boss.entity.maxHealth)
        XCTAssertEqual(altar.entity.health, boss.entity.health)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        XCTAssertTrue(coord.areEnemies(brute, altar.piece), "it can be attacked")

        let full = boss.entity.health
        XCTAssertFalse(coord.sufferDamage(5, to: boss.piece, killer: brute))
        XCTAssertEqual(boss.entity.health, full, "nothing damages the Prime Demon")
        coord.sufferDamage(5, to: altar.piece, killer: brute)
        XCTAssertEqual(altar.entity.health, full - 5)
        XCTAssertEqual(boss.entity.health, full - 5, "what the altar loses, it loses")
        coord.applyCondition(.poison, to: altar.piece)
        XCTAssertTrue(altar.entity.entityConditions.isEmpty, "an altar takes no condition")

        // The altar destroyed, the Prime Demon falls and the scenario is won.
        coord.sufferDamage(999, to: altar.piece, killer: brute)
        XCTAssertTrue(monsters(sim, "prime-demon").isEmpty)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// "The altar jumps to the next hex in the order of a, b, c, d, e, f, and then back to a …
    /// The altar then summons one normal demon for two characters … The type depends on the
    /// location" (as the FAQ corrects it: Wind, Night, Earth, Flame, Sun, Frost). "The Prime
    /// Demon then performs Move+2, Attack-1."
    func testTheAltarJumpsRoundItsSixPlacesSummoningAsItLands() async throws {
        let sim = try simulator()
        let coord = sim.coord
        try open(sim, into: "j1a")
        try open(sim, into: "d1a")
        for piece in monsters(sim) where piece != coord.throneBoss()?.piece { coord.sufferDamage(999, to: piece) }
        let stone = try XCTUnwrap(coord.throneAltar()).hex
        XCTAssertEqual(coord.boardState.cells[stone]?.overlay, .obstacle)
        let health = try XCTUnwrap(coord.throneAltar()).entity.health

        let places: [(letter: String, tile: String, demon: String)] = [
            ("a", "j1a", "wind-demon"), ("b", "j1a", "night-demon"), ("c", "j2a", "earth-demon"),
            ("d", "j2a", "flame-demon"), ("e", "d2a", "sun-demon"), ("f", "d1a", "frost-demon"), ("a", "j1a", "wind-demon"),
        ]
        var last = stone
        for (step, place) in places.enumerated() {
            for piece in monsters(sim) where piece != coord.throneBoss()?.piece { coord.sufferDamage(999, to: piece) }
            let bossBefore = coord.boardState.piecePositions[try XCTUnwrap(coord.throneBoss()).piece]
            try await special(step % 2 + 1, sim)
            let altar = try XCTUnwrap(coord.throneAltar())
            XCTAssertEqual(tile(sim, altar.hex), place.tile, "jump \(step + 1)")
            XCTAssertEqual(coord.boardState.markerHexes[place.letter], [altar.hex], "onto (\(place.letter))")
            XCTAssertEqual(coord.boardState.cells[altar.hex]?.overlay, .obstacle, "its stone goes with it")
            XCTAssertNil(coord.boardState.cells[last]?.overlay, "and is gone from where it stood")
            XCTAssertTrue(coord.boardState.cells[last]?.passable ?? false)
            XCTAssertEqual(altar.entity.health, health)
            // One demon of the place, normal for two characters, beside the altar; not acting this round.
            // (A room it reveals has its own monsters set up as well: the summoned one is the newcomer.)
            let summoned = monsters(sim).filter { (coord.entity(for: $0) as? GameMonsterEntity)?.summonState == .new }
            XCTAssertEqual(summoned.count, 1, "jump \(step + 1): \(summoned)")
            guard let demon = summoned.first, case .monster(let name, _) = demon else { continue }
            XCTAssertEqual(name, place.demon)
            XCTAssertFalse(coord.boardState.eliteStandees.contains(demon))
            XCTAssertTrue(coord.boardState.areAdjacent(try XCTUnwrap(coord.boardState.piecePositions[demon]), altar.hex))
            XCTAssertEqual((coord.entity(for: demon) as? GameMonsterEntity)?.summonState, .new, "summoned: it waits a round")
            // The Prime Demon has made its own move.
            if step == 0 { XCTAssertNotEqual(coord.boardState.piecePositions[try XCTUnwrap(coord.throneBoss()).piece], bossBefore) }
            last = altar.hex
        }
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })
        XCTAssertTrue(coord.boardState.doors.allSatisfy(\.isOpen), "every room it landed in is revealed, its doors open")
    }

    /// "If the hex is occupied by a figure … that figure … is moved to the nearest unoccupied
    /// hex. If the altar moves into an unrevealed room, that room is immediately revealed."
    func testTheAltarMovesWhoeverStandsThereAndRevealsItsRoom() async throws {
        let sim = try simulator()
        let coord = sim.coord
        // The party came round the other way: the first long hall has never been seen.
        try open(sim, into: "j2a")
        try open(sim, into: "d2a")
        try open(sim, into: "d1a")
        XCTAssertTrue(coord.boardState.markerHexes["a"]?.isEmpty ?? true)
        try await special(1, sim)
        let altar = try XCTUnwrap(coord.throneAltar())
        XCTAssertEqual(tile(sim, altar.hex), "j1a")
        XCTAssertFalse(monsters(sim, "night-demon").isEmpty, "the hall's own monsters are set up")
        XCTAssertTrue(coord.boardState.doors.allSatisfy(\.isOpen), "and every door between it and the rooms already seen is open")

        // The Brute on the next place: moved aside.
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let next = try XCTUnwrap(coord.boardState.markerHexes["b"]?.first)
        if let there = coord.boardState.piece(at: next) { coord.removePieceFromBoard(there) }
        coord.boardState.removePiece(brute)
        coord.boardState.placePiece(brute, at: next)
        try await special(2, sim)
        XCTAssertEqual(coord.throneAltar()?.hex, next)
        let moved = try XCTUnwrap(coord.boardState.piecePositions[brute])
        XCTAssertNotEqual(moved, next)
        XCTAssertTrue(coord.boardState.areAdjacent(moved, next) || coord.boardState.range(from: moved, to: next) ?? 9 <= 2, "to the nearest empty hex")
    }

    /// "…or one elite demon for three or four characters"; with the second special "the demon
    /// summoned is normal for two or three characters or elite for four characters."
    func testHowManyCharactersMakeTheSummonedDemonElite() async throws {
        for (party, eliteOnFirst, eliteOnSecond) in [(["brute", "spellweaver", "tinkerer"], true, false),
                                                     (["brute", "spellweaver", "tinkerer", "scoundrel"], true, true)] {
            let sim = try simulator(party)
            let coord = sim.coord
            try open(sim, into: "j1a")
            try open(sim, into: "d1a")
            for (number, elite) in [(1, eliteOnFirst), (2, eliteOnSecond)] {
                for piece in monsters(sim) where piece != coord.throneBoss()?.piece { coord.sufferDamage(999, to: piece) }
                try await special(number, sim)
                let demon = try XCTUnwrap(monsters(sim).first { $0 != coord.throneBoss()?.piece })
                XCTAssertEqual(coord.boardState.eliteStandees.contains(demon), elite, "\(party.count) characters, special \(number)")
            }
        }
    }
}
