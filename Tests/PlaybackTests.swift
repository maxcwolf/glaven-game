import XCTest
@testable import GlavenGameLib

/// Pause and fast-forward for the turns that play themselves (monsters, summons, escorts).
@MainActor
final class PlaybackTests: XCTestCase {

    func testFastForwardShortensThePausesAndQuickensTheBoard() throws {
        let base = BoardCoordinator.baseTurnDelayNanoseconds
        XCTAssertEqual(BoardCoordinator.beatNanoseconds(base: base, factor: 1, fastForward: false), base)
        XCTAssertEqual(BoardCoordinator.beatNanoseconds(base: base, factor: 2, fastForward: true), base / 2)

        let gm = try SaveAndContinueTestsSupport.manager()
        gm.settingsManager.animationSpeed = 2
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        XCTAssertEqual(coord.boardScene?.speed, 0.5)
        coord.setFastForward(true)
        XCTAssertEqual(coord.boardScene?.speed, 2, "four times the Animation Speed setting's pace")
        coord.setFastForward(false)
        XCTAssertEqual(coord.boardScene?.speed, 0.5)
    }

    /// Paused, the monsters stop before their next step and nothing more happens until resumed;
    /// then the round plays on. Pause and fast-forward both end when a character's turn comes.
    func testPauseHoldsTheMonstersUntilResumed() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2, autoResolvePrompts: true))
        let coord = sim.coord
        var pausedSteps = 0
        var logWhilePaused: Int?
        var sawPausedText = false
        var resumed = false
        // Pause as a monster starts to move, as a tap on Pause would mid-turn.
        let checkMove = coord.moveObserver
        coord.moveObserver = { piece, path, style in
            checkMove?(piece, path, style)
            if case .monster = piece, !resumed, pausedSteps == 0, !coord.isPaused {
                coord.setPaused(true)
                coord.setFastForward(true)
            }
        }
        await sim.play(rounds: 2) {
            guard coord.isPaused else { return }
            pausedSteps += 1
            sawPausedText = sawPausedText || coord.instruction(for: coord.interactionMode)?.detail == BoardCoordinator.pausedDetail
            // A few steps for the turn to reach its next step, then it must hold still.
            if pausedSteps == 3 { logWhilePaused = coord.turnLog.count }
            if pausedSteps > 3 { XCTAssertEqual(coord.turnLog.count, logWhilePaused, "the turn went on while paused") }
            if pausedSteps == 40 {
                XCTAssertTrue(coord.isAutomatedTurn, "still the monsters' turn")
                coord.setPaused(false)
                resumed = true
            }
        }
        XCTAssertTrue(resumed, "a monster turn was paused")
        XCTAssertTrue(sawPausedText)
        XCTAssertGreaterThanOrEqual(sim.gm.game.round, 2, "the round played on after resuming")
        XCTAssertFalse(coord.isFastForward, "back to the normal pace once the player had the board")
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    /// Leaving the board lets a paused turn go (it would otherwise wait forever).
    func testLeavingTheBoardReleasesAPausedTurn() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        let coord = sim.coord
        coord.setPaused(true)
        var done = false
        Task { @MainActor in
            await coord.beat()
            done = true
        }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(done, "held by the pause")
        coord.exitBoard()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(done)
        XCTAssertFalse(coord.isPaused)
    }
}
