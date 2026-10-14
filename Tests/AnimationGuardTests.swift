import XCTest

/// A repeating animation started with `withAnimation` takes every change of its update with it.
/// On macOS the main menu's map drift did so as the window grew to fill the screen: the whole menu
/// crept from a corner to full size over 45 seconds. A repeating animation is scoped to the view
/// it animates (`.animation(_:body:)` or `.animation(_:value:)` on that view). This reads the
/// game's sources.
final class AnimationGuardTests: XCTestCase {
    func testNoRepeatingAnimationIsStartedWithWithAnimation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlavenGame")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(atPath: root.path))
        var offences: [String] = []
        var scanned = 0
        while let path = enumerator.nextObject() as? String {
            guard path.hasSuffix(".swift") else { continue }
            scanned += 1
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            for (number, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("withAnimation(") && line.contains("repeatForever") {
                offences.append("\(path):\(number + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThan(scanned, 100, "the sources were found")
        XCTAssertEqual(offences, [], "scope the repeating animation to its view:\n" + offences.joined(separator: "\n"))
    }
}
