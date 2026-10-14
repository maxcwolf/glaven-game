import XCTest

/// The rules count adjacency and range round walls (GH p.19, FAQ): "adjacent" and "within range"
/// must be asked of the board (`BoardState.areAdjacent`, `neighbors(of:)`, `range(from:to:)`,
/// `isWithin`, `steps`), never of the bare hex grid, which knows no walls. This reads the game's
/// sources so a new rule can't quietly measure through a wall.
final class BoardGeometryGuardTests: XCTestCase {

    /// Files that are the geometry itself, or that measure the page rather than the board.
    private let exempt: Set<String> = [
        "HexCoord.swift", "BoardState.swift", "Pathfinder.swift", "BoardBuilder.swift",
        "RandomDungeonMap.swift",      // lays out tiles before there is a board, like BoardBuilder
        "LearnDiagram.swift",          // a teaching diagram, not the board
        "SoakDriver.swift",            // the soak test's own player
        "EscortTurnController.swift",  // nearest door to a place not yet on the map
    ]

    func testRulesAskTheBoardNotTheBareGridForAdjacencyAndRange() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlavenGame")
        let bare = try NSRegularExpression(pattern: #"\.distance\(to:|\.isAdjacent\(to:|\.pushCandidates\(|\.pullCandidates\(|(?<![Ss]tate|board|context)\.neighbors\b(?!\(of)"#)
        var offences: [String] = []
        var scanned = 0
        for folder in ["Board", "Engine", "Managers"] {
            let directory = root.appendingPathComponent(folder)
            for file in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            where file.hasSuffix(".swift") && !exempt.contains(file) {
                scanned += 1
                let source = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
                for (number, line) in source.components(separatedBy: "\n").enumerated() {
                    let code = line.components(separatedBy: "//").first ?? line
                    // Forced movement filters its candidates by the wall lines on the same line.
                    if code.contains("pushCandidates(") && code.contains("pullCandidates(") { continue }
                    if bare.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil {
                        offences.append("\(folder)/\(file):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        XCTAssertGreaterThan(scanned, 40, "the sources were found")
        XCTAssertEqual(offences, [], "measured on the bare hex grid; ask BoardState instead:\n" + offences.joined(separator: "\n"))
    }
}
