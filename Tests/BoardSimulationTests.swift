import XCTest
import SwiftData
@testable import GlavenGameLib

/// Plays real scenarios headlessly through the BoardCoordinator turn loop with the scripted party
/// (first cards, first options, prompts resolved by the coordinator), checking that the round flow
/// keeps the board and the game state consistent. `PlaythroughTests` plays to the end with the
/// tactical party; both use `ScenarioSimulator`, which checks every attack, move and board state.
@MainActor
final class BoardSimulationTests: XCTestCase {

    private func scripted(_ index: String, seed: UInt64, party: [String]? = nil, level: Int = 1) throws -> ScenarioSimulator {
        var options = ScenarioSimulator.Options(characterLevel: level, seed: seed, autoResolvePrompts: true)
        if let party { options.characters = party }
        return try ScenarioSimulator(scenario: index, options: options, policy: ScriptedPolicy())
    }

    private func hostileMonsters(_ sim: ScenarioSimulator) -> Int {
        sim.coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return !sim.coord.isPlayerSide($0) }; return false }.count
    }

    func testScenario1_playsRoundsConsistently() async throws {
        let sim = try scripted("1", seed: 11)
        XCTAssertGreaterThan(hostileMonsters(sim), 0, "starting room has monsters")

        // Monster ability decks advance: a type that acted for several rounds shows more than one card.
        var initiatives: [String: [Int]] = [:]
        var lastRound = -1
        await sim.play(rounds: 12) {
            guard sim.gm.game.round != lastRound, sim.gm.game.state == .next else { return }
            lastRound = sim.gm.game.round
            for monster in sim.gm.game.monsters where monster.abilityDrawn {
                if let initiative = sim.gm.monsterManager.currentAbilityInitiative(for: monster) {
                    initiatives[monster.name, default: []].append(initiative)
                }
            }
        }
        XCTAssertEqual(sim.violations, [])
        XCTAssertGreaterThanOrEqual(sim.gm.game.round, 2, "several rounds were played")
        for (name, seen) in initiatives where seen.count >= 3 {
            XCTAssertGreaterThan(Set(seen).count, 1, "\(name) reveals different ability cards over rounds: \(seen)")
        }
    }

    /// With tough characters and fragile monsters, the scripted party clears every room: doors
    /// open, rooms reveal and the default goal (kill everything) wins at the end of the round.
    func testScenario1_toughPartyRevealsRoomsAndWins() async throws {
        let sim = try scripted("1", seed: 12)
        for character in sim.gm.game.characters {
            character.maxHealth = 500
            character.health = 500
        }
        await sim.play(rounds: 40) {
            for monster in sim.gm.game.monsters {
                for entity in monster.aliveEntities where entity.health > 1 { entity.health = 1 }
            }
            // Keep the scripted party from running out of cards.
            if sim.coord.boardPhase == .cardSelection {
                for character in sim.gm.game.characters where !character.exhausted && character.handCards.count < 4 {
                    character.handCards.append(contentsOf: character.lostCards)
                    character.lostCards.removeAll()
                }
            }
        }
        XCTAssertTrue(sim.coord.boardState.doors.contains { $0.isOpen }, "the party opened a door")
        XCTAssertEqual(sim.coord.scenarioResult, .victory, "killing every monster in every room wins (round \(sim.gm.game.round))")
        XCTAssertNil(sim.outcomeProblem())
    }

    func testScenarioWithOwnWinConditionIsNotWonByEmptyBoard() async throws {
        // Ruinous Rift starts without monsters (they spawn each round) and is won at round 10.
        let sim = try scripted("27", seed: 13)
        await sim.play(rounds: 3)
        XCTAssertNotEqual(sim.coord.scenarioResult, .victory, "no early victory before the scenario's own goal")
        XCTAssertGreaterThan(hostileMonsters(sim), 0, "spawned demons are on the board")
        XCTAssertEqual(sim.violations, [])
    }

    func testScenarioLevelIsAppliedToMonsters() throws {
        // avg 5 / 2 = 2.5 → rounds up to 3
        let sim = try scripted("1", seed: 14, level: 5)
        XCTAssertEqual(sim.gm.game.level, 3)
        for monster in sim.gm.game.monsters where !monster.aliveEntities.isEmpty {
            XCTAssertEqual(monster.level, 3, "\(monster.name) uses the scenario level")
        }
    }

    func testManyScenariosRunWithoutStalling() async throws {
        for index in ["2", "3", "4", "8", "13", "36", "61"] {
            let sim = try scripted(index, seed: 15, party: ["brute", "tinkerer", "scoundrel"])
            await sim.play(rounds: 4)
            XCTAssertEqual(sim.violations, [], "scenario \(index)")
        }
    }
}

/// Regressions found in review: map tree lookups, starting rooms, monster card targeting.
@MainActor
final class BoardReviewRegressionTests: XCTestCase {

