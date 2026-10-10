import XCTest
import SpriteKit
import SwiftData
@testable import GlavenGameLib

/// Objectives on the board and lettered spawn hexes (`ScenarioPlacements`): the map data has
/// neither, so their hexes are written by hand, tile by tile.
@MainActor
final class ScenarioPlacementTests: XCTestCase {

    // MARK: - The written data

    /// The whole map of a scenario, every door opened.
    private func wholeBoard(_ index: String) throws -> (BoardState, VGBScenario) {
        let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index), "map \(index)")
        let (board, _) = BoardBuilder.buildStartingRoom(from: map)
        while let door = board.doors.first(where: { !$0.isOpen }) {
            XCTAssertNotNil(BoardBuilder.revealRoomSlots(door: door, scenario: map, board: board), "\(index): \(door.childTileRef)")
            if let stuck = board.doors.firstIndex(where: { $0.coord == door.coord && !$0.isOpen }) { board.doors[stuck].isOpen = true }
        }
        return (board, map)
    }

    /// Every objective and marker written lands on a hex of its map: an objective on its own
    /// hex (a barred door on a door), a marker on a hex of the map.
    func testEveryWrittenPlacementLandsOnItsMap() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        let written = ScenarioPlacementStore.shared.all()
        XCTAssertFalse(written.isEmpty, "placements are bundled")
        for (index, placements) in written.sorted(by: { $0.key < $1.key }) {
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil }, index)
            let (board, _) = try wholeBoard(index)
            let entries = placements.tiles.values.flatMap { $0.objectives ?? [] }
            XCTAssertEqual(board.openObjectiveSlots.count, entries.count, "\(index): every objective written has a place on the map")
            XCTAssertEqual(Set(board.openObjectiveSlots.map(\.coord)).count, board.openObjectiveSlots.count, "\(index): one objective a hex")
            for slot in board.openObjectiveSlots {
                XCTAssertTrue((1...(data.objectives?.count ?? 0)).contains(slot.objective), "\(index): objective \(slot.objective) exists")
                XCTAssertNotNil(board.cells[slot.coord], "\(index): \(slot.coord) is on the map")
                XCTAssertEqual(slot.barsDoor, board.doors.contains { $0.coord == slot.coord }, "\(index): \(slot.coord) door")
                for hex in slot.cells { XCTAssertNotNil(board.cells[hex], "\(index): \(hex) is on the map") }
            }
            let letters = placements.tiles.values.flatMap { ($0.markers ?? [:]).keys }
            XCTAssertEqual(Set(board.markerHexes.keys), Set(letters), "\(index): every marker written is on the map")
            for (marker, hexes) in board.markerHexes {
                for hex in hexes { XCTAssertNotNil(board.cells[hex], "\(index): marker \(marker) at \(hex) is on the map") }
            }
        }
    }

    /// Every written goal names things its scenario has: its monsters, objectives, letters,
    /// tiles and treasure.
    func testEveryWrittenGoalRefersToThingsInItsScenario() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        for (index, placements) in ScenarioPlacementStore.shared.all().sorted(by: { $0.key < $1.key }) {
            guard let goal = placements.goal else { continue }
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil }, index)
            let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index))
            let tiles = BoardBuilder.findPlacements(in: map.mapTileData).map(\.tile)
            let monsters = Set((data.monsters ?? []).map { MonsterNameSpec($0).name })
            let letters = Set(placements.tiles.values.flatMap { ($0.markers ?? [:]).keys })
            let treasure = Set(tiles.flatMap { $0.overlays.filter { $0.ref.type == "treasure" }.compactMap(\.ref.id) })
            func check(_ goal: ScenarioPlacements.Goal) {
                XCTAssertFalse((goal.text ?? "x").isEmpty)
                for name in (goal.kill ?? []) + (goal.killCount?.of ?? []) + (goal.lostIfKilled ?? []) + (goal.spare ?? []) {
                    XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
                }
                for objective in (goal.destroy ?? []) + (goal.arrive.map { [$0.objective] } ?? []) + (goal.lostAt ?? [:]).keys.compactMap(Int.init) {
                    XCTAssertTrue((1...(data.objectives?.count ?? 0)).contains(objective), "\(index): no objective \(objective)")
                }
                let used = [goal.arrive?.marker, goal.escape?.marker, goal.reach?.marker].compactMap { $0 }
                    + (goal.occupy.map { $0.markers + ($0.more ?? [:]).values.flatMap { $0 } } ?? [])
                for letter in used { XCTAssertTrue(letters.contains(letter), "\(index): no hex lettered \(letter)") }
                for tile in (goal.reveal ?? []) + [goal.escape?.tile, goal.lostIfExhaustedOnceRevealed].compactMap({ $0 }) where tile != "*" {
                    XCTAssertTrue(tiles.contains { $0.ref.lowercased() == tile }, "\(index): no tile \(tile)")
                }
                if goal.loot != nil { XCTAssertTrue(treasure.contains(BoardCoordinator.goalTreasureID), "\(index): no goal treasure") }
                for id in goal.lootIDs ?? [] { XCTAssertTrue(treasure.contains(id), "\(index): no treasure \(id)") }
                if let kills = goal.killCount {
                    XCTAssertNotNil(ScenarioExpression.integerValue(kills.count, variables: ["C": 2, "L": 1]), "\(index): \(kills.count)")
                }
                XCTAssertTrue(["all", "revealed", nil].contains(goal.enemies), "\(index)")
                XCTAssertTrue(["goal", "each", nil].contains(goal.loot), "\(index)")
                for way in goal.lostIfExhausted ?? [] { XCTAssertTrue(["any", "offExit", "beforeLoot"].contains(way), "\(index): \(way)") }
                if goal.lostIfExhausted?.contains("offExit") == true { XCTAssertNotNil(goal.escape, "\(index): an exit to be off") }
                (goal.either ?? []).forEach(check)
            }
            check(goal)
        }
    }

    /// Every rule written for a scenario names things it has: monsters, letters, tiles, locks,
    /// objectives and treasure; what is held back is set up by some rule, and a rule left out is
    /// one of the scenario's own.
    func testEveryWrittenRuleRefersToThingsInItsScenario() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        var checked = 0
        for (index, placements) in ScenarioPlacementStore.shared.all().sorted(by: { $0.key < $1.key }) {
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil }, index)
            let map = try XCTUnwrap(ScenarioMapStore.shared.scenarioMap(for: index))
            let tiles = Set(BoardBuilder.findPlacements(in: map.mapTileData).map { $0.tile.ref.lowercased() })
            let monsters = Set((data.monsters ?? []).map { MonsterNameSpec($0).name })
            let inRooms = Set((data.rooms ?? []).flatMap { ($0.monster ?? []).map(\.name) })
            let letters = Set(placements.tiles.values.flatMap { ($0.markers ?? [:]).keys })
            let treasure = Set(BoardBuilder.findPlacements(in: map.mapTileData)
                .flatMap { $0.tile.overlays.filter { $0.ref.type == "treasure" }.compactMap(\.ref.id) })
            let objectives = Set((data.objectives ?? []).compactMap(\.name))
            let rules = placements.rules ?? []
            let own = (data.rules ?? []).count - rules.count

            for dropped in placements.dropRules ?? [] { XCTAssertTrue((0..<own).contains(dropped), "\(index): no rule \(dropped) to leave out") }
            for (objective, risen) in placements.whenDestroyed ?? [:] {
                XCTAssertTrue((1...(data.objectives?.count ?? 0)).contains(Int(objective) ?? 0), "\(index): no objective \(objective)")
                XCTAssertTrue(monsters.contains(risen.name), "\(index): no monster \(risen.name)")
            }
            for name in placements.later ?? [] {
                XCTAssertTrue(inRooms.contains(name), "\(index): no \(name) in a room to hold back")
                XCTAssertTrue(rules.contains { ($0.setUp ?? []).contains(name) || ($0.spawns ?? []).contains { $0.monster.name == name } },
                              "\(index): nothing ever sets up \(name)")
            }
            for objective in placements.focusFirst ?? [] {
                XCTAssertEqual(data.objectives?.indices.contains(objective - 1), true, "\(index): no objective \(objective)")
            }
            for name in (placements.undamageable ?? []) + (placements.reprieve.map { $0.killed + [$0.removes] } ?? []) {
                XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
            }
            if let cleansing = placements.water?.cleanses {
                for tile in cleansing.tiles { XCTAssertTrue(tiles.contains(tile), "\(index): no tile \(tile)") }
                for name in cleansing.against { XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)") }
            }
            for name in placements.apart ?? [] { XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)") }
            for objective in placements.sheltered ?? [] {
                XCTAssertEqual(data.objectives?.indices.contains(objective - 1), true, "\(index): no objective \(objective)")
                XCTAssertEqual(placements.protect?.contains(objective), nil, "\(index): sheltered or protected, not both")
            }
            if let damage = placements.water?.endOfTurn {
                XCTAssertNotNil(ScenarioExpression.integerValue(damage, variables: ["C": 2, "L": 1]), "\(index): \(damage)")
            }
            for (name, cycle) in placements.cycles ?? [:] {
                XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
                XCTAssertTrue((cycle.letters?.isEmpty == false) != (cycle.doors == true), "\(index): letters or doors")
                for letter in cycle.letters ?? [] { XCTAssertTrue(letters.contains(letter), "\(index): no hex lettered \(letter)") }
                if cycle.doors == true { XCTAssertFalse((placements.locks ?? []).isEmpty, "\(index): no locked doors to go round") }
                if cycle.appears == true || cycle.leavesAfterMelee == true { XCTAssertNotNil(cycle.letters, index) }
            }
            for (name, specials) in placements.specials ?? [:] {
                XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
                XCTAssertEqual(specials.count, 2, "\(index): a boss has two specials")
            }
            for entry in placements.inactive ?? [] {
                XCTAssertFalse(entry.monsters.isEmpty, index)
                for name in entry.monsters { XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)") }
                XCTAssertTrue((entry.rounds.map { ["odd", "even"].contains($0) } ?? false) != (entry.untilSetUp == true),
                              "\(index): inactive by the round, or until woken")
                if entry.untilSetUp == true {
                    for name in entry.monsters {
                        XCTAssertTrue(rules.contains { ($0.setUp ?? []).contains(name) }, "\(index): nothing wakes \(name)")
                    }
                }
            }
            for note in placements.notes ?? [] {
                XCTAssertGreaterThan(note.split(separator: " ").count, 4, "\(index): \(note)")
                XCTAssertTrue(note.hasSuffix("."), "\(index): \(note)")
            }
            for effect in placements.effects ?? [] {
                XCTAssertTrue(["monsters", "party"].contains(effect.on) || monsters.contains(effect.on), "\(index): no \(effect.on)")
                XCTAssertTrue(effect.attack != nil || effect.advantage != nil || effect.disadvantage != nil || effect.shield != nil
                              || effect.noItems != nil, "\(index): an effect that does nothing")
                if effect.untilLooted == true { XCTAssertEqual(placements.goal?.loot, "each", "\(index): no treasure for each to loot") }
                for objective in [effect.whileStanding, effect.per?.objective].compactMap({ $0 }) {
                    XCTAssertTrue((1...(data.objectives?.count ?? 0)).contains(objective), "\(index): no objective \(objective)")
                }
                for name in [effect.per?.monster, effect.per?.lostWith].compactMap({ $0 }) {
                    XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
                }
                if let room = effect.room { XCTAssertTrue((data.rooms ?? []).contains { $0.roomNumber == room }, "\(index): no room \(room)") }
                if let shield = effect.shield {
                    XCTAssertNotNil(ScenarioExpression.integerValue(shield, variables: ["X": 2, "C": 2, "L": 1]), "\(index): \(shield)")
                    XCTAssertEqual(effect.per?.tokens != nil, effect.per?.lostWith != nil, "\(index): tokens are lost with something")
                }
            }
            for rule in rules {
                checked += 1
                for spawn in rule.spawns ?? [] {
                    XCTAssertTrue(monsters.contains(MonsterNameSpec(spawn.monster.name).name), "\(index): no monster \(spawn.monster.name)")
                    // A letter on the map, or one a monster of the scenario carries (it appears where that one fell).
                    let carried = Set((data.rooms ?? []).flatMap { ($0.monster ?? []).compactMap(\.marker) })
                    if let marker = spawn.marker {
                        XCTAssertTrue(letters.contains(marker) || carried.contains(marker), "\(index): no hex lettered \(marker)")
                    }
                }
                let asleep = (placements.inactive ?? []).filter { $0.untilSetUp == true }.flatMap(\.monsters)
                for name in rule.setUp ?? [] {
                    XCTAssertTrue((placements.later ?? []).contains(name) || asleep.contains(name), "\(index): \(name) isn't held back or asleep")
                }
                for room in (rule.requiredRooms ?? []) + (rule.rooms ?? []) {
                    XCTAssertTrue((data.rooms ?? []).contains { $0.roomNumber == room }, "\(index): no room \(room)")
                }
                for fact in rule.when ?? [] {
                    XCTAssertTrue(fact.saved != nil || fact.lock != nil || fact.looted != nil || fact.unrevealed != nil
                                  || fact.occupied != nil, "\(index): an empty fact")
                    for letter in fact.occupied.map({ $0.markers + ($0.more ?? [:]).values.flatMap { $0 } }) ?? [] {
                        XCTAssertTrue(letters.contains(letter), "\(index): no plate \(letter)")
                    }
                    if let room = fact.unrevealed { XCTAssertTrue((data.rooms ?? []).contains { $0.roomNumber == room && $0.initial != true }, "\(index): no room \(room) to reveal") }
                    if let lock = fact.lock { XCTAssertTrue((placements.locks ?? []).indices.contains(lock), "\(index): no lock \(lock)") }
                    if fact.saved != nil { XCTAssertNotNil(placements.goal?.arrive, "\(index): no one to save") }
                    if let looted = fact.looted {
                        XCTAssertTrue(treasure.contains(looted) || (tiles.contains(looted) && treasure.contains(BoardCoordinator.goalTreasureID)),
                                      "\(index): no treasure \(looted)")
                    }
                }
                for figure in rule.figures ?? [] {
                    guard let identifier = figure.identifier else { continue }
                    if identifier.type ?? "monster" == "monster", let name = identifier.name, name != ".*" {
                        XCTAssertTrue(monsters.contains(name), "\(index): no monster \(name)")
                    }
                    if identifier.type == "objective", let name = identifier.name { XCTAssertTrue(objectives.contains(name), "\(index): no objective \(name)") }
                    if let tile = identifier.tile { XCTAssertTrue(tiles.contains(tile), "\(index): no tile \(tile)") }
                    if let near = identifier.near {
                        XCTAssertTrue((near.marker != nil) != (near.objective != nil), "\(index): near one thing")
                        if let marker = near.marker { XCTAssertTrue(letters.contains(marker), "\(index): no hex lettered \(marker)") }
                        if let objective = near.objective { XCTAssertTrue(objectives.contains(objective), "\(index): no objective \(objective)") }
                        XCTAssertGreaterThan(near.range, 0, index)
                    }
                    if let value = figure.value, case .string(let text) = value, ["damage", "heal"].contains(figure.type) {
                        XCTAssertNotNil(ScenarioExpression.integerValue(text, variables: ["C": 2, "L": 1, "R": 3, "F": 1]), "\(index): \(text)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 15)
    }

    // MARK: - Objectives in play

    private func simulator(_ index: String, characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        try ScenarioSimulator(scenario: index, options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
    }

    private func objectives(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .objective = $0 { return true }; return false }.sorted()
    }

    /// Temple of the Elements: four altars, one in each side room, each its own piece standing
    /// on the altar drawn there. Characters attack them; monsters leave them be.
    func testAltarsStandInTheirRoomsToBeDestroyed() throws {
        let sim = try simulator("22")
        let coord = sim.coord
        XCTAssertTrue(objectives(sim).isEmpty, "no altar in the first room")
        while let door = coord.boardState.doors.first(where: { !$0.isOpen }) { coord.openDoor(at: door.coord) }

        let altars = objectives(sim)
        XCTAssertEqual(altars.count, 4)
        XCTAssertEqual(altars.map(coord.name), ["Altar 1", "Altar 2", "Altar 3", "Altar 4"])
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let demon = try XCTUnwrap(coord.boardState.piecePositions.keys.sorted().first {
            if case .monster(let name, _) = $0 { return name.contains("demon") }; return false })
        for altar in altars {
            let hex = try XCTUnwrap(coord.boardState.piecePositions[altar])
            XCTAssertEqual(coord.boardState.cells[hex]?.overlaySubType, "altar", "on the altar drawn on the map")
            XCTAssertTrue(coord.areEnemies(brute, altar), "characters attack it")
            XCTAssertFalse(coord.areEnemies(demon, altar))
            XCTAssertFalse(coord.areAllies(demon, altar), "and it is no monster's ally")
            XCTAssertFalse(coord.pieceAppearance(altar).isPlayerSide)
        }
        let demons = try XCTUnwrap(sim.gm.game.monsters.first { $0.name.contains("demon") })
        XCTAssertFalse(MonsterAI.gatherEnemies(board: coord.boardState, monster: demons, gameState: sim.gm.game)
            .contains { altars.contains($0) }, "monsters don't attack the altars")
        XCTAssertTrue(PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: false)
            .contains(altars[0]), "a summon does")

        // Immune to conditions, never moved.
        coord.applyCondition(.wound, to: altars[0])
        XCTAssertTrue(coord.entity(for: altars[0])?.entityConditions.isEmpty ?? false)

        // Destroyed: off the board, and the obstacle with it.
        let hex = try XCTUnwrap(coord.boardState.piecePositions[altars[0]])
        coord.sufferDamage(99, to: altars[0], killer: brute)
        XCTAssertNil(coord.boardState.piecePositions[altars[0]])
        XCTAssertNil(coord.boardState.cells[hex]?.overlay)
        XCTAssertTrue(coord.boardState.isPassable(hex))
        XCTAssertEqual(objectives(sim).count, 3)
    }

    /// Sanctuary of Gloom: the three doors can't be opened, only broken down.
    func testABarredDoorOpensWhenBrokenDown() throws {
        let sim = try simulator("29")
        let coord = sim.coord
        let doors = objectives(sim)
        XCTAssertEqual(doors.count, 3)
        XCTAssertEqual(coord.boardState.doors.count, 3)
        let door = doors[0]
        let hex = try XCTUnwrap(coord.boardState.piecePositions[door])
        XCTAssertTrue(coord.boardState.isClosedDoor(hex), "it stands on its door")
        let rooms = coord.boardState.visibleRooms.count

        coord.openDoor(at: hex)
        XCTAssertTrue(coord.boardState.isClosedDoor(hex), "a barred door doesn't open")
        XCTAssertEqual(coord.boardState.visibleRooms.count, rooms)

        coord.sufferDamage(99, to: door, killer: .character(sim.gm.game.characters[0].id))
        XCTAssertFalse(coord.boardState.isClosedDoor(hex), "broken down, it is open")
        XCTAssertEqual(coord.boardState.visibleRooms.count, rooms + 1, "and the room behind is revealed")
        XCTAssertEqual(objectives(sim).count, 2)
    }

    // MARK: - Objectives as the rooms list them

    /// Ancient Cistern lists "Water Pump" three times over (a, b, c) and its room mentions them
    /// by player count: two pumps for two characters, four for four. Each is its own piece.
    func testEachMentionOfAnObjectiveIsItsOwn() throws {
        for (characters, markers) in [(["brute", "spellweaver"], ["a", "a"]),
                                      (["brute", "spellweaver", "cragheart", "scoundrel"], ["a", "a", "b", "c"])] {
            let sim = try simulator("26", characters: characters)
            let room = try XCTUnwrap(sim.gm.game.scenario?.data.rooms?.first { $0.objectives != nil })
            sim.gm.scenarioManager.openRoom(room)
            let pumps = sim.gm.game.objectives.flatMap(\.entities)
            XCTAssertEqual(pumps.map(\.marker).sorted(), markers, "\(characters.count) characters")
            XCTAssertEqual(Set(pumps.map(\.number)).count, pumps.count, "each has its own number")
        }
    }

    /// A pump has no hit points: nothing attacks it, and having none doesn't destroy it.
    func testAnObjectiveWithoutHitPointsIsLeftAlone() throws {
        let sim = try simulator("26")
        let coord = sim.coord
        let room = try XCTUnwrap(sim.gm.game.scenario?.data.rooms?.first { $0.objectives != nil })
        sim.gm.scenarioManager.openRoom(room)
        let pump = try XCTUnwrap(sim.gm.game.objectives.first?.entities.first)
        let piece = PieceID.objective(id: pump.number)
        let hex = try XCTUnwrap(coord.nearestEmptyHex(to: coord.boardState.startingLocations[0]))
        coord.boardState.placePiece(piece, at: hex)
        coord.sweepDeadFigures()
        XCTAssertNotNil(coord.boardState.piecePositions[piece], "still there")
        XCTAssertFalse(coord.areEnemies(.character(sim.gm.game.characters[0].id), piece))
    }

    // MARK: - Spawn markers

    /// A rule's spawn at a letter goes to the hex lettered with it; with that taken, as near as
    /// it can. A letter an objective carries (an imp at water pump "a") is beside the objective.
    func testARuleSpawnGoesToItsLetter() throws {
        let sim = try simulator("1")
        let coord = sim.coord
        let free = coord.boardState.cells.keys.sorted().filter(coord.isEmptyHex)
        let lettered = try XCTUnwrap(free.last)
        coord.boardState.markerHexes["a"] = [lettered]
        let before = Set(coord.boardState.piecePositions.keys)
        XCTAssertTrue(coord.spawnFromScenarioRule(name: "bandit-archer", type: .normal, marker: "a", health: nil))
        let first = try XCTUnwrap(Set(coord.boardState.piecePositions.keys).subtracting(before).first)
        XCTAssertEqual(coord.boardState.piecePositions[first], lettered)

        XCTAssertTrue(coord.spawnFromScenarioRule(name: "bandit-archer", type: .normal, marker: "a", health: nil))
        let second = try XCTUnwrap(Set(coord.boardState.piecePositions.keys).subtracting(before).subtracting([first]).first)
        let secondHex = try XCTUnwrap(coord.boardState.piecePositions[second])
        XCTAssertEqual(secondHex.distance(to: lettered), 1, "beside the taken hex")

        // No hex lettered "b", but an objective carries it.
        let container = GameObjectiveContainer(name: "Water Pump", edition: "gh", title: "Water Pump")
        let pump = GameObjectiveEntity(number: sim.gm.game.nextObjectiveNumber, health: 0, maxHealth: 0)
        pump.marker = "b"
        container.entities = [pump]
        sim.gm.game.figures.append(.objective(container))
        let pumpHex = try XCTUnwrap(free.first { $0.distance(to: lettered) > 3 })
        coord.boardState.placePiece(.objective(id: pump.number), at: pumpHex)
        let taken = Set(coord.boardState.piecePositions.keys)
        XCTAssertTrue(coord.spawnFromScenarioRule(name: "bandit-archer", type: .normal, marker: "b", health: nil))
        let third = try XCTUnwrap(Set(coord.boardState.piecePositions.keys).subtracting(taken).first)
        XCTAssertEqual(coord.boardState.piecePositions[third]?.distance(to: pumpHex), 1, "beside the pump")
    }

    /// Inox Encampment: for three or four characters a guard arrives at (a) as every round
    /// begins — before anyone acts — and for two, as odd rounds end.
    func testTheEncampmentsGuardArrivesAsTheRoundBegins() async throws {
        for (party, early) in [(["brute", "spellweaver", "cragheart"], true), (["brute", "spellweaver"], false)] {
            let sim = try simulator("3", characters: party)
            await sim.play(rounds: 1)
            let arrival = try XCTUnwrap(sim.transcript.firstIndex { $0.contains("Inox Guard") && $0.contains("appears") && $0.contains("marker a") },
                                        "\(party.count): a guard arrives in round 1")
            let firstTurn = try XCTUnwrap(sim.transcript.firstIndex { $0.contains("turn:") || $0.contains("\u{2019}s turn") })
            XCTAssertEqual(arrival < firstTurn, early, "\(party.count) characters")
        }
    }

    // MARK: - Escorts

    /// An escort fights on the players' side: monsters focus on it as on a character.
    func testMonstersAttackAnEscort() throws {
        let sim = try simulator("1")
        let coord = sim.coord
        let container = GameObjectiveContainer(name: "Hail", edition: "gh", title: "Hail", escort: true)
        let hail = GameObjectiveEntity(number: sim.gm.game.nextObjectiveNumber, health: 6, maxHealth: 6)
        container.entities = [hail]
        sim.gm.game.figures.append(.objective(container))
        let piece = PieceID.objective(id: hail.number)
        coord.boardState.placePiece(piece, at: try XCTUnwrap(coord.nearestEmptyHex(to: coord.boardState.startingLocations[0])))

        let guards = try XCTUnwrap(sim.gm.game.monsters.first)
        XCTAssertTrue(MonsterAI.gatherEnemies(board: coord.boardState, monster: guards, gameState: sim.gm.game).contains(piece))
        XCTAssertTrue(coord.isPlayerSide(piece))
        XCTAssertTrue(coord.areAllies(.character(sim.gm.game.characters[0].id), piece))
        XCTAssertFalse(PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: false).contains(piece))
    }

    /// Forgotten Crypt: Hail's "Move 2 towards the altar (b)" walks to the hex lettered b, two
    /// hexes a turn, instead of toward an enemy.
    func testAnEscortWalksToTheLetterItsMoveNames() async throws {
        let sim = try simulator("19")
        let coord = sim.coord
        let container = try XCTUnwrap(sim.gm.game.objectives.first { $0.name == "Hail" })
        let hail = try XCTUnwrap(container.entities.first)
        let piece = PieceID.objective(id: hail.number)
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        // The altar's room isn't revealed: she makes for the door on the way to it.
        let door = try XCTUnwrap(coord.boardState.doors.first)
        XCTAssertEqual(controller.destination(of: container), [door.coord])

        // A free hex well away from the start, lettered b.
        let start = try XCTUnwrap(coord.nearestEmptyHex(to: coord.boardState.startingLocations[0]))
        coord.boardState.placePiece(piece, at: start)
        func steps(_ from: HexCoord, _ to: HexCoord) -> Int? {
            Pathfinder.pathCost(board: coord.boardState, from: from, to: to, canOpenDoors: true)
        }
        let free = coord.boardState.cells.keys.sorted().filter(coord.isEmptyHex)
        let altar = try XCTUnwrap(free.filter { steps(start, $0) != nil }.max { steps(start, $0)! < steps(start, $1)! })
        let before = try XCTUnwrap(steps(start, altar))
        XCTAssertGreaterThan(before, 2)
        coord.boardState.markerHexes["b"] = [altar]
        XCTAssertEqual(controller.destination(of: container), [altar])

        let result = EscortAI.computeTurn(escort: container, entity: hail, board: coord.boardState, gameState: sim.gm.game,
                                          destination: [altar])
        let end = try XCTUnwrap(result.movementPath.last, "it moves")
        XCTAssertLessThanOrEqual(result.movementPath.count - 1, 2, "Move 2")
        XCTAssertLessThan(try XCTUnwrap(steps(end, altar)), before, "toward b")
        XCTAssertNil(result.attackTarget)
    }

    /// With an enemy barring the only way, an escort still comes as near as it can.
    func testABlockedEscortComesAsNearAsItCan() {
        let (game, board) = makeGameState(characterPos: HexCoord(0, 5), monsterPositions: [(1, HexCoord(3, 0))])
        // A corridor one hex wide: the monster stands in it.
        board.cells = board.cells.filter { $0.key.row == 0 || $0.key.row == 5 }
        let container = GameObjectiveContainer(name: "Hail", edition: "gh", title: "Hail", escort: true)
        container.escortActions = [ActionModel(type: .move, value: .int(2))]
        let hail = GameObjectiveEntity(number: 1, health: 6, maxHealth: 6)
        container.entities = [hail]
        game.figures.append(.objective(container))
        board.placePiece(.objective(id: 1), at: HexCoord(0, 0))

        let result = EscortAI.computeTurn(escort: container, entity: hail, board: board, gameState: game,
                                          destination: [HexCoord(6, 0)])
        XCTAssertEqual(result.movementPath, [HexCoord(0, 0), HexCoord(1, 0), HexCoord(2, 0)], "up to the monster")
    }

    /// An escort takes a turn each round; an altar or a door takes none.
    func testOnlyEscortsTakeTurns() async throws {
        let sim = try simulator("29")
        await sim.play(rounds: 1)
        XCTAssertFalse(sim.coord.turnOrder.contains { if case .objective = $0.figure { return true }; return false },
                       "a barred door is in no turn order")
        XCTAssertFalse(sim.transcript.contains { $0.contains("Door 99") })
    }

    // MARK: - What the book asks of the objectives

    private func revealAll(_ sim: ScenarioSimulator) {
        while let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) { sim.coord.openDoor(at: door.coord) }
    }

    /// Temple of the Elements is won by destroying all four altars, whatever is still alive.
    func testDestroyingEveryAltarWins() async throws {
        let sim = try simulator("22")
        let coord = sim.coord
        await sim.play(rounds: 1)
        XCTAssertEqual(ScenarioBrief.make(for: try XCTUnwrap(sim.gm.game.scenario?.data), labels: sim.gm.editionStore).goal,
                       "Destroy all altars.")
        revealAll(sim)
        let altars = objectives(sim)
        XCTAssertEqual(altars.count, 4)
        for altar in altars.dropLast() { coord.sufferDamage(99, to: altar) }
        XCTAssertNil(coord.pendingResult, "one altar stands")
        coord.sufferDamage(99, to: altars[3])
        XCTAssertEqual(coord.pendingResult, .victory)
        XCTAssertEqual(coord.endReason, .goalMet("Destroy all altars."))
        XCTAssertTrue(sim.gm.game.monsters.contains { !$0.aliveEntities.isEmpty }, "with enemies still alive")
    }

    /// With the altars standing, killing every enemy doesn't win it.
    func testKillingEveryEnemyIsNotTheGoalThere() async throws {
        let sim = try simulator("22")
        let coord = sim.coord
        await sim.play(rounds: 1)
        revealAll(sim)
        for piece in coord.boardState.piecePositions.keys.sorted() {
            if case .monster = piece { coord.sufferDamage(999, to: piece) }
        }
        coord.checkVictoryDefeat()
        XCTAssertNil(coord.pendingResult)
    }

    /// Ruinous Rift is lost the moment Hail is killed; she starts on her lettered hex and the
    /// demons come for her.
    func testLosingTheEscortLosesTheScenario() async throws {
        let sim = try simulator("27")
        let coord = sim.coord
        let hail = try XCTUnwrap(objectives(sim).first, "Hail is on the board")
        XCTAssertEqual(coord.name(hail), "Hail")
        XCTAssertTrue(coord.isPlayerSide(hail))
        XCTAssertTrue(ScenarioBrief.make(for: try XCTUnwrap(sim.gm.game.scenario?.data), labels: sim.gm.editionStore)
            .defeat.contains("Hail is killed."))
        await sim.play(rounds: 1)
        coord.sufferDamage(99, to: hail)
        XCTAssertEqual(coord.pendingResult, .defeat)
        XCTAssertEqual(coord.endReason, .ruleLost("Hail is killed."))
    }

    /// Forgotten Crypt: Hail walks for the altar, and the scenario is won when she ends a turn
    /// beside it.
    func testAnEscortArrivingWins() async throws {
        let sim = try simulator("19")
        let coord = sim.coord
        await sim.play(rounds: 1)
        let hail = try XCTUnwrap(objectives(sim).first)
        revealAll(sim)
        let altar = try XCTUnwrap(coord.boardState.markerHexes["b"]?.first)
        let beside = try XCTUnwrap(altar.neighbors.first(where: coord.isEmptyHex))
        coord.noteEscortArrival(hail)
        XCTAssertNil(coord.pendingResult, "not there yet")
        coord.boardState.movePiece(hail, to: beside)
        coord.noteEscortArrival(hail)
        XCTAssertEqual(coord.pendingResult, .victory)
        XCTAssertNil(coord.boardState.piecePositions[hail])
        // Even with a place free for her kind, she isn't set out again.
        let free = try XCTUnwrap(coord.boardState.cells.keys.sorted().first(where: coord.isEmptyHex))
        coord.boardState.openObjectiveSlots.append(ObjectiveSlot(objective: 1, coord: free, cells: [free]))
        coord.placeRevealedObjectives()
        XCTAssertNil(coord.boardState.piecePositions[hail])
    }

    /// Overgrown Graveyard: what a dug-up grave lets out appears where the grave was.
    func testWhatAGraveLetsOutAppearsWhereItStood() async throws {
        let sim = try simulator("75")
        let coord = sim.coord
        await sim.play(rounds: 1)
        let grave = try XCTUnwrap(objectives(sim).first { (coord.entity(for: $0) as? GameObjectiveEntity)?.marker == "a" })
        let hex = try XCTUnwrap(coord.boardState.piecePositions[grave])
        let before = Set(coord.boardState.piecePositions.keys)
        coord.sufferDamage(99, to: grave)
        let risen = Set(coord.boardState.piecePositions.keys).subtracting(before)
        XCTAssertEqual(risen.count, 1, "a Living Corpse rises")
        XCTAssertEqual(risen.first.flatMap { coord.boardState.piecePositions[$0] }, hex, "from the grave")
    }

    /// Tribal Assault's captives are the monsters' to attack and no one's to heal or hit.
    func testCaptivesAreAttackedOnlyByMonsters() throws {
        let sim = try simulator("44")
        let coord = sim.coord
        let captive = try XCTUnwrap(objectives(sim).first { coord.name($0).hasPrefix("Captive Orchid") })
        let redthorn = try XCTUnwrap(objectives(sim).first { coord.name($0) == "Redthorn" })
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        XCTAssertFalse(coord.areEnemies(brute, captive))
        XCTAssertFalse(coord.areAllies(brute, captive), "not an ally: no heals, no buffs")
        XCTAssertTrue(coord.areAllies(brute, redthorn))
        let inox = try XCTUnwrap(sim.gm.game.monsters.first { !$0.aliveEntities.isEmpty })
        let targets = MonsterAI.gatherEnemies(board: coord.boardState, monster: inox, gameState: sim.gm.game)
        XCTAssertTrue(targets.contains(captive))
        XCTAssertTrue(targets.contains(redthorn))
    }

    // MARK: - Saving

    /// A save keeps where objectives stand, the lettered hexes and what an escort does.
    func testASaveKeepsObjectivesAndMarkers() throws {
        let sim = try simulator("29")
        let board = sim.coord.boardState
        board.markerHexes["c"] = [HexCoord(1, 1)]
        let data = try JSONEncoder().encode(BoardSnapshot.from(board))
        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: data).restore(to: restored)
        XCTAssertEqual(restored.objectiveSites, board.objectiveSites)
        XCTAssertEqual(restored.objectiveSites.count, 3)
        XCTAssertEqual(restored.markerHexes, ["c": [HexCoord(1, 1)]])

        let container = GameObjectiveContainer(name: "Hail", edition: "gh", title: "Hail", escort: true)
        container.escortActions = [ActionModel(type: .move, value: .int(2))]
        container.useAllyDeck = true
        container.objectiveIndex = 1
        let saved = try JSONDecoder().decode(ObjectiveContainerSnapshot.self, from: JSONEncoder().encode(container.toSnapshot())).toRuntime()
        XCTAssertEqual(saved.escortMove, 2)
        XCTAssertTrue(saved.useAllyDeck)
        XCTAssertEqual(saved.objectiveIndex, 1)
    }

    // MARK: - Writing placements

    /// A sheet for writing a scenario's placements from the scenario book: its whole map with
    /// every hex labelled by its tile and tile coordinates (what `placements/gh.json` is written
    /// in), and the objectives and lettered hexes already written drawn in.
    /// `PLACEMENT_SHEET=19 PLACEMENT_SHEET_OUT=/tmp/s19.png swift test --filter testRenderPlacementSheet`
    /// `PLACEMENT_SHEET_TURN=90` turns the map a quarter clockwise, for a scenario the book prints turned.
    func testRenderPlacementSheet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let index = env["PLACEMENT_SHEET"], let out = env["PLACEMENT_SHEET_OUT"] else {
            throw XCTSkip("set PLACEMENT_SHEET and PLACEMENT_SHEET_OUT to render a sheet")
        }
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        // Every room: doors opened, barred ones broken down.
        for _ in 0..<40 {
            guard let door = coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
            if let barring = coord.boardState.objectiveSites.first(where: { $0.value.barsDoor && $0.value.coord == door.coord }) {
                coord.handleDeath(of: .objective(id: barring.key))
            } else {
                coord.openDoor(at: door.coord)
            }
        }
        let scene = try XCTUnwrap(coord.boardScene)
        let map = try XCTUnwrap(coord.scenarioData)
        // Turning the camera one way turns the map the other; labels turn with the camera to stay upright.
        let turn = CGFloat(Double(env["PLACEMENT_SHEET_TURN"] ?? "0") ?? 0) * .pi / 180

        func label(_ text: String, at hex: HexCoord, color: SKColor, size: CGFloat, dy: CGFloat) {
            let node = SKLabelNode(fontNamed: "Helvetica-Bold")
            node.text = text
            node.fontSize = size
            node.fontColor = color
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            let center = scene.sceneCenter(of: hex)
            node.position = CGPoint(x: center.x - dy * sin(turn), y: center.y + dy * cos(turn))
            node.zRotation = turn
            node.zPosition = 1000
            let plate = SKShapeNode(rectOf: CGSize(width: node.frame.width + 4, height: size + 2), cornerRadius: 2)
            plate.fillColor = SKColor(white: 0, alpha: 0.7)
            plate.strokeColor = .clear
            plate.position = node.position
            plate.zRotation = turn
            plate.zPosition = 999
            scene.addChild(plate)
            scene.addChild(node)
        }

        var labelled: Set<HexCoord> = []
        for placement in BoardBuilder.findPlacements(in: map.mapTileData) {
            let tile = placement.tile
            let axis = placement.axis
            func global(_ x: Int, _ y: Int) -> HexCoord {
                let point = HexMath.normaliseAndRotatePoint(turns: tile.turns, refPoint: axis?.refPoint ?? (0, 0),
                                                            origin: axis?.origin ?? (0, 0), tileCoord: (x, y))
                return HexCoord(point.0, point.1)
            }
            var cells: [(Int, Int)] = []
            for (y, row) in TileGrids.grid(for: tile.ref).enumerated() {
                for (x, exists) in row.enumerated() where exists { cells.append((x, y)) }
            }
            cells += tile.overlays.flatMap { $0.cells.filter { $0.count >= 2 }.map { ($0[0], $0[1]) } }
            cells += tile.monsters.map { ($0.initialX, $0.initialY) }
            cells += tile.doors.map { ($0.room1X, $0.room1Y) }
            var named = false
            for (x, y) in cells {
                let hex = global(x, y)
                guard coord.boardState.cells[hex] != nil, labelled.insert(hex).inserted else { continue }
                label("\(x),\(y)", at: hex, color: .white, size: 11, dy: -22)
                if !named { label(tile.ref, at: hex, color: .yellow, size: 11, dy: -34); named = true }
            }
        }
        for (marker, hexes) in coord.boardState.markerHexes {
            for hex in hexes { label(marker, at: hex, color: .red, size: 22, dy: 6) }
        }
        for slot in coord.boardState.openObjectiveSlots { label("obj \(slot.objective)", at: slot.coord, color: .cyan, size: 13, dy: 8) }
        for (number, site) in coord.boardState.objectiveSites { label("#\(number)", at: site.coord, color: .cyan, size: 13, dy: 22) }

        let view = SKView(frame: CGRect(x: 0, y: 0, width: 2200, height: 1700))
        view.presentScene(scene)
        scene.camera?.setScale(1.6)
        scene.camera?.zRotation = turn
        let texture = try XCTUnwrap(view.texture(from: scene))
        let rep = NSBitmapImageRep(cgImage: texture.cgImage())
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: out))
    }
}
