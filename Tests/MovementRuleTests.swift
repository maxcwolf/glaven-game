import XCTest
@testable import GlavenGameLib

/// Traps and hazardous terrain as figures really move (rulebook pp. 14–15, 19; gh-rules.md MOV-3,
/// MOV-5, MOV-6, SET-4): a jump's last hex, a push, and the damage each scenario level gives.
@MainActor
final class MovementRuleTests: XCTestCase {

    private var board: RuleBoard!
    private var coord: BoardCoordinator { board.coord }
    private let start = HexCoord(5, 5), landing = HexCoord(7, 5)

    override func setUp() async throws {
        board = try RuleBoard(level: 3)   // traps 5, hazardous terrain 2
        XCTAssertEqual(start.distance(to: landing), 2)
    }

    private func traps(in hexes: [HexCoord]) -> Int { hexes.filter { coord.boardState.cells[$0]?.isTrap == true }.count }

    /// The Brute jumps (Leaping Cleave's bottom, Move 3 with Jump) from `start` to `landing`.
    private func jump(_ brute: GameCharacter) async throws {
        let leap = try board.card("Leaping Cleave", of: "brute"), other = try board.card("Trample", of: "brute")
        board.play(other, leap, for: brute)
        board.startTurns([TurnOrderEntry(figure: .character(brute), initiative: 54)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .selectingMove(_, _, let hexes, _, let mode) = coord.interactionMode else { return XCTFail("the move waits for a hex") }
        XCTAssertEqual(mode, .jump)
        XCTAssertTrue(hexes.contains(landing))
        coord.handleHexTap(landing)
        let done = await board.settle { !turn.isWaiting }
        XCTAssertTrue(done)
        XCTAssertEqual(board.hex(.character(brute.id)), landing)
    }

    // MARK: - MOV-3: a jump's last hex

    /// MOV-3 (p.19): a Jump ignores what it passes over, but "the last hex of a jump is still
    /// considered a normal movement": the trap landed on is sprung, and none of those jumped.
    func testAJumpSpringsTheTrapItLandsOnAndNoneItPassesOver() async throws {
        let brute = board.character(at: start, health: 30)
        let ring = start.neighbors
        (ring + [landing]).forEach { coord.boardState.cells[$0]?.overlay = .trap }
        try await jump(brute)
        XCTAssertEqual(brute.health, 30 - 5, "one trap: 2 + 3")
        XCTAssertEqual(traps(in: ring), 6, "every trap beside the start is still set")
        XCTAssertEqual(traps(in: [landing]), 0, "the one landed on is sprung and gone")
    }

    /// MOV-3, MOV-6: landing on hazardous terrain hurts (half a trap, rounded down); jumping
    /// over it doesn't.
    func testAJumpTakesHazardDamageOnlyWhereItLands() async throws {
        let brute = board.character(at: start, health: 30)
        (start.neighbors + [landing]).forEach { coord.boardState.cells[$0]?.overlay = .hazard }
        try await jump(brute)
        XCTAssertEqual(brute.health, 30 - 2, "once, for the hex landed on")

        // Over hazardous terrain onto clear floor: nothing.
        board = try RuleBoard(level: 3)
        let other = board.character(at: start, health: 30)
        start.neighbors.forEach { coord.boardState.cells[$0]?.overlay = .hazard }
        try await jump(other)
        XCTAssertEqual(other.health, 30)
    }

    // MARK: - MOV-5, MOV-6: forced movement

    /// MOV-6 (p.14, FAQ): hazardous terrain hurts a figure pushed into it, each hex it is forced
    /// to enter — and not for standing in it afterwards as its turn starts and ends.
    func testAPushedFigureIsHurtByEachHazardHexItEnters() async throws {
        let pusher = HexCoord(4, 5)
        board.character(at: pusher)
        let pushed = try board.monster(at: start)
        // Everything further from the pusher, two rings deep, is hazardous.
        for hex in coord.boardState.cells.keys where hex.distance(to: pusher) >= 2 && hex.distance(to: pusher) <= 3 {
            coord.boardState.cells[hex]?.overlay = .hazard
        }
        await coord.performPushPull(target: pushed.piece, attackerPos: pusher, steps: 2, isPush: true)
        XCTAssertEqual(board.hex(pushed.piece)?.distance(to: pusher), 3, "pushed two hexes")
        XCTAssertEqual(pushed.entity.health, 30 - 2 - 2, "2 for each hazardous hex entered")

        // Its own turn, standing there: no more damage (an immobilized Guard that doesn't move).
        pushed.entity.entityConditions = [EntityCondition(name: .immobilize, state: .normal)]
        try board.draw(527, for: "bandit-guard")
        try await board.act("bandit-guard")
        XCTAssertEqual(board.hex(pushed.piece)?.distance(to: pusher), 3)
        XCTAssertEqual(pushed.entity.health, 30 - 4, "nothing for starting and ending a turn in it")
    }

    /// MOV-5: a figure pushed onto a trap springs it and suffers its damage in full.
    func testAPushedFigureSpringsATrapForItsFullDamage() async throws {
        let pusher = HexCoord(4, 5)
        board.character(at: pusher)
        let pushed = try board.monster(at: start)
        let behind = start.pushCandidates(awayFrom: pusher)
        behind.forEach { coord.boardState.cells[$0]?.overlay = .trap }
        await coord.performPushPull(target: pushed.piece, attackerPos: pusher, steps: 1, isPush: true)
        XCTAssertEqual(pushed.entity.health, 30 - 5)
        XCTAssertEqual(traps(in: behind), behind.count - 1)
    }

    // MARK: - SET-4: the level's damage

    /// SET-4 (p.15): at scenario level L a damage trap does 2 + L and hazardous terrain half of
    /// that, rounded down — every level from 0 to 7, walked into by a monster.
    func testTrapAndHazardDamageAtEveryScenarioLevel() async throws {
        for level in 0...7 {
            board = try RuleBoard(level: level)
            let walker = try board.monster(at: start, health: 50)
            let first = HexCoord(6, 5)
            coord.boardState.cells[first]?.overlay = .trap
            coord.boardState.cells[landing]?.overlay = .hazard
            await coord.moveAlong(walker.piece, path: [start, first], style: .normal)
            XCTAssertEqual(50 - walker.entity.health, 2 + level, "trap at level \(level)")
            walker.entity.health = 50
            await coord.moveAlong(walker.piece, path: [first, landing], style: .normal)
            XCTAssertEqual(50 - walker.entity.health, (2 + level) / 2, "hazardous terrain at level \(level)")
        }
    }
}
