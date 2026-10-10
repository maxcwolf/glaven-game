import XCTest
import SwiftData
@testable import GlavenGameLib

/// Scenario setup (GH p.12–15): which standees monsters take, and the scenario level.
@MainActor
final class SetupRulesTests: XCTestCase {

    private func eliteGuardNumbers(seed: UInt64) throws -> Set<Int> {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: seed))
        var numbers = Set<Int>()
        for piece in sim.coord.boardState.eliteStandees {
            if case .monster("bandit-guard", let standee) = piece { numbers.insert(standee) }
        }
        return numbers
    }

    /// "Standees should be placed randomly": within a type monsters act in standee order (elites
    /// first), so which monster holds which number decides who goes first. Black Barrow's two
    /// elite Bandit Guards for four characters don't always hold the same two numbers, and the
    /// six guards between them hold six different ones.
    func testStandeesAreDrawnAtRandomWhenAScenarioIsSetUp() throws {
        var seen = Set<Set<Int>>()
        for seed in 1...12 as ClosedRange<UInt64> {
            let numbers = try eliteGuardNumbers(seed: seed)
            XCTAssertEqual(numbers.count, 2, "two elite guards for four characters")
            seen.insert(numbers)
        }
        XCTAssertGreaterThan(seen.count, 3, "the elites' standees vary from game to game: \(seen)")
        XCTAssertEqual(try eliteGuardNumbers(seed: 5), try eliteGuardNumbers(seed: 5), "the same seed sets up the same game")

        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 3))
        let guards = sim.coord.boardState.piecePositions.keys.compactMap { piece -> Int? in
            if case .monster("bandit-guard", let standee) = piece { return standee }
            return nil
        }
        XCTAssertEqual(guards.count, 6)
        XCTAssertEqual(Set(guards), Set(1...6), "each of the six standees once")
    }

    /// A standee freed by a dead monster is used again, and is then whatever the newcomer is.
    func testAReusedStandeeTakesItsNewMonstersRank() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard()
        let elite = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .elite, at: HexCoord(3, 3), origin: .placed))
        XCTAssertTrue(coord.boardState.eliteStandees.contains(elite))
        coord.sufferDamage(99, to: elite)
        let normal = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 5), origin: .placed))
        XCTAssertEqual(normal, elite, "boards built by hand number in order, so the freed standee is taken again")
        XCTAssertFalse(coord.boardState.eliteStandees.contains(normal), "and it is a normal monster now")
    }

    /// Only as many monsters of a type as it has standees can be on the board (GH p.13).
    func testNoMonsterIsPlacedOnceItsStandeesAreAllOut() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        let coord = gm.boardCoordinator
        coord.boardState = makeBoard(cols: 12, rows: 12)
        var placed = 0
        for column in 0..<10 where coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(column, 2), origin: .placed) != nil {
            placed += 1
        }
        XCTAssertEqual(placed, 6, "Bandit Guards have six standees")
        let numbers = coord.boardState.piecePositions.keys.compactMap { piece -> Int? in
            if case .monster(_, let standee) = piece { return standee }
            return nil
        }
        XCTAssertEqual(Set(numbers), Set(1...6))
    }
}
