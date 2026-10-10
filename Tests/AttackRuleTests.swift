import XCTest
@testable import GlavenGameLib

/// The attack rules (rulebook pp. 19–22; gh-rules.md ATK-1 … ATK-12, CND-2, CND-8), each through
/// `BoardCoordinator.performAttack` or a real turn on a board, with the decks stacked so the
/// cards drawn — and how many — are known.
@MainActor
final class AttackRuleTests: XCTestCase {

    private var board: RuleBoard!
    private var coord: BoardCoordinator { board.coord }
    private let here = HexCoord(3, 3), beside = HexCoord(4, 3), twoAway = HexCoord(5, 3)

    override func setUp() async throws {
        board = try RuleBoard()
        XCTAssertEqual(here.distance(to: beside), 1)
        XCTAssertEqual(here.distance(to: twoAway), 2)
    }

    private func shield(_ value: Int) -> ActionModel { ActionModel(type: .shield, value: .int(value)) }

    private func poison(_ entity: any Entity) {
        entity.entityConditions.append(EntityCondition(name: .poison, state: .normal))
    }

    private func curses(in deck: AttackModifierDeck) -> Int { deck.cards.filter { $0.type == .curse }.count }

    /// Give `character` a real turn with these two cards, outside the round's order.
    private func turn(for character: GameCharacter, top: String, bottom: String) throws -> PlayerTurnController {
        let deck = character.name
        let topCard = try board.card(top, of: deck), bottomCard = try board.card(bottom, of: deck)
        character.handCards = [topCard.cardId!, bottomCard.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: board.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: topCard, bottom: bottomCard)
        return turn
    }

    /// Tap `target` for the attack the board is waiting on and let it resolve.
    private func attack(_ target: PieceID, in turn: PlayerTurnController,
                        file: StaticString = #filePath, line: UInt = #line) async {
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, targets.contains(target) else {
            return XCTFail("the attack waits for a target, \(target) among them: \(coord.interactionMode)", file: file, line: line)
        }
        coord.handlePieceTap(target)
        let done = await board.settle { !turn.isWaiting }
        XCTAssertTrue(done, "the attack resolves", file: file, line: line)
    }

    // MARK: - ATK-1: a ranged attack on an adjacent enemy

    /// ATK-1 (p.19): "any ranged attack targeting an adjacent enemy gains Disadvantage" — two
    /// cards are drawn and the worse is used. Two hexes away, and in melee, it is one card.
    func testARangedAttackOnAnAdjacentEnemyDrawsTwoCardsAndKeepsTheWorse() async throws {
        let brute = board.character(at: here)
        let near = try board.monster(at: beside), far = try board.monster(at: twoAway)
        brute.attackModifierDeck = RuleBoard.deck([.plus2, .minus1, .plus1, .plus2, .plus0])
        let ranged = AttackParameters(value: 3, isRanged: true, range: 3)

        await coord.performAttack(attacker: .character(brute.id), target: near.piece, attack: ranged)
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2, "adjacent: two cards")
        XCTAssertEqual(near.entity.health, 30 - 2, "the worse of +2 and −1")

