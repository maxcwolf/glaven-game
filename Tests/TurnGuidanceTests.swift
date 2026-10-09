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
            .placingToken(pieceID: .character(gm.game.characters[0].id), token: .trap(damage: 6, subType: nil, experience: 2),
                          remaining: 1, validHexes: hexes),
            .placingToken(pieceID: .character(gm.game.characters[0].id), token: .obstacle, remaining: 2, validHexes: hexes),
            .choosingPerformer(pieceID: brute, action: ActionModel(type: .attack, value: .int(6)), candidates: [brute]),
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
        XCTAssertEqual(coord.instruction(for: modes[10])?.title, "Push Bandit Guard 1")
        XCTAssertEqual(coord.instruction(for: modes[7])?.title, "Place a 6 damage trap")
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

    // MARK: - Cancel a choice

    private func cragheartTurn(top: String, bottom: String, autoResolve: Bool = true) throws -> (GameManager, BoardCoordinator, PlayerTurnController, PieceID) {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        coord.autoResolvePrompts = autoResolve
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let cragheart = gm.game.characters[0]
        coord.boardState.placePiece(.character(cragheart.id), at: HexCoord(3, 3))
        let target = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal,
                                                      at: HexCoord(5, 3), origin: .placed))
        let turn = PlayerTurnController(characterID: cragheart.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        let deck = gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
        let topCard = try XCTUnwrap(deck.first { $0.name == top }), bottomCard = try XCTUnwrap(deck.first { $0.name == bottom })
        cragheart.handCards = [topCard.cardId!, bottomCard.cardId!]
        turn.selectCards(top: topCard, bottom: bottomCard)
        return (gm, coord, turn, target)
    }

    private func earth(_ gm: GameManager) -> ElementState? {
        gm.game.elementBoard.first { $0.type == .earth }?.state
    }

    /// Cancelling a target choice takes the ability back: Earthen Clod's Earth, consumed as the
    /// attack began, is back, the log forgets it, and the attack can be performed again.
    func testCancellingATargetChoiceTakesTheAbilityBack() throws {
        let (gm, coord, turn, target) = try cragheartTurn(top: "Earthen Clod", bottom: "Rumbling Advance")
        if let i = gm.game.elementBoard.firstIndex(where: { $0.type == .earth }) { gm.game.elementBoard[i].state = .strong }
        let logBefore = coord.turnLog.count

        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else { return XCTFail("waits for a target") }
        XCTAssertEqual(earth(gm), .consumed, "Earth consumed as the attack began")
        XCTAssertTrue(turn.canCancelChoice)
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canCancel, true)

        turn.cancelChoice()
        XCTAssertTrue({ if case .idle = coord.interactionMode { return true }; return false }())
        XCTAssertEqual(earth(gm), .strong, "the Earth is back")
        XCTAssertEqual(coord.turnLog.count, logBefore, "the log forgets it")
        XCTAssertEqual(turn.currentActionIndex, 0, "the attack is still to do")
        XCTAssertFalse(turn.isWaiting)
        XCTAssertFalse(turn.hasActed, "the cards can still be rearranged")

        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else { return XCTFail("and asks again") }
        XCTAssertEqual(earth(gm), .consumed)
        coord.handlePieceTap(target)
        XCTAssertFalse(turn.canCancelChoice, "a target chosen can't be taken back")
    }

    /// Once the board has changed (one of Avalanche's two obstacles placed) the choice can't be
    /// cancelled.
    func testNoCancelOnceTheBoardHasChanged() throws {
        // The player places the obstacles.
        let (gm, coord, turn, _) = try cragheartTurn(top: "Crater", bottom: "Avalanche", autoResolve: false)
        defer { withExtendedLifetime(gm) {} }   // the turn holds the manager weakly
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .placingToken(_, .obstacle, 2, let hexes) = coord.interactionMode else {
            return XCTFail("two obstacles to place, got \(coord.interactionMode)")
        }
        XCTAssertTrue(turn.canCancelChoice, "nothing placed yet")
        coord.handleHexTap(try XCTUnwrap(hexes.sorted().first))
        guard case .placingToken(_, .obstacle, 1, _) = coord.interactionMode else { return XCTFail("the second obstacle") }
        XCTAssertFalse(turn.canCancelChoice, "one obstacle already placed")
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canCancel, false)
    }
}
