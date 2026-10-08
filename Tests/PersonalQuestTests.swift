import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Personal quests (GH p.12, 44): a recruit is dealt two and keeps one; the game counts what it
/// can see from each character's campaign record; a completed quest lets the character retire.
@MainActor
final class PersonalQuestTests: XCTestCase {

    private var gm: GameManager!
    private var manager: CharacterManager { gm.characterManager }
    private var brute: GameCharacter { gm.game.characters[0] }

    override func setUpWithError() throws {
        gm = try SaveAndContinueTestsSupport.manager()
        manager.addCharacter(name: "brute", edition: "gh")
        manager.addCharacter(name: "tinkerer", edition: "gh")
    }

    private func give(_ questId: String, to character: GameCharacter) {
        character.questChoices = [questId]
        manager.chooseQuest(questId, for: character)
    }

    /// Play scenario `index` to an end with the given result, after `during` runs on the board.
    private func play(_ index: String, success: Bool, during: (BoardCoordinator) -> Void = { _ in }) throws {
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(data)
        during(gm.boardCoordinator)
        gm.completeScenario(success: success)
    }

    // MARK: - Dealing

    func testARecruitIsDealtTwoQuestsNoOneHolds() {
        give("515", to: gm.game.characters[1])
        for _ in 0..<20 {
            manager.dealQuests(to: brute)
            XCTAssertEqual(brute.questChoices.count, 2)
            XCTAssertEqual(Set(brute.questChoices).count, 2)
            XCTAssertFalse(brute.questChoices.contains("515"), "the Tinkerer holds that one")
        }
        let kept = brute.questChoices[1]
        manager.chooseQuest("999", for: brute)
        XCTAssertNil(brute.personalQuest, "only a quest that was dealt")
        manager.chooseQuest(kept, for: brute)
        XCTAssertEqual(brute.personalQuest, kept)
        XCTAssertTrue(brute.questChoices.isEmpty)
    }

    func testEveryQuestReadsCleanly() throws {
        for data in gm.editionStore.personalQuests(for: "gh") {
            let quest = try XCTUnwrap(manager.personalQuest(data.cardId), data.cardId)
            XCTAssertFalse(quest.name.hasPrefix("Quest "), "\(data.cardId) has its name")
            for line in [quest.name] + quest.requirements.map(\.text) {
                XCTAssertFalse(line.isEmpty || line.contains("%"), "\(data.cardId): \(line)")
                XCTAssertEqual(PlayerTextTests.lint(line), [], "\(data.cardId): \(line)")
            }
        }
        XCTAssertEqual(manager.personalQuest("511")?.requirements.first?.text, "Head items")
    }

    // MARK: - Counting

    /// Law Bringer: bandits and cultists killed, in any scenario, won or lost.
    func testKillsCountTowardTheQuest() throws {
        give("515", to: brute)
        try play("1", success: false) { coord in
            let bandits = coord.boardState.piecePositions.keys.filter {
                if case .monster(let name, _) = $0 { return name.hasPrefix("bandit") }
                return false
            }.sorted()
            for bandit in bandits.prefix(3) {
                coord.sufferDamage(99, to: bandit, killer: .character(self.brute.id))
            }
        }
        XCTAssertEqual(brute.personalQuestProgress.first, 3)
        XCTAssertEqual(brute.record.kills["bandit-guard"], 3)
    }

    func testScenarioVariantsCountAsTheirMonster() {
        XCTAssertEqual(CharacterRecord.baseMonsterName("cultist-scenario-78"), "cultist")
        XCTAssertEqual(CharacterRecord.baseMonsterName("bandit-guard-music-note-solo"), "bandit-guard")
        XCTAssertEqual(CharacterRecord.baseMonsterName("vermling-scout"), "vermling-scout")
    }

