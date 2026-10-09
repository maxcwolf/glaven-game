import XCTest
@testable import GlavenGameLib

/// Every setting the Settings sheet shows changes something in the game.
@MainActor
final class SettingsWiringTests: XCTestCase {

    private func startScenario(animationSpeed: Double) throws -> BoardCoordinator {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.settingsManager.animationSpeed = animationSpeed
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        return gm.boardCoordinator
    }

    func testAnimationSpeedSetsTheBoardsPace() throws {
        let fast = try startScenario(animationSpeed: 0.5)
        XCTAssertEqual(fast.boardScene?.speed, 2)
        XCTAssertEqual(fast.turnDelayNanoseconds, BoardCoordinator.baseTurnDelayNanoseconds / 2)

        let normal = try startScenario(animationSpeed: 1)
        XCTAssertEqual(normal.boardScene?.speed, 1)
        XCTAssertEqual(normal.turnDelayNanoseconds, BoardCoordinator.baseTurnDelayNanoseconds)

        let slow = try startScenario(animationSpeed: 2)
        XCTAssertEqual(slow.boardScene?.speed, 0.5)
        XCTAssertEqual(slow.turnDelayNanoseconds, BoardCoordinator.baseTurnDelayNanoseconds * 2)
    }

    func testLaunchStingFollowsTheSoundSettingAndPlaysOnce() {
        XCTAssertTrue(SoundPlayer.shouldPlayLaunchSting(soundEffects: true, alreadyPlayed: false))
        XCTAssertFalse(SoundPlayer.shouldPlayLaunchSting(soundEffects: false, alreadyPlayed: false))
        XCTAssertFalse(SoundPlayer.shouldPlayLaunchSting(soundEffects: true, alreadyPlayed: true))
    }

    func testSoundAndHapticsFollowTheirOwnToggles() {
        #if os(iOS)
        XCTAssertEqual(SoundPlayer.feedback(for: .cardFlip, soundEffects: true, haptics: false),
                       .init(systemSound: 1104, haptic: false))
        XCTAssertEqual(SoundPlayer.feedback(for: .cardFlip, soundEffects: false, haptics: true),
                       .init(systemSound: nil, haptic: true))
        #else
        // The Mac has no effect sounds; it must never fall back to the system alert beep.
        for effect in [SoundEffect.tap, .cardFlip, .phaseChange, .coin, .error] {
            XCTAssertEqual(SoundPlayer.feedback(for: effect, soundEffects: true, haptics: true),
                           .init(systemSound: nil, haptic: false))
        }
        #endif
    }

    /// The board's element display is read-only; elements change only through abilities.
    func testBoardElementsAreReadOnlyAndDescribeTheirState() {
        XCTAssertFalse(ElementBoardView().isEditable)
        for element in ElementType.allCases {
            for state in ElementState.allCases {
                let text = GameText.elementStateDescription(element, state)
                XCTAssertTrue(text.hasPrefix(GameText.elementName(element) + ": "), text)
                XCTAssertEqual(PlayerTextTests.lint(text), [], text)
            }
        }
        XCTAssertEqual(GameText.elementStateDescription(.fire, .new), "Fire: infused this turn, usable from the next turn")
    }
}

/// The settings dialog's named stops.
final class SettingsStopsTests: XCTestCase {
    func testEachValueShowsItsNearestStop() {
        XCTAssertEqual(PreferencesSheet.nearest(1, in: PreferencesSheet.speedStops).name, "Normal")
        XCTAssertEqual(PreferencesSheet.nearest(0.5, in: PreferencesSheet.speedStops).name, "Fast")
        XCTAssertEqual(PreferencesSheet.nearest(1.25, in: PreferencesSheet.speedStops).name, "Normal",
                       "a value between stops (an older save) shows the nearer, or first, of the two")
        XCTAssertEqual(PreferencesSheet.nearest(1.7, in: PreferencesSheet.speedStops).name, "Slow")
        XCTAssertEqual(PreferencesSheet.nearest(1, in: PreferencesSheet.sizeStops).name, "Default")
        XCTAssertEqual(PreferencesSheet.nearest(1.45, in: PreferencesSheet.sizeStops).name, "Maximum")
        // Every stop is inside the range the settings accept.
        XCTAssertTrue(PreferencesSheet.speedStops.allSatisfy { (0.5...2).contains($0.value) })
        XCTAssertTrue(PreferencesSheet.sizeStops.allSatisfy { (0.85...1.5).contains($0.value) })
    }
}
