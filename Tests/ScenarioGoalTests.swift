import XCTest
@testable import GlavenGameLib

/// The goal and loss conditions the scenario book prints (`ScenarioPlacements.Goal`): the game
/// ends a scenario when its own goal is met, not when every enemy happens to be dead.
@MainActor
final class ScenarioGoalTests: XCTestCase {

    private func simulator(_ index: String, characters: [String] = ["brute", "spellweaver"]) async throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        // A goal is only judged once a round has been played.
        sim.gm.game.round = 1
        return sim
    }

    private func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<40 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            if let barring = sim.coord.boardState.objectiveSites.first(where: { $0.value.barsDoor && $0.value.coord == door.coord }) {
                sim.coord.handleDeath(of: .objective(id: barring.key))
            } else {
                sim.coord.openDoor(at: door.coord)
            }
        }
    }

    private func pieces(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    private func kill(_ sim: ScenarioSimulator, _ targets: [PieceID]) {
        for piece in targets where sim.coord.isOnBoard(piece) { sim.coord.handleDeath(of: piece) }
    }

    private func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    /// Stand a character on a hex, moving aside whatever is there.
    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != character(sim, index) { board.removePiece(other) }
        board.removePiece(character(sim, index))
        board.placePiece(character(sim, index), at: hex)
    }

    private func brief(_ sim: ScenarioSimulator) throws -> ScenarioBrief {
        ScenarioBrief.make(for: try XCTUnwrap(sim.gm.game.scenario?.data), labels: sim.gm.editionStore)
    }

    // MARK: - Kill

    /// Gloomhaven Warehouse: killing both Inox Bodyguards wins, whoever else still stands.
    func testKillingTheNamedEnemiesWins() async throws {
        let sim = try await simulator("8")
        XCTAssertEqual(try brief(sim).goal, "Kill both Inox Bodyguards.")
        revealAll(sim)
        let guards = pieces(sim, named: "inox-bodyguard")
        XCTAssertEqual(guards.count, 2)
        kill(sim, [guards[0]])
        XCTAssertNil(sim.coord.pendingResult, "one bodyguard stands")
        kill(sim, [guards[1]])
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertEqual(sim.coord.endReason, .goalMet("Kill both Inox Bodyguards."))
        XCTAssertFalse(pieces(sim).isEmpty, "with other enemies still alive")
    }

    /// There, killing everything but the bodyguards wins nothing.
    func testKillingEveryoneElseIsNotTheGoal() async throws {
        let sim = try await simulator("8")
        revealAll(sim)
        kill(sim, pieces(sim).filter { !pieces(sim, named: "inox-bodyguard").contains($0) })
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult)
    }

    /// A boss behind a door hasn't been killed by not having been met.
    func testABossNotYetRevealedIsNotDead() async throws {
        let sim = try await simulator("8")
        kill(sim, pieces(sim))
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult)
    }

    /// Inox Encampment: five kills a character, of any enemy.
    func testANumberOfKillsWins() async throws {
        let sim = try await simulator("3")
        for _ in 0..<9 { sim.coord.recordMonsterKill(name: "inox-guard") }
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "nine of ten")
        sim.coord.recordMonsterKill(name: "inox-archer")
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertFalse(pieces(sim).isEmpty)
    }

    /// Drake Nest counts drakes only.
    func testOnlyTheNamedKindsCount() async throws {
        let sim = try await simulator("43")
        for _ in 0..<8 { sim.coord.recordMonsterKill(name: "flame-demon") }
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult)
        for _ in 0..<8 { sim.coord.recordMonsterKill(name: "rending-drake") }
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// Barrow Lair: the Bandit Commander and every enemy on the board, with rooms still shut.
    func testRevealedEnemiesAreEnough() async throws {
        let sim = try await simulator("2")
        let coord = sim.coord
        let door = try XCTUnwrap(coord.boardState.doors.first { $0.childTileRef.lowercased() == "m1a" })
        coord.openDoor(at: door.coord)
        XCTAssertTrue(coord.boardState.doors.contains { !$0.isOpen }, "side rooms stay shut")
        let commander = pieces(sim, named: "bandit-commander")
        kill(sim, pieces(sim).filter { !commander.contains($0) })
        XCTAssertNil(coord.pendingResult, "the commander lives")
        kill(sim, commander)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// Decaying Crypt needs the M tile revealed as well.
    func testATileToReveal() async throws {
        let sim = try await simulator("6")
        kill(sim, pieces(sim))
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "the M tile isn't revealed")
        revealAll(sim)
        kill(sim, pieces(sim))
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// "All enemies" needs every room revealed; "all revealed enemies" doesn't. And a kind of
    /// enemy to kill isn't all dead while a room that holds some is still shut.
    func testEnemiesBehindDoorsCount() async throws {
        let sim = try await simulator("1")
        let coord = sim.coord
        kill(sim, pieces(sim))
        XCTAssertTrue(coord.boardState.doors.contains { !$0.isOpen })
        XCTAssertFalse(coord.goalMet(ScenarioPlacements.Goal(enemies: "all")))
        XCTAssertTrue(coord.goalMet(ScenarioPlacements.Goal(enemies: "revealed")))
        XCTAssertFalse(coord.goalMet(ScenarioPlacements.Goal(kill: ["bandit-guard"])), "more wait in the next room")
        revealAll(sim)
        kill(sim, pieces(sim))
        XCTAssertTrue(coord.goalMet(ScenarioPlacements.Goal(enemies: "all")))
        XCTAssertTrue(coord.goalMet(ScenarioPlacements.Goal(kill: ["bandit-guard"])))
    }

    /// Back Alley Brawl: the other enemies must die; a City Guard dying loses it.
    func testKillingTheWrongEnemyLoses() async throws {
        let sim = try await simulator("92")
        XCTAssertTrue(try brief(sim).defeat.contains("A City Guard is killed."))
        sim.coord.recordMonsterKill(name: "city-guard")
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
        XCTAssertEqual(sim.coord.endReason, .ruleLost("A City Guard is killed."))
    }

    // MARK: - Loot

    private func goalTreasure(_ sim: ScenarioSimulator) -> [HexCoord] {
        sim.coord.boardState.cells.values.filter { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }
            .map(\.coord).sorted()
    }

    /// Shrine of the Depths: looting the treasure tile wins, with the room full of enemies.
    func testLootingTheGoalTreasureWins() async throws {
        let sim = try await simulator("30")
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "the treasure's room isn't revealed")
        revealAll(sim)
        let chest = try XCTUnwrap(goalTreasure(sim).first)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chest], byLootAction: true)
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertFalse(pieces(sim).isEmpty)
    }

    /// There the treasure takes a Loot action: ending a turn on it, or walking over it, leaves
    /// it where it is. A scenario without that rule (Diamond Mine) lets a turn's end pick it up.
    func testGoalTreasureThatNeedsALootAction() async throws {
        let sim = try await simulator("30")
        revealAll(sim)
        let chest = try XCTUnwrap(goalTreasure(sim).first)
        stand(sim, 0, on: chest)
        sim.coord.lootAtEndOfTurn(sim.gm.game.characters[0].id)
        XCTAssertEqual(goalTreasure(sim), [chest], "still there")
        sim.coord.collectLootInRange(pieceID: character(sim, 0), range: 1)
        XCTAssertTrue(goalTreasure(sim).isEmpty, "a Loot action takes it")
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)

        let mine = try await simulator("9")
        revealAll(mine)
        let goal = try XCTUnwrap(goalTreasure(mine).first)
        stand(mine, 0, on: goal)
        mine.coord.lootAtEndOfTurn(mine.gm.game.characters[0].id)
        XCTAssertTrue(goalTreasure(mine).isEmpty)
    }

    /// Forgotten Grove wants the enemies dead as well.
    func testLootAndEnemiesTogether() async throws {
        let sim = try await simulator("59")
        revealAll(sim)
        let chest = try XCTUnwrap(goalTreasure(sim).first)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chest], byLootAction: true)
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "enemies remain")
        kill(sim, pieces(sim))
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// Noxious Cellar: every character loots one tile — and only one.
    func testEveryCharacterLootsOne() async throws {
        let sim = try await simulator("52")
        revealAll(sim)
        let chests = goalTreasure(sim)
        XCTAssertEqual(chests.count, 4)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chests[0]], byLootAction: true)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chests[1]], byLootAction: true)
        XCTAssertEqual(goalTreasure(sim).count, 3, "a second tile isn't theirs to take")
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult)
        sim.coord.lootHexes(for: character(sim, 1), coords: [chests[1]], byLootAction: true)
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// There, a character exhausted before looting theirs loses the scenario; after, it doesn't.
    func testExhaustionBeforeLootingLoses() async throws {
        var sim = try await simulator("52")
        XCTAssertTrue(try brief(sim).defeat.contains("A character is exhausted before the treasure is looted."))
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)

        sim = try await simulator("52")
        revealAll(sim)
        sim.coord.lootHexes(for: character(sim, 0), coords: [try XCTUnwrap(goalTreasure(sim).first)], byLootAction: true)
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertNil(sim.coord.pendingResult)
    }

    // MARK: - Escape

    /// Icecrag Ascent: won with every character on an exit hex as a turn ends.
    func testEveryoneOnTheExitWins() async throws {
        let sim = try await simulator("25")
        let coord = sim.coord
        revealAll(sim)
        let exits = try XCTUnwrap(coord.boardState.markerHexes["a"])
        XCTAssertEqual(exits.count, 5)
        stand(sim, 0, on: exits[0])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.pendingResult, "one is still on the way")
        stand(sim, 1, on: exits[1])
        coord.checkVictoryDefeat()
        XCTAssertNil(coord.pendingResult, "judged as a turn ends, not in passing")
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
        XCTAssertFalse(pieces(sim).isEmpty)
    }

    /// Exhausted away from the exit, the scenario is lost; exhausted on it, the others go on.
    func testExhaustionAwayFromTheExitLoses() async throws {
        var sim = try await simulator("25")
        XCTAssertTrue(try brief(sim).defeat.contains("A character is exhausted away from the exit."))
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
        XCTAssertEqual(sim.coord.endReason, .ruleLost("Brute is exhausted away from the exit."))

        sim = try await simulator("25")
        revealAll(sim)
        let exits = try XCTUnwrap(sim.coord.boardState.markerHexes["a"])
        stand(sim, 0, on: exits[0])
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertNil(sim.coord.pendingResult)
        stand(sim, 1, on: exits[1])
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory, "the one left reached the exit")
    }

    /// Savvas Armory: the exit only counts once the treasure is looted.
    func testTheTreasureComesBeforeTheExit() async throws {
        let sim = try await simulator("33")
        let coord = sim.coord
        let exits = try XCTUnwrap(coord.boardState.markerHexes["a"])
        stand(sim, 0, on: exits[0])
        stand(sim, 1, on: exits[1])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.pendingResult, "nothing looted yet")
        revealAll(sim)
        coord.lootHexes(for: character(sim, 0), coords: goalTreasure(sim), byLootAction: true)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// Timeworn Tomb: a character on the exit as a round ends is gone; when all are, it is won.
    func testLeavingOneByOne() async throws {
        let sim = try await simulator("41")
        let coord = sim.coord
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertNil(coord.pendingResult, "exhaustion only loses once the last room is open")

        let again = try await simulator("41")
        revealAll(again)
        let exit = try XCTUnwrap(again.coord.boardState.markerHexes["a"]?.first)
        stand(again, 0, on: exit)
        again.coord.letCharactersLeave()
        XCTAssertNil(again.coord.boardState.piecePositions[character(again, 0)], "gone from the board")
        again.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(again.coord.scenarioResult, "one is still inside")
        XCTAssertNil(again.coord.pendingResult)
        stand(again, 1, on: exit)
        again.coord.letCharactersLeave()
        again.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(again.coord.scenarioResult, .victory)
    }

    /// There, with the last room open, anyone's exhaustion loses.
    func testExhaustionInTheLastRoomLoses() async throws {
        let sim = try await simulator("41")
        revealAll(sim)
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    /// Vigil Keep: each loots a tile, then all stand on the B tile.
    func testATileToReach() async throws {
        let sim = try await simulator("80")
        let coord = sim.coord
        revealAll(sim)
        let tile = coord.boardState.cells.values.filter { $0.tileRef == "b1a" && $0.passable && $0.overlay == nil }.map(\.coord).sorted()
        stand(sim, 0, on: tile[0])
        stand(sim, 1, on: tile[1])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.pendingResult, "no one has looted")
        let chests = goalTreasure(sim)
        coord.lootHexes(for: character(sim, 0), coords: [chests[0]], byLootAction: true)
        coord.lootHexes(for: character(sim, 1), coords: [chests[1]], byLootAction: true)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    // MARK: - Pressure plates and hexes to reach

    /// Ancient Defense Network: a character on each plate at once.
    func testStandingOnEveryPlateWins() async throws {
        let sim = try await simulator("40")
        let coord = sim.coord
        revealAll(sim)
        let plates = try XCTUnwrap(coord.boardState.markerHexes["a"])
        XCTAssertEqual(plates.count, 2)
        stand(sim, 0, on: plates[0])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.pendingResult)
        stand(sim, 1, on: plates[1])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// Deep Ruins has a plate a character: two, three or four.
    func testPlatesByCharacterCount() async throws {
        for (party, plates) in [(["brute", "spellweaver"], 2), (["brute", "spellweaver", "cragheart"], 3),
                                (["brute", "spellweaver", "cragheart", "scoundrel"], 4)] {
            let sim = try await simulator("23", characters: party)
            let goal = try XCTUnwrap(sim.coord.scenarioGoal?.occupy)
            revealAll(sim)
            let hexes = sim.coord.platesInPlay(goal).flatMap { sim.coord.boardState.markerHexes[$0] ?? [] }
            XCTAssertEqual(hexes.count, plates, "\(party.count) characters")
            for (index, hex) in hexes.enumerated() { stand(sim, index, on: hex) }
            sim.coord.checkVictoryDefeat(turnEnded: true)
            XCTAssertEqual(sim.coord.pendingResult, .victory, "\(party.count) characters")
        }
    }

    /// Clockwork Cove: a character ending a turn on the last plate.
    func testEndingATurnOnAHexWins() async throws {
        let sim = try await simulator("66")
        revealAll(sim)
        let plate = try XCTUnwrap(sim.coord.boardState.markerHexes["e"]?.first)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult)
        stand(sim, 0, on: try XCTUnwrap(plate.neighbors.first { sim.coord.boardState.isPassable($0) }))
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult, "beside the plate isn't on it")
        stand(sim, 1, on: plate)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// Well of the Unfortunate: beside the well is enough (it can't be stood on).
    func testEndingATurnBesideAHexWins() async throws {
        let sim = try await simulator("69")
        revealAll(sim)
        let well = try XCTUnwrap(sim.coord.boardState.markerHexes["a"]?.first)
        let beside = try XCTUnwrap(well.neighbors.first { sim.coord.boardState.isPassable($0) })
        stand(sim, 0, on: beside)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// Burning Mountain: with the treasure looted, either the altar hex or the way out.
    func testEitherOfTwoWays() async throws {
        for way in ["altar", "entrance"] {
            let sim = try await simulator("82")
            let coord = sim.coord
            let start = coord.boardState.startingLocations
            revealAll(sim)
            let altar = try XCTUnwrap(coord.boardState.markerHexes["g"]?.first)
            stand(sim, 0, on: altar)
            coord.checkVictoryDefeat(turnEnded: true)
            XCTAssertNil(coord.pendingResult, "the treasure isn't looted")
            let chest = try XCTUnwrap(coord.boardState.cells.values.first { $0.treasureID == "62" }?.coord)
            stand(sim, 1, on: chest)
            coord.lootHexes(for: character(sim, 1), coords: [chest], byLootAction: true)
            if way == "entrance" {
                stand(sim, 0, on: start[0])
                coord.checkVictoryDefeat(turnEnded: true)
                XCTAssertNil(coord.pendingResult, "one is still inside")
                stand(sim, 1, on: start[1])
            }
            coord.checkVictoryDefeat(turnEnded: true)
            XCTAssertEqual(coord.pendingResult, .victory, way)
        }
    }

    // MARK: - Rules the data leaves out

    /// Pit of Souls: the tenth Living Bones killed brings the Hungry Soul, at its lettered hex;
    /// killing it wins.
    func testTheHungrySoulComesAfterTenKills() async throws {
        let sim = try await simulator("62")
        let coord = sim.coord
        for _ in 0..<9 { coord.recordMonsterKill(name: "living-bones") }
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertTrue(pieces(sim, named: "hungry-soul").isEmpty)
        coord.recordMonsterKill(name: "living-bones")
        sim.gm.scenarioRulesManager.evaluateRules()
        let soul = try XCTUnwrap(pieces(sim, named: "hungry-soul").first, "it appears")
        XCTAssertEqual(coord.boardState.piecePositions[soul], coord.boardState.markerHexes["c"]?.first)
        XCTAssertNil(coord.pendingResult)
        kill(sim, [soul])
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    // MARK: - The default

    /// A scenario with no goal of its own is still won by killing every enemy with every room
    /// revealed — and one whose goal is only a loss condition as well.
    func testKillEveryEnemyIsStillTheDefault() async throws {
        for index in ["1", "38"] {
            let sim = try await simulator(index)
            kill(sim, pieces(sim))
            sim.coord.checkVictoryDefeat()
            XCTAssertNil(sim.coord.pendingResult, "\(index): rooms are unrevealed")
            revealAll(sim)
            kill(sim, pieces(sim))
            XCTAssertEqual(sim.coord.pendingResult, .victory, index)
            XCTAssertEqual(sim.coord.endReason, .enemiesDefeated, index)
        }
    }
}
