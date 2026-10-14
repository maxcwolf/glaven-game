import XCTest
@testable import GlavenGameLib

/// The Beast Tyrant's bear (`BoardCoordinator+Companion`, `PlayerTurnController.commandedFigure`):
/// set up beside him as the scenario starts, a summon of his every round, and the one who
/// performs his Command halves.
@MainActor
final class CompanionTests: XCTestCase {

    private func simulator(asking: Bool = false) throws -> ScenarioSimulator {
        try ScenarioSimulator(scenario: "1", options: .init(characters: ["two-mini", "brute"], seed: 1, autoResolvePrompts: !asking))
    }

    private func tyrant(_ sim: ScenarioSimulator) -> GameCharacter { sim.gm.game.characters[0] }

    private func card(_ sim: ScenarioSimulator, _ name: String) throws -> AbilityModel {
        try XCTUnwrap(sim.gm.editionStore.abilities(forDeck: "two-mini", edition: "gh").first { $0.name == name }, name)
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    /// Clear the board of monsters but one, beside the bear and not the Tyrant; the Tyrant's turn
    /// playing `top` and `bottom`, the bottom first.
    private func stage(_ sim: ScenarioSimulator, top: String, bottom: String) throws -> (turn: PlayerTurnController, bear: PieceID, foe: PieceID) {
        let coord = sim.coord
        let board = coord.boardState
        let me = PieceID.character(tyrant(sim).id)
        let bear = try XCTUnwrap(coord.companionPiece(of: tyrant(sim)))
        let foe = try XCTUnwrap(board.piecePositions.keys.sorted().first { if case .monster = $0 { return true }; return false })
        for piece in board.piecePositions.keys where piece != foe {
            if case .monster = piece { board.removePiece(piece) }
        }
        if let entity = coord.entity(for: foe) { entity.maxHealth = 40; entity.health = 40 }
        (coord.entity(for: foe) as? GameMonsterEntity)?.shield = nil
        let bearHex = try XCTUnwrap(board.piecePositions[bear])
        let spot = try XCTUnwrap(board.neighbors(of: bearHex).sorted().first { hex in
            coord.isEmptyHex(hex) && !board.areAdjacent(hex, try! XCTUnwrap(board.piecePositions[me]))
        }, "a hex beside the bear and not beside the Tyrant")
        board.removePiece(foe)
        board.placePiece(foe, at: spot)
        let first = try card(sim, top), second = try card(sim, bottom)
        tyrant(sim).handCards = [first.cardId!, second.cardId!]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: tyrant(sim).id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: first, bottom: second)
        turn.setBottomFirst(true)
        return (turn, bear, foe)
    }

    /// "Summon the bear in an adjacent hex at the start of each scenario": 8 + 2×level hit
    /// points, Move 3, Attack 2; it acts from the first round.
    func testTheBearIsSetUpBesideTheTyrant() throws {
        let sim = try simulator()
        let character = tyrant(sim)
        let bear = try XCTUnwrap(sim.coord.companion(of: character))
        let piece = try XCTUnwrap(sim.coord.companionPiece(of: character))
        let board = sim.coord.boardState
        XCTAssertTrue(board.areAdjacent(try XCTUnwrap(board.piecePositions[piece]), try XCTUnwrap(board.piecePositions[.character(character.id)])))
        XCTAssertEqual(bear.maxHealth, 8 + 2 * character.level)
        XCTAssertEqual(bear.movement, 3)
        XCTAssertEqual(bear.attack, .int(2))
        XCTAssertEqual(bear.state, .active)
        XCTAssertEqual(sim.coord.name(piece), "Bear")
        XCTAssertEqual(character.summons.count, 1, "one bear")
        XCTAssertNil(sim.coord.companion(of: sim.gm.game.characters[1]), "the Brute has none")
        XCTAssertNotNil(sim.coord.cardSelectingCharacterID, "and the first round's cards are chosen")
    }

    /// The player taps where the bear starts, beside the Tyrant, before anyone chooses cards.
    func testThePlayerPlacesTheBear() async throws {
        let sim = try simulator(asking: true)
        let coord = sim.coord
        _ = await waitUntil { coord.pendingHexChoice != nil }
        let pending = try XCTUnwrap(coord.pendingHexChoice, "the bear's hex is asked for")
        let me = try XCTUnwrap(coord.boardState.piecePositions[.character(tyrant(sim).id)])
        XCTAssertTrue(pending.options.allSatisfy { coord.boardState.areAdjacent($0, me) })
        XCTAssertNil(coord.cardSelectingCharacterID, "no one chooses cards yet")
        let chosen = try XCTUnwrap(pending.options.last)
        coord.resolveHexChoice(chosen)
        let placed = await waitUntil { coord.companionPiece(of: self.tyrant(sim)) != nil }
        XCTAssertTrue(placed)
        XCTAssertEqual(coord.boardState.piecePositions[try XCTUnwrap(coord.companionPiece(of: tyrant(sim)))], chosen)
        let selecting = await waitUntil { coord.cardSelectingCharacterID != nil }
        XCTAssertTrue(selecting)
    }

