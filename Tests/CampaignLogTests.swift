import XCTest
@testable import GlavenGameLib

/// The campaign log, shown on the Campaign sheet, reads as plain words; and the campaign's
/// standing is earned, not edited.
@MainActor
final class CampaignLogTests: XCTestCase {

    /// A stretch of a campaign: recruiting, a scenario, a city event, a level and a retirement.
    func testTheLogReadsCleanly() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 2)
        let gm = sim.gm
        gm.completeScenario(success: true)
        gm.eventCardManager.resolve(.city, option: "B")
        let character = gm.game.characters[0]
        character.experience = 45
        gm.characterManager.levelUp(character)
        gm.characterManager.retireCharacter(character)

        let types = Set(gm.game.campaignLog.map(\.type))
        for expected: CampaignLogType in [.characterAdded, .scenarioCompleted, .eventResolved, .levelUp, .characterRetired] {
            XCTAssertTrue(types.contains(expected), "\(expected) is logged")
        }
        for entry in gm.game.campaignLog {
            XCTAssertEqual(PlayerTextTests.lint(entry.message), [], entry.message)
            if let details = entry.details { XCTAssertEqual(PlayerTextTests.lint(details), [], details) }
        }
        XCTAssertTrue(gm.game.campaignLog.contains { $0.message == "Completed #1 Black Barrow" })
    }

    /// Regression: the Campaign sheet (from the companion app) had +/− buttons for reputation
    /// and prosperity. They're earned in scenarios and events; no view sets them.
    func testNoViewEditsTheCampaignsStanding() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent("GlavenGame/Views"),
                                                        includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for field in ["partyReputation", "partyProsperity"] {
                XCTAssertNil(text.range(of: #"\#(field)\s*[+\-]?="#, options: .regularExpression),
                             "\(url.lastPathComponent) sets \(field)")
            }
        }
    }
}
