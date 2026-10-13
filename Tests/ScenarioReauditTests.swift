import XCTest
@testable import GlavenGameLib

/// What the second rules audit found wrong, each on its own scenario's board: escapes that undo a
/// loss or miss a win, section rules that outstay their section, damage that lands late, heals
/// counted as one, and the smaller rules that weren't enforced.
@MainActor
final class ScenarioReauditTests: XCTestCase {

    // MARK: - Helpers

    func simulator(_ index: String, characters: [String] = ["brute", "spellweaver"], auto: Bool = true) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: characters, seed: 1, autoResolvePrompts: auto))
        sim.gm.game.round = 1
        return sim
    }

    func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<40 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            sim.coord.openDoor(at: door.coord)
        }
    }

    func pieces(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    func objectives(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .objective = $0 { return true }; return false }.sorted()
    }

    func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != character(sim, index) { board.removePiece(other) }
        board.removePiece(character(sim, index))
        board.placePiece(character(sim, index), at: hex)
    }

    func hexes(_ sim: ScenarioSimulator, _ marker: String) -> [HexCoord] {
        (sim.coord.boardState.markerHexes[marker] ?? []).sorted()
    }

    func tile(_ sim: ScenarioSimulator, _ piece: PieceID) -> String? {
        sim.coord.boardState.piecePositions[piece].flatMap { sim.coord.boardState.cells[$0]?.tileRef.lowercased() }
    }

    func entity(_ sim: ScenarioSimulator, _ piece: PieceID) throws -> GameMonsterEntity {
        guard case .monster(let name, let standee) = piece else { throw XCTSkip("not a monster") }
        return try XCTUnwrap(sim.coord.monsterEntity(name: name, standee: standee))
    }

    /// A free hex at a distance from another that satisfies `wanted`.
    func freeHex(_ sim: ScenarioSimulator, from origin: HexCoord, where wanted: (Int) -> Bool) throws -> HexCoord {
        try XCTUnwrap(sim.coord.boardState.cells.keys.sorted().first { wanted($0.distance(to: origin)) && sim.coord.isEmptyHex($0) })
    }

    // MARK: - #41 Timeworn Tomb

    /// Once the last room is open any exhaustion loses: a character exhausted after another has
    /// left through the exit doesn't turn that loss into a win.
    func testTheTombIsLostByExhaustionAfterAnotherHasLeft() throws {
        let sim = try simulator("41")
        revealAll(sim)
        stand(sim, 1, on: try XCTUnwrap(hexes(sim, "a").first))
        sim.coord.letCharactersLeave()
        XCTAssertEqual(sim.coord.boardState.escapedCharacters, [sim.gm.game.characters[1].id])
        XCTAssertNil(sim.coord.scenarioResult, "one is still inside")
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.scenarioResult, .defeat, "exhausted in the last room: lost, whoever got out")
    }

    /// Leaving through the exit isn't exhaustion: the one who left keeps their cards (for
    /// Streamliner), isn't held against a companion's Protector, and neither character's record
    /// counts an exhaustion for a personal quest.
    func testLeavingThroughTheExitIsNotExhaustion() throws {
        let sim = try simulator("41")
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        revealAll(sim)
        let exits = hexes(sim, "a")
        stand(sim, 1, on: try XCTUnwrap(exits.first))
        spellweaver.activeCards = [try XCTUnwrap(spellweaver.handCards.popLast())]
        let held = spellweaver.handCards.count + 1
        sim.coord.letCharactersLeave()
        XCTAssertFalse(sim.coord.isOnBoard(character(sim, 1)), "gone from the board")
        XCTAssertFalse(sim.gm.game.activeCharacters.contains { $0.id == spellweaver.id }, "and no turn comes to them again")
        XCTAssertEqual(spellweaver.handCards.count + spellweaver.discardedCards.count, held,
                       "their cards are as they were, the one in play put away")
        XCTAssertTrue(spellweaver.lostCards.isEmpty && spellweaver.activeCards.isEmpty)
        XCTAssertFalse(sim.gm.scenarioStatsManager.wasExhausted(spellweaver))

        stand(sim, 0, on: try XCTUnwrap(exits.last))
        sim.coord.letCharactersLeave()
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.scenarioResult ?? sim.coord.pendingResult, .victory)

        // Streamliner (five or more cards in hand and discard) for the one who left first;
        // Protector (no ally exhausted) for the other.
        spellweaver.battleGoalCardIds = ["458"]; spellweaver.selectedBattleGoal = 0
        brute.battleGoalCardIds = ["466"]; brute.selectedBattleGoal = 0
        let results = BattleGoalEvaluator.evaluateAll(game: sim.gm.game, statsManager: sim.gm.scenarioStatsManager,
                                                      scenarioXPGained: [:], battleGoalData: sim.gm.editionStore.battleGoals(for: "gh"))
        XCTAssertEqual(results[spellweaver.id]?.achieved, true, "Streamliner")
        XCTAssertEqual(results[brute.id]?.achieved, true, "Protector")
        if sim.coord.scenarioResult == nil { sim.coord.scenarioResult = .victory }
        XCTAssertEqual(sim.coord.scenarioOutcome()?.heroes.map(\.exhausted), [false, false],
                       "nor does the scenario's summary call them exhausted")

        sim.gm.scenarioManager.finishScenario(success: true)
        for character in [brute, spellweaver] {
            XCTAssertEqual(character.record.timesExhausted, 0, character.name)
            XCTAssertEqual(character.record.partyExhaustions, 0, character.name)
        }
    }

    // MARK: - Escapes: exhausted on the exit

    /// Icecrag Ascent (and #33, #37, #60, #71): the escape is complete when every character is on
    /// an exit hex or was exhausted on one — the last of them exhausted on the exit too.
    func testAnEscapeIsCompleteWithEveryoneExhaustedOnTheExit() throws {
        let sim = try simulator("25")
        revealAll(sim)
        let exits = hexes(sim, "a")
        XCTAssertGreaterThanOrEqual(exits.count, 2)
        stand(sim, 0, on: exits[0])
        stand(sim, 1, on: exits[1])
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertNil(sim.coord.scenarioResult)
        XCTAssertNil(sim.coord.pendingResult, "on the exit: no loss")
        sim.coord.exhaust(sim.gm.game.characters[1], reason: "test")
        XCTAssertEqual(sim.coord.scenarioResult, .victory, "everyone was exhausted on the exit")
    }

    /// One exhausted away from the exit has lost it, wherever the last one falls.
    func testAnEscapeIsLostByExhaustionAwayFromTheExit() throws {
        let sim = try simulator("25")
        revealAll(sim)
        stand(sim, 1, on: try XCTUnwrap(hexes(sim, "a").first))
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
        sim.coord.exhaust(sim.gm.game.characters[1], reason: "test")
        XCTAssertEqual(sim.coord.scenarioResult, .defeat)
    }

    /// Savvas Armory: the treasure comes first — everyone exhausted on the exit with a tile still
    /// to loot is no escape.
    func testAnEscapeStillNeedsTheTreasure() throws {
        let sim = try simulator("33")
        let exits = hexes(sim, "a")
        stand(sim, 0, on: exits[0])
        stand(sim, 1, on: exits[1])
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        sim.coord.exhaust(sim.gm.game.characters[1], reason: "test")
        XCTAssertEqual(sim.coord.scenarioResult, .defeat)
    }

    // MARK: - #83 Shadows Within

    /// When every Cultist is dead the altar's first rules end and the second set replaces them:
    /// a character two hexes from the altar suffers 2, not 3, and no monster is healed by it.
    func testTheAltarsFirstRulesEndWithTheCultists() throws {
        let sim = try simulator("83")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        revealAll(sim)
        let altar = try XCTUnwrap(hexes(sim, "a").first)
        stand(sim, 0, on: try freeHex(sim, from: altar) { $0 == 2 })
        let brute = sim.gm.game.characters[0]
        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: brute)
        XCTAssertEqual(coord.ruleDamageDue.map(\.amount), [1], "Section 1, while a Cultist lives")

        for piece in pieces(sim, named: "cultist") { coord.handleDeath(of: piece) }
        let demon = try XCTUnwrap(pieces(sim, named: "flame-demon").first, "Section 2 sets up the Flame Demons")
        XCTAssertLessThanOrEqual(try XCTUnwrap(coord.boardState.piecePositions[demon]).distance(to: altar), 2)
        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: brute)
        XCTAssertEqual(coord.ruleDamageDue.map(\.amount), [2], "the second set replaces the first")
        let flame = try entity(sim, demon)
        flame.health = flame.maxHealth - 2
        rules.evaluateTurnRules(.turnStart, for: flame)
        XCTAssertEqual(flame.health, flame.maxHealth - 2, "the altar heals no one any more")
    }

    // MARK: - #42 Realm of the Voice

    /// Chord 4's damage lands as a character's turn starts — before they act — not after it.
    func testTheFourthChordHurtsAsTheTurnStarts() async throws {
        let sim = try ScenarioSimulator(scenario: "42", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        await sim.play(rounds: 1)
        let log = sim.transcript
        let roundOver = try XCTUnwrap(log.firstIndex { $0.contains("Round 1 complete") })
        for name in ["Brute", "Spellweaver"] {
            let hurt = try XCTUnwrap(log.firstIndex { $0.hasPrefix("\(name) suffers 1 damage from the scenario") }, name)
            let began = try XCTUnwrap(log.firstIndex { $0.hasPrefix("\(name)\u{2019}s turn") || $0.hasPrefix("\(name) long rests") }, name)
            let ended = try XCTUnwrap(log[..<roundOver].lastIndex { $0.hasPrefix("\(name) ends the turn") || $0.hasPrefix("\(name) long rests") }, name)
            XCTAssertLessThan(hurt, began, "\(name) is hurt before playing the turn")
            XCTAssertLessThan(hurt, ended)
            XCTAssertEqual(log[..<roundOver].filter { $0.hasPrefix("\(name) suffers 1 damage from the scenario") }.count, 1)
        }
    }

    /// And the player may lose a card to negate it there and then, before the turn is played.
    func testTheFourthChordsDamageCanBeNegatedBeforeTheTurn() async throws {
        let sim = try ScenarioSimulator(scenario: "42", options: .init(characters: ["brute", "spellweaver"], seed: 1))
        // Whether the character had already begun playing their cards when asked, each time.
        var askedAfterTheTurnBegan: [String: Bool] = [:]
        await sim.play(rounds: 1) {
            guard let pending = sim.coord.pendingDamage, pending.sourceDescription == "the scenario",
                  askedAfterTheTurnBegan[pending.characterID] == nil else { return }
            let name = sim.coord.characterName(pending.characterID)
            askedAfterTheTurnBegan[pending.characterID] = sim.coord.turnLog.contains { $0.message.hasPrefix("\(name)\u{2019}s turn") }
        }
        XCTAssertEqual(askedAfterTheTurnBegan.count, 2, "each character is asked about the chord's damage")
        XCTAssertEqual(askedAfterTheTurnBegan.values.filter { $0 }.count, 0, "and before their turn is played")
    }

    // MARK: - #58 Bloody Shack

    /// Each bone pile is a heal of its own: Poison stops only the first, and being stunned
    /// stops none of them.
    func testEachBonePileHealsTheHarvesterOnItsOwn() throws {
        let sim = try simulator("58")
        let coord = sim.coord
        revealAll(sim)
        let harvester = try XCTUnwrap(pieces(sim, named: "the-harvester").first)
        XCTAssertEqual(objectives(sim).count, 4)
        let entity = try entity(sim, harvester)
        entity.maxHealth = 30
        entity.health = 10
        coord.applyCondition(.poison, to: harvester)
        coord.applyCondition(.stun, to: harvester)
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertFalse(coord.isConditionActive(.poison, on: harvester), "the first heal takes the Poison")
        XCTAssertEqual(entity.health, 13, "and the other three heal C\u{2212}1 each, stunned or not")
    }

    // MARK: - #2 Barrow Lair

    /// The side room behind door b (A4b) holds the treasure and the elite Living Corpse; the one
    /// behind door d (A3b) two normal ones. (The scenario data had the two tiles' names swapped.)
    func testTheBarrowsSideRoomsHoldWhatTheBookPrints() throws {
        let sim = try simulator("2")
        let coord = sim.coord
        revealAll(sim)
        func corpses(on tile: String) -> [MonsterType] {
            pieces(sim, named: "living-corpse").filter { self.tile(sim, $0) == tile }.compactMap { try? entity(sim, $0).type }.sorted { $0.rawValue < $1.rawValue }
        }
        XCTAssertEqual(corpses(on: "a4b"), [.elite], "door b, with two characters")
        XCTAssertEqual(corpses(on: "a3b"), [.normal, .normal], "door d")
        XCTAssertEqual(corpses(on: "a2a"), [.elite], "door c")
        XCTAssertEqual(corpses(on: "a1a"), [.normal, .normal], "door a")
        let chest = try XCTUnwrap(coord.boardState.cells.values.first { $0.overlay == .treasure && $0.treasureID == "67" })
        XCTAssertEqual(chest.tileRef.lowercased(), "a4b")
        // And the scenario's rooms say the same of the tiles as the map does.
        let rooms = try XCTUnwrap(sim.gm.game.scenario?.data.rooms)
        XCTAssertEqual(rooms.first { $0.treasures?.isEmpty == false && $0.roomNumber > 2 }?.ref, "A4b")
    }

    // MARK: - #92 Back Alley Brawl

    /// The City Guards and the City Archer are set up at the far end of the first room, behind
    /// the party — not spawned (they drop money) and not beside the bandits of the second room.
    func testTheCitysMenAreSetUpBehindTheParty() throws {
        let sim = try simulator("92", characters: ["brute", "spellweaver", "cragheart"])
        revealAll(sim)
        let archer = try XCTUnwrap(pieces(sim, named: "city-archer").first)
        let guards = pieces(sim, named: "city-guard")
        XCTAssertEqual(guards.count, 2)
        XCTAssertEqual(sim.coord.boardState.piecePositions[archer], hexes(sim, "a").first)
        XCTAssertEqual(Set(guards.compactMap { sim.coord.boardState.piecePositions[$0] }), Set(hexes(sim, "b") + hexes(sim, "c")))
        for piece in guards + [archer] {
            XCTAssertEqual(tile(sim, piece), "h3b", "the first room")
            XCTAssertNil(try entity(sim, piece).summonState, "set up, not spawned: it drops money")
        }
        XCTAssertEqual(try entity(sim, archer).type, .elite, "elite for three characters")
        XCTAssertEqual(guards.map { try? entity(sim, $0).type }, [.normal, .normal])
    }

    // MARK: - Immune to forced movement

    /// Sacrifice Pit's two Cultists (b) and Rebel's Stand's Siege Cannon can't be pushed or pulled.
    func testTheCarriersAndTheCannonCantBeForcedToMove() async throws {
        for (scenario, name) in [("78", "cultist-scenario-78"), ("49", "siege-cannon")] {
            let sim = try simulator(scenario)
            revealAll(sim)
            let found = pieces(sim, named: name)
            XCTAssertFalse(found.isEmpty, "\(name) is set up in #\(scenario)")
            for piece in found {
                let hex = try XCTUnwrap(sim.coord.boardState.piecePositions[piece])
                let from = try XCTUnwrap(hex.neighbors.first { sim.coord.boardState.cells[$0] != nil })
                await sim.coord.performPushPull(target: piece, attackerPos: from, steps: 2, isPush: true)
                await sim.coord.performPushPull(target: piece, attackerPos: from, steps: 2, isPush: false)
                XCTAssertEqual(sim.coord.boardState.piecePositions[piece], hex, "\(name) stays put")
            }
        }
        // The pit's carriers shrug off Immobilize and Stun as well.
        let pit = try simulator("78")
        revealAll(pit)
        let carrier = try XCTUnwrap(pieces(pit, named: "cultist-scenario-78").first)
        pit.coord.applyCondition(.stun, to: carrier)
        pit.coord.applyCondition(.immobilize, to: carrier)
        XCTAssertFalse(pit.coord.isConditionActive(.stun, on: carrier))
        XCTAssertFalse(pit.coord.isConditionActive(.immobilize, on: carrier))
    }

    // MARK: - #70 Chained Isle

    /// A Living Spirit can't be damaged in any way: a Wound on it does nothing as its turn starts.
    func testAWoundDoesNotHurtALivingSpirit() throws {
        let sim = try simulator("70")
        let coord = sim.coord
        let hex = try XCTUnwrap(coord.boardState.cells.keys.sorted().first(where: coord.isEmptyHex))
        let piece = try XCTUnwrap(coord.spawnMonster(name: "living-spirit", type: .normal, at: hex, origin: .spawned))
        let spirit = try entity(sim, piece)
        let health = spirit.health
        coord.applyCondition(.wound, to: piece)
        XCTAssertTrue(spirit.entityConditions.contains { $0.name == .wound }, "conditions still take hold")
        // As its turn starts (MonsterTurnController does exactly this).
        sim.gm.entityManager.restoreConditions(spirit)
        sim.gm.entityManager.applyConditionsTurn(spirit)
        XCTAssertEqual(spirit.health, health, "no damage at all, a wound's included")
    }

    // MARK: - #82 Burning Mountain

    private func lootTheMountainsChest(_ sim: ScenarioSimulator) throws {
        revealAll(sim)
        let chest = try XCTUnwrap(sim.coord.boardState.cells.values.first { $0.overlay == .treasure && $0.treasureID == "62" }).coord
        stand(sim, 0, on: chest)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chest])
        XCTAssertTrue(sim.gm.game.characters[0].items.contains("gh-110"), "the chest's two artifacts")
        XCTAssertTrue(sim.gm.game.characters[0].items.contains("gh-115"))
    }

    /// Sacrificing an artifact on the altar hex is Conclusion A: +1 reputation.
    func testSacrificingOnTheMountainIsConclusionA() throws {
        let sim = try simulator("82")
        try lootTheMountainsChest(sim)
        let reputation = sim.gm.game.partyReputation, prosperity = sim.gm.game.partyProsperity
        stand(sim, 0, on: try XCTUnwrap(hexes(sim, "g").first))
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertEqual(sim.coord.boardState.conclusion, "82-A")
        sim.coord.scenarioResult = .victory
        sim.coord.confirmScenarioEnd()
        XCTAssertEqual(sim.gm.game.partyReputation, reputation + 1)
        XCTAssertEqual(sim.gm.game.partyProsperity, prosperity)
        XCTAssertTrue(sim.gm.game.characters[0].items.contains("gh-110"), "won: the treasure is kept")
    }

    /// Escaping with both artifacts is Conclusion B: −1 reputation, −2 prosperity (which never
    /// takes the city below a prosperity level it has reached: CampaignRulesTests).
    func testEscapingTheMountainIsConclusionB() throws {
        let sim = try simulator("82")
        try lootTheMountainsChest(sim)
        sim.gm.game.partyProsperity = 7
        let reputation = sim.gm.game.partyReputation, prosperity = sim.gm.game.partyProsperity
        let entrance = sim.coord.boardState.startingLocations
        stand(sim, 0, on: entrance[0])
        stand(sim, 1, on: entrance[1])
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertEqual(sim.coord.boardState.conclusion, "82-B")
        sim.coord.scenarioResult = .victory
        sim.coord.confirmScenarioEnd()
        XCTAssertEqual(sim.gm.game.partyReputation, reputation - 1)
        XCTAssertEqual(sim.gm.game.partyProsperity, prosperity - 2)
    }

    /// Lost, the chest is reset: its artifacts aren't kept and it can be looted on the next attempt.
    func testTheMountainsChestIsResetOnALoss() throws {
        let sim = try simulator("82")
        try lootTheMountainsChest(sim)
        let key = try XCTUnwrap(sim.gm.scenarioManager.treasureKey("62"))
        XCTAssertTrue(sim.gm.game.lootedTreasures.contains(key))
        let reputation = sim.gm.game.partyReputation
        let brute = sim.gm.game.characters[0]
        sim.coord.scenarioResult = .defeat
        sim.coord.confirmScenarioEnd()
        XCTAssertFalse(brute.items.contains("gh-110"))
        XCTAssertFalse(brute.items.contains("gh-115"))
        XCTAssertFalse(sim.gm.game.lootedTreasures.contains(key), "to be looted again")
        XCTAssertEqual(sim.gm.game.partyReputation, reputation, "and no conclusion is read")
    }

    /// Abandoning the scenario is a loss like any other: the chest is handed back then too.
    func testTheMountainsChestIsResetWhenTheScenarioIsAbandoned() throws {
        let sim = try simulator("82")
        try lootTheMountainsChest(sim)
        let key = try XCTUnwrap(sim.gm.scenarioManager.treasureKey("62"))
        let brute = sim.gm.game.characters[0]
        sim.gm.completeScenario(success: false)   // what "Abandon Scenario" does
        XCTAssertFalse(brute.items.contains("gh-110"))
        XCTAssertFalse(brute.items.contains("gh-115"))
        XCTAssertFalse(sim.gm.game.lootedTreasures.contains(key))
    }

    /// A chest of another scenario is kept when that scenario is lost, as the rules have it.
    func testOtherTreasureIsKeptOnALoss() throws {
        let sim = try simulator("1")
        revealAll(sim)
        let chest = try XCTUnwrap(sim.coord.boardState.cells.values.first { $0.overlay == .treasure && Int($0.treasureID ?? "") != nil })
        stand(sim, 0, on: chest.coord)
        sim.coord.lootHexes(for: character(sim, 0), coords: [chest.coord])
        let key = try XCTUnwrap(sim.gm.scenarioManager.treasureKey(try XCTUnwrap(chest.treasureID)))
        XCTAssertTrue(sim.gm.game.lootedTreasures.contains(key))
        sim.gm.completeScenario(success: false)
        XCTAssertTrue(sim.gm.game.lootedTreasures.contains(key))
    }

    // MARK: - Obstacles that can't be destroyed

    private func obstacles(_ sim: ScenarioSimulator, _ subType: String? = nil, on tile: String? = nil) -> [HexCoord] {
        sim.coord.boardState.cells.values.filter {
            $0.overlay == .obstacle && (subType == nil || $0.overlaySubType == subType) && (tile == nil || $0.tileRef.lowercased() == tile)
        }.map(\.coord).sorted()
    }

    /// The huge boulders of #34, the wall sections of #35 and #36, the dark pits of #39, #51 and
    /// #73 and the centre room's obstacles of #52 can't be destroyed; other obstacles still can.
    func testWhatTheScenarioSaysCantBeDestroyedIsnt() throws {
        for (scenario, subType) in [("34", "boulder-3"), ("35", "wall-section"), ("36", "wall-section"),
                                    ("39", "dark-pit"), ("51", "dark-pit"), ("73", "dark-pit")] {
            let sim = try simulator(scenario)
            revealAll(sim)
            let barred = obstacles(sim, subType)
            XCTAssertFalse(barred.isEmpty, "#\(scenario) has \(subType) obstacles")
            for hex in barred { XCTAssertFalse(sim.coord.isDestructibleObstacle(hex), "#\(scenario) \(subType) at \(hex)") }
        }
        let cellar = try simulator("52")
        revealAll(cellar)
        XCTAssertFalse(obstacles(cellar, on: "m1a").isEmpty)
        for hex in obstacles(cellar, on: "m1a") { XCTAssertFalse(cellar.coord.isDestructibleObstacle(hex), "the centre room") }
        let outer = obstacles(cellar).filter { !obstacles(cellar, on: "m1a").contains($0) }
        XCTAssertTrue(outer.contains(where: cellar.coord.isDestructibleObstacle), "an outer room's boulder can still be destroyed")
        // An obstacle that is an objective (Rebel Swamp's totems) only falls as that objective.
        let swamp = try simulator("45")
        let totem = try XCTUnwrap(objectives(swamp).first.flatMap { swamp.coord.boardState.piecePositions[$0] })
        XCTAssertFalse(swamp.coord.isDestructibleObstacle(totem))
    }

    /// The three ways an ability destroys an obstacle all leave a dark pit where it is: an
    /// ability that destroys one beside the character, Stone Pummel's bonus, Heaving Swing's push.
    func testNoAbilityDestroysADarkPit() async throws {
        let sim = try simulator("39")
        let coord = sim.coord
        revealAll(sim)
        let pit = try XCTUnwrap(obstacles(sim, "dark-pit").first { hex in hex.neighbors.contains(where: coord.isEmptyHex) })
        // Clear the other obstacles around the hex the character takes, so the pit is the only one.
        let beside = try XCTUnwrap(pit.neighbors.sorted().first(where: coord.isEmptyHex))
        for hex in beside.neighbors where hex != pit && coord.boardState.cells[hex]?.overlay == .obstacle { coord.boardState.removeObstacle(at: hex) }
        stand(sim, 0, on: beside)
        XCTAssertFalse(coord.beginPlacingTokens(.destroyObstacle, count: 1, by: character(sim, 0)), "nothing there to destroy")
        XCTAssertEqual(coord.boardState.cells[pit]?.overlay, .obstacle)
        // An ordinary boulder beside the character can be.
        let boulder = try XCTUnwrap(beside.neighbors.sorted().first { $0 != pit && coord.isEmptyHex($0) })
        coord.boardState.placeObstacle(at: boulder, subType: "boulder-1")
        XCTAssertTrue(coord.beginPlacingTokens(.destroyObstacle, count: 1, by: character(sim, 0)))
        guard case .placingToken(_, _, _, let valid) = coord.interactionMode else { return XCTFail("\(coord.interactionMode)") }
        XCTAssertEqual(valid, [boulder])
    }

    // MARK: - #27 Ruinous Rift

    /// Hail does nothing, but she takes a turn at initiative 99, and a Wound hurts her then.
    func testHailsWoundHurtsHerOnHerTurn() async throws {
        let sim = try ScenarioSimulator(scenario: "27", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let hail = try XCTUnwrap(objectives(sim).first)
        let entity = try XCTUnwrap(sim.coord.entity(for: hail) as? GameObjectiveEntity)
        entity.maxHealth = 50
        entity.health = 50
        sim.coord.applyCondition(.wound, to: hail)
        await sim.play(rounds: 1)
        let log = sim.transcript
        XCTAssertEqual(log.filter { $0.hasPrefix("Hail suffers 1 damage from a wound") }.count, 1, "once, on her turn")
        XCTAssertLessThan(entity.health, 50)
        XCTAssertTrue(sim.coord.isConditionActive(.wound, on: hail), "and the wound stays")
        let order = try XCTUnwrap(log.first { $0.hasPrefix("Turn order:") })
        XCTAssertTrue(order.contains("Hail 99"), order)
    }

    // MARK: - #66 Clockwork Cove, #67 Arcane Library

    private func doors(_ sim: ScenarioSimulator, _ a: String, _ b: String) -> [DoorInfo] {
        sim.coord.boardState.doors.filter { Set([($0.fromTileRef ?? "").lowercased(), $0.childTileRef.lowercased()]) == [a, b] }
    }

    private func revealed(_ sim: ScenarioSimulator, _ tile: String) -> Bool {
        sim.coord.boardState.visibleRooms.contains { $0.lowercased() == tile }
    }

    /// Take the rule damage that is due, as the turn loop does between turns.
    private func takeRuleDamage(_ sim: ScenarioSimulator, answering choice: ((BoardCoordinator.PendingDamage) -> BoardCoordinator.DamageMitigationChoice)? = nil) async {
        let done = expectation(description: "rule damage taken")
        sim.coord.afterRuleDamage { done.fulfill() }
        for _ in 0..<200 {
            if let pending = sim.coord.pendingDamage, let choice { sim.coord.resolvePendingDamage(choice: choice(pending)) }
            await Task.yield()
        }
        await fulfillment(of: [done], timeout: 5)
    }

    /// Clockwork Cove's first door opens when a character ENDS a turn on plate (a): walking over
    /// the plate in the middle of a move opens nothing.
    func testTheCovesFirstDoorOpensAsATurnEndsOnItsPlate() async throws {
        let sim = try simulator("66")
        let coord = sim.coord
        let plate = try XCTUnwrap(hexes(sim, "a").first)
        let door = try XCTUnwrap(doors(sim, "j1b", "c1a").first)
        let beside = plate.neighbors.sorted().filter(coord.isEmptyHex)
        XCTAssertGreaterThanOrEqual(beside.count, 2)
        stand(sim, 0, on: beside[0])
        // Across the plate and off it again within one move.
        _ = await coord.moveAlong(character(sim, 0), path: [beside[0], plate, beside[1]], style: .normal)
        XCTAssertFalse(revealed(sim, "c1a"), "stepping over the plate opens nothing")
        // Onto the plate, the move over but the turn not yet.
        _ = await coord.moveAlong(character(sim, 0), path: [beside[1], plate], style: .normal)
        XCTAssertFalse(revealed(sim, "c1a"), "not until the turn ends there")
        XCTAssertTrue(coord.boardState.isLockedDoor(door.coord))
        coord.updateLocks(turnEnded: true)
        XCTAssertTrue(revealed(sim, "c1a"), "the turn ended on the plate")
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))
        // From then on it is held like the others: it shuts as the plate is left, and opens the
        // moment it is stood on again.
        _ = await coord.moveAlong(character(sim, 0), path: [plate, beside[0]], style: .normal)
        XCTAssertTrue(coord.boardState.isClosedDoor(door.coord))
        _ = await coord.moveAlong(character(sim, 0), path: [beside[0], plate], style: .normal)
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))
    }

    /// A character caught in a closing doorway may lose a card to negate the trap damage, like
    /// any damage; a monster simply suffers it.
    func testDamageFromAClosingDoorCanBeNegated() async throws {
        let sim = try simulator("67", auto: false)
        let coord = sim.coord
        coord.openDoor(at: try XCTUnwrap(doors(sim, "l3a", "g1b").first).coord)
        let door = try XCTUnwrap(doors(sim, "a2a", "m1a").first)
        let plate = try XCTUnwrap(hexes(sim, "a").first { coord.boardState.cells[$0]?.tileRef.lowercased() == "g1b" })
        let beside = try XCTUnwrap(plate.neighbors.sorted().first(where: coord.isEmptyHex))
        stand(sim, 0, on: beside)
        _ = await coord.moveAlong(character(sim, 0), path: [beside, plate], style: .normal)
        XCTAssertFalse(coord.boardState.isClosedDoor(door.coord))

        let spellweaver = sim.gm.game.characters[1]
        let health = spellweaver.health, hand = spellweaver.handCards.count
        stand(sim, 1, on: door.coord)
        coord.ruleDamageDue = []
        _ = await coord.moveAlong(character(sim, 0), path: [plate, beside], style: .normal)
        XCTAssertTrue(coord.boardState.isClosedDoor(door.coord))
        XCTAssertNotEqual(coord.boardState.piecePositions[character(sim, 1)], door.coord, "put out of the doorway")
        XCTAssertEqual(coord.ruleDamageDue.map(\.characterID), [spellweaver.id])
        XCTAssertEqual(coord.ruleDamageDue.first?.amount, sim.gm.levelManager.trap())
        XCTAssertEqual(spellweaver.health, health, "not suffered before they have had the choice")
        var asked = 0
        await takeRuleDamage(sim) { pending in
            asked += 1
            XCTAssertEqual(pending.characterID, spellweaver.id)
            return .loseHandCard(cardId: spellweaver.handCards[0])
        }
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(spellweaver.health, health, "negated")
        XCTAssertEqual(spellweaver.handCards.count, hand - 1)
        XCTAssertEqual(spellweaver.lostCards.count, 1)

        // Declined, it is suffered.
        _ = await coord.moveAlong(character(sim, 0), path: [beside, plate], style: .normal)
        stand(sim, 1, on: door.coord)
        _ = await coord.moveAlong(character(sim, 0), path: [plate, beside], style: .normal)
        await takeRuleDamage(sim) { _ in .takeDamage }
        XCTAssertEqual(spellweaver.health, health - sim.gm.levelManager.trap())
    }

    // MARK: - #69 Well of the Unfortunate

    /// Entering a hex beside the well is enough — the move may go on past it.
    func testEnteringAHexBesideTheWellWins() async throws {
        let sim = try simulator("69")
        let coord = sim.coord
        revealAll(sim)
        let well = try XCTUnwrap(hexes(sim, "a").first)
        for piece in pieces(sim) { coord.removePieceFromBoard(piece) }   // the room to ourselves
        func away(_ hex: HexCoord) -> [HexCoord] { hex.neighbors.sorted().filter { coord.isEmptyHex($0) && $0.distance(to: well) == 2 } }
        let beside = try XCTUnwrap(well.neighbors.sorted().first { coord.isEmptyHex($0) && away($0).count >= 2 })
        let before = away(beside)[0], after = away(beside)[1]
        stand(sim, 0, on: before)
        XCTAssertNil(coord.pendingResult)
        _ = await coord.moveAlong(character(sim, 0), path: [before, beside, after], style: .normal)
        XCTAssertNotEqual(coord.boardState.piecePositions[character(sim, 0)]?.distance(to: well), 1, "the move ended away from the well")
        XCTAssertEqual(coord.pendingResult, .victory, "but a hex beside it was entered")
    }

    /// Section 1: as door 1 opens two damage traps appear at (d); a figure on foot standing on
    /// one springs it at once.
    func testTheWellsTrapsAppearWhenItsDoorOpens() async throws {
        let sim = try simulator("69")
        let coord = sim.coord
        // Into the plate's room, where the (d) hexes are.
        for _ in 0..<10 {
            guard hexes(sim, "d").isEmpty,
                  let door = coord.boardState.doors.first(where: { !$0.isOpen && !coord.boardState.isLockedDoor($0.coord) }) else { break }
            coord.openDoor(at: door.coord)
        }
        let trapHexes = hexes(sim, "d")
        XCTAssertEqual(trapHexes.count, 2)
        XCTAssertTrue(trapHexes.allSatisfy { coord.boardState.cells[$0]?.isTrap == false }, "nothing there yet")
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        stand(sim, 0, on: trapHexes[0])
        coord.ruleDamageDue = []
        // The plate is stood on as a turn ends: the door opens, Section 1 is read.
        stand(sim, 1, on: try XCTUnwrap(hexes(sim, "b").first))
        coord.updateLocks(turnEnded: true)
        XCTAssertFalse(pieces(sim, named: "vermling-scout").isEmpty, "Section 1's Vermlings")
        XCTAssertEqual(coord.boardState.cells[trapHexes[1]]?.isTrap, true, "a trap on the free hex")
        XCTAssertEqual(coord.boardState.cells[trapHexes[1]]?.trapDamage, sim.gm.levelManager.trap())
        XCTAssertEqual(coord.boardState.cells[trapHexes[0]]?.isTrap, false, "the one under the Brute went off")
        XCTAssertEqual(coord.ruleDamageDue.map(\.characterID), [brute.id])
        XCTAssertEqual(coord.ruleDamageDue.first?.amount, sim.gm.levelManager.trap())
        let health = brute.health
        await takeRuleDamage(sim)
        XCTAssertEqual(brute.health, health - sim.gm.levelManager.trap())
        XCTAssertEqual(spellweaver.health, spellweaver.maxHealth)
    }

    // MARK: - #85 Sun Temple

    /// With the party achievement Sun-Blessed every round starts with Light strong and Dark
    /// inert; without it the elements are left alone.
    func testSunBlessedLightsTheSunTemple() throws {
        func elements(_ sim: ScenarioSimulator) -> [ElementType: ElementState] {
            Dictionary(uniqueKeysWithValues: sim.gm.game.elementBoard.map { ($0.type, $0.state) })
        }
        let plain = try simulator("85")
        let dark = try XCTUnwrap(plain.gm.game.elementBoard.firstIndex { $0.type == .dark })
        plain.gm.game.elementBoard[dark].state = .strong
        plain.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        XCTAssertEqual(elements(plain)[.light], .inert)
        XCTAssertEqual(elements(plain)[.dark], .strong, "without the achievement nothing is set")

        let blessed = try simulator("85")
        blessed.gm.game.partyAchievements.insert("sun-blessed")
        blessed.gm.game.elementBoard[dark].state = .strong
        blessed.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        XCTAssertEqual(elements(blessed)[.light], .strong)
        XCTAssertEqual(elements(blessed)[.dark], .inert)
        // Every round, not just the first.
        let light = try XCTUnwrap(blessed.gm.game.elementBoard.firstIndex { $0.type == .light })
        blessed.gm.game.elementBoard[light].state = .inert
        blessed.gm.game.round = 2
        blessed.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        XCTAssertEqual(elements(blessed)[.light], .strong)
    }

    // MARK: - #88 Plane of Water

    /// Every Move ability of a character and of their summons is one less.
    func testEveryMoveIsOneLessOnThePlaneOfWater() throws {
        let sim = try simulator("88")
        let coord = sim.coord
        coord.beginMoveAction(pieceID: character(sim, 0), moveRange: 3)
        guard case .selectingMove(_, let range, let valid, _, _) = coord.interactionMode else { return XCTFail("\(coord.interactionMode)") }
        XCTAssertEqual(range, 2, "Move 3 is Move 2 here")
        let from = try XCTUnwrap(coord.boardState.piecePositions[character(sim, 0)])
        XCTAssertFalse(valid.contains { $0.distance(to: from) > 2 })
        coord.interactionMode = .idle

        // A summon three hexes from the nearest enemy, with Move 3: it gets two.
        let brute = sim.gm.game.characters[0]
        let summon = GameSummon(name: "bear", health: 10, maxHealth: 10)
        summon.state = .active
        summon.movement = 3
        summon.attack = .int(2)
        brute.summons.append(summon)
        let piece = PieceID.summon(id: summon.id)
        coord.boardState.placePiece(piece, at: try XCTUnwrap(from.neighbors.first(where: coord.isEmptyHex)))
        XCTAssertEqual(coord.scenarioMoveBonus(of: piece), -1)
        XCTAssertEqual(coord.scenarioMoveBonus(of: character(sim, 0)), -1)
        let enemy = try XCTUnwrap(pieces(sim).first)
        XCTAssertEqual(coord.scenarioMoveBonus(of: enemy), 0, "the monsters move as ever")
        let plain = SummonAI.computeTurn(summon: summon, ownerCharacterID: brute.id, board: coord.boardState, gameState: sim.gm.game)
        let slowed = SummonAI.computeTurn(summon: summon, ownerCharacterID: brute.id, board: coord.boardState, gameState: sim.gm.game,
                                          moveBonus: coord.scenarioMoveBonus(of: piece))
        XCTAssertLessThanOrEqual(slowed.movementPath.count - 1, 2)
        XCTAssertLessThanOrEqual(slowed.movementPath.count, plain.movementPath.count)
        // Elsewhere a Move is what the card says.
        let other = try simulator("1")
        other.coord.beginMoveAction(pieceID: character(other, 0), moveRange: 3)
        guard case .selectingMove(_, let usual, _, _, _) = other.coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(usual, 3)
    }

    // MARK: - #90 Demonic Rift

    /// As every even round ends with no character in the right-hand room, a Night Demon appears
    /// beside the left room's altar: normal for two characters, every second one elite for
    /// three, elite for four.
    func testANightDemonComesWhenTheRightRoomIsEmpty() throws {
        func demons(_ sim: ScenarioSimulator) -> [PieceID] { pieces(sim, named: "night-demon") }
        for (party, ranks) in [(["brute", "spellweaver"], [MonsterType.normal, .normal]),
                               (["brute", "spellweaver", "cragheart"], [.normal, .elite]),
                               (["brute", "spellweaver", "cragheart", "scoundrel"], [.elite, .elite])] {
            let sim = try simulator("90", characters: party)
            let rules = sim.gm.scenarioRulesManager
            let altarSide = Set(hexes(sim, "b"))
            XCTAssertEqual(altarSide.count, 2)
            var known = Set(demons(sim))
            sim.gm.game.round = 1
            rules.evaluateRules(phase: .roundEnd)
            XCTAssertEqual(Set(demons(sim)), known, "an odd round: none")
            for (number, rank) in ranks.enumerated() {
                sim.gm.game.round = 2 * (number + 1)
                rules.evaluateRules(phase: .roundEnd)
                let arrived = Set(demons(sim)).subtracting(known)
                XCTAssertEqual(arrived.count, 1, "\(party.count) characters, round \(sim.gm.game.round)")
                for demon in arrived {
                    XCTAssertEqual(try entity(sim, demon).type, rank, "\(party.count) characters, spawn \(number + 1)")
                    XCTAssertEqual(tile(sim, demon), "m1b", "in the left room")
                }
                known.formUnion(arrived)
            }
            // With a character in the right-hand room, none comes.
            revealAll(sim)
            known = Set(demons(sim))
            let right = try XCTUnwrap(sim.coord.boardState.cells.values.first { $0.tileRef.lowercased() == "d1b" && sim.coord.isEmptyHex($0.coord) }).coord
            stand(sim, 0, on: right)
            sim.gm.game.round = 8
            rules.evaluateRules(phase: .roundEnd)
            XCTAssertEqual(Set(demons(sim)), known)
        }
    }
}
