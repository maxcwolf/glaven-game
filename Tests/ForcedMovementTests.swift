import XCTest
import SwiftData
@testable import GlavenGameLib

/// Push and pull (GH p.20, FAQ "Push/Pull") and Retaliate (GH p.24, FAQ "Shield and Retaliate"),
/// through the coordinator's own attack and forced-movement code.
@MainActor
final class ForcedMovementTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private let attackerHex = HexCoord(3, 3)
    private let targetHex = HexCoord(4, 3)

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

    @discardableResult
    private func addCharacter(_ name: String = "brute", at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    private func addMonster(_ name: String = "bandit-guard", at hex: HexCoord, health: Int = 30) -> (piece: PieceID, entity: GameMonsterEntity) {
        let piece = coord.spawnMonster(name: name, type: .normal, at: hex, origin: .placed)!
        guard case .monster(_, let standee) = piece else { fatalError() }
        let entity = coord.monsterEntity(name: name, standee: standee)!
        entity.maxHealth = health
        entity.health = health
        entity.shield = nil
        entity.retaliate = []
        return (piece, entity)
    }

    private func position(_ piece: PieceID) -> HexCoord? { coord.boardState.piecePositions[piece] }

    private func setObstacle(_ hex: HexCoord) {
        coord.boardState.cells[hex]?.overlay = .obstacle
        coord.boardState.cells[hex]?.passable = false
    }

    /// The hexes a target on `targetHex` can be pushed into, away from `attackerHex`.
    private var behind: [HexCoord] { targetHex.pushCandidates(awayFrom: attackerHex).sorted() }
    /// The one straight behind it.
    private var straightBehind: HexCoord { HexCoord(5, 3) }

    private func zeroDraw() -> AttackModifier? { .standard(.plus0) }

    // MARK: - Push and pull

    /// Each hex of a push is further from the attacker than the last, and a pull's nearer.
    func testEachStepOfAPushIsFurtherAndOfAPullNearer() async {
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 2, isPush: true)
        XCTAssertEqual(position(target.piece)?.distance(to: attackerHex), 3, "pushed the full two hexes away")

        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 1, isPush: false)
        XCTAssertEqual(position(target.piece)?.distance(to: attackerHex), 2, "pulled one hex nearer")
        _ = brute
    }

    /// A push stops when no further hex is free: walls (the board's edge), obstacles.
    func testAPushStopsAtObstacles() async {
        addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        behind.forEach(setObstacle)
        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 2, isPush: true)
        XCTAssertEqual(position(target.piece), targetHex)
    }

    /// FAQ: a figure can be pushed through other figures of its own side, but can't end on one.
    func testAPushGoesThroughTheTargetsAlliesToAFreeHexBeyond() async {
        addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        let blockers = behind.map { addMonster("bandit-archer", at: $0) }
        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 2, isPush: true)
        XCTAssertEqual(position(target.piece)?.distance(to: attackerHex), 3, "through its allies, to the row behind them")
        for (index, blocker) in blockers.enumerated() {
            XCTAssertEqual(position(blocker.piece), behind[index], "they don't move")
        }

        // With only one step it would have to stop on an ally: it can't be pushed at all.
        let second = addMonster(at: HexCoord(3, 6))
        let origin = HexCoord(2, 6)
        let ring = HexCoord(3, 6).pushCandidates(awayFrom: origin)
        ring.forEach { _ = addMonster("living-bones", at: $0) }
        await coord.performPushPull(target: second.piece, attackerPos: origin, steps: 1, isPush: true)
        XCTAssertEqual(position(second.piece), HexCoord(3, 6))
    }

    /// It can't pass its enemies: a character standing behind a pushed monster blocks that hex.
    func testAPushDoesNotGoThroughTheTargetsEnemies() async {
        addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        for (index, hex) in behind.enumerated() { addCharacter(["tinkerer", "spellweaver", "scoundrel"][index], at: hex) }
        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 2, isPush: true)
        XCTAssertEqual(position(target.piece), targetHex)
    }

    /// A pushed figure springs the traps it is forced onto (GH p.14)…
    func testAPushedWalkerSpringsATrap() async {
        addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        behind.forEach { coord.boardState.cells[$0]?.overlay = .trap }
        await coord.performPushPull(target: target.piece, attackerPos: attackerHex, steps: 1, isPush: true)
        XCTAssertEqual(target.entity.health, 30 - 3, "trap damage: 2 + L at level 1, once")
        XCTAssertEqual(behind.filter { coord.boardState.cells[$0]?.isTrap == true }.count, behind.count - 1, "and the trap is gone")
    }

    /// …and takes hazardous terrain's damage, but a flying figure does neither (FAQ).
    func testAPushedFlyerTouchesNeitherTrapsNorHazardsAndCrossesObstacles() async {
        addCharacter(at: attackerHex)
        let walker = addMonster(at: targetHex)
        behind.forEach { coord.boardState.cells[$0]?.overlay = .hazard }
        await coord.performPushPull(target: walker.piece, attackerPos: attackerHex, steps: 1, isPush: true)
        XCTAssertEqual(walker.entity.health, 30 - 1, "a walker pushed into hazardous terrain is hurt: half a trap, rounded down")
        coord.sufferDamage(99, to: walker.piece)

        let demon = addMonster("flame-demon", at: targetHex)
        XCTAssertTrue(coord.flies(demon.piece))
        behind.forEach { coord.boardState.cells[$0]?.overlay = .trap }
        await coord.performPushPull(target: demon.piece, attackerPos: attackerHex, steps: 1, isPush: true)
        XCTAssertNotEqual(position(demon.piece), targetHex, "it is pushed onto a trap hex")
        XCTAssertEqual(demon.entity.health, 30, "which doesn't spring")
        XCTAssertEqual(behind.filter { coord.boardState.cells[$0]?.isTrap == true }.count, behind.count)

        // Over obstacles too, where a walker stops.
        coord.boardState.movePiece(demon.piece, to: targetHex)
        behind.forEach(setObstacle)
        await coord.performPushPull(target: demon.piece, attackerPos: attackerHex, steps: 2, isPush: true)
        XCTAssertEqual(position(demon.piece)?.distance(to: attackerHex), 3)
    }

    /// A character's own push may be turned down before it starts (FAQ: optional, all or none).
    func testThePlayersOwnPushCanBeDeclined() async throws {
        coord.autoResolvePrompts = false
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        let pushing = Task { @MainActor in
            await self.coord.performPushPull(target: target.piece, attackerPos: self.attackerHex, steps: 2, isPush: true)
        }
        for _ in 0..<200 {
            if case .selectingPushPullHex = coord.interactionMode { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard case .selectingPushPullHex = coord.interactionMode else { return XCTFail("the push waits for its first hex") }
        XCTAssertTrue(coord.pushPullDeclinable)
        XCTAssertEqual(coord.instruction(for: coord.interactionMode)?.canSkip, true)
        turn.skipCurrentAction()
        await pushing.value
        XCTAssertEqual(position(target.piece), targetHex, "not pushed")
        XCTAssertFalse(coord.pushPullDeclinable)
    }

    /// Once begun it must go the whole way: after the first hex there is nothing to decline.
    func testAPushOnceBegunCannotBeDeclined() async throws {
        coord.autoResolvePrompts = false
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        coord.activePlayerTurn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        let pushing = Task { @MainActor in
            await self.coord.performPushPull(target: target.piece, attackerPos: self.attackerHex, steps: 2, isPush: true)
        }
        for _ in 0..<200 {
            if case .selectingPushPullHex = coord.interactionMode { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        coord.handleHexTap(straightBehind)
        for _ in 0..<500 {
            if position(target.piece) != targetHex, case .selectingPushPullHex = coord.interactionMode { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        guard case .selectingPushPullHex(_, _, let hexes, let remaining, _) = coord.interactionMode else {
            return XCTFail("the second hex of the push")
        }
        XCTAssertEqual(remaining, 1)
        XCTAssertFalse(coord.pushPullDeclinable)
        coord.handleHexTap(hexes.sorted()[0])
        await pushing.value
        XCTAssertEqual(position(target.piece)?.distance(to: attackerHex), 3)
    }

    // MARK: - Retaliate

    private func retaliate(_ value: Int, range: Int? = nil) -> ActionModel {
        ActionModel(type: .retaliate, value: .int(value),
                    subActions: range.map { [ActionModel(type: .range, value: .int($0))] })
    }

    /// Retaliate hits an adjacent attacker after its attack, for the full amount: it isn't an
    /// attack, so the attacker's Shield doesn't reduce it.
    func testRetaliateDamagesAnAdjacentAttackerWhateverItsShield() async {
        let brute = addCharacter(at: attackerHex)
        brute.shield = ActionModel(type: .shield, value: .int(5))
        let target = addMonster(at: targetHex)
        target.entity.retaliate = [retaliate(2)]
        let before = brute.health
        await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                  attack: AttackParameters(value: 2), drawCard: zeroDraw)
        XCTAssertEqual(target.entity.health, 28)
        XCTAssertEqual(brute.health, before - 2)
    }

    /// Several Retaliates add; one with a Range reaches that far, one without only adjacent.
    func testRetaliatesAddAndEachHasItsOwnReach() async {
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: HexCoord(5, 3))
        target.entity.retaliate = [retaliate(1), retaliate(2, range: 2)]
        let before = brute.health
        await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                  attack: AttackParameters(value: 1, isRanged: true, range: 3), drawCard: zeroDraw)
        XCTAssertEqual(brute.health, before - 2, "two hexes away: only the Retaliate with Range 2")

        coord.boardState.movePiece(target.piece, to: targetHex)
        await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                  attack: AttackParameters(value: 1), drawCard: zeroDraw)
        XCTAssertEqual(brute.health, before - 5, "adjacent: both")
    }

    /// A figure killed by the attack doesn't retaliate (GH p.24).
    func testAKilledFigureDoesNotRetaliate() async {
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex, health: 2)
        target.entity.retaliate = [retaliate(3)]
        let before = brute.health
        let died = await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                             attack: AttackParameters(value: 2), drawCard: zeroDraw)
        XCTAssertTrue(died)
        XCTAssertEqual(brute.health, before)
    }

    /// FAQ: Retaliate "doesn't trigger if the retaliating figure … is pushed out of range".
    func testRetaliateDoesNotReachAnAttackerWhoPushedTheFigureAway() async {
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: targetHex)
        target.entity.retaliate = [retaliate(2)]
        let before = brute.health
        await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                  attack: AttackParameters(value: 2, push: 1), drawCard: zeroDraw)
        XCTAssertNotEqual(position(target.piece), targetHex, "pushed")
        XCTAssertEqual(brute.health, before, "no longer adjacent: no retaliate")
    }

    /// …and "it does trigger if the figure is pulled into range".
    func testRetaliateReachesAnAttackerWhoPulledTheFigureAdjacent() async {
        let brute = addCharacter(at: attackerHex)
        let target = addMonster(at: HexCoord(6, 3))
        target.entity.retaliate = [retaliate(2)]
        let before = brute.health
        await coord.performAttack(attacker: .character(brute.id), target: target.piece,
                                  attack: AttackParameters(value: 1, isRanged: true, pull: 2, range: 3), drawCard: zeroDraw)
        XCTAssertEqual(position(target.piece)?.distance(to: attackerHex), 1, "pulled adjacent")
        XCTAssertEqual(brute.health, before - 2)
    }
}
