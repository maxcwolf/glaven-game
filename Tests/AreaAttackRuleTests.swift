import XCTest
import SwiftData
@testable import GlavenGameLib

/// Area attacks (GH p.19–20 and the FAQ): the pattern may be turned and mirrored; one red hex of
/// a ranged pattern must be within range (empty is fine, a wall is not); and a target added to
/// an area attack is one more enemy within the attack's range, attacked besides the area.
@MainActor
final class AreaAttackRuleTests: XCTestCase {

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

    private func monster(_ standee: Int) -> PieceID { .monster(name: "bandit-guard", standee: standee) }

    // MARK: - Mirror image

    /// A bent line: the attacker's hex, two hexes east, then one to the north-west of the last —
    /// a left turn. Its mirror image turns right, which no rotation of the original does.
    private let bentLine = "(1,1,active)|(2,1,target)|(3,1,target)|(3,0,target)"

    func testAnAreaMayBeTurned() {
        let board = makeBoard(cols: 12, rows: 12)
        let attacker = HexCoord(5, 5)
        // As printed: east, east, north-west.
        for (standee, hex) in [(1, HexCoord(6, 5)), (2, HexCoord(7, 5)), (3, HexCoord(7, 4))] {
            board.piecePositions[monster(standee)] = hex
        }
        let hit = AoEResolver.resolveTargets(pattern: bentLine, attackerPos: attacker, focusTarget: monster(3),
                                             enemies: [monster(1), monster(2), monster(3)], board: board)
        XCTAssertEqual(Set(hit), [monster(1), monster(2), monster(3)])
    }

    /// FAQ: "you can also use the mirror image of the area."
    func testAnAreaMayBeMirrored() {
        let board = makeBoard(cols: 12, rows: 12)
        let attacker = HexCoord(5, 5)
        // East, east, then south-west: only the mirror image covers the third hex at all.
        for (standee, hex) in [(1, HexCoord(6, 5)), (2, HexCoord(7, 5)), (3, HexCoord(7, 6))] {
            board.piecePositions[monster(standee)] = hex
        }
        let hit = AoEResolver.resolveTargets(pattern: bentLine, attackerPos: attacker, focusTarget: monster(3),
                                             enemies: [monster(1), monster(2), monster(3)], board: board)
        XCTAssertEqual(hit.first, monster(3), "the focus is covered")
        XCTAssertEqual(Set(hit), [monster(1), monster(2), monster(3)], "with both others, by the mirrored pattern")
    }

    func testARangedAreaMayBeMirroredToo() {
        let board = makeBoard(cols: 12, rows: 12)
        let pattern = "(1,1,target)|(2,1,target)|(3,1,target)|(3,0,target)"
        let straight = AoEResolver.rangedPlacements(pattern: pattern, covering: HexCoord(6, 5), attackerPos: HexCoord(2, 5), range: 4, board: board)
        XCTAssertTrue(straight.contains { Set($0) == [HexCoord(5, 5), HexCoord(6, 5), HexCoord(7, 5), HexCoord(7, 4)] }, "as printed")
        XCTAssertTrue(straight.contains { Set($0) == [HexCoord(5, 5), HexCoord(6, 5), HexCoord(7, 5), HexCoord(7, 6)] }, "and mirrored")
    }

    // MARK: - The hex within range

    /// One red hex of a ranged area must be within range; it may be empty, but not a wall (FAQ).
    func testTheHexOfARangedAreaWithinRangeMayBeEmptyButNotAWall() {
        let board = makeBoard(cols: 12, rows: 12)
        let pair = "(0,0,target)|(1,0,target)"
        let attacker = HexCoord(2, 2), far = HexCoord(4, 0)
        XCTAssertEqual(attacker.distance(to: far), 3, "the enemy's hex is out of range 2")
        let near = [HexCoord(3, 1), HexCoord(3, 0)]
        for hex in near { XCTAssertEqual(attacker.distance(to: hex), 2); XCTAssertTrue(hex.isAdjacent(to: far)) }

        var placements = AoEResolver.rangedPlacements(pattern: pair, covering: far, attackerPos: attacker, range: 2, board: board)
        for hex in near { XCTAssertTrue(placements.contains { Set($0) == [hex, far] }, "the empty hex \(hex) brings the area within range") }
        board.cells[near[1]]?.overlay = .wall
        board.cells[near[1]]?.passable = false
        placements = AoEResolver.rangedPlacements(pattern: pair, covering: far, attackerPos: attacker, range: 2, board: board)
        XCTAssertFalse(placements.contains { Set($0) == [near[1], far] }, "a wall hex is not a hex within range")
        XCTAssertTrue(placements.contains { Set($0) == [near[0], far] })
    }