        await coord.performAttack(attacker: .character(brute.id), target: far.piece, attack: ranged)
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 3, "two hexes away: one card")
        XCTAssertEqual(far.entity.health, 30 - 4, "the +1 it drew")

        await coord.performAttack(attacker: .character(brute.id), target: near.piece, attack: AttackParameters(value: 3))
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 4, "a melee attack on the adjacent one: one card")
        XCTAssertEqual(near.entity.health, 30 - 2 - 5)
    }

    /// The same through a card: Spare Dagger's top (Attack 3, Range 3) thrown at the enemy
    /// beside the Brute is made with Disadvantage, and the log says so.
    func testARangedCardPlayedOnAnAdjacentEnemyHasDisadvantage() async throws {
        let brute = board.character(at: here)
        let near = try board.monster(at: beside)
        brute.attackModifierDeck = RuleBoard.deck([.plus1, .minus2, .plus0, .plus0])
        let turn = try turn(for: brute, top: "Spare Dagger", bottom: "Trample")
        turn.executeCurrentAction()
        await attack(near.piece, in: turn)
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2)
        XCTAssertEqual(near.entity.health, 30 - 1, "Attack 3 with the −2, not the +1")
        XCTAssertTrue(coord.turnLog.contains { $0.message.contains("with disadvantage") })
    }

    /// And for a monster: an archer that can't step away shoots the character beside it with
    /// Disadvantage; another shooting from two hexes draws one card.
    func testAnArcherBesideItsTargetShootsWithDisadvantage() async throws {
        let brute = board.character(at: here, health: 40)
        let archer = try board.monster("bandit-archer", at: beside)
        archer.entity.entityConditions = [EntityCondition(name: .immobilize, state: .normal)]
        let card = try board.card(of: "bandit-archer") { card in
            let kinds = MonsterAbility.flattened(card.actions ?? []).map(\.type)
            return kinds.contains(.attack) && !kinds.contains(.condition) && !kinds.contains(.element)
        }
        try board.draw(try XCTUnwrap(card.cardId), for: "bandit-archer")
        board.game.monsterAttackModifierDeck = RuleBoard.deck([.plus2, .minus1, .plus2, .plus2])
        try await board.act("bandit-archer")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 2, "two cards for the one attack")
        let hurt = 40 - brute.health

        // The same card from two hexes away: one card, the +2 — three more than with the −1.
        coord.boardState.movePiece(archer.piece, to: twoAway)
        archer.entity.entityConditions = [EntityCondition(name: .immobilize, state: .normal)]
        brute.health = 40
        try await board.act("bandit-archer")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 3)
        XCTAssertEqual(40 - brute.health, hurt + 3)
    }

    // MARK: - ATK-2, ATK-8, ATK-12, CND-2: what changes an attack's damage, on the board

    /// CND-2 (p.22): "all enemies add +1 Attack to all of their attacks targeting the figure".
    func testPoisonOnTheTargetAddsOneToAnEnemysAttack() async throws {
        let brute = board.character(at: here, health: 20)
        let guardian = try board.monster(at: beside)
        poison(guardian.entity)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 3),
                                  drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30 - 4)

        // A poisoned character is hit harder by a monster in the same way.
        poison(brute)
        await coord.performAttack(attacker: guardian.piece, target: .character(brute.id), attack: AttackParameters(value: 2),
                                  drawCard: { .standard(.plus0) })
        XCTAssertEqual(brute.health, 20 - 3)
    }

    /// ATK-12 (p.25): Shield X reduces each attack on the figure by X, and a figure's Shields
    /// add — here the one on its stat card and the one this round's ability card gave it.
    func testShieldReducesAnAttackAndSeveralShieldsAdd() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        guardian.entity.shieldPersistent = shield(2)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 5),
                                  drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30 - 3, "Shield 2")

        guardian.entity.shield = shield(1)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 5),
                                  drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30 - 3 - 2, "Shield 2 and Shield 1 make Shield 3")
    }

    /// ATK-8 (p.20): Pierce X ignores up to X of the target's Shield — and no more than it has.
    func testPierceIgnoresThatMuchShield() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        guardian.entity.shieldPersistent = shield(3)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece,
                                  attack: AttackParameters(value: 5, pierce: 2), drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30 - 4, "Pierce 2 leaves Shield 1")

        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece,
                                  attack: AttackParameters(value: 5, pierce: 9), drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30 - 4 - 5, "Pierce past the Shield adds nothing")
    }

    /// ATK-2 (p.19): damage is never below 0 — a −2 on an Attack 1, or more Shield than attack,
    /// leaves the target as it was (it is never healed by a hit).
    func testAnAttacksDamageIsNeverBelowZero() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        guardian.entity.health = 12
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 1),
                                  drawCard: { .standard(.minus2) })
        XCTAssertEqual(guardian.entity.health, 12)

        guardian.entity.shieldPersistent = shield(6)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 4),
                                  drawCard: { .standard(.plus1) })
        XCTAssertEqual(guardian.entity.health, 12)
    }

    /// ATK-2: the order — the attacker's bonuses (Poison's +1 among them), then the card, then
    /// the Shield. Attack 2 on a poisoned Shield 1 target with a ×2 is (2 + 1) × 2 − 1 = 5.
    func testPoisonComesBeforeTheCardAndShieldAfterIt() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        poison(guardian.entity)
        guardian.entity.shieldPersistent = shield(1)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 2),
                                  drawCard: { .standard(.double_) })
        XCTAssertEqual(guardian.entity.health, 30 - 5)
    }

    // MARK: - ATK-3, CND-8: what is not an attack

    /// ATK-13 (p.25): Retaliate "is not an attack": no card is drawn for it, and neither the
    /// attacker's Shield nor its Poison changes it.
    func testRetaliateDrawsNoCardAndIgnoresShieldAndPoison() async throws {
        let brute = board.character(at: here, health: 20)
        brute.shield = shield(5)
        poison(brute)
        brute.attackModifierDeck = RuleBoard.deck(of: .plus0)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus2)
        let guardian = try board.monster(at: beside)
        guardian.entity.retaliate = [ActionModel(type: .retaliate, value: .int(2))]
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece, attack: AttackParameters(value: 3))
        XCTAssertEqual(brute.health, 20 - 2, "exactly the Retaliate")
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 1, "the Brute's own attack")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 0, "nothing for the Retaliate")
    }

    /// ATK-3, CND-8 (p.14, p.22): a trap does 2 + L and hazardous terrain half of it, whatever
    /// Shield or Poison the figure walking in has, and no card is drawn. At level 3: 5 and 2.
    func testTrapsAndHazardsDrawNoCardAndIgnoreShieldAndPoison() async throws {
        board = try RuleBoard(level: 3)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus2)
        let walker = try board.monster(at: here)
        walker.entity.shieldPersistent = shield(3)
        poison(walker.entity)
        coord.boardState.cells[beside]?.overlay = .trap
        coord.boardState.cells[twoAway]?.overlay = .hazard

        await coord.moveAlong(walker.piece, path: [here, beside], style: .normal)
        XCTAssertEqual(walker.entity.health, 30 - 5, "the trap: 2 + 3")
        XCTAssertFalse(coord.boardState.cells[beside]?.isTrap ?? true, "and it is gone")

        await coord.moveAlong(walker.piece, path: [beside, twoAway], style: .normal)
        XCTAssertEqual(walker.entity.health, 30 - 5 - 2, "hazardous terrain: half of 5, rounded down")
        XCTAssertTrue(coord.boardState.cells[twoAway]?.isHazard ?? false, "which stays")
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 0)

        // A character too.
        let brute = board.character(at: HexCoord(3, 6), health: 20)
        brute.shield = shield(4)
        poison(brute)
        brute.attackModifierDeck = RuleBoard.deck(of: .plus2)
        coord.boardState.cells[HexCoord(4, 6)]?.overlay = .trap
        await coord.moveAlong(.character(brute.id), path: [HexCoord(3, 6), HexCoord(4, 6)], style: .normal)
        XCTAssertEqual(brute.health, 20 - 5)
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 0)
    }

    /// CND-3, CND-8 (p.22): a Wound is 1 damage at the start of the figure's turn — not an
    /// attack, so the monster's Shield doesn't stop it, its Poison doesn't raise it, and no card
    /// is drawn.
    func testAWoundDrawsNoCardAndIgnoresShieldAndPoison() async throws {
        let wounded = try board.monster(at: here)
        wounded.entity.shieldPersistent = shield(3)
        wounded.entity.entityConditions = [EntityCondition(name: .wound, state: .normal),
                                           EntityCondition(name: .poison, state: .normal)]
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus2)
        let anyCard = try board.card(of: "bandit-guard") { _ in true }
        try board.draw(try XCTUnwrap(anyCard.cardId), for: "bandit-guard")
        try await board.act("bandit-guard")
        XCTAssertEqual(wounded.entity.health, 30 - 1)
        XCTAssertEqual(RuleBoard.drawn(board.game.monsterAttackModifierDeck), 0)
        XCTAssertTrue(board.has(.wound, wounded.entity), "and the Wound stays until healed")
    }

    // MARK: - ATK-6: an attack's effects

    /// ATK-6 (p.19, p.22): an attack's conditions and push "are applied regardless of whether
    /// the attack does damage" — a Null draw takes the damage and nothing else.
    func testAnAttacksConditionsAndPushLandOnANullDraw() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        let died = await coord.performAttack(attacker: .character(brute.id), target: guardian.piece,
                                             attack: AttackParameters(value: 4, conditions: [.poison, .muddle], push: 1),
                                             drawCard: { .standard(.null_) })
        XCTAssertFalse(died)
        XCTAssertEqual(guardian.entity.health, 30, "no damage")
        XCTAssertTrue(board.has(.poison, guardian.entity))
        XCTAssertTrue(board.has(.muddle, guardian.entity))
        XCTAssertEqual(board.hex(guardian.piece)?.distance(to: here), 2, "pushed one hex")
    }

    /// …and fully shielded, the same: the effects still land.
    func testAnAttackStoppedByShieldStillAppliesItsEffects() async throws {
        let brute = board.character(at: here)
        let guardian = try board.monster(at: beside)
        guardian.entity.shieldPersistent = shield(9)
        await coord.performAttack(attacker: .character(brute.id), target: guardian.piece,
                                  attack: AttackParameters(value: 3, conditions: [.wound], pull: 0),
                                  drawCard: { .standard(.plus0) })
        XCTAssertEqual(guardian.entity.health, 30)
        XCTAssertTrue(board.has(.wound, guardian.entity))
    }

    /// ATK-6 (p.19): "if the target is killed or exhausted by the attack, no added effects are
    /// applied". A Curse is the effect that would show: it goes into a deck, whoever is left.
    func testAnAttackThatKillsItsTargetAppliesNoneOfItsEffects() async throws {
        let brute = board.character(at: here, health: 3)
        let doomed = try board.monster(at: beside, health: 3), survivor = try board.monster(at: HexCoord(3, 4))
        XCTAssertEqual(here.distance(to: HexCoord(3, 4)), 1)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .plus0)
        brute.attackModifierDeck = RuleBoard.deck(of: .plus0)
        let cursing = AttackParameters(value: 3, conditions: [.curse, .poison], push: 1)

        let died = await coord.performAttack(attacker: .character(brute.id), target: doomed.piece, attack: cursing)
        XCTAssertTrue(died)
        XCTAssertNil(board.hex(doomed.piece), "dead and off the board, not pushed anywhere")
        XCTAssertEqual(curses(in: board.game.monsterAttackModifierDeck), 0, "no Curse from an attack that killed")
        XCTAssertFalse(doomed.entity.entityConditions.contains { $0.name == .poison })

        // The same attack on one who lives through it does curse the monsters.
        await coord.performAttack(attacker: .character(brute.id), target: survivor.piece, attack: cursing)
        XCTAssertEqual(curses(in: board.game.monsterAttackModifierDeck), 1)
        XCTAssertTrue(board.has(.poison, survivor.entity))

        // A character exhausted by an attack gains nothing from it either.
        await coord.performAttack(attacker: survivor.piece, target: .character(brute.id),
                                  attack: AttackParameters(value: 3, conditions: [.curse, .wound]))
        XCTAssertTrue(brute.exhausted)
        XCTAssertEqual(curses(in: brute.attackModifierDeck), 0)
        XCTAssertFalse(brute.entityConditions.contains { $0.name == .wound })
    }

    // MARK: - ATK-10: areas

    /// ATK-10 (p.20): "each target constitutes a separate attack (drawing its own attack
    /// modifier card)". Sweeping Blow (Attack 2 on three hexes) on two Guards with a +1 and a −1
    /// on top of the Brute's deck: one takes 3, the other 1, and two cards are gone.
    func testEachTargetOfAnAreaIsItsOwnAttackWithItsOwnDraw() async throws {
        let brute = board.character(at: here)
        let ring = here.neighbors.filter { coord.boardState.cells[$0] != nil }
        let pair = try XCTUnwrap(ring.lazy.compactMap { a in ring.first { $0.isAdjacent(to: a) }.map { (a, $0) } }.first,
                                 "two hexes beside the Brute and beside each other")
        let first = try board.monster(at: pair.0), second = try board.monster(at: pair.1)
        brute.attackModifierDeck = RuleBoard.deck([.plus1, .minus1, .plus0, .plus0])
        let turn = try turn(for: brute, top: "Sweeping Blow", bottom: "Trample")
        turn.executeCurrentAction()
        await attack(first.piece, in: turn)
        XCTAssertEqual([30 - first.entity.health, 30 - second.entity.health].sorted(), [1, 3])
        XCTAssertEqual(RuleBoard.drawn(brute.attackModifierDeck), 2)
    }

    // MARK: - SET-9, ACT-5, MON-7: whose deck

    /// A character draws from their own deck, a summon from its owner's (p.26), a monster from
    /// the monster deck and a monster allied to the party from the ally deck (p.30) — each in a
    /// real attack that is handed no card.
    func testEveryFigureDrawsFromItsOwnSidesDeck() async throws {
        let brute = board.character(at: here, health: 20)
        let enemy = try board.monster(at: beside, health: 60)
        let ally = try board.monster("inox-guard", at: twoAway)
        try board.type("inox-guard").isAlly = true
        XCTAssertTrue(coord.isPlayerSide(ally.piece))
        let pet = board.summon(of: brute, at: HexCoord(4, 4), attack: 2, move: 0)
        XCTAssertEqual(HexCoord(4, 4).distance(to: beside), 1)

        brute.attackModifierDeck = RuleBoard.deck(of: .plus2)
        board.game.monsterAttackModifierDeck = RuleBoard.deck(of: .minus1)
        board.game.allyAttackModifierDeck = RuleBoard.deck(of: .plus1)
        func drawn() -> [Int] {
            [brute.attackModifierDeck, board.game.monsterAttackModifierDeck, board.game.allyAttackModifierDeck].map(RuleBoard.drawn)
        }

        await coord.performAttack(attacker: .character(brute.id), target: enemy.piece, attack: AttackParameters(value: 3))
        XCTAssertEqual(enemy.entity.health, 60 - 5, "the Brute's +2")
        XCTAssertEqual(drawn(), [1, 0, 0])

        // The summon's own turn: Attack 2 with its owner's +2.
        await SummonTurnController(coordinator: coord, gameManager: board.gm).executeSummonTurns(for: brute)
        XCTAssertEqual(enemy.entity.health, 60 - 5 - 4, "the summon drew the Brute's +2")
        XCTAssertEqual(drawn(), [2, 0, 0])

        await coord.performAttack(attacker: enemy.piece, target: .character(brute.id), attack: AttackParameters(value: 3))
        XCTAssertEqual(brute.health, 20 - 2, "the monsters' −1")
        XCTAssertEqual(drawn(), [2, 1, 0])

        await coord.performAttack(attacker: ally.piece, target: enemy.piece, attack: AttackParameters(value: 3))
        XCTAssertEqual(enemy.entity.health, 60 - 5 - 4 - 4, "the allies' +1")
        XCTAssertEqual(drawn(), [2, 1, 1])
    }
}
