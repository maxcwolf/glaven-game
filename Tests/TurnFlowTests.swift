import XCTest
import SwiftData
@testable import GlavenGameLib

/// A character's turn and the round around it, as found in the October 2026 audit: skipping
/// or taking back a choice leaves nothing behind, persistent bonuses run however the halves
/// are played, and the round ends in the rulebook's order.
@MainActor
final class TurnFlowTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    private func add(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    private func deck(_ name: String) -> [AbilityModel] {
        gm.editionStore.abilities(forDeck: name, edition: "gh")
    }

    private func turn(for character: GameCharacter, top: AbilityModel, bottom: AbilityModel) -> PlayerTurnController {
        character.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        return turn
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - Skipping and taking back a summon

    /// Skipping a summon's placement leaves no summon behind: none in the character's summons
    /// (counted for X, shown in the panel), the card isn't kept active for it, and later choices
    /// can still be taken back.
    func testSkippingASummonsPlacementLeavesNoSummon() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let summonCard = try XCTUnwrap(deck("tinkerer").first { $0.cardId == 31 })   // Harmless Contraption
        let other = try XCTUnwrap(deck("tinkerer").first { $0.cardId != 31 && ($0.bottomActions ?? []).contains { $0.type == .move } })
        let turn = turn(for: tinkerer, top: summonCard, bottom: other)
        while turn.phase == .executeTopAction {
            turn.executeCurrentAction()
            if case .placingSummon = coord.interactionMode { break }
        }
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the summon waits for its hex") }
        XCTAssertTrue(turn.canCancelChoice, "placing a summon can be taken back")

        turn.skipCurrentAction()
        XCTAssertNil(coord.pendingSummonPlacement)
        XCTAssertTrue(tinkerer.summons.isEmpty, "no summon that never reached the board")

        turn.skipRemainingActions()
        turn.useDefaultAction()   // a fresh choice: basic Move 2
        guard case .selectingMove = coord.interactionMode else { return XCTFail("a basic move") }
        XCTAssertTrue(turn.canCancelChoice)
    }

    /// Taking back a summon's placement takes back the summon too.
    func testCancellingASummonsPlacementTakesItBack() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let summonCard = try XCTUnwrap(deck("tinkerer").first { $0.cardId == 31 })
        let other = try XCTUnwrap(deck("tinkerer").first { $0.cardId != 31 })
        let turn = turn(for: tinkerer, top: summonCard, bottom: other)
        while turn.phase == .executeTopAction {
            turn.executeCurrentAction()
            if case .placingSummon = coord.interactionMode { break }
        }
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the summon waits for its hex") }
        turn.cancelChoice()
        XCTAssertNil(coord.pendingSummonPlacement)
        XCTAssertTrue(tinkerer.summons.isEmpty)
        XCTAssertFalse(turn.hasActed)
    }

    // MARK: - Bonuses at the start and end of the turn

    /// After Lumbering Bash's start-of-turn heal, the first half can still be played as the
    /// basic attack; the button offers it only while it can be used, with the real value.
    func testABasicAttackFollowsAStartOfTurnHeal() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [143]   // Lumbering Bash: Heal at the start of each turn
        let cards = deck("cragheart").filter { $0.cardId != 143 }
        let turn = turn(for: cragheart, top: cards[0], bottom: cards[1])
        XCTAssertNotNil(PlayerTurnController.bonusCard(of: turn.topActions[0]), "the heal comes first")
        XCTAssertTrue(turn.canUseDefaultAction)
        XCTAssertEqual(turn.defaultActionTitle, "Use Basic Attack 2")

        turn.executeCurrentAction()   // the start-of-turn heal
        coord.handlePieceTap(.character(cragheart.id))
        XCTAssertEqual(turn.currentActionIndex, 1)
        XCTAssertTrue(turn.canUseDefaultAction, "the half's own abilities haven't started")
        turn.useDefaultAction()
        XCTAssertTrue(turn.topUsedAsDefault)
    }

    /// Auto Turret's end-of-turn attack still comes when the last half is a basic move.
    func testAnEndOfTurnAttackFollowsABasicMove() async throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        tinkerer.activeCards = [54]   // Auto Turret
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(3, 6), origin: .placed)
        let cards = deck("tinkerer").filter { $0.cardId != 54 }
        let turn = turn(for: tinkerer, top: cards[0], bottom: cards[1])
        turn.skipRemainingActions()   // the top half
        XCTAssertEqual(turn.phase, .executeBottomAction)
        turn.useDefaultAction()       // the bottom half: basic Move 2
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("a move") }
        coord.handleHexTap(try XCTUnwrap(hexes.sorted().first))
        _ = await waitUntil { !turn.isWaiting }
        XCTAssertEqual(turn.phase, .executeBottomAction, "the turn isn't over: Auto Turret's attack is still to come")
        XCTAssertFalse(turn.canUseDefaultAction)
        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else { return XCTFail("Auto Turret attacks") }
    }

    /// Once a half's printed ability is performed, its basic action can no longer replace it.
    func testNoBasicActionAfterAPrintedAbility() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let trample = try XCTUnwrap(deck("brute").first { $0.name == "Trample" })
        let dagger = try XCTUnwrap(deck("brute").first { $0.name == "Spare Dagger" })
        let turn = turn(for: brute, top: dagger, bottom: trample)
        turn.skipRemainingActions()
        turn.executeCurrentAction()   // Trample's bottom: Move 4, Jump
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("a move") }
        coord.handleHexTap(try XCTUnwrap(hexes.sorted().first))
        XCTAssertFalse(turn.canUseDefaultAction)
    }

    // MARK: - The end of the round

    /// A round bonus card leaves the active area before the short rest is offered, so the rest
    /// can recover it — and with one other discard, the character may now rest at all.
    func testARoundBonusCardIsDiscardedBeforeTheShortRest() {
        coord.autoResolvePrompts = false
        let brute = add("brute", at: HexCoord(3, 3))
        coord.boardPhase = .execution
        gm.game.state = .next
        brute.handCards = [3, 4, 5]
        brute.discardedCards = [1]
        brute.activeCards = [2]
        brute.roundBonusCards = [2]
        coord.turnOrder = []
        coord.currentTurnIndex = -1
        coord.advanceToNextFigure()   // the round ends
        XCTAssertNotNil(coord.pendingShortRest, "two discards: a short rest is offered")
        XCTAssertEqual(Set(brute.discardedCards), [1, 2])
        XCTAssertTrue(brute.activeCards.isEmpty)
    }

    // MARK: - Choosing two cards

    /// A mis-tap is never stuck: with two cards chosen, another card takes the second's place; a
    /// chosen card makes itself lead, or (alone) is put back.
    func testTheTwoCardsCanBeChangedBeforeConfirming() {
        XCTAssertEqual(CardSelectionPanel.selection([], tapping: 4), [4])
        XCTAssertEqual(CardSelectionPanel.selection([4], tapping: 7), [4, 7])
        XCTAssertEqual(CardSelectionPanel.selection([4, 7], tapping: 2), [4, 2], "the second card is replaced")
        XCTAssertEqual(CardSelectionPanel.selection([4, 7], tapping: 7), [7, 4], "the tapped card leads")
        XCTAssertEqual(CardSelectionPanel.selection([4], tapping: 4), [], "put back")
    }

    // MARK: - Skipping a choice

    /// An item's extra condition rides on the target being chosen; skipping the choice drops it
    /// instead of putting it on a later target.
    func testSkippingATargetChoiceDropsWhatRodeOnIt() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        let dagger = try XCTUnwrap(deck("brute").first { $0.name == "Spare Dagger" })
        let trample = try XCTUnwrap(deck("brute").first { $0.name == "Trample" })
        let turn = turn(for: brute, top: dagger, bottom: trample)
        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else { return XCTFail("a target to pick") }
        coord.pendingExtraConditions = [.curse]
        turn.skipCurrentAction()
        XCTAssertEqual(coord.pendingExtraConditions, [])
    }

    // MARK: - Looting at the end of the turn

    /// Looting at the end of the turn isn't an ability: a stunned character, or one resting,
    /// still picks up the money token in their hex (p.28).
    func testAStunnedCharacterStillLootsAtTheEndOfTheTurn() {
        let brute = add("brute", at: HexCoord(3, 3))
        coord.boardState.lootTokens[HexCoord(3, 3)] = 1
        brute.entityConditions = [EntityCondition(name: .stun)]
        let gold = brute.loot
        coord.boardPhase = .execution
        gm.game.state = .next
        coord.turnOrder = [TurnOrderEntry(figure: .character(brute), initiative: 30)]
        coord.currentTurnIndex = -1
        coord.advanceToNextFigure()
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(3, 3)], "the token is picked up")
        XCTAssertGreaterThan(brute.loot, gold)
    }

    // MARK: - Reach

    /// With the Halberd a single-target melee attack reaches 2 hexes, and an enemy that far is a
    /// target for everything the attack prints: Crushing Grasp's Earth is infused.
    func testAHalberdAttackOnAFarEnemyPaysItsInfusion() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.items = [PassiveItems.halberd]
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed)
        let grasp = try XCTUnwrap(deck("cragheart").first { $0.cardId == 117 })   // Crushing Grasp
        let other = try XCTUnwrap(deck("cragheart").first { $0.cardId != 117 })
        let turn = turn(for: cragheart, top: grasp, bottom: other)
        let attack = try XCTUnwrap(turn.topActions.first { $0.type == .attack })
        XCTAssertFalse(turn.attackHasNoTarget(attack), "the button doesn't say no enemy is in range")
        while turn.phase == .executeTopAction && turn.topActions[turn.currentActionIndex].type != .attack {
            turn.executeCurrentAction()
        }
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode else { return XCTFail("a target 2 hexes away") }
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .earth }?.state, .new, "the attack's infusion")
    }

    // MARK: - Setting up

    /// Until the scenario begins, a placed character can be moved to another starting hex.
    func testAPlacedCharacterCanMoveBeforeTheScenarioBegins() throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let starts = coord.boardState.startingLocations.filter { !coord.boardState.isOccupied($0) }
        XCTAssertGreaterThan(starts.count, 1)
        coord.placeCharacter(characterID: brute.id, at: starts[0])
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], starts[0])

        coord.beginPlaceCharacter(characterID: brute.id)
        coord.handleHexTap(starts[1])
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], starts[1])
        XCTAssertFalse(coord.boardState.isOccupied(starts[0]))

        coord.finishSetup()
        coord.placeCharacter(characterID: brute.id, at: starts[0])
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], starts[1], "not once play has begun")
    }
}
