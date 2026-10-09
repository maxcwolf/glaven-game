import XCTest
import SwiftUI
@testable import GlavenGameLib

/// The board's HUD fits the screen in every phase: nothing is pushed off the top or bottom.
/// (A rigid side column once pushed the top bar and the action card off an iPad screen.)
@MainActor
final class BoardLayoutTests: XCTestCase {

    /// iPad Pro 13" and iPad mini, landscape, minus status bar and home indicator.
    private let screens: [CGSize] = [CGSize(width: 1376, height: 1032 - 44), CGSize(width: 1133, height: 744 - 44)]

    private func assertFits(_ gm: GameManager, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for screen in screens {
            let view = BoardView(coordinator: gm.boardCoordinator).environment(gm)
            let host = NSHostingController(rootView: view)
            let size = host.sizeThatFits(in: screen)
            XCTAssertLessThanOrEqual(size.height, screen.height + 0.5, "\(context): HUD taller than \(screen)", file: file, line: line)
            XCTAssertLessThanOrEqual(size.width, screen.width + 0.5, "\(context): HUD wider than \(screen)", file: file, line: line)
        }
    }

    func testHUDFitsThroughARound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        assertFits(sim.gm, "card selection")
        var checked = Set<String>()
        await sim.play(rounds: 2) {
            let key = "\(sim.coord.boardPhase)-\(sim.coord.activePlayerTurn != nil)"
            guard !checked.contains(key) else { return }
            checked.insert(key)
            self.assertFits(sim.gm, key)
        }
        XCTAssertGreaterThan(checked.count, 1)
    }

    /// Regression: the turn panel showed the whole 240 pt card while one half of it was being
    /// played, so the panel took a third of the screen and the board shrank to fit above it. The
    /// two played cards stay small, with the half being performed lit.
    func testThePlayedCardsStaySmall() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        var checked = false
        await sim.play(rounds: 2) {
            guard !checked, let turn = sim.coord.activePlayerTurn, turn.topCard != nil, turn.bottomCard != nil else { return }
            let view = PlayedCardsView(turn: turn, edition: "gh")
            let size = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: 800, height: 600))
            XCTAssertLessThanOrEqual(size.height, PlayedCardsView.cardHeight + 1)
            XCTAssertLessThanOrEqual(size.width, 260, "two cards side by side, \(size.width) pt")
            checked = true
        }
        XCTAssertTrue(checked)
    }

    /// Regression: the quiet buttons (Swap Cards … Skip Rest of Half) ran out of the turn panel
    /// on an 11-inch-wide layout; they wrap within the width they're given.
    func testTheTurnButtonsStayInsideThePanel() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        var checked = false
        await sim.play(rounds: 2) {
            guard !checked, let turn = sim.coord.activePlayerTurn, !turn.hasActed,
                  turn.phase == .executeTopAction || turn.phase == .executeBottomAction else { return }
            let host = NSHostingController(rootView: TurnChoiceButtons(turn: turn))
            let narrow = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
            let wide = host.sizeThatFits(in: CGSize(width: 2000, height: 1000))
            XCTAssertLessThanOrEqual(narrow.width, 320.5, "wider than the panel: \(narrow.width) pt")
            XCTAssertGreaterThan(narrow.height, wide.height, "wraps onto another row instead")
            checked = true
        }
        XCTAssertTrue(checked)
    }

    func testHalfHeadings() {
        XCTAssertEqual(BoardView.halfHeading(phase: .turnComplete, top: nil, bottom: nil), "Turn done")
        for phase in [PlayerTurnPhase.executeTopAction, .executeBottomAction, .turnComplete] {
            XCTAssertEqual(PlayerTextTests.lint(BoardView.halfHeading(phase: phase, top: nil, bottom: nil)), [])
        }
    }

    func testHUDFitsDuringSetupWithAFullParty() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        for name in ["brute", "tinkerer", "spellweaver", "cragheart"] {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "2" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        assertFits(gm, "setup, four characters")
    }
}

/// The party screen keeps its rows still as characters are added.
@MainActor
final class PartyScreenLayoutTests: XCTestCase {

    /// Regression: adding the first character inserted the scenario-level line, shifting every
    /// class row down so the next tap hit the wrong class.
    func testAddingTheFirstCharacterDoesNotMoveTheClassList() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        func lineHeight() -> CGFloat {
            let line = ScenarioLevelLine(text: GameSetupView.difficultyHint(for: gm))
            return NSHostingController(rootView: line).sizeThatFits(in: CGSize(width: 400, height: 200)).height
        }
        let empty = GameSetupView.difficultyHint(for: gm)
        let before = lineHeight()
        XCTAssertGreaterThan(before, 8, "the line takes space before any character is added")
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        XCTAssertNotEqual(GameSetupView.difficultyHint(for: gm), empty)
        XCTAssertEqual(PlayerTextTests.lint(GameSetupView.difficultyHint(for: gm)), [])
        XCTAssertEqual(lineHeight(), before, accuracy: 0.5, "and the same space after")
    }

    /// The hint says the scenario level once, then what the difficulty does (iPad playthrough
    /// 2026-10-09: "Scenario level 0 · Scenario level −1 (min 0).").
    func testTheDifficultyHintDoesNotRepeatItself() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        for mode in DifficultyMode.allCases {
            gm.game.difficulty = mode
            let hint = GameSetupView.difficultyHint(for: gm)
            XCTAssertEqual(hint.components(separatedBy: "Scenario level").count, 2, hint)
            XCTAssertTrue(hint.contains(mode.shortLabel == "V.Hard" ? "Very hard" : mode.shortLabel), hint)
        }
    }

    /// Regression: FlowLayout reported all the width it was offered, so the turn controls'
    /// buttons stretched the action panel across the screen, leaving an empty block beside them.
    func testAFlowIsAsWideAsItsRows() {
        let buttons = FlowLayout(spacing: 8) {
            ForEach(["Swap Cards", "Bottom First"], id: \.self) { Text($0).frame(width: 100, height: 30) }
        }
        let size = NSHostingController(rootView: buttons.fixedSize(horizontal: false, vertical: true))
            .sizeThatFits(in: CGSize(width: 1000, height: 400))
        XCTAssertEqual(size.width, 208, accuracy: 0.5, "two buttons and a gap, not the 1000 offered")
        XCTAssertEqual(size.height, 30, accuracy: 0.5)
        let wrapped = NSHostingController(rootView: buttons).sizeThatFits(in: CGSize(width: 150, height: 400))
        XCTAssertEqual(wrapped.height, 68, accuracy: 0.5, "wraps to two rows when narrow")
    }
}

/// The board's dialogs are drawn in its own look: its fonts, colours and buttons, not the
/// system's steppers, pickers and caption styles (iPad playthrough 2026-10-09: the rest
/// dialogs and the gold split were still in the old style).
@MainActor
final class BoardDialogStyleTests: XCTestCase {
    func testTheRestAndRewardDialogsUseTheBoardsLook() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["GlavenGame/Board/RestSheets.swift", "GlavenGame/Board/RewardChoicesView.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for old in ["GlavenTheme", " Stepper(", " Picker(", ".font(.caption", ".font(.title", ".font(.headline", ".foregroundStyle(.orange"] {
                XCTAssertFalse(source.contains(old), "\(file) uses \(old)")
            }
        }
        let board = try String(contentsOf: root.appendingPathComponent("GlavenGame/Board/BoardView.swift"), encoding: .utf8)
        XCTAssertFalse(board.contains("func shortRestOverlay"), "the old rest overlays are gone")
        XCTAssertFalse(board.contains("func longRestOverlay"))
    }
}
