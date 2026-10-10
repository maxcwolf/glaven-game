import XCTest
@testable import GlavenGameLib

/// Rules the game already enforced that no test would have caught breaking (the second rules
/// audit's list): spawn schedules and their ranks by the number of characters, setup effects,
/// round-start elements, goals and losses — each on its own scenario's board.
@MainActor
final class ScenarioEnforcedRuleTests: XCTestCase {

    private static let parties = [["brute", "spellweaver"], ["brute", "spellweaver", "cragheart"],
                                  ["brute", "spellweaver", "cragheart", "scoundrel"]]

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

    private func pieces(_ sim: ScenarioSimulator, named name: String? = nil) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter {
            if case .monster(let monster, _) = $0 { return name == nil || monster == name }
            return false
        }.sorted()
    }

    private func objectives(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .objective = $0 { return true }; return false }.sorted()
    }

    private func character(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ index: Int, on hex: HexCoord) {
        let board = sim.coord.boardState
        if let other = board.piece(at: hex), other != character(sim, index) { board.removePiece(other) }
        board.removePiece(character(sim, index))
        board.placePiece(character(sim, index), at: hex)
    }

    private func hexes(_ sim: ScenarioSimulator, _ marker: String) -> [HexCoord] {
        (sim.coord.boardState.markerHexes[marker] ?? []).sorted()
    }

    private func type(_ sim: ScenarioSimulator, _ piece: PieceID) -> MonsterType? {
        guard case .monster(let name, let standee) = piece else { return nil }
        return sim.coord.monsterEntity(name: name, standee: standee)?.type
    }

    private func name(_ piece: PieceID) -> String {
        if case .monster(let name, _) = piece { return name }
        return "\(piece)"
    }

    /// The letter a rule's spawn came in at (the rule marks what it spawns).
    private func letter(_ sim: ScenarioSimulator, _ piece: PieceID) -> String? {
        guard case .monster(let name, let standee) = piece else { return nil }
        return sim.coord.monsterEntity(name: name, standee: standee)?.markers.last
    }

    private enum Moment { case start, end }

    /// Who arrives when a round starts or ends, as "name rank@letter"; they are then taken off
    /// again so the next arrivals find their hexes free.
    private func arrivals(_ sim: ScenarioSimulator, _ moment: Moment, round: Int, keep: Bool = false) -> [String] {
        let before = Set(pieces(sim))
        sim.gm.game.round = round
        sim.gm.scenarioRulesManager.evaluateRules(phase: moment == .start ? .roundStart : .roundEnd)
        let arrived = pieces(sim).filter { !before.contains($0) }
        let described: [String] = arrived.map { piece in
            let hex = sim.coord.boardState.piecePositions[piece]
            let lettered = letter(sim, piece)
            let at = lettered.flatMap { sim.coord.boardState.markerHexes[$0] } ?? []
            // On its lettered hex, or beside it when that is taken.
            let placed = at.isEmpty || at.contains { $0.distance(to: hex ?? $0) <= 1 }
            return "\(name(piece)) \(type(sim, piece)?.rawValue ?? "?")@\(lettered ?? "?")\(placed ? "" : " (misplaced)")"
        }.sorted()
        if !keep { for piece in arrived { sim.coord.removePieceFromBoard(piece); entity(sim, piece)?.dead = true } }
        return described
    }

    private func entity(_ sim: ScenarioSimulator, _ piece: PieceID) -> GameMonsterEntity? {
        guard case .monster(let name, let standee) = piece else { return nil }
        return sim.coord.monsterEntity(name: name, standee: standee)
    }

    private func rank(_ ranks: String, for count: Int) -> String {
        // "n/e/e" for 2/3/4 characters
        let parts = ranks.split(separator: "/")
        return parts[count - 2] == "e" ? "elite" : "normal"
    }

    // MARK: - Spawn schedules

    /// Inox Encampment: an Inox Guard at (a) as every odd round ends (two characters) or as every
    /// round begins (three or four) — until door 1 is opened.
    func testTheEncampmentsGuardsStopComingWhenTheDoorOpens() throws {
        for party in Self.parties {
            let sim = try simulator("3", characters: party)
            let count = party.count
            // (With four characters every Inox Guard standee is on the map from the start, and a
            // spawn with no standee left brings nothing: free one.)
            if let guardPiece = pieces(sim, named: "inox-guard").first { sim.coord.handleDeath(of: guardPiece) }
            if count == 2 {
                XCTAssertEqual(arrivals(sim, .end, round: 1), ["inox-guard normal@a"])
                XCTAssertEqual(arrivals(sim, .end, round: 2), [], "only odd rounds")
                XCTAssertEqual(arrivals(sim, .start, round: 3), [], "and as they end")
                XCTAssertEqual(arrivals(sim, .end, round: 3), ["inox-guard normal@a"])
            } else {
                XCTAssertEqual(arrivals(sim, .start, round: 2), ["inox-guard normal@a"], "\(count)")
                XCTAssertEqual(arrivals(sim, .end, round: 2), [], "\(count): as rounds begin only")
                XCTAssertEqual(arrivals(sim, .start, round: 3), ["inox-guard normal@a"], "\(count)")
            }
            // Door 1 leads to the back cave (E1b).
            let door = try XCTUnwrap(sim.coord.boardState.doors.first { $0.childTileRef.lowercased() == "e1b" })
            sim.coord.openDoor(at: door.coord)
            sim.gm.scenarioRulesManager.evaluateRules()
            XCTAssertEqual(arrivals(sim, .end, round: 5).filter { $0.hasSuffix("@a") }, [], "\(count): none after the door")
            XCTAssertEqual(arrivals(sim, .start, round: 6).filter { $0.hasSuffix("@a") }, [], "\(count): none after the door")
        }
    }

    /// Ruinous Rift: one demon after each of the first two rounds, then two a round — at d and e
    /// after odd rounds, b and c after even ones — the types in turn; Wind, Sun and Flame Demons
    /// are elite for three characters, all for four.
    func testTheRiftsDemonsComeInTheirOrder() throws {
        let cycle = ["night-demon", "wind-demon", "frost-demon", "sun-demon", "earth-demon", "flame-demon"]
        let eliteForThree: Set<String> = ["wind-demon", "sun-demon", "flame-demon"]
        for party in Self.parties {
            let sim = try simulator("27", characters: party)
            var next = 0
            for round in 1...9 {
                let letters = round == 1 ? ["b"] : round == 2 ? ["c"] : (round % 2 == 1 ? ["d", "e"] : ["b", "c"])
                let expected: [String] = letters.map { letter in
                    let name = cycle[next % cycle.count]
                    next += 1
                    let elite = party.count == 4 || (party.count == 3 && eliteForThree.contains(name))
                    return "\(name) \(elite ? "elite" : "normal")@\(letter)"
                }.sorted()
                XCTAssertEqual(arrivals(sim, .end, round: round), expected, "\(party.count) characters, round \(round)")
            }
        }
    }

    /// Plane of Night, Section 1: once the last room is open a Night Demon comes at (b) as odd
    /// rounds end (elite for four) and at (c) as even rounds end (elite for three or four).
    func testThePlanesNightDemonsComeOnceTheLastRoomIsOpen() throws {
        for party in Self.parties {
            let sim = try simulator("31", characters: party)
            XCTAssertEqual(arrivals(sim, .end, round: 1), [], "not before door 1 is opened")
            revealAll(sim)
            XCTAssertEqual(arrivals(sim, .end, round: 3), ["night-demon \(rank("n/n/e", for: party.count))@b"], "\(party.count)")
            XCTAssertEqual(arrivals(sim, .end, round: 4), ["night-demon \(rank("n/e/e", for: party.count))@c"], "\(party.count)")
        }
    }

    /// Battlements B: a demon as every round ends — Flame at a, Earth at b, Frost at c, Wind at
    /// d, and round again; Flame and Frost are elite for three characters, all for four.
    func testTheBattlementsDemonsComeRoundTheGate() throws {
        let rota = [("flame-demon", "a", "n/e/e"), ("earth-demon", "b", "n/n/e"), ("frost-demon", "c", "n/e/e"), ("wind-demon", "d", "n/n/e")]
        for party in Self.parties {
            let sim = try simulator("36", characters: party)
            for round in 1...8 {
                let (name, letter, ranks) = rota[(round - 1) % 4]
                XCTAssertEqual(arrivals(sim, .end, round: round).filter { !$0.hasPrefix("prime-demon") },
                               ["\(name) \(rank(ranks, for: party.count))@\(letter)"], "\(party.count) characters, round \(round)")
            }
        }
    }

    /// Forgotten Crypt: each numbered door brings its section's monsters — Cultists at (c), Living
    /// Spirits at (d), Living Bones at (e), one or two by the number of characters.
    func testTheCryptsDoorsBringTheirSections() throws {
        for (party, counts) in zip(Self.parties, [[1, 1, 1], [2, 1, 2], [2, 2, 2]]) {
            let sim = try simulator("19", characters: party)
            func lettered(_ name: String, _ letter: String) -> [PieceID] { pieces(sim, named: name).filter { self.letter(sim, $0) == letter } }
            XCTAssertTrue(lettered("cultist", "c").isEmpty)
            revealAll(sim)
            XCTAssertEqual(lettered("cultist", "c").count, counts[0], "\(party.count) characters")
            XCTAssertEqual(lettered("living-spirit", "d").count, counts[1], "\(party.count) characters")
            XCTAssertEqual(lettered("living-bones", "e").count, counts[2], "\(party.count) characters")
            for piece in lettered("cultist", "c") + lettered("living-spirit", "d") + lettered("living-bones", "e") {
                XCTAssertEqual(type(sim, piece), .normal)
            }
        }
    }

    /// Investigation, Section 3: opening the storage room brings two City Guards at (a) — two
    /// normal, one of each, or two elite.
    func testTheStorageRoomBringsGuards() throws {
        for (party, ranks) in zip(Self.parties, [[MonsterType.normal, .normal], [.elite, .normal], [.elite, .elite]]) {
            let sim = try simulator("57", characters: party)
            func guards() -> [PieceID] { pieces(sim, named: "city-guard").filter { letter(sim, $0) == "a" } }
            XCTAssertTrue(guards().isEmpty)
            let door = try XCTUnwrap(sim.coord.boardState.doors.first { $0.childTileRef.lowercased() == "a1a" }, "door 3")
            sim.coord.openDoor(at: door.coord)
            XCTAssertEqual(guards().compactMap { type(sim, $0) }.sorted { $0.rawValue < $1.rawValue }, ranks.sorted { $0.rawValue < $1.rawValue },
                           "\(party.count) characters")
            XCTAssertTrue(guards().allSatisfy { sim.coord.boardState.cells[sim.coord.boardState.piecePositions[$0]!]?.tileRef.lowercased() == "f1b" },
                          "on the corridor")
        }
    }

    /// Pit of Souls: a Living Bones at (a) and at (b) as every round begins — both normal, (a)
    /// elite, or both elite.
    func testThePitsLivingBonesComeEveryRound() throws {
        for (party, expected) in zip(Self.parties, [["living-bones normal@a", "living-bones normal@b"],
                                                    ["living-bones elite@a", "living-bones normal@b"],
                                                    ["living-bones elite@a", "living-bones elite@b"]]) {
            let sim = try simulator("62", characters: party)
            XCTAssertEqual(arrivals(sim, .start, round: 2), expected, "\(party.count) characters")
            XCTAssertEqual(arrivals(sim, .start, round: 3), expected, "every round")
            XCTAssertEqual(arrivals(sim, .end, round: 3), [])
        }
    }

    /// Chained Isle: normal Living Spirits as rounds end — at (a) after odd and (b) after even
    /// rounds for two characters; (a), then (a) and (b), for three; both every round for four.
    func testTheIslesSpiritsRise() throws {
        let a = "living-spirit normal@a", b = "living-spirit normal@b"
        for (party, expected) in zip(Self.parties, [[[a], [b]], [[a], [a, b]], [[a, b], [a, b]]]) {
            let sim = try simulator("70", characters: party)
            XCTAssertEqual(arrivals(sim, .end, round: 1), expected[0], "\(party.count) characters, odd")
            XCTAssertEqual(arrivals(sim, .end, round: 2), expected[1], "\(party.count) characters, even")
            XCTAssertEqual(arrivals(sim, .end, round: 3), expected[0], "\(party.count) characters, odd")
            XCTAssertEqual(arrivals(sim, .start, round: 4), [])
        }
    }

    /// Oozing Grove: one tree in turn — a, b, c, a… — brings an Ooze as each round ends: normal
    /// for two characters, normal after odd and elite after even rounds for three, elite for
    /// four. A destroyed tree keeps its place in the order and brings nothing.
    func testTheGrovesTreesBringOozesInTurn() throws {
        for party in Self.parties {
            let sim = try simulator("72", characters: party)
            revealAll(sim)
            for round in 1...6 {
                let tree = ["a", "b", "c"][(round - 1) % 3]
                let elite = party.count == 4 || (party.count == 3 && round % 2 == 0)
                XCTAssertEqual(arrivals(sim, .end, round: round), ["ooze \(elite ? "elite" : "normal")@\(tree)"],
                               "\(party.count) characters, round \(round)")
            }
            // Tree (a) falls: its rounds bring nothing; the others keep theirs.
            let treeA = try XCTUnwrap(objectives(sim).first {
                (sim.coord.entity(for: $0) as? GameObjectiveEntity).map { $0.marker == "a" || $0.markers.contains("a") } == true
            })
            sim.coord.sufferDamage(999, to: treeA)
            XCTAssertEqual(arrivals(sim, .end, round: 7), [], "tree (a) is gone")
            XCTAssertEqual(arrivals(sim, .end, round: 8).count, 1, "tree (b) still stands")
        }
    }

    /// Merchant Ship: door 1 opens as the third round ends and door 2 as the sixth does, each
    /// bringing its Deep Terrors.
    func testTheShipsDoorsOpenByTheRound() throws {
        for (party, first, second) in [(Self.parties[0], ["deep-terror normal@a"], ["deep-terror normal@c", "deep-terror normal@c"]),
                                       (Self.parties[1], ["deep-terror elite@a"], ["deep-terror normal@c", "deep-terror normal@c"]),
                                       (Self.parties[2], ["deep-terror normal@b", "deep-terror normal@b"], ["deep-terror elite@c", "deep-terror elite@c"])] {
            let sim = try simulator("74", characters: party)
            let coord = sim.coord
            func closed() -> Int { coord.boardState.doors.filter { !$0.isOpen }.count }
            func terrors() -> [String] {
                pieces(sim, named: "deep-terror").filter { letter(sim, $0) != nil }
                    .map { "deep-terror \(type(sim, $0)?.rawValue ?? "?")@\(letter(sim, $0) ?? "?")" }.sorted()
            }
            XCTAssertEqual(closed(), 2)
            sim.gm.game.round = 2
            coord.updateLocks(roundEnded: true)
            XCTAssertEqual(closed(), 2, "not yet")
            sim.gm.game.round = 3
            coord.updateLocks(roundEnded: true)
            XCTAssertEqual(closed(), 1, "door 1 as round 3 ends")
            XCTAssertEqual(terrors(), first, "\(party.count) characters")
            sim.gm.game.round = 6
            coord.updateLocks(roundEnded: true)
            XCTAssertEqual(closed(), 0, "door 2 as round 6 ends")
            XCTAssertEqual(terrors(), (first + second).sorted(), "\(party.count) characters")
        }
    }

    /// Overgrown Graveyard, Section 1: the regent's grave (c) dug up lets out the Bloated Regent.
    func testTheRegentRisesFromItsGrave() throws {
        let sim = try simulator("75")
        revealAll(sim)
        XCTAssertTrue(pieces(sim, named: "bloated-regent").isEmpty)
        let grave = try XCTUnwrap(objectives(sim).first {
            (sim.coord.entity(for: $0) as? GameObjectiveEntity).map { $0.marker == "c" || $0.markers.contains("c") } == true
        }, "grave (c)")
        let stood = try XCTUnwrap(sim.coord.boardState.piecePositions[grave])
        sim.coord.sufferDamage(999, to: grave)
        let regent = try XCTUnwrap(pieces(sim, named: "bloated-regent").first)
        XCTAssertLessThanOrEqual(try XCTUnwrap(sim.coord.boardState.piecePositions[regent]).distance(to: stood), 1, "where the grave was")
        XCTAssertNil(sim.coord.pendingResult, "it is still to be killed, and the other graves dug up")
    }

    /// Demonic Rift, Section 1: the Living Spirits at (b) are elite for three characters, those
    /// at (c) normal; all normal for two, all elite for four.
    func testTheRiftsSpiritsHaveTheirRanks() throws {
        for (party, ranks) in zip(Self.parties, [["b": MonsterType.normal, "c": .normal], ["b": .elite, "c": .normal], ["b": .elite, "c": .elite]]) {
            let sim = try simulator("90", characters: party)
            for piece in pieces(sim) { sim.coord.handleDeath(of: piece) }
            // They come once a character stands in each room: one crosses by the altars.
            let board = sim.coord.boardState
            let across = try XCTUnwrap(board.neighbors(of: board.crossings[1]).filter { board.isPassable($0) && !board.isOccupied($0) }.sorted().first)
            board.piecePositions[.character(sim.gm.game.characters[0].id)] = across
            sim.gm.scenarioRulesManager.evaluateRules()
            let spirits = pieces(sim, named: "living-spirit")
            XCTAssertEqual(spirits.count, 4, "\(party.count) characters")
            for spirit in spirits {
                let letter = try XCTUnwrap(letter(sim, spirit))
                XCTAssertEqual(type(sim, spirit), ranks[letter], "\(party.count) characters, (\(letter))")
            }
            XCTAssertEqual(spirits.filter { letter(sim, $0) == "b" }.count, 2)
        }
    }

    // MARK: - Setup and round-start effects

    /// Ruinous Crypt starts everyone Disarmed, Shadow Weald Muddled.
    func testCharactersStartDisarmedOrMuddled() throws {
        for (scenario, condition) in [("5", ConditionName.disarm), ("48", .muddle)] {
            let sim = try simulator(scenario)
            sim.gm.game.round = 1
            sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
            for character in sim.gm.game.characters {
                XCTAssertTrue(character.entityConditions.contains { $0.name == condition }, "#\(scenario): \(character.name) starts with \(condition)")
            }
            // Only as the scenario starts.
            for character in sim.gm.game.characters { character.entityConditions.removeAll() }
            sim.gm.game.round = 2
            sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
            XCTAssertTrue(sim.gm.game.characters.allSatisfy { $0.entityConditions.isEmpty }, "#\(scenario): not again in round 2")
        }
    }

    /// The elements a scenario sets as every round starts: Dark strong and Light inert on the
    /// Plane of Night; Ice strong and Fire inert at the Treacherous Divide; Light and Dark strong
    /// and the other four inert in the Temple of the Eclipse.
    func testElementsAreSetAsEveryRoundStarts() throws {
        let cases: [(String, [ElementType: ElementState])] = [
            ("31", [.dark: .strong, .light: .inert]),
            ("39", [.ice: .strong, .fire: .inert]),
            ("81", [.light: .strong, .dark: .strong, .fire: .inert, .ice: .inert, .air: .inert, .earth: .inert]),
        ]
        for (scenario, expected) in cases {
            let sim = try simulator(scenario)
            for round in 1...3 {
                // Whatever the round before left behind.
                for index in sim.gm.game.elementBoard.indices {
                    sim.gm.game.elementBoard[index].state = expected[sim.gm.game.elementBoard[index].type] == .strong ? .inert : .waning
                }
                sim.gm.game.round = round
                sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
                for element in sim.gm.game.elementBoard {
                    guard let state = expected[element.type] else { continue }
                    XCTAssertEqual(element.state, state, "#\(scenario) round \(round): \(element.type)")
                }
            }
        }
    }

    /// Outer Ritual Chamber: the Living Corpses are two levels above the scenario's (never above
    /// 7); everything else is at the scenario's level.
    func testTheRitualChambersCorpsesAreTwoLevelsUp() throws {
        let sim = try simulator("28")
        revealAll(sim)
        let level = sim.gm.game.level
        let corpses = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "living-corpse" })
        XCTAssertFalse(corpses.aliveEntities.isEmpty)
        XCTAssertEqual(corpses.level, min(7, level + 2))
        let corpse = try XCTUnwrap(corpses.aliveEntities.first)
        let card = try XCTUnwrap(corpses.monsterData?.stat(for: corpse.type, at: min(7, level + 2)))
        let usual = try XCTUnwrap(corpses.monsterData?.stat(for: corpse.type, at: level))
        XCTAssertEqual(corpse.maxHealth, card.healthValue(characterCount: 2), "and have that level's hit points")
        XCTAssertNotEqual(card.healthValue(characterCount: 2), usual.healthValue(characterCount: 2))
        for other in sim.gm.game.monsters where other.name != "living-corpse" && !other.aliveEntities.isEmpty {
            XCTAssertEqual(other.level, level, other.name)
        }
    }

    /// Gloomhaven Square A and B: the monster types the scenario names fight on the party's side,
    /// and only those.
    func testTheSquaresAlliesAreTheScenariosOwn() throws {
        for (scenario, allies) in [("11", Set(["living-bones", "living-corpse"])), ("12", Set(["city-guard", "city-archer"]))] {
            let sim = try simulator(scenario)
            XCTAssertEqual(Set(sim.gm.game.scenario?.data.allies ?? []), allies, "#\(scenario): written in its data")
            revealAll(sim)
            let onBoard = sim.gm.game.monsters.filter { !$0.aliveEntities.isEmpty }
            XCTAssertTrue(allies.isSubset(of: Set(onBoard.map(\.name))), "#\(scenario): they are set up")
            for monster in onBoard {
                XCTAssertEqual(MonsterAI.isAllyFaction(monster), allies.contains(monster.name), "#\(scenario): \(monster.name)")
            }
            let ally = try XCTUnwrap(pieces(sim).first { allies.contains(name($0)) })
            let enemy = try XCTUnwrap(pieces(sim).first { !allies.contains(name($0)) })
            XCTAssertFalse(sim.coord.areEnemies(character(sim, 0), ally))
            XCTAssertTrue(sim.coord.areEnemies(character(sim, 0), enemy))
            XCTAssertTrue(sim.coord.areEnemies(ally, enemy))
        }
    }

    /// Syndicate Hideout: the Cultists summon elite Giant Vipers, not Living Bones.
    func testTheHideoutsCultistsSummonVipers() throws {
        let sim = try simulator("89")
        revealAll(sim)
        sim.gm.scenarioRulesManager.evaluateRules()
        let cultists = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "cultist" })
        XCTAssertEqual(cultists.deckOverride, "cultist-scenario-89")
        let deck = sim.gm.editionStore.abilities(forDeck: "cultist-scenario-89", edition: "gh")
        func summons(_ actions: [ActionModel]) -> [MonsterSummonSpec] {
            actions.flatMap { ($0.monsterSummons ?? []) + summons($0.subActions ?? []) }
        }
        let summoned = deck.flatMap { summons($0.actions ?? []) }
        XCTAssertFalse(summoned.isEmpty, "the deck has its summons")
        for standee in summoned {
            XCTAssertEqual(standee.name, "giant-viper")
            XCTAssertEqual(standee.type, .elite, "elite for any number of characters")
        }
        // And the ordinary Cultist deck's summons are Living Bones — so the override matters.
        let usual = sim.gm.editionStore.abilities(forDeck: "cultist", edition: "gh").flatMap { summons($0.actions ?? []) }
        XCTAssertTrue(usual.contains { $0.name == "living-bones" })
    }

    // MARK: - Goals and losses

    /// Echo Chamber: the goal is every door opened — with every enemy alive, and not a door less.
    func testOpeningEveryDoorWinsTheEchoChamber() throws {
        let sim = try simulator("24")
        let coord = sim.coord
        var opened = 0
        for _ in 0..<40 {
            guard let door = coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
            coord.checkVictoryDefeat(turnEnded: true)
            XCTAssertNil(coord.pendingResult, "a door is still shut (\(opened) opened)")
            coord.openDoor(at: door.coord)
            opened += 1
        }
        XCTAssertGreaterThanOrEqual(opened, 5, "the map's five doors")
        XCTAssertTrue(coord.boardState.doors.allSatisfy(\.isOpen))
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
        XCTAssertFalse(pieces(sim).isEmpty, "with enemies still standing")
    }

    /// Slave Pens and Crystalline Cave: the death of the Orchid, the destruction of the crystal,
    /// loses the scenario.
    func testWhatIsToBeProtectedLosesByItsDeath() throws {
        for scenario in ["38", "84"] {
            let sim = try simulator(scenario)
            let ward = try XCTUnwrap(objectives(sim).first, "#\(scenario)")
            sim.coord.sufferDamage(1, to: ward)
            XCTAssertNil(sim.coord.pendingResult, "#\(scenario): hurt isn't lost")
            sim.coord.sufferDamage(999, to: ward)
            XCTAssertEqual(sim.coord.pendingResult, .defeat, "#\(scenario)")
        }
    }

    /// Tribal Assault: Redthorn acts first every round (initiative 01) with Move 3, Attack 3 at
    /// Range 3, on the party's side.
    func testRedthornTakesHisTurn() async throws {
        let sim = try ScenarioSimulator(scenario: "44", options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: true))
        let redthorn = try XCTUnwrap(sim.gm.game.objectives.first { $0.name == "Redthorn" })
        XCTAssertTrue(redthorn.escort)
        XCTAssertEqual(redthorn.initiative, 1)
        XCTAssertEqual(redthorn.escortMove, 3)
        XCTAssertEqual(redthorn.escortAttack, 3)
        XCTAssertEqual(redthorn.escortRange, 3)
        let piece = try XCTUnwrap(redthorn.entities.first.map { PieceID.objective(id: $0.number) })
        XCTAssertFalse(sim.coord.areEnemies(character(sim, 0), piece))
        let stood = sim.coord.boardState.piecePositions[piece]
        await sim.play(rounds: 1)
        let log = sim.transcript
        let order = try XCTUnwrap(log.first { $0.hasPrefix("Turn order:") })
        XCTAssertTrue(order.hasPrefix("Turn order: Redthorn 1,"), order)
        XCTAssertTrue(log.contains { $0.hasPrefix("Redthorn\u{2019}s turn") })
        let acted = sim.coord.boardState.piecePositions[piece] != stood || log.contains { $0.hasPrefix("Redthorn attacks") }
        XCTAssertTrue(acted, "he moves toward an enemy or attacks one")
    }

    /// Crypt Basement: won as the tenth round ends, and not a round sooner.
    func testTheBasementIsWonAsTheTenthRoundEnds() throws {
        let sim = try simulator("53")
        sim.gm.game.round = 9
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult)
        sim.gm.game.round = 10
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundStart)
        sim.coord.checkVictoryDefeat()
        XCTAssertNil(sim.coord.pendingResult, "the tenth round is still to be played")
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)
    }

    /// Bandit's Wood: lost only when all three captive Orchids are dead.
    func testTheWoodIsLostWhenAllThreeCaptivesDie() throws {
        let sim = try simulator("56")
        revealAll(sim)
        let captives = objectives(sim)
        XCTAssertEqual(captives.count, 3)
        for captive in captives.dropLast() {
            sim.coord.sufferDamage(999, to: captive)
            sim.coord.checkVictoryDefeat()
            XCTAssertNil(sim.coord.pendingResult, "one still lives")
        }
        sim.coord.sufferDamage(999, to: captives[2])
        sim.coord.checkVictoryDefeat()
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    private func lootEveryGoalTreasure(_ sim: ScenarioSimulator, by index: Int = 0) {
        let chests = sim.coord.boardState.cells.values
            .filter { $0.overlay == .treasure && $0.treasureID == BoardCoordinator.goalTreasureID }.map(\.coord).sorted()
        for chest in chests {
            stand(sim, index, on: chest)
            sim.coord.lootHexes(for: character(sim, index), coords: [chest], byLootAction: true)
        }
    }

    /// Alchemy Lab: won with every treasure tile looted and everyone back on the entrance; lost
    /// by an exhaustion before the last tile is looted or away from the entrance, or when the
    /// twelfth round ends.
    func testTheLabsGoalAndItsLosses() throws {
        // The goal.
        var sim = try simulator("60")
        revealAll(sim)
        let entrance = sim.coord.boardState.startingLocations
        stand(sim, 0, on: entrance[0])
        stand(sim, 1, on: entrance[1])
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult, "the treasure first")
        lootEveryGoalTreasure(sim)
        stand(sim, 1, on: entrance[1])
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult, "one is still away from the entrance")
        stand(sim, 0, on: entrance[0])
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .victory)

        // Exhausted before the treasure is looted — even on the entrance.
        sim = try simulator("60")
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)

        // Exhausted away from the entrance, the treasure looted.
        sim = try simulator("60")
        revealAll(sim)
        lootEveryGoalTreasure(sim)
        XCTAssertFalse(sim.coord.boardState.startingLocations.contains(try XCTUnwrap(sim.coord.boardState.piecePositions[character(sim, 0)])))
        sim.coord.exhaust(sim.gm.game.characters[0], reason: "test")
        XCTAssertEqual(sim.coord.pendingResult, .defeat)

        // The twelfth round ends.
        sim = try simulator("60")
        sim.gm.game.round = 11
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(sim.coord.pendingResult)
        sim.gm.game.round = 12
        sim.gm.scenarioRulesManager.evaluateRules(phase: .roundEnd)
        sim.coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    /// Harried Village: seven villagers at the docks win it; five killed lose it.
    func testSevenVillagersSavedWinAndFiveKilledLose() throws {
        var sim = try simulator("86")
        revealAll(sim)
        let docks = try XCTUnwrap(hexes(sim, "b").first)
        var villagers = objectives(sim)
        XCTAssertEqual(villagers.count, 11)
        for (saved, villager) in villagers.prefix(7).enumerated() {
            XCTAssertNil(sim.coord.pendingResult, "\(saved) saved")
            sim.coord.boardState.removePiece(villager)
            if let other = sim.coord.boardState.piece(at: docks) { sim.coord.boardState.removePiece(other) }
            sim.coord.boardState.placePiece(villager, at: docks)
            sim.coord.noteEscortArrival(villager)
            XCTAssertFalse(sim.coord.isOnBoard(villager), "off the map, safe")
        }
        XCTAssertEqual(sim.coord.pendingResult, .victory)

        sim = try simulator("86")
        revealAll(sim)
        villagers = objectives(sim)
        for (killed, villager) in villagers.prefix(5).enumerated() {
            XCTAssertNil(sim.coord.pendingResult, "\(killed) killed")
            sim.coord.sufferDamage(999, to: villager)
        }
        XCTAssertEqual(sim.coord.pendingResult, .defeat)
    }

    // MARK: - Locks

    /// Clockwork Cove: each plate holds its own doors open — (a) door 1; (b) doors 1 and f; (c)
    /// f and g; (d) g and h.
    func testEachPlateOfTheCoveHoldsItsDoors() throws {
        let sim = try simulator("66")
        let coord = sim.coord
        revealAll(sim)
        coord.updateLocks()
        let held = [("j1b", "c1a"), ("c1a", "d1a"), ("d1a", "d2a"), ("d2a", "c2b")]   // doors 1, f, g, h
        func open() -> [Bool] {
            held.map { pair in
                let doors = coord.boardState.doors.filter { Set([($0.fromTileRef ?? "").lowercased(), $0.childTileRef.lowercased()]) == [pair.0, pair.1] }
                XCTAssertFalse(doors.isEmpty, "\(pair)")
                return doors.allSatisfy { !coord.boardState.isClosedDoor($0.coord) }
            }
        }
        // Off every plate, all four are shut.
        let nowhere = try XCTUnwrap(coord.boardState.startingLocations.first { !coord.pressurePlateHexes.contains($0) })
        stand(sim, 0, on: nowhere)
        stand(sim, 1, on: try XCTUnwrap(nowhere.neighbors.first { coord.isEmptyHex($0) && !coord.pressurePlateHexes.contains($0) }))
        coord.updateLocks()
        XCTAssertEqual(open(), [false, false, false, false])
        for (plate, expected) in [("a", [true, false, false, false]), ("b", [true, true, false, false]),
                                  ("c", [false, true, true, false]), ("d", [false, false, true, true])] {
            stand(sim, 0, on: try XCTUnwrap(hexes(sim, plate).first, "plate \(plate)"))
            coord.updateLocks()
            XCTAssertEqual(open(), expected, "plate (\(plate))")
        }
        // Two plates held at once keep both their doors.
        stand(sim, 0, on: try XCTUnwrap(hexes(sim, "a").first))
        stand(sim, 1, on: try XCTUnwrap(hexes(sim, "d").first))
        coord.updateLocks()
        XCTAssertEqual(open(), [true, false, true, true])
    }

    /// Well of the Unfortunate: door 1 stays locked until a character ends a turn on plate (b).
    func testTheWellsDoorOpensFromItsPlate() throws {
        let sim = try simulator("69")
        let coord = sim.coord
        for _ in 0..<10 {
            guard hexes(sim, "b").isEmpty,
                  let door = coord.boardState.doors.first(where: { !$0.isOpen && !coord.boardState.isLockedDoor($0.coord) }) else { break }
            coord.openDoor(at: door.coord)
        }
        let locked = coord.boardState.doors.filter { coord.boardState.isLockedDoor($0.coord) }
        XCTAssertEqual(locked.count, 1, "door 1")
        XCTAssertEqual(locked.first?.childTileRef.lowercased(), "j1a")
        let plate = try XCTUnwrap(hexes(sim, "b").first)
        stand(sim, 0, on: plate)
        coord.updateLocks()
        XCTAssertTrue(coord.boardState.isLockedDoor(locked[0].coord), "standing there isn't yet ending a turn there")
        coord.updateLocks(turnEnded: true)
        XCTAssertFalse(coord.boardState.isClosedDoor(locked[0].coord))
        XCTAssertTrue(coord.boardState.visibleRooms.contains { $0.lowercased() == "j1a" })
    }

    // MARK: - Every boss is somewhere

    /// Every scenario whose goal is to kill a named monster names one the scenario brings: set up
    /// in one of its rooms, spawned by a rule, or a boss that appears by itself.
    func testEveryBossToKillIsBroughtByItsScenario() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        var checked = 0
        for (index, placements) in ScenarioPlacementStore.shared.all().sorted(by: { $0.key < $1.key }) {
            let goals = [placements.goal].compactMap { $0 } + (placements.goal?.either ?? [])
            let wanted = goals.flatMap { $0.kill ?? [] }
            guard !wanted.isEmpty else { continue }
            let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil }, index)
            var brought = Set((data.rooms ?? []).flatMap { ($0.monster ?? []).map { MonsterNameSpec($0.name).name } })
            for rule in (data.rules ?? []) + (placements.rules ?? []) {
                brought.formUnion((rule.spawns ?? []).map { MonsterNameSpec($0.monster.name).name })
            }
            brought.formUnion((placements.cycles ?? [:]).filter { $0.value.appears == true }.keys)
            brought.formUnion((placements.whenDestroyed ?? [:]).values.map { MonsterNameSpec($0.name).name })
            for name in wanted {
                checked += 1
                XCTAssertTrue(brought.contains(name), "#\(index): nothing sets up or spawns \(name)")
                XCTAssertNotNil(gm.editionStore.monsterData(name: name, edition: "gh"), "#\(index): no monster data for \(name)")
            }
        }
        XCTAssertGreaterThan(checked, 20)
    }
}
