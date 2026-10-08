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
        for number in 1...95 {
            let index = String(number)
            guard ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
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

    /// Print a seeded playthrough: SIM_SCENARIO=<index> [SIM_SEED=n] [SIM_DIFFICULTY=easy] [SIM_ROUNDS=n] [SIM_PARTY=a,b]
    /// [SIM_OUT=path to write the transcript to instead of printing it].
    func testDebugPlaythrough() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let index = env["SIM_SCENARIO"] else { throw XCTSkip("set SIM_SCENARIO") }
        var options = ScenarioSimulator.Options(seed: UInt64(env["SIM_SEED"] ?? "1") ?? 1)
        if env["SIM_DIFFICULTY"] == "easy" { options.difficulty = .easy }
        if let level = env["SIM_LEVEL"].flatMap(Int.init) { options.characterLevel = level }
        if let party = env["SIM_PARTY"] { options.characters = party.split(separator: ",").map(String.init) }
        let sim = try ScenarioSimulator(scenario: index, options: options)
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
