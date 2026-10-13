import XCTest
@testable import GlavenGameLib

/// Things a character carries through a scenario (`ScenarioPlacements.carried`): who holds it,
/// how it changes hands, where it goes when its holder is exhausted, and what it does — the doll
/// of the Well of the Unfortunate (#69) and the Lurker King's claw (#88).
@MainActor
final class CarriedThingTests: XCTestCase {

    private func simulator(_ index: String, prompts: Bool = false) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: !prompts))
        sim.gm.game.round = 1
        return sim
    }

    private func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<40 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            sim.coord.openDoor(at: door.coord)
        }
    }

    private func monsters(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
    }

    private func piece(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != piece(sim, index) { board.removePiece(other) }
        board.removePiece(piece(sim, index))
        board.placePiece(piece(sim, index), at: hex)
    }

    // MARK: - #69: the doll

    /// "Choose one character to hold the doll": the players are asked as the scenario starts
    /// (with no one to ask, the first character holds it).
    func testThePlayersChooseWhoHoldsTheDoll() async throws {
        let headless = try simulator("69")
        XCTAssertEqual(headless.coord.holder(of: "doll")?.id, headless.gm.game.characters[0].id)

        let sim = try simulator("69", prompts: true)
        let coord = sim.coord
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingFigureChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        let asked = try XCTUnwrap(coord.pendingFigureChoice, "who holds the doll?")
        XCTAssertEqual(asked.title, "The doll")
        XCTAssertEqual(Set(asked.options), [piece(sim, 0), piece(sim, 1)])
        XCTAssertNil(asked.declineTitle, "someone must")
        XCTAssertNil(coord.holder(of: "doll"))
        coord.resolveFigureChoice(piece(sim, 1))
        while coord.holder(of: "doll") == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertEqual(coord.holder(of: "doll")?.id, sim.gm.game.characters[1].id)
        XCTAssertEqual(coord.carried(by: sim.gm.game.characters[1].id).map(\.name), ["doll"])
    }

    /// "Bring the doll to the well": a hex beside the well entered by the doll's holder wins;
    /// entered by anyone else it doesn't.
    func testOnlyTheDollsHolderWinsAtTheWell() async throws {
        let sim = try simulator("69")
        let coord = sim.coord
        revealAll(sim)
        for monster in monsters(sim) { coord.removePieceFromBoard(monster) }
        let well = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first)
        func away(_ hex: HexCoord) -> [HexCoord] { hex.neighbors.sorted().filter { coord.isEmptyHex($0) && $0.distance(to: well) == 2 } }
        let beside = try XCTUnwrap(well.neighbors.sorted().first { coord.isEmptyHex($0) && away($0).count >= 2 })
        let before = away(beside)[0], after = away(beside)[1]
        XCTAssertEqual(coord.holder(of: "doll")?.id, sim.gm.game.characters[0].id)

        stand(sim, 1, on: before)
        _ = await coord.moveAlong(piece(sim, 1), path: [before, beside], style: .normal)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.scenarioResult ?? coord.pendingResult, "the Spellweaver hasn't the doll")

        stand(sim, 1, on: after)
        stand(sim, 0, on: before)
        _ = await coord.moveAlong(piece(sim, 0), path: [before, beside], style: .normal)
        XCTAssertEqual(coord.scenarioResult ?? coord.pendingResult, .victory, "the Brute has")
    }

    /// "The doll changes hands only when another character performs a Loot action with the
    /// doll's holder within the loot range" — not by ending a turn beside them. A Loot with only
    /// the holder in range is a Loot performed.
    func testTheDollChangesHandsByALootAction() throws {
        let sim = try simulator("69")
        let coord = sim.coord
        for monster in monsters(sim) { coord.removePieceFromBoard(monster) }
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        let here = try XCTUnwrap(coord.boardState.piecePositions[piece(sim, 0)])
        let free = coord.boardState.cells.keys.filter(coord.isEmptyHex).sorted { ($0.distance(to: here), $0) < ($1.distance(to: here), $1) }
        stand(sim, 1, on: try XCTUnwrap(free.first { coord.boardState.range(from: here, to: $0) == 3 }))
        XCTAssertFalse(coord.collectLootInRange(pieceID: piece(sim, 1), range: 2), "the holder is out of range: nothing to loot")
        XCTAssertEqual(coord.holder(of: "doll")?.id, brute.id)

        stand(sim, 1, on: try XCTUnwrap(free.first { coord.boardState.areAdjacent(here, $0) }))
        coord.lootAtEndOfTurn(spellweaver.id)
        XCTAssertEqual(coord.holder(of: "doll")?.id, brute.id, "ending a turn beside the holder isn't a Loot action")
        XCTAssertTrue(coord.collectLootInRange(pieceID: piece(sim, 1), range: 1), "the Loot is performed")
        XCTAssertEqual(coord.holder(of: "doll")?.id, spellweaver.id)
        XCTAssertTrue(coord.carried(by: brute.id).isEmpty)
        XCTAssertFalse(coord.collectLootInRange(pieceID: piece(sim, 1), range: 1), "she has it: nothing more to take")
    }

    /// "If the character holding the doll becomes exhausted, the treasure tile is placed in the
    /// hex that character occupied": it lies there, is drawn there, and whoever loots that hex
    /// (ending a turn on it will do) holds it. Where it lies is saved with the board.
    func testAnExhaustedHoldersDollLiesWhereTheyStood() throws {
        let sim = try simulator("69")
        let coord = sim.coord
        for monster in monsters(sim) { coord.removePieceFromBoard(monster) }
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        let stood = try XCTUnwrap(coord.boardState.piecePositions[piece(sim, 0)])
        coord.sufferDamage(999, to: piece(sim, 0))
        XCTAssertTrue(brute.exhausted)
        XCTAssertNil(coord.holder(of: "doll"))
        XCTAssertEqual(coord.boardState.carriedLying, ["doll": stood])

        let restored = BoardState()
        try JSONDecoder().decode(BoardSnapshot.self, from: JSONEncoder().encode(BoardSnapshot.from(coord.boardState))).restore(to: restored)
        XCTAssertEqual(restored.carriedLying, ["doll": stood])

        stand(sim, 1, on: stood)
        coord.lootAtEndOfTurn(spellweaver.id)
        XCTAssertEqual(coord.holder(of: "doll")?.id, spellweaver.id)
        XCTAssertTrue(coord.boardState.carriedLying.isEmpty)
    }

    // MARK: - #88: the claw

    /// "When it dies it drops a claw (a treasure tile) instead of a money token. A character
    /// holding the claw has −2 Move on all their Move abilities" (on top of the scenario's −1).
    func testTheLurkerKingDropsHisClawAndItWeighsItsHolderDown() throws {
        let sim = try simulator("88")
        let coord = sim.coord
        revealAll(sim)
        let king = try XCTUnwrap(monsters(sim).first { if case .monster("lurker-king", _) = $0 { return true }; return false }, "the King")
        let lair = try XCTUnwrap(coord.boardState.piecePositions[king])
        XCTAssertTrue(coord.boardState.carriedLying.isEmpty && coord.boardState.carriedBy.isEmpty)
        coord.sufferDamage(999, to: king)
        XCTAssertEqual(coord.boardState.carriedLying, ["claw": lair])
        XCTAssertEqual(coord.boardState.lootTokens[lair] ?? 0, 0, "instead of a money token")

        XCTAssertEqual(coord.scenarioMoveBonus(of: piece(sim, 0)), -1)
        stand(sim, 0, on: lair)
        coord.lootAtEndOfTurn(sim.gm.game.characters[0].id)
        XCTAssertEqual(coord.holder(of: "claw")?.id, sim.gm.game.characters[0].id)
        XCTAssertEqual(coord.scenarioMoveBonus(of: piece(sim, 0)), -3, "the claw's −2 with the scenario's −1")
        XCTAssertEqual(coord.scenarioMoveBonus(of: piece(sim, 1)), -1)
    }

    /// "Bring the Lurker King's claw to the crystal": the claw's holder ends a turn beside it.
    func testTheClawsHolderBesideTheCrystalWins() throws {
        let sim = try simulator("88")
        let coord = sim.coord
        revealAll(sim)
        let king = try XCTUnwrap(monsters(sim).first { if case .monster("lurker-king", _) = $0 { return true }; return false })
        coord.sufferDamage(999, to: king)
        for monster in monsters(sim) { coord.removePieceFromBoard(monster) }
        let crystal = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first)
        let beside = coord.boardState.neighbors(of: crystal).sorted().filter { coord.boardState.isPassable($0) }
        XCTAssertGreaterThanOrEqual(beside.count, 2)
        stand(sim, 1, on: beside[0])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.scenarioResult ?? coord.pendingResult, "no one has the claw")
        coord.give("claw", to: sim.gm.game.characters[0].id, how: "picks up")
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.scenarioResult ?? coord.pendingResult, "its holder isn't beside the crystal")
        stand(sim, 0, on: beside[1])
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.scenarioResult ?? coord.pendingResult, .victory)
    }
}
