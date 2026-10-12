import XCTest
@testable import GlavenGameLib

/// Opening a door (rulebook pp. 14, 16, 32; gh-rules.md MOV-8, MOV-9, SET-1), in Black Barrow
/// with the real turn loop: a character's own move opens the door, the room beyond is set up for
/// the characters the scenario began with, a type with no card draws one, and the room's
/// monsters act at the right moment of the round.
///
/// Black Barrow's second room holds Bandit Archers (new to the scenario there) and more Bandit
/// Guards. Standee numbers are random, so monsters are told apart by type and rank only.
@MainActor
final class RevealRuleTests: XCTestCase {

    private var sim: ScenarioSimulator!
    private var coord: BoardCoordinator { sim.coord }
    private var game: GameState { sim.gm.game }

    private func start(_ party: [String] = ["brute", "tinkerer"]) throws {
        sim = try ScenarioSimulator(scenario: "1", options: .init(characters: party, seed: 4, autoResolvePrompts: true))
        // The monsters' hits are kept small: who acts when is what these tests are about.
        game.monsterAttackModifierDeck = RuleBoard.deck(of: .minus2)
    }

    private func character(_ name: String) throws -> GameCharacter {
        try XCTUnwrap(game.characters.first { $0.name == name })
    }

    private func type(_ name: String) throws -> GameMonster {
        try XCTUnwrap(game.monsters.first { $0.name == name }, "\(name) is in the scenario")
    }

    private func pieces(of name: String) -> [PieceID] {
        coord.boardState.piecePositions.keys.filter { if case .monster(name, _) = $0 { return true }; return false }.sorted()
    }

    private func ranks(of name: String) -> [MonsterType] {
        pieces(of: name).compactMap { piece -> MonsterType? in
            guard case .monster(_, let standee) = piece else { return nil }
            return coord.monsterEntity(name: name, standee: standee)?.type
        }.sorted { $0.rawValue < $1.rawValue }
    }

    /// The next card the type will draw is `cardId`.
    private func stack(_ cardId: Int, for name: String) throws {
        let monster = try type(name)
        let deck = sim.gm.monsterManager.abilities(for: monster)
        let index = try XCTUnwrap(deck.firstIndex { $0.cardId == cardId }, "card \(cardId)")
        XCTAssertFalse(monster.abilityDrawn, "\(name) has no card yet this round")
        monster.abilities = [index] + deck.indices.filter { $0 != index }
        monster.ability = -1
    }

    private func card(_ name: String, of character: GameCharacter) throws -> AbilityModel {
        let card = try XCTUnwrap(sim.gm.editionStore.abilities(forDeck: character.name, edition: "gh").first { $0.name == name }, name)
        // Any ten of a first-level character's cards may be their hand: this one is among them.
        if let id = card.cardId, !character.handCards.contains(id) { character.handCards[character.handCards.count - 1] = id }
        return card
    }

