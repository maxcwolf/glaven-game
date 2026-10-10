import XCTest
@testable import GlavenGameLib

/// The round (rulebook pp. 16–18, 26, 28, 32; gh-rules.md RND-2, RND-6, RND-8, RND-9, RND-10,
/// ATK-15), through the coordinator's own turn order and end of round: who acts when, when a
/// modifier deck is reshuffled, and what exhaustion takes away.
@MainActor
final class RoundRuleTests: XCTestCase {

    private var board: RuleBoard!
    private var coord: BoardCoordinator { board.coord }
    private let here = HexCoord(3, 3), beside = HexCoord(4, 3), twoAway = HexCoord(5, 3)

    override func setUp() async throws {
        board = try RuleBoard()
    }

    private func count(_ type: AttackModifierType, in deck: AttackModifierDeck) -> Int {
        deck.cards.filter { $0.type == type }.count
    }

    // MARK: - RND-9, RND-10: reshuffling the modifier decks

    /// RND-9 (p.20): a deck from which a ×2 or a Null was drawn this round is shuffled, discards
    /// and all, at the end of the round — and a deck that drew neither is left as it is.
    func testADeckThatDrewATimesTwoOrANullIsReshuffledAtTheEndOfTheRound() async throws {
        let brute = board.character(at: here, health: 30), tinkerer = board.character("tinkerer", at: HexCoord(1, 1))
        let enemy = try board.monster(at: beside, health: 60)
        let ally = try board.monster("inox-guard", at: twoAway)
        try board.type("inox-guard").isAlly = true
        brute.attackModifierDeck = RuleBoard.deck([.double_, .plus0, .plus0, .plus0])
        tinkerer.attackModifierDeck = RuleBoard.deck([.plus1, .double_, .plus0, .plus0])
        board.game.monsterAttackModifierDeck = RuleBoard.deck([.plus1, .null_, .plus0, .plus0])
        board.game.allyAttackModifierDeck = RuleBoard.deck([.null_, .plus0, .plus0, .plus0])

        await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 2))
        await coord.performAttack(attacker: enemy.piece, target: .character(brute.id), attack: AttackParameters(value: 2))
        await coord.performAttack(attacker: ally.piece, target: enemy.piece, attack: AttackParameters(value: 2))
        XCTAssertEqual(enemy.entity.health, 60 - 4, "the Brute's ×2 doubled the attack; the ally's Null did nothing")
        XCTAssertEqual(brute.health, 30 - 3)
        XCTAssertEqual([brute.attackModifierDeck, board.game.monsterAttackModifierDeck, board.game.allyAttackModifierDeck]
            .map(RuleBoard.drawn), [1, 1, 1], "nothing is reshuffled before the round ends")

        board.endRound()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0, "drew a ×2: reshuffled")
        XCTAssertEqual(brute.attackModifierDeck.cards.count, 4, "with its discard back in")
        XCTAssertEqual(RuleBoard.drawn(board.game.allyAttackModifierDeck), 0, "drew a Null: reshuffled")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 1, "drew a +1: its discard stays out")
        XCTAssertEqual(board.game.monsterAttackModifierDeck.cards.dropFirst().first?.type, .null_, "and its order is untouched")
        XCTAssertEqual(RuleBoard.drawn(tinkerer.attackModifierDeck), 0, "drew nothing")
        XCTAssertEqual(tinkerer.attackModifierDeck.cards.map(\.type), [.plus1, .double_, .plus0, .plus0], "not shuffled either")
    }

    /// RND-10 (p.23): a Bless or a Curse is removed when drawn and "does not trigger a
    /// reshuffle": the round a Bless was drawn in ends with the deck as it was, and when the deck
    /// is next shuffled the card is no longer in it.
    func testBlessAndCurseAreRemovedWhenDrawnAndCauseNoReshuffle() async throws {
        let brute = board.character(at: here, health: 30)
        let enemy = try board.monster(at: beside, health: 60)
        brute.attackModifierDeck = RuleBoard.deck([.bless, .plus0, .null_, .plus0])
        board.game.monsterAttackModifierDeck = RuleBoard.deck([.curse, .plus0, .double_, .plus0])

        await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 3))
        await coord.performAttack(attacker: enemy.piece, target: .character(brute.id), attack: AttackParameters(value: 3))
        XCTAssertEqual(enemy.entity.health, 60 - 6, "a Bless is a ×2")
        XCTAssertEqual(brute.health, 30, "a Curse is a Null")
        board.endRound()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 1, "the Bless caused no reshuffle")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 1, "nor the Curse")
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .bless), 0, "the drawn Bless is out of the deck")
        XCTAssertTrue(coord.gameManager?.game.hasSpecialCardLeft(.bless, forMonsterDeck: false) ?? false)

        // Next round each deck draws its +0 and then its Null / ×2: reshuffled, without the
        // Bless and the Curse.
        for _ in 0..<2 {
            await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 3))
            await coord.performAttack(attacker: enemy.piece, target: .character(brute.id), attack: AttackParameters(value: 3))
        }
        board.endRound()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0)
        XCTAssertEqual(brute.attackModifierDeck.cards.map(\.type).sorted { $0.rawValue < $1.rawValue }, [.null_, .plus0, .plus0])
        XCTAssertEqual(board.game.monsterAttackModifierDeck.cards.map(\.type).sorted { $0.rawValue < $1.rawValue }, [.double_, .plus0, .plus0])
    }

    /// A Bless still waiting in the deck stays in it through a reshuffle (only drawn ones go).
    func testAnUndrawnBlessStaysInTheDeckThroughAReshuffle() async throws {
        let brute = board.character(at: here)
        let enemy = try board.monster(at: beside, health: 60)
        brute.attackModifierDeck = RuleBoard.deck([.null_, .plus0, .plus0])
        coord.applyCondition(.bless, to: .character(brute.id))
        coord.applyCondition(.curse, to: .character(brute.id))
        // Whatever the first card is, draw until the Null has come up.
        var draws = 0
        while !brute.attackModifierDeck.needsShuffle, draws < 5 {
            await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 1))
            draws += 1
        }
        XCTAssertTrue(brute.attackModifierDeck.needsShuffle)
        let blessLeft = brute.attackModifierDeck.undrawnCount(of: .bless), curseLeft = brute.attackModifierDeck.undrawnCount(of: .curse)
        board.endRound()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0)
        XCTAssertEqual(count(.bless, in: brute.attackModifierDeck), blessLeft, "an undrawn Bless stays; a drawn one is gone")
        XCTAssertEqual(count(.curse, in: brute.attackModifierDeck), curseLeft)
        XCTAssertEqual(brute.attackModifierDeck.cards.count, 3 + blessLeft + curseLeft)
    }

    /// RND-9: a deck that ran out and was reshuffled in mid-round still drew its Null this
    /// round, so it is shuffled again when the round ends (audit A11).
    func testADeckThatRanOutMidRoundIsStillReshuffledAtTheEndOfTheRound() async throws {
        let brute = board.character(at: here)
        let enemy = try board.monster(at: beside, health: 90)
        // A seed with which the card drawn after the mid-round reshuffle isn't the Null itself.
        var seed: UInt64 = 0
        repeat {
            seed += 1
            GameRandom.shared = GameRandom(seed: seed)
            brute.attackModifierDeck = RuleBoard.deck([.null_, .plus0, .plus0, .plus0, .plus0, .plus0])
            for _ in 0..<7 {
                await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 1))
            }
        } while brute.attackModifierDeck.currentCard?.type == .null_ && seed < 20
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 1, "the deck ran out and was shuffled for the seventh draw")
        XCTAssertNotEqual(brute.attackModifierDeck.currentCard?.type, .null_)

        board.endRound()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0, "a Null was drawn this round: shuffled at its end")
    }

    // MARK: - RND-6, RND-8: the order of turns

    private func order() -> [String] {
        coord.turnOrder.map { entry in
            switch entry.figure {
            case .character(let character): return character.name
            case .monster(let monster): return monster.name
            case .objective(let objective): return objective.name
            }
        }
    }

    /// RND-6 (p.18): figures act in ascending initiative, and "if there is a tie between a
    /// player and a monster type, the player goes first"; two characters on the same initiative
    /// go by their second card.
    func testInitiativeOrderAndItsTies() throws {
        let brute = board.character(at: here), tinkerer = board.character("tinkerer", at: HexCoord(1, 1))
        let scoundrel = board.character("scoundrel", at: HexCoord(1, 5))
        try board.monster(at: HexCoord(8, 8))
        try board.monster("bandit-archer", at: HexCoord(8, 3))
        try board.draw(525, for: "bandit-guard")     // initiative 30
        try board.draw(532, for: "bandit-archer")    // initiative 16
        // The Brute leads with a 30 too (a tie with the Guards); the Scoundrel and the Tinkerer
        // both lead with a 20, their second cards 86 and 74.
        board.play(try board.card("Trample", of: "brute"), try board.card("Spare Dagger", of: "brute"), for: brute)
        brute.initiative = 30
        board.play(try board.card("Stun Shot", of: "tinkerer"), try board.card("Harmless Contraption", of: "tinkerer"), for: tinkerer)
        board.play(try board.card("Smoke Bomb", of: "scoundrel"), try board.card("Single Out", of: "scoundrel"), for: scoundrel)
        scoundrel.initiative = 20
        coord.boardPhase = .execution
        board.game.state = .next
        coord.buildTurnOrderAndStart()
        XCTAssertEqual(order(), ["bandit-archer", "tinkerer", "scoundrel", "brute", "bandit-guard"])
    }

    /// RND-8 (p.26): "a summon's turn … always occurs directly before the summoner's", each
    /// round, and never in the round it was summoned. Aid from the Ether's bottom summons the
    /// Mystic Ally through the Spellweaver's own turn; next round it attacks after the Guards
    /// (initiative 30) and before the Spellweaver (70) has the board.
    func testASummonActsJustBeforeItsOwnerAndNotInTheRoundItArrives() async throws {
        let weaver = board.character("spellweaver", at: here, health: 30)
        let guardian = try board.monster(at: twoAway, health: 60)
        weaver.attackModifierDeck = RuleBoard.deck(of: .plus0)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus0)
        var attackers: [PieceID] = []
        var turnWasOpen: [Bool] = []
        coord.attackObserver = { attacker, _ in
            attackers.append(attacker)
            turnWasOpen.append(self.coord.activePlayerTurn != nil)
        }

        // Round 1: the Spellweaver summons.
        let aid = try board.card("Aid from the Ether", of: "spellweaver")
        board.play(try board.card("Mana Bolt", of: "spellweaver"), aid, for: weaver)
        board.startTurns([TurnOrderEntry(figure: .character(weaver), initiative: 7)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        guard case .placingSummon(_, _, let hexes) = coord.interactionMode else { return XCTFail("the summon waits for its hex") }
        XCTAssertTrue(hexes.contains(beside))
        coord.handleHexTap(beside)
        let pet = try XCTUnwrap(weaver.summons.first)
        XCTAssertEqual(pet.state, .new, "summoned this round")
        XCTAssertEqual(board.hex(.summon(id: pet.id)), beside)

        // Its turn would come before its owner's — were the owner to act again this round, it
        // still waits.
        await SummonTurnController(coordinator: coord, gameManager: board.gm).executeSummonTurns(for: weaver)
        XCTAssertEqual(guardian.entity.health, 60, "no turn in the round it was summoned")
        XCTAssertEqual(attackers, [])
        board.endTurn()
        if coord.pendingShortRest != nil { coord.skipShortRest() }
        XCTAssertEqual(pet.state, .active, "from the next round on it acts")

        // Round 2: Guards on 30, the Spellweaver on 70.
        try board.draw(525, for: "bandit-guard")
        board.play(try board.card("Impaling Eruption", of: "spellweaver"), try board.card("Fire Orbs", of: "spellweaver"), for: weaver)
        coord.boardPhase = .execution
        board.game.state = .next
        coord.buildTurnOrderAndStart()
        XCTAssertEqual(order(), ["bandit-guard", "spellweaver"])
        let reached = await board.settle { self.coord.activePlayerTurn?.characterID == weaver.id }
        XCTAssertTrue(reached, "the Spellweaver's turn comes")
        XCTAssertEqual(attackers, [guardian.piece, .summon(id: pet.id)], "the Guard on 30, then the summon")
        XCTAssertEqual(turnWasOpen, [false, false], "both before the Spellweaver had the board")
        XCTAssertEqual(guardian.entity.health, 60 - 3, "Mystic Ally: Attack 3")
    }

    /// …and before a monster type that acts after its owner.
    func testASummonActsBeforeMonstersThatFollowItsOwner() async throws {
        let weaver = board.character("spellweaver", at: here, health: 30)
        let guardian = try board.monster(at: twoAway, health: 60)
        let pet = board.summon(of: weaver, at: beside, attack: 3, move: 0)
        weaver.attackModifierDeck = RuleBoard.deck(of: .plus0)
        var attackers: [PieceID] = []
        coord.attackObserver = { attacker, _ in attackers.append(attacker) }
        try board.draw(525, for: "bandit-guard")   // 30
        board.play(try board.card("Mana Bolt", of: "spellweaver"), try board.card("Fire Orbs", of: "spellweaver"), for: weaver)   // 7
        coord.boardPhase = .execution
        board.game.state = .next
        coord.buildTurnOrderAndStart()
        XCTAssertEqual(order(), ["spellweaver", "bandit-guard"])
        let reached = await board.settle { self.coord.activePlayerTurn?.characterID == weaver.id }
        XCTAssertTrue(reached)
        XCTAssertEqual(attackers, [pet.piece], "the summon has acted; the Guards, on 30, have not")
        XCTAssertEqual(guardian.entity.health, 60 - 3)
    }

    // MARK: - ATK-15, RND-2: exhaustion

    /// ATK-15 (p.28): a character brought to 0 hit points is exhausted — every card they have,
    /// in hand, discarded or in play, is lost; their figure and their summons leave the map; and
    /// they take no further turn.
    func testAnExhaustedCharactersCardsAreAllLostAndTheirSummonsLeave() async throws {
        let brute = board.character(at: here, health: 3), tinkerer = board.character("tinkerer", at: HexCoord(1, 1))
        let pet = board.summon(of: brute, at: HexCoord(3, 4))
        let guardian = try board.monster(at: beside)
        let cards = brute.handCards
        XCTAssertEqual(cards.count, 10, "the Brute's hand")
        brute.handCards = Array(cards[0..<5])
        brute.discardedCards = Array(cards[5..<7])
        brute.activeCards = [cards[7]]
        brute.lostCards = Array(cards[8...])

        let died = await coord.performAttack(attacker: guardian.piece, target: .character(brute.id),
                                             attack: AttackParameters(value: 3), drawCard: { .standard(.plus0) })
        XCTAssertTrue(died)
        XCTAssertTrue(brute.exhausted)
        XCTAssertEqual(brute.lostCards.sorted(), cards.sorted(), "all ten are lost")
        XCTAssertTrue(brute.handCards.isEmpty && brute.discardedCards.isEmpty && brute.activeCards.isEmpty)
        XCTAssertNil(board.hex(.character(brute.id)), "off the map")
        XCTAssertNil(board.hex(pet.piece), "with the summon")
        XCTAssertTrue(pet.entity.dead)
        XCTAssertNil(coord.scenarioResult, "the Tinkerer plays on")

        // No further turn: the round's order passes the Brute by.
        board.play(try board.card("Stun Shot", of: "tinkerer"), try board.card("Enhancement Field", of: "tinkerer"), for: tinkerer)
        board.startTurns([TurnOrderEntry(figure: .character(brute), initiative: 10),
                          TurnOrderEntry(figure: .character(tinkerer), initiative: 20)])
        XCTAssertEqual(coord.activePlayerTurn?.characterID, tinkerer.id)

        // The last character exhausted loses the scenario.
        coord.sufferDamage(99, to: .character(tinkerer.id))
        XCTAssertEqual(coord.scenarioResult, .defeat)
    }

    /// RND-2 (p.28): cards in the active area are neither in hand nor discarded — a character
    /// with nothing but active cards can neither play two cards nor rest, and is exhausted when
    /// cards are chosen; one with two discards must rest instead.
    func testACharacterWithOnlyActiveCardsIsExhaustedAtCardSelection() throws {
        let brute = board.character(at: here), tinkerer = board.character("tinkerer", at: HexCoord(1, 1))
        let scoundrel = board.character("scoundrel", at: HexCoord(1, 5))
        let cards = brute.handCards
        brute.handCards = []
        brute.activeCards = Array(cards[0..<5])
        brute.lostCards = Array(cards[5...])
        let others = tinkerer.handCards
        tinkerer.handCards = [others[0]]
        tinkerer.discardedCards = [others[1], others[2]]
        tinkerer.activeCards = Array(others[3...])

        coord.beginCardSelection()
        XCTAssertTrue(brute.exhausted, "no hand, no discard: the cards in play don't count")
        XCTAssertEqual(brute.lostCards.sorted(), cards.sorted())
        XCTAssertTrue(brute.activeCards.isEmpty)
        XCTAssertNil(board.hex(.character(brute.id)))
        XCTAssertFalse(tinkerer.exhausted)
        XCTAssertTrue(tinkerer.longRest, "one card in hand, two discarded: a long rest")
        XCTAssertEqual(coord.cardSelectingCharacterID, scoundrel.id, "the Scoundrel chooses as usual")
    }
}
