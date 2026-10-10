import XCTest
@testable import GlavenGameLib

/// Each check the simulator makes of a playthrough (`PlayLedger`) fires on a bad event — and
/// the simulator itself reports one when the game on its board is made to break the rule. A
/// check that can't fail checks nothing.
@MainActor
final class PlayLedgerTests: XCTestCase {

    private let guardian = PieceID.monster(name: "bandit-guard", standee: 1)
    private let archer = PieceID.monster(name: "bandit-archer", standee: 2)
    private let brute = PieceID.character("gh-brute")

    // MARK: - The checks, fed by hand

    func testAnAttackBeyondItsReachIsAProblem() {
        let from = HexCoord(3, 3)
        XCTAssertNil(PlayLedger.rangeProblem(attacker: guardian, target: brute, from: from, to: HexCoord(4, 3), reach: 1))
        XCTAssertNil(PlayLedger.rangeProblem(attacker: archer, target: brute, from: from, to: HexCoord(6, 3), reach: 3))
        XCTAssertNotNil(PlayLedger.rangeProblem(attacker: guardian, target: brute, from: from, to: HexCoord(5, 3), reach: 1),
                        "a melee attack from two hexes away")
        XCTAssertNotNil(PlayLedger.rangeProblem(attacker: archer, target: brute, from: from, to: HexCoord(7, 3), reach: 3))
    }

