import XCTest
@testable import GlavenGameLib

/// Full scenarios played to the end by a tactical party, with no HP or card tweaks. Every run must
/// end in a victory or defeat the rules allow, with no rule violation along the way (every
/// attack, move and board state is checked by the simulator).
@MainActor
final class PlaythroughTests: XCTestCase {

    struct Run {
        let index: String
        let seed: UInt64
        let outcome: ScenarioSimulator.Outcome
        let rounds: Int
        let problems: [String]
    }

    /// Play each scenario to its end (at most `maxRounds` rounds).
    func playthrough(_ index: String, seed: UInt64, party: [String]? = nil, difficulty: DifficultyMode = .normal,
                     maxRounds: Int = 60) async throws -> Run {
        var options = ScenarioSimulator.Options(difficulty: difficulty, seed: seed)
        if let party { options.characters = party }
        let sim = try ScenarioSimulator(scenario: index, options: options)
        let outcome = await sim.play(rounds: maxRounds)
        return Run(index: index, seed: seed, outcome: outcome, rounds: sim.gm.game.round,
                   problems: sim.violations + [sim.outcomeProblem()].compactMap { $0 })
    }

    /// The scenarios every test run plays to the end: the campaign opening, ranged and elemental
    /// monsters, summoners, bosses and multi-room maps, with two different parties.
    func testCoreScenariosPlayToALegitimateEnd() async throws {
        let fourParty = ["brute", "spellweaver", "cragheart", "scoundrel"]
        let threeParty = ["tinkerer", "mindthief", "brute"]
        var runs: [Run] = []
        for index in ["1", "2", "3", "4", "5", "8"] {
            runs.append(try await playthrough(index, seed: 1, party: fourParty))
        }
        for index in ["1", "13"] {
            runs.append(try await playthrough(index, seed: 2, party: threeParty))
        }
        for run in runs {
            XCTAssertNotEqual(run.outcome, .unfinished, "scenario \(run.index) seed \(run.seed) ended")
            XCTAssertTrue(run.problems.isEmpty, "scenario \(run.index) seed \(run.seed):\n" + run.problems.prefix(10).joined(separator: "\n"))
        }
    }

