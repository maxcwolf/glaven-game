import XCTest
@testable import GlavenGameLib

/// Slave Pens (#38): the Orchid "performs Move 3 toward the shaman on the D tile, opening doors
/// and springing traps if needed" (`ScenarioPlacements.seeks`).
@MainActor
final class OrchidTests: XCTestCase {

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "38", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func orchid(_ sim: ScenarioSimulator) throws -> (container: GameObjectiveContainer, piece: PieceID) {
        let container = try XCTUnwrap(sim.gm.game.objectives.first { $0.escort })
        let entity = try XCTUnwrap(container.entities.first)
        return (container, .objective(id: entity.number))
    }

    private func shamans(_ sim: ScenarioSimulator, on tile: String) -> [PieceID] {
        sim.coord.boardState.piecePositions.filter { piece, hex in
            guard case .monster("inox-shaman", _) = piece else { return false }
            return sim.coord.boardState.cells[hex]?.tileRef.lowercased() == tile
        }.map(\.key).sorted()
    }

    private func turn(_ sim: ScenarioSimulator) async throws {
        let (container, _) = try orchid(sim)
        await EscortTurnController(coordinator: sim.coord, gameManager: sim.gm).executeEscortTurns(for: container)
    }

    /// Before the D tile is seen he makes for the doors on the way to it, and opens them.
    func testHeMakesForTheDoorsOnTheWayToTheDTile() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        for monster in coord.boardState.piecePositions.keys.sorted() {
            if case .monster = monster { coord.sufferDamage(999, to: monster, killer: .character(sim.gm.game.characters[0].id)) }
        }
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen })
        XCTAssertEqual(controller.destination(of: container, from: coord.boardState.piecePositions[piece]), [door.coord])
        var turns = 0
        while !coord.boardState.visibleRooms.contains(where: { $0.lowercased() == "a4a" }), turns < 6 {
            try await turn(sim)
            turns += 1
        }
        XCTAssertTrue(coord.boardState.visibleRooms.contains { $0.lowercased() == "a4a" }, "he walked into the door and opened it")
    }

    /// With the D tile in sight he heads for its shaman — not for a nearer enemy, nor the shaman
    /// of the M tile — and stops beside him.
    func testHeHeadsForTheShamanOnTheDTile() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        let target = try XCTUnwrap(shamans(sim, on: "d1b").first)
        XCTAssertFalse(shamans(sim, on: "m1b").isEmpty, "a shaman on the M tile too")
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        let goal = try XCTUnwrap(coord.boardState.piecePositions[target])
        XCTAssertEqual(controller.destination(of: container, from: coord.boardState.piecePositions[piece]), [goal])

        // Every other monster out of his way; none of them draws him.
        for monster in coord.boardState.piecePositions.keys.sorted() where monster != target {
            if case .monster = monster { coord.removePieceFromBoard(monster) }
        }
        var last = try XCTUnwrap(coord.boardState.piecePositions[piece])
        for _ in 0..<20 {
            try await turn(sim)
            let now = try XCTUnwrap(coord.boardState.piecePositions[piece])
            if now == last { break }
            XCTAssertLessThan(coord.boardState.steps(from: now, to: goal), coord.boardState.steps(from: last, to: goal), "each move nearer")
            XCTAssertLessThanOrEqual(last.distance(to: now), 3)
            last = now
        }
        XCTAssertTrue(coord.boardState.areAdjacent(last, goal), "he ends beside the shaman")
    }

    /// Once the D tile's shaman is dead he has nowhere to go: he stays.
    func testWithTheShamanDeadHeStays() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (container, piece) = try orchid(sim)
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        for shaman in shamans(sim, on: "d1b") { coord.sufferDamage(999, to: shaman, killer: .character(sim.gm.game.characters[0].id)) }
        let here = try XCTUnwrap(coord.boardState.piecePositions[piece])
        let controller = EscortTurnController(coordinator: coord, gameManager: sim.gm)
        XCTAssertEqual(controller.destination(of: container, from: here), [here])
        try await turn(sim)
        XCTAssertEqual(coord.boardState.piecePositions[piece], here)
    }
}

