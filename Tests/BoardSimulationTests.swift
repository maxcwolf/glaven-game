import XCTest
import SwiftData
@testable import GlavenGameLib

/// Plays real scenarios headlessly through the BoardCoordinator turn loop with a scripted party,
/// checking that the round flow keeps the board and the game state consistent.
@MainActor
final class BoardSimulationTests: XCTestCase {

    // MARK: - Harness

    private func makeGame(characters: [String] = ["brute", "spellweaver", "cragheart", "scoundrel"]) throws -> GameManager {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        for name in characters {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        return gm
    }

    /// Start a scenario on the board in headless mode and place the party.
    private func startScenario(_ index: String, gm: GameManager) throws -> BoardCoordinator {
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        XCTAssertEqual(coord.boardPhase, .setup, "board started for scenario \(index)")
        coord.boardScene = nil
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        for (i, character) in gm.game.characters.enumerated() where i < coord.boardState.startingLocations.count {
            coord.placeCharacter(characterID: character.id, at: coord.boardState.startingLocations[i])
        }
        coord.finishSetup()
        return coord
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    /// Choose cards for whichever character is selecting (first two hand cards).
    private func selectCards(gm: GameManager, coord: BoardCoordinator) {
        while coord.boardPhase == .cardSelection, let id = coord.cardSelectingCharacterID,
              let character = gm.game.characters.first(where: { $0.id == id }) {
            let deck = gm.editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: "gh")
            let hand = character.handCards.compactMap { cardId in deck.first { $0.cardId == cardId } }
            guard hand.count >= 2 else { return }
            coord.storeSelectedCards(for: id, top: hand[0], bottom: hand[1])
            character.initiative = hand[0].initiative
            coord.completeCardSelection(for: id)
        }
    }

    /// Hostile monster positions.
    private func enemyHexes(_ coord: BoardCoordinator) -> [HexCoord] {
        coord.boardState.piecePositions.compactMap { id, hex in
            if case .monster = id, !coord.isPlayerSide(id) { return hex }
            return nil
        }
    }

    /// Respond to whatever the current player action is waiting for.
    private func answerInteraction(coord: BoardCoordinator) {
        switch coord.interactionMode {
        case .selectingMove(_, _, let hexes, _, _):
            // Head for the nearest enemy, or for a closed door once the room is clear.
            var enemies = enemyHexes(coord)
            if enemies.isEmpty {
                enemies = coord.boardState.doors.filter { !$0.isOpen }.map(\.coord)
            }
            let best = hexes.min { a, b in
                let da = enemies.map { a.distance(to: $0) }.min() ?? 0
                let db = enemies.map { b.distance(to: $0) }.min() ?? 0
                return da == db ? (a.col, a.row) < (b.col, b.row) : da < db
            }
            if let best { coord.handleHexTap(best) } else { coord.interactionMode = .idle }
        case .selectingAttackTarget(_, _, let targets):
            if let target = targets.sorted(by: { $0.description < $1.description }).first { coord.handlePieceTap(target) }
        case .selectingMultiAttackTargets(_, _, let targets, _, let selected):
            if let next = targets.subtracting(selected).sorted(by: { $0.description < $1.description }).first {
                coord.handlePieceTap(next)
            } else {
                coord.confirmMultiAttack()
            }
        case .selectingConditionTarget(_, _, let targets):
            if let target = targets.sorted(by: { $0.description < $1.description }).first { coord.handlePieceTap(target) }
        case .selectingHealTarget(let healer, _, _):
            coord.handlePieceTap(healer)
        case .placingSummon(_, _, let hexes):
            if let hex = hexes.sorted(by: { ($0.col, $0.row) < ($1.col, $1.row) }).first { coord.handleHexTap(hex) }
        case .selectingPushPullHex(_, _, let hexes, _, _):
            if let hex = hexes.sorted(by: { ($0.col, $0.row) < ($1.col, $1.row) }).first { coord.handleHexTap(hex) }
        default:
            break
        }
    }

    /// Play one player turn to completion.
    private func playTurn(_ turn: PlayerTurnController, coord: BoardCoordinator) async {
        var steps = 0
        while turn.phase != .turnComplete && steps < 60 {
            steps += 1
            if case .idle = coord.interactionMode {
                turn.executeCurrentAction()
            } else {
                answerInteraction(coord: coord)
            }
            _ = await waitUntil(timeout: 0.05) { false }
            if coord.scenarioResult != nil { return }
        }
        // Let any pending move/attack finish before ending the turn.
        _ = await waitUntil(timeout: 1) {
            if case .idle = coord.interactionMode { return true }
            answerInteraction(coord: coord)
            return false
        }
        if coord.activePlayerTurn === turn {
            coord.finishPlayerTurn()
        }
    }

    /// Board/game-state consistency checks.
    private func assertConsistent(gm: GameManager, coord: BoardCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        for (piece, _) in coord.boardState.piecePositions {
            switch piece {
            case .monster(let name, let standee):
                let entity = coord.monsterEntity(name: name, standee: standee)
                XCTAssertNotNil(entity, "monster piece \(piece) has an entity", file: file, line: line)
                XCTAssertFalse(entity?.dead ?? true, "monster piece \(piece) is alive", file: file, line: line)
            case .character(let id):
                let character = gm.game.characters.first { $0.id == id }
                XCTAssertFalse(character?.exhausted ?? true, "character piece \(id) is not exhausted", file: file, line: line)
            case .summon:
                let summon = coord.entity(for: piece) as? GameSummon
                XCTAssertFalse(summon?.dead ?? true, "summon piece is alive", file: file, line: line)
            case .objective:
                break
            }
        }
        // No two pieces share a hex.
        let positions = Array(coord.boardState.piecePositions.values)
        XCTAssertEqual(Set(positions).count, positions.count, "one figure per hex", file: file, line: line)
        // Every living character has a full set of cards accounted for.
        for character in gm.game.characters where !character.exhausted {
            let total = character.handCards.count + character.discardedCards.count
                + character.lostCards.count + character.activeCards.count
            XCTAssertEqual(total, character.handSize, "\(character.name) keeps all \(character.handSize) cards", file: file, line: line)
        }
    }

    /// Run the scenario for up to `rounds` rounds. Returns the monster initiatives seen per type.
    @discardableResult
    private func play(gm: GameManager, coord: BoardCoordinator, rounds: Int,
                      eachStep: (() -> Void)? = nil) async -> [String: [Int]] {
        var initiatives: [String: [Int]] = [:]
        var lastRound = -1
        var guardSteps = 0
        while coord.scenarioResult == nil && gm.game.round < rounds && guardSteps < 5000 {
            guardSteps += 1
            eachStep?()
            if coord.boardPhase == .cardSelection {
                selectCards(gm: gm, coord: coord)
            }
            if gm.game.round != lastRound && gm.game.state == .next {
                lastRound = gm.game.round
                for monster in gm.game.monsters where monster.abilityDrawn {
                    if let initiative = gm.monsterManager.currentAbilityInitiative(for: monster) {
                        initiatives[monster.name, default: []].append(initiative)
                    }
                }
            }
            if let turn = coord.activePlayerTurn {
                await playTurn(turn, coord: coord)
                assertConsistent(gm: gm, coord: coord)
            } else if let rest = coord.pendingLongRest {
                coord.resolveLongRest(characterID: rest.characterID, discardIndex: 0)
            } else if coord.pendingShortRest != nil {
                coord.commitShortRest()
                coord.resolveShortRest()
            } else {
                _ = await waitUntil(timeout: 0.02) { false }
            }
        }
        XCTAssertLessThan(guardSteps, 5000, "simulation kept making progress")
        return initiatives
    }

    // MARK: - Tests

    func testScenario1_playsRoundsConsistently() async throws {
        let gm = try makeGame()
        let coord = try startScenario("1", gm: gm)
        XCTAssertGreaterThan(enemyHexes(coord).count, 0, "starting room has monsters")
        assertConsistent(gm: gm, coord: coord)

        let initiatives = await play(gm: gm, coord: coord, rounds: 12)
        assertConsistent(gm: gm, coord: coord)
        if ProcessInfo.processInfo.environment["SIM_LOG"] != nil {
            for entry in coord.turnLog { print("LOG", entry.isRoundHeader ? "=== \(entry.message) ===" : entry.message) }
        }
        XCTAssertGreaterThanOrEqual(gm.game.round, 2, "several rounds were played")

        // Monster ability decks advance: a type that acted for several rounds shows more than one card.
        for (name, seen) in initiatives where seen.count >= 3 {
            XCTAssertGreaterThan(Set(seen).count, 1, "\(name) reveals different ability cards over rounds: \(seen)")
        }
    }

    func testScenario1_toughPartyRevealsRoomsAndWins() async throws {
        let gm = try makeGame()
        let coord = try startScenario("1", gm: gm)
        for character in gm.game.characters {
            character.maxHealth = 500
            character.health = 500
        }
        // Fragile monsters so the scripted party can clear every room before running out of cards.
        await play(gm: gm, coord: coord, rounds: 40) {
            for monster in gm.game.monsters {
                for entity in monster.aliveEntities where entity.health > 1 { entity.health = 1 }
            }
            // Keep the scripted party from running out of cards.
            if coord.boardPhase == .cardSelection {
                for character in gm.game.characters where !character.exhausted && character.handCards.count < 4 {
                    character.handCards.append(contentsOf: character.lostCards)
                    character.lostCards.removeAll()
                }
            }
        }
        assertConsistent(gm: gm, coord: coord)
        if ProcessInfo.processInfo.environment["SIM_LOG"] != nil {
            for entry in coord.turnLog { print("LOG", entry.isRoundHeader ? "=== \(entry.message) ===" : entry.message) }
        }
        XCTAssertTrue(coord.boardState.doors.contains { $0.isOpen }, "the party opened a door")
        XCTAssertEqual(coord.scenarioResult, .victory, "killing every monster in every room wins (round \(gm.game.round))")
    }

    func testScenarioWithOwnWinConditionIsNotWonByEmptyBoard() async throws {
        // Ruinous Rift starts without monsters (they spawn each round) and is won at round 10.
        let gm = try makeGame()
        let coord = try startScenario("27", gm: gm)
        await play(gm: gm, coord: coord, rounds: 3)
        XCTAssertNotEqual(coord.scenarioResult, .victory, "no early victory before the scenario's own goal")
        XCTAssertGreaterThan(enemyHexes(coord).count, 0, "spawned demons are on the board")
    }

    func testDebugScenarioLog() async throws {
        guard let index = ProcessInfo.processInfo.environment["SIM_SCENARIO"] else { throw XCTSkip("set SIM_SCENARIO") }
        let gm = try makeGame()
        let coord = try startScenario(index, gm: gm)
        await play(gm: gm, coord: coord, rounds: 3)
        for entry in coord.turnLog { print("LOG", entry.isRoundHeader ? "=== \(entry.message) ===" : entry.message) }
        for c in gm.game.characters { print("CHAR", c.name, c.health, c.maxHealth, c.exhausted, c.handCards.count, c.discardedCards.count, c.lostCards.count) }
    }

    func testScenarioLevelIsAppliedToMonsters() async throws {
        let gm = try makeGame()
        for character in gm.game.characters {
            character.level = 5
        }
        let coord = try startScenario("1", gm: gm)
        // avg 5 / 2 = 2.5 → rounds up to 3
        XCTAssertEqual(gm.game.level, 3)
        for monster in gm.game.monsters where !monster.aliveEntities.isEmpty {
            XCTAssertEqual(monster.level, 3, "\(monster.name) uses the scenario level")
        }
        assertConsistent(gm: gm, coord: coord)
    }

    func testStartingRoomMonstersMatchScenarioData() async throws {
        // Every starting-room monster created from the scenario data has a board piece.
        for index in ["1", "2", "3", "4", "5", "8", "13"] {
            let gm = try makeGame()
            let coord = try startScenario(index, gm: gm)
            XCTAssertTrue(coord.unplacedMonsterEntities().isEmpty,
                          "scenario \(index): all starting monsters are on the board")
            assertConsistent(gm: gm, coord: coord)
        }
    }

    /// Every main GH scenario: setup + a few rounds without crashing, stalling or desyncing.
    /// Slow — enabled with SIM_ALL=1.
    func testAllScenariosSmoke() async throws {
        guard ProcessInfo.processInfo.environment["SIM_ALL"] != nil else { throw XCTSkip("set SIM_ALL=1") }
        for number in 1...95 {
            let index = String(number)
            guard ScenarioMapStore.shared.scenarioMap(for: index) != nil else { continue }
            let gm = try makeGame()
            let coord = try startScenario(index, gm: gm)
            await play(gm: gm, coord: coord, rounds: 3)
            assertConsistent(gm: gm, coord: coord)
            print("SMOKE scenario \(index): round \(gm.game.round), result \(String(describing: coord.scenarioResult)), monsters on board \(enemyHexes(coord).count)")
        }
    }

    func testManyScenariosRunWithoutStalling() async throws {
        for index in ["2", "3", "4", "8", "13", "36", "61"] {
            let gm = try makeGame(characters: ["brute", "tinkerer", "scoundrel"])
            let coord = try startScenario(index, gm: gm)
            await play(gm: gm, coord: coord, rounds: 4)
            assertConsistent(gm: gm, coord: coord)
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

    /// Every party member gets a starting hex, and the starting monsters are placed.
    func testStartingRoomHasRoomForTheParty() throws {
        for index in ["12", "36", "50", "85"] {
            let gm = try makeGame()
            let coord = try start(index, gm: gm)
            XCTAssertGreaterThanOrEqual(coord.boardState.startingLocations.count, 4,
                                        "scenario \(index) has starting locations for the party")
            XCTAssertTrue(coord.unplacedMonsterEntities().isEmpty, "scenario \(index): starting monsters placed")
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
