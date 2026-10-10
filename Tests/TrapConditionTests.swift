import XCTest
import SwiftData
@testable import GlavenGameLib

/// A trap does what the scenario book's legend says of it — not what its art suggests: a "Stun
/// Trap" deals no damage, a "Curse and Damage Trap" curses, an "Immobilize and Poison Trap"
/// doesn't hurt. Traps are sprung here the way play springs them (`moveAlong`: a character's
/// move, a monster's move, a push) on the scenarios' own boards.
@MainActor
final class TrapConditionTests: XCTestCase {

    // MARK: - Scenario boards

    /// A scenario on the board, every room revealed.
    private func scenario(_ index: String) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: index, options: .init(characters: ["brute", "spellweaver"], seed: 1,
                                                                        autoResolvePrompts: true))
        sim.gm.game.round = 1
        var progress = true
        while progress {
            progress = false
            for door in sim.coord.boardState.doors where !door.isOpen {
                sim.coord.openDoor(at: door.coord)
                if sim.coord.boardState.doors.first(where: { $0.coord == door.coord })?.isOpen == true { progress = true }
            }
        }
        return sim
    }

    /// A trap with a free hex to step from and another to go on to.
    private struct Site {
        let from: HexCoord
        let trap: HexCoord
        let beyond: HexCoord
        var path: [HexCoord] { [from, trap, beyond] }
    }

    /// The scenario's traps (those drawn with `art`), each with two free hexes beside it.
    private func sites(_ sim: ScenarioSimulator, art: String? = nil) -> [Site] {
        let coord = sim.coord
        return coord.boardState.cells.values
            .filter { $0.isTrap && (art == nil || $0.overlaySubType == art) }
            .sorted { $0.coord < $1.coord }
            .compactMap { cell in
                let free = cell.coord.neighbors.sorted().filter(coord.isEmptyHex)
                return free.count >= 2 ? Site(from: free[0], trap: cell.coord, beyond: free[1]) : nil
            }
    }

    private func site(_ sim: ScenarioSimulator, art: String? = nil) throws -> Site {
        try XCTUnwrap(sites(sim, art: art).first, "a trap with room around it in scenario \(sim.index)")
    }

    private func piece(_ sim: ScenarioSimulator, _ index: Int) -> PieceID { .character(sim.gm.game.characters[index].id) }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    /// A Bandit Guard with plenty of hit points on `hex`.
    private func bandit(_ coord: BoardCoordinator, at hex: HexCoord) throws -> (piece: PieceID, entity: GameMonsterEntity) {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
        guard case .monster(let name, let standee) = piece else { throw XCTSkip("not a monster") }
        let entity = try XCTUnwrap(coord.monsterEntity(name: name, standee: standee))
        entity.health = 20
        entity.maxHealth = 20
        return (piece, entity)
    }

    private func conditions(_ entity: any Entity) -> Set<ConditionName> {
        Set(entity.entityConditions.filter { !$0.expired }.map(\.name))
    }

    private func isTrap(_ coord: BoardCoordinator, _ hex: HexCoord) -> Bool { coord.boardState.cells[hex]?.isTrap == true }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - #1 Black Barrow: Damage Trap

    /// A plain damage trap: 2 + L damage, no condition, gone once sprung, and the move goes on.
    func testBlackBarrowsDamageTrapDealsTrapDamageAndNothingElse() async throws {
        let sim = try scenario("1")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        XCTAssertEqual(coord.boardState.cells.values.filter(\.isTrap).count, 2)
        let site = try site(sim)
        stand(sim, me, on: site.from)
        let health = brute.health
        let trapDamage = 2 + sim.gm.game.level
        XCTAssertEqual(coord.trapDescription(at: site.trap), "\(trapDamage) damage")

        let goesOn = await coord.moveAlong(me, path: site.path, style: .normal)

        XCTAssertTrue(goesOn)
        XCTAssertEqual(brute.health, health - trapDamage)
        XCTAssertEqual(conditions(brute), [])
        XCTAssertFalse(isTrap(coord, site.trap), "a sprung trap is removed")
        XCTAssertEqual(coord.boardState.piecePositions[me], site.beyond, "a damage trap doesn't end the move")
        XCTAssertTrue(coord.turnLog.contains { $0.message == "\(coord.name(me)) springs a trap and suffers \(trapDamage) damage" })
    }

    // MARK: - #2 Barrow Lair: Stun Trap

    /// A Stun trap stuns and deals no damage (it used to deal 2 + L and Immobilize, from its
    /// bear-trap art), and the character who springs it stops there.
    func testBarrowLairsStunTrapStunsWithoutDamageAndEndsTheMove() async throws {
        let sim = try scenario("2")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        XCTAssertEqual(coord.boardState.cells.values.filter(\.isTrap).count, 2)
        let site = try site(sim)
        stand(sim, me, on: site.from)
        let health = brute.health
        XCTAssertEqual(coord.trapDescription(at: site.trap), "Stun, no damage")

        let goesOn = await coord.moveAlong(me, path: site.path, style: .normal)

        XCTAssertFalse(goesOn, "stunned: nothing more this turn")
        XCTAssertEqual(brute.health, health, "a Stun trap deals no damage")
        XCTAssertEqual(conditions(brute), [.stun], "and no Immobilize")
        XCTAssertFalse(isTrap(coord, site.trap), "a sprung trap is removed")
        XCTAssertEqual(coord.boardState.piecePositions[me], site.trap, "a Stun trap ends the move on its hex")
        XCTAssertTrue(coord.turnLog.contains { $0.message == "\(coord.name(me)) springs a Stun trap" })
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("suffers") })
    }

    /// Gained on the character's own turn, the Stun lasts to the end of their next turn.
    func testAStunFromATrapLastsToTheEndOfTheNextTurn() async throws {
        let sim = try scenario("2")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        let site = try site(sim)
        stand(sim, me, on: site.from)
        _ = await coord.moveAlong(me, path: site.path, style: .normal)
        let conditionTurns = sim.gm.entityManager

        conditionTurns.expireConditions(brute)                 // the turn it was sprung on ends
        XCTAssertTrue(coord.isConditionActive(.stun, on: me), "not over with the turn it was gained on")
        conditionTurns.restoreConditions(brute)                // the next turn starts
        conditionTurns.applyConditionsTurn(brute)
        XCTAssertTrue(coord.isConditionActive(.stun, on: me), "stunned for the whole of the next turn")
        conditionTurns.expireConditions(brute)                 // and ends
        XCTAssertFalse(coord.isConditionActive(.stun, on: me))
    }

    /// The same trap under a monster walking over it.
    func testAMonsterWalkingOntoAStunTrapIsStunnedUnharmedAndStops() async throws {
        let sim = try scenario("2")
        let coord = sim.coord
        let site = try site(sim)
        let (monster, entity) = try bandit(coord, at: site.from)

        let goesOn = await coord.moveAlong(monster, path: site.path, style: .normal)

        XCTAssertFalse(goesOn)
        XCTAssertEqual(entity.health, 20)
        XCTAssertEqual(conditions(entity), [.stun])
        XCTAssertFalse(isTrap(coord, site.trap))
        XCTAssertEqual(coord.boardState.piecePositions[monster], site.trap)
    }

    /// Pushed onto it, a figure is stunned just the same — and a push isn't its own move, so
    /// it goes on past the trap.
    func testAFigurePushedOverAStunTrapIsStunnedAndThePushGoesOn() async throws {
        let sim = try scenario("2")
        let coord = sim.coord
        let traps = sites(sim)
        XCTAssertEqual(traps.count, 2, "both of the scenario's traps have room around them")

        // One step of a push, as an attack's Push 1 makes it.
        let (first, firstEntity) = try bandit(coord, at: traps[0].from)
        coord.executePushPullStep(target: first, to: traps[0].trap, attackerPos: traps[0].from, remainingSteps: 1, isPush: true)
        let pushed = await waitUntil { coord.boardState.piecePositions[first] == traps[0].trap && !self.isTrap(coord, traps[0].trap) }
        XCTAssertTrue(pushed)
        XCTAssertEqual(firstEntity.health, 20)
        XCTAssertEqual(conditions(firstEntity), [.stun])

        // Two hexes of forced movement over the other trap.
        let (second, secondEntity) = try bandit(coord, at: traps[1].from)
        let alive = await coord.moveAlong(second, path: traps[1].path, style: .forced)
        XCTAssertTrue(alive)
        XCTAssertEqual(coord.boardState.piecePositions[second], traps[1].beyond, "the Stun doesn't end a push")
        XCTAssertEqual(secondEntity.health, 20)
        XCTAssertEqual(conditions(secondEntity), [.stun])
        XCTAssertFalse(isTrap(coord, traps[1].trap))
    }

    /// On their turn, a character who walks onto a Stun trap performs no more abilities: the
    /// rest of the move and the other card's Attack are passed over, both cards are discarded.
    func testACharacterStunnedByATrapDoesNothingMoreThatTurn() async throws {
        let sim = try scenario("2")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        let site = try site(sim)
        stand(sim, me, on: site.from)
        // An enemy the Brute could attack next, were they able to.
        let (_, enemy) = try bandit(coord, at: site.beyond)
        let cards = sim.gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let top = try XCTUnwrap(cards.first { $0.name == "Spare Dagger" })     // top: Attack 3
        let bottom = try XCTUnwrap(cards.first { $0.name == "Grab and Go" })   // bottom: Move 4
        brute.handCards = [try XCTUnwrap(top.cardId), try XCTUnwrap(bottom.cardId)]
        brute.discardedCards = []
        brute.lostCards = []
        let health = brute.health
        var attacks = 0
        coord.attackObserver = { _, _ in attacks += 1 }

        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: sim.gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()   // Move 4
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("a hex to move to") }
        XCTAssertTrue(hexes.contains(site.trap))
        coord.handleHexTap(site.trap)

        let moved = await waitUntil { turn.currentActionIndex > 0 || turn.phase != .executeBottomAction }
        XCTAssertTrue(moved, "the move has been resolved")
        XCTAssertEqual(coord.boardState.piecePositions[me], site.trap)
        XCTAssertEqual(brute.health, health)
        XCTAssertEqual(conditions(brute), [.stun])
        turn.executeCurrentAction()   // what would be the Attack 3
        XCTAssertEqual(turn.phase, .turnComplete, "the turn is over: no ability is left to perform")
        turn.executeCurrentAction()
        turn.useDefaultAction()
        XCTAssertEqual(turn.phase, .turnComplete)
        if case .idle = coord.interactionMode {} else { XCTFail("nothing is offered: \(coord.interactionMode)") }
        XCTAssertEqual(attacks, 0, "the Attack 3 isn't performed")
        XCTAssertEqual(enemy.health, 20)
        XCTAssertEqual(Set(brute.discardedCards), [top.cardId!, bottom.cardId!], "both played cards are discarded")
        XCTAssertTrue(brute.handCards.isEmpty)
        XCTAssertTrue(brute.lostCards.isEmpty)
        XCTAssertTrue(coord.turnLog.contains { $0.message == "\(coord.name(me)) is stunned and can do nothing more this turn" })
    }

    /// Nor may a stunned character fall back on a card's basic Attack 2 or Move 2.
    func testAStunnedCharacterHasNoBasicActionEither() throws {
        let gm = try plainGame()
        let coord = gm.boardCoordinator
        let brute = character(gm, "brute", at: HexCoord(3, 3))
        _ = try bandit(coord, at: HexCoord(4, 3))
        let cards = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let top = try XCTUnwrap(cards.first { $0.name == "Spare Dagger" }), bottom = try XCTUnwrap(cards.first { $0.name == "Grab and Go" })
        brute.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        coord.applyCondition(.stun, to: .character(brute.id))   // as a Stun trap would, mid-turn

        turn.useDefaultAction()

        XCTAssertEqual(turn.phase, .turnComplete)
        if case .idle = coord.interactionMode {} else { XCTFail("no target is asked for: \(coord.interactionMode)") }
        XCTAssertEqual(Set(brute.discardedCards), [top.cardId!, bottom.cardId!])
    }

    // MARK: - #31 Plane of Night: Curse and Damage Trap

    /// Curse and damage: 2 + L damage and a Curse card in the deck of whoever sprang it (it
    /// used to be damage alone).
    func testPlaneOfNightsTrapsCurseAndDamage() async throws {
        let sim = try scenario("31")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        let traps = sites(sim)
        XCTAssertEqual(coord.boardState.cells.values.filter(\.isTrap).count, 6)
        XCTAssertGreaterThanOrEqual(traps.count, 2)
        let trapDamage = 2 + sim.gm.game.level
        XCTAssertEqual(coord.trapDescription(at: traps[0].trap), "\(trapDamage) damage and Curse")

        stand(sim, me, on: traps[0].from)
        let health = brute.health
        let curses = brute.attackModifierDeck.undrawnCount(of: .curse)
        let goesOn = await coord.moveAlong(me, path: traps[0].path, style: .normal)
        XCTAssertTrue(goesOn)
        XCTAssertEqual(brute.health, health - trapDamage)
        XCTAssertEqual(brute.attackModifierDeck.undrawnCount(of: .curse), curses + 1)
        XCTAssertEqual(conditions(brute), [], "a Curse is a card, not a token")
        XCTAssertFalse(isTrap(coord, traps[0].trap))
        XCTAssertEqual(coord.boardState.piecePositions[me], traps[0].beyond)

        // A monster's Curse goes into the monsters' deck.
        let (monster, entity) = try bandit(coord, at: traps[1].from)
        let monsterCurses = sim.gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse)
        _ = await coord.moveAlong(monster, path: traps[1].path, style: .normal)
        XCTAssertEqual(entity.health, 20 - trapDamage)
        XCTAssertEqual(sim.gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse), monsterCurses + 1)
        XCTAssertFalse(isTrap(coord, traps[1].trap))
    }

    // MARK: - #44 Tribal Assault: Immobilize and Poison Trap

    /// Immobilize and Poison, and no damage (it used to deal 2 + L and Immobilize only). The
    /// Immobilize ends the move; the figure isn't stunned, so its turn can go on.
    func testTribalAssaultsTrapsImmobilizeAndPoisonWithoutDamage() async throws {
        let sim = try scenario("44")
        let coord = sim.coord, brute = sim.gm.game.characters[0], me = piece(sim, 0)
        XCTAssertEqual(coord.boardState.cells.values.filter(\.isTrap).count, 4)
        let site = try site(sim)
        stand(sim, me, on: site.from)
        let health = brute.health
        XCTAssertEqual(coord.trapDescription(at: site.trap), "Immobilize and Poison, no damage")

        let goesOn = await coord.moveAlong(me, path: site.path, style: .normal)

        XCTAssertTrue(goesOn, "immobilized, not stunned: the rest of the turn is theirs")
        XCTAssertEqual(brute.health, health, "no damage")
        XCTAssertEqual(conditions(brute), [.immobilize, .poison])
        XCTAssertFalse(isTrap(coord, site.trap))
        XCTAssertEqual(coord.boardState.piecePositions[me], site.trap, "the Immobilize ends the move")
    }

    // MARK: - #15 Shrine of Strength: two kinds

    /// Two kinds on one map: the four drawn as bear traps are Poison and Damage, the four spike
    /// pits Wound and Damage.
    func testShrineOfStrengthHasBothItsKinds() async throws {
        let sim = try scenario("15")
        let coord = sim.coord
        let trapDamage = 2 + sim.gm.game.level
        let traps = coord.boardState.cells.values.filter(\.isTrap)
        XCTAssertEqual(traps.filter { $0.overlaySubType == "bear" }.count, 4)
        XCTAssertEqual(traps.filter { $0.overlaySubType == "spike" }.count, 4)

        let brute = sim.gm.game.characters[0], spellweaver = sim.gm.game.characters[1]
        let poisoned = try site(sim, art: "bear")
        stand(sim, piece(sim, 0), on: poisoned.from)
        var health = brute.health
        XCTAssertEqual(coord.trapDescription(at: poisoned.trap), "\(trapDamage) damage and Poison")
        _ = await coord.moveAlong(piece(sim, 0), path: poisoned.path, style: .normal)
        XCTAssertEqual(brute.health, health - trapDamage)
        XCTAssertEqual(conditions(brute), [.poison])
        XCTAssertEqual(coord.boardState.piecePositions[piece(sim, 0)], poisoned.beyond)

        let wounded = try site(sim, art: "spike")
        stand(sim, piece(sim, 1), on: wounded.from)
        health = spellweaver.health
        XCTAssertEqual(coord.trapDescription(at: wounded.trap), "\(trapDamage) damage and Wound")
        _ = await coord.moveAlong(piece(sim, 1), path: wounded.path, style: .normal)
        XCTAssertEqual(spellweaver.health, health - trapDamage)
        XCTAssertEqual(conditions(spellweaver), [.wound])
        XCTAssertEqual(coord.boardState.cells.values.filter(\.isTrap).count, 6, "the two sprung are gone")
    }

    // MARK: - What the player is told

    /// Asked about a trap, the game says what that trap does.
    func testATrapSaysWhatItDoes() throws {
        let stun = try scenario("2")
        let stunTrap = try site(stun).trap
        let told = stun.coord.explanation(for: .hex(stunTrap))
        XCTAssertEqual(told.title, "Trap")
        XCTAssertEqual(told.paragraphs.first,
                       "It springs on the first figure to enter it: Stun, no damage. Then it's gone. Monsters walk around traps when they can.")
        XCTAssertTrue(told.paragraphs.contains { $0.contains("can do nothing more that turn") })
        XCTAssertTrue(stun.coord.spokenHex(stunTrap, from: nil).contains("trap (Stun, no damage)"))

        let damage = try scenario("1")
        let level = damage.gm.game.level
        XCTAssertEqual(damage.coord.explanation(for: .hex(try site(damage).trap)).paragraphs,
                       ["It springs on the first figure to enter it: \(2 + level) damage. Then it's gone. Monsters walk around traps when they can."])
    }

    // MARK: - Traps from cards and monsters

    private func plainGame(cols: Int = 12, rows: Int = 12) throws -> GameManager {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        gm.boardCoordinator.boardState = makeBoard(cols: cols, rows: rows)
        gm.boardCoordinator.autoResolvePrompts = true
        gm.boardCoordinator.turnDelayNanoseconds = 0
        return gm
    }

    private func character(_ gm: GameManager, _ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        gm.boardCoordinator.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    /// The Tinkerer's own half of `name` (top or bottom) played, up to the hex to choose.
    private func place(_ name: String, top: Bool, gm: GameManager, tinkerer: GameCharacter) throws -> PlacedToken {
        let coord = gm.boardCoordinator
        let cards = gm.editionStore.abilities(forDeck: "tinkerer", edition: "gh")
        let card = try XCTUnwrap(cards.first { $0.name == name }, name)
        let other = try XCTUnwrap(cards.first { $0.name == "Proximity Mine" })
        tinkerer.handCards = [card.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: tinkerer.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        if top {
            turn.selectCards(top: card, bottom: other)
        } else {
            turn.selectCards(top: other, bottom: card)
            turn.setBottomFirst(true)
        }
        turn.executeCurrentAction()
        guard case .placingToken(_, let token, _, _) = coord.interactionMode else {
            XCTFail("\(name) asks for a hex to put its trap on")
            throw XCTSkip("no trap to place")
        }
        return token
    }

    /// Tinkerer's Tools: "Create one Stun trap" — it stuns and deals no damage.
    func testACardsStunTrapStunsWithoutDamage() async throws {
        let gm = try plainGame()
        let coord = gm.boardCoordinator
        let tinkerer = character(gm, "tinkerer", at: HexCoord(3, 3))
        let token = try place("Tinkerer's Tools", top: false, gm: gm, tinkerer: tinkerer)
        XCTAssertEqual(token, .trap(damage: 0, subType: "stun", experience: 0))
        XCTAssertEqual(token.name, "a stun trap")
        coord.handleHexTap(HexCoord(4, 3))
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.trapEffect, TrapEffect(damage: false, conditions: [.stun]))
        XCTAssertEqual(coord.trapDescription(at: HexCoord(4, 3)), "Stun, no damage")

        let (monster, entity) = try bandit(coord, at: HexCoord(5, 3))
        let goesOn = await coord.moveAlong(monster, path: [HexCoord(5, 3), HexCoord(4, 3), HexCoord(4, 4)], style: .normal)
        XCTAssertFalse(goesOn)
        XCTAssertEqual(entity.health, 20)
        XCTAssertEqual(conditions(entity), [.stun])
        XCTAssertEqual(coord.boardState.piecePositions[monster], HexCoord(4, 3))
    }

    /// Volatile Concoction: "Create one 2 damage Poison trap" — 2 damage, not 2 + L, and Poison.
    func testACardsPoisonTrapDealsItsPrintedDamageAndPoisons() async throws {
        let gm = try plainGame()
        let coord = gm.boardCoordinator
        let tinkerer = character(gm, "tinkerer", at: HexCoord(3, 3))
        let token = try place("Volatile Concoction", top: true, gm: gm, tinkerer: tinkerer)
        XCTAssertEqual(token, .trap(damage: 2, subType: "poison", experience: 0))
        XCTAssertEqual(token.name, "a 2 damage poison trap")
        coord.handleHexTap(HexCoord(4, 3))
        XCTAssertEqual(coord.trapDescription(at: HexCoord(4, 3)), "2 damage and Poison")

        let (monster, entity) = try bandit(coord, at: HexCoord(5, 3))
        _ = await coord.moveAlong(monster, path: [HexCoord(5, 3), HexCoord(4, 3), HexCoord(4, 4)], style: .normal)
        XCTAssertEqual(entity.health, 18)
        XCTAssertEqual(conditions(entity), [.poison])
        XCTAssertEqual(coord.boardState.piecePositions[monster], HexCoord(4, 4))
    }

    /// The condition a card's trap gives is the one its text names before "trap".
    func testACardsTrapTextNamesItsCondition() {
        XCTAssertNil(PlacedToken.trapCondition(in: "create one 6 damage trap in an adjacent empty hex."))
        XCTAssertEqual(PlacedToken.trapCondition(in: "Create one 4 damage %game.condition.muddle% trap in an adjacent empty hex."), "muddle")
        XCTAssertEqual(PlacedToken.trapCondition(in: "create one 2 damage immobilize trap in an adjacent empty hex."), "immobilize")
        XCTAssertEqual(PlacedToken.trap(damage: 4, subType: "muddle", experience: 0).trapEffect, TrapEffect(damage: true, conditions: [.muddle]))
        XCTAssertEqual(PlacedToken.trap(damage: 6, subType: nil, experience: 2).trapEffect, .damageOnly)
        XCTAssertNil(PlacedToken.obstacle.trapEffect)
    }

    /// A trap a monster sets ("Create a 3 damage trap…") deals the damage printed, whatever
    /// the scenario level, and gives nothing else.
    func testAMonstersTrapDealsItsPrintedDamage() async throws {
        let gm = try plainGame()
        let coord = gm.boardCoordinator
        gm.game.level = 4
        let brute = character(gm, "brute", at: HexCoord(3, 3))
        let (archer, _) = try bandit(coord, at: HexCoord(8, 8))
        coord.placeTrap(damage: 3, at: HexCoord(4, 3), by: archer)
        XCTAssertEqual(coord.boardState.cells[HexCoord(4, 3)]?.trapEffect, .damageOnly)
        let health = brute.health
        let goesOn = await coord.moveAlong(.character(brute.id), path: [HexCoord(3, 3), HexCoord(4, 3), HexCoord(5, 3)], style: .normal)
        XCTAssertTrue(goesOn)
        XCTAssertEqual(brute.health, health - 3)
        XCTAssertEqual(conditions(brute), [])
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], HexCoord(5, 3))
    }

    /// A trap nothing describes (a board built by hand, an old save) is still guessed from its
    /// art: a bear trap deals trap damage and immobilizes.
    func testATrapWithoutALegendIsGuessedFromItsArt() async throws {
        let gm = try plainGame()
        let coord = gm.boardCoordinator
        let brute = character(gm, "brute", at: HexCoord(3, 3))
        coord.boardState.cells[HexCoord(4, 3)]?.overlay = .trap
        coord.boardState.cells[HexCoord(4, 3)]?.overlaySubType = "bear"
        let health = brute.health
        _ = await coord.moveAlong(.character(brute.id), path: [HexCoord(3, 3), HexCoord(4, 3), HexCoord(5, 3)], style: .normal)
        XCTAssertEqual(brute.health, health - 3)
        XCTAssertEqual(conditions(brute), [.immobilize])
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], HexCoord(4, 3))
    }

    // MARK: - Stunned on the way: monsters and summons

    /// A corridor one hex wide along row 0, with a Stun trap on (2, 0).
    private func corridorWithAStunTrap() throws -> GameManager {
        let gm = try plainGame(cols: 7, rows: 1)
        gm.boardCoordinator.boardState.placeTrap(at: HexCoord(2, 0), damage: 0, effect: TrapEffect(damage: false, conditions: [.stun]))
        return gm
    }

    /// A monster whose only way to its focus is over a Stun trap is stunned on it and doesn't
    /// attack; it loses its next turn too, and the Stun is over as that turn ends.
    func testAMonsterStunnedOnItsWayDoesNotAttack() async throws {
        let gm = try corridorWithAStunTrap()
        let coord = gm.boardCoordinator
        let brute = character(gm, "brute", at: HexCoord(3, 0))
        let (piece, entity) = try bandit(coord, at: HexCoord(1, 0))
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "bandit-guard" })
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 525 })]   // Move +1, Attack -1
        monster.ability = 0
        monster.abilityDrawn = true
        var attacks = 0
        coord.attackObserver = { _, _ in attacks += 1 }
        let health = brute.health

        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual(coord.boardState.piecePositions[piece], HexCoord(2, 0), "it had to step on the trap, beside its focus")
        XCTAssertEqual(entity.health, 20)
        XCTAssertEqual(conditions(entity), [.stun])
        XCTAssertEqual(attacks, 0, "stunned on the way, it performs no attack")
        XCTAssertEqual(brute.health, health)

        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual(attacks, 0, "it loses its next turn")
        XCTAssertEqual(conditions(entity), [], "and the Stun ends with that turn")

        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual(attacks, 1, "then it attacks")
    }

    /// A summon the same: stunned beside its focus, it doesn't attack.
    func testASummonStunnedOnItsWayDoesNotAttack() async throws {
        let gm = try corridorWithAStunTrap()
        let coord = gm.boardCoordinator
        let brute = character(gm, "brute", at: HexCoord(0, 0))
        var data = SummonDataModel(name: "rat", health: .int(5))
        data.attack = .int(2)
        data.movement = .int(3)
        data.range = .int(0)
        gm.characterManager.addSummon(from: data, for: brute)
        let summon = try XCTUnwrap(brute.summons.first)
        summon.state = .active
        coord.boardState.placePiece(.summon(id: summon.id), at: HexCoord(1, 0))
        let (_, enemy) = try bandit(coord, at: HexCoord(3, 0))
        var attacks = 0
        coord.attackObserver = { _, _ in attacks += 1 }

        await SummonTurnController(coordinator: coord, gameManager: gm).executeSummonTurns(for: brute)

        XCTAssertEqual(coord.boardState.piecePositions[.summon(id: summon.id)], HexCoord(2, 0))
        XCTAssertEqual(summon.health, 5)
        XCTAssertEqual(conditions(summon), [.stun])
        XCTAssertEqual(attacks, 0)
        XCTAssertEqual(enemy.health, 20)
    }
}
