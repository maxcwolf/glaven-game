import XCTest
@testable import GlavenGameLib

/// A boss on all the hexes of an obstacle, flying from one to the next, and its untouchable
/// summons (`ScenarioPlacements.Perch`, `BoardCoordinator+Perch`): the Elder Drake of the
/// Scorched Summit and its Zephyrs (#34).
@MainActor
final class PerchTests: XCTestCase {

    private func simulator() throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "34", options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        // Only the Elder Drake is left.
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster(let name, _) = piece, name != "elder-drake" { sim.coord.sufferDamage(999, to: piece) }
        }
        return sim
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func drake(_ sim: ScenarioSimulator) throws -> PieceID { try XCTUnwrap(sim.coord.perchedBoss()) }

    private func play(_ sim: ScenarioSimulator, card matches: (AbilityModel) -> Bool) async throws {
        let boss = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "elder-drake" })
        let deck = sim.gm.monsterManager.abilities(for: boss)
        let card = try XCTUnwrap(deck.firstIndex(where: matches), "no such card")
        boss.abilities = [card]
        boss.ability = 0
        boss.abilityDrawn = true
        sim.gm.game.state = .next
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(boss)
    }

    private func special(_ number: Int) -> (AbilityModel) -> Bool {
        { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == number } }
    }

    private func floor(_ sim: ScenarioSimulator, where test: (HexCoord) -> Bool) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { board.isPassable($0) && board.cells[$0]?.overlay == nil && board.piece(at: $0) == nil && test($0) })
    }

    /// "The Elder Drake occupies all three hexes of the obstacle it is on. If a figure can target
    /// any one of these hexes, they can target the Elder Drake."
    func testTheElderDrakeSitsOnAllThreeHexesOfItsBoulder() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let boss = try drake(sim)
        let perch = Set(coord.boardState.markerHexes["c"] ?? [])
        XCTAssertEqual(perch.count, 3)
        XCTAssertEqual(Set(coord.boardState.hexes(of: boss)), perch, "set up on the top boulder")
        XCTAssertTrue(perch.allSatisfy { coord.boardState.cells[$0]?.overlay == .obstacle && coord.boardState.piece(at: $0) == boss })
        XCTAssertEqual(coord.perchLetter(of: boss), "c")

        // Beside each of its hexes in turn the Brute can reach it with a melee attack.
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        let full = try XCTUnwrap(coord.entity(for: boss)).health
        var struck = 0
        for hex in perch.sorted() {
            guard let beside = coord.boardState.neighbors(of: hex).sorted().first(where: { place in
                coord.boardState.isPassable(place) && coord.boardState.piece(at: place) == nil
                    && perch.filter { coord.boardState.areAdjacent($0, place) } == [hex]
            }) else { continue }
            stand(sim, brute, on: beside)
            XCTAssertTrue(coord.targetableEnemies(of: brute, range: 1).contains(boss), "from beside \(hex)")
            _ = await coord.performAttack(attacker: brute, target: boss, attack: AttackParameters(value: 2),
                                          drawCard: { AttackModifier(type: .plus0, value: 0) })
            struck += 1
            XCTAssertEqual(coord.entity(for: boss)?.health, full - 2 * struck)
        }
        XCTAssertGreaterThanOrEqual(struck, 2, "more than one of its hexes can be stood beside alone")
        // Two hexes off every one of them: out of reach.
        stand(sim, brute, on: try floor(sim) { place in perch.allSatisfy { coord.boardState.range(from: place, to: $0) == 2 } || perch.map { coord.boardState.range(from: place, to: $0) ?? 9 }.min() == 2 })
        XCTAssertFalse(coord.targetableEnemies(of: brute, range: 1).contains(boss))

        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(coord.boardState))).restore(to: restored)
        XCTAssertEqual(restored.bodies, coord.boardState.bodies)
    }

    /// "…and the Elder Drake can use any of its hexes to determine what it can target."
    func testTheElderDrakeAttacksFromAnyOfItsHexes() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let boss = try drake(sim)
        let perch = coord.boardState.hexes(of: boss).sorted()
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        let brute = sim.gm.game.characters[0]
        var attackedFrom = Set<HexCoord>()
        for hex in perch {
            guard let beside = coord.boardState.neighbors(of: hex).sorted().first(where: { place in
                coord.boardState.isPassable(place) && coord.boardState.piece(at: place) == nil
                    && perch.filter { coord.boardState.areAdjacent($0, place) } == [hex]
            }) else { continue }
            stand(sim, .character(brute.id), on: beside)
            brute.health = brute.maxHealth
            let lines = coord.turnLog.count
            try await play(sim) { card in
                let actions = MonsterAbility.flattened(card.actions ?? [])
                return actions.contains { $0.type == .attack } && !actions.contains { $0.type == .special }
            }
            if coord.turnLog.dropFirst(lines).contains(where: { $0.message.contains("attacks Brute") }) { attackedFrom.insert(hex) }
        }
        XCTAssertGreaterThanOrEqual(attackedFrom.count, 2, "it reached the Brute from more than one of its hexes: \(attackedFrom)")
    }

    /// Its first special is an area attack whose three grey hexes are its body: it lies only the
    /// ways that put them on the boulder, not turned any way round one hex.
    func testTheAreaOfItsFirstSpecialLiesAsItsBodyDoes() throws {
        let sim = try simulator()
        let coord = sim.coord
        let boss = try drake(sim)
        let stat = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "elder-drake" }?.stat(for: .boss))
        let pattern = try XCTUnwrap(stat.special?.first?.first { $0.type == .attack }?.subActions?.first { $0.type == .area }?.value?.stringValue)
        XCTAssertEqual(AoEResolver.parsePattern(pattern).filter(\.isActive).count, 3)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        let anchor = try XCTUnwrap(coord.boardState.piecePositions[boss])
        func covered() -> Set<HexCoord> {
            var hexes = Set<HexCoord>()
            for hex in coord.boardState.cells.keys.sorted() where coord.boardState.isPassable(hex) && (coord.boardState.range(from: anchor, to: hex) ?? 9) <= 5 {
                stand(sim, brute, on: hex)
                if !AoEResolver.resolveTargets(pattern: pattern, attackerPos: anchor, focusTarget: brute, enemies: [brute], board: coord.boardState).isEmpty {
                    hexes.insert(hex)
                }
            }
            return hexes
        }
        let fixed = covered()
        XCTAssertFalse(fixed.isEmpty, "someone in front of it is in the area")
        XCTAssertLessThanOrEqual(fixed.count, 14, "the seven red hexes, and their mirror image")
        // The same pattern from a figure of one hex could be turned any of six ways.
        let body = coord.boardState.bodies.removeValue(forKey: boss)
        XCTAssertGreaterThan(covered().count, fixed.count)
        coord.boardState.bodies[boss] = body
    }

    /// "The Elder Drake summons two Zephyrs …, then flies to the next perch of boulders in the
    /// order of a, b, c, and then back to a."
    func testItsSecondSpecialSummonsTwoZephyrsAndTakesItToTheNextPerch() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let boss = try drake(sim)
        func zephyrs() -> [PieceID] { coord.boardState.piecePositions.keys.filter { if case .monster("zephyr", _) = $0 { return true }; return false }.sorted() }
        var summonedSoFar = 0
        for letter in ["a", "b", "c", "a"] {
            let from = Set(coord.boardState.hexes(of: boss))
            let already = Set(zephyrs())
            try await play(sim, card: special(2))
            XCTAssertEqual(coord.perchLetter(of: boss), letter)
            XCTAssertEqual(Set(coord.boardState.hexes(of: boss)), Set(coord.boardState.markerHexes[letter] ?? []), "all three hexes of (\(letter))")
            XCTAssertTrue(from.allSatisfy { coord.boardState.piece(at: $0) == nil }, "it has left the last perch")
            summonedSoFar += 2
            XCTAssertEqual(zephyrs().count, summonedSoFar, "two more Zephyrs")
            // Summoned before it flew: beside the perch it left.
            let new = zephyrs().filter { !already.contains($0) }
            XCTAssertTrue(new.allSatisfy { (coord.entity(for: $0) as? GameMonsterEntity)?.summonState == .new })
            for zephyr in new {
                let hex = try XCTUnwrap(coord.boardState.piecePositions[zephyr])
                XCTAssertLessThanOrEqual(from.compactMap { coord.boardState.range(from: hex, to: $0) }.min() ?? 9, 2, "\(zephyr) beside the perch it was summoned from")
            }
        }
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })
    }

    /// "Zephyrs cannot be damaged in any way. They perform 'Move 2, Attack C' immediately before
    /// the Elder Drake's turn every round." Nothing affects them and no summon goes for them.
    func testZephyrsAreUntouchableAndActBeforeTheElderDrake() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let boss = try drake(sim)
        try await play(sim, card: special(2))
        let zephyrs = coord.boardState.piecePositions.keys.filter { if case .monster("zephyr", _) = $0 { return true }; return false }.sorted()
        XCTAssertEqual(zephyrs.count, 2)
        XCTAssertTrue(MonsterAI.idleMonsters(sim.gm.game).contains("zephyr"), "no turn or card of their own")
        let brute = sim.gm.game.characters[0]
        let zephyr = zephyrs[0]
        coord.removePieceFromBoard(zephyrs[1])
        (coord.entity(for: zephyrs[1]) as? GameMonsterEntity)?.dead = true
        // Untouchable.
        XCTAssertFalse(coord.areEnemies(.character(brute.id), zephyr))
        XCTAssertFalse(coord.sufferDamage(9, to: zephyr))
        XCTAssertNotNil(coord.boardState.piecePositions[zephyr])
        coord.applyCondition(.stun, to: zephyr)
        XCTAssertTrue(coord.entity(for: zephyr)?.entityConditions.isEmpty ?? false)
        XCTAssertFalse(PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: false).contains(zephyr))
        XCTAssertTrue(PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: false).contains(boss))

        // Just summoned, it waits; next round it moves 2 and attacks before the drake does.
        coord.boardState.removePiece(.character(sim.gm.game.characters[1].id))
        let start = try XCTUnwrap(coord.boardState.piecePositions[zephyr])
        stand(sim, .character(brute.id), on: try floor(sim) { place in
            coord.boardState.range(from: place, to: start) == 3
                && coord.boardState.hexes(of: boss).allSatisfy { perch in (coord.boardState.range(from: place, to: perch) ?? 0) > 3 }
        })
        var lines = coord.turnLog.count
        try await play(sim, card: special(1))
        XCTAssertEqual(coord.boardState.piecePositions[zephyr], start, "summoned this round: it doesn't act")
        (coord.entity(for: zephyr) as? GameMonsterEntity)?.summonState = .active
        lines = coord.turnLog.count
        try await play(sim, card: special(1))
        let after = try XCTUnwrap(coord.boardState.piecePositions[zephyr])
        XCTAssertTrue(coord.boardState.areAdjacent(after, try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])), "Move 2 to the Brute's side")
        let said = coord.turnLog.dropFirst(lines).map(\.message)
        let attack = try XCTUnwrap(said.firstIndex { $0.hasPrefix("Zephyr") && $0.contains("attacks Brute") }, "\(said)")
        let bossTurn = try XCTUnwrap(said.firstIndex { $0.contains("Elder Drake") && $0.contains("special ability") })
        XCTAssertLessThan(attack, bossTurn, "before the Elder Drake acts")
        XCTAssertTrue(said[attack].contains("\(sim.gm.game.characterCount)"), "Attack C: \(said[attack])")
    }
}
