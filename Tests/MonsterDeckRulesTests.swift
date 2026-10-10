import XCTest
import SwiftData
@testable import GlavenGameLib

/// Monster ability decks and the round around them: types that share a deck act on one card,
/// only types on the board draw, a type arriving mid-round draws for the round, and who a
/// monster focuses on when two enemies are as near (RND-5, MON-2, MON-10, MON-12).
@MainActor
final class MonsterDeckRulesTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    @discardableResult
    private func character(_ name: String, at hex: HexCoord, initiative: Int = 50) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        character.health = 30
        character.maxHealth = 30
        character.handCards = []
        character.initiative = initiative
        return character
    }

    @discardableResult
    private func monster(_ name: String, _ type: MonsterType = .normal, at hex: HexCoord) throws -> PieceID {
        try XCTUnwrap(coord.spawnMonster(name: name, type: type, at: hex, origin: .placed))
    }

    private func type(_ name: String) throws -> GameMonster {
        try XCTUnwrap(gm.game.monsters.first { $0.name == name }, "no \(name) in the game")
    }

    private func card(_ name: String) throws -> AbilityModel? {
        gm.monsterManager.currentAbility(for: try type(name))
    }

    /// Start a round (cards are drawn) and end it again.
    private func startRound() { gm.game.state = .draw; gm.roundManager.nextGameState() }
    private func endRound() { gm.game.state = .next; gm.roundManager.nextGameState() }

    // MARK: - Types that share a deck

    /// There is one Guard deck: Bandit Guards and City Guards on the board together act on the
    /// one card drawn for it, round after round, and it is reshuffled for both at once.
    func testGuardsOfTwoTypesActOnOneCardEveryRound() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        try monster("city-guard", at: HexCoord(7, 7))
        let (bandits, city) = (try type("bandit-guard"), try type("city-guard"))
        XCTAssertEqual(bandits.abilities, city.abilities, "one draw pile")
        var seen: [Int] = []
        var reshuffles = 0
        for round in 1...30 {
            startRound()
            let drawn = try XCTUnwrap(try card("bandit-guard"), "round \(round)")
            XCTAssertEqual(try card("city-guard")?.cardId, drawn.cardId, "round \(round): one card for both")
            XCTAssertEqual(city.drawnInitiative, bandits.drawnInitiative, "at the same initiative")
            XCTAssertEqual(city.ability, bandits.ability)
            seen.append(drawn.cardId ?? 0)
            endRound()
            XCTAssertEqual(bandits.abilities, city.abilities, "round \(round): still one pile")
            XCTAssertEqual(bandits.ability, city.ability)
            if drawn.shuffle == true {
                reshuffles += 1
                XCTAssertEqual(bandits.ability, -1, "reshuffled after its shuffle card")
                // Between two shuffles no card comes twice: one deck is being drawn down.
                XCTAssertEqual(Set(seen).count, seen.count, "cards since the last shuffle: \(seen)")
                seen = []
            }
            XCTAssertFalse(bandits.abilityDrawn || city.abilityDrawn)
        }
        XCTAssertGreaterThan(reshuffles, 0)
    }

    /// The Archer deck is another deck: its card is its own.
    func testADifferentDeckIsDrawnSeparately() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        try monster("bandit-archer", at: HexCoord(7, 7))
        try monster("city-archer", at: HexCoord(9, 9))
        XCTAssertTrue(gm.monsterManager.deckMates(of: try type("bandit-guard")).isEmpty)
        XCTAssertEqual(gm.monsterManager.deckMates(of: try type("bandit-archer")).map(\.name), ["city-archer"])
        startRound()
        XCTAssertEqual(try card("bandit-archer")?.cardId, try card("city-archer")?.cardId)
        let guardCards = Set(gm.monsterManager.abilities(for: try type("bandit-guard")).compactMap(\.cardId))
        XCTAssertTrue(guardCards.contains(try XCTUnwrap(try card("bandit-guard")?.cardId)))
        XCTAssertFalse(guardCards.contains(try XCTUnwrap(try card("bandit-archer")?.cardId)))
    }

    /// A type whose scenario gives it a deck of its own keeps it: the Cultists of #89 don't
    /// draw with the ordinary Cultist deck.
    func testATypeWithAScenarioDeckKeepsItsOwn() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("cultist", at: HexCoord(5, 5))
        try monster("cultist-scenario-78", at: HexCoord(7, 7))
        let (cultists, others) = (try type("cultist"), try type("cultist-scenario-78"))
        XCTAssertEqual(gm.monsterManager.deckMates(of: cultists).map(\.name), ["cultist-scenario-78"], "both name the Cultist deck")

        gm.monsterManager.applyScenarioStatEffect(StatEffectData(deck: "cultist-scenario-89"), to: cultists, charCount: 2)
        XCTAssertTrue(gm.monsterManager.deckMates(of: cultists).isEmpty, "a deck of its own")
        let position = others.ability
        gm.monsterManager.drawAbility(for: cultists)
        XCTAssertTrue(cultists.abilityDrawn)
        XCTAssertFalse(others.abilityDrawn)
        XCTAssertEqual(others.ability, position, "the Cultist deck wasn't drawn from")
    }

    /// A type that enters play after its deck's card was revealed acts on that card: nothing
    /// more is drawn.
    func testATypeArrivingLaterInTheRoundJoinsItsDecksCard() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        startRound()
        let bandits = try type("bandit-guard")
        let (drawn, position) = (try XCTUnwrap(try card("bandit-guard")?.cardId), bandits.ability)

        try monster("city-guard", at: HexCoord(7, 7))
        let city = try type("city-guard")
        XCTAssertFalse(city.abilityDrawn, "placed off-turn: the coordinator draws for it mid-round")
        gm.monsterManager.drawAbility(for: city)
        XCTAssertEqual(try card("city-guard")?.cardId, drawn)
        XCTAssertEqual(bandits.ability, position, "the deck's card for the round is the one already out")
    }

    /// The deck runs out with no shuffle card drawn: it is reshuffled once, for every type on it.
    func testASharedDeckThatRunsOutIsReshuffledForBoth() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        try monster("inox-guard", at: HexCoord(7, 7))
        let (bandits, inox) = (try type("bandit-guard"), try type("inox-guard"))
        let deck = gm.monsterManager.abilities(for: bandits)
        let plain = deck.indices.filter { deck[$0].shuffle != true }
        XCTAssertEqual(deck.count, 8)
        // The pile holds only the cards without the shuffle icon, in order.
        bandits.abilities = plain
        bandits.ability = -1
        inox.abilities = plain
        inox.ability = -1
        for index in plain {
            startRound()
            XCTAssertEqual(gm.monsterManager.currentAbilityCardIndex(for: bandits), index)
            XCTAssertEqual(gm.monsterManager.currentAbilityCardIndex(for: inox), index)
            endRound()
            XCTAssertEqual(bandits.abilities, plain, "no shuffle card: no reshuffle")
        }
        startRound()   // nothing left to draw
        XCTAssertEqual(bandits.abilities.sorted(), Array(deck.indices), "all eight cards are back")
        XCTAssertEqual(bandits.ability, 0, "and the first of them is drawn")
        XCTAssertEqual(inox.abilities, bandits.abilities)
        XCTAssertEqual(try card("inox-guard")?.cardId, try card("bandit-guard")?.cardId)
    }

    /// A game saved when every type had a pile of its own still loads, and its Guards come to
    /// one card with the next draw.
    func testAnOlderSaveWithADeckPerTypeStillLoads() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        try monster("city-guard", at: HexCoord(7, 7))
        // As the older game left them: two orders, two places.
        try type("bandit-guard").abilities = [0, 1, 2, 3, 4, 5, 6, 7]
        try type("bandit-guard").ability = 2
        try type("city-guard").abilities = [7, 6, 5, 4, 3, 2, 1, 0]
        try type("city-guard").ability = 4
        var saved = gm.game.toSnapshot()
        saved.boardSnapshot = coord.snapshot()
        let snapshot = try JSONDecoder().decode(GameSnapshot.self, from: JSONEncoder().encode(saved))
        gm.game.restore(from: snapshot, editionStore: gm.editionStore, boardCoordinator: coord)

        let (bandits, city) = (try type("bandit-guard"), try type("city-guard"))
        XCTAssertEqual(bandits.abilities, [0, 1, 2, 3, 4, 5, 6, 7], "loaded as saved")
        XCTAssertEqual(city.abilities, [7, 6, 5, 4, 3, 2, 1, 0])
        startRound()
        XCTAssertEqual(try card("city-guard")?.cardId, try card("bandit-guard")?.cardId, "one card from now on")
        XCTAssertEqual(city.abilities, bandits.abilities)
        endRound()
        startRound()
        XCTAssertEqual(try card("city-guard")?.cardId, try card("bandit-guard")?.cardId)
    }

    /// Through a real round on the board: both Guard types take their turns on the one card, at
    /// one initiative, one type after the other, elites before normals within each.
    func testTwoGuardTypesTakeTheirTurnsOnTheSameCard() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 3,
                                                                       autoResolvePrompts: true))
        let coord = sim.coord
        let free = coord.boardState.cells.keys.sorted().filter(coord.isEmptyHex)
        XCTAssertNotNil(coord.spawnMonster(name: "city-guard", type: .normal, at: free[0], origin: .placed))
        XCTAssertNotNil(coord.spawnMonster(name: "city-guard", type: .elite, at: free[1], origin: .placed))
        var pairs: [(bandit: Int?, city: Int?)] = []
        var acting: [String] = []
        await sim.play(rounds: 1) {
            let monsters = sim.gm.game.monsters
            guard let bandits = monsters.first(where: { $0.name == "bandit-guard" }),
                  let city = monsters.first(where: { $0.name == "city-guard" }),
                  bandits.abilityDrawn, city.abilityDrawn else { return }
            pairs.append((sim.gm.monsterManager.currentAbility(for: bandits)?.cardId,
                          sim.gm.monsterManager.currentAbility(for: city)?.cardId))
            if let piece = coord.actingPiece, case .monster(let name, let standee) = piece, name.hasSuffix("-guard") {
                let kind = coord.monsterEntity(name: name, standee: standee)?.type == .elite ? "elite" : "normal"
                if acting.last != "\(name) \(kind)" { acting.append("\(name) \(kind)") }
            }
        }
        XCTAssertFalse(pairs.isEmpty, "both types drew")
        XCTAssertTrue(pairs.allSatisfy { $0.bandit != nil && $0.bandit == $0.city }, "one card for both types")
        let turns = coord.turnLog.map(\.message).filter { $0.contains("Guard\u{2019}s turn: ") }
        XCTAssertEqual(turns.count, 2, "each type takes its turn: \(turns)")
        XCTAssertEqual(turns.first?.components(separatedBy: "turn: ").last, turns.last?.components(separatedBy: "turn: ").last,
                       "the same card and initiative")
        XCTAssertTrue(turns.first?.hasPrefix("Bandit Guard") == true, "one type at a time, in a fixed order: \(turns)")
        // Within a type the elites went first; the types didn't interleave.
        let types = acting.map { $0.components(separatedBy: " ")[0] }
        XCTAssertEqual(types.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.count, Set(types).count,
                       "one type finished before the other began: \(acting)")
        for name in Set(types) {
            let kinds = acting.filter { $0.hasPrefix(name) }
            if kinds.count == 2 { XCTAssertEqual(kinds.first, "\(name) elite", "elites first: \(acting)") }
        }
        XCTAssertTrue(sim.violations.isEmpty, "\(sim.violations)")
    }

    // MARK: - Who draws (RND-5, MON-12)

    /// A card is revealed only for the types with a figure on the board.
    func testOnlyTypesWithAFigureOnTheBoardDraw() throws {
        character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        gm.monsterManager.addMonster(name: "bandit-archer", edition: "gh")   // in the scenario, not yet revealed
        let dead = try monster("living-bones", at: HexCoord(7, 7))
        coord.sufferDamage(99, to: dead)
        coord.sweepDeadFigures()
        startRound()
        XCTAssertTrue(try type("bandit-guard").abilityDrawn)
        XCTAssertFalse(try type("bandit-archer").abilityDrawn, "none on the board")
        XCTAssertNil(try card("bandit-archer"))
        XCTAssertFalse(try type("living-bones").abilityDrawn, "none left alive")
    }

    /// A type spawned or summoned during a round with no card yet draws one for the round. The
    /// spawned monster acts on it this round; the summoned one waits for the next.
    func testATypeArrivingMidRoundDrawsACardForTheRound() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(characters: ["brute", "spellweaver"], seed: 5,
                                                                       autoResolvePrompts: true))
        let coord = sim.coord
        var spawned: PieceID?, summoned: PieceID?
        var drewAtOnce: [Bool] = []
        var moved: Set<PieceID> = []
        let checks = coord.moveObserver
        coord.moveObserver = { piece, path, style in
            moved.insert(piece)
            checks?(piece, path, style)
        }
        await sim.play(rounds: 1) {
            guard spawned == nil, coord.isMidRound else { return }
            let free = coord.boardState.cells.keys.sorted().filter(coord.isEmptyHex)
            spawned = coord.spawnMonster(name: "living-corpse", type: .normal, at: free[0], origin: .spawned)
            summoned = coord.spawnMonster(name: "cave-bear", type: .normal, at: free[1], origin: .summoned)
            for name in ["living-corpse", "cave-bear"] {
                drewAtOnce.append(sim.gm.game.monsters.first { $0.name == name }?.abilityDrawn == true)
            }
        }
        XCTAssertEqual(drewAtOnce, [true, true], "each new type has a card as it arrives")
        let turns = coord.turnLog.map(\.message)
        XCTAssertTrue(turns.contains { $0.hasPrefix("Living Corpse\u{2019}s turn: ") }, "the spawned type acts this round")
        let bear = try XCTUnwrap(summoned)
        XCTAssertFalse(moved.contains(bear), "the summoned monster doesn't act in the round it arrives")
        XCTAssertFalse(turns.contains { $0.contains("\(coord.name(bear)) attacks") })
        _ = spawned
    }

    // MARK: - Focus ties (MON-2)

    private func focus(of guardian: PieceID) throws -> PieceID? {
        guard case .monster(let name, let standee) = guardian else { return nil }
        let monster = try type(name)
        let ability = AbilityModel(cardId: 1, initiative: 50, actions: [ActionModel(type: .move, value: .int(0), valueType: .plus),
                                                                         ActionModel(type: .attack, value: .int(0), valueType: .plus)])
        return MonsterAI.computeTurn(pieceID: guardian, monster: monster,
                                     entity: try XCTUnwrap(coord.monsterEntity(name: name, standee: standee)),
                                     ability: ability, board: coord.boardState, gameState: gm.game).focusTarget
    }

    /// As near as its owner, a summon is the focus: it acts just before the character.
    func testASummonIsFocusedOnBeforeItsOwner() throws {
        let brute = character("brute", at: HexCoord(3, 5), initiative: 30)
        let summon = GameSummon(name: "Rat", number: 1, health: 3, maxHealth: 3, level: 1, attack: .int(2), movement: 3, range: 0)
        summon.state = .active
        brute.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: HexCoord(7, 5))
        let guardian = try monster("bandit-guard", at: HexCoord(5, 5))
        XCTAssertEqual(try focus(of: guardian), .summon(id: summon.id))
        // Further off, it isn't: initiative only breaks a tie.
        coord.boardState.removePiece(.summon(id: summon.id))
        coord.boardState.placePiece(.summon(id: summon.id), at: HexCoord(9, 5))
        XCTAssertEqual(try focus(of: guardian), .character(brute.id))
    }

    /// A long-resting character counts as initiative 99 whatever card they led with last.
    func testALongRestingCharacterIsFocusedOnLast() throws {
        let resting = character("brute", at: HexCoord(3, 5), initiative: 0)
        resting.longRest = true
        let slow = character("tinkerer", at: HexCoord(7, 5), initiative: 90)
        let guardian = try monster("bandit-guard", at: HexCoord(5, 5))
        XCTAssertEqual(try focus(of: guardian), .character(slow.id))
        resting.longRest = false
        resting.initiative = 12
        XCTAssertEqual(try focus(of: guardian), .character(resting.id))
    }

    /// An objective the monsters attack counts as initiative 99, behind any character as near —
    /// a resting one included.
    func testAnObjectiveIsFocusedOnAfterACharacterAsNear() throws {
        let slow = character("brute", at: HexCoord(3, 5), initiative: 98)
        gm.objectiveManager.addObjective(name: "Crystal", health: 10)
        let container = try XCTUnwrap(gm.game.objectives.last)
        container.isProtected = true
        let crystal = try XCTUnwrap(container.entities.first)
        coord.boardState.placePiece(.objective(id: crystal.number), at: HexCoord(7, 5))
        let guardian = try monster("bandit-guard", at: HexCoord(5, 5))
        XCTAssertEqual(try focus(of: guardian), .character(slow.id))
        slow.longRest = true
        XCTAssertEqual(try focus(of: guardian), .character(slow.id), "99 for both: the character first")
        coord.boardState.removePiece(.character(slow.id))
        XCTAssertEqual(try focus(of: guardian), .objective(id: crystal.number), "alone, it is the focus")
    }

    // MARK: - Summons and escorts share the monsters' rules (MON-5, MON-6)

    private func summon(range: Int, at hex: HexCoord, owner: GameCharacter) -> GameSummon {
        let summon = GameSummon(name: "Archer", number: 1, health: 5, maxHealth: 5, level: 1, attack: .int(2), movement: 2, range: range)
        summon.state = .active
        owner.summons.append(summon)
        coord.boardState.placePiece(.summon(id: summon.id), at: hex)
        return summon
    }

    /// A disarmed ranged summon moves as if it had no attack: up to its focus.
    func testADisarmedRangedSummonClosesInOnItsFocus() throws {
        let owner = character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(8, 5))
        let archer = summon(range: 4, at: HexCoord(4, 5), owner: owner)
        let armed = SummonAI.computeTurn(summon: archer, ownerCharacterID: owner.id, board: coord.boardState, gameState: gm.game)
        XCTAssertTrue(armed.movementPath.isEmpty, "in range: it stays and shoots")
        XCTAssertEqual(armed.attackTargets.count, 1)

        archer.entityConditions = [EntityCondition(name: .disarm)]
        let disarmed = SummonAI.computeTurn(summon: archer, ownerCharacterID: owner.id, board: coord.boardState, gameState: gm.game)
        XCTAssertEqual(disarmed.movementPath.last, HexCoord(6, 5), "its Move 2, toward the guard")
        XCTAssertTrue(disarmed.attackTargets.isEmpty)
    }

    /// A ranged summon beside its focus steps away — unless it is muddled.
    func testAMuddledRangedSummonStaysBesideItsFocus() throws {
        let owner = character("brute", at: HexCoord(0, 0))
        try monster("bandit-guard", at: HexCoord(5, 5))
        let archer = summon(range: 4, at: HexCoord(4, 5), owner: owner)
        let clear = SummonAI.computeTurn(summon: archer, ownerCharacterID: owner.id, board: coord.boardState, gameState: gm.game)
        XCTAssertGreaterThan(try XCTUnwrap(clear.movementPath.last).distance(to: HexCoord(5, 5)), 1, "it steps away")

        archer.entityConditions = [EntityCondition(name: .muddle)]
        let muddled = SummonAI.computeTurn(summon: archer, ownerCharacterID: owner.id, board: coord.boardState, gameState: gm.game)
        XCTAssertTrue(muddled.movementPath.isEmpty, "Disadvantage either way: it stays")
        XCTAssertEqual(muddled.attackTargets.count, 1)
    }

    // MARK: - Printed damage: who suffers

    /// Every card text of a monster or a character that makes figures around it suffer damage
    /// hurts the figures its words name, whichever way round they are named.
    func testPrintedDamageHurtsWhomTheWordsName() async throws {
        var texts: [String] = []
        func collect(_ value: Any) {
            if let text = value as? String {
                if text.lowercased().contains("suffer") { texts.append(text.lowercased()) }
            } else if let group = value as? [String: Any] {
                for key in group.keys.sorted() { collect(group[key]!) }
            }
        }
        collect((gm.editionStore.labelsByEdition["gh"] ?? [:])["custom"] ?? [:])
        XCTAssertTrue(texts.contains { $0.contains("adjacent enemies and allies suffer") }, "the Night Demon's is among them")

        let actor = try monster("bandit-guard", at: HexCoord(5, 5))
        let nearAlly = try monster("bandit-archer", at: HexCoord(6, 5))
        let farAlly = try monster("bandit-archer", at: HexCoord(10, 10))
        let nearEnemy = character("brute", at: HexCoord(4, 5))
        let farEnemy = character("tinkerer", at: HexCoord(0, 0))
        func entity(_ piece: PieceID) throws -> any Entity { try XCTUnwrap(coord.entity(for: piece)) }
        var checked = 0
        for text in texts {
            // Whom the words name, read here on their own: the subject comes before "suffer".
            let subject = text.components(separatedBy: "suffer")[0]
            let (allies, enemies) = (subject.contains("allies"), subject.contains("enemies"))
            // "All enemies suffer" is the monster turn's own to carry out; "in the same room"
            // needs rooms (reported); neither comes through here anchored on a hex.
            guard allies || enemies, subject.contains("adjacent") || subject.contains("all allies"),
                  !subject.contains("same room") else { continue }
            let everywhere = text.contains("all allies suffer")
            let pieces = [nearAlly, farAlly, .character(nearEnemy.id), .character(farEnemy.id)]
            for piece in pieces {
                let figure = try entity(piece)
                figure.maxHealth = 30
                figure.health = 30
            }
            await coord.printedDamage(text, amount: 1, by: actor, around: HexCoord(5, 5))
            let hurt = try pieces.map { try entity($0).health < 30 }
            XCTAssertEqual(hurt, [allies, allies && everywhere, enemies && !everywhere, false], "\u{201C}\(text)\u{201D}")
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 10, "the texts were found: \(texts.count)")
    }
}