    /// The closed door of the first room, and a free hex of that room beside it.
    private func firstDoor() throws -> (door: HexCoord, beside: HexCoord) {
        let door = try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen }, "a closed door")
        let beside = try XCTUnwrap(door.coord.neighbors.sorted().first { coord.isEmptyHex($0) }, "a free hex beside the door")
        return (door.coord, beside)
    }

    private func settle(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    private func killEveryMonsterOnTheBoard(except spared: PieceID? = nil) {
        for piece in coord.boardState.piecePositions.keys.sorted() where piece != spared {
            if case .monster = piece { coord.sufferDamage(999, to: piece) }
        }
    }

    /// Round 1 with the Brute (leading with Overwhelming Assault, 61, and Grab and Go's Move 4
    /// below it) standing beside the door, and the Tinkerer on 74. Plays up to the Brute's turn.
    private func playToTheBrutesTurn() async throws -> (brute: GameCharacter, door: HexCoord, turn: PlayerTurnController) {
        let brute = try character("brute"), tinkerer = try character("tinkerer")
        let (door, beside) = try firstDoor()
        coord.boardState.movePiece(.character(brute.id), to: beside)
        let assault = try card("Overwhelming Assault", of: brute), grab = try card("Grab and Go", of: brute)
        let contraption = try card("Harmless Contraption", of: tinkerer), mist = try card("Restorative Mist", of: tinkerer)
        XCTAssertEqual(coord.cardSelectingCharacterID, brute.id)
        coord.chooseCards(for: brute.id, leading: assault, other: grab)
        coord.chooseCards(for: tinkerer.id, leading: contraption, other: mist)
        let reached = await settle { self.coord.activePlayerTurn?.characterID == brute.id }
        XCTAssertTrue(reached, "the Brute's turn comes")
        return (brute, door, try XCTUnwrap(coord.activePlayerTurn))
    }

    /// The Brute walks onto the door with the bottom half's Move and the turn is ended.
    private func walkThroughTheDoor(_ door: HexCoord, _ turn: PlayerTurnController) async {
        if turn.topCard?.name == "Grab and Go" { turn.swapCards() }
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode, hexes.contains(door) else {
            return XCTFail("the Move offers the door's hex: \(coord.interactionMode)")
        }
        coord.handleHexTap(door)
        // The door open, the move may go on with the movement left (MOV-8): he stays in the doorway.
        _ = await settle { self.coord.continuedMove != nil || !turn.isWaiting }
        if coord.continuedMove != nil { turn.skipCurrentAction() }
        let moved = await settle { !turn.isWaiting }
        XCTAssertTrue(moved)
    }

    private func endTurn(_ turn: PlayerTurnController) {
        var tries = 0
        while turn.phase != .turnComplete, tries < 40 {
            turn.skipRemainingActions()
            tries += 1
        }
        coord.finishPlayerTurn()
    }

    /// Whose turns the log shows from entry `logged` on, in order ("Bandit Archer", "Tinkerer").
    private func turnsLogged(from logged: Int) -> [String] {
        coord.turnLog[logged...].compactMap { entry in
            entry.message.range(of: "\u{2019}s turn: ").map { String(entry.message[..<$0.lowerBound]) }
        }
    }

    /// The round's order from the entry after `name`'s: who, on what initiative, and whether the
    /// whole type or only the newly revealed standees.
    private func orderAfter(_ name: String) -> [String] {
        let entries = coord.turnOrder.map { entry -> String in
            switch entry.figure {
            case .character(let character): return character.name
            case .monster(let monster):
                return "\(monster.name) \(Int(entry.initiative))" + (entry.onlyStandees == nil ? "" : " (the revealed)")
            case .objective(let objective): return objective.name
            }
        }
        return Array(entries.drop { $0 != name }.dropFirst())
    }

    // MARK: - MOV-8, SET-1: the door and the room

    /// MOV-8 (p.16): a character who moves onto a closed door opens it, and the room beyond is
    /// revealed at once — set up, SET-1, for the number of characters: with two, one elite Archer
    /// and two normal Guards.
    func testACharactersMoveOpensTheDoorAndRevealsTheRoomForTwo() async throws {
        try start()
        // One Guard of the first room is left (the others would stand in the Brute's way).
        killEveryMonsterOnTheBoard(except: try XCTUnwrap(pieces(of: "bandit-guard").first))
        let before = Set(coord.boardState.piecePositions.keys)
        let (brute, door, turn) = try await playToTheBrutesTurn()
        XCTAssertTrue(pieces(of: "bandit-archer").isEmpty, "no Archer before the door opens")
        XCTAssertEqual(coord.boardState.doors.filter(\.isOpen).count, 0)

        await walkThroughTheDoor(door, turn)
        XCTAssertEqual(coord.boardState.doors.first { $0.coord == door }?.isOpen, true)
        XCTAssertEqual(sim.position(.character(brute.id)), door, "the Brute stands in the doorway")
        XCTAssertEqual(game.scenario?.revealedRooms.sorted(), [1, 2])
        XCTAssertEqual(ranks(of: "bandit-archer"), [.elite])
        let newGuards = pieces(of: "bandit-guard").filter { !before.contains($0) }
        XCTAssertEqual(newGuards.count, 2, "two more Guards")
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    /// SET-1 (FAQ): a room revealed later is set up for the characters the scenario began with,
    /// exhausted ones included. Three began: an elite and two normal Archers and an elite Guard,
    /// each where the map puts a monster of its rank for three — the room as it is set up when
    /// no one has fallen.
    func testARoomIsSetUpForTheCharactersTheScenarioBeganWith() throws {
        func secondRoom(exhausting fallen: String?) throws -> [String] {
            try start(["brute", "tinkerer", "scoundrel"])
            killEveryMonsterOnTheBoard()
            if let fallen {
                coord.sufferDamage(999, to: .character(try character(fallen).id))
                XCTAssertTrue(try character(fallen).exhausted)
            }
            let (door, _) = try firstDoor()
            coord.openDoor(at: door)
            return coord.boardState.piecePositions.compactMap { piece, hex -> String? in
                guard case .monster(let name, let standee) = piece,
                      let rank = coord.monsterEntity(name: name, standee: standee)?.type else { return nil }
                return "\(rank.rawValue) \(name) at \(hex)"
            }.sorted()
        }
        let room = try secondRoom(exhausting: "scoundrel")
        XCTAssertEqual(ranks(of: "bandit-archer"), [.elite, .normal, .normal].sorted { $0.rawValue < $1.rawValue })
        XCTAssertEqual(ranks(of: "bandit-guard"), [.elite])
        XCTAssertEqual(room, try secondRoom(exhausting: nil), "who stands where")
    }

    /// A door a scenario rule opens as a round starts (Gloomhaven Battlements B: the gate falls
    /// in round 9) opens while cards are being chosen, and they are still being chosen once the
    /// room is set up: a reveal goes back to what it interrupted. It used to leave the round's
    /// turns "in progress" with no one to act — the veteran playthrough of #36 never ended.
    func testARoomRevealedWhileCardsAreChosenLeavesThemBeingChosen() throws {
        try start()
        XCTAssertEqual(coord.boardPhase, .cardSelection)
        coord.openDoor(at: try XCTUnwrap(coord.boardState.doors.first { !$0.isOpen }).coord)
        XCTAssertEqual(game.scenario?.revealedRooms.sorted(), [1, 2])
        XCTAssertEqual(coord.boardPhase, .cardSelection)
        let brute = try character("brute"), tinkerer = try character("tinkerer")
        coord.chooseCards(for: brute.id, leading: try card("Overwhelming Assault", of: brute), other: try card("Grab and Go", of: brute))
        coord.chooseCards(for: tinkerer.id, leading: try card("Harmless Contraption", of: tinkerer), other: try card("Restorative Mist", of: tinkerer))
        XCTAssertEqual(coord.boardPhase, .execution, "and with every card chosen the round's turns begin")
        XCTAssertFalse(coord.turnOrder.isEmpty)
    }

    // MARK: - MOV-9: cards and turns for the revealed

    /// MOV-9 (p.32): the Guards drew a 30 at the start of the round and have acted; the Brute, on
    /// 61, opens the door. The Archers, new, draw a card now (a 16). Both types' initiatives are
    /// lower than the Brute's, so the revealed monsters act as soon as his turn ends — Archers
    /// (16) before the revealed Guards (30), who act on the card their type already has — and
    /// before the Tinkerer on 74.
    func testRevealedMonstersWithALowerInitiativeActRightAfterTheRevealingTurn() async throws {
        try start()
        let spared = try XCTUnwrap(pieces(of: "bandit-guard").first)
        killEveryMonsterOnTheBoard(except: spared)
        try stack(525, for: "bandit-guard")    // Move +1, Attack +1: initiative 30
        try stack(532, for: "bandit-archer")   // initiative 16
        let (_, door, turn) = try await playToTheBrutesTurn()
        let guards = try type("bandit-guard"), archers = try type("bandit-archer")
        XCTAssertEqual(sim.gm.monsterManager.currentAbility(for: guards)?.cardId, 525, "the Guards drew as the round began")
        XCTAssertFalse(archers.abilityDrawn, "the Archers, with no figure on the board, did not")
        XCTAssertEqual(orderAfter("bandit-guard 30"), ["brute", "tinkerer"])

        await walkThroughTheDoor(door, turn)
        XCTAssertTrue(archers.abilityDrawn, "a type revealed without a card draws one at once")
        XCTAssertEqual(sim.gm.monsterManager.currentAbility(for: archers)?.cardId, 532)
        XCTAssertEqual(sim.gm.monsterManager.currentAbility(for: guards)?.cardId, 525, "the Guards keep the card they have")

        let logged = coord.turnLog.count
        endTurn(turn)
        XCTAssertEqual(orderAfter("brute"), ["bandit-archer 16 (the revealed)", "bandit-guard 30 (the revealed)", "tinkerer"])
        let tinkerer = try character("tinkerer")
        let reached = await settle { self.coord.activePlayerTurn?.characterID == tinkerer.id || self.coord.scenarioResult != nil }
        XCTAssertTrue(reached, "the Tinkerer's turn comes after them")
        XCTAssertEqual(turnsLogged(from: logged), ["Bandit Archer", "Bandit Guard", "Tinkerer"], "and they acted in that order")
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    /// MOV-9: with no Guard on the board as the round began, neither type has a card: both draw
    /// when the door opens. The Archers' 16 is lower than the Brute's 61 — they act at once; the
    /// Guards' 70 is not — they act at their place in the order, before the Tinkerer on 74, and
    /// as a whole type.
    func testRevealedMonstersWithAHigherInitiativeActAtTheirPlaceInTheOrder() async throws {
        try start()
        killEveryMonsterOnTheBoard()
        try stack(529, for: "bandit-guard")    // initiative 70
        try stack(532, for: "bandit-archer")   // initiative 16
        let (_, door, turn) = try await playToTheBrutesTurn()
        let guards = try type("bandit-guard"), archers = try type("bandit-archer")
        XCTAssertFalse(guards.abilityDrawn, "only types with a figure on the board draw as a round begins")
        XCTAssertFalse(archers.abilityDrawn)
        XCTAssertEqual(orderAfter("brute"), ["tinkerer"])

        await walkThroughTheDoor(door, turn)
        XCTAssertEqual(sim.gm.monsterManager.currentAbility(for: guards)?.cardId, 529, "both draw at the reveal")
        XCTAssertEqual(sim.gm.monsterManager.currentAbility(for: archers)?.cardId, 532)

        let logged = coord.turnLog.count
        endTurn(turn)
        XCTAssertEqual(orderAfter("brute"), ["bandit-archer 16 (the revealed)", "bandit-guard 70 (the revealed)", "tinkerer"])
        let tinkerer = try character("tinkerer")
        let reached = await settle { self.coord.activePlayerTurn?.characterID == tinkerer.id || self.coord.scenarioResult != nil }
        XCTAssertTrue(reached)
        XCTAssertEqual(turnsLogged(from: logged), ["Bandit Archer", "Bandit Guard", "Tinkerer"])
    }

    /// MOV-9: revealed by the last character to act in the round, the room's monsters still take
    /// their turns in it. The Tinkerer goes first on 16; the Brute (61) opens the door; Archers
    /// (68) and Guards (70) act before the round ends.
    func testRevealedMonstersStillActWhenEveryCharacterHasActed() async throws {
        try start()
        killEveryMonsterOnTheBoard()
        try stack(529, for: "bandit-guard")    // 70
        try stack(537, for: "bandit-archer")   // 68
        let brute = try character("brute"), tinkerer = try character("tinkerer")
        let (door, beside) = try firstDoor()
        coord.boardState.movePiece(.character(brute.id), to: beside)
        coord.chooseCards(for: brute.id, leading: try card("Overwhelming Assault", of: brute), other: try card("Grab and Go", of: brute))
        coord.chooseCards(for: tinkerer.id, leading: try card("Energizing Tonic", of: tinkerer), other: try card("Restorative Mist", of: tinkerer))
        XCTAssertEqual(coord.activePlayerTurn?.characterID, tinkerer.id, "the Tinkerer, on 16, goes first")
        endTurn(try XCTUnwrap(coord.activePlayerTurn))
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        XCTAssertEqual(turn.characterID, brute.id)

        await walkThroughTheDoor(door, turn)
        let round = game.round
        let logged = coord.turnLog.count
        endTurn(turn)
        XCTAssertEqual(orderAfter("brute"), ["bandit-archer 68 (the revealed)", "bandit-guard 70 (the revealed)"])
        let over = await settle { self.coord.boardPhase == .cardSelection || self.coord.pendingShortRest != nil || self.coord.scenarioResult != nil }
        XCTAssertTrue(over, "the round ends once they have acted")
        XCTAssertEqual(game.round, round)
        XCTAssertEqual(turnsLogged(from: logged), ["Bandit Archer", "Bandit Guard"])
    }
}
