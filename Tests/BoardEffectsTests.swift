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

    /// Regression: labels were drawn at a fixed size in board space, so with the board zoomed
    /// out to fit around the turn's panel "Miss" shrank to about 14 points. They now keep the
    /// same, readable size on screen at any zoom.
    func testLabelsStayReadableAtAnyZoom() {
        let monster = aMonster
        var heights: [CGFloat] = []
        for scale: CGFloat in [1, 1.6, 2.2] {
            scene.cameraState = BoardCamera(position: .zero, scale: scale)
            scene.pieceUnharmed(id: monster, missed: true)
            scene.settleEffectsForSnapshot()
            heights.append(scene.floatingTextHeights(over: monster).last!)
        }
        for height in heights {
            XCTAssertGreaterThanOrEqual(height, 24, "a label stands at least 24 points tall on screen")
            XCTAssertEqual(height, heights[0], accuracy: 0.5, "and the same at every zoom: \(heights)")
        }
    }

    /// Renders an attack's labels at the zoom the board has during a turn, for review:
    /// `FLOAT_RENDER_OUT=/tmp/floats.png swift test --filter testRenderFloatingText`
    func testRenderFloatingText() throws {
        guard let out = ProcessInfo.processInfo.environment["FLOAT_RENDER_OUT"] else {
            throw XCTSkip("set FLOAT_RENDER_OUT to render the labels")
        }
        let brute = PieceID.character(gm.game.characters[0].id)
        let monsters = coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1376, height: 1032))
        view.presentScene(scene)
        scene.cameraState = BoardCamera(position: scene.sceneCenter(of: coord.boardState.piecePositions[monsters[0]]!),
                                        scale: 1.6)
        scene.pieceDamage(id: monsters[0], amount: 3)
        scene.pieceUnharmed(id: monsters[1], missed: true)
        scene.pieceUnharmed(id: monsters[2], missed: false)
        coord.applyCondition(.stun, to: monsters[0])
        scene.pieceHeal(id: brute, amount: 2)
        scene.pieceLoot(id: brute, text: "+2g")
        scene.settleEffectsForSnapshot()
        let image = try XCTUnwrap(view.texture(from: scene)).cgImage()
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
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
