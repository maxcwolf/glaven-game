import XCTest
@testable import GlavenGameLib

/// Seeded games compared turn by turn against recorded transcripts in `Tests/Golden/`. The
/// recordings were checked by hand against the rulebook (monster focus and movement, attack values
/// and modifiers, conditions, elements, card piles), so any change to how a turn plays out shows
/// up here as a diff.
///
/// After an intended rules change, re-record with `GOLDEN_RECORD=1 swift test --filter
/// GoldenTurnLogTests`, then review the diff of `Tests/Golden/` like any other code change.
@MainActor
final class GoldenTurnLogTests: XCTestCase {

    private func assertMatchesGolden(_ name: String, scenario: String, seed: UInt64, party: [String]? = nil,
                                     rounds: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        var options = ScenarioSimulator.Options(seed: seed)
        if let party { options.characters = party }
        let sim = try ScenarioSimulator(scenario: scenario, options: options)
        await sim.play(rounds: rounds)
        XCTAssertEqual(sim.violations, [], "rule violations in \(name)", file: file, line: line)
        let actual = sim.transcript.joined(separator: "\n") + "\n"

        let url = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
            .appendingPathComponent("Golden/\(name).txt")
        if ProcessInfo.processInfo.environment["GOLDEN_RECORD"] != nil {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            print("Recorded \(url.path)")
            return
        }
        let expected = try String(contentsOf: url, encoding: .utf8)
        guard expected != actual else { return }
        let expectedLines = expected.components(separatedBy: "\n"), actualLines = actual.components(separatedBy: "\n")
        let index = zip(expectedLines, actualLines).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(expectedLines.count, actualLines.count)
        let context = { (lines: [String]) in lines[max(0, index - 3)..<min(lines.count, index + 3)].joined(separator: "\n") }
        XCTFail("""
            \(name) differs from Golden/\(name).txt at line \(index + 1).
            Expected:
            \(context(expectedLines))
            Actual:
            \(context(actualLines))
            If the change is intended, re-record with GOLDEN_RECORD=1 and review the diff.
            """, file: file, line: line)
    }

    /// Black Barrow: bandit guards' focus, movement and ranged/melee card values, shield,
    /// poison, strengthen, money tokens, short rests.
    func testScenario1BlackBarrow() async throws {
        try await assertMatchesGolden("s1-black-barrow", scenario: "1", seed: 1, rounds: 3)
    }

    /// Barrow Lair: bandit archers at range, the Bandit Commander boss and its summoned living
    /// bones, traps.
    func testScenario2BarrowLair() async throws {
        try await assertMatchesGolden("s2-barrow-lair", scenario: "2", seed: 3, rounds: 3)
    }

    /// Crypt of the Damned with a summoning party: character summons acting before their
    /// summoner, cultists' summons and heals, elements.
    func testScenario4CryptWithSummoners() async throws {
        try await assertMatchesGolden("s4-crypt-summoners", scenario: "4", seed: 5,
                                      party: ["tinkerer", "mindthief", "spellweaver"], rounds: 3)
    }
}
