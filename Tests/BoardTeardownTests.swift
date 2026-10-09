import XCTest
import SpriteKit
import SwiftData
@testable import GlavenGameLib

/// Leaving the board (Save & Quit, Abandon, New Campaign) or restarting it while a turn waits on
/// the player or an animation: the waiting turn ends instead of hanging on, it never acts on the
/// next board, and no prompt of the old board is left over.
@MainActor
final class BoardTeardownTests: XCTestCase {

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

    private var brute: GameCharacter { gm.game.characters[0] }

    private func addBrute(at hex: HexCoord) {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(.character(brute.id), at: hex)
    }

    private func settle(_ times: Int = 50) async {
        for _ in 0..<times { await Task.yield() }
    }

    /// A player attack waiting for its modifier draw when the player leaves: the turn ends and is
    /// freed, the attack never lands, and the draw isn't offered again.
    func testLeavingMidDrawEndsTheTurn() async throws {
        addBrute(at: HexCoord(3, 3))
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        let bandit = try XCTUnwrap(coord.entity(for: piece))
        coord.autoResolvePrompts = false
        weak var waitingTurn: PlayerTurnController?
        do {
            let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
            let top = try XCTUnwrap(deck.first { $0.name == "Spare Dagger" })
            let bottom = try XCTUnwrap(deck.first { $0.name == "Trample" })
            let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
            waitingTurn = turn
            coord.activePlayerTurn = turn
            turn.selectCards(top: top, bottom: bottom)
            turn.executeCurrentAction()
            coord.handlePieceTap(piece)
        }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingModifierDraw == nil && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertNotNil(coord.pendingModifierDraw, "the attack waits for the player's draw")
        let health = bandit.health

        coord.exitBoard()
        await settle()
        XCTAssertNil(coord.pendingModifierDraw)
        XCTAssertNil(waitingTurn, "the waiting turn ended and was freed")
        XCTAssertEqual(bandit.health, health, "the attack never landed")
    }

    /// An enemy's attack waiting on a defence item offer when the player leaves: the offer goes,
    /// the item stays unused and the attack never lands.
    func testLeavingMidItemOfferDropsTheOffer() async throws {
        addBrute(at: HexCoord(3, 3))
        brute.items = ["gh-4"]   // Leather Armor: offered before the draw
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        brute.handCards = []
        brute.discardedCards = []
        coord.autoResolvePrompts = false
        let health = brute.health
        let attack = Task { @MainActor in
            await self.coord.performAttack(attacker: piece, target: .character(self.brute.id),
                                           attack: AttackParameters(value: 3), drawCard: { AttackModifier(type: .plus0) })
        }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingItemUse == nil && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertNotNil(coord.pendingItemUse)

        coord.exitBoard()
        _ = await attack.value   // ends rather than hanging
        XCTAssertNil(coord.pendingItemUse, "no offer from the old board")
        XCTAssertEqual(brute.health, health, "the attack never landed")
        XCTAssertTrue(brute.spentItems.isEmpty)
    }

    /// A move waiting for its animation when the board goes (a scene that's gone never finishes
    /// its animations) ends instead of hanging the turn.
    func testLeavingMidMoveEndsTheMove() async throws {
        addBrute(at: HexCoord(3, 3))
        // A scene whose animations never finish, as for a scene torn down mid-move.
        coord.boardScene = StalledScene(size: CGSize(width: 400, height: 300))
        var finished = false
        let move = Task { @MainActor in
            await self.coord.moveAlong(.character(self.brute.id), path: [HexCoord(3, 3), HexCoord(4, 3), HexCoord(5, 3)],
                                       style: .normal)
            finished = true
        }
        await settle()
        XCTAssertFalse(finished, "the move waits for its animation")
        XCTAssertFalse(coord.pendingMoveAnimations.isEmpty)

        coord.exitBoard()
        _ = await move.value
        XCTAssertTrue(finished)
        XCTAssertTrue(coord.pendingMoveAnimations.isEmpty)
    }

    /// A monster type's turn pausing between its standees when the board is restarted: the rest
    /// of the type never acts on the new board, even where the same pieces stand again.
    func testAMonsterTurnLeftBehindNeverActsOnTheNextBoard() async throws {
        addBrute(at: HexCoord(3, 3))
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(2, 3), origin: .placed)
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "bandit-guard" })
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 527 })]   // Move +0, Attack +0
        monster.ability = 0
        monster.abilityDrawn = true
        var attacks = 0
        coord.attackObserver = { _, _ in attacks += 1 }
        coord.turnDelayNanoseconds = 200_000_000   // the pause between standees

        let turn = Task { @MainActor in
            await MonsterTurnController(coordinator: self.coord, gameManager: self.gm).executeMonsterGroup(monster)
        }
        let deadline = Date().addingTimeInterval(3)
        while attacks == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(attacks, 1, "the first guard attacked")

        // The board is left and a new one set up with the same pieces where they were.
        let positions = coord.boardState.piecePositions
        coord.exitBoard()
        coord.boardState = makeBoard(cols: 12, rows: 12)
        for (piece, hex) in positions { coord.boardState.placePiece(piece, at: hex) }

        _ = await turn.value
        XCTAssertEqual(attacks, 1, "the second guard never acts on the new board")
    }
}

extension BoardTeardownTests {
    /// The modifier tray shows the last scenario's last draw no more once the next one begins
    /// (iPad playthrough 2026-10-09: "Cragheart → Bandit Archer 2" greeted #2 Barrow Lair).
    func testTheNextScenarioStartsWithNoDrawShown() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenarios = gm.editionStore.scenarios(for: "gh").filter { $0.solo == nil }
        gm.startScenarioOnBoard(try XCTUnwrap(scenarios.first { $0.index == "1" }))
        let coord = gm.boardCoordinator
        let brute = PieceID.character(gm.game.characters[0].id)
        let card = AttackModifier(type: .plus0)
        coord.lastModifierReveal = .init(attacker: brute, defender: brute, drawn: [card], selected: [card],
                                         advantage: false, disadvantage: false, drawnByPlayer: true)
        coord.exitBoard()
        gm.startScenarioOnBoard(try XCTUnwrap(scenarios.first { $0.index == "2" }))
        XCTAssertNil(coord.lastModifierReveal)
    }

    /// The elements start inert in every scenario, whatever the last one left lit.
    func testTheNextScenarioStartsWithNoElements() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenarios = gm.editionStore.scenarios(for: "gh").filter { $0.solo == nil }
        gm.startScenarioOnBoard(try XCTUnwrap(scenarios.first { $0.index == "1" }))
        let earth = try XCTUnwrap(gm.game.elementBoard.firstIndex { $0.type == .earth })
        gm.game.elementBoard[earth].state = .waning
        gm.boardCoordinator.exitBoard()
        gm.startScenarioOnBoard(try XCTUnwrap(scenarios.first { $0.index == "2" }))
        XCTAssertEqual(gm.game.elementBoard[earth].state, .inert)
    }
}

/// A board scene whose move animations never finish.
private final class StalledScene: BoardScene {
    override func movePiece(id: PieceID, along path: [HexCoord], animation: MoveAnimation = .walk,
                            offsetCol: Int = 0, offsetRow: Int = 0, completion: @escaping () -> Void) {}
}
