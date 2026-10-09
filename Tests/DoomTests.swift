import XCTest
import SwiftData
@testable import GlavenGameLib

/// The Doomstalker's dooms: a doom card's bottom half puts the character's token on one enemy
/// and its effect lasts while the card is in play; it ends when the enemy dies or another doom
/// is played.
@MainActor
final class DoomTests: XCTestCase {

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

    private func add(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        character.health = 20
        character.maxHealth = 20
        return character
    }

    private func bandit(at hex: HexCoord, health: Int = 50) throws -> PieceID {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
        let entity = try XCTUnwrap(coord.entity(for: piece))
        entity.health = health
        entity.maxHealth = health
        return piece
    }

    private func health(_ piece: PieceID) -> Int { coord.entity(for: piece)?.health ?? 0 }

    /// An attack with a +0 drawn, so the damage is the attack value.
    private func hit(_ target: PieceID, by attacker: PieceID, value: Int = 2, range: Int = 1) async {
        await coord.performAttack(attacker: attacker, target: target,
                                  attack: AttackParameters(value: value, isRanged: range > 1, range: range),
                                  drawCard: { AttackModifier(type: .plus0) })
    }

    /// Doom `cardId` played by the Doomstalker on `target`, the card in the active area.
    private func doom(_ cardId: Int, by stalker: GameCharacter, on target: PieceID) {
        stalker.activeCards.append(cardId)
        coord.placeDoom(cardId: cardId, by: stalker, on: target)
    }

