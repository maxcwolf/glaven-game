import XCTest
import SwiftData
@testable import GlavenGameLib

/// The game saves at the start of every round on the board, when a scenario ends, and when the
/// player leaves; Continue puts the scenario back on the board where it was saved; and nothing on
/// the way to the main menu throws the campaign away.
@MainActor
final class SaveAndContinueTests: XCTestCase {

    private struct BoardPicture: Equatable {
        var round: Int
        var positions: [PieceID: HexCoord]
        var health: [String: Int]
        var hands: [String: [Int]]
    }

    private func picture(_ gm: GameManager) -> BoardPicture {
        BoardPicture(round: gm.game.round,
                     positions: gm.boardCoordinator.boardState.piecePositions,
                     health: Dictionary(uniqueKeysWithValues: gm.game.characters.map { ($0.id, $0.health) }),
                     hands: Dictionary(uniqueKeysWithValues: gm.game.characters.map { ($0.id, $0.handCards) }))
    }

    /// Relaunching the app (a new GameManager on the same store) and pressing Continue puts the
    /// scenario back on the board at the start of the saved round, and play carries on from there.
    func testContinueAfterRelaunchResumesTheScenarioAtTheSavedRound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 2)
        XCTAssertEqual(sim.coord.boardPhase, .cardSelection)
        let saved = picture(sim.gm)

        // A save in the middle of the next round (the app going to the background) keeps the
        // round's starting point rather than a half-played turn.
        sim.gm.game.characters[0].health = 1
        sim.gm.saveGame()

        let relaunched = GameManager(modelContainer: sim.gm.modelContainer)
        let summary = try XCTUnwrap(relaunched.autosaveSummary)
        XCTAssertEqual(summary.scenario, "#1 Black Barrow")
        XCTAssertEqual(summary.round, 3)
        XCTAssertEqual(summary.characterNames, ["Brute", "Cragheart", "Scoundrel", "Spellweaver"])

        relaunched.continueGame()
        XCTAssertEqual(relaunched.appPhase, .board)
        XCTAssertEqual(relaunched.boardCoordinator.boardPhase, .cardSelection)
        XCTAssertNotNil(relaunched.boardCoordinator.boardScene, "the board is drawn again")
        XCTAssertEqual(picture(relaunched), saved)

        let resumed = ScenarioSimulator(resuming: relaunched, scenario: "1")
        let outcome = await resumed.play(rounds: 4)
        XCTAssertEqual(resumed.violations, [])
        XCTAssertTrue(outcome != .unfinished || relaunched.game.round >= 4, "play continues after resuming")
    }

    /// Everything that steers play survives a save and load: the difficulty (it sets the next
    /// scenario's level), monsters' initiatives this round (focus ties), a character's traps (the
    /// XP when one is sprung) and an outcome the rules have decided for the end of the round.
    func testASaveKeepsWhatSteersPlay() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)
        let gm = sim.gm, coord = sim.coord
        gm.game.difficulty = .hard
        let monster = try XCTUnwrap(gm.game.monsters.first)
        monster.drawnInitiative = 32
        let trapHex = HexCoord(0, 3)
        coord.characterTraps[trapHex] = (characterID: gm.game.characters[0].id, experience: 2)
        gm.game.scenario?.pendingFinish = "won"

        // As the round checkpoint saves it.
        var saved = gm.game.toSnapshot()
        saved.boardSnapshot = coord.snapshot()
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(saved))
        gm.game.difficulty = .normal
        monster.drawnInitiative = nil
        coord.characterTraps = [:]
        gm.game.scenario?.pendingFinish = nil
        gm.game.restore(from: snapshot, editionStore: gm.editionStore, boardCoordinator: coord)

        XCTAssertEqual(gm.game.difficulty, .hard)
        XCTAssertEqual(gm.game.monsters.first { $0.name == monster.name }?.drawnInitiative, 32)
        XCTAssertEqual(coord.characterTraps[trapHex]?.characterID, gm.game.characters[0].id)
        XCTAssertEqual(coord.characterTraps[trapHex]?.experience, 2)
        XCTAssertEqual(gm.game.scenario?.pendingFinish, "won")
    }

    /// Undo is a town tool: nothing is recorded on the board (a restored snapshot would strand a
    /// turn in progress), and a finished scenario can't be undone from town.
    func testUndoNeverReachesIntoOrAcrossAScenario() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        let gm = sim.gm
        sim.gm.appPhase = .board
        await sim.play(rounds: 2)
        XCTAssertEqual(gm.appPhase, .board)
        XCTAssertFalse(gm.canUndo, "nothing to undo on the board")
        XCTAssertEqual(gm.undoCount, 0, "nothing recorded on the board")
        let health = gm.game.characters.map(\.health)
        gm.undo()
        XCTAssertEqual(gm.game.characters.map(\.health), health)

        gm.completeScenario(success: true)
        XCTAssertEqual(gm.appPhase, .gameSetup)
        XCTAssertFalse(gm.canUndo, "the scenario's end can't be undone")
        XCTAssertEqual(gm.game.completedScenarios, ["gh-1"])

        // In town, undo works as before.
        let brute = try XCTUnwrap(gm.game.characters.first)
        gm.characterManager.setNotes("bought a sword", for: brute)
        XCTAssertTrue(gm.canUndo)
        gm.undo()
        XCTAssertEqual(gm.game.characters.first?.notes, "")
        XCTAssertEqual(gm.game.completedScenarios, ["gh-1"])
    }

    /// Quitting while the characters are being placed keeps the town as the party left it: the
    /// next Continue sets out again from town, and the scenario's setup (item −1 cards, the
    /// events' damage) isn't applied twice.
    func testQuittingBeforeTheFirstRoundSetsOutAgainFromTown() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        brute.items = ["gh-3"]   // Hide Armor: two −1 cards for the scenario
        gm.game.events.nextScenario.damage = 2
        let minusOnes = brute.attackModifierDeck.cards.filter { $0.type == .minus1 }.count
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })

        gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(gm.boardCoordinator.boardPhase, .setup)
        gm.saveAndQuitScenario()
        gm.continueGame()

        XCTAssertEqual(gm.appPhase, .gameSetup, "back in town, ready to set out")
        let again = gm.game.characters[0]
        XCTAssertEqual(again.attackModifierDeck.cards.filter { $0.type == .minus1 }.count, minusOnes)
        XCTAssertEqual(gm.game.events.nextScenario.damage, 2, "the events' damage still waits for the scenario")
        XCTAssertEqual(again.health, again.maxHealth)

        gm.startScenarioOnBoard(scenario)
        let once = gm.game.characters[0]
        XCTAssertEqual(once.health, once.maxHealth - 2, "taken once")
    }

    /// Save & Quit leaves for the main menu; Continue brings the same round back, even after the
    /// app saved again at the menu.
    func testSaveAndQuitThenContinueResumesTheSameRound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 4))
        await sim.play(rounds: 1)
        let saved = picture(sim.gm)

        sim.gm.saveAndQuitScenario()
        XCTAssertEqual(sim.gm.appPhase, .mainMenu)
        XCTAssertNil(sim.coord.scenarioData)
        sim.gm.saveGame()
        XCTAssertEqual(sim.gm.autosaveSummary?.round, 2)

        sim.gm.continueGame()
        XCTAssertEqual(sim.gm.appPhase, .board)
        XCTAssertEqual(picture(sim.gm), saved)
    }

    /// Finishing a scenario saves its rewards straight away, so Continue (or a relaunch) can't
    /// bring back the game from before the scenario ended.
    func testScenarioRewardsAreSavedWhenTheScenarioEnds() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)
        let xpBefore = sim.gm.game.characters.map(\.experience)

        sim.gm.completeScenario(success: true)
        XCTAssertEqual(sim.gm.appPhase, .gameSetup, "back to town")
        XCTAssertNil(sim.gm.roundCheckpoint)
        XCTAssertNil(sim.gm.autosaveSummary?.scenario, "nothing left to resume on the board")

        let relaunched = GameManager(modelContainer: sim.gm.modelContainer)
        relaunched.continueGame()
        XCTAssertEqual(relaunched.appPhase, .gameSetup)
        XCTAssertTrue(relaunched.game.completedScenarios.contains { $0.contains("1") }, "the win is recorded")
        XCTAssertTrue(relaunched.game.partyAchievements.contains("first-steps"), "the scenario's reward is kept")
        for (character, before) in zip(relaunched.game.characters, xpBefore) {
            XCTAssertGreaterThan(character.experience, before, "\(character.name) keeps the bonus XP")
        }
    }

    /// Abandoning a scenario counts as losing it: no completion, characters reset for the next one.
    func testAbandoningAScenarioRecordsALossAndResetsCharacters() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)
        sim.gm.game.characters[0].health = 2

        sim.gm.completeScenario(success: false)
        XCTAssertFalse(sim.gm.game.completedScenarios.contains { $0.contains("1") })
        XCTAssertNil(sim.gm.game.scenario)
        XCTAssertEqual(sim.gm.game.characters[0].health, sim.gm.game.characters[0].maxHealth)
        XCTAssertNotNil(sim.gm.autosaveSummary, "the party is still saved")
    }

    /// Going back to the main menu from the party screen keeps the campaign.
    func testReturningToTheMenuKeepsTheCampaign() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.game.completedScenarios.insert("gh-1")
        gm.appPhase = .gameSetup

        gm.returnToMainMenu()
        XCTAssertEqual(gm.appPhase, .mainMenu)
        XCTAssertEqual(gm.game.completedScenarios, ["gh-1"])
        XCTAssertEqual(gm.autosaveSummary?.characterNames, ["Brute"])

        gm.continueGame()
        XCTAssertEqual(gm.appPhase, .gameSetup)
        XCTAssertEqual(gm.game.characters.map(\.name), ["brute"])
    }

    /// New Game while a scenario is on the board takes the board down, so the next scenario starts.
    func testNewGameTearsDownTheBoardSoTheNextScenarioStarts() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)

        sim.gm.newGame()
        XCTAssertNil(sim.coord.scenarioData)
        XCTAssertNil(sim.coord.boardScene)
        XCTAssertNil(sim.gm.roundCheckpoint)

        sim.gm.setEdition("gh")
        sim.gm.characterManager.addCharacter(name: "brute", edition: "gh")
        sim.gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(sim.gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        sim.gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(sim.gm.appPhase, .board)
        XCTAssertEqual(sim.coord.boardPhase, .setup)
        XCTAssertNotNil(sim.coord.scenarioData)
    }
}
