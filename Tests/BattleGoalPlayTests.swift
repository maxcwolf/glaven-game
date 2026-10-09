import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Battle goals in play (GH p.15, 47): two dealt to each character before a scenario, one kept;
/// what the goals need is tracked on the board; a success pays the checkmarks.
@MainActor
final class BattleGoalPlayTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var brute: GameCharacter { gm.game.characters[0] }
    private var bruteID: PieceID { .character(brute.id) }
    private var stats: ScenarioCharacterStats { gm.scenarioStatsManager.stats(for: brute.name) }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
    }

    private func monsters() -> [PieceID] {
        coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
    }

    // MARK: - Dealing

    func testEachCharacterIsDealtTwoGoalsAndKeepsOne() throws {
        gm.scenarioManager.dealBattleGoals()
        let dealt = gm.game.characters.flatMap(\.battleGoalCardIds)
        XCTAssertEqual(dealt.count, 4)
        XCTAssertEqual(Set(dealt).count, 4, "no goal dealt twice")
        XCTAssertFalse(gm.scenarioManager.battleGoalsChosen)
        for character in gm.game.characters { gm.scenarioManager.chooseBattleGoal(1, for: character) }
        XCTAssertTrue(gm.scenarioManager.battleGoalsChosen)
        let goal = try XCTUnwrap(gm.scenarioManager.chosenBattleGoal(of: brute))
        XCTAssertEqual(goal.id, brute.battleGoalCardIds[1])
        XCTAssertFalse(goal.text.isEmpty)
        XCTAssertEqual(PlayerTextTests.lint(goal.text), [])
    }

    // MARK: - Tracking

    func testKillsRecordEliteOverkillExecutionAndTheFirstKiller() throws {
        let target = try XCTUnwrap(monsters().first)
        let entity = try XCTUnwrap(coord.entity(for: target))
        coord.sufferDamage(entity.health + 4, to: target, killer: bruteID)   // from full, 4 spare
        XCTAssertEqual(stats.kills, 1)
        XCTAssertEqual(stats.largestOverkill, 4)
        XCTAssertEqual(stats.executions, 1)
        XCTAssertEqual(gm.scenarioStatsManager.partyStats.firstKiller, brute.name)

        let second = try XCTUnwrap(monsters().first)
        let secondEntity = try XCTUnwrap(coord.entity(for: second))
        coord.sufferDamage(1, to: second, killer: bruteID)
        coord.sufferDamage(secondEntity.health, to: second, killer: .character(gm.game.characters[1].id))
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: "tinkerer").executions, 0, "already wounded")
        XCTAssertEqual(gm.scenarioStatsManager.partyStats.firstKiller, brute.name, "still the first")
        XCTAssertEqual(stats.eliteKills + gm.scenarioStatsManager.stats(for: "tinkerer").eliteKills,
                       [target, second].filter { coord.boardState.eliteStandees.contains($0) }.count)
    }

    func testDroppingBelowHalfHealthBreaksDiehard() {
        coord.sufferDamage(brute.maxHealth / 2 - 1, to: bruteID)
        XCTAssertFalse(stats.droppedBelowHalf, "still at least half")
        coord.sufferDamage(2, to: bruteID)
        XCTAssertTrue(stats.droppedBelowHalf)
    }

    func testDoorsOnACharactersTurnAreTheirs() throws {
        coord.setActing(bruteID)
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen })
        coord.openDoor(at: door.coord)
        XCTAssertEqual(stats.doorsOpened, 1)
    }

    func testARoundWithoutMonstersBreaksAggressor() {
        gm.scenarioStatsManager.advanceRound(monstersPresent: true)
        XCTAssertFalse(gm.scenarioStatsManager.partyStats.roundStartedWithoutMonsters)
        gm.scenarioStatsManager.advanceRound(monstersPresent: false)
        XCTAssertTrue(gm.scenarioStatsManager.partyStats.roundStartedWithoutMonsters)
    }

    /// Regression: the tallies were only cleared for a new campaign, so one scenario's kills
    /// counted toward the next one's goals; and they weren't saved, so Continue lost them.
    func testTalliesBelongToTheScenarioAndAreSaved() throws {
        gm.scenarioStatsManager.recordKill(by: brute.name)
        let scenario = try XCTUnwrap(gm.game.scenario)
        let restored = try XCTUnwrap(scenario.toSnapshot().toRuntime(editionStore: gm.editionStore))
        XCTAssertEqual(restored.stats[brute.name]?.kills, 1, "saved with the scenario")

        gm.completeScenario(success: true)
        let next = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "2" && $0.solo == nil })
        gm.startScenarioOnBoard(next)
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: brute.name).kills, 0, "a fresh scenario starts fresh")
    }

    // MARK: - Results

    /// The results say how each goal went, and Finish pays the checkmarks it shows. Workhorse
    /// counts the experience really gained in the scenario.
    func testTheResultsJudgeTheGoalsAndFinishPaysThem() throws {
        brute.battleGoalCardIds = ["460", "470"]   // Workhorse, Pacifist
        gm.scenarioManager.chooseBattleGoal(0, for: brute)
        brute.experience += 13
        coord.scenarioResult = .victory
        let hero = try XCTUnwrap(coord.scenarioOutcome()?.heroes.first { $0.id == brute.id })
        XCTAssertEqual(hero.battleGoal, ScenarioOutcome.GoalResult(name: "Workhorse", met: true, checks: 1))

        coord.confirmScenarioEnd()
        XCTAssertEqual(brute.battleGoalProgress, 1)
        XCTAssertTrue(brute.battleGoalCardIds.isEmpty, "goals are for one scenario")
    }

    func testALossMeetsNoGoal() throws {
        brute.battleGoalCardIds = ["470", "460"]   // Pacifist: met by doing nothing
        gm.scenarioManager.chooseBattleGoal(0, for: brute)
        coord.scenarioResult = .defeat
        let hero = try XCTUnwrap(coord.scenarioOutcome()?.heroes.first { $0.id == brute.id })
        XCTAssertEqual(hero.battleGoal?.met, false)
        coord.confirmScenarioEnd()
        XCTAssertEqual(brute.battleGoalProgress, 0)
    }

    /// `GOALS_RENDER_OUT=/tmp/g.png swift test --filter testRenderGoalPicker` renders the picker.
    func testRenderGoalPicker() throws {
        guard let out = ProcessInfo.processInfo.environment["GOALS_RENDER_OUT"] else {
            throw XCTSkip("set GOALS_RENDER_OUT to render the picker")
        }
        GlavenFont.registerFonts()
        brute.battleGoalCardIds = ["471", "478"]
        let view = BattleGoalPicker {}.environment(gm).frame(width: 1376, height: 1032)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
