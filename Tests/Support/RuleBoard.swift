import XCTest
import SwiftData
@testable import GlavenGameLib

/// A hand-built board with the real game behind it, for rule tests that go through the
/// coordinator: an open 12 × 12 floor, figures put where a test wants them, decks stacked so a
/// draw is known, and the turn loop's own calls to give a figure its turn.
///
/// Monsters come from `spawnMonster`, so standees number in order here (1, 2, 3 …).
@MainActor
final class RuleBoard {

    let gm: GameManager
    var coord: BoardCoordinator { gm.boardCoordinator }
    var game: GameState { gm.game }

    init(level: Int = 1, cols: Int = 12, rows: Int = 12) throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = level
        coord.boardState = makeBoard(cols: cols, rows: rows)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    // MARK: - Figures

    @discardableResult
    func character(_ name: String = "brute", at hex: HexCoord, health: Int? = nil) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        // The hand the character would bring: with it the next round waits for their cards.
        character.handCards = gm.characterManager.nextHand(for: character)
        if let health {
            character.maxHealth = health
            character.health = health
        }
        return character
    }

    /// A monster with `health` hit points and nothing from its stat card in the way of an exact
    /// number (no Shield, no Retaliate) unless a test gives it some.
    @discardableResult
    func monster(_ name: String = "bandit-guard", _ type: MonsterType = .normal, at hex: HexCoord, health: Int = 30,
                 origin: BoardCoordinator.SpawnOrigin = .placed,
                 file: StaticString = #filePath, line: UInt = #line) throws -> (piece: PieceID, entity: GameMonsterEntity) {
        let piece = try XCTUnwrap(coord.spawnMonster(name: name, type: type, at: hex, origin: origin), file: file, line: line)
        guard case .monster(_, let standee) = piece else { throw XCTSkip("not a monster") }
        let entity = try XCTUnwrap(coord.monsterEntity(name: name, standee: standee), file: file, line: line)
        entity.maxHealth = health
        entity.health = health
        entity.shield = nil
        entity.shieldPersistent = nil
        entity.retaliate = []
        entity.retaliatePersistent = []
        return (piece, entity)
    }

    func type(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> GameMonster {
        try XCTUnwrap(gm.game.monsters.first { $0.name == name }, "no \(name) in the game", file: file, line: line)
    }

    /// A summon of `owner`, already on the board. `.active` has been there since an earlier
    /// round; `.new` was summoned this round.
    @discardableResult
    func summon(of owner: GameCharacter, at hex: HexCoord, attack: Int = 2, move: Int = 2, range: Int = 0,
                health: Int = 10, state: SummonState = .active) -> (piece: PieceID, entity: GameSummon) {
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: owner.summons.count + 1,
                                health: health, maxHealth: health, level: 1,
                                attack: .int(attack), movement: move, range: range)
        summon.state = state
        owner.summons.append(summon)
        let piece = PieceID.summon(id: summon.id)
        coord.boardState.placePiece(piece, at: hex)
        return (piece, summon)
    }

    func hex(_ piece: PieceID) -> HexCoord? { coord.boardState.piecePositions[piece] }

    func has(_ condition: ConditionName, _ entity: any Entity) -> Bool {
        entity.entityConditions.contains { $0.name == condition && !$0.expired }
    }

    // MARK: - Decks

    /// A deck that deals `cards` in this order (and is made of them, should it reshuffle).
    static func deck(_ cards: [AttackModifierType]) -> AttackModifierDeck {
        let modifiers = cards.map { AttackModifier.standard($0) }
        return AttackModifierDeck(attackModifiers: modifiers, cards: modifiers)
    }

    /// A deck of nothing but `type`, thirty of them.
    static func deck(of type: AttackModifierType) -> AttackModifierDeck {
        deck(Array(repeating: type, count: 30))
    }

    /// How many cards have been drawn from a deck since it was last shuffled.
    static func drawn(_ deck: AttackModifierDeck) -> Int { deck.current + 1 }

    // MARK: - Monster cards

    /// Make `cardId` the card the type has drawn this round.
    @discardableResult
    func draw(_ cardId: Int, for name: String, file: StaticString = #filePath, line: UInt = #line) throws -> GameMonster {
        let monster = try type(name, file: file, line: line)
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == cardId }, "card \(cardId)", file: file, line: line)]
        monster.ability = 0
        monster.abilityDrawn = true
        monster.drawnInitiative = deck.first { $0.cardId == cardId }?.initiative
        return monster
    }

    /// The first card of the type's deck that fits, e.g. one with a Move and an Attack and
    /// nothing else in the way.
    func card(of name: String, where fits: (AbilityModel) -> Bool,
              file: StaticString = #filePath, line: UInt = #line) throws -> AbilityModel {
        let monster = try type(name, file: file, line: line)
        return try XCTUnwrap(gm.monsterManager.abilities(for: monster).first(where: fits),
                             "no such card in the \(name) deck", file: file, line: line)
    }

    /// The type takes its turn, as the turn loop has it (all of it, or only the standees named).
    func act(_ name: String, only: [GameMonsterEntity]? = nil) async throws {
        await MonsterTurnController(coordinator: coord, gameManager: gm)
            .executeMonsterGroup(try type(name), only: only.map { Set($0.map(\.number)) })
    }

    // MARK: - Turns

    /// Start the round's turns with exactly these figures to act, in this order.
    func startTurns(_ entries: [TurnOrderEntry]) {
        coord.boardPhase = .execution
        gm.game.state = .next
        coord.turnOrder = entries
        coord.currentTurnIndex = -1
        coord.advanceToNextFigure()
    }

    /// The end of the round as the turn loop reaches it: no figure left to act.
    func endRound() {
        coord.boardPhase = .execution
        gm.game.state = .next
        coord.turnOrder = []
        coord.currentTurnIndex = -1
        coord.advanceToNextFigure()
    }

    /// A character's two cards for the round, as card selection leaves them.
    func play(_ top: AbilityModel, _ bottom: AbilityModel, for character: GameCharacter) {
        for id in [top.cardId, bottom.cardId].compactMap({ $0 }) where !character.handCards.contains(id) {
            character.handCards.append(id)
        }
        character.initiative = top.initiative
        character.longRest = false
        coord.storeSelectedCards(for: character.id, top: top, bottom: bottom)
    }

    func card(_ name: String, of deck: String, file: StaticString = #filePath, line: UInt = #line) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name,
                      file: file, line: line)
    }

    /// Skip whatever is left of the active turn and end it, as End Turn does.
    func endTurn(file: StaticString = #filePath, line: UInt = #line) {
        guard let turn = coord.activePlayerTurn else { return XCTFail("no turn to end", file: file, line: line) }
        var tries = 0
        while turn.phase != .turnComplete, tries < 40 {
            turn.skipRemainingActions()
            tries += 1
        }
        coord.finishPlayerTurn()
    }

    /// A whole turn of the round for `character`, the only figure to act in it: the first two
    /// cards of the hand are played and nothing is done with them unless `during` does it.
    /// The round ends with the turn (a short rest, if offered, is declined).
    func takeTurn(_ character: GameCharacter, during: ((PlayerTurnController) -> Void)? = nil,
                  file: StaticString = #filePath, line: UInt = #line) throws {
        let deck = gm.characterManager.abilities(for: character)
        let cards = character.handCards.prefix(2).compactMap { id in deck.first { $0.cardId == id } }
        guard cards.count == 2 else { return XCTFail("\(character.name) has no two cards to play", file: file, line: line) }
        play(cards[0], cards[1], for: character)
        startTurns([TurnOrderEntry(figure: .character(character), initiative: Double(character.initiative))])
        let turn = try XCTUnwrap(coord.activePlayerTurn, "the turn is \(character.name)'s", file: file, line: line)
        XCTAssertEqual(turn.characterID, character.id, file: file, line: line)
        during?(turn)
        endTurn(file: file, line: line)
        if coord.pendingShortRest != nil { coord.skipShortRest() }
    }

    /// Wait for the turn loop's tasks to get somewhere.
    @discardableResult
    func settle(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }
}
