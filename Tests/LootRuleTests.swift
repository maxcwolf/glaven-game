import XCTest
@testable import GlavenGameLib

/// Looting (rulebook p.28 and the FAQ; gh-rules.md TRN-5, ACT-7, LOS-2, SET-4), through real
/// turns: who picks up the money in their hex and when, what a Loot X ability reaches, and what a
/// token is worth at each scenario level.
@MainActor
final class LootRuleTests: XCTestCase {

    private var board: RuleBoard!
    private var coord: BoardCoordinator { board.coord }
    private let here = HexCoord(5, 5)

    override func setUp() async throws {
        board = try RuleBoard()
    }

    private func tokens(at hex: HexCoord) -> Int { coord.boardState.lootTokens[hex] ?? 0 }

    // MARK: - TRN-5: the end of a turn

    /// TRN-5 (p.28): "a character must also loot any money tokens … in the hex they occupy at
    /// the end of their turn" — at the end, not while they stand there during it; each token is
    /// worth the level's gold (2 at level 1).
    func testACharacterLootsTheirHexAsTheirTurnEnds() throws {
        let brute = board.character(at: here)
        coord.boardState.placeLoot(at: here, count: 2)
        let gold = brute.loot
        var tokensDuringTheTurn = 0
        try board.takeTurn(brute) { _ in tokensDuringTheTurn = self.tokens(at: self.here) }
        XCTAssertEqual(tokensDuringTheTurn, 2, "not before the turn ends")
        XCTAssertEqual(tokens(at: here), 0, "both tokens are picked up")
        XCTAssertEqual(brute.loot, gold + 4, "two tokens at 2 gold each")
    }

    /// TRN-5: "summons and monsters do not perform end-of-turn looting". A summon that ends its
    /// turn on a money token, and a monster that does, leave it where it lies.
    func testSummonsAndMonstersDoNotLootAtTheEndOfTheirTurns() async throws {
        let brute = board.character(at: here, health: 40)
        // The summon walks one hex onto the token to reach its enemy; the Guard stands on another.
        let pet = board.summon(of: brute, at: HexCoord(5, 8), attack: 1, move: 1)
        let prey = try board.monster("living-bones", at: HexCoord(7, 8), health: 40)
        let coinForSummon = HexCoord(6, 8)
        XCTAssertEqual(HexCoord(5, 8).distance(to: HexCoord(7, 8)), 2)
        coord.boardState.placeLoot(at: coinForSummon)
        let guardian = try board.monster(at: HexCoord(6, 5))
        XCTAssertEqual(here.distance(to: HexCoord(6, 5)), 1)
        coord.boardState.placeLoot(at: HexCoord(6, 5))
        let gold = brute.loot
        brute.attackModifierDeck = RuleBoard.deck(of: .plus0)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus0)

        await SummonTurnController(coordinator: coord, gameManager: board.gm).executeSummonTurns(for: brute)
        XCTAssertEqual(board.hex(pet.piece), coinForSummon, "the summon ended its turn on the token")
        XCTAssertEqual(prey.entity.health, 39, "having attacked from there")
        XCTAssertEqual(tokens(at: coinForSummon), 1, "and left it")

