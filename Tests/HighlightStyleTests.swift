import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Each kind of choice on the board is highlighted its own way, and never by colour alone.
@MainActor
final class HighlightStyleTests: XCTestCase {

    /// Styles that share a hue differ in shape, so colour-blind players can tell them apart.
    func testNoTwoChoicesLookTheSame() {
        let styles = HighlightStyle.allCases.filter { $0 != .summon } // summon placement is a kind of placing
        for (i, a) in styles.enumerated() {
            for b in styles[(i + 1)...] {
                XCTAssertFalse(a.color == b.color && a.cue == b.cue, "\(a) and \(b) look identical")
            }
        }
        // The choices most often confused before all differ in hue.
        XCTAssertNotEqual(HighlightStyle.attack.color, HighlightStyle.heal.color)
        XCTAssertNotEqual(HighlightStyle.heal.color, HighlightStyle.jump.color)
        XCTAssertNotEqual(HighlightStyle.fly.color, HighlightStyle.condition.color)
        XCTAssertNotEqual(HighlightStyle.attack.cue, .outline, "targets carry a reticle, not just a colour")
    }

    func testEachActionUsesItsStyle() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let scene = try XCTUnwrap(coord.boardScene)

        coord.beginPlaceCharacter(characterID: gm.game.characters[0].id)
        XCTAssertEqual(scene.highlightStyle, .place)
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
        let brute = PieceID.character(gm.game.characters[0].id)

        coord.beginMoveAction(pieceID: brute, moveRange: 3)
        XCTAssertEqual(scene.highlightStyle, .move)
        coord.beginMoveAction(pieceID: brute, moveRange: 3, mode: .jump)
        XCTAssertEqual(scene.highlightStyle, .jump)
        coord.beginMoveAction(pieceID: brute, moveRange: 3, mode: .fly)
        XCTAssertEqual(scene.highlightStyle, .fly)
        coord.beginHealAction(pieceID: brute, healValue: 2, range: 3)
        XCTAssertEqual(scene.highlightStyle, .heal)
        XCTAssertFalse(scene.highlightedHexes.isEmpty)
        coord.beginAttackAction(pieceID: brute, range: 10)
        XCTAssertEqual(scene.highlightStyle, .attack)
        XCTAssertFalse(scene.highlightedHexes.isEmpty, "monsters in range are marked as targets")
    }
}
