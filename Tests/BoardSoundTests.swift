import XCTest
import SpriteKit
@testable import GlavenGameLib

/// The board makes a sound for what happens on it — and every cue has audio to play.
@MainActor
final class BoardSoundTests: XCTestCase {

    func testEveryCueHasAudio() {
        for sound in BoardSound.allCases {
            XCTAssertFalse(sound.files.isEmpty, "\(sound) has at least one bundled file")
        }
    }

    /// Variants take turns, so a flurry of hits doesn't sound like one sample on repeat — and
    /// nothing draws from the game's seeded randomness.
    func testVariantsTakeTurns() {
        let files = BoardSound.hit.files
        XCTAssertGreaterThan(files.count, 1)
        let played = (0..<(files.count * 2)).compactMap { _ in BoardSoundPlayer.nextFile(for: .hit) }
        XCTAssertEqual(Set(played), Set(files), "every variant plays")
        XCTAssertNotEqual(played[0], played[1], "not the same one twice running")
    }

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var heard: [BoardSound] = []

    /// Scenario 1 shown in a view, with its sounds recorded rather than played.
    private func start(presented: Bool = true) throws -> BoardScene {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
        coord.placeCharacter(characterID: gm.game.characters[0].id, at: free)
        let scene = try XCTUnwrap(coord.boardScene)
        if presented { SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768)).presentScene(scene) }
        scene.playSound = { [weak self] in self?.heard.append($0) }
        return scene
    }

    private var aMonster: PieceID {
        coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted().first!
    }

    func testWhatHappensOnTheBoardIsHeard() throws {
        let scene = try start()
        let brute = PieceID.character(gm.game.characters[0].id)
        let monster = aMonster

        scene.pieceDamage(id: monster, amount: 2)
        scene.pieceDamage(id: monster, amount: 5)
        scene.pieceUnharmed(id: monster, missed: true)
        scene.pieceUnharmed(id: monster, missed: false)
        XCTAssertEqual(heard, [.hit, .heavyHit, .miss, .blocked])

        heard = []
        coord.applyCondition(.stun, to: monster)
        coord.applyCondition(.strengthen, to: brute)
        coord.sufferDamage(3, to: brute)
        coord.heal(brute, amount: 2)
        coord.setActing(brute)
        coord.setActing(monster)
        XCTAssertEqual(heard, [.harm, .boon, .hit, .heal, .turn], "a monster's turn starts quietly")

        heard = []
        coord.sufferDamage(coord.entity(for: monster)!.health, to: monster)
        XCTAssertTrue(heard.contains(.death))

        heard = []
        let door = try XCTUnwrap(coord.boardState.doors.sorted { $0.coord < $1.coord }.first { !$0.isOpen })
        coord.openDoor(at: door.coord)
        XCTAssertTrue(heard.contains(.door))
    }

    /// Regression: tests that show the board in a real view (camera, rendering) played its
    /// sounds through the speakers on every run — a door creak every few minutes. Nothing plays
    /// under the test runner.
    func testTheTestRunnerIsSilent() throws {
        XCTAssertTrue(BoardSoundPlayer.isSilenced)
        let before = BoardSoundPlayer.playedCount
        BoardSoundPlayer.play(.door)
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let scene = try XCTUnwrap(gm.boardCoordinator.boardScene)
        SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600)).presentScene(scene)
        let door = try XCTUnwrap(gm.boardCoordinator.boardState.doors.first { !$0.isOpen })
        gm.boardCoordinator.openDoor(at: door.coord)
        XCTAssertEqual(BoardSoundPlayer.playedCount, before)
    }

    /// Headless play (the simulator, tests) makes no sound.
    func testAHeadlessBoardIsSilent() throws {
        let scene = try start(presented: false)
        scene.pieceDamage(id: aMonster, amount: 2)
        coord.applyCondition(.stun, to: aMonster)
        XCTAssertEqual(heard, [])
    }
}
