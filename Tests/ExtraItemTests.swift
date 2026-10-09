import XCTest
import SwiftData
@testable import GlavenGameLib

/// The last of the base game's items: summons, extra card plays and an extra turn, class
/// actions, and items used on another figure's turn.
@MainActor
final class ExtraItemTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var brute: GameCharacter { gm.game.characters[0] }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(3, 3))
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.game.scenario = Scenario(data: data)
    }

    private func card(_ name: String, deck: String = "brute") throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
    }

    /// Trample on top (Attack 3), Spare Dagger's bottom; the rest of the hand as given.
    @discardableResult
    private func startTurn(hand extra: [String] = []) throws -> PlayerTurnController {
        let trample = try card("Trample"), other = try card("Spare Dagger")
        brute.handCards = [trample.cardId!, other.cardId!] + (try extra.map { try card($0).cardId! })
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: other)
        return turn
    }

    private func use(_ key: String) throws {
        let item = try XCTUnwrap(coord.usableItems().first { $0.itemKey == key }, "\(key) is offered")
        XCTAssertTrue(coord.useItem(item), key)
    }

    // MARK: - Summons

    /// Ring of Skulls, Power Core, Falcon Figurine, Mountain Hammer: the item's figure, placed
    /// next to the character like a card's summon; the item is consumed.
    func testSummonItemsPlaceTheirFigure() throws {
        brute.items = ["gh-123", "gh-35"]
        try startTurn()
        try use("gh-123")
        guard case .placingSummon(_, _, let hexes) = coord.interactionMode else { return XCTFail("placing the skeleton") }
        XCTAssertTrue(hexes.allSatisfy { $0.distance(to: HexCoord(3, 3)) == 1 })
        coord.handleHexTap(try XCTUnwrap(hexes.sorted().first))
        let skeleton = try XCTUnwrap(brute.summons.first)
        XCTAssertEqual(skeleton.name, "skeleton")
        XCTAssertEqual(skeleton.maxHealth, 3)
        XCTAssertEqual(skeleton.movement, 2)
        XCTAssertTrue(coord.isOnBoard(.summon(id: skeleton.id)))
        XCTAssertTrue(brute.consumedItems.contains("gh-123"))

        try use("gh-35")
        guard case .placingSummon = coord.interactionMode else { return XCTFail("placing the falcon") }
        let falcon = try XCTUnwrap(brute.summons.last)
        XCTAssertTrue(falcon.flying, "the Jade Falcon flies")
    }

    func testASummonItemIsntOfferedWithNoRoom() throws {
        brute.items = ["gh-132"]
        try startTurn()
        for (index, hex) in HexCoord(3, 3).neighbors.enumerated() {
            coord.boardState.placePiece(.objective(id: 900 + index), at: hex)
        }
        XCTAssertFalse(coord.usableItems().contains { $0.itemKey == "gh-132" })
    }

    // MARK: - Playing more cards

    /// Ends the turn's two halves without doing them.
    private func finishHalves(_ turn: PlayerTurnController) {
        turn.skipRemainingActions()
        turn.skipRemainingActions()
    }

    /// Ring of Haste: at the end of the turn, another card from the hand for its bottom half;
    /// that card is discarded after, and the turn can then end.
    func testRingOfHastePlaysACardsBottomHalf() throws {
        brute.items = ["gh-42"]
        let turn = try startTurn(hand: ["Grab and Go", "Sweeping Blow"])
        XCTAssertFalse(coord.usableItems().contains { $0.itemKey == "gh-42" }, "not before the turn's halves are done")
        finishHalves(turn)
        XCTAssertEqual(turn.phase, .turnComplete)
        try use("gh-42")
        let pending = try XCTUnwrap(coord.pendingCardPlay)
        let grab = try card("Grab and Go"), sweep = try card("Sweeping Blow")
        XCTAssertEqual(Set(pending.options), [grab.cardId!, sweep.cardId!], "the turn's own cards are put away")
        XCTAssertFalse(brute.consumedItems.contains("gh-42"), "used once the card is chosen")

        coord.resolveCardPlay([grab.cardId!])
        XCTAssertTrue(brute.consumedItems.contains("gh-42"))
        XCTAssertEqual(turn.phase, .executeExtraHalf)
        XCTAssertEqual(turn.currentSteps.first?.type, .move, "Grab and Go's bottom: Move 4")
        XCTAssertEqual(BoardView.halfHeading(phase: turn.phase, top: turn.topCard, bottom: turn.bottomCard,
                                             extra: turn.extraPlay), "Extra card, bottom half · Grab and Go")
        turn.executeCurrentAction()
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("moving") }
        XCTAssertEqual(range, 4)
        turn.skipRemainingActions()
        XCTAssertEqual(turn.phase, .turnComplete, "back to the end of the turn")
        XCTAssertTrue(brute.discardedCards.contains(grab.cardId!))
        XCTAssertFalse(brute.handCards.contains(grab.cardId!))
        XCTAssertTrue(brute.handCards.contains(sweep.cardId!))
    }

    /// Ring of Brutality: the top half; changing your mind leaves the ring unused.
    func testRingOfBrutalityPlaysATopHalfAndCanBeLeftUnused() throws {
        brute.items = ["gh-56"]
        let turn = try startTurn(hand: ["Overwhelming Assault"])
        finishHalves(turn)
        try use("gh-56")
        coord.resolveCardPlay([])
        XCTAssertFalse(brute.consumedItems.contains("gh-56"), "not used without a card")
        XCTAssertEqual(turn.phase, .turnComplete)

        try use("gh-56")
        coord.resolveCardPlay([try card("Overwhelming Assault").cardId!])
        XCTAssertEqual(turn.currentSteps.first?.type, .attack, "Overwhelming Assault's top: Attack 6")
    }

    /// Second Chance Ring: two more cards for another turn this round, led by a later initiative.
    func testSecondChanceRingGivesAnotherTurnAtALaterInitiative() throws {
        brute.items = ["gh-70"]
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let spellweaver = gm.game.characters[1]
        brute.initiative = 30
        spellweaver.initiative = 70
        coord.turnOrder = [TurnOrderEntry(figure: .character(brute), initiative: 30),
                           TurnOrderEntry(figure: .character(spellweaver), initiative: 70)]
        coord.currentTurnIndex = 0
        let turn = try startTurn(hand: ["Eye for an Eye", "Grab and Go", "Shield Bash"])   // 18, 87, 15
        finishHalves(turn)
        try use("gh-70")
        let eye = try card("Eye for an Eye"), grab = try card("Grab and Go"), bash = try card("Shield Bash")
        XCTAssertEqual(coord.pendingCardPlay?.kind, .anotherTurn(after: 30))

        coord.resolveCardPlay([eye.cardId!, bash.cardId!])
        XCTAssertFalse(brute.consumedItems.contains("gh-70"), "an earlier lead (18) isn't allowed")
        XCTAssertEqual(coord.turnOrder.count, 2)

        try use("gh-70")
        coord.resolveCardPlay([grab.cardId!, eye.cardId!])
        XCTAssertTrue(brute.consumedItems.contains("gh-70"))
        XCTAssertEqual(brute.initiative, 87)
        XCTAssertEqual(coord.turnOrder.map(\.initiative), [30, 70, 87], "after the Spellweaver's 70")
        XCTAssertTrue(coord.turnOrder[2].anotherTurn)
        XCTAssertEqual(coord.selectedCardPairs[brute.id]?.top.cardId, grab.cardId)
        XCTAssertEqual(coord.selectedCardPairs[brute.id]?.bottom.cardId, eye.cardId)

        // The Spellweaver isn't on the board, so the Brute's second turn comes straight away.
        coord.boardPhase = .execution
        coord.finishPlayerTurn()
        let second = try XCTUnwrap(coord.activePlayerTurn, "the Brute's second turn")
        XCTAssertFalse(second === turn)
        XCTAssertEqual(second.characterID, brute.id)
        XCTAssertEqual(second.topCard?.cardId, grab.cardId)
        XCTAssertEqual(second.phase, .executeTopAction)
    }

    /// Staff of Command: after a Command half, a card's half on the same side, before the
    /// turn goes on to its other half.
    func testStaffOfCommandPlaysTheSameSideAfterACommand() throws {
        gm.characterManager.addCharacter(name: "two-mini", edition: "gh")
        let tyrant = gm.game.characters[1]
        coord.boardState.placePiece(.character(tyrant.id), at: HexCoord(6, 6))
        tyrant.items = ["gh-150"]
        let maul = try card("Maul", deck: "two-mini"), heal = try card("Disappearing Wounds", deck: "two-mini")
        let strike = try card("Energizing Strike", deck: "two-mini")
        tyrant.handCards = [maul.cardId!, heal.cardId!, strike.cardId!]
        let turn = PlayerTurnController(characterID: tyrant.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: maul, bottom: heal)    // Maul's top is a Command
        XCTAssertFalse(coord.usableItems().contains { $0.itemKey == "gh-150" })

        turn.skipRemainingActions()
        XCTAssertEqual(turn.phase, .executeBottomAction)
        XCTAssertEqual(turn.finishedHalf, .init(top: true, kinds: ["command"]))
        try use("gh-150")
        XCTAssertEqual(coord.pendingCardPlay?.kind, .half(top: true))
        XCTAssertEqual(coord.pendingCardPlay?.options, [strike.cardId!], "not the two being played")
        coord.resolveCardPlay([strike.cardId!])
        XCTAssertTrue(tyrant.spentItems.contains("gh-150"), "the staff is spent")
        XCTAssertEqual(turn.phase, .executeExtraHalf)
        XCTAssertEqual(turn.extraPlay?.top, true)

        turn.skipRemainingActions()
        XCTAssertEqual(turn.phase, .executeBottomAction, "the turn's bottom half is still to come")
        XCTAssertEqual(turn.currentActionIndex, 0)
        XCTAssertTrue(tyrant.discardedCards.contains(strike.cardId!))
    }

    /// Master's Lute: after a Song, Attack 2 or Move 2.
    func testMastersLuteGivesAnAttackOrMoveAfterASong() throws {
        gm.characterManager.addCharacter(name: "music-note", edition: "gh")
        let singer = gm.game.characters[1]
        coord.boardState.placePiece(.character(singer.id), at: HexCoord(6, 6))
        singer.items = ["gh-146"]
        let ditty = try card("Defensive Ditty", deck: "music-note"), dagger = try card("Warding Dagger", deck: "music-note")
        singer.handCards = [ditty.cardId!, dagger.cardId!]
        let turn = PlayerTurnController(characterID: singer.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: ditty, bottom: dagger)
        turn.skipRemainingActions()
        try use("gh-146")
        XCTAssertNotNil(coord.pendingActionChoice)
        XCTAssertFalse(coord.usableItems().contains { $0.itemKey == "gh-146" }, "once per Song")
        coord.resolveActionChoice("move")
        guard case .selectingMove(let mover, let range, _, _, _) = coord.interactionMode else { return XCTFail("moving") }
        XCTAssertEqual(mover, .character(singer.id))
        XCTAssertEqual(range, 2)
    }

    // MARK: - Class actions

    private func addGuard(at hex: HexCoord) throws -> PieceID {
        try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
    }

    /// Cloak of the Hunter: a Doom's target is muddled (the Doom's token is still placed by hand).
    func testCloakOfTheHunterMuddlesTheDoomsTarget() throws {
        gm.characterManager.addCharacter(name: "angry-face", edition: "gh")
        let stalker = gm.game.characters[1]
        coord.boardState.placePiece(.character(stalker.id), at: HexCoord(6, 6))
        let guardPiece = try addGuard(at: HexCoord(6, 9))
        let rain = try card("Rain of Arrows", deck: "angry-face"), other = try card("Felling Swoop", deck: "angry-face")
        stalker.handCards = [rain.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: stalker.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: rain)    // Rain of Arrows' bottom is a Doom
        turn.setBottomFirst(true)

        // Without the cloak the Doom asks nothing on the board.
        turn.executeCurrentAction()
        if case .selectingConditionTarget = coord.interactionMode { XCTFail("no cloak, no muddle") }

        stalker.items = [PassiveItems.cloakOfTheHunter]
        turn.cancelChoice()
        let again = PlayerTurnController(characterID: stalker.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = again
        again.selectCards(top: other, bottom: rain)
        again.setBottomFirst(true)
        again.executeCurrentAction()
        guard case .selectingConditionTarget(_, let condition, let targets) = coord.interactionMode else {
            return XCTFail("choosing the Doom's target")
        }
        XCTAssertEqual(condition, .muddle)
        XCTAssertTrue(targets.contains(guardPiece), "any enemy in sight, at any range")
        coord.handlePieceTap(guardPiece)
        XCTAssertTrue(coord.isConditionActive(.muddle, on: guardPiece))
    }
}