/// Toxic Moor (#68): the tree "can be healed like any normal ally, but no other ability can affect
/// it", and "a character summon that has POISON treats water hexes like traps".
@MainActor
final class ToxicMoorTests: XCTestCase {

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "68", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func tree(_ sim: ScenarioSimulator) throws -> (piece: PieceID, entity: GameObjectiveEntity) {
        let container = try XCTUnwrap(sim.gm.game.objectives.first { $0.name == "Tree" })
        let entity = try XCTUnwrap(container.entities.first)
        return (.objective(id: entity.number), entity)
    }

    private func water(_ sim: ScenarioSimulator) -> Set<HexCoord> {
        Set(sim.coord.boardState.cells.values.filter { $0.overlay == .difficultTerrain && $0.overlaySubType == "water" }.map(\.coord))
    }

    private func clearMonsters(_ sim: ScenarioSimulator, except kept: PieceID? = nil) {
        for piece in sim.coord.boardState.piecePositions.keys.sorted() where piece != kept {
            if case .monster = piece { sim.coord.boardState.removePiece(piece) }
        }
    }

    /// Healed like an ally once its room is seen; never strengthened, blessed or shielded.
    func testTheTreeIsHealedAndNothingElse() throws {
        let sim = try simulator()
        let coord = sim.coord
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        let (piece, entity) = try tree(sim)
        let at = try XCTUnwrap(coord.boardState.piecePositions[piece])
        clearMonsters(sim)
        let beside = try XCTUnwrap(coord.boardState.neighbors(of: at).sorted().first { coord.isEmptyHex($0) })
        coord.boardState.removePiece(brute)
        coord.boardState.placePiece(brute, at: beside)

        XCTAssertFalse(coord.alliesInRange(of: brute, range: 2, includeSelf: false).contains(piece), "no ally to a condition or a shield")
        XCTAssertTrue(coord.alliesInRange(of: brute, range: 2, includeSelf: false, healing: true).contains(piece), "an ally to a heal")
        coord.applyConditionToAllAllies(from: brute, condition: .strengthen, range: 2)
        XCTAssertTrue(entity.entityConditions.isEmpty, "Strengthen given to all allies doesn't land on it")
        XCTAssertFalse(coord.beginConditionAction(pieceID: brute, condition: .bless, range: 2, onAllies: true), "no ally to bless")

        coord.beginHealAction(pieceID: brute, healValue: 2, range: 2)
        guard case .selectingHealTarget(_, _, let targets) = coord.interactionMode else { return XCTFail("a heal to aim") }
        XCTAssertTrue(targets.contains(piece), "the tree can be chosen for a heal")

        // Before its room is seen, not even a heal reaches it.
        let tile = try XCTUnwrap(coord.boardState.cells[at]?.tileRef)
        coord.boardState.visibleRooms.remove(tile)
        XCTAssertFalse(coord.alliesInRange(of: brute, range: 2, includeSelf: false, healing: true).contains(piece))
    }

