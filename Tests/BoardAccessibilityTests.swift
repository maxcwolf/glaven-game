import XCTest
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
}