    private func card(_ id: Int) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: "angry-face", edition: "gh").first { $0.cardId == id })
    }

    // MARK: - Placing

    /// Playing a doom half asks for an enemy, puts the token on it, and the card stays in play;
    /// the half's description lines (Vital Charge's heal) don't happen as it's played.
    func testPlayingADoomPlacesItsToken() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(6, 6))
        let race = try card(379), other = try card(385)   // Vital Charge: "When this enemy dies, perform…"
        stalker.handCards = [race.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: stalker.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: other, bottom: race)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        for _ in 0..<20 where coord.activeDooms.isEmpty { await Task.yield() }
        for _ in 0..<6 where turn.phase == .executeBottomAction { turn.executeCurrentAction(); await Task.yield() }
        XCTAssertEqual(coord.dooms(on: piece).map(\.cardId), [379])
        XCTAssertEqual(stalker.health, 20, "the heal comes when the enemy dies")
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("by hand") },
                       "the card's lines are what the doom does, not steps for the players")
        XCTAssertTrue(turn.persistentCardsThisTurn.contains(379), "the doom card stays in play")
        let token = try XCTUnwrap(coord.pieceStatus(piece)?.tokens.first)
        XCTAssertEqual(token.className, "angry-face")
    }

    /// One doom at a time: playing another discards the first. Inescapable Fate allows two on
    /// one target; a third on another target discards both.
    func testAnotherDoomReplacesTheFirst() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let a = try bandit(at: HexCoord(5, 5)), b = try bandit(at: HexCoord(7, 5))
        doom(376, by: stalker, on: a)
        doom(381, by: stalker, on: b)
        XCTAssertTrue(coord.dooms(on: a).isEmpty)
        XCTAssertEqual(coord.dooms(on: b).map(\.cardId), [381])
        XCTAssertFalse(stalker.activeCards.contains(376))
        XCTAssertTrue(stalker.discardedCards.contains(376))

        stalker.activeCards.append(397)   // Inescapable Fate's top: two dooms on one target
        doom(395, by: stalker, on: b)
        XCTAssertEqual(coord.dooms(on: b).map(\.cardId), [381, 395])
        doom(389, by: stalker, on: b)
        XCTAssertEqual(coord.dooms(on: b).map(\.cardId), [395, 389], "a third on the same target: the older goes")
        doom(377, by: stalker, on: a)
        XCTAssertTrue(coord.dooms(on: b).isEmpty, "a third on another target: both go")
        XCTAssertEqual(coord.dooms(on: a).map(\.cardId), [377])
    }

    /// A doom is saved with the game, as a marker on the monster.
    func testADoomIsSavedWithTheMonster() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(5, 5))
        doom(397, by: stalker, on: piece)
        let marker = try XCTUnwrap(coord.monsterEntity(name: "bandit-guard", standee: 1)?.markers.first)
        XCTAssertEqual(Doom(marker: marker), Doom(characterID: stalker.id, cardId: 397))
        XCTAssertEqual(Doom(marker: Doom(characterID: "a:b", cardId: 5, marks: 2).marker)?.characterID, "a:b")
    }

    // MARK: - Attacks

    /// Rain of Arrows: +2 on the Doomstalker's attacks only. Multi-Pronged Assault: +1 on the
    /// allies' attacks, not the Doomstalker's.
    func testAttackBonusesGoToWhomTheCardSays() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let brute = add("brute", at: HexCoord(6, 4))
        let piece = try bandit(at: HexCoord(6, 5))
        let me = PieceID.character(stalker.id), ally = PieceID.character(brute.id)
        doom(376, by: stalker, on: piece)
        await hit(piece, by: me, range: 5)
        XCTAssertEqual(health(piece), 46, "Attack 2 + 2")
        await hit(piece, by: ally)
        XCTAssertEqual(health(piece), 44, "the Brute gets nothing")
        doom(381, by: stalker, on: piece)
        await hit(piece, by: ally)
        XCTAssertEqual(health(piece), 41, "Attack 2 + 1 for an ally")
        await hit(piece, by: me, range: 5)
        XCTAssertEqual(health(piece), 39, "nothing for the Doomstalker")
    }

    /// Expose's doom: Pierce 2 for everyone; Singular Focus: advantage; Crashing Wave: Curse;
    /// Predator and Prey: +range − distance.
    func testPierceAdvantageCurseAndRangeGap() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(5, 2))
        let me = PieceID.character(stalker.id)
        doom(391, by: stalker, on: piece)
        var attack = AttackParameters(value: 2, isRanged: true, range: 5)
        coord.applyDoomBonuses(to: &attack, attacker: me, target: piece, distance: 3)
        XCTAssertEqual(attack.pierce, 2)
        doom(395, by: stalker, on: piece)
        attack = AttackParameters(value: 2, isRanged: true, range: 5)
        coord.applyDoomBonuses(to: &attack, attacker: me, target: piece, distance: 3)
        XCTAssertTrue(attack.advantage)
        doom(402, by: stalker, on: piece)
        attack = AttackParameters(value: 2, isRanged: true, range: 5)
        coord.applyDoomBonuses(to: &attack, attacker: me, target: piece, distance: 3)
        XCTAssertEqual(attack.conditions, [.curse])
        doom(405, by: stalker, on: piece)
        attack = AttackParameters(value: 2, isRanged: true, range: 5)
        coord.applyDoomBonuses(to: &attack, attacker: me, target: piece, distance: 3)
        XCTAssertEqual(attack.value, 4, "range 5, 3 hexes away: +2")
    }

    /// "+2 Attack and XP +1 if the target is Doomed" (Swift Trickery, Press the Attack).
    func testTextBonusesAgainstDoomedEnemies() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(5, 2))
        let text = ["add +2 attack and gain xp +1 if the target is doomed."]
        let me = PieceID.character(stalker.id)
        XCTAssertEqual(coord.attackTextBonus(text, attacker: me, target: piece).attack, 0)
        doom(381, by: stalker, on: piece)
        let bonus = coord.attackTextBonus(text, attacker: me, target: piece)
        XCTAssertEqual(bonus.attack, 2)
        XCTAssertEqual(bonus.experience, 1)
    }

    /// Crippling Noose: the doomed monster's Attack, Move and Range are all 1 less.
    func testCripplingNooseWeakensTheMonster() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(6, 6))
        let entity = try XCTUnwrap(coord.monsterEntity(name: "bandit-guard", standee: 1))
        XCTAssertEqual(entity.doomPenalty, 0)
        doom(377, by: stalker, on: piece)
        XCTAssertEqual(entity.doomPenalty, 1)
        let spec = MonsterAttackSpec(value: 3, range: 3, isRanged: true, targetCount: 1, pierce: 0, push: 0, pull: 0,
                                     conditions: [], area: nil, advantage: false)
        let reduced = spec.reduced(by: entity.doomPenalty)
        XCTAssertEqual(reduced.value, 2)
        XCTAssertEqual(reduced.range, 2)
        var melee = spec
        melee.isRanged = false
        melee.range = 1
        XCTAssertEqual(melee.reduced(by: 1).range, 1, "a melee attack keeps its reach")
    }

    // MARK: - Over time

    /// Race to the Grave: 2 damage as each of the monster's turns starts. Sap Life: the
    /// Doomstalker heals 2 each time it suffers damage.
    func testDamageAtTurnStartAndSapLife() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        stalker.health = 10
        let piece = try bandit(at: HexCoord(6, 6))
        doom(380, by: stalker, on: piece)
        await coord.applyDoomTurnStart(piece)
        XCTAssertEqual(health(piece), 48)
        stalker.activeCards.append(397)   // two dooms
        doom(388, by: stalker, on: piece)
        await coord.applyDoomTurnStart(piece)
        XCTAssertEqual(health(piece), 46)
        XCTAssertEqual(stalker.health, 12, "Sap Life heals 2 as it suffers the damage")
    }

    /// Inescapable Fate: the marker advances at the start of the owner's next three turns, and
    /// the third kills the target.
    func testInescapableFateKillsOnTheThirdTurn() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(6, 6))
        doom(397, by: stalker, on: piece)
        await coord.advanceDoomCountdowns(for: stalker)
        await coord.advanceDoomCountdowns(for: stalker)
        XCTAssertEqual(coord.dooms(on: piece).first?.marks, 2)
        XCTAssertTrue(coord.isOnBoard(piece))
        await coord.advanceDoomCountdowns(for: stalker)
        XCTAssertFalse(coord.isOnBoard(piece))
        XCTAssertFalse(stalker.activeCards.contains(397), "the card is discarded")
    }

    // MARK: - Deaths

    /// Vital Charge: the Doomstalker heals 4 as the doomed enemy dies, and the card is discarded.
    /// Rain of Arrows' top (in play beside it): an Attack 2, Range 5 at another enemy, a charge used.
    func testADoomedEnemysDeath() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        stalker.health = 10
        let brute = add("brute", at: HexCoord(6, 4))
        let doomed = try bandit(at: HexCoord(6, 5), health: 2)
        let other = try bandit(at: HexCoord(4, 2))
        stalker.activeCards.append(376)   // Rain of Arrows played for its top half
        doom(379, by: stalker, on: doomed)
        await hit(doomed, by: .character(brute.id), value: 5)
        XCTAssertFalse(coord.isOnBoard(doomed))
        XCTAssertEqual(stalker.health, 14, "Vital Charge: Heal 4")
        XCTAssertFalse(stalker.activeCards.contains(379))
        XCTAssertTrue(stalker.discardedCards.contains(379))
        XCTAssertLessThan(health(other), 50, "Rain of Arrows' attack")
        XCTAssertEqual(stalker.bonusChargesUsed[376], 1)
    }

    /// Detonation: 3 damage to every enemy beside where the doomed enemy died.
    func testDetonation() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let brute = add("brute", at: HexCoord(6, 4))
        let doomed = try bandit(at: HexCoord(6, 5), health: 2)
        let beside = try bandit(at: HexCoord(7, 5))
        doom(382, by: stalker, on: doomed)
        await hit(doomed, by: .character(brute.id), value: 5)
        XCTAssertEqual(health(beside), 47)
        XCTAssertEqual(stalker.health, 20, "allies aren't hurt")
    }

    /// Rising Momentum: dying within range 2 of another enemy, the dooms move to it.
    func testRisingMomentumMovesTheDooms() async throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let brute = add("brute", at: HexCoord(6, 4))
        let doomed = try bandit(at: HexCoord(6, 5), health: 2)
        let near = try bandit(at: HexCoord(8, 5))
        doom(403, by: stalker, on: doomed)
        await hit(doomed, by: .character(brute.id), value: 5)
        XCTAssertEqual(coord.dooms(on: near).map(\.cardId), [403])
        XCTAssertTrue(stalker.activeCards.contains(403), "the card stays in play")
    }

    /// Expose's top: enemies lose Invisible while it's in play.
    func testExposeEndsInvisibility() throws {
        let stalker = add("angry-face", at: HexCoord(2, 2))
        let piece = try bandit(at: HexCoord(5, 2))
        coord.applyCondition(.invisible, to: piece)
        XCTAssertTrue(coord.isConditionActive(.invisible, on: piece))
        stalker.activeCards.append(391)
        XCTAssertFalse(coord.isConditionActive(.invisible, on: piece))
        XCTAssertTrue(coord.targetableEnemies(of: .character(stalker.id), range: 5).contains(piece))
    }

    /// The doom cards' text reads with its words: "Doom: Place your character token…", "a
    /// Doomed enemy" (the nested labels were dropped, leaving ": Place…" and "a enemy").
    func testDoomCardTextKeepsItsWords() throws {
        let store = gm.editionStore
        XCTAssertEqual(store.resolveCustomText("%data.custom.gh.angry-face.abilities.376.2%", edition: "gh"),
                       "Doom: Place your character token on any one enemy.")
        XCTAssertTrue(store.resolveCustomText("%data.custom.gh.angry-face.abilities.376.1%", edition: "gh")?
            .hasPrefix("The next four times a Doomed enemy dies") == true)
    }
}