    /// A Command half is the bear's: Disappearing Wounds' "Command: Attack 2" is aimed from the
    /// bear's hex, at an enemy beside it and not beside the Tyrant; the experience is his.
    func testACommandIsPerformedByTheBear() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, foe) = try stage(sim, top: "Venomous Ally", bottom: "Disappearing Wounds")
        let xp = tyrant(sim).experience
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(let attacker, _, let targets) = coord.interactionMode else {
            return XCTFail("the bear's attack waits for its target, got \(coord.interactionMode)")
        }
        XCTAssertEqual(attacker, bear, "the bear attacks")
        XCTAssertEqual(targets, [foe])
        XCTAssertEqual(turn.commandedFigure, bear)
        coord.handlePieceTap(foe)
        _ = await waitUntil { !turn.isWaiting }
        XCTAssertLessThan(coord.entity(for: foe)?.health ?? 40, 40, "hit")
        XCTAssertTrue(coord.turnLog.contains { $0.message.hasPrefix("Bear attacks") }, "\(coord.turnLog.suffix(5).map(\.message))")
        turn.executeCurrentAction()   // the card's experience
        XCTAssertEqual(tyrant(sim).experience, xp + 1, "the Tyrant's experience")
    }

    /// "Command: Attack 4, Strengthen self" (Energizing Strike): the bear attacks and is
    /// strengthened — not its target, nor the Tyrant. "Command: Heal 4, self" (Patch Fur) heals
    /// the bear.
    func testSelfMeansTheBearOnACommand() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, foe) = try stage(sim, top: "Energizing Strike", bottom: "Patch Fur")
        turn.setBottomFirst(false)
        let bearEntity = try XCTUnwrap(coord.entity(for: bear))
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(let attacker, _, _) = coord.interactionMode else { return XCTFail("\(coord.interactionMode)") }
        XCTAssertEqual(attacker, bear)
        coord.handlePieceTap(foe)
        _ = await waitUntil { !turn.isWaiting }
        XCTAssertTrue(coord.isConditionActive(.strengthen, on: bear) || bearEntity.entityConditions.contains { $0.name == .strengthen },
                      "the bear is strengthened")
        XCTAssertFalse(coord.isConditionActive(.strengthen, on: foe), "not its target")
        XCTAssertFalse(tyrant(sim).entityConditions.contains { $0.name == .strengthen }, "nor the Tyrant")
        XCTAssertFalse(coord.turnLog.contains { $0.message.hasPrefix("Bear attacks") && $0.message.contains("advantage") },
                       "its own Strengthen comes after the attack")
    }

    func testAHealOnACommandIsTheBears() throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, _) = try stage(sim, top: "Venomous Ally", bottom: "Patch Fur")
        let bearEntity = try XCTUnwrap(coord.entity(for: bear))
        bearEntity.health = bearEntity.maxHealth - 5
        tyrant(sim).health = tyrant(sim).maxHealth - 2
        turn.executeCurrentAction()   // Command: Heal 4, self
        XCTAssertEqual(bearEntity.health, bearEntity.maxHealth - 1, "the bear heals 4")
        XCTAssertEqual(tyrant(sim).health, tyrant(sim).maxHealth - 2, "not the Tyrant")
    }

    /// "Command: Loot 1" (Soaring Ally): the bear loots, beside itself, and the money is the Tyrant's.
    func testWhatTheBearLootsIsTheTyrants() throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, foe) = try stage(sim, top: "Venomous Ally", bottom: "Soaring Ally")
        coord.boardState.removePiece(foe)
        let board = coord.boardState
        let me = try XCTUnwrap(board.piecePositions[.character(tyrant(sim).id)])
        let spot = try XCTUnwrap(board.neighbors(of: try XCTUnwrap(board.piecePositions[bear])).sorted().first {
            coord.isEmptyHex($0) && !board.areAdjacent($0, me) && $0 != me })
        board.placeLoot(at: spot)
        let gold = tyrant(sim).loot
        turn.executeCurrentAction()
        XCTAssertNil(board.lootTokens[spot], "taken")
        XCTAssertGreaterThan(tyrant(sim).loot, gold, "the Tyrant's")
    }

    /// Earthen Spikes: "Shield 2, Retaliate 2 — affect all summoned allies" for the round: the
    /// bear and every other summon on the party's side have them, the Tyrant doesn't; they go
    /// as the round ends.
    func testABonusForAllSummonedAlliesIsTheirs() throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, _) = try stage(sim, top: "Venomous Ally", bottom: "Earthen Spikes")
        let bearEntity = try XCTUnwrap(coord.entity(for: bear) as? GameSummon)
        turn.executeCurrentAction()
        XCTAssertEqual(bearEntity.shield?.value?.intValue, 2, "Shield 2")
        XCTAssertEqual(bearEntity.retaliate.map { $0.value?.intValue ?? 0 }, [2], "Retaliate 2, printed under the Shield")
        XCTAssertNil(tyrant(sim).shield, "not the Tyrant")
        XCTAssertTrue(tyrant(sim).retaliate.isEmpty)
        // The round ends.
        sim.gm.game.state = .next
        sim.gm.roundManager.nextGameState()
        XCTAssertNil(bearEntity.shield, "a round's bonus")
        XCTAssertTrue(bearEntity.retaliate.isEmpty)
    }

    /// With the bear gone, a Command does nothing: no attack, and the half isn't performed.
    func testACommandWithTheBearGoneDoesNothing() throws {
        let sim = try simulator()
        let coord = sim.coord
        let (turn, bear, _) = try stage(sim, top: "Venomous Ally", bottom: "Disappearing Wounds")
        coord.sufferDamage(999, to: bear, killer: nil)
        XCTAssertNil(coord.companionPiece(of: tyrant(sim)))
        turn.executeCurrentAction()
        if case .selectingAttackTarget = coord.interactionMode { XCTFail("no one to attack with") }
        XCTAssertTrue(coord.turnLog.contains { $0.message.contains("Command does nothing") })
    }

    /// The Tyrant's own items stay his: Silent Stiletto's Pierce isn't the bear's on a Command.
    func testTheTyrantsItemsArentTheBears() throws {
        let sim = try simulator()
        tyrant(sim).items = ["gh-137"]
        let (turn, _, _) = try stage(sim, top: "Venomous Ally", bottom: "Disappearing Wounds")
        turn.executeCurrentAction()
        XCTAssertEqual(turn.pendingPierce, 0, "no Pierce for the bear")
    }

    /// The bear is one of his summons: it takes its own turn with them.
    func testTheBearActsAsASummon() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (_, bear, foe) = try stage(sim, top: "Venomous Ally", bottom: "Disappearing Wounds")
        coord.activePlayerTurn = nil
        await SummonTurnController(coordinator: coord, gameManager: sim.gm).executeSummonTurns(for: tyrant(sim))
        XCTAssertLessThan(coord.entity(for: foe)?.health ?? 40, 40, "the bear attacked")
        XCTAssertNotNil(coord.boardState.piecePositions[bear])
    }
}