        try board.draw(527, for: "bandit-guard")   // Move +0, Attack +0
        try await board.act("bandit-guard")
        XCTAssertLessThan(brute.health, 40, "the Guard took its turn")
        XCTAssertEqual(board.hex(guardian.piece), HexCoord(6, 5))
        XCTAssertEqual(tokens(at: HexCoord(6, 5)), 1)
        XCTAssertEqual(brute.loot, gold, "no one gained a coin")
    }

    /// FAQ ("Looting"): a figure forced onto a money token doesn't pick it up — only the end of
    /// a character's own turn does, and then it is theirs.
    func testAFigurePushedOntoATokenDoesNotPickItUp() async throws {
        let brute = board.character(at: here)
        let pusher = HexCoord(4, 5)
        let landing = here.pushCandidates(awayFrom: pusher)
        XCTAssertFalse(landing.isEmpty)
        landing.forEach { coord.boardState.placeLoot(at: $0) }
        let gold = brute.loot
        await coord.performPushPull(target: .character(brute.id), attackerPos: pusher, steps: 1, isPush: true)
        let now = try XCTUnwrap(board.hex(.character(brute.id)))
        XCTAssertTrue(landing.contains(now), "pushed onto a token")
        XCTAssertEqual(tokens(at: now), 1, "which stays on the floor")
        XCTAssertEqual(brute.loot, gold)

        try board.takeTurn(brute)
        XCTAssertEqual(tokens(at: now), 0, "the end of their own turn picks it up")
        XCTAssertEqual(brute.loot, gold + 2)
    }

    // MARK: - ACT-7, LOS-2: Loot X

    /// ACT-7 (p.28): Loot X takes "all money tokens … within range X" — under a monster's feet
    /// or beyond an obstacle too — but nothing further away, and (LOS-2, FAQ) nothing out of
    /// sight. Hook Gun's bottom, Loot 2.
    func testALootAbilityTakesEveryTokenInRangeAndSightWhateverIsInTheWay() throws {
        let tinkerer = board.character("tinkerer", at: here)
        let underAMonster = HexCoord(3, 5), beyondAnObstacle = HexCoord(5, 3), tooFar = HexCoord(5, 8), walledIn = HexCoord(7, 5)
        XCTAssertEqual(here.distance(to: underAMonster), 2)
        XCTAssertEqual(here.distance(to: beyondAnObstacle), 2)
        XCTAssertEqual(here.distance(to: tooFar), 3)
        XCTAssertEqual(here.distance(to: walledIn), 2)
        for hex in [here, underAMonster, beyondAnObstacle, tooFar, walledIn] { coord.boardState.placeLoot(at: hex) }
        try board.monster(at: underAMonster)
        try board.monster("bandit-archer", at: HexCoord(4, 5))
        for hex in beyondAnObstacle.neighbors where hex.distance(to: here) == 1 { coord.boardState.placeObstacle(at: hex) }
        // A token in a cell with a wall on every side: within two hexes, and out of sight.
        for hex in walledIn.neighbors {
            coord.boardState.cells[hex]?.passable = false
            coord.boardState.cells[hex]?.overlay = .wall
        }
        XCTAssertFalse(LineOfSight.hasLOS(from: here, to: walledIn, board: coord.boardState))
        let gold = tinkerer.loot

        let hook = try board.card("Hook Gun", of: "tinkerer"), other = try board.card("Stun Shot", of: "tinkerer")
        board.play(other, hook, for: tinkerer)
        board.startTurns([TurnOrderEntry(figure: .character(tinkerer), initiative: 20)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()

        XCTAssertEqual([here, underAMonster, beyondAnObstacle].map(tokens(at:)), [0, 0, 0], "everything in range and sight")
        XCTAssertEqual(tokens(at: tooFar), 1, "three hexes away: out of range")
        XCTAssertEqual(tokens(at: walledIn), 1, "behind walls: out of sight")
        XCTAssertEqual(tinkerer.loot, gold + 6, "three tokens")
        XCTAssertEqual(tinkerer.experience, 1, "the Loot was performed: its experience")
    }

    // MARK: - SET-4: what a token is worth

    /// SET-4 (p.15): gold for each money token by scenario level: 2, 2, 3, 3, 4, 4, 5, 6.
    func testAMoneyTokenIsWorthTheLevelsGold() throws {
        for (level, rate) in [2, 2, 3, 3, 4, 4, 5, 6].enumerated() {
            board = try RuleBoard(level: level)
            let brute = board.character(at: here)
            coord.boardState.placeLoot(at: here, count: 3)
            let gold = brute.loot
            try board.takeTurn(brute)
            XCTAssertEqual(brute.loot, gold + 3 * rate, "level \(level): three tokens at \(rate)")
        }
    }
}
