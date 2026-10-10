import XCTest
@testable import GlavenGameLib

/// Special rules of single scenarios, as the scenario book prints them (found wanting by the
/// rules audit of 2026-10-09, `docs/scenario-book/rules-audit.md`).
@MainActor
final class ScenarioSpecialRuleTests: XCTestCase {

    private func simulator(_ index: String, characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        return sim
    }

    private func revealAll(_ sim: ScenarioSimulator) {
        for _ in 0..<40 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { return }
            sim.coord.openDoor(at: door.coord)
        }
    }

    private func objectives(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .objective = $0 { return true }; return false }.sorted()
    }

    // MARK: - #22 Temple of the Elements

    /// For each altar standing, every demon has +1 maximum hit points and +1 attack, and +½
    /// movement and range (rounded up) — range only for those that have any. Each altar destroyed
    /// takes its share away. (The rule used to set every demon's hit points to 1.)
    func testAltarsStrengthenTheDemons() throws {
        let sim = try simulator("22")
        let coord = sim.coord
        revealAll(sim)
        let demons = sim.gm.game.monsters.filter { $0.name.hasSuffix("-demon") && !$0.aliveEntities.isEmpty }
        XCTAssertEqual(demons.count, 4, "earth, flame, frost and wind")
        func printed(_ monster: GameMonster, _ type: MonsterType) throws -> MonsterStatModel {
            try XCTUnwrap(monster.monsterData?.stat(for: type, at: monster.level))
        }
        func check(altars: Int, _ message: String) throws {
            for monster in demons {
                for entity in monster.aliveEntities {
                    let card = try printed(monster, entity.type), stat = try XCTUnwrap(monster.stat(for: entity.type))
                    XCTAssertEqual(entity.maxHealth, card.healthValue(characterCount: 2) + altars, "\(monster.name) hit points, \(message)")
                    XCTAssertEqual(stat.attackValue(characterCount: 2), card.attackValue(characterCount: 2) + altars, "\(monster.name) attack, \(message)")
                    XCTAssertEqual(stat.movementValue(characterCount: 2), card.movementValue(characterCount: 2) + (altars + 1) / 2,
                                   "\(monster.name) movement, \(message)")
                    let range = card.rangeValue(characterCount: 2)
                    XCTAssertEqual(stat.rangeValue(characterCount: 2), range == 0 ? 0 : range + (altars + 1) / 2, "\(monster.name) range, \(message)")
                    XCTAssertLessThanOrEqual(entity.health, entity.maxHealth)
                }
            }
        }
        try check(altars: 4, "four altars")
        XCTAssertTrue(demons.contains { $0.stat(for: .normal)?.rangeValue(characterCount: 2) == 0 }, "a melee demon is among them")
        XCTAssertTrue(demons.contains { ($0.stat(for: .normal)?.rangeValue(characterCount: 2) ?? 0) > 0 }, "and a ranged one")

        let altars = objectives(sim)
        coord.sufferDamage(99, to: altars[0])
        try check(altars: 3, "three altars")
        for altar in altars.dropFirst() { coord.sufferDamage(99, to: altar) }
        try check(altars: 0, "none")
    }

    /// A demon that arrives while altars stand arrives with their bonus.
    func testADemonSpawnedLaterHasTheBonusToo() throws {
        let sim = try simulator("22")
        revealAll(sim)
        let earth = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "earth-demon" })
        let card = try XCTUnwrap(earth.monsterData?.stat(for: .normal, at: earth.level)).healthValue(characterCount: 2)
        let hex = try XCTUnwrap(sim.coord.boardState.cells.keys.sorted().first(where: sim.coord.isEmptyHex))
        let piece = try XCTUnwrap(sim.coord.spawnMonster(name: "earth-demon", type: .normal, at: hex, origin: .spawned))
        guard case .monster(_, let standee) = piece else { return XCTFail() }
        XCTAssertEqual(sim.coord.monsterEntity(name: "earth-demon", standee: standee)?.maxHealth, card + 4)
    }

    /// The other health rules still mean what they did: Battlements B's Prime Demon has twice
    /// its hit points, the Arcane Golem its own times the number of characters.
    func testHealthFormulasAreStillFormulas() throws {
        let battlements = try simulator("36")
        let prime = try XCTUnwrap(battlements.gm.game.monsters.first { $0.name == "prime-demon" })
        let primeCard = try XCTUnwrap(prime.monsterData?.stat(for: .boss, at: prime.level)).healthValue(characterCount: 2)
        battlements.gm.scenarioRulesManager.evaluateRules()
        XCTAssertEqual(prime.aliveEntities.first?.maxHealth, primeCard * 2)

        let library = try simulator("67")
        while let door = library.coord.boardState.doors.first(where: { !$0.isOpen }) { library.coord.openDoor(at: door.coord) }
        let golem = try XCTUnwrap(library.gm.game.monsters.first { $0.name == "stone-golem" })
        let golemCard = try XCTUnwrap(golem.monsterData?.stat(for: .elite, at: golem.level)).healthValue(characterCount: 2)
        XCTAssertEqual(golem.aliveEntities.first?.maxHealth, golemCard * 2)
    }

    private func pieces(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    private func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != character(sim, index) { board.removePiece(other) }
        board.removePiece(character(sim, index))
        board.placePiece(character(sim, index), at: hex)
    }

    // MARK: - Figures that can't be moved

    /// Lair of the Unseeing Eye: the Sightless Eye can't be pushed or pulled (its stat card's
    /// immunity was never looked at).
    func testAnImmovableBossIsNotPushed() async throws {
        let sim = try simulator("47")
        revealAll(sim)
        let eye = try XCTUnwrap(pieces(sim, named: "the-sightless-eye").first)
        let hex = try XCTUnwrap(sim.coord.boardState.piecePositions[eye])
        let from = try XCTUnwrap(hex.neighbors.first { sim.coord.boardState.cells[$0] != nil })
        await sim.coord.performPushPull(target: eye, attackerPos: from, steps: 2, isPush: true)
        XCTAssertEqual(sim.coord.boardState.piecePositions[eye], hex)
        await sim.coord.performPushPull(target: eye, attackerPos: from, steps: 2, isPush: false)
        XCTAssertEqual(sim.coord.boardState.piecePositions[eye], hex)
        // An ordinary monster beside it still is.
        let terror = try XCTUnwrap(pieces(sim).first { $0 != eye })
        let stood = try XCTUnwrap(sim.coord.boardState.piecePositions[terror])
        let pusher = try XCTUnwrap(stood.neighbors.first { sim.coord.boardState.cells[$0] != nil })
        await sim.coord.performPushPull(target: terror, attackerPos: pusher, steps: 1, isPush: true)
        XCTAssertNotEqual(sim.coord.boardState.piecePositions[terror], stood)
    }

    // MARK: - #51 The Void

    /// Each character suffers 2 damage as their own turn ends — not all together when the round
    /// does — and so does a summon.
    func testTheVoidHurtsAsEachTurnEnds() async throws {
        let sim = try ScenarioSimulator(scenario: "51", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        await sim.play(rounds: 1)
        let log = sim.transcript
        let hurt = log.indices.filter { log[$0].contains("suffers 2 damage from the scenario") }
        XCTAssertEqual(hurt.count, 2, "once for each character")
        let roundOver = try XCTUnwrap(log.firstIndex { $0.contains("Round 1 complete") })
        let turnEnds = log.indices.filter { log[$0].contains("ends the turn") }
        for index in hurt {
            XCTAssertLessThan(index, roundOver)
            let ended = try XCTUnwrap(turnEnds.last { $0 < index }, "after a turn's end")
            XCTAssertFalse(log[ended...index].contains { $0.contains("\u{2019}s turn") }, "before anyone else acts")
        }

        let owner = sim.gm.game.characters[0]
        let summon = GameSummon(name: "bear", health: 6, maxHealth: 6)
        summon.state = .active
        owner.summons.append(summon)
        let hex = try XCTUnwrap(sim.coord.boardState.cells.keys.sorted().first(where: sim.coord.isEmptyHex))
        sim.coord.boardState.placePiece(.summon(id: summon.id), at: hex)
        await SummonTurnController(coordinator: sim.coord, gameManager: sim.gm).executeSummonTurns(for: owner)
        XCTAssertEqual(summon.health, 4, "the summon's turn ended too")
    }

    // MARK: - Protected, not allied

    /// Crystalline Cave's crystal and Harried Village's villagers are the monsters' targets and
    /// the party's to protect, but no allies: nothing heals or helps them.
    func testWhatIsProtectedIsNoAlly() throws {
        for index in ["84", "86"] {
            let sim = try simulator(index)
            let ward = try XCTUnwrap(objectives(sim).first, index)
            let brute = character(sim, 0)
            XCTAssertFalse(sim.coord.areAllies(brute, ward), index)
            XCTAssertFalse(sim.coord.areEnemies(brute, ward), index)
            stand(sim, 0, on: try XCTUnwrap(sim.coord.boardState.piecePositions[ward]?.neighbors.first(where: sim.coord.isEmptyHex)))
            XCTAssertFalse(sim.coord.alliesInRange(of: brute, range: 3, includeSelf: false).contains(ward), "\(index): no heal reaches it")
            let monsters = try XCTUnwrap(sim.gm.game.monsters.first { !$0.aliveEntities.isEmpty }, index)
            XCTAssertTrue(MonsterAI.gatherEnemies(board: sim.coord.boardState, monster: monsters, gameState: sim.gm.game).contains(ward), index)
        }
    }

    // MARK: - #75 Overgrown Graveyard

    /// Every grave dug up lets out its own Living Corpse where it stood — normal from an (a)
    /// grave and elite from a (b) grave for three characters. (Only the first of each used to.)
    func testEveryGraveLetsOutItsCorpse() throws {
        let sim = try simulator("75", characters: ["brute", "spellweaver", "cragheart"])
        revealAll(sim)
        let coord = sim.coord
        func graves(_ marker: String) -> [PieceID] {
            objectives(sim).filter { (coord.entity(for: $0) as? GameObjectiveEntity)?.marker == marker }
        }
        XCTAssertEqual(graves("a").count, 4)
        XCTAssertEqual(graves("b").count, 4)
        var risen = 0
        for (marker, rank) in [("a", MonsterType.normal), ("b", .elite)] {
            for grave in graves(marker).prefix(2) {
                let hex = try XCTUnwrap(coord.boardState.piecePositions[grave])
                coord.sufferDamage(99, to: grave)
                risen += 1
                let corpse = try XCTUnwrap(coord.boardState.piece(at: hex), "a corpse where grave \(marker) was")
                guard case .monster("living-corpse", let standee) = corpse else { return XCTFail("\(corpse)") }
                XCTAssertEqual(coord.monsterEntity(name: "living-corpse", standee: standee)?.type, rank, marker)
                XCTAssertEqual(pieces(sim, named: "living-corpse").count, risen)
            }
        }
    }

    // MARK: - #26 Ancient Cistern

    /// Each uncleansed pump summons its own imp: two pumps lettered (a), an imp beside each.
    func testEachPumpGetsItsOwnImp() throws {
        let sim = try simulator("26")
        revealAll(sim)
        let coord = sim.coord
        let pumps = objectives(sim).compactMap { coord.boardState.piecePositions[$0] }
        XCTAssertEqual(pumps.count, 2)
        for imp in pieces(sim, named: "black-imp") { coord.boardState.removePiece(imp) }
        XCTAssertTrue(coord.spawnFromScenarioRule(name: "black-imp", type: .normal, marker: "a", health: nil))
        XCTAssertTrue(coord.spawnFromScenarioRule(name: "black-imp", type: .normal, marker: "a", health: nil))
        let imps = pieces(sim, named: "black-imp").compactMap { coord.boardState.piecePositions[$0] }
        XCTAssertEqual(imps.count, 2)
        for pump in pumps {
            XCTAssertEqual(imps.filter { $0.distance(to: pump) == 1 }.count, 1, "one imp beside the pump at \(pump)")
        }
    }

    // MARK: - Hit points that round up

    /// The Hungry Soul and the Bloated Regent have half an elite's hit points times the number
    /// of characters, rounded up — a point more than rounding down for three characters.
    func testBossHitPointsRoundUp() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        for (name, level, three) in [("hungry-soul", 2, 11), ("bloated-regent", 2, 20)] {
            let data = try XCTUnwrap(gm.editionStore.monsterData(name: name, edition: "gh"), name)
            let stat = try XCTUnwrap(data.stat(for: .boss, at: level), name)
            XCTAssertEqual(stat.healthValue(characterCount: 3), three, name)
            XCTAssertEqual(stat.healthValue(characterCount: 2) * 2, stat.healthValue(characterCount: 4), "\(name): whole numbers stay whole")
        }
    }

    // MARK: - Setup

    /// The book's counts: two −1 cards at the Rebel Swamp, two Curses in the Noxious Cellar.
    func testSetupCardCountsAreTheBooks() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        for (index, cards) in [("45", "minus1:2"), ("52", "curse:2")] {
            let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
            let added = (scenario.rules ?? []).flatMap { $0.figures ?? [] }.filter { $0.type == "amAdd" }.compactMap { $0.value?.stringValue }
            XCTAssertEqual(added, [cards], index)
        }
    }

    // MARK: - #41 Timeworn Tomb

    /// One exhausted on the way (before the last room, where that doesn't lose) isn't waited
    /// for: the scenario is won when the rest have left.
    func testEscapeDoesNotWaitForTheExhausted() throws {
        let sim = try simulator("41")
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertNil(sim.coord.pendingResult)
        revealAll(sim)
        stand(sim, 1, on: try XCTUnwrap(sim.coord.boardState.markerHexes["a"]?.first))
        sim.coord.letCharactersLeave()
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.scenarioResult, .victory)
    }

    // MARK: - #92 Back Alley Brawl

    /// The guards arrive when the second room opens, not as the scenario starts; every other
    /// enemy dead wins it with the guards still standing.
    func testTheBrawlIsWonWithTheGuardsAlive() throws {
        let sim = try simulator("92")
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertTrue(pieces(sim, named: "city-guard").isEmpty, "no guards yet")
        XCTAssertTrue(sim.coord.boardState.doors.contains { !$0.isOpen }, "and the door is shut")
        revealAll(sim)
        XCTAssertEqual(pieces(sim, named: "city-guard").count, 2)
        XCTAssertEqual(pieces(sim, named: "city-archer").count, 1)
        let city = Set(pieces(sim, named: "city-guard") + pieces(sim, named: "city-archer"))
        let others = pieces(sim).filter { !city.contains($0) }
        XCTAssertNil(sim.coord.pendingResult, "nothing is won yet")
        for piece in others.dropLast() { sim.coord.handleDeath(of: piece) }
        XCTAssertNil(sim.coord.pendingResult, "one enemy is left")
        sim.coord.handleDeath(of: try XCTUnwrap(others.last))
        XCTAssertEqual(sim.coord.pendingResult, .victory)
        XCTAssertEqual(Set(pieces(sim)), city)
    }

    // MARK: - #90 Demonic Rift

    /// The Living Spirits come when every demon is dead, not as the scenario starts; killing
    /// them closes the rift.
    func testTheRiftsSpiritsComeAfterTheDemons() throws {
        let sim = try simulator("90")
        sim.gm.scenarioRulesManager.evaluateRules()
        XCTAssertTrue(pieces(sim, named: "living-spirit").isEmpty)
        for piece in pieces(sim) { sim.coord.handleDeath(of: piece) }
        XCTAssertTrue(pieces(sim, named: "living-spirit").isEmpty, "the second room's demons haven't been met")
        XCTAssertNil(sim.coord.pendingResult)
        revealAll(sim)
        XCTAssertTrue(pieces(sim, named: "living-spirit").isEmpty, "demons still stand")
        for piece in pieces(sim) { sim.coord.handleDeath(of: piece) }
        XCTAssertEqual(pieces(sim, named: "living-spirit").count, 4, "two at (b), two at (c)")
        XCTAssertNil(sim.coord.pendingResult)
        for piece in pieces(sim) { sim.coord.handleDeath(of: piece) }
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    // MARK: - Sides

    /// Fading Lighthouse's demons are enemies (the data lists them as "allied", which made
    /// them fight for the party).
    func testTheLighthousesDemonsAreEnemies() throws {
        let sim = try simulator("61")
        revealAll(sim)
        let demon = try XCTUnwrap(pieces(sim).first { if case .monster(let name, _) = $0 { return name.hasSuffix("-demon") }; return false })
        XCTAssertFalse(sim.coord.isPlayerSide(demon))
        XCTAssertTrue(sim.coord.areEnemies(character(sim, 0), demon))
    }

    /// Gloomhaven Battlements A: the demons allied to the party attack the gate; the city's
    /// guards don't. In B the gate is the demons' to break and the allied archers leave it be.
    func testAlliedMonstersAttackWhatIsToBeDestroyed() throws {
        let a = try simulator("35")
        let gate = try XCTUnwrap(objectives(a).first)
        func targets(_ sim: ScenarioSimulator, _ name: String) throws -> [PieceID] {
            MonsterAI.gatherEnemies(board: sim.coord.boardState,
                                    monster: try XCTUnwrap(sim.gm.game.monsters.first { $0.name == name }, name), gameState: sim.gm.game)
        }
        XCTAssertTrue(try targets(a, "earth-demon").contains(gate))
        XCTAssertFalse(try targets(a, "city-archer").contains(gate))

        let b = try simulator("36")
        let gateB = try XCTUnwrap(objectives(b).first)
        XCTAssertTrue(try targets(b, "earth-demon").contains(gateB))
        XCTAssertFalse(try targets(b, "city-archer").contains(gateB))
    }
}
