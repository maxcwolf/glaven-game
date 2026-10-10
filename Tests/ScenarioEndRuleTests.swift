import XCTest
@testable import GlavenGameLib

/// The end of a scenario (rulebook pp. 33, 49 and the FAQ; gh-rules.md END-1 … END-3), in Black
/// Barrow played by the real turn loop: the round is played out once the goal is met, a goal met
/// in the round the last character is exhausted is a loss, and what the party takes home.
@MainActor
final class ScenarioEndRuleTests: XCTestCase {

    private var sim: ScenarioSimulator!
    private var coord: BoardCoordinator { sim.coord }
    private var game: GameState { sim.gm.game }

    /// Two characters of `level` play Black Barrow. In the second round, as soon as a character
    /// has the board, every room is opened and every monster killed — the goal is met in that
    /// round — and `then` is run; the round is then played out.
    private func playWithTheGoalMetInRoundTwo(characterLevel level: Int = 1, then: @escaping () -> Void = {}) async throws {
        sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "tinkerer"], characterLevel: level, seed: 6))
        var met = false
        await sim.play(rounds: 12) {
            guard !met, self.game.round == 2, self.coord.boardPhase == .execution, self.coord.activePlayerTurn != nil else { return }
            met = true
            var opened = 0
            while let door = self.coord.boardState.doors.first(where: { !$0.isOpen }), opened < 10 {
                self.coord.openDoor(at: door.coord)
                opened += 1
            }
            for piece in self.coord.boardState.piecePositions.keys.sorted() {
                if case .monster = piece { self.coord.sufferDamage(999, to: piece) }
            }
            XCTAssertEqual(self.coord.pendingResult, .victory, "every enemy dead, every room open: the goal is met")
            XCTAssertNil(self.coord.scenarioResult, "but nothing is declared in mid-round")
            then()
        }
        XCTAssertTrue(met, "the second round was reached")
    }

    /// END-1 (p.33): "once a scenario's success or failure conditions are triggered, the
    /// remainder of the round is played out" — the win is declared when that round ends.
    func testAGoalMetIsAWinOnlyWhenTheRoundHasBeenPlayedOut() async throws {
        try await playWithTheGoalMetInRoundTwo()
        XCTAssertEqual(coord.scenarioResult, .victory)
        XCTAssertEqual(game.round, 2, "at the end of the round it was met in")
        XCTAssertTrue(coord.turnLog.contains { $0.message == "Round 2 complete" }, "which was played to its end")
        XCTAssertNil(sim.outcomeProblem())
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    /// END-1 (FAQ): if the last character is exhausted in the round the goal was met, the
    /// scenario is lost.
    func testAGoalMetInTheRoundTheLastCharacterIsExhaustedIsALoss() async throws {
        try await playWithTheGoalMetInRoundTwo {
            for character in self.game.characters { self.coord.sufferDamage(999, to: .character(character.id)) }
        }
        XCTAssertEqual(coord.scenarioResult, .defeat)
        XCTAssertEqual(game.round, 2)
    }

    /// END-3 (p.49): on a success every character gains 4 + 2L bonus experience — exhausted or
    /// not — and END-2: keeps the experience and money collected. Level 5 characters play at
    /// scenario level 3: 10 experience.
    func testAWinGivesFourPlusTwiceTheLevelInExperienceToEveryone() async throws {
        try await playWithTheGoalMetInRoundTwo(characterLevel: 5) {
            let tinkererID = self.game.characters.first { $0.name == "tinkerer" }?.id ?? ""
            // Exhausted in the last round: still rewarded.
            self.coord.sufferDamage(999, to: .character(tinkererID))
        }
        XCTAssertEqual(game.level, 3)
        let brute = try XCTUnwrap(game.characters.first { $0.name == "brute" })
        let tinkerer = try XCTUnwrap(game.characters.first { $0.name == "tinkerer" })
        XCTAssertTrue(tinkerer.exhausted)
        XCTAssertEqual(coord.scenarioResult, .victory)
        let experience = [brute.experience, tinkerer.experience], gold = [brute.loot, tinkerer.loot]

        coord.confirmScenarioEnd()
        XCTAssertEqual([brute.experience, tinkerer.experience], experience.map { $0 + 10 })
        XCTAssertEqual([brute.loot, tinkerer.loot], gold, "money looted is kept; nothing more is paid")
        XCTAssertEqual(game.completedScenarios.count, 1, "Black Barrow is completed")
        XCTAssertFalse(tinkerer.exhausted, "and everyone is back on their feet")
        XCTAssertEqual(tinkerer.health, tinkerer.maxHealth)
    }

    /// END-2, END-3: a loss gives no bonus experience, and takes nothing collected away: the
    /// gold of a token looted before the end stays (3 a token at level 3).
    func testALossGivesNoBonusAndKeepsWhatWasCollected() async throws {
        sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "tinkerer"], characterLevel: 5, seed: 6))
        let brute = try XCTUnwrap(game.characters.first { $0.name == "brute" })
        let tinkerer = try XCTUnwrap(game.characters.first { $0.name == "tinkerer" })
        let hex = try XCTUnwrap(sim.position(.character(brute.id)))
        coord.boardState.placeLoot(at: hex, count: 2)
        let gold = brute.loot, experience = [brute.experience, tinkerer.experience]
        coord.lootAtEndOfTurn(brute.id)
        XCTAssertEqual(brute.loot, gold + 6)

        coord.sufferDamage(999, to: .character(brute.id))
        coord.sufferDamage(999, to: .character(tinkerer.id))
        XCTAssertEqual(coord.scenarioResult, .defeat, "every character exhausted")
        coord.confirmScenarioEnd()
        XCTAssertEqual([brute.experience, tinkerer.experience], experience, "no bonus experience")
        XCTAssertEqual(brute.loot, gold + 6, "the money is kept")
        XCTAssertTrue(game.completedScenarios.isEmpty)
        XCTAssertTrue(brute.lostCards.isEmpty && !brute.exhausted, "cards and hit points come back either way")
    }
}
