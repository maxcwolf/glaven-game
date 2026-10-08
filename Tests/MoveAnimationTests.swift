import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Each kind of move looks different on the board — a walk steps hex by hex, a jump arcs over
/// what's in between, a flyer stays lifted, a teleport vanishes and reappears, a push shoves —
/// and every one of them ends on the right hex.
@MainActor
final class MoveAnimationTests: XCTestCase {

    private let path = (0...4).map { CGPoint(x: CGFloat($0) * 76, y: 0) }
    private var destination: CGPoint { path.last! }

    // MARK: - Plans

    func testAWalkStepsThroughEveryHexAndEasesInAndOut() {
        let plan = MovePlan.plan(.walk, through: path)
        XCTAssertEqual(plan.legs.map(\.to), Array(path.dropFirst()))
        XCTAssertEqual(plan.legs.first?.timing, .easeIn)
        XCTAssertEqual(plan.legs.last?.timing, .easeOut)
        XCTAssertEqual(plan.lift, 1)
        XCTAssertFalse(plan.fades)
    }

    func testAJumpArcsOverTheHexesBetween() {
        let plan = MovePlan.plan(.jump, through: path)
        XCTAssertEqual(plan.legs.map(\.to), [destination], "straight to the landing hex, not through the others")
        XCTAssertGreaterThan(plan.lift, 1, "it rises")
        XCTAssertFalse(plan.holdsLift, "and comes down again over the move")
        XCTAssertLessThan(plan.duration, MovePlan.plan(.walk, through: path).duration, "quicker than walking it")
    }

    func testAFlyerStaysLiftedAlongItsPath() {
        let plan = MovePlan.plan(.fly, through: path)
        XCTAssertEqual(plan.legs.map(\.to), Array(path.dropFirst()))
        XCTAssertGreaterThan(plan.lift, 1)
        XCTAssertTrue(plan.holdsLift)
    }

    func testATeleportVanishesAndReappears() {
        let plan = MovePlan.plan(.teleport, through: [path[0], destination])
        XCTAssertEqual(plan.legs.map(\.to), [destination])
        XCTAssertEqual(plan.legs.first?.duration, 0, "it doesn't travel")
        XCTAssertTrue(plan.fades)
    }

    func testAPushIsAQuickEvenShove() {
        let plan = MovePlan.plan(.forced, through: Array(path.prefix(3)))
        XCTAssertTrue(plan.legs.allSatisfy { $0.timing == .linear }, "no wind-up")
        XCTAssertLessThan(plan.duration, MovePlan.plan(.walk, through: Array(path.prefix(3))).duration)
        XCTAssertEqual(plan.lift, 1)
    }

    /// Reduced motion keeps moves readable but drops the lifting.
    func testReducedMotionDropsTheLift() {
        for kind in [MoveAnimation.jump, .fly] {
            XCTAssertEqual(MovePlan.plan(kind, through: path, reduceMotion: true).lift, 1, "\(kind)")
        }
        XCTAssertTrue(MovePlan.plan(.teleport, through: path, reduceMotion: true).fades, "a teleport still fades")
    }

    func testEveryMoveEndsOnItsDestination() {
        for kind in [MoveAnimation.walk, .jump, .fly, .teleport, .forced] {
            XCTAssertEqual(MovePlan.plan(kind, through: path).legs.last?.to, destination, "\(kind)")
        }
        XCTAssertEqual(MovePlan.plan(.walk, through: [path[0]]).legs, [], "no move, no legs")
    }

    // MARK: - The coordinator picks the right one

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    /// Scenario 1 with the party placed, its scene built but not shown, so moves land at once.
    private func startScenario() throws -> BoardScene {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
        coord.placeCharacter(characterID: gm.game.characters[0].id, at: free)
        return try XCTUnwrap(coord.boardScene)
    }

    private var brute: PieceID { .character(gm.game.characters[0].id) }

    /// A short route from the Brute to a free hex `steps` away.
    private func route(_ steps: Int) throws -> [HexCoord] {
        let start = try XCTUnwrap(coord.boardState.piecePositions[brute])
        var path = [start]
        var current = start
        for _ in 0..<steps {
            let next = try XCTUnwrap(current.neighbors.sorted().first { hex in
                coord.boardState.cells[hex] != nil && !coord.boardState.isOccupied(hex)
                    && !path.contains(hex) && coord.boardState.cells[hex]?.isTrap != true
                    && coord.boardState.cells[hex]?.isHazard != true
                    && !coord.boardState.doors.contains { $0.coord == hex }
            })
            path.append(next)
            current = next
        }
        return path
    }

    func testEachMovementStyleAnimatesAsItsKind() async throws {
        let scene = try startScenario()
        for (style, kind) in [(MovementStyle.normal, MoveAnimation.walk), (.jump, .jump), (.fly, .fly), (.forced, .forced)] {
            let path = try route(2)
            let moved = await coord.moveAlong(brute, path: path, style: style)
            XCTAssertTrue(moved)
            XCTAssertEqual(scene.lastMoveAnimation[brute], kind, "\(style)")
            XCTAssertEqual(scene.pieceNode(for: brute)?.position, scene.sceneCenter(of: path.last!),
                           "\(style): the token is on its hex")
        }
    }

    func testATeleportAnimatesAsATeleport() async throws {
        let scene = try startScenario()
        let target = try route(3).last!
        coord.executeTeleport(pieceID: brute, to: target)
        let deadline = Date().addingTimeInterval(2)
        while coord.boardState.piecePositions[brute] != target && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(coord.boardState.piecePositions[brute], target)
        XCTAssertEqual(scene.lastMoveAnimation[brute], .teleport)
        XCTAssertEqual(scene.pieceNode(for: brute)?.position, scene.sceneCenter(of: target))
    }
}