    // MARK: - An added target

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    /// FAQ, "Add Target": an added target is a single extra enemy within the range of the attack —
    /// range 1 for a melee area — attacked besides the area, which is placed as ever.
    func testATargetAddedToAnAreaAttackIsOneMoreEnemyInRange() async throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = try XCTUnwrap(gm.game.characters.last)
        let me = PieceID.character(brute.id)
        coord.boardState.placePiece(me, at: HexCoord(5, 5))
        // The area: the hexes east and north-east of the attacker.
        var foes: [HexCoord: PieceID] = [:]
        for hex in [HexCoord(6, 5), HexCoord(6, 4), HexCoord(4, 5), HexCoord(8, 5)] {
            let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
            guard case .monster(let name, let standee) = piece else { return XCTFail() }
            let entity = try XCTUnwrap(coord.monsterEntity(name: name, standee: standee))
            entity.maxHealth = 40; entity.health = 40; entity.shield = nil
            foes[hex] = piece
        }
        let cleave = AbilityModel(cardId: 9001, name: "Cleave and one more", initiative: 20, actions: [
            ActionModel(type: .attack, value: .int(2), subActions: [
                ActionModel(type: .area, value: .string("(1,1,active)|(2,1,target)|(2,0,target)")),
                ActionModel(type: .target, value: .int(2)),
            ])
        ], bottomActions: [ActionModel(type: .move, value: .int(2))])
        let other = AbilityModel(cardId: 9002, name: "Step", initiative: 30,
                                 actions: [ActionModel(type: .attack, value: .int(1))], bottomActions: [ActionModel(type: .move, value: .int(2))])
        brute.handCards = [9001, 9002]
        coord.boardPhase = .execution
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: cleave, bottom: other)
        turn.executeCurrentAction()

        guard case .selectingAttackTarget(_, _, let primaries) = coord.interactionMode else {
            return XCTFail("the area is aimed at one enemy, got \(coord.interactionMode)")
        }
        XCTAssertTrue(primaries.contains(foes[HexCoord(6, 5)]!))
        coord.handlePieceTap(foes[HexCoord(6, 5)]!)
        // The two in the area are attacked, then the added target is asked for.
        let asked = await waitUntil {
            if case .selectingAttackTarget(_, _, let more) = self.coord.interactionMode { return more == [foes[HexCoord(4, 5)]!] }
            return false
        }
        XCTAssertTrue(asked, "the adjacent enemy outside the area is offered as the added target, got \(coord.interactionMode)")
        func attacks() -> [String] { coord.turnLog.map(\.message).filter { $0.hasPrefix("Brute attacks ") } }
        XCTAssertEqual(attacks().count, 2, "the area's two enemies were attacked first")
        XCTAssertTrue(turn.isWaiting)

        coord.handlePieceTap(foes[HexCoord(4, 5)]!)
        let done = await waitUntil { !turn.isWaiting }
        XCTAssertTrue(done)
        XCTAssertEqual(attacks().count, 3, "one more attack, on the added target")
        let names = Set(attacks().compactMap { $0.dropFirst("Brute attacks ".count).split(separator: ":").first.map(String.init) })
        XCTAssertEqual(names, Set([HexCoord(6, 5), HexCoord(6, 4), HexCoord(4, 5)].map { coord.name(foes[$0]!) }))
        XCTAssertFalse(names.contains(coord.name(foes[HexCoord(8, 5)]!)), "never the enemy three hexes away")
    }
}
