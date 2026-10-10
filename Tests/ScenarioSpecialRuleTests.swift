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

    /// The other health rules still mean what they did: the Arcane Golem has its own hit points
    /// times the number of characters (Battlements B's doubled Prime Demon: see below).
    func testHealthFormulasAreStillFormulas() throws {
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

    // MARK: - Rules that wait for something

    private func tile(_ sim: ScenarioSimulator, _ piece: PieceID) -> String? {
        sim.coord.boardState.piecePositions[piece].flatMap { sim.coord.boardState.cells[$0]?.tileRef.lowercased() }
    }

    private func hexes(_ sim: ScenarioSimulator, _ marker: String) -> [HexCoord] {
        sim.coord.boardState.markerHexes[marker] ?? []
    }

    /// Sunken Vessel: every character starts immobilized.
    func testTheSunkenVesselStartsEveryoneImmobilized() throws {
        let sim = try simulator("93")
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        for character in sim.gm.game.characters {
            XCTAssertTrue(character.entityConditions.contains { $0.name == .immobilize }, character.name)
        }
    }

    /// Harried Village: the scouts come as each round begins (elite at c, normal at d for three
    /// characters), and the Lurkers aren't set up until the end of the round in which the first
    /// villager is saved — then where the map prints them.
    func testTheLurkersWaitForTheFirstVillagerSaved() throws {
        let sim = try simulator("86", characters: ["brute", "spellweaver", "cragheart"])
        let coord = sim.coord
        revealAll(sim)
        XCTAssertTrue(pieces(sim, named: "lurker").isEmpty, "no Lurkers at the start")
        XCTAssertFalse(coord.boardState.heldMonsterSlots.isEmpty, "their places are kept")
        XCTAssertNil(sim.gm.game.monsters.first { $0.name == "lurker" }?.aliveEntities.first)

        let before = Set(pieces(sim, named: "vermling-scout"))
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        let scouts = Set(pieces(sim, named: "vermling-scout")).subtracting(before)
        XCTAssertEqual(scouts.count, 2, "one at c, one at d, as round 1 begins")
        func scout(by marker: String) throws -> PieceID {
            let place = try XCTUnwrap(hexes(sim, marker).first)
            return try XCTUnwrap(scouts.first { coord.boardState.piecePositions[$0].map { $0.distance(to: place) <= 1 } == true }, marker)
        }
        let atC = try scout(by: "c"), atD = try scout(by: "d")
        XCTAssertNotEqual(atC, atD)
        XCTAssertTrue(coord.boardState.eliteStandees.contains(atC), "elite at c for three")
        XCTAssertFalse(coord.boardState.eliteStandees.contains(atD), "normal at d for three")

        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertTrue(pieces(sim, named: "lurker").isEmpty, "no villager is saved yet")

        // A villager reaches the docks.
        sim.gm.game.round = 2
        let villager = try XCTUnwrap(objectives(sim).first)
        let dock = try XCTUnwrap(hexes(sim, "b").first)
        if let other = coord.boardState.piece(at: dock) { coord.boardState.removePiece(other) }
        coord.boardState.removePiece(villager)
        coord.boardState.placePiece(villager, at: dock)
        coord.noteEscortArrival(villager)
        XCTAssertNil(coord.boardState.piecePositions[villager], "saved")
        XCTAssertTrue(pieces(sim, named: "lurker").isEmpty, "not before the round ends")
        // A save in between keeps their places.
        let saved = BoardSnapshot.from(coord.boardState)
        let copy = BoardState()
        saved.restore(to: copy)
        XCTAssertEqual(copy.heldMonsterSlots, coord.boardState.heldMonsterSlots)

        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        let lurkers = pieces(sim, named: "lurker")
        XCTAssertEqual(lurkers.count, 2, "an elite and a normal for three characters")
        XCTAssertEqual(lurkers.filter(coord.boardState.eliteStandees.contains).count, 1)
        for lurker in lurkers { XCTAssertEqual(tile(sim, lurker), "h3a") }
        XCTAssertTrue(coord.boardState.heldMonsterSlots.isEmpty)
        XCTAssertEqual(sim.gm.game.scenario?.releasedMonsters, ["lurker"])
    }

    /// Shadows Within, Section 1: within two hexes of the altar characters suffer 1 damage and
    /// monsters heal 1 as their turns start. Section 2: the Flame Demons aren't set up until every
    /// Cultist is dead; from then everyone suffers 2 damage a turn and Fire is strong every round.
    func testTheAltarOfShadowsWithin() async throws {
        let sim = try simulator("83")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        revealAll(sim)
        XCTAssertTrue(pieces(sim, named: "flame-demon").isEmpty, "the Flame Demons wait")
        let altar = try XCTUnwrap(hexes(sim, "a").first)
        let near = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { $0.distance(to: altar) == 2 && coord.isEmptyHex($0) })
        let far = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { $0.distance(to: altar) > 4 && coord.isEmptyHex($0) })
        stand(sim, 0, on: near)
        stand(sim, 1, on: far)
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]

        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: brute)
        rules.evaluateTurnRules(.turnStart, for: spellweaver)
        XCTAssertEqual(coord.ruleDamageDue.map(\.characterID), [brute.id])
        XCTAssertEqual(coord.ruleDamageDue.first?.amount, 1)

        // A Cultist beside the altar heals; one far from it doesn't.
        let cultists = pieces(sim, named: "cultist")
        let healed = try XCTUnwrap(cultists.first), unhealed = try XCTUnwrap(cultists.last)
        XCTAssertNotEqual(healed, unhealed)
        for (piece, wanted) in [(healed, { (d: Int) in d == 2 }), (unhealed, { (d: Int) in d > 3 })] {
            coord.boardState.removePiece(piece)
            coord.boardState.placePiece(piece, at: try XCTUnwrap(coord.boardState.cells.keys.sorted().first { wanted($0.distance(to: altar)) && coord.isEmptyHex($0) }))
        }
        for piece in [healed, unhealed] {
            guard case .monster(let name, let standee) = piece, let entity = coord.monsterEntity(name: name, standee: standee) else { return XCTFail() }
            entity.health = entity.maxHealth - 3
            rules.evaluateTurnRules(.turnStart, for: entity)
            XCTAssertEqual(entity.health, entity.maxHealth - (piece == healed ? 2 : 3), "\(piece)")
        }

        // A summon's own turn starts the same way.
        let summon = GameSummon(name: "bear", health: 10, maxHealth: 10)
        summon.state = .active
        brute.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: try XCTUnwrap(near.neighbors.first { $0.distance(to: altar) <= 2 && coord.isEmptyHex($0) }))
        await SummonTurnController(coordinator: coord, gameManager: sim.gm).executeSummonTurns(for: brute)
        XCTAssertEqual(summon.health, 9)

        // Every Cultist dead: the Flame Demons are set up where the map prints them.
        let fire = try XCTUnwrap(sim.gm.game.elementBoard.firstIndex { $0.type == .fire })
        rules.evaluateRules(phase: .roundStart)
        XCTAssertEqual(sim.gm.game.elementBoard[fire].state, .inert)
        for piece in pieces(sim, named: "cultist") { coord.handleDeath(of: piece) }
        let demons = pieces(sim, named: "flame-demon")
        XCTAssertEqual(demons.count, 1, "one elite for two characters")
        for demon in demons {
            XCTAssertEqual(tile(sim, demon), "m1a")
            XCTAssertEqual(coord.boardState.piecePositions[demon]?.distance(to: altar), 1, "beside the altar")
        }
        XCTAssertNil(coord.pendingResult, "they are still to be killed")

        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: spellweaver)
        XCTAssertEqual(coord.ruleDamageDue.first?.amount, 2, "everyone, wherever they stand")
        sim.gm.game.round = 2
        rules.evaluateRules(phase: .roundStart)
        XCTAssertEqual(sim.gm.game.elementBoard[fire].state, .strong)
    }

    /// Lair of the Unseeing Eye, Section 1: once door 1 is open, whoever is still on the first
    /// tile as a round ends suffers 3+L damage — summons too.
    func testTheFirstCaveOfTheLairHurtsThoseWhoStay() throws {
        let sim = try simulator("47")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        coord.ruleDamageDue = []
        rules.evaluateRules(phase: .roundEnd)
        XCTAssertTrue(coord.ruleDamageDue.isEmpty, "the door is shut")

        revealAll(sim)
        let inside = try XCTUnwrap(coord.boardState.cells.values.filter { $0.tileRef.lowercased() == "m1a" }.map(\.coord).sorted().first(where: coord.isEmptyHex))
        stand(sim, 1, on: inside)
        let summon = GameSummon(name: "bear", health: 10, maxHealth: 10)
        brute.summons.append(summon)
        let beside = try XCTUnwrap(coord.boardState.piecePositions[character(sim, 0)]?.neighbors.first(where: coord.isEmptyHex))
        coord.boardState.placePiece(.summon(id: summon.id), at: beside)
        XCTAssertEqual(tile(sim, .summon(id: summon.id)), "j1a")

        sim.gm.game.round = 2
        rules.evaluateRules(phase: .roundEnd)
        let due = 3 + sim.gm.game.level
        XCTAssertEqual(coord.ruleDamageDue.map(\.characterID), [brute.id], "\(spellweaver.name) has gone on")
        XCTAssertEqual(coord.ruleDamageDue.first?.amount, due)
        XCTAssertEqual(summon.health, 10 - due)
    }

    /// Rebel Swamp: a monster within two hexes of a totem performs Heal 2, Self as its turn
    /// starts (so Poison stops it); one farther off, or with the totem destroyed, doesn't.
    func testTotemsHealTheMonstersNearThem() async throws {
        let sim = try simulator("45")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        let totem = try XCTUnwrap(objectives(sim).first)
        let place = try XCTUnwrap(coord.boardState.piecePositions[totem])
        func guardAt(_ distance: (Int) -> Bool) throws -> GameMonsterEntity {
            let hex = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { distance($0.distance(to: place)) && coord.isEmptyHex($0) })
            let piece = try XCTUnwrap(coord.spawnMonster(name: "city-guard", type: .normal, at: hex, origin: .placed))
            guard case .monster(let name, let standee) = piece else { throw XCTSkip() }
            let entity = try XCTUnwrap(coord.monsterEntity(name: name, standee: standee))
            entity.maxHealth = 20
            entity.health = 10
            return entity
        }
        let near = try guardAt { $0 == 2 }, far = try guardAt { $0 >= 4 }, poisoned = try guardAt { $0 <= 2 }
        coord.applyCondition(.poison, to: try XCTUnwrap(coord.pieceID(of: poisoned)))
        for entity in [near, far, poisoned] { rules.evaluateTurnRules(.turnStart, for: entity) }
        XCTAssertEqual(near.health, 12)
        XCTAssertEqual(far.health, 10)
        XCTAssertEqual(poisoned.health, 10, "the heal only removes the Poison")
        XCTAssertFalse(poisoned.entityConditions.contains { $0.name == .poison })

        // It is done as the monster's own turn starts.
        let guards = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "city-guard" })
        sim.gm.monsterManager.drawAbility(for: guards)
        await MonsterTurnController(coordinator: coord, gameManager: sim.gm).executeMonsterGroup(guards)
        XCTAssertEqual(near.health, 14)
        XCTAssertEqual(far.health, 10)

        coord.sufferDamage(99, to: totem)
        rules.evaluateTurnRules(.turnStart, for: near)
        XCTAssertEqual(near.health, 14, "its totem is gone")
    }

    /// Crystalline Cave: the three walls can't be walked through; they come down as rounds 4, 6
    /// and 9 begin.
    func testTheCaveWallsComeDownByTheRound() throws {
        let sim = try simulator("84")
        let coord = sim.coord
        func revealed(_ ref: String) -> Bool { coord.boardState.visibleRooms.contains { $0.lowercased() == ref } }
        XCTAssertEqual(Set(coord.boardState.doors.map(\.coord)), coord.boardState.lockedDoors, "every way out is a wall")
        let wall = try XCTUnwrap(coord.boardState.doors.first)
        let beside = try XCTUnwrap(wall.coord.neighbors.first { coord.boardState.cells[$0] != nil && coord.boardState.isPassable($0) && !coord.boardState.isClosedDoor($0) })
        stand(sim, 0, on: beside)
        XCTAssertFalse(coord.adjacentDoors(from: beside).contains { $0.coord == wall.coord }, "no way through")
        XCTAssertEqual(coord.boardState.visibleRooms.count, 1)
        for (round, opened) in [(2, [String]()), (3, ["a3a"]), (4, ["a3a"]), (5, ["a3a", "a2b"]), (8, ["a3a", "a2b", "e1b"])] {
            sim.gm.game.round = round
            coord.updateLocks(roundEnded: true)
            for ref in ["a3a", "a2b", "e1b"] {
                XCTAssertEqual(revealed(ref), opened.contains(ref), "\(ref) as round \(round) ends")
            }
        }
    }

    /// Gloomhaven Battlements B: the Prime Demon isn't set up. It arrives at (e) when the gate
    /// falls, with twice its hit points less the damage of every round the gate stood; the gate
    /// falls by itself when eight rounds are over.
    func testThePrimeDemonComesWhenTheGateFalls() throws {
        func arrival(round: Int, breaking: Bool) throws -> (health: Int, card: Int, perRound: Int, sim: ScenarioSimulator) {
            let sim = try simulator("36")
            let coord = sim.coord
            XCTAssertTrue(pieces(sim, named: "prime-demon").isEmpty, "not set up")
            sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
            XCTAssertTrue(pieces(sim, named: "prime-demon").isEmpty, "the gate stands")
            let gate = try XCTUnwrap(objectives(sim).first)
            sim.gm.game.round = round
            if breaking { coord.sufferDamage(999, to: gate) } else { sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart) }
            XCTAssertNil(coord.boardState.piecePositions[gate], "the gate is down")
            let demon = try XCTUnwrap(pieces(sim, named: "prime-demon").first, "round \(round)")
            XCTAssertLessThanOrEqual(try XCTUnwrap(coord.boardState.piecePositions[demon]).distance(to: try XCTUnwrap(hexes(sim, "e").first)), 1)
            let monster = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "prime-demon" })
            let card = try XCTUnwrap(monster.monsterData?.stat(for: .boss, at: monster.level)).healthValue(characterCount: 2)
            let entity = try XCTUnwrap(monster.aliveEntities.first)
            XCTAssertEqual(entity.maxHealth, card * 2)
            XCTAssertNil(entity.summonState, "set up, not spawned: it is a monster like any other")
            return (entity.health, card, (2 * 2) + sim.gm.game.level - 2, sim)
        }
        let early = try arrival(round: 3, breaking: true)
        XCTAssertEqual(early.health, early.card * 2 - 2 * early.perRound, "two rounds went by with the gate standing")
        let late = try arrival(round: 9, breaking: false)
        XCTAssertEqual(late.health, late.card * 2 - 8 * late.perRound, "all eight")
        let standing = try simulator("36")
        standing.gm.game.round = 8
        standing.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        XCTAssertEqual(objectives(standing).count, 1, "round 8 is still to be played")
    }

    /// Savvas Armory: a Savvas Icestorm comes at (d) at the end of the round in which the last
    /// treasure tile is looted.
    func testTheIcestormComesWhenTheLastTreasureIsLooted() throws {
        let sim = try simulator("33")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        for _ in 0..<10 {
            for index in coord.scenarioLocks.indices { coord.boardState.releasedLocks.insert(index) }
            for objective in objectives(sim) { coord.sufferDamage(999, to: objective) }
            coord.updateLocks()
            revealAll(sim)
        }
        XCTAssertTrue(coord.boardState.doors.allSatisfy(\.isOpen))
        rules.evaluateRules(phase: .roundEnd)
        let before = pieces(sim, named: "savvas-icestorm").count
        let chests = coord.boardState.cells.values.filter { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }.map(\.coord).sorted()
        XCTAssertEqual(chests.count, 4)
        for chest in chests.dropLast() { coord.lootHexes(for: character(sim, 0), coords: [chest], byLootAction: true) }
        sim.gm.game.round = 2
        rules.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(pieces(sim, named: "savvas-icestorm").count, before, "one chest is left")
        coord.lootHexes(for: character(sim, 0), coords: [try XCTUnwrap(chests.last)], byLootAction: true)
        XCTAssertEqual(pieces(sim, named: "savvas-icestorm").count, before, "not before the round ends")
        sim.gm.game.round = 3
        rules.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(pieces(sim, named: "savvas-icestorm").count, before + 1)
        // Once only (with a standee free for another).
        coord.handleDeath(of: try XCTUnwrap(pieces(sim, named: "savvas-icestorm").first))
        sim.gm.game.round = 4
        rules.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(pieces(sim, named: "savvas-icestorm").count, before, "once")
    }

    /// Timeworn Tomb, Section 1: the middle room's Stone Golems and Ancient Artilleries aren't
    /// set up until a character ends a turn on the pressure plate — then where the book prints
    /// them, in the ranks for the number of characters.
    func testTheTombsGuardiansWakeWithThePlate() throws {
        let sim = try simulator("41", characters: ["brute", "spellweaver", "cragheart"])
        let coord = sim.coord
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen })
        coord.openDoor(at: door.coord)
        func inTheRoom(_ name: String) -> [PieceID] { pieces(sim, named: name).filter { tile(sim, $0) == "l1a" } }
        // The first room's six artilleries are destroyed (there are six standees in all).
        for piece in pieces(sim, named: "ancient-artillery") { coord.handleDeath(of: piece) }
        XCTAssertTrue(inTheRoom("stone-golem").isEmpty)
        XCTAssertTrue(inTheRoom("ancient-artillery").isEmpty)

        stand(sim, 0, on: try XCTUnwrap(hexes(sim, "b").first))
        coord.updateLocks()
        XCTAssertTrue(inTheRoom("stone-golem").isEmpty, "the turn isn't over")
        coord.updateLocks(turnEnded: true)
        let golems = inTheRoom("stone-golem"), artilleries = inTheRoom("ancient-artillery")
        XCTAssertEqual(golems.count, 2)
        XCTAssertEqual(golems.filter(coord.boardState.eliteStandees.contains).count, 1, "one elite for three characters")
        XCTAssertEqual(artilleries.count, 3, "the fourth is for four characters")
        XCTAssertTrue(artilleries.allSatisfy { !coord.boardState.eliteStandees.contains($0) })
        for piece in golems + artilleries {
            guard case .monster(let name, let standee) = piece else { return XCTFail() }
            XCTAssertNil(coord.monsterEntity(name: name, standee: standee)?.summonState, "set up, not spawned")
        }
        coord.updateLocks(turnEnded: true)
        XCTAssertEqual(inTheRoom("ancient-artillery").count, 3, "once")
    }

    // MARK: - Standing effects on attacks and shields

    private func entity(_ sim: ScenarioSimulator, _ piece: PieceID) throws -> GameMonsterEntity {
        guard case .monster(let name, let standee) = piece else { throw XCTSkip("not a monster") }
        return try XCTUnwrap(sim.coord.monsterEntity(name: name, standee: standee))
    }

    /// A monster's own Shield, as its stat card and this round's ability card give it.
    private func cardShield(_ sim: ScenarioSimulator, _ piece: PieceID) throws -> Int {
        let entity = try entity(sim, piece)
        guard case .monster(let name, _) = piece, let monster = sim.gm.game.monsters.first(where: { $0.name == name }) else { return 0 }
        if !monster.abilityDrawn { sim.gm.monsterManager.drawAbility(for: monster) }
        sim.gm.monsterManager.applyStatEffects(for: monster)
        return CombatResolver.totalShield(shield: entity.shield, shieldPersistent: entity.shieldPersistent)
    }

    /// Realm of the Voice: each vocal chord has its penalty for as long as it stands.
    func testEachVocalChordHasItsPenalty() async throws {
        let sim = try simulator("42")
        let coord = sim.coord, rules = sim.gm.scenarioRulesManager
        let brute = sim.gm.game.characters[0]
        brute.health = 30
        brute.maxHealth = 30
        func chord(_ number: Int) throws -> PieceID {
            try XCTUnwrap(objectives(sim).first { coord.objectiveContainer(of: $0)?.objectiveIndex == number }, "chord \(number)")
        }
        XCTAssertEqual(objectives(sim).count, 6)
        // (Not a Night Demon, which gives its attackers disadvantage by itself; and not adjacent,
        // where a ranged attack has it.)
        let stood = try XCTUnwrap(coord.boardState.piecePositions[character(sim, 0)])
        let hex = try XCTUnwrap(coord.boardState.cells.keys.sorted().first { $0.distance(to: stood) == 2 && coord.isEmptyHex($0) })
        let demon = try XCTUnwrap(coord.spawnMonster(name: "wind-demon", type: .normal, at: hex, origin: .placed))
        let night = try entity(sim, demon)
        night.maxHealth = 40
        night.health = 30
        night.shield = nil
        night.shieldPersistent = nil
        let plain = { AttackModifier(type: .plus0) }

        // Chords 1 and 2: the monsters' attacks.
        var health = brute.health
        await coord.performAttack(attacker: demon, target: character(sim, 0), attack: AttackParameters(value: 2), drawCard: plain)
        XCTAssertEqual(health - brute.health, 3, "+1 Attack")
        XCTAssertEqual(coord.lastModifierReveal?.advantage, true)
        coord.sufferDamage(99, to: try chord(1))
        health = brute.health
        await coord.performAttack(attacker: demon, target: character(sim, 0), attack: AttackParameters(value: 2), drawCard: plain)
        XCTAssertEqual(health - brute.health, 2)
        XCTAssertEqual(coord.lastModifierReveal?.advantage, true, "chord 2 still stands")
        coord.sufferDamage(99, to: try chord(2))
        await coord.performAttack(attacker: demon, target: character(sim, 0), attack: AttackParameters(value: 2), drawCard: plain)
        XCTAssertEqual(coord.lastModifierReveal?.advantage, false)

        // Chords 5 and 6: the party's attacks — and what the board says an attack will do.
        let deck = sim.gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: try XCTUnwrap(deck.first { $0.name == "Spare Dagger" }), bottom: try XCTUnwrap(deck.first { $0.name == "Trample" }))
        turn.executeCurrentAction()   // Attack 3, Range 3
        XCTAssertEqual(coord.expectedDamage(attacker: character(sim, 0), target: demon), 2, "\u{2212}1 Attack")
        XCTAssertEqual(coord.attackPreview(attacker: character(sim, 0), target: demon)?.contains("disadvantage"), true)
        var before = night.health
        await coord.performAttack(attacker: character(sim, 0), target: demon, attack: AttackParameters(value: 3), drawCard: plain)
        XCTAssertEqual(before - night.health, 2, "\u{2212}1 Attack")
        XCTAssertEqual(coord.lastModifierReveal?.disadvantage, true)
        coord.sufferDamage(99, to: try chord(5))
        XCTAssertEqual(coord.expectedDamage(attacker: character(sim, 0), target: demon), 2, "chord 6 still stands")
        XCTAssertEqual(coord.attackPreview(attacker: character(sim, 0), target: demon)?.contains("disadvantage"), false)
        coord.sufferDamage(99, to: try chord(6))
        XCTAssertEqual(coord.expectedDamage(attacker: character(sim, 0), target: demon), 3)
        before = night.health
        await coord.performAttack(attacker: character(sim, 0), target: demon, attack: AttackParameters(value: 3), drawCard: plain)
        XCTAssertEqual(before - night.health, 3)
        XCTAssertEqual(coord.lastModifierReveal?.disadvantage, false)
        coord.activePlayerTurn = nil

        // Chords 3 and 4: as turns start.
        before = night.health
        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: night)
        rules.evaluateTurnRules(.turnStart, for: brute)
        XCTAssertEqual(night.health, before + 1)
        XCTAssertEqual(coord.ruleDamageDue.map(\.amount), [1])
        coord.sufferDamage(99, to: try chord(3))
        coord.sufferDamage(99, to: try chord(4))
        coord.ruleDamageDue = []
        rules.evaluateTurnRules(.turnStart, for: night)
        rules.evaluateTurnRules(.turnStart, for: brute)
        XCTAssertEqual(night.health, before + 1)
        XCTAssertTrue(coord.ruleDamageDue.isEmpty)
    }

    /// Pit of Souls: the Hungry Soul has Shield 5 on top of an elite Living Bones' own, less 1
    /// for every other Living Bones on the map, never below none.
    func testTheHungrySoulsShieldFallsWithTheBonesAroundIt() async throws {
        let sim = try simulator("62")
        let coord = sim.coord
        for piece in pieces(sim) { coord.boardState.removePiece(piece) }
        let free = coord.boardState.cells.keys.sorted().filter(coord.isEmptyHex)
        let soul = try XCTUnwrap(coord.spawnMonster(name: "hungry-soul", type: .boss, at: free[0], origin: .placed))
        let bones = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "living-bones" })
        let own = try XCTUnwrap(bones.monsterData?.stat(for: .elite, at: bones.level)).actions?.first { $0.type == .shield }?.value?.intValue ?? 0
        XCTAssertEqual(try cardShield(sim, soul), 5 + own)
        XCTAssertEqual(coord.shield(of: soul), 5 + own, "no other Living Bones")
        for hex in free[1...2] { coord.spawnMonster(name: "living-bones", type: .normal, at: hex, origin: .spawned) }
        XCTAssertEqual(coord.shield(of: soul), 3 + own)

        let entity = try entity(sim, soul)
        entity.maxHealth = 40
        entity.health = 40
        await coord.performAttack(attacker: character(sim, 0), target: soul, attack: AttackParameters(value: 4 + own),
                                  drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(entity.health, 39, "one more than its shield")

        for hex in free[3...9] { coord.spawnMonster(name: "living-bones", type: .normal, at: hex, origin: .spawned) }
        XCTAssertEqual(coord.shield(of: soul), 0, "never below none")
        XCTAssertEqual(coord.shield(of: try XCTUnwrap(pieces(sim, named: "living-bones").first)), 0, "theirs is their own")
    }

    /// Bloody Shack: for each bone pile standing the Harvester has Shield 1 more, and heals
    /// C−1 as every round ends.
    func testBonePilesShieldAndHealTheHarvester() throws {
        let sim = try simulator("58")
        let coord = sim.coord
        revealAll(sim)
        let harvester = try XCTUnwrap(pieces(sim, named: "the-harvester").first)
        let piles = objectives(sim)
        XCTAssertEqual(piles.count, 4)
        let own = try cardShield(sim, harvester)
        XCTAssertEqual(coord.shield(of: harvester), own + 4)
        coord.sufferDamage(99, to: piles[0])
        XCTAssertEqual(coord.shield(of: harvester), own + 3)

        let entity = try entity(sim, harvester)
        entity.maxHealth = 30
        entity.health = 10
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(entity.health, 13, "C\u{2212}1 for each of three piles, with two characters")
        for pile in piles.dropFirst() { coord.sufferDamage(99, to: pile) }
        sim.gm.game.round = 2
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(entity.health, 13)
        XCTAssertEqual(coord.shield(of: harvester), own)
    }

    /// Corrupted Cove: the Giant Ooze has Shield 2 for each of four tokens and loses one each
    /// time an Ooze dies.
    func testTheGiantOozeLosesATokenWithEveryOoze() throws {
        let sim = try simulator("87")
        let coord = sim.coord
        revealAll(sim)
        let giant = try XCTUnwrap(pieces(sim, named: "giant-ooze").first)
        let own = try cardShield(sim, giant)
        XCTAssertEqual(coord.shield(of: giant), own + 8)
        coord.handleDeath(of: try XCTUnwrap(pieces(sim, named: "ooze").first))
        XCTAssertEqual(coord.shield(of: giant), own + 6)
        coord.handleDeath(of: try XCTUnwrap(pieces(sim, named: "black-imp").first))
        XCTAssertEqual(coord.shield(of: giant), own + 6, "only an Ooze takes a token")
        for _ in 0..<5 {
            let hex = try XCTUnwrap(coord.boardState.cells.keys.sorted().first(where: coord.isEmptyHex))
            coord.handleDeath(of: try XCTUnwrap(coord.spawnMonster(name: "ooze", type: .normal, at: hex, origin: .spawned)))
        }
        XCTAssertEqual(coord.shield(of: giant), own, "no tokens left, and no fewer")
    }

    // MARK: - What the brief says

    /// The brief says the rules the game enforces in the book's sense, not a guess from the data.
    func testTheBriefSaysTheWrittenRules() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        func rules(_ index: String) throws -> [String] {
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil })
            return ScenarioBrief.make(for: data, labels: gm.editionStore).rules
        }
        let voice = try rules("42")
        XCTAssertEqual(voice.count, 6, voice.joined(separator: " / "))
        XCTAssertTrue(voice.contains("Chord 1, while it stands: all monsters add +1 Attack to all their attacks."))
        let battlements = try rules("36")
        XCTAssertFalse(battlements.contains { $0.hasPrefix("More ") }, "who arrives is written out")
        XCTAssertTrue(battlements.contains { $0.contains("until the gate falls") })
        XCTAssertTrue(battlements.contains { $0.contains("twice the number of hit points") }, "the data's own text stays")
        XCTAssertTrue(try rules("84").contains { $0.contains("the Crystal") && $0.contains("no ally") })
        XCTAssertFalse(try rules("84").contains { $0.contains("fights on your side") })
        XCTAssertTrue(try rules("38").contains { $0.contains("fights on your side") }, "an escort still does")
        XCTAssertTrue(try rules("7").contains { $0.contains("Loot action") })
        XCTAssertTrue(try rules("93").contains("Each character starts the scenario with Immobilize."))
        XCTAssertTrue(try rules("87").contains { $0.contains("Curses") }, "what the data's own rules do is still said")
        XCTAssertTrue(try rules("3").contains { $0.hasPrefix("More Inox Guards") }, "and guessed where nothing is written")
    }
}
