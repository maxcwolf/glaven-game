import XCTest
import SpriteKit
@testable import GlavenGameLib

/// The board shows what happens: who attacks whom, the numbers (even on a killing blow), misses
/// and blocks, heals, and whose turn it is.
@MainActor
final class BoardEffectsTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var scene: BoardScene { coord.boardScene! }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
    }

    private var aMonster: PieceID {
        coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted().first!
    }

    private func floatTexts(over piece: PieceID) -> [String] {
        scene.floatingTexts(over: piece)
    }

    /// Regression: the killing blow's number was a child of the dying piece and vanished with it.
    func testKillingBlowNumberOutlivesThePiece() {
        let monster = aMonster
        let health = coord.entity(for: monster)!.health
        coord.sufferDamage(health, to: monster)
        XCTAssertNil(scene.pieceNode(for: monster), "the piece is gone")
        XCTAssertEqual(floatTexts(over: monster), ["\u{2212}\(health)"], "its damage number is still showing")
    }

    func testAttackShowsALineAndItsOutcome() async {
        let brute = PieceID.character(gm.game.characters[0].id)
        let monster = aMonster
        let before = scene.activeEffectCount
        // Give the target a big shield so the attack is blocked.
        coord.entity(for: monster)!.shield = ActionModel(type: .shield, value: .int(20))
        _ = await coord.performAttack(attacker: brute, target: monster, attack: AttackParameters(value: 1))
        XCTAssertGreaterThan(scene.activeEffectCount, before, "the attack line is drawn")
        let texts = floatTexts(over: monster)
        XCTAssertTrue(texts == ["Blocked"] || texts == ["Miss"], "a hit for no damage says so: \(texts)")
    }

    func testHealsFloatInGreen() {
        let brute = PieceID.character(gm.game.characters[0].id)
        coord.sufferDamage(3, to: brute)
        coord.heal(brute, amount: 2)
        XCTAssertEqual(floatTexts(over: brute), ["\u{2212}3", "+2"])
    }

    /// Every attack happens while its attacker is the ringed figure, so the player can always
    /// see who is acting. (A summon's or a character's attack counts as theirs.)
    func testEveryAttackerIsRingedWhenItAttacks() async {
        coord.finishSetup()
        let sim = ScenarioSimulator(resuming: gm, scenario: "1")
        let observe = sim.coord.attackObserver
        var checked = 0
        var mismatches: [String] = []
        sim.coord.attackObserver = { attacker, target in
            checked += 1
            if sim.coord.actingPiece != attacker {
                mismatches.append("\(attacker) attacked while \(String(describing: sim.coord.actingPiece)) was ringed")
            }
            observe?(attacker, target)
        }
        await sim.play(rounds: 3)
        XCTAssertGreaterThan(checked, 2)
        XCTAssertEqual(mismatches, [])
    }

    func testTheRingSitsOnTheActingPiece() {
        let monster = aMonster
        coord.setActing(monster)
        XCTAssertEqual(scene.actingPieceID, monster)
        coord.setActing(nil)
        XCTAssertNil(coord.actingPiece)
    }

    // MARK: - Conditions

    /// A condition landing says so over the figure and its icon appears; wearing off says so too.
    func testConditionsAreAnnouncedAsTheyComeAndGo() throws {
        let monster = aMonster
        coord.applyCondition(.stun, to: monster)
        XCTAssertEqual(floatTexts(over: monster), ["Stun"])
        XCTAssertTrue(scene.pieceNode(for: monster)?.shownConditions.contains(.stun) == true)

        let entity = try XCTUnwrap(coord.entity(for: monster))
        gm.entityManager.removeCondition(.stun, from: entity)
        coord.syncPieceVisuals()
        XCTAssertEqual(floatTexts(over: monster), ["Stun", "Stun ends"])
    }

    /// Curse and bless go into a deck, not onto the token, so the label is the only sign on the board.
    func testCurseAndBlessAreAnnouncedThoughTheyHaveNoIcon() {
        let monster = aMonster
        let brute = PieceID.character(gm.game.characters[0].id)
        coord.applyCondition(.curse, to: monster)
        coord.applyCondition(.bless, to: brute)
        XCTAssertEqual(floatTexts(over: monster), ["Curse"])
        XCTAssertEqual(floatTexts(over: brute), ["Bless"])
    }

    func testImmunityIsShown() throws {
        let monster = aMonster
        let entity = try XCTUnwrap(coord.entity(for: monster))
        entity.immunities.append(.poison)
        coord.applyCondition(.poison, to: monster)
        XCTAssertEqual(floatTexts(over: monster), ["Immune"])
    }

    /// A rebuilt board (undo, a revealed room) doesn't announce the conditions figures already have.
    func testARebuiltBoardAnnouncesNothing() throws {
        let monster = aMonster
        gm.entityManager.addCondition(.poison, to: try XCTUnwrap(coord.entity(for: monster)))
        coord.restore(from: coord.snapshot())
        XCTAssertTrue(scene.pieceNode(for: monster)?.shownConditions.contains(.poison) == true, "the icon shows")
        for piece in coord.boardState.piecePositions.keys {
            XCTAssertEqual(floatTexts(over: piece), [], "\(piece)")
        }
    }

    func testConditionLabelsReadCleanly() {
        for condition in ConditionName.allCases {
            XCTAssertEqual(PlayerTextTests.lint(GameText.conditionName(condition)), [], "\(condition)")
        }
    }
}

/// The scene survives being put on screen, which runs `didMove(to:)` after the board is built.
@MainActor
final class BoardScenePresentationTests: XCTestCase {

    /// Regression: the acting-figure ring was added in both `buildBoard` and `didMove(to:)`, and
    /// SpriteKit throws when a node that already has a parent is added again, so the app crashed
    /// as soon as a board appeared.
    func testABuiltBoardCanBeShownAndShownAgain() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let scene = try XCTUnwrap(gm.boardCoordinator.boardScene)

        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        view.presentScene(nil)
        view.presentScene(scene)   // e.g. leaving the board view and coming back
        gm.boardCoordinator.setActing(gm.boardCoordinator.boardState.piecePositions.keys.sorted().first)
        XCTAssertNotNil(scene.actingPieceID)
    }
}
