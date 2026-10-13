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

    // MARK: - #58: the Occult Dagger

    /// "Only the character on the Vengeance quest may loot the treasure tile; looting it gives
    /// that character the Occult Dagger", whose holder "adds Pierce 4 to all their attacks that
    /// target the Harvester".
    func testOnlyTheVengeanceCharacterTakesTheDaggerAndItPiercesTheHarvester() async throws {
        let sim = try simulator("58")
        let coord = sim.coord
        revealAll(sim)
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        spellweaver.personalQuest = "526"
        let chest = try XCTUnwrap(coord.boardState.cells.values.first { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }?.coord)
        stand(sim, 0, on: chest)
        coord.lootAtEndOfTurn(brute.id)
        XCTAssertEqual(coord.boardState.cells[chest]?.overlay, .treasure, "the Brute isn't on the quest: the tile stays")
        XCTAssertNil(coord.holder(of: "Occult Dagger"))
        let free = try XCTUnwrap(coord.boardState.cells.keys.sorted().first(where: coord.isEmptyHex))
        stand(sim, 0, on: free)
        stand(sim, 1, on: chest)
        coord.lootAtEndOfTurn(spellweaver.id)
        XCTAssertEqual(coord.holder(of: "Occult Dagger")?.id, spellweaver.id)

        // Against the Harvester, with nothing else shielding it: Shield 4 is pierced by the
        // holder's attack and not by the Brute's. Against anyone else the dagger does nothing.
        for pile in coord.boardState.piecePositions.keys.sorted() { if case .objective = pile { coord.sufferDamage(999, to: pile) } }
        let harvester = try XCTUnwrap(monsters(sim).first { if case .monster("the-harvester", _) = $0 { return true }; return false })
        let boss = try XCTUnwrap(coord.entity(for: harvester))
        boss.shield = ActionModel(type: .shield, value: .int(4))
        boss.shieldPersistent = nil
        boss.maxHealth = 99
        boss.health = 99
        XCTAssertEqual(coord.carriedPierce(of: piece(sim, 1), against: harvester), 4)
        XCTAssertEqual(coord.carriedPierce(of: piece(sim, 0), against: harvester), 0)
        let other = try XCTUnwrap(monsters(sim).first { $0 != harvester })
        XCTAssertEqual(coord.carriedPierce(of: piece(sim, 1), against: other), 0)
        await coord.performAttack(attacker: piece(sim, 1), target: harvester, attack: AttackParameters(value: 3), drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(boss.health, 96, "Attack 3 through Shield 4, pierced")
        await coord.performAttack(attacker: piece(sim, 0), target: harvester, attack: AttackParameters(value: 3), drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(boss.health, 96, "the Brute's Attack 3 stops at the Shield")

        // The dagger doesn't change hands, whatever the Brute loots.
        coord.collectLootInRange(pieceID: piece(sim, 0), range: 99)
        XCTAssertEqual(coord.holder(of: "Occult Dagger")?.id, spellweaver.id)
    }

    /// With no one in the party on the quest (the scenario played for itself) anyone may loot it.
    func testWithNoOneOnTheQuestAnyoneTakesTheDagger() throws {
        let sim = try simulator("58")
        revealAll(sim)
        let chest = try XCTUnwrap(sim.coord.boardState.cells.values.first { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }?.coord)
        stand(sim, 0, on: chest)
        sim.coord.lootAtEndOfTurn(sim.gm.game.characters[0].id)
        XCTAssertEqual(sim.coord.holder(of: "Occult Dagger")?.id, sim.gm.game.characters[0].id)
    }

    // MARK: - #82: the artifacts

    /// Burning Mountain: whoever loots the chest holds its artifacts; it is their holder who
    /// sacrifices one on the altar hex, and "the scenario is lost if the character holding the
    /// items becomes exhausted" (FAQ).
    func testTheArtifactsHolderSacrificesOneOrLosesThemAll() throws {
        let sim = try simulator("82")
        let coord = sim.coord
        revealAll(sim)
        for monster in monsters(sim) { coord.removePieceFromBoard(monster) }
        let chest = try XCTUnwrap(coord.boardState.cells.values.first { $0.treasureID == "62" }?.coord)
        stand(sim, 1, on: chest)
        coord.lootAtEndOfTurn(sim.gm.game.characters[1].id)
        XCTAssertEqual(coord.holder(of: "artifacts")?.id, sim.gm.game.characters[1].id)
        // A Loot that reaches the holder's hex (a coin lies under her) takes the coin, not the artifacts.
        coord.boardState.placeLoot(at: chest)
        stand(sim, 0, on: try XCTUnwrap(coord.boardState.neighbors(of: chest).sorted()
            .first { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil }, "a hex beside the holder"))
        XCTAssertTrue(coord.collectLootInRange(pieceID: piece(sim, 0), range: 1))
        XCTAssertEqual(coord.boardState.lootTokens[chest] ?? 0, 0)
        XCTAssertEqual(coord.holder(of: "artifacts")?.id, sim.gm.game.characters[1].id, "they stay with their holder")

        // Their holder exhausted, with the Brute still standing: lost, and nothing left to pick up.
        coord.sufferDamage(999, to: piece(sim, 1))
        XCTAssertTrue(coord.boardState.carriedLying.isEmpty, "they don't lie to be picked up")
        XCTAssertFalse(sim.gm.game.characters[0].exhausted)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.scenarioResult ?? coord.pendingResult, .defeat)

        // Anyone else's exhaustion loses nothing.
        let other = try simulator("82")
        revealAll(other)
        let tile = try XCTUnwrap(other.coord.boardState.cells.values.first { $0.treasureID == "62" }?.coord)
        stand(other, 1, on: tile)
        other.coord.lootAtEndOfTurn(other.gm.game.characters[1].id)
        other.coord.sufferDamage(999, to: piece(other, 0))
        other.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(other.coord.scenarioResult ?? other.coord.pendingResult)
    }

    // MARK: - #81: the Crystal of Zenith and the Sphere of Midnight

    /// "The first treasure tile looted gives the looting character the Crystal of Zenith; the
    /// second gives the Sphere of Midnight." A character "adjacent to the altar at the end of
    /// their turn may discard the Crystal of Zenith or the Sphere of Midnight to make the
    /// Colorless suffer 2×C damage": asked for each as the turn ends there, and free to keep it.
    func testTheRelicsAreLootedInOrderAndDiscardedBesideTheAltar() async throws {
        let sim = try simulator("81", prompts: true)
        let coord = sim.coord
        revealAll(sim)
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        let goals = coord.boardState.cells.values.filter { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }.map(\.coord).sorted()
        XCTAssertEqual(goals.count, 2)
        stand(sim, 0, on: goals[0])
        coord.lootAtEndOfTurn(brute.id)
        XCTAssertEqual(coord.carried(by: brute.id).map(\.name), ["Crystal of Zenith"], "the first tile looted")
        stand(sim, 1, on: goals[1])
        coord.lootAtEndOfTurn(spellweaver.id)
        XCTAssertEqual(coord.carried(by: spellweaver.id).map(\.name), ["Sphere of Midnight"], "the second")

        let boss = try XCTUnwrap(monsters(sim).first { if case .monster("the-colorless", _) = $0 { return true }; return false })
        let colorless = try XCTUnwrap(coord.entity(for: boss))
        colorless.maxHealth = 50
        colorless.health = 50
        let altar = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first)
        let beside = coord.boardState.neighbors(of: altar).sorted().filter { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil }
        XCTAssertGreaterThanOrEqual(beside.count, 2)

        // Away from the altar there is nothing to ask.
        coord.noteCarriedSpends(after: brute.id)
        XCTAssertTrue(coord.pendingSpends.isEmpty)

        func endTurnBesideTheAltar(_ index: Int, on hex: HexCoord, discard: Bool) async throws {
            stand(sim, index, on: hex)
            coord.noteCarriedSpends(after: sim.gm.game.characters[index].id)
            XCTAssertEqual(coord.pendingSpends, [sim.gm.game.characters[index].id])
            let asking = Task { @MainActor in await coord.resolveCarriedSpends() }
            let deadline = Date().addingTimeInterval(3)
            while coord.pendingFigureChoice == nil, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
            let asked = try XCTUnwrap(coord.pendingFigureChoice, "asked whether to discard it")
            XCTAssertEqual(asked.options, [boss])
            XCTAssertEqual(asked.declineTitle, "Keep It")
            XCTAssertTrue(asked.question.contains("4 damage"), asked.question)
            coord.resolveFigureChoice(discard ? boss : nil)
            await asking.value
        }
        try await endTurnBesideTheAltar(0, on: beside[0], discard: false)
        XCTAssertEqual(colorless.health, 50, "kept")
        XCTAssertEqual(coord.holder(of: "Crystal of Zenith")?.id, brute.id)
        try await endTurnBesideTheAltar(0, on: beside[0], discard: true)
        XCTAssertEqual(colorless.health, 50 - 2 * 2, "2 × C")
        XCTAssertNil(coord.holder(of: "Crystal of Zenith"))
        XCTAssertEqual(coord.boardState.carriedGone["Crystal of Zenith"], "spent")
        XCTAssertTrue(coord.spendable(by: brute.id).isEmpty, "it is gone")
        try await endTurnBesideTheAltar(1, on: beside[1], discard: true)
        XCTAssertEqual(colorless.health, 50 - 4 * 2)
    }

    // MARK: - #54: the Staff of Xorn

    /// Palace of Ice: the Seeker of Xorn (the character on that quest) holds the staff. "Only
    /// the character equipped with the Staff of Xorn can inflict damage on the Harrower
    /// Infesters. For each point of damage inflicted … place one damage token on the Staff."
    /// It is full at 2×C×(L+1); then the Seeker ending a turn beside the altar wins — and "if
    /// the Seeker of Xorn becomes exhausted, the scenario is lost."
    func testTheStaffOfXornIsChargedByItsHolderAndPlacedOnTheAltar() async throws {
        let sim = try simulator("54")
        let coord = sim.coord
        let brute = sim.gm.game.characters[0], seeker = sim.gm.game.characters[1]
        // The Spellweaver is the Seeker: set before the scenario is set up again with her quest.
        seeker.personalQuest = "510"
        coord.boardState.carriedBy = [:]
        coord.assignCarriedAtSetup()
        XCTAssertEqual(coord.holder(of: "Staff of Xorn")?.id, seeker.id, "the one on the quest, whoever comes first")
        revealAll(sim)
        let staff = try XCTUnwrap(coord.carriedThings.first)
        XCTAssertEqual(coord.fullCharge(of: staff), 2 * 2 * (sim.gm.game.level + 1))
        let full = try XCTUnwrap(coord.fullCharge(of: staff))

        let infesters = monsters(sim).filter { if case .monster("harrower-infester", _) = $0 { return true }; return false }
        let infester = try XCTUnwrap(infesters.first)
        let harrower = try XCTUnwrap(coord.entity(for: infester))
        harrower.maxHealth = 40
        harrower.health = 40
        harrower.shield = nil
        harrower.shieldPersistent = nil
        // Anyone else's attack does nothing to it — nor does damage from nowhere — but its effects land.
        await coord.performAttack(attacker: piece(sim, 0), target: infester, attack: AttackParameters(value: 5, conditions: [.muddle]),
                                  drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(harrower.health, 40, "the Brute hasn't the staff")
        XCTAssertTrue(harrower.entityConditions.contains { $0.name == .muddle })
        XCTAssertFalse(coord.sufferDamage(3, to: infester))
        XCTAssertEqual(coord.boardState.carriedCharge["Staff of Xorn"] ?? 0, 0)
        // The Seeker's does, and each point is a token on the staff.
        await coord.performAttack(attacker: piece(sim, 1), target: infester, attack: AttackParameters(value: 3),
                                  drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(harrower.health, 37)
        XCTAssertEqual(coord.boardState.carriedCharge["Staff of Xorn"], 3)
        // Damage she does anyone else charges nothing.
        let other = try XCTUnwrap(monsters(sim).first { !infesters.contains($0) })
        coord.sufferDamage(1, to: other, killer: piece(sim, 1))
        XCTAssertEqual(coord.boardState.carriedCharge["Staff of Xorn"], 3)

        // Beside the altar with the staff not yet full: nothing. Full: the scenario is won.
        let altar = try XCTUnwrap(coord.boardState.markerHexes["a"]?.first)
        for monster in monsters(sim) where monster != infester { coord.removePieceFromBoard(monster) }
        let beside = try XCTUnwrap(coord.boardState.neighbors(of: altar).sorted().first { coord.boardState.isPassable($0) && coord.boardState.piece(at: $0) == nil })
        stand(sim, 1, on: beside)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.scenarioResult ?? coord.pendingResult, "the staff isn't charged")
        coord.sufferDamage(full, to: infester, killer: piece(sim, 1))
        XCTAssertEqual(coord.boardState.carriedCharge["Staff of Xorn"], full, "never more than full")
        XCTAssertTrue(coord.isFullyCharged("Staff of Xorn"))
        stand(sim, 1, on: try XCTUnwrap(coord.boardState.cells.keys.sorted().first { coord.isEmptyHex($0) && $0.distance(to: altar) > 2 }))
        stand(sim, 0, on: beside)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.scenarioResult ?? coord.pendingResult, "the Brute beside the altar isn't the Seeker")
        stand(sim, 0, on: try XCTUnwrap(coord.boardState.cells.keys.sorted().first { coord.isEmptyHex($0) && $0.distance(to: altar) > 2 }))
        stand(sim, 1, on: beside)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.scenarioResult ?? coord.pendingResult, .victory)
        _ = brute

        // The Seeker exhausted loses it.
        let lost = try simulator("54")
        XCTAssertEqual(lost.coord.holder(of: "Staff of Xorn")?.id, lost.gm.game.characters[0].id, "no one on the quest or bearing the item: the first")
        lost.coord.sufferDamage(999, to: piece(lost, 0))
        lost.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(lost.coord.scenarioResult ?? lost.coord.pendingResult, .defeat)
    }
}
