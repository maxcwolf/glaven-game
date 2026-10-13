import XCTest
@testable import GlavenGameLib

/// Conditions (rulebook pp. 22–23 and the FAQ's "Conditions"; gh-rules.md CND-1 … CND-6), through
/// real turns on a board: how long each lasts for a character, a monster and a summon, what a
/// stunned, immobilized, disarmed, invisible or strengthened figure can and can't do, and which
/// deck a Curse goes into.
@MainActor
final class ConditionRuleTests: XCTestCase {

    private var board: RuleBoard!
    private var coord: BoardCoordinator { board.coord }
    private let here = HexCoord(3, 3), beside = HexCoord(4, 3), twoAway = HexCoord(5, 3)

    /// The conditions that last "until the end of the figure's next turn".
    private let passing: [ConditionName] = [.immobilize, .disarm, .muddle, .invisible, .strengthen]

    override func setUp() async throws {
        board = try RuleBoard()
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus0)
        board.game.allyAttackModifierDeck = RuleBoard.deck(of: .plus0)
    }

    // MARK: - Turns

    /// The character plays a whole turn of the round (two cards, nothing done with them), with
    /// `during` run while the turn is theirs.
    private func takeTurn(_ character: GameCharacter, during: (() -> Void)? = nil,
                          file: StaticString = #filePath, line: UInt = #line) throws {
        let top = try board.card("Trample", of: "brute"), bottom = try board.card("Spare Dagger", of: "brute")
        character.discardedCards.removeAll { $0 == top.cardId || $0 == bottom.cardId }
        board.play(top, bottom, for: character)
        board.startTurns([TurnOrderEntry(figure: .character(character), initiative: Double(character.initiative))])
        XCTAssertEqual(coord.activePlayerTurn?.characterID, character.id, "the turn is the character's", file: file, line: line)
        during?()
        board.endTurn(file: file, line: line)
        if coord.pendingShortRest != nil { coord.skipShortRest() }
        XCTAssertNil(coord.activePlayerTurn, "and it has ended", file: file, line: line)
    }

    /// A Guard card with a Move and an Attack and nothing that would change the numbers.
    private func drawAPlainGuardCard() throws {
        let card = try board.card(of: "bandit-guard") { card in
            let kinds = Set(MonsterAbility.flattened(card.actions ?? []).map(\.type))
            return kinds == [.move, .attack]
        }
        try board.draw(try XCTUnwrap(card.cardId), for: "bandit-guard")
    }

    // MARK: - CND-1, CND-4: how long a condition lasts

    /// CND-4 (p.22): a condition a character gains outside their turn is with them for their
    /// next turn and gone as it ends.
    func testAConditionGainedOutsideACharactersTurnEndsWithTheirNextTurn() throws {
        for condition in passing {
            board = try RuleBoard()
            let brute = board.character(at: here)
            coord.applyCondition(condition, to: .character(brute.id))
            var hadIt = false
            try takeTurn(brute) { hadIt = self.board.has(condition, brute) }
            XCTAssertTrue(hadIt, "\(condition) holds during the turn")
            XCTAssertFalse(board.has(condition, brute), "\(condition) is gone when the turn ends")
        }
    }

    /// FAQ: a condition gained during the figure's own turn "lasts through their next turn" —
    /// it doesn't fall off at the end of the turn it arrived in.
    func testAConditionGainedOnACharactersOwnTurnLastsThroughTheirNextTurn() throws {
        for condition in passing {
            board = try RuleBoard()
            let brute = board.character(at: here)
            try takeTurn(brute) { self.coord.applyCondition(condition, to: .character(brute.id)) }
            XCTAssertTrue(board.has(condition, brute), "\(condition) outlasts the turn it was gained in")
            var hadIt = false
            try takeTurn(brute) { hadIt = self.board.has(condition, brute) }
            XCTAssertTrue(hadIt, "\(condition) holds for the whole of the next turn")
            XCTAssertFalse(board.has(condition, brute), "and ends with it")
        }
    }

    /// CND-1 (p.22): a figure has a condition once, and gaining it again only renews it: a
    /// Muddle given again during the turn it was to end with lasts through the turn after.
    func testReapplyingAConditionRenewsItsDuration() throws {
        let brute = board.character(at: here)
        coord.applyCondition(.muddle, to: .character(brute.id))
        coord.applyCondition(.muddle, to: .character(brute.id))
        XCTAssertEqual(brute.entityConditions.filter { $0.name == .muddle }.count, 1, "one of each condition")
        try takeTurn(brute) { self.coord.applyCondition(.muddle, to: .character(brute.id)) }
        XCTAssertEqual(brute.entityConditions.filter { $0.name == .muddle }.count, 1)
        XCTAssertTrue(board.has(.muddle, brute), "renewed on this turn: still there as it ends")
        try takeTurn(brute)
        XCTAssertFalse(board.has(.muddle, brute))
    }

    /// The same for a monster, through its own turns: disarmed outside its turn it makes no
    /// attack on its next turn and attacks again on the one after.
    func testAConditionGainedOutsideAMonstersTurnEndsWithItsNextTurn() async throws {
        let brute = board.character(at: here, health: 40)
        let guardian = try board.monster(at: beside)
        try drawAPlainGuardCard()
        coord.applyCondition(.disarm, to: guardian.piece)

        try await board.act("bandit-guard")
        XCTAssertEqual(brute.health, 40, "disarmed: no attack")
        XCTAssertFalse(board.has(.disarm, guardian.entity), "gone at the end of that turn")

        try await board.act("bandit-guard")
        XCTAssertLessThan(brute.health, 40, "armed again on its next turn")
    }

    /// A monster muddled in the middle of its own turn (here as it attacks) is still muddled on
    /// its next turn — two cards, the worse kept — and no longer on the turn after.
    func testAConditionGainedOnAMonstersOwnTurnLastsThroughItsNextTurn() async throws {
        let brute = board.character(at: here, health: 60)
        let guardian = try board.monster(at: beside)
        try drawAPlainGuardCard()
        var muddleOnAttack = true
        coord.attackObserver = { attacker, _ in
            if muddleOnAttack, attacker == guardian.piece { self.coord.applyCondition(.muddle, to: attacker) }
        }

        try await board.act("bandit-guard")
        XCTAssertLessThan(brute.health, 60, "it attacked, and was muddled as it did")
        XCTAssertTrue(board.has(.muddle, guardian.entity), "muddled on its own turn: not gone as that turn ends")
        muddleOnAttack = false

        board.game.monsterAttackModifierDeck = RuleBoard.deck([.plus1, .minus1, .plus1, .plus1])
        let before = brute.health
        try await board.act("bandit-guard")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 2, "its next turn: Disadvantage")
        XCTAssertFalse(board.has(.muddle, guardian.entity), "and the Muddle ends with that turn")
        let hurtWithMinusOne = before - brute.health

        let again = brute.health
        try await board.act("bandit-guard")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 3, "the turn after: one card")
        XCTAssertEqual(again - brute.health, hurtWithMinusOne + 2, "the +1 instead of the −1")
    }

    /// And for a summon, whose turn comes before its owner's: muddled as it attacks (so that
    /// attack is already made with Disadvantage), it is still muddled on its next turn and no
    /// longer on the one after.
    func testAConditionGainedOnASummonsOwnTurnLastsThroughItsNextTurn() async throws {
        let brute = board.character(at: here)
        let pet = board.summon(of: brute, at: beside, attack: 2, move: 0)
        let enemy = try board.monster(at: twoAway, health: 60)
        XCTAssertEqual(beside.distance(to: twoAway), 1)
        brute.attackModifierDeck = RuleBoard.deck([.plus0, .plus0, .plus1, .minus1, .plus1, .plus1])
        var muddleOnAttack = true
        coord.attackObserver = { attacker, _ in
            if muddleOnAttack, attacker == pet.piece { self.coord.applyCondition(.muddle, to: attacker) }
        }
        func summonsAct() async { await SummonTurnController(coordinator: coord, gameManager: board.gm).executeSummonTurns(for: brute) }

        await summonsAct()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2)
        XCTAssertTrue(board.has(.muddle, pet.entity), "muddled on its own turn: not gone as that turn ends")
        muddleOnAttack = false

        await summonsAct()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 4, "its next turn: two cards")
        XCTAssertEqual(enemy.entity.health, 60 - 2 - 1, "Attack 2, then Attack 2 with the \u{2212}1 kept over the +1")
        XCTAssertFalse(board.has(.muddle, pet.entity), "and the Muddle ends with that turn")

        await summonsAct()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 5, "the turn after: one")
        XCTAssertEqual(enemy.entity.health, 60 - 2 - 1 - 3)

        // Gained outside its turn, a condition ends with the summon's next turn.
        coord.applyCondition(.disarm, to: pet.piece)
        let health = enemy.entity.health
        await summonsAct()
        XCTAssertEqual(enemy.entity.health, health, "disarmed: no attack")
        XCTAssertFalse(board.has(.disarm, pet.entity))
    }

    // MARK: - CND-4: Stun, Immobilize, Disarm

    /// CND-4 (p.22): a stunned character still plays two cards, performs nothing, and the cards
    /// are discarded; the Stun is gone when that turn ends.
    func testAStunnedCharactersTwoCardsAreDiscardedAndNothingIsPerformed() throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        let top = try board.card("Shield Bash", of: "brute"), bottom = try board.card("Grab and Go", of: "brute")
        board.play(top, bottom, for: brute)
        coord.applyCondition(.stun, to: .character(brute.id))
        let experience = brute.experience

        board.startTurns([TurnOrderEntry(figure: .character(brute), initiative: 15)])
        if coord.pendingShortRest != nil { coord.skipShortRest() }

        XCTAssertNil(coord.activePlayerTurn, "no turn to play")
        XCTAssertEqual(brute.discardedCards.sorted(), [top.cardId!, bottom.cardId!].sorted(), "both cards are discarded")
        XCTAssertTrue(brute.lostCards.isEmpty, "Shield Bash's lost icon costs nothing: it wasn't performed")
        XCTAssertFalse(brute.handCards.contains(top.cardId!))
        XCTAssertEqual(guardian.entity.health, 30)
        XCTAssertEqual(board.hex(.character(brute.id)), here)
        XCTAssertEqual(brute.experience, experience)
        XCTAssertFalse(board.has(.stun, brute), "the Stun ends with the turn it took")
    }

    /// CND-4 (p.22): "the figure cannot … use items". Attacked while stunned, a character is
    /// not offered their Heater Shield.
    func testAStunnedCharacterIsNotOfferedTheirShieldItem() async throws {
        coord.autoResolvePrompts = false
        let brute = board.character(at: here, health: 20)
        brute.items = ["gh-8"]   // Heater Shield: Shield 1 for an attack
        brute.entityConditions = [EntityCondition(name: .stun, state: .normal)]
        let guardian = try board.monster(at: beside)
        let attacking = Task { @MainActor in
            await self.coord.performAttack(attacker: guardian.piece, target: .character(brute.id),
                                           attack: AttackParameters(value: 3), drawCard: { .standard(.plus0) })
        }
        await board.settle(timeout: 0.5) { self.coord.pendingItemUse != nil || brute.health < 20 }
        XCTAssertNil(coord.pendingItemUse, "no item while stunned")
        coord.resolvePendingItemUse(false)
        // The damage itself may still be negated by losing a card (not an item): it is taken.
        await board.settle(timeout: 1) { self.coord.pendingDamage != nil || brute.health < 20 }
        coord.resolvePendingDamage(choice: .takeDamage)
        _ = await attacking.value
        XCTAssertEqual(brute.health, 20 - 3)
    }

    /// CND-4: an immobilized character's Move does nothing (Grab and Go's bottom, Move 4), and a
    /// disarmed character's Attack neither (Trample's top) — the cards are still played.
    func testAnImmobilizedCharacterCannotMoveAndADisarmedOneCannotAttack() throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        let attack = try board.card("Trample", of: "brute"), move = try board.card("Grab and Go", of: "brute")
        brute.entityConditions = [EntityCondition(name: .immobilize, state: .normal), EntityCondition(name: .disarm, state: .normal)]
        board.play(attack, move, for: brute)
        board.startTurns([TurnOrderEntry(figure: .character(brute), initiative: 72)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)

        turn.executeCurrentAction()   // Attack 3, Pierce 2
        if case .selectingAttackTarget = coord.interactionMode { XCTFail("a disarmed character is offered no target") }
        while turn.phase == .executeTopAction { turn.executeCurrentAction() }
        XCTAssertEqual(turn.phase, .executeBottomAction)
        turn.executeCurrentAction()   // Move 4
        if case .selectingMove = coord.interactionMode { XCTFail("an immobilized character is offered no hex") }
        board.endTurn()
        XCTAssertEqual(guardian.entity.health, 30)
        XCTAssertEqual(board.hex(.character(brute.id)), here)
        XCTAssertEqual(brute.discardedCards.sorted(), [attack.cardId!, move.cardId!].sorted())
    }

    // MARK: - CND-4, CND-5: Muddle, Strengthen, Invisible

    /// CND-5 (p.23): a strengthened figure "gains Advantage on all of its attacks" — two cards,
    /// the better kept; CND-4: a muddled one Disadvantage; with both, one card (p.20).
    func testStrengthenGivesAdvantageMuddleDisadvantageAndBothCancel() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside, health: 90)
        let plain = AttackParameters(value: 3)
        func strike() async { await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: plain) }

        brute.attackModifierDeck = RuleBoard.deck([.minus1, .plus2, .plus0, .plus0])
        brute.entityConditions = [EntityCondition(name: .strengthen, state: .normal)]
        await strike()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2)
        XCTAssertEqual(guardian.entity.health, 90 - 5, "the +2, not the −1")

        brute.attackModifierDeck = RuleBoard.deck([.plus2, .minus1, .plus0, .plus0])
        brute.entityConditions = [EntityCondition(name: .muddle, state: .normal)]
        await strike()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2)
        XCTAssertEqual(guardian.entity.health, 90 - 5 - 2, "the −1, not the +2")

        brute.attackModifierDeck = RuleBoard.deck([.plus2, .minus1, .plus0, .plus0])
        brute.entityConditions = [EntityCondition(name: .muddle, state: .normal), EntityCondition(name: .strengthen, state: .normal)]
        await strike()
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 1, "one of each cancels")
        XCTAssertEqual(guardian.entity.health, 90 - 5 - 2 - 5)

        // Muddled and shooting an adjacent enemy: Disadvantage once, not twice.
        brute.attackModifierDeck = RuleBoard.deck([.plus2, .minus1, .minus2, .plus0])
        brute.entityConditions = [EntityCondition(name: .muddle, state: .normal)]
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece,
                                  attack: AttackParameters(value: 3, isRanged: true, range: 3))
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2, "they don't stack")
        XCTAssertEqual(guardian.entity.health, 90 - 5 - 2 - 5 - 2)
    }

    /// CND-5, MON-4 (p.23, p.29): an invisible character can't be focused on or targeted. A
    /// Guard beside one walks off to the character it can see; with no one else to see it does
    /// nothing at all.
    func testAnInvisibleCharacterIsNotAttacked() async throws {
        let hidden = board.character("scoundrel", at: here, health: 20)
        hidden.entityConditions = [EntityCondition(name: .invisible, state: .normal)]
        let guardian = try board.monster(at: beside)
        try drawAPlainGuardCard()

        try await board.act("bandit-guard")
        XCTAssertEqual(hidden.health, 20)
        XCTAssertEqual(board.hex(guardian.piece), beside, "no focus: it neither moves nor attacks")

        let seen = board.character("brute", at: HexCoord(6, 3), health: 20)
        XCTAssertEqual(beside.distance(to: HexCoord(6, 3)), 2)
        try await board.act("bandit-guard")
        XCTAssertEqual(hidden.health, 20, "still not the one beside it")
        XCTAssertLessThan(seen.health, 20, "the visible character is attacked")
        XCTAssertEqual(board.hex(guardian.piece)?.distance(to: HexCoord(6, 3)), 1)
    }

    /// CND-5: an attack a Cultist makes as it dies ("On death: Attack +2" on the hexes around
    /// it) is an attack like any other: it can't target the invisible character beside it.
    /// (Found by the veteran playthroughs of #4, #83 and #89, where an invisible Scoundrel is hit.)
    func testADyingCultistsAttackDoesNotReachAnInvisibleCharacter() async throws {
        let hidden = board.character("scoundrel", at: here, health: 20), seen = board.character("brute", at: HexCoord(4, 4), health: 20)
        hidden.entityConditions = [EntityCondition(name: .invisible, state: .normal)]
        let cultist = try board.monster("cultist", at: beside, health: 1)
        XCTAssertEqual(HexCoord(4, 4).distance(to: beside), 1)
        try board.draw(604, for: "cultist")   // Move −1, Attack −1; on death: Attack +2 on the hexes around
        var attacked: [PieceID] = []
        coord.attackObserver = { _, target in attacked.append(target) }

        let died = await coord.performAttack(attacker: .character(seen.id), target: cultist.piece, attack: AttackParameters(value: 3),
                                             drawCard: { .standard(.plus0) })
        XCTAssertTrue(died)
        XCTAssertTrue(attacked.contains(.character(seen.id)), "the visible Brute beside it is attacked as it dies")
        XCTAssertLessThan(seen.health, 20)
        XCTAssertFalse(attacked.contains(.character(hidden.id)), "the invisible Scoundrel is no target")
        XCTAssertEqual(hidden.health, 20)
    }

    /// The same for the players: an invisible monster is no target for a character's attack
    /// (Trample's top, with it the only enemy in reach), so nothing is drawn or performed.
    func testAnInvisibleMonsterCannotBeTargeted() throws {
        let brute = board.character(at: here)
        brute.attackModifierDeck = RuleBoard.deck(of: .plus0)
        let guardian = try board.monster(at: beside)
        guardian.entity.entityConditions = [EntityCondition(name: .invisible, state: .normal)]
        board.play(try board.card("Trample", of: "brute"), try board.card("Grab and Go", of: "brute"), for: brute)
        board.startTurns([TurnOrderEntry(figure: .character(brute), initiative: 72)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        turn.executeCurrentAction()
        if case .selectingAttackTarget = coord.interactionMode { XCTFail("an invisible enemy is offered as a target") }
        XCTAssertTrue(coord.targetableEnemies(of: .character(brute.id), range: 3).isEmpty)
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0)
        XCTAssertEqual(guardian.entity.health, 30)
    }

    // MARK: - CND-2, CND-3: healing

    /// CND-3 (p.22): a heal removes a Wound and still heals; CND-2: it removes Poison and heals
    /// nothing; with both, both go and nothing is healed. Nothing else is cured by a heal.
    func testWhatAHealRemoves() {
        let brute = board.character(at: here, health: 20)
        let piece = PieceID.character(brute.id)

        brute.health = 10
        brute.entityConditions = [EntityCondition(name: .wound, state: .normal), EntityCondition(name: .immobilize, state: .normal)]
        XCTAssertEqual(coord.heal(piece, amount: 3), 3)
        XCTAssertEqual(brute.health, 13, "a Wound doesn't stop the heal")
        XCTAssertEqual(brute.entityConditions.map(\.name), [.immobilize], "the Wound goes, the Immobilize stays")

        brute.entityConditions = [EntityCondition(name: .poison, state: .normal), EntityCondition(name: .muddle, state: .normal)]
        XCTAssertEqual(coord.heal(piece, amount: 3), 0)
        XCTAssertEqual(brute.health, 13, "Poison takes the heal")
        XCTAssertEqual(brute.entityConditions.map(\.name), [.muddle])

        brute.entityConditions = [EntityCondition(name: .poison, state: .normal), EntityCondition(name: .wound, state: .normal)]
        XCTAssertEqual(coord.heal(piece, amount: 3), 0)
        XCTAssertEqual(brute.health, 13)
        XCTAssertTrue(brute.entityConditions.isEmpty, "both removed, nothing healed")

        XCTAssertEqual(coord.heal(piece, amount: 30), 7, "never above the maximum")
        XCTAssertEqual(brute.health, 20)
    }

    // MARK: - CND-6: Curse and Bless

    private func count(_ type: AttackModifierType, in deck: AttackModifierDeck) -> Int {
        deck.cards.filter { $0.type == type }.count
    }

    /// CND-6 (p.23): a Curse goes into the deck its figure draws from — the monster deck for a
    /// monster, the owner's for a summon, the allies' for a monster on the party's side.
    func testACurseGoesIntoTheDeckItsFigureDrawsFrom() throws {
        let brute = board.character(at: here)
        let pet = board.summon(of: brute, at: beside)
        let enemy = try board.monster(at: HexCoord(8, 8))
        let ally = try board.monster("inox-guard", at: HexCoord(8, 3))
        try board.type("inox-guard").isAlly = true
        func curses() -> [Int] {
            [brute.attackModifierDeck, board.game.monsterAttackModifierDeck, board.game.allyAttackModifierDeck].map { count(.curse, in: $0) }
        }

        coord.applyCondition(.curse, to: enemy.piece)
        XCTAssertEqual(curses(), [0, 1, 0], "a monster: the monster deck")
        coord.applyCondition(.curse, to: pet.piece)
        XCTAssertEqual(curses(), [1, 1, 0], "a summon: its owner's deck")
        coord.applyCondition(.curse, to: ally.piece)
        XCTAssertEqual(curses(), [1, 1, 1], "an allied monster: the ally deck")
        coord.applyCondition(.bless, to: pet.piece)
        XCTAssertEqual(count(.bless, in: brute.attackModifierDeck), 1, "a Bless on a summon is its owner's too")
        XCTAssertFalse(pet.entity.entityConditions.contains { $0.name == .curse || $0.name == .bless }, "cards, not tokens")
        XCTAssertFalse(enemy.entity.entityConditions.contains { $0.name == .curse })
    }

    /// CND-6: ten Curses for the monsters and ten for the players' side — characters, their
    /// summons and their allies together; an eleventh is not given.
    func testTheTenCursesOfEachSide() throws {
        let brute = board.character(at: here), tinkerer = board.character("tinkerer", at: HexCoord(1, 1))
        let pet = board.summon(of: tinkerer, at: HexCoord(1, 2))
        let enemy = try board.monster(at: HexCoord(8, 8))
        let ally = try board.monster("inox-guard", at: HexCoord(8, 3))
        try board.type("inox-guard").isAlly = true

        for _ in 0..<4 { coord.applyCondition(.curse, to: .character(brute.id)) }
        for _ in 0..<4 { coord.applyCondition(.curse, to: pet.piece) }
        for _ in 0..<4 { coord.applyCondition(.curse, to: ally.piece) }
        XCTAssertEqual(count(.curse, in: brute.attackModifierDeck), 4)
        XCTAssertEqual(count(.curse, in: tinkerer.attackModifierDeck), 4)
        XCTAssertEqual(count(.curse, in: board.game.allyAttackModifierDeck), 2, "only two of the players' ten were left")

        for _ in 0..<13 { coord.applyCondition(.curse, to: enemy.piece) }
        XCTAssertEqual(count(.curse, in: board.game.monsterAttackModifierDeck), 10, "the monsters have their own ten")

        // A Curse that has been drawn is back in the supply.
        brute.attackModifierDeck = RuleBoard.deck([.curse, .plus0])
        XCTAssertEqual(board.gm.attackModifierManager.drawCharacterCard(for: brute)?.type, .curse)
        coord.applyCondition(.curse, to: .character(tinkerer.id))
        XCTAssertEqual(count(.curse, in: tinkerer.attackModifierDeck), 5)
    }

    // MARK: - A condition with an area

    /// Singing Arrow: "Curse, Range 3" printed beside three hexes. It is aimed like an area
    /// attack — any enemy the area can cover may be chosen — and every enemy in the area as it
    /// is placed is cursed; one outside it is not.
    func testAConditionPrintedWithAnAreaGoesToEveryEnemyInIt() async throws {
        let centre = HexCoord(5, 5)
        let singer = board.character("music-note", at: centre)
        let cluster = try [HexCoord(7, 5), HexCoord(8, 5), HexCoord(8, 6)].map { try board.monster(at: $0) }
        let apart = try board.monster(at: HexCoord(5, 3))
        for (a, b) in [(0, 1), (1, 2), (0, 2)] {
            XCTAssertTrue(coord.boardState.areAdjacent(board.hex(cluster[a].piece)!, board.hex(cluster[b].piece)!), "three hexes in a triangle")
        }
        let curses = board.game.monsterAttackModifierDeck.undrawnCount(of: .curse)
        board.play(try board.card("Singing Arrow", of: "music-note"), try board.card("Tuning the Outcome", of: "music-note"), for: singer)
        board.startTurns([TurnOrderEntry(figure: .character(singer), initiative: 89)])
        let turn = try XCTUnwrap(coord.activePlayerTurn)
        turn.executeCurrentAction()
        guard case .selectingConditionTarget(_, .curse, let options) = coord.interactionMode else {
            return XCTFail("a Curse to aim: \(coord.interactionMode)")
        }
        XCTAssertEqual(options, Set(cluster.map(\.piece) + [apart.piece]), "every enemy the area can reach")
        coord.handlePieceTap(cluster[0].piece)
        await board.settle { !turn.isWaiting }
        XCTAssertEqual(board.game.monsterAttackModifierDeck.undrawnCount(of: .curse), curses + 3, "the three in the area, not the fourth")
        XCTAssertFalse(turn.topActions.contains { $0.type == .area }, "the area is the Curse's, not a step of its own")
    }
}
