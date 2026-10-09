import XCTest
import SwiftData
@testable import GlavenGameLib

/// The board is readable and speakable: no text below 11 points, every control says what it
/// does to VoiceOver, and every figure on the board has a spoken description.
@MainActor
final class BoardAccessibilityTests: XCTestCase {

    /// The board's Swift sources (the ability card replica scales its printed text with the card,
    /// so it's exempt from the floor).
    private func boardSources(excluding exempt: Set<String> = []) throws -> [(name: String, text: String)] {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("GlavenGame/Board")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".swift") && !exempt.contains($0) }
            .sorted()
            .map { ($0, try String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8)) }
    }

    /// Regression: the HUD had 31 fixed font sizes from 7 to 10 points.
    func testNoBoardTextIsSmallerThanElevenPoints() throws {
        let tooSmall = try NSRegularExpression(pattern: #"BoardTheme\.font\(size: *([0-9.]+)"#)
        for (name, text) in try boardSources(excluding: ["AbilityCardView.swift"]) {
            XCTAssertFalse(text.contains(".font(.system(size:"),
                           "\(name): fixed sizes go through BoardTheme.font, which keeps the 11 pt floor")
            for match in tooSmall.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let size = Double((text as NSString).substring(with: match.range(at: 1))) ?? 0
                XCTAssertGreaterThanOrEqual(size, Double(BoardTheme.minimumTextSize), "\(name): \(size) pt")
            }
        }
    }

    /// Every button and tappable view on the board has text or an accessibility label, so
    /// VoiceOver never announces just "button".
    func testEveryBoardControlSaysWhatItDoes() throws {
        let control = try NSRegularExpression(pattern: #"Button\s*\{|Button\(action:|Menu\s*\{|\.onTapGesture"#)
        for (name, text) in try boardSources() {
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard control.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                // A tap modifier follows the view it's on, so look above it too.
                let start = line.contains(".onTapGesture") ? max(0, index - 12) : index
                let block = lines[start..<min(lines.count, index + 18)].joined(separator: "\n")
                let speaks = ["Text(", "Label(", "Button(\"", "accessibilityLabel", "accessibilityHidden"]
                    .contains { block.contains($0) }
                XCTAssertTrue(speaks, "\(name):\(index + 1) has no text or accessibility label: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    /// A view made tappable with `.onTapGesture` is a button to VoiceOver too (a plain tap
    /// gesture isn't announced as one): the card selection's cards weren't.
    func testTappableViewsAreButtons() throws {
        for (name, text) in try boardSources() {
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".onTapGesture") {
                let block = lines[index..<min(lines.count, index + 8)].joined(separator: "\n")
                let isButton = block.contains(".isButton") || block.contains("accessibilityHidden")
                   
                XCTAssertTrue(isButton, "\(name):\(index + 1) is tappable but not a button to VoiceOver")
            }
        }
    }

    /// Each figure on the board is described: who it is, its rank, its health and conditions.
    func testFiguresHaveSpokenDescriptions() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let scene = try XCTUnwrap(coord.boardScene)
        let monster = try XCTUnwrap(coord.boardState.piecePositions.keys
            .filter { if case .monster = $0 { return true }; return false }.sorted().first)
        coord.applyCondition(.stun, to: monster)
        let entity = try XCTUnwrap(coord.entity(for: monster))

        let spoken = try XCTUnwrap(scene.pieceNode(for: monster)?.spokenDescription)
        XCTAssertTrue(spoken.hasPrefix(coord.name(monster)), spoken)
        XCTAssertTrue(spoken.contains("\(entity.health) of \(entity.maxHealth) health"), spoken)
        XCTAssertTrue(spoken.hasSuffix("Stun"), spoken)
        for piece in coord.boardState.piecePositions.keys {
            let text = try XCTUnwrap(scene.pieceNode(for: piece)?.spokenDescription)
            XCTAssertEqual(PlayerTextTests.lint(text), [], text)
        }
    }

    // MARK: - Choosing without seeing the board

    private func boardWithBrute() throws -> (GameManager, BoardCoordinator, PieceID) {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        retained.append(gm)
        gm.setEdition("gh")
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = PieceID.character(gm.game.characters[0].id)
        coord.boardState.placePiece(brute, at: HexCoord(3, 3))
        return (gm, coord, brute)
    }

    /// The coordinator holds the game manager weakly; keep it alive for the test.
    private var retained: [GameManager] = []

    func testDirectionsFollowTheMapAsDrawn() {
        let origin = HexCoord(3, 3)
        XCTAssertEqual(BoardCoordinator.direction(from: origin, to: HexCoord(4, 3)), "east")
        XCTAssertEqual(BoardCoordinator.direction(from: origin, to: HexCoord(2, 3)), "west")
        XCTAssertEqual(Set(origin.neighbors.map { BoardCoordinator.direction(from: origin, to: $0) }),
                       ["east", "west", "northeast", "northwest", "southeast", "southwest"])
        XCTAssertEqual(BoardCoordinator.direction(from: origin, to: HexCoord(3, 0)), "north")
        XCTAssertEqual(BoardCoordinator.direction(from: origin, to: HexCoord(3, 7)), "south")
    }

    /// Every hex a move can reach is a spoken choice, nearest first, and choosing one moves
    /// the character there, as tapping it would.
    func testAMoveCanBeChosenInWords() async throws {
        let (_, coord, brute) = try boardWithBrute()
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed)
        coord.beginMoveAction(pieceID: brute, moveRange: 2)
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("a move waits for a hex") }
        let choices = coord.accessibleChoices()
        XCTAssertEqual(choices.count, hexes.count)
        XCTAssertEqual(Set(choices.map(\.label)).count, choices.count, "no two choices read alike")
        XCTAssertTrue(choices[0].label.hasPrefix("Move 1 hex "), choices[0].label)
        for choice in choices { XCTAssertEqual(PlayerTextTests.lint(choice.label), [], choice.label) }

        let east = try XCTUnwrap(choices.first { $0.label.hasPrefix("Move 1 hex east") })
        XCTAssertTrue(east.label.contains("next to Bandit Guard 1"), east.label)
        east.perform()
        let deadline = Date().addingTimeInterval(3)
        while coord.boardState.piecePositions[brute] != HexCoord(4, 3) && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(coord.boardState.piecePositions[brute], HexCoord(4, 3))
    }

    func testATargetCanBeChosenInWords() throws {
        let (_, coord, brute) = try boardWithBrute()
        let near = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed)
        coord.beginAttackAction(pieceID: brute, range: 2)
        let choices = coord.accessibleChoices()
        XCTAssertEqual(choices.count, 2)
        let entity = try XCTUnwrap(coord.entity(for: near))
        XCTAssertEqual(choices[0].label, "Attack Bandit Guard 1, \(entity.health) of \(entity.maxHealth) health, next to you")
        XCTAssertTrue(choices[1].label.hasSuffix("2 hexes away"), choices[1].label)
        choices[0].perform()
        if case .selectingAttackTarget = coord.interactionMode { XCTFail("choosing the target attacks it") }
    }

    func testNothingToChooseWhileMonstersAct() throws {
        let (_, coord, _) = try boardWithBrute()
        coord.interactionMode = .watchingMonsterTurn
        XCTAssertTrue(coord.accessibleChoices().isEmpty)
    }
}