    /// Seeker of Xorn: three Crypt scenarios won, then Noxious Cellar (only after the first).
    func testScenarioRequirementsAndTheirOrder() throws {
        give("510", to: brute)
        brute.record.scenariosCompleted = ["gh-5", "gh-6", "gh-1"]   // two crypts and Black Barrow
        gm.game.completedScenarios.insert("gh-52")
        PersonalQuestEvaluator.updateProgress(character: brute, game: gm.game, editionStore: gm.editionStore)
        XCTAssertEqual(brute.personalQuestProgress, [2, 0], "the cellar waits for the third crypt")
        brute.record.scenariosCompleted.insert("gh-19")
        PersonalQuestEvaluator.updateProgress(character: brute, game: gm.game, editionStore: gm.editionStore)
        XCTAssertEqual(brute.personalQuestProgress, [3, 1])
        XCTAssertTrue(manager.questComplete(brute))
    }

    /// Regression: these "automatic" counts were stubs that always gave 0 (or every scenario).
    func testRecordBasedCountsAreReal() throws {
        brute.record.scenariosCompleted = ["gh-1", "gh-52", "gh-60", "gh-2"]
        brute.record.timesExhausted = 4
        brute.record.partyExhaustions = 9
        let cases: [(quest: String, expected: Int)] = [
            ("522", 2),   // side scenarios: numbered above 51
            ("527", 4),   // times exhausted
            ("514", 9),   // party exhaustions
        ]
        for (quest, expected) in cases {
            brute.personalQuest = quest
            brute.personalQuestProgress = []
            PersonalQuestEvaluator.updateProgress(character: brute, game: gm.game, editionStore: gm.editionStore)
            XCTAssertEqual(brute.personalQuestProgress.first, expected, quest)
        }
    }

    func testOnlyWhatTheGameCantSeeIsCountedByHand() {
        give("531", to: brute)   // scenarios in map regions: by hand
        manager.adjustQuest(0, by: 1, for: brute)
        XCTAssertEqual(brute.personalQuestProgress.first, 1)
        give("515", to: gm.game.characters[1])   // kills: the game counts
        manager.adjustQuest(0, by: 5, for: gm.game.characters[1])
        XCTAssertEqual(gm.game.characters[1].personalQuestProgress.first, 0)
    }

    // MARK: - Retiring and saving

    func testACompletedQuestRetiresTheCharacter() throws {
        give("519", to: brute)   // Battle Legend: 15 checkmarks; unlocks the Soothsinger
        brute.battleGoalProgress = 15
        PersonalQuestEvaluator.updateProgress(character: brute, game: gm.game, editionStore: gm.editionStore)
        XCTAssertTrue(manager.questComplete(brute))
        let prosperity = gm.game.partyProsperity
        let retiree = brute
        manager.retireCharacter(retiree)
        XCTAssertFalse(gm.game.characters.contains { $0 === retiree })
        XCTAssertTrue(gm.game.unlockedCharacters.contains("gh-music-note"))
        XCTAssertEqual(gm.game.partyProsperity, prosperity + 1)
        XCTAssertEqual(gm.game.retiredCharacters.count, 1)
    }

    func testRecordsAndDealtQuestsAreSaved() {
        brute.record.kills = ["ooze": 2]
        brute.questChoices = ["520", "521"]
        let restored = brute.toSnapshot().toRuntime(editionStore: gm.editionStore)
        XCTAssertEqual(restored.record, brute.record)
        XCTAssertEqual(restored.questChoices, ["520", "521"])
    }

    /// `QUEST_RENDER_OUT=/tmp/q.png swift test --filter testRenderQuestPicker` renders the picker.
    func testRenderQuestPicker() throws {
        guard let out = ProcessInfo.processInfo.environment["QUEST_RENDER_OUT"] else {
            throw XCTSkip("set QUEST_RENDER_OUT to render the picker")
        }
        GlavenFont.registerFonts()
        brute.questChoices = ["510", "523"]
        let view = QuestPicker(character: brute) {}.environment(gm).frame(width: 1376, height: 1032)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
