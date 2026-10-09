import XCTest

/// Settings in project.yml that the app's look depends on.
final class ProjectSettingsTests: XCTestCase {

    private func projectYML() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
    }

    /// Regression: without a launch screen iOS letterboxes the app to an older iPad's size, so on
    /// an 11-inch iPad Pro (M4) it ran squeezed between black bars.
    func testTheAppDeclaresALaunchScreen() throws {
        let lines = try projectYML().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertTrue(lines.contains("INFOPLIST_KEY_UILaunchScreen_Generation: true"), "an active setting, not a comment")
    }
}