    /// "Heal 1, all adjacent allies" (Restorative Mist) heals the tree beside the Tinkerer.
    func testAHealForAllAdjacentAlliesHealsTheTree() throws {
        let sim = try ScenarioSimulator(scenario: "68", options: .init(characters: ["tinkerer", "brute"], seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        let coord = sim.coord
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        let (piece, entity) = try tree(sim)
        clearMonsters(sim)
        let tinkerer = sim.gm.game.characters[0]
        let me = PieceID.character(tinkerer.id)
        let at = try XCTUnwrap(coord.boardState.piecePositions[piece])
        let beside = try XCTUnwrap(coord.boardState.neighbors(of: at).sorted().first { coord.isEmptyHex($0) })
        coord.boardState.removePiece(me)
        coord.boardState.placePiece(me, at: beside)
        entity.health = entity.maxHealth - 3
        let deck = sim.gm.editionStore.abilities(forDeck: "tinkerer", edition: "gh")
        let top = try XCTUnwrap(deck.first { $0.name == "Hook Gun" }), bottom = try XCTUnwrap(deck.first { $0.name == "Restorative Mist" })
        tinkerer.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: tinkerer.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        turn.setBottomFirst(true)
        turn.skipCurrentAction()      // Move 2
        turn.executeCurrentAction()   // Heal 1, all adjacent allies
        XCTAssertEqual(entity.health, entity.maxHealth - 2)
    }

    /// A poisoned summon plans its move round the water, as it would round traps; unpoisoned it
    /// wades. Its turn leaves nothing behind for the next plan.
    func testAPoisonedSummonGoesRoundTheWater() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let board = coord.boardState
        coord.openScenarioRooms((sim.gm.game.scenario?.data.rooms ?? []).map(\.roomNumber))
        let brute = sim.gm.game.characters[0]
        let foe = try XCTUnwrap(board.piecePositions.keys.sorted().first { if case .monster = $0 { return true }; return false })
        clearMonsters(sim, except: foe)
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: 1, health: 20, maxHealth: 20, level: 1,
                                attack: .int(1), movement: 3, range: 0)
        summon.state = .active
        brute.summons.append(summon)
        let piece = PieceID.summon(id: summon.id)
        let wet = water(sim)
        XCTAssertFalse(wet.isEmpty)
        XCTAssertTrue(coord.waterAvoided(by: piece).isEmpty, "not poisoned")

        // Somewhere its shortest way to the enemy is through water, and another way is open.
        func plan(avoiding: Set<HexCoord>) -> [HexCoord] {
            board.avoidedAsTraps = avoiding
            defer { board.avoidedAsTraps = [] }
            return SummonAI.computeTurn(summon: summon, ownerCharacterID: brute.id, board: board, gameState: sim.gm.game).movementPath
        }
        let dry = board.cells.values.filter { $0.overlay == nil && $0.passable }.map(\.coord).sorted()
        var found: (start: HexCoord, enemy: HexCoord)?
        search: for start in dry where wet.contains(where: { board.areAdjacent($0, start) }) {
            for enemy in dry where enemy != start && board.range(from: start, to: enemy).map({ (3...5).contains($0) }) == true {
                board.removePiece(foe); board.placePiece(foe, at: enemy)
                board.removePiece(piece); board.placePiece(piece, at: start)
                let wading = plan(avoiding: [])
                let around = plan(avoiding: wet)
                if wading.contains(where: wet.contains), !around.isEmpty, !around.contains(where: wet.contains) {
                    found = (start, enemy)
                    break search
                }
            }
        }
        let (start, enemy) = try XCTUnwrap(found, "no place where the water is the short way")
        board.removePiece(foe); board.placePiece(foe, at: enemy)
        board.removePiece(piece); board.placePiece(piece, at: start)

        coord.applyCondition(.poison, to: piece)
        XCTAssertEqual(coord.waterAvoided(by: piece), wet)
        let health = summon.health
        await SummonTurnController(coordinator: coord, gameManager: sim.gm).executeSummonTurns(for: brute)
        XCTAssertTrue(board.avoidedAsTraps.isEmpty, "nothing is left for the next plan")
        let moved = try XCTUnwrap(board.piecePositions[piece])
        XCTAssertNotEqual(moved, start, "it moved")
        XCTAssertFalse(wet.contains(moved))
        XCTAssertEqual(summon.health, health, "no water entered, no trap damage (poison deals none of itself)")

        // Elsewhere — Cove, water and all — a poisoned summon wades as before.
        let cove = try ScenarioSimulator(scenario: "87", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let other = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: 1, health: 9, maxHealth: 9, level: 1,
                               attack: .int(1), movement: 3, range: 0)
        other.state = .active
        cove.gm.game.characters[0].summons.append(other)
        let spot = try XCTUnwrap(cove.coord.boardState.startingLocations.first { cove.coord.isEmptyHex($0) })
        cove.coord.boardState.placePiece(.summon(id: other.id), at: spot)
        cove.coord.applyCondition(.poison, to: .summon(id: other.id))
        XCTAssertTrue(cove.coord.waterAvoided(by: .summon(id: other.id)).isEmpty)
    }
}