    private func makeGame() throws -> GameManager {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        for name in ["brute", "spellweaver", "cragheart", "scoundrel"] {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        return gm
    }

    private func start(_ index: String, gm: GameManager) throws -> BoardCoordinator {
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        coord.boardScene = nil
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        return coord
    }

    /// Every scenario sets up with a free starting hex for each of four characters, no monster on
    /// a starting hex, and every starting monster on the board. Scenarios that split the party
    /// between separate tiles (GH 50, 58, 85) reveal all of them.
    func testEveryScenarioSetsUpWithRoomForTheParty() throws {
        for number in 1...95 {
            let index = String(number)
            guard ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
            let gm = try makeGame()
            let coord = try start(index, gm: gm)
            let board = coord.boardState
            let free = board.startingLocations.filter { !board.isOccupied($0) }
            XCTAssertGreaterThanOrEqual(free.count, 4, "scenario \(index): a free starting hex per character")
            for hex in board.startingLocations {
                if let piece = board.piece(at: hex) { XCTFail("scenario \(index): \(piece) stands on starting hex \(hex)") }
            }
            XCTAssertTrue(coord.unplacedMonsterEntities().isEmpty, "scenario \(index): starting monsters placed")
        }
        for (index, tiles) in [("50", ["b2b", "b3b"]), ("58", ["c2a", "d1b"]), ("85", ["c1a", "c2b"])] {
            let gm = try makeGame()
            let coord = try start(index, gm: gm)
            XCTAssertTrue(Set(tiles).isSubset(of: coord.boardState.visibleRooms), "scenario \(index) starts in \(tiles)")
        }
        // GH 12's map is rooted at its last room; the party starts in the scenario's initial room.
        let gm = try makeGame()
        let coord = try start("12", gm: gm)
        XCTAssertTrue(coord.boardState.visibleRooms.contains("e1a"))
    }

    /// Opening every door in turn reveals the real room (with its onward doors and monsters), never
    /// an empty copy, and puts every revealed monster on the board.
    func testOpeningDoorsRevealsWholeMap() throws {
        for index in ["1", "6", "15", "21", "24", "32", "43", "76", "94"] {
            let gm = try makeGame()
            let coord = try start(index, gm: gm)
            var opened = 0
            while let door = coord.boardState.doors.first(where: { !$0.isOpen }), opened < 30 {
                coord.openDoor(at: door.coord)
                opened += 1
                XCTAssertTrue(coord.unplacedMonsterEntities().isEmpty, "scenario \(index): revealed monsters are placed")
            }
            let rooms = gm.game.scenario?.data.rooms ?? []
            XCTAssertEqual(gm.game.scenario?.revealedRooms.count, rooms.count,
                           "scenario \(index): every room revealed after opening all \(opened) doors")
            let positions = Array(coord.boardState.piecePositions.values)
            XCTAssertEqual(Set(positions).count, positions.count, "scenario \(index): one figure per hex")
        }
    }

    func testMonsterAttackAllAdjacentEnemies() {
        let action = ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                 subActions: [ActionModel(type: .specialTarget, value: .string("enemiesAdjacent"))])
        let spec = MonsterAbility.attack(action, stat: nil, baseAttack: 2, baseRange: 3)
        XCTAssertEqual(spec.allEnemiesWithin, 1)
        XCTAssertFalse(spec.isRanged)

        let oneAll = MonsterAbility.attack(
            ActionModel(type: .attack, value: .int(0), valueType: .plus,
                        subActions: [ActionModel(type: .specialTarget, value: .string("enemyOneAll"))]),
            stat: MonsterStatModel(type: .normal, level: 1, actions: [ActionModel(type: .target, value: .int(2))]),
            baseAttack: 2, baseRange: 0)
        XCTAssertTrue(oneAll.allAttacksOnFocus)
        XCTAssertEqual(oneAll.targetCount, 2)
    }

    func testMeleeAreaReachUsesPattern() {
        // A 3-hex line from the attacker: reaches 3 hexes even though the monster is melee.
        let action = ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                 subActions: [ActionModel(type: .area, value: .string("(0,0,active)|(1,0,target)|(2,0,target)|(3,0,target)"))])
        let spec = MonsterAbility.attack(action, stat: nil, baseAttack: 2, baseRange: 0)
        XCTAssertEqual(spec.range, 3)
        XCTAssertFalse(spec.isRanged)
    }

    func testOneAbilityCardPerRound() throws {
        let gm = try makeGame()
        gm.monsterManager.addMonster(name: "bandit-guard", edition: "gh")
        let monster = try XCTUnwrap(gm.game.monsters.first)
        gm.monsterManager.drawAbility(for: monster)
        let first = monster.ability
        gm.monsterManager.drawAbility(for: monster)
        XCTAssertEqual(monster.ability, first, "a second draw in the same round is ignored")
    }
}