    /// A monster's reach is read from its stat card and ability card: the stat card's range, a
    /// card range that replaces it or adds to it, 1 for a melee attack, a pattern's extent.
    func testAMonstersReachIsReadFromItsCards() {
        func attack(_ subs: [ActionModel] = []) -> [ActionModel] {
            [ActionModel(type: .move, value: .int(0)), ActionModel(type: .attack, value: .int(0), valueType: .plus, subActions: subs)]
        }
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 0, card: attack()), 1, "a melee monster")
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 4, card: attack()), 4, "an archer")
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 4, card: attack([ActionModel(type: .range, value: .int(1), valueType: .plus)])), 5)
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 0, card: attack([ActionModel(type: .range, value: .int(3))])), 3,
                       "a range printed on the card of a melee monster")
        XCTAssertNil(PlayLedger.monsterReach(statRange: 4, card: [ActionModel(type: .move, value: .int(1))]), "no attack on the card")
        // A melee area: a line of three hexes from the attacker reaches three.
        let line = ActionModel(type: .area, value: .string("(0,0,active)|(1,0,target)|(2,0,target)|(3,0,target)"))
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 0, card: attack([line])), 3)
        // Inside a group, as some cards print it.
        let grouped = [ActionModel(type: .grid, value: .string("1"), subActions: attack())]
        XCTAssertEqual(PlayLedger.monsterReach(statRange: 2, card: grouped), 2)
    }

    func testAnEnemyAttackedTwiceByOneAbilityIsAProblem() {
        let ledger = PlayLedger()
        XCTAssertNil(ledger.noteAttack(ability: "brute top step 0", target: guardian))
        XCTAssertNil(ledger.noteAttack(ability: "brute top step 0", target: archer), "another enemy of the same ability")
        XCTAssertNil(ledger.noteAttack(ability: "brute bottom step 0", target: guardian), "another ability")
        XCTAssertNotNil(ledger.noteAttack(ability: "brute top step 0", target: guardian), "the same enemy again")

        // A monster may attack an enemy once for each Attack on its card — and with every attack
        // where the card says "target one enemy with all attacks".
        let twoAttacks = [ActionModel(type: .attack, value: .int(0)), ActionModel(type: .attack, value: .int(1))]
        XCTAssertEqual(PlayLedger.attacksOnOneEnemy(card: twoAttacks, statTargets: 1), 2)
        let allOnOne = [ActionModel(type: .attack, value: .int(0), subActions: [ActionModel(type: .specialTarget, value: .string("enemyOneAll"))])]
        XCTAssertEqual(PlayLedger.attacksOnOneEnemy(card: allOnOne, statTargets: 2), 2)
        XCTAssertEqual(PlayLedger.attacksOnOneEnemy(card: [ActionModel(type: .attack, value: .int(0))], statTargets: 2), 1,
                       "Target 2 is two different enemies")
        XCTAssertNil(ledger.noteAttack(ability: "living-bones#1", target: brute, allowed: 2))
        XCTAssertNil(ledger.noteAttack(ability: "living-bones#1", target: brute, allowed: 2))
        XCTAssertNotNil(ledger.noteAttack(ability: "living-bones#1", target: brute, allowed: 2))
    }

    func testAFigureActingOutOfInitiativeOrderIsAProblem() {
        let ledger = PlayLedger()
        let early = PlayLedger.characterInitiative(15, longRest: false)
        XCTAssertEqual(ledger.noteAct(round: 1, piece: brute, initiative: early), [])
        XCTAssertEqual(ledger.noteAct(round: 1, piece: brute, initiative: early), [], "the same turn going on")
        XCTAssertEqual(ledger.noteAct(round: 1, piece: guardian, initiative: 15), [], "a tie: the character went first")
        XCTAssertEqual(ledger.noteAct(round: 1, piece: archer, initiative: 31), [])
        let late = ledger.noteAct(round: 1, piece: .character("gh-tinkerer"), initiative: PlayLedger.characterInitiative(20, longRest: false))
        XCTAssertEqual(late.count, 1, "initiative 20 after 31")
        // A new round starts the order afresh.
        XCTAssertEqual(ledger.noteAct(round: 2, piece: archer, initiative: 14), [])
        // A monster on the same number as a character must wait for the character.
        let tie = PlayLedger()
        XCTAssertEqual(tie.noteAct(round: 1, piece: guardian, initiative: 15), [])
        XCTAssertEqual(tie.noteAct(round: 1, piece: brute, initiative: early).count, 1, "the monster went before the character on a tie")
        // A long rest is 99: after a character on 99, before a monster on 99.
        XCTAssertLessThan(PlayLedger.characterInitiative(99, longRest: false), PlayLedger.characterInitiative(0, longRest: true))
        XCTAssertLessThan(PlayLedger.characterInitiative(0, longRest: true), 99)
    }

    func testAMonsterRevealedThisRoundActsOutsideTheOrder() {
        let ledger = PlayLedger()
        XCTAssertEqual(ledger.noteAct(round: 1, piece: brute, initiative: 60.5), [])
        XCTAssertEqual(ledger.noteAct(round: 1, piece: archer, initiative: 16, newcomer: true), [], "revealed by the Brute: at once")
        XCTAssertEqual(ledger.noteAct(round: 1, piece: guardian, initiative: 70), [], "the order goes on from the Brute's 61")
        XCTAssertEqual(ledger.noteAct(round: 1, piece: .monster(name: "living-bones", standee: 1), initiative: 45).count, 1)
    }

    func testASecondTurnInARoundIsAProblem() {
        let ledger = PlayLedger()
        XCTAssertEqual(ledger.noteAct(round: 3, piece: guardian, initiative: 30), [])
        XCTAssertEqual(ledger.noteAct(round: 3, piece: brute, initiative: 40.5), [])
        XCTAssertFalse(ledger.noteAct(round: 3, piece: guardian, initiative: 30).isEmpty, "the Guard again, after the Brute")
        // The same standee number on another monster (the first died, a new one was revealed) is another figure.
        let reused = PlayLedger()
        XCTAssertEqual(reused.noteAct(round: 3, piece: guardian, initiative: 30, identity: "first"), [])
        XCTAssertEqual(reused.noteAct(round: 3, piece: brute, initiative: 40.5), [])
        XCTAssertEqual(reused.noteAct(round: 3, piece: guardian, initiative: 30, newcomer: true, identity: "second"), [])
        // A boss that has its minions act again gives them one more turn, and only one.
        ledger.anotherTurn(for: guardian)
        XCTAssertEqual(ledger.noteAct(round: 3, piece: guardian, initiative: 30, newcomer: true), [])
        XCTAssertEqual(ledger.noteAct(round: 3, piece: brute, initiative: 40.5).count, 1, "but the Brute doesn't get one")
    }

    func testASummonActingAfterItsOwnerOrInTheRoundItArrivedIsAProblem() {
        let pet = PieceID.summon(id: "pet")
        let owner = PlayLedger.characterInitiative(40, longRest: false)
        let good = PlayLedger()
        XCTAssertEqual(good.noteAct(round: 1, piece: pet, initiative: PlayLedger.summonInitiative(ownerInitiative: owner), owner: brute), [])
        XCTAssertEqual(good.noteAct(round: 1, piece: brute, initiative: owner), [])

        let bad = PlayLedger()
        XCTAssertEqual(bad.noteAct(round: 1, piece: brute, initiative: owner), [])
        XCTAssertFalse(bad.noteAct(round: 1, piece: pet, initiative: PlayLedger.summonInitiative(ownerInitiative: owner), owner: brute).isEmpty,
                       "after its owner")
        XCTAssertFalse(PlayLedger().noteAct(round: 1, piece: pet, initiative: 10, owner: brute, summonedThisRound: true).isEmpty,
                       "in the round it was summoned")
    }

    func testARestWithoutTwoDiscardsIsAProblem() {
        XCTAssertNil(PlayLedger.restProblem("brute", rest: "short", discards: 2))
        XCTAssertNil(PlayLedger.restProblem("brute", rest: "long", discards: 5))
        XCTAssertNotNil(PlayLedger.restProblem("brute", rest: "short", discards: 1))
        XCTAssertNotNil(PlayLedger.restProblem("brute", rest: "long", discards: 0))
    }

    func testCardsMadeLostOrHeldByTheExhaustedAreAProblem() {
        XCTAssertNil(PlayLedger.cardProblem("brute", exhausted: false, hand: 4, discard: 3, lost: 2, active: 1, handSize: 10))
        XCTAssertNotNil(PlayLedger.cardProblem("brute", exhausted: false, hand: 4, discard: 3, lost: 2, active: 2, handSize: 10), "eleven cards")
        XCTAssertNotNil(PlayLedger.cardProblem("brute", exhausted: false, hand: 4, discard: 3, lost: 2, active: 0, handSize: 10), "nine")
        XCTAssertNil(PlayLedger.cardProblem("brute", exhausted: true, hand: 0, discard: 0, lost: 10, active: 0, handSize: 10))
        XCTAssertNotNil(PlayLedger.cardProblem("brute", exhausted: true, hand: 2, discard: 0, lost: 8, active: 0, handSize: 10),
                        "an exhausted character with a hand")
        XCTAssertNotNil(PlayLedger.cardProblem("brute", exhausted: true, hand: 0, discard: 0, lost: 9, active: 1, handSize: 10))
    }

    func testGoldThatDoesNotMatchTheTokensLootedIsAProblem() {
        // Level 3: 3 gold a token.
        XCTAssertNil(PlayLedger.goldProblem(gained: 6, tokensGone: 2, treasureGold: 0, rate: 3, monstersActing: false))
        XCTAssertNil(PlayLedger.goldProblem(gained: 21, tokensGone: 2, treasureGold: 15, rate: 3, monstersActing: false), "with a treasure's 15 gold")
        XCTAssertNotNil(PlayLedger.goldProblem(gained: 4, tokensGone: 2, treasureGold: 0, rate: 3, monstersActing: false), "paid at 2 a token")
        XCTAssertNotNil(PlayLedger.goldProblem(gained: 3, tokensGone: 2, treasureGold: 0, rate: 3, monstersActing: false),
                        "a token left the board unpaid on a character's own turn")
        XCTAssertNotNil(PlayLedger.goldProblem(gained: 9, tokensGone: 2, treasureGold: 0, rate: 3, monstersActing: false), "three paid for two")
        XCTAssertNotNil(PlayLedger.goldProblem(gained: 3, tokensGone: 0, treasureGold: 0, rate: 3, monstersActing: true), "gold from nowhere")
        // While monsters act, one of them may have looted a token: it is gone and no one is paid.
        XCTAssertNil(PlayLedger.goldProblem(gained: 0, tokensGone: 1, treasureGold: 0, rate: 3, monstersActing: true))
        XCTAssertNil(PlayLedger.goldProblem(gained: 3, tokensGone: 2, treasureGold: 0, rate: 3, monstersActing: true))
    }

    // MARK: - The simulator, with the game made to cheat

    /// Play Black Barrow with the veteran party, and at the first chance `cheat` breaks a rule
    /// behind the simulator's back. Returns what the simulator reported.
    private func violations(rounds: Int = 2, when ready: @escaping (ScenarioSimulator) -> Bool = { _ in true },
                            cheat: @escaping (ScenarioSimulator) -> Void) async throws -> [String] {
        let sim = try ScenarioSimulator(scenario: "1", options: .veteranParty(seed: 3), policy: VeteranPolicy())
        var cheated = false
        await sim.play(rounds: rounds) {
            guard !cheated, ready(sim) else { return }
            cheated = true
            cheat(sim)
        }
        XCTAssertTrue(cheated, "the moment to cheat came")
        return sim.violations
    }

    private func midTurn(_ sim: ScenarioSimulator) -> Bool {
        guard let turn = sim.coord.activePlayerTurn else { return false }
        if case .idle = sim.coord.interactionMode { return !turn.isWaiting && turn.phase != .turnComplete }
        return false
    }

    func testAnHonestGameHasNoViolation() async throws {
        let seen = try await violations(cheat: { _ in })
        XCTAssertEqual(seen, [])
    }

    func testTheSimulatorSeesGoldFromNowhere() async throws {
        let seen = try await violations(when: midTurn) { sim in sim.gm.game.characters[0].loot += 5 }
        XCTAssertTrue(seen.contains { $0.contains("gold gained") }, "\(seen)")
    }

    func testTheSimulatorSeesATokenPaidAtTheWrongRate() async throws {
        // Two tokens leave the board and their taker is paid 3 gold: not 2 each (level 0).
        let seen = try await violations(when: midTurn) { sim in
            let character = sim.gm.game.characters[0]
            let hex = sim.position(.character(character.id))!
            sim.coord.boardState.placeLoot(at: hex, count: 2)
            sim.coord.lootAtEndOfTurn(character.id)   // the game pays 4
            character.loot -= 1
        }
        XCTAssertTrue(seen.contains { $0.contains("gold gained") }, "\(seen)")
    }

    func testTheSimulatorSeesAnExtraCardAndAnExhaustedCharactersHand() async throws {
        let extra = try await violations(when: midTurn) { sim in sim.gm.game.characters[1].handCards.append(9999) }
        XCTAssertTrue(extra.contains { $0.contains("cards") }, "\(extra)")

        let held = try await violations(when: { $0.coord.boardPhase == .cardSelection && $0.gm.game.round == 1 }) { sim in
            let character = sim.gm.game.characters[2]
            sim.coord.sufferDamage(999, to: .character(character.id))
            character.handCards = [character.lostCards.removeLast()]
        }
        XCTAssertTrue(held.contains { $0.contains("exhausted") && $0.contains("still holds") }, "\(held)")
    }

    func testTheSimulatorSeesARestWithoutTwoDiscards() async throws {
        let seen = try await violations(when: { $0.coord.boardPhase == .cardSelection && $0.gm.game.round == 1 }) { sim in
            // A rest declared for a character with an empty discard pile.
            let character = sim.gm.game.characters[0]
            character.handCards.append(contentsOf: character.discardedCards)
            character.discardedCards = []
            character.longRest = true
        }
        XCTAssertTrue(seen.contains { $0.contains("long rest with 0 cards") }, "\(seen)")
    }

    func testTheSimulatorSeesAnAttackFromOutOfRange() async throws {
        // On a Guard's turn, the Guard "attacks" a character it is nowhere near.
        let seen = try await violations(rounds: 3, when: { sim in
            guard case .monster(let name, _)? = sim.coord.actingPiece, name == "bandit-guard",
                  let from = sim.position(sim.coord.actingPiece!) else { return false }
            return sim.gm.game.characters.contains { sim.position(.character($0.id)).map { $0.distance(to: from) > 1 } ?? false }
        }) { sim in
            let guardPiece = sim.coord.actingPiece!, from = sim.position(guardPiece)!
            let far = sim.gm.game.characters.map { PieceID.character($0.id) }
                .first { sim.position($0).map { $0.distance(to: from) > 1 } ?? false }!
            sim.coord.attackObserver?(guardPiece, far)
        }
        XCTAssertTrue(seen.contains { $0.contains("hexes away, with a reach of 1") }, "\(seen)")
    }
}
