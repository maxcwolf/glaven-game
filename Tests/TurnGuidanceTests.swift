import XCTest
@testable import GlavenGameLib

/// The board always says whose turn it is, who acts next, and what the player should tap; and
/// "Skip This Action" skips one ability without resolving it.
@MainActor
final class TurnGuidanceTests: XCTestCase {

    // MARK: - Instruction banner

    /// Every interaction mode except idle has a heading and a "tap…" line that read cleanly.
    func testEveryInteractionModeTellsThePlayerWhatToDo() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        let brute = PieceID.character(gm.game.characters[0].id)
        let guardPiece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal,
                                                          at: HexCoord(5, 5), origin: .placed))
        let hexes: Set<HexCoord> = [HexCoord(1, 1)]

        let modes: [InteractionMode] = [
            .placingCharacter(characterID: gm.game.characters[0].id),
            .selectingMove(pieceID: brute, range: 3, validHexes: hexes),
            .selectingMove(pieceID: brute, range: 3, validHexes: hexes, mode: .jump),
            .selectingMove(pieceID: brute, range: 4, validHexes: hexes, teleport: true),
            .selectingAttackTarget(pieceID: brute, range: 1, validTargets: [guardPiece]),
            .selectingMultiAttackTargets(pieceID: brute, range: 2, validTargets: [guardPiece], targetCount: 2, selected: []),
            .placingSummon(summonID: "x", characterID: gm.game.characters[0].id, validHexes: hexes),
            .selectingPushPullHex(target: guardPiece, attackerPos: HexCoord(4, 5), validHexes: hexes,
                                  remainingSteps: 2, isPush: true),
            .selectingConditionTarget(pieceID: brute, condition: .poison, validTargets: [guardPiece]),
            .selectingHealTarget(pieceID: brute, healValue: 2, validTargets: [brute]),
            .selectingForcedMoveTarget(pieceID: brute, steps: 1, isPush: false, validTargets: [guardPiece]),
            .watchingMonsterTurn,
        ]
        XCTAssertNil(coord.instruction(for: .idle))
        for mode in modes {
            let instruction = try XCTUnwrap(coord.instruction(for: mode), "\(mode)")
            XCTAssertEqual(PlayerTextTests.lint(instruction.title), [], "\(mode): \(instruction.title)")
            XCTAssertEqual(PlayerTextTests.lint(instruction.detail), [], "\(mode): \(instruction.detail)")
            XCTAssertFalse(instruction.title.isEmpty)
        }
        XCTAssertEqual(coord.instruction(for: modes[2])?.title, "Jump 3")
        XCTAssertEqual(coord.instruction(for: modes[7])?.title, "Push Bandit Guard 1")
        XCTAssertEqual(coord.instruction(for: .watchingMonsterTurn)?.canSkip, false)
    }

    // MARK: - Turn rail

    func testTurnRailFollowsTheRound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        XCTAssertEqual(sim.coord.turnRail, [], "no turn order while cards are being chosen")
        var checked = 0
        await sim.play(rounds: 2) {
            let rail = sim.coord.turnRail
            guard sim.coord.boardPhase == .execution, !rail.isEmpty else { return }
            checked += 1
            XCTAssertLessThanOrEqual(rail.filter { $0.state == .current }.count, 1)
            XCTAssertEqual(rail.map(\.initiative), rail.map(\.initiative).sorted(), "in initiative order")
            if let current = rail.firstIndex(where: { $0.state == .current }) {
                XCTAssertTrue(rail[..<current].allSatisfy { $0.state == .done }, "everyone before the actor has acted")
            }
            for entry in rail {
                XCTAssertEqual(PlayerTextTests.lint(entry.name), [], entry.name)
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }

    // MARK: - Skip this action

    /// Skipping an attack while choosing its target moves on to the next ability of the same
    /// half (Massive Boulder: Attack 3, then infuse Earth) without attacking.
    func testSkipThisActionSkipsOnlyTheCurrentAbility() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        coord.autoResolvePrompts = true
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let cragheart = gm.game.characters[0]
        coord.boardState.placePiece(.character(cragheart.id), at: HexCoord(3, 3))
        let target = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal,
                                                      at: HexCoord(4, 3), origin: .placed))
        let guardEntity = try XCTUnwrap(coord.entity(for: target))
        let healthBefore = guardEntity.health

        let turn = PlayerTurnController(characterID: cragheart.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        let deck = gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
        let boulder = try XCTUnwrap(deck.first { $0.name == "Massive Boulder" })
        let advance = try XCTUnwrap(deck.first { $0.name == "Rumbling Advance" })
        turn.selectCards(top: boulder, bottom: advance)
        XCTAssertEqual(turn.topActions.map(\.type), [.attack, .element])

        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else {
            return XCTFail("the attack waits for a target, got \(coord.interactionMode)")
        }
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canSkip, true)

        turn.skipCurrentAction()
        XCTAssertTrue({ if case .idle = coord.interactionMode { return true }; return false }())
        XCTAssertEqual(guardEntity.health, healthBefore, "the skipped attack does nothing")
        XCTAssertEqual(turn.phase, .executeTopAction, "still on the top half")
        XCTAssertEqual(turn.currentActionIndex, 1, "the infusion is next")
        XCTAssertNotEqual(gm.game.elementBoard.first { $0.type == .earth }?.state, .new,
                          "the infusion hasn't happened yet")

        turn.executeCurrentAction()
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .earth }?.state, .new, "and still can")
    }
}