    /// Every main GH scenario with a map, several seeds each. Slow — enabled with SIM_ALL=1
    /// (SIM_SEEDS=n for more seeds per scenario).
    func testAllScenariosPlayToALegitimateEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SIM_ALL"] != nil else { throw XCTSkip("set SIM_ALL=1") }
        let seeds = UInt64(env["SIM_SEEDS"] ?? "2") ?? 2
        var runs: [Run] = []
        // Every scenario with a map, and the random dungeon, drawn anew each seed.
        for index in (1...95).map(String.init) + ["rnd"] {
            guard ["rnd", "55"].contains(index) || ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
            for seed in 1...seeds {
                // Odd seeds play on Normal, even seeds on Easy (more victories, so the late rooms,
                // bosses and scenario goals get played too).
                let run = try await playthrough(index, seed: seed, difficulty: seed % 2 == 0 ? .easy : .normal)
                runs.append(run)
                print("PLAYTHROUGH scenario \(index) seed \(seed)\(seed % 2 == 0 ? " (easy)" : ""): \(run.outcome) in round \(run.rounds)"
                      + (run.problems.isEmpty ? "" : " — \(run.problems.count) problem(s)"))
            }
        }
        let victories = runs.filter { $0.outcome == .victory }.count
        print("PLAYTHROUGH \(runs.count) runs: \(victories) victories, \(runs.count - victories) defeats/unfinished")
        for run in runs {
            XCTAssertNotEqual(run.outcome, .unfinished, "scenario \(run.index) seed \(run.seed) ended")
            XCTAssertTrue(run.problems.isEmpty, "scenario \(run.index) seed \(run.seed):\n" + run.problems.prefix(10).joined(separator: "\n"))
        }
    }

    // MARK: - Playthroughs that end in victory

    struct VeteranRun {
        let index: String
        let seed: UInt64
        let party: [String]
        let outcome: ScenarioSimulator.Outcome
        let rounds: Int
        let ownGoal: Bool
        let ending: String
        let problems: [String]
    }

    /// Play a scenario with a veteran party and the policy that plays to win.
    func veteranPlaythrough(_ index: String, seed: UInt64 = 1, party: [String] = ScenarioSimulator.Options.veterans,
                            scenarioLevel: Int = 0, maxRounds: Int = 60) async throws -> VeteranRun {
        let sim = try ScenarioSimulator(scenario: index, options: .veteranParty(party, seed: seed, scenarioLevel: scenarioLevel),
                                        policy: VeteranPolicy())
        let outcome = await sim.play(rounds: maxRounds)
        return VeteranRun(index: index, seed: seed, party: party, outcome: outcome, rounds: sim.gm.game.round,
                          ownGoal: sim.coord.scenarioGoal?.replacesKillAll ?? false,
                          ending: sim.coord.endReason.map { "\($0)" } ?? "?",
                          problems: sim.violations + [sim.outcomeProblem()].compactMap { $0 })
    }

    /// Six scenarios won from the first round to the last by the veteran party, each a different
    /// way of winning, with every attack, move, turn, rest and coin checked along the way:
    /// #1 Black Barrow (kill every enemy, three rooms), #13 Temple of the Seer (kill every
    /// enemy), #9 Diamond Mine (kill the Merciless Overseer — a boss — and loot the treasure),
    /// #94 Vermling Nest (kill every enemy and loot the treasure tile), #25 Icecrag Ascent (every
    /// character escapes through the exit) and #51 The Void (kill the Gloom, a boss).
    func testTheVeteranPartyWinsSixKindsOfScenario() async throws {
        let placements = ScenarioPlacementStore.shared
        func goal(_ index: String) -> ScenarioPlacements.Goal? { placements.placements(for: index, edition: "gh")?.goal }
        // The scenarios are what the test says they are.
        XCTAssertNil(goal("1"), "#1 has no goal of its own: it is won by killing every enemy")
        XCTAssertNil(goal("13"))
        XCTAssertEqual(goal("9")?.kill, ["merciless-overseer"])
        XCTAssertNotNil(goal("9")?.loot)
        XCTAssertNotNil(goal("94")?.loot)
        XCTAssertNotNil(goal("25")?.escape)
        XCTAssertEqual(goal("51")?.kill, ["the-gloom"])

        // (A seed each with which this party wins: about one game in three is lost to the cards.)
        for (index, seed) in [("1", UInt64(1)), ("13", 1), ("9", 1), ("94", 1), ("25", 2), ("51", 1)] {
            let run = try await veteranPlaythrough(index, seed: seed)
            XCTAssertEqual(run.outcome, .victory, "scenario \(index) is won (it ended in round \(run.rounds): \(run.ending))")
            XCTAssertTrue(run.problems.isEmpty, "scenario \(index):\n" + run.problems.prefix(10).joined(separator: "\n"))
        }
    }

    /// Every main scenario with the two veteran parties (SIM_ALL=1; SIM_SEEDS=n seeds each,
    /// default 1; ~3 min). No violation in any game, every game ends, and the party wins a share
    /// that shows the late rooms, the bosses and the scenarios' own goals are really played:
    /// at commit 22c35bc the Brute, Sunkeeper and Berserker win 59 of 94 scenarios on seed 1 and
    /// 26 of the 30 that are won by killing every enemy.
    func testVeteranPartiesWinMostScenarios() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SIM_ALL"] != nil || env["SIM_WIN"] != nil else { throw XCTSkip("set SIM_ALL=1") }
        let seeds = UInt64(env["SIM_SEEDS"] ?? "1") ?? 1
        let from = Int(env["SIM_FROM"] ?? "1") ?? 1, to = Int(env["SIM_TO"] ?? "95") ?? 95
        var parties = [ScenarioSimulator.Options.veterans, ScenarioSimulator.Options.veteransWithAScoundrel]
        if let party = env["SIM_PARTY"] { parties = [party.split(separator: ",").map(String.init)] }
        let level = Int(env["SIM_LEVEL"] ?? "0") ?? 0
        var runs: [VeteranRun] = []
        for party in parties {
            for number in from...to {
                let index = String(number)
                guard ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
                for seed in 1...seeds {
                    let run = try await veteranPlaythrough(index, seed: seed, party: party, scenarioLevel: level)
                    runs.append(run)
                    print("VETERAN \(party.joined(separator: "+")) scenario \(index) seed \(seed) [\(run.ownGoal ? "own goal" : "kill all")]: "
                          + "\(run.outcome) in round \(run.rounds)" + (run.outcome == .victory ? "" : " — \(run.ending)")
                          + (run.problems.isEmpty ? "" : " — \(run.problems.count) problem(s): \(run.problems.prefix(3))"))
                }
            }
        }
        for party in parties {
            let own = runs.filter { $0.party == party }
            let won = own.filter { $0.outcome == .victory }
            let killAll = own.filter { !$0.ownGoal }
            print("VETERAN \(party.joined(separator: "+")): \(won.count) of \(own.count) won; "
                  + "kill-all scenarios \(killAll.filter { $0.outcome == .victory }.count) of \(killAll.count)")
            guard from == 1, to == 95 else { continue }
            XCTAssertGreaterThanOrEqual(won.count * 2, own.count, "\(party): at least half of all scenarios are won")
            if party == ScenarioSimulator.Options.veterans {
                XCTAssertGreaterThanOrEqual(killAll.filter { $0.outcome == .victory }.count * 4, killAll.count * 3,
                                            "three in four of the kill-everything scenarios are won")
            }
        }
        for run in runs {
            XCTAssertNotEqual(run.outcome, .unfinished, "scenario \(run.index) seed \(run.seed) ended")
            XCTAssertTrue(run.problems.isEmpty, "\(run.party) scenario \(run.index) seed \(run.seed):\n" + run.problems.prefix(10).joined(separator: "\n"))
        }
    }

    /// The same seed replays the same game; another seed plays a different one.
    func testSeededGamesReplayExactly() async throws {
        func transcript(seed: UInt64) async throws -> [String] {
            let sim = try ScenarioSimulator(scenario: "2", options: .init(seed: seed))
            await sim.play(rounds: 4)
            return sim.transcript
        }
        let first = try await transcript(seed: 7)
        let again = try await transcript(seed: 7)
        let other = try await transcript(seed: 8)
        XCTAssertEqual(first, again, "same seed, same game")
        XCTAssertNotEqual(first, other, "different seed, different game")
    }

    /// Diamond Mine, where the Merciless Overseer has every Scout act again (MON-11): a Scout
    /// that attacks on the turn the Overseer gives it and again on its own has made two attacks
    /// with two abilities, also when it is the only Scout to act on either turn. (The ledger
    /// counted them as one ability attacking twice: audit N12, seeds 2 and 3.)
    func testAScoutsExtraTurnIsATurnOfItsOwn() async throws {
        for seed in [UInt64(2), 3] {
            let sim = try ScenarioSimulator(scenario: "9", options: .veteranParty(ScenarioSimulator.Options.veterans, seed: seed, scenarioLevel: 0),
                                            policy: VeteranPolicy())
            _ = await sim.play(rounds: 30)
            XCTAssertTrue(sim.transcript.contains { $0.hasSuffix("act again") }, "seed \(seed): the Overseer's special was played")
            XCTAssertTrue(sim.violations.isEmpty, "seed \(seed): " + sim.violations.joined(separator: "\n"))
        }
    }

    /// Overgrown Graveyard with the four veterans: graves are dug with movement, and a corpse let
    /// out in the middle of a round acts straight after the turn that dug it up when its card's
    /// initiative has passed (MOV-9) — which the ledger must take for an arrival, also when no
    /// one had attacked or moved yet that round.
    func testACorpseDugUpMidRoundIsAnArrival() async throws {
        let sim = try ScenarioSimulator(scenario: "75", options: .veteranParty(["brute", "scoundrel", "sun", "lightning"], seed: 1, scenarioLevel: 0),
                                        policy: VeteranPolicy())
        _ = await sim.play(rounds: 30)
        XCTAssertTrue(sim.transcript.contains { $0.contains("digging") }, "the party digs")
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    /// Print a seeded playthrough: SIM_SCENARIO=<index> [SIM_SEED=n] [SIM_DIFFICULTY=easy] [SIM_ROUNDS=n] [SIM_PARTY=a,b]
    /// [SIM_VETERAN=1 for the ninth-level party at scenario level 0]
    /// [SIM_OUT=path to write the transcript to instead of printing it].
    func testDebugPlaythrough() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let index = env["SIM_SCENARIO"] else { throw XCTSkip("set SIM_SCENARIO") }
        var options = ScenarioSimulator.Options(seed: UInt64(env["SIM_SEED"] ?? "1") ?? 1)
        if env["SIM_DIFFICULTY"] == "easy" { options.difficulty = .easy }
        if let level = env["SIM_LEVEL"].flatMap(Int.init) { options.characterLevel = level }
        if let party = env["SIM_PARTY"] { options.characters = party.split(separator: ",").map(String.init) }
        if env["SIM_VETERAN"] != nil {
            options = .veteranParty(env["SIM_PARTY"] == nil ? ScenarioSimulator.Options.veterans : options.characters,
                                    seed: options.seed ?? 1, scenarioLevel: env["SIM_LEVEL"].flatMap(Int.init) ?? 0)
        }
        let sim = try ScenarioSimulator(scenario: index, options: options, policy: env["SIM_VETERAN"] != nil ? VeteranPolicy() : nil)
        let outcome = await sim.play(rounds: Int(env["SIM_ROUNDS"] ?? "60") ?? 60)
        let report = sim.transcript + sim.violations.map { "VIOLATION \($0)" }
            + [sim.outcomeProblem().map { "PROBLEM \($0)" } ?? "", "OUTCOME \(outcome) round \(sim.gm.game.round)"]
        if let path = env["SIM_OUT"] {
            try report.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            report.forEach { print("LOG", $0) }
        }
    }
}
