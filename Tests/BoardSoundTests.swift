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
        XCTAssertEqual(heard, [.stun, .strengthen, .hit, .heal, .turn], "a monster's turn starts quietly")

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

    // MARK: - Conditions

    /// Regression: every hindrance played one plucked-string note and every boon one chime,
    /// whatever the condition. Each of the base game's conditions has its own cue; the rest share
    /// the hindrance or the boon cue.
    func testEachConditionHasItsOwnCue() {
        let own: [ConditionName: BoardSound] = [
            .wound: .wound, .poison: .poison, .stun: .stun, .immobilize: .immobilize, .disarm: .disarm,
            .muddle: .muddle, .curse: .curse, .strengthen: .strengthen, .bless: .bless,
        ]
        for (condition, sound) in own {
            XCTAssertEqual(BoardSound.condition(condition), sound)
            XCTAssertTrue(sound.isCondition)
        }
        XCTAssertEqual(Set(own.values).count, own.count, "no two share a cue")
        XCTAssertEqual(BoardSound.condition(.brittle), .harm)
        XCTAssertEqual(BoardSound.condition(.ward), .boon)
        XCTAssertEqual(BoardSound.condition(.invisible), .boon)
    }

    func testCurseAndBlessAreHeardThoughTheyGoIntoADeck() throws {
        _ = try start()
        coord.applyCondition(.curse, to: aMonster)
        coord.applyCondition(.bless, to: .character(gm.game.characters[0].id))
        XCTAssertEqual(heard, [.curse, .bless])
    }

    // MARK: - What used to be silent, or shared a cue

    /// Regression: a character going down played the same thud as a bandit guard dying.
    func testACharacterGoingDownIsExhaustionNotAMonsterDeath() throws {
        _ = try start()
        let brute = gm.game.characters[0]
        coord.sufferDamage(brute.health, to: .character(brute.id))
        XCTAssertEqual(heard.last, .exhaust)
        XCTAssertFalse(heard.contains(.death))
    }

    func testElementsAreHeardInfusedAndConsumed() throws {
        _ = try start()
        gm.game.infuseElement(.fire)
        XCTAssertEqual(heard, [.infuse])
        gm.game.infuseElement(.fire)
        XCTAssertEqual(heard, [.infuse], "already on its way to strong: nothing new to hear")
        let index = try XCTUnwrap(gm.game.elementBoard.firstIndex { $0.type == .fire })
        gm.game.elementBoard[index].state = .strong
        heard = []
        XCTAssertNotNil(gm.game.consumeElements([.fire]))
        XCTAssertNil(gm.game.consumeElements([.fire]), "nothing left to consume")
        XCTAssertEqual(heard, [.consume])
    }

    /// A room's monsters arrive with its door; one spawned or summoned later announces itself.
    func testAMonsterSpawnedMidScenarioIsHeard() throws {
        _ = try start()
        let free = try XCTUnwrap(coord.boardState.cells.keys.sorted().first {
            !coord.boardState.isOccupied($0) && coord.boardState.isPassable($0) })
        XCTAssertNotNil(coord.spawnMonster(name: "bandit-guard", type: .normal, at: free, origin: .placed))
        XCTAssertEqual(heard, [])
        XCTAssertNotNil(coord.spawnMonster(name: "bandit-guard", type: .normal, at: free, origin: .spawned))
        XCTAssertEqual(heard, [.summon])
    }

    /// Locking in the round's cards, the round beginning and the first turn are each heard, in
    /// that order.
    func testLockingInCardsBeginsTheRound() throws {
        _ = try start()
        let brute = gm.game.characters[0]
        let deck = gm.editionStore.abilities(forDeck: brute.characterData?.deck ?? brute.name, edition: "gh")
        let hand = brute.handCards.compactMap { id in deck.first { $0.cardId == id } }
        XCTAssertGreaterThanOrEqual(hand.count, 2)
        coord.chooseCards(for: brute.id, leading: hand[0], other: hand[1])
        XCTAssertEqual(Array(heard.prefix(2)), [.cardConfirm, .round])
    }

    func testAShortRestIsHeardAndSoIsTheCardItCosts() throws {
        _ = try start()
        let brute = gm.game.characters[0]
        brute.discardedCards = Array(brute.handCards.prefix(3))
        brute.handCards.removeFirst(3)
        coord.pendingShortRest = .init(characterID: brute.id, randomCardId: brute.discardedCards[0])
        coord.resolveShortRest()
        XCTAssertEqual(Array(heard.prefix(2)), [.rest, .lose])
        XCTAssertEqual(brute.lostCards.count, 1)
    }

    // MARK: - Shield and retaliate

    private func attack(_ target: PieceID, from attacker: PieceID, value: Int, pierce: Int = 0) async {
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        await coord.performAttack(attacker: attacker, target: target, attack: AttackParameters(value: value, pierce: pierce),
                                  drawCard: { AttackModifier(type: .plus0) })
    }

    /// Regression: only a fully blocked attack made a sound; shield that took part of a blow was
    /// silent, as was retaliate.
    func testShieldThatTakesPartOfABlowAndRetaliateAreHeard() async throws {
        _ = try start()
        let brute = PieceID.character(gm.game.characters[0].id)
        let monster = aMonster
        let entity = try XCTUnwrap(coord.entity(for: monster))
        entity.health = 40
        entity.maxHealth = 40
        let from = try XCTUnwrap(coord.boardState.piecePositions[monster]?.neighbors.first {
            coord.boardState.cells[$0] != nil && !coord.boardState.isOccupied($0) && coord.boardState.isPassable($0) })
        coord.boardState.movePiece(brute, to: from)

        entity.shield = ActionModel(type: .shield, value: .int(1))
        await attack(monster, from: brute, value: 3)
        XCTAssertEqual(heard, [.shield, .hit], "shield takes 1 of 3")

        heard = []
        await attack(monster, from: brute, value: 3, pierce: 1)
        XCTAssertEqual(heard, [.hit], "pierced: the shield took nothing")

        heard = []
        await attack(monster, from: brute, value: 1)
        XCTAssertEqual(heard, [.blocked], "all of it: a block, not a partial")

        heard = []
        entity.shield = nil
        entity.retaliate = [ActionModel(type: .retaliate, value: .int(1))]
        await attack(monster, from: brute, value: 2)
        XCTAssertEqual(heard, [.hit, .retaliate, .hit], "the blow, the answer, the damage it does")
    }

    // MARK: - Taps

    /// A tap that isn't one of the choices on offer is answered; a tap when nothing is asked, or
    /// off the board, is not.
    func testATapThatIsNotAChoiceIsHeard() throws {
        let scene = try start()
        let brute = PieceID.character(gm.game.characters[0].id)
        let monster = aMonster
        let empty = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { !coord.boardState.isOccupied($0) })

        scene.clearHighlights()
        coord.interactionMode = .idle
        scene.handleTap(at: scene.sceneCenter(of: empty))
        coord.handlePieceTap(monster)
        XCTAssertEqual(heard, [], "nothing was being asked")

        let offered = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { !coord.boardState.isOccupied($0) && $0 != empty })
        scene.highlightHexes([offered], style: .move, offsetCol: coord.offsetCol, offsetRow: coord.offsetRow)
        scene.handleTap(at: scene.sceneCenter(of: empty))
        XCTAssertEqual(heard, [.invalid], "a hex, but not the highlighted one")

        heard = []
        coord.interactionMode = .selectingHealTarget(pieceID: brute, healValue: 2, validTargets: [brute])
        coord.handlePieceTap(monster)
        XCTAssertEqual(heard, [.invalid], "a figure that can't be healed")

        heard = []
        coord.interactionMode = .selectingAttackTarget(pieceID: brute, range: 1, validTargets: [])
        coord.handlePieceTap(monster)
        XCTAssertEqual(heard, [.invalid], "a figure that can't be attacked")
    }

    func testChoosingAnAttackTargetIsHeard() throws {
        _ = try start()
        coord.autoResolvePrompts = true
        let brute = PieceID.character(gm.game.characters[0].id)
        coord.interactionMode = .selectingAttackTarget(pieceID: brute, range: 1, validTargets: [aMonster])
        coord.handlePieceTap(aMonster)
        XCTAssertEqual(heard.first, .target)
    }
}