/// Amputate's bottom: "Heal 7, Range 1" with Stun on the one healed (it nests the Stun in the
/// heal), played on a test board.
@MainActor
final class NestedAbilityCardTests: XCTestCase {

    func testAmputateHealsAndStunsTheOneHealed() throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["saw", "brute"], seed: 1, autoResolvePrompts: true))
        let coord = sim.coord
        let board = coord.boardState
        let sawbones = sim.gm.game.characters[0], brute = sim.gm.game.characters[1]
        let me = try XCTUnwrap(board.piecePositions[.character(sawbones.id)])
        let beside = try XCTUnwrap(board.neighbors(of: me).sorted().first { coord.isEmptyHex($0) })
        board.removePiece(.character(brute.id))
        board.placePiece(.character(brute.id), at: beside)
        brute.health = 1
        let deck = sim.gm.editionStore.abilities(forDeck: "saw", edition: "gh")
        let amputate = try XCTUnwrap(deck.first { $0.name == "Amputate" })
        let other = try XCTUnwrap(deck.first { $0.cardId != amputate.cardId && $0.level == .int(1) })
        sawbones.handCards = [amputate.cardId!, other.cardId!]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: sawbones.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: amputate)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()   // Heal 7, Range 1, Stun
        guard case .selectingHealTarget(_, _, let targets) = coord.interactionMode else { return XCTFail("\(coord.interactionMode)") }
        XCTAssertTrue(targets.contains(.character(brute.id)))
        coord.handlePieceTap(.character(brute.id))
        XCTAssertEqual(brute.health, min(brute.maxHealth, 8), "Heal 7")
        XCTAssertTrue(brute.entityConditions.contains { $0.name == .stun }, "and stunned")
        XCTAssertFalse(sawbones.entityConditions.contains { $0.name == .stun })
    }
}
