import XCTest
@testable import GlavenGameLib

/// Monsters set up asleep (`ScenarioPlacements.asleep`, `BoardCoordinator+Sleep`): the Spitting
/// Drakes of the Windswept Highlands (#71).
@MainActor
final class SleepingMonsterTests: XCTestCase {

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "71", options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func drakes(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .monster("spitting-drake", _) = $0 { return true }; return false }.sorted()
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    /// A drake on its own with open floor round it, every other monster off the board, and the
    /// characters out of the way.
    private func oneDrake(_ sim: ScenarioSimulator) throws -> (drake: PieceID, hex: HexCoord, beside: [HexCoord]) {
        let coord = sim.coord
        let drake = try XCTUnwrap(drakes(sim).first)
        for piece in coord.boardState.piecePositions.keys.sorted() where piece != drake {
            if case .monster = piece { coord.removePieceFromBoard(piece) }
        }
        let hex = try XCTUnwrap(coord.boardState.piecePositions[drake])
        let beside = coord.boardState.neighbors(of: hex).sorted().filter { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil }
        return (drake, hex, beside)
    }

    private func drawCard(_ sim: ScenarioSimulator) throws -> GameMonster {
        let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "spitting-drake" })
        if !monster.abilityDrawn { sim.gm.monsterManager.drawAbility(for: monster) }
        return monster
    }

    /// "The Spitting Drakes on the map are asleep and do not act until they are woken up."
    func testTheDrakesOfTheMapAreAsleepAndDoNothing() async throws {
        let sim = try simulator()
        let coord = sim.coord
        XCTAssertFalse(drakes(sim).isEmpty)
        for drake in drakes(sim) {
            XCTAssertTrue(coord.isAsleep(drake))
            XCTAssertTrue(coord.pieceAppearance(drake).badge?.hasSuffix("z") ?? false, "it shows")
        }
        // The other monsters aren't, and the drakes behind the doors are when their rooms open.
        coord.boardState.lockedDoors.removeAll()
        for _ in 0..<10 { if let door = coord.boardState.doors.first(where: { !$0.isOpen }) { coord.openDoor(at: door.coord) } }
        XCTAssertGreaterThan(drakes(sim).count, 1)
        XCTAssertEqual(coord.boardState.asleep, Set(drakes(sim)))

        // Its type's turn comes: a character two hexes off is neither approached nor attacked.
        let (drake, hex, beside) = try oneDrake(sim)
        let brute = sim.gm.game.characters[0]
        let near = try XCTUnwrap(beside.flatMap { coord.boardState.neighbors(of: $0) }.sorted()
            .first { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil && !coord.boardState.areAdjacent($0, hex) && $0 != hex })
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        stand(sim, .character(brute.id), on: near)
        let health = brute.health
        let monster = try drawCard(sim)
        await MonsterTurnController(coordinator: coord, gameManager: sim.gm).executeMonsterGroup(monster)
        XCTAssertEqual(coord.boardState.piecePositions[drake], hex)
        XCTAssertEqual(brute.health, health)
        XCTAssertTrue(coord.isAsleep(drake))

        // Awake, the same turn has it act.
        coord.wake(drake)
        XCTAssertFalse(coord.pieceAppearance(drake).badge?.hasSuffix("z") ?? true)
        await MonsterTurnController(coordinator: coord, gameManager: sim.gm).executeMonsterGroup(monster)
        XCTAssertTrue(coord.boardState.piecePositions[drake] != hex || brute.health < health, "it moved or attacked")

        let restored = BoardState()
        coord.boardState.asleep.insert(drake)
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(coord.boardState))).restore(to: restored)
        XCTAssertEqual(restored.asleep, [drake])
    }

    /// "…when any character or character summon attacks, damages, places any negative condition
    /// on, or ends any movement (including the forced movement at the end of the round) adjacent
    /// to the drake."
    func testWhatWakesADrake() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let (drake, hex, beside) = try oneDrake(sim)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        func sleepAgain() { coord.boardState.asleep.insert(drake) }
        let far = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { cell in
            coord.boardState.isPassable(cell) && coord.boardState.piece(at: cell) == nil && coord.boardState.steps(from: cell, to: hex) > 3
                && coord.boardState.steps(from: cell, to: hex) < 40
        })
        stand(sim, brute, on: far)

        // An attack, whatever comes of it.
        _ = await coord.performAttack(attacker: brute, target: drake, attack: AttackParameters(value: 1),
                                      drawCard: { AttackModifier(type: .null_, value: 0, valueType: .multiply) })
        XCTAssertEqual(coord.entity(for: drake)?.health, coord.entity(for: drake)?.maxHealth, "a miss")
        XCTAssertFalse(coord.isAsleep(drake), "attacked")
        // Damage.
        sleepAgain()
        coord.sufferDamage(1, to: drake)
        XCTAssertFalse(coord.isAsleep(drake), "damaged")
        // A negative condition — not a positive one.
        sleepAgain()
        coord.applyCondition(.strengthen, to: drake)
        XCTAssertTrue(coord.isAsleep(drake))
        coord.applyCondition(.muddle, to: drake)
        XCTAssertFalse(coord.isAsleep(drake), "muddled")

        // A movement that ends beside it; one that only passes by doesn't.
        sleepAgain()
        XCTAssertGreaterThanOrEqual(beside.count, 2)
        let passing = try XCTUnwrap(coord.boardState.neighbors(of: beside[0]).sorted()
            .first { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil && !coord.boardState.areAdjacent($0, hex) && $0 != hex })
        stand(sim, brute, on: passing)
        let on = try XCTUnwrap(coord.boardState.neighbors(of: passing).sorted()
            .first { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil && !coord.boardState.areAdjacent($0, hex) && $0 != hex })
        stand(sim, brute, on: on)
        _ = await coord.moveAlong(brute, path: [on, passing], style: .normal)
        XCTAssertTrue(coord.isAsleep(drake), "two hexes off isn't beside it")
        _ = await coord.moveAlong(brute, path: [passing, beside[0]], style: .normal)
        XCTAssertFalse(coord.isAsleep(drake), "a move ended beside it")
        // The wind's forced movement too.
        sleepAgain()
        stand(sim, brute, on: passing)
        _ = await coord.moveAlong(brute, path: [passing, beside[0]], style: .forced)
        XCTAssertFalse(coord.isAsleep(drake), "blown beside it")
        // A monster moving beside it doesn't.
        sleepAgain()
        coord.boardState.removePiece(brute)
        let demon = try XCTUnwrap(coord.spawnMonster(name: "wind-demon", type: .normal, at: passing, origin: .spawned))
        _ = await coord.moveAlong(demon, path: [passing, beside[0]], style: .normal)
        XCTAssertTrue(coord.isAsleep(drake))
    }

    /// "While a drake is asleep, character summons will not attack them unless directly
    /// controlled by a character."
    func testASummonLeavesASleepingDrakeAlone() throws {
        let sim = try simulator()
        let coord = sim.coord
        let (drake, _, beside) = try oneDrake(sim)
        let brute = sim.gm.game.characters[0]
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: 1, health: 5, maxHealth: 5, level: 1,
                                attack: .int(2), movement: 2, range: 0)
        summon.state = .active
        brute.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: beside[0])
        var turn = SummonAI.computeTurn(summon: summon, ownerCharacterID: brute.id, board: coord.boardState, gameState: sim.gm.game)
        XCTAssertTrue(turn.attackTargets.isEmpty, "\(turn.attackTargets)")
        XCTAssertTrue(PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: true).contains(drake),
                      "it is in the way all the same")
        coord.wake(drake)
        turn = SummonAI.computeTurn(summon: summon, ownerCharacterID: brute.id, board: coord.boardState, gameState: sim.gm.game)
        XCTAssertEqual(turn.attackTargets, [drake])
    }

    /// "When a drake awakes, follow the rules as if it has just been spawned": woken in a round's
    /// turns it acts that round — after the turn it woke in, when its type's place has gone by.
    func testAWokenDrakeActsInTheRoundItWakes() async throws {
        var wokenLate = 0, actedAfter = 0
        for seed in 1...6 {
            let sim = try ScenarioSimulator(scenario: "71", options: .init(characters: ["brute", "spellweaver"], seed: UInt64(seed)))
            _ = await sim.play(rounds: 8)
            XCTAssertTrue(sim.violations.isEmpty, "seed \(seed): \(sim.violations)")
            let lines = sim.transcript
            if let woke = lines.firstIndex(where: { $0.contains("Spitting Drake") && $0.contains("wakes up") }) {
                XCTAssertFalse(lines[..<woke].contains { $0.hasPrefix("Spitting Drake") && ($0.contains(" moves ") || $0.contains(" attacks ")) },
                               "seed \(seed): none acted while all were asleep")
            }
            // Round by round: a drake woken after the drakes' turn that round, and their turn again after it.
            var turnSeen = false, wokeAfterTurn = false
            for line in lines {
                if line.hasPrefix("=== Round") { turnSeen = false; wokeAfterTurn = false }
                if line.hasPrefix("Spitting Drake\u{2019}s turn") {
                    if wokeAfterTurn { actedAfter += 1; wokeAfterTurn = false }
                    turnSeen = true
                }
                if line.contains("Spitting Drake"), line.contains("wakes up"), turnSeen, !line.contains("wind") {
                    if !wokeAfterTurn { wokenLate += 1 }
                    wokeAfterTurn = true
                }
            }
        }
        XCTAssertGreaterThan(wokenLate, 0, "some drake is woken after its type's turn in these games")
        XCTAssertGreaterThan(actedAfter, 0, "and takes a turn that round")
    }
}
