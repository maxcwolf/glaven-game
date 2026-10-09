import XCTest
import SwiftData
@testable import GlavenGameLib

/// Persistent bonuses with charges (GH p.24): each use marks a charge (some give experience), and
/// the card leaves the active area once all are marked.
@MainActor
final class ChargedBonusTests: XCTestCase {

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
        return character
    }

    private func bandit(at hex: HexCoord) throws -> PieceID {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
        let entity = try XCTUnwrap(coord.entity(for: piece))
        entity.health = 50
        entity.maxHealth = 50
        return piece
    }

    private func attack(_ target: GameCharacter, from piece: PieceID, value: Int = 3) async {
        await coord.performAttack(attacker: piece, target: .character(target.id), attack: AttackParameters(value: value),
                                  drawCard: { AttackModifier(type: .plus0) })
    }

    func testSlotsAndTheirExperienceComeFromTheCard() throws {
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let warding = try XCTUnwrap(deck.first { $0.cardId == 7 })
        XCTAssertEqual(ChargedBonus.slots(of: warding), [0, 1, 0, 1, 0, 1])
        let all = ["brute", "cragheart", "scoundrel", "spellweaver", "tinkerer", "lightning", "sun", "eclipse",
                   "saw", "three-spears", "mindthief", "squidface", "circles", "music-note", "two-mini", "angry-face"]
            .flatMap { gm.editionStore.abilities(forDeck: $0, edition: "gh") }
        for (key, bonus) in ChargedBonus.byCard where !bonus.isUnlimited && bonus != .negateNextDamage {
            let id = try XCTUnwrap(Int(key.dropFirst(3)))
            let card = try XCTUnwrap(all.first { $0.cardId == id }, key)
            XCTAssertFalse(ChargedBonus.slots(of: card).isEmpty, key)
        }
    }

    /// Warding Strength: Shield 1 against the next six attacks that would damage, XP on every
    /// second one, then the card is lost.
    func testWardingStrengthShieldsSixAttacksThenIsLost() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        brute.activeCards = [7]
        brute.lostWhenRemoved = [7]
        let piece = try bandit(at: HexCoord(4, 3))
        brute.health = 50
        brute.maxHealth = 50
        let xp = brute.experience
        await attack(brute, from: piece)
        XCTAssertEqual(brute.health, 48, "Attack 3, Shield 1")
        XCTAssertEqual(brute.bonusChargesUsed[7], 1)
        for _ in 0..<5 { await attack(brute, from: piece) }
        XCTAssertEqual(brute.health, 38)
        XCTAssertEqual(brute.experience, xp + 3)
        XCTAssertTrue(brute.activeCards.isEmpty)
        XCTAssertEqual(brute.lostCards, [7])
        await attack(brute, from: piece)
        XCTAssertEqual(brute.health, 35, "no shield any more")
    }

    func testJuggernautNegatesAnyDamageThreeTimes() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        brute.activeCards = [15]
        let health = brute.health
        for _ in 0..<3 { coord.sufferDamage(2, to: .character(brute.id)) }
        XCTAssertEqual(brute.health, health)
        XCTAssertFalse(brute.activeCards.contains(15))
        coord.sufferDamage(2, to: .character(brute.id))
        XCTAssertEqual(brute.health, health - 2)
    }

    func testOpposingStrikeRetaliatesAgainstMelee() async throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [116]
        let piece = try bandit(at: HexCoord(4, 3))
        await attack(cragheart, from: piece, value: 1)
        XCTAssertEqual(coord.entity(for: piece)?.health, 48)
        XCTAssertEqual(cragheart.bonusChargesUsed[116], 1)
    }

    func testSingleOutAddsTwoAgainstALoneEnemy() throws {
        let scoundrel = add("scoundrel", at: HexCoord(3, 3))
        scoundrel.activeCards = [88]
        let lone = try bandit(at: HexCoord(4, 3))
        XCTAssertEqual(coord.attackValueWithBonuses(3, attacker: .character(scoundrel.id), target: lone), 5)
        XCTAssertEqual(scoundrel.bonusChargesUsed[88], 1)
        _ = try bandit(at: HexCoord(5, 3))   // now it has an ally beside it
        XCTAssertEqual(coord.attackValueWithBonuses(3, attacker: .character(scoundrel.id), target: lone), 3)
        XCTAssertEqual(scoundrel.bonusChargesUsed[88], 1)
    }

    /// A persistent half works from the moment it's performed, before the card is put away.
    func testABonusWorksTheTurnItIsPlayed() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let deck = gm.editionStore.abilities(forDeck: "brute", edition: "gh")
        let warding = try XCTUnwrap(deck.first { $0.cardId == 7 }), trample = try XCTUnwrap(deck.first { $0.cardId == 1 })
        brute.handCards = [7, 1]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: warding)
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        XCTAssertEqual(coord.chargedBonuses(of: brute).map(\.cardId), [7])
    }

    func testChargesAreSaved() {
        let brute = add("brute", at: HexCoord(3, 3))
        brute.bonusChargesUsed = [7: 2]
        let restored = brute.toSnapshot().toRuntime(editionStore: gm.editionStore)
        XCTAssertEqual(restored.bonusChargesUsed, [7: 2])
    }

    // MARK: - Locked classes

    func testDefianceOfDeathOnlyStopsALethalBlow() throws {
        let berserker = add("lightning", at: HexCoord(3, 3))
        berserker.activeCards = [322]
        berserker.health = 5
        coord.sufferDamage(2, to: .character(berserker.id))
        XCTAssertEqual(berserker.health, 3, "not lethal: suffered")
        coord.sufferDamage(4, to: .character(berserker.id))
        XCTAssertEqual(berserker.health, 3, "lethal: negated")
        XCTAssertEqual(berserker.bonusChargesUsed[322], 1)
    }

    func testCauterizeAndMasterPhysicianImproveHeals() throws {
        let berserker = add("lightning", at: HexCoord(3, 3))
        berserker.activeCards = [325]
        berserker.health = 2
        coord.heal(.character(berserker.id), amount: 1)
        XCTAssertEqual(berserker.health, 5, "Heal 1 +2")

        let sawbones = add("saw", at: HexCoord(4, 3))
        sawbones.activeCards = [441]
        coord.applyCondition(.poison, to: .character(berserker.id))
        coord.heal(.character(berserker.id), amount: 1, source: .character(sawbones.id))
        XCTAssertFalse(berserker.entityConditions.contains { $0.name == .poison })
        XCTAssertEqual(berserker.health, 8, "poison removed first, so the heal (+2 Cauterize) lands")
    }

    func testEndOfTurnBonusesInfuseAndHeal() throws {
        let sun = add("sun", at: HexCoord(3, 3))
        let spears = add("three-spears", at: HexCoord(4, 3))
        sun.activeCards = [187]   // Beacon of Light
        spears.activeCards = [230]   // Fortified Position
        sun.health = 3
        let sunTurn = PlayerTurnController(characterID: sun.id, coordinator: coord, gameManager: gm)
        coord.applyEndOfTurnBonuses(sunTurn)
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .light }?.state, .new)
        XCTAssertEqual(sun.bonusChargesUsed[187], 1)
        let spearsTurn = PlayerTurnController(characterID: spears.id, coordinator: coord, gameManager: gm)
        coord.applyEndOfTurnBonuses(spearsTurn)
        XCTAssertEqual(sun.health, 5)
    }

    func testAngelicAscensionEmpowersTheNextAttacks() throws {
        let sun = add("sun", at: HexCoord(3, 3))
        sun.activeCards = [203]
        _ = try bandit(at: HexCoord(4, 3))
        let deck = gm.editionStore.abilities(forDeck: "sun", edition: "gh")
        let attackCard = try XCTUnwrap(deck.first { ($0.actions ?? []).first?.type == .attack && $0.cardId != 203 })
        let other = try XCTUnwrap(deck.first { $0.cardId != attackCard.cardId && $0.cardId != 203 })
        sun.handCards = [attackCard.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: sun.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: attackCard, bottom: other)
        let printed = attackCard.actions?.first?.value?.intValue ?? 0
        turn.executeCurrentAction()
        XCTAssertEqual(turn.currentAttackValue(), printed + 3)
        XCTAssertTrue(turn.pendingConditions.contains(.wound))
        XCTAssertTrue(turn.pendingAdvantage)
    }

    // MARK: - Printed per-target bonuses

    private func texts(of name: String, _ deck: String) throws -> [String] {
        let card = try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
        let attack = try XCTUnwrap(card.actions?.first { $0.type == .attack })
        return (attack.subActions ?? []).filter { $0.type == .custom }
            .compactMap { $0.value?.stringValue }
            .compactMap { gm.editionStore.resolveCustomText($0, edition: "gh")?.lowercased() }
    }

    func testBackstabRewardsAFlankedOrLoneTarget() throws {
        let scoundrel = add("scoundrel", at: HexCoord(3, 3))
        let target = try bandit(at: HexCoord(4, 3))
        let backstab = try texts(of: "Backstab", "scoundrel")
        let me = PieceID.character(scoundrel.id)
        XCTAssertEqual(coord.attackTextBonus(backstab, attacker: me, target: target).attack, 2, "alone: +2")
        _ = add("brute", at: HexCoord(5, 3))
        let flanked = coord.attackTextBonus(backstab, attacker: me, target: target)
        XCTAssertEqual(flanked.attack, 4, "beside the Brute and still without allies of its own: both lines, +2 each")
        XCTAssertEqual(flanked.experience, 2, "XP +1 each")
    }

    func testSubmissiveAfflictionCountsNegativeConditions() throws {
        let mindthief = add("mindthief", at: HexCoord(3, 3))
        let target = try bandit(at: HexCoord(4, 3))
        coord.applyCondition(.poison, to: target)
        coord.applyCondition(.wound, to: target)
        let texts = try texts(of: "Submissive Affliction", "mindthief")
        XCTAssertEqual(coord.attackTextBonus(texts, attacker: .character(mindthief.id), target: target).attack, 2)
    }

    func testNetShooterGivesExperiencePerTarget() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let target = try bandit(at: HexCoord(5, 3))
        let texts = try texts(of: "Net Shooter", "tinkerer")
        XCTAssertEqual(coord.attackTextBonus(texts, attacker: .character(tinkerer.id), target: target).experience, 1)
    }

    // MARK: - Round bonuses

    func testWallOfDoomAndEnhancementFieldAddToAttacks() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let tinkerer = add("tinkerer", at: HexCoord(4, 3))
        brute.activeCards = [13]   // Wall of Doom: +1 on every attack this round
        tinkerer.activeCards = [40]   // Enhancement Field: +1 for the Tinkerer and adjacent allies
        XCTAssertEqual(coord.roundAttackBonus(for: .character(brute.id), ranged: false), 2)
        XCTAssertEqual(coord.roundAttackBonus(for: .character(tinkerer.id), ranged: true), 1)
        coord.boardState.movePiece(.character(brute.id), to: HexCoord(8, 8))
        XCTAssertEqual(coord.roundAttackBonus(for: .character(brute.id), ranged: false), 1, "out of the field")
        XCTAssertNil(brute.bonusChargesUsed[13], "a round bonus has no charges")
    }

    func testTrickstersReversalNegatesTheNextDamageOnly() {
        let scoundrel = add("scoundrel", at: HexCoord(3, 3))
        scoundrel.activeCards = [98]
        scoundrel.roundBonusCards = [98]
        let health = scoundrel.health
        coord.sufferDamage(3, to: .character(scoundrel.id))
        XCTAssertEqual(scoundrel.health, health)
        coord.sufferDamage(3, to: .character(scoundrel.id))
        XCTAssertEqual(scoundrel.health, health - 3)
    }

    func testEyeForAnEyeGivesExperiencePerRetaliation() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        brute.activeCards = [2]
        brute.retaliate = [ActionModel(type: .retaliate, value: .int(2))]
        let piece = try bandit(at: HexCoord(4, 3))
        let xp = brute.experience
        await attack(brute, from: piece, value: 1)
        XCTAssertEqual(brute.experience, xp + 1)
    }

    func testProvokingRoarDrawsAttacksMeantForAdjacentAllies() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let tinkerer = add("tinkerer", at: HexCoord(4, 3))
        brute.activeCards = [4]
        let piece = try bandit(at: HexCoord(5, 3))
        let (bruteHealth, tinkererHealth) = (brute.health, tinkerer.health)
        await attack(tinkerer, from: piece, value: 2)
        XCTAssertEqual(tinkerer.health, tinkererHealth)
        XCTAssertEqual(brute.health, bruteHealth - 2, "the Brute takes it, though it's out of melee range")
    }

    func testCracklingAirAddsTwoByConsumingAir() throws {
        let spellweaver = add("spellweaver", at: HexCoord(3, 3))
        spellweaver.activeCards = [69]
        _ = try bandit(at: HexCoord(5, 3))
        let deck = gm.editionStore.abilities(forDeck: "spellweaver", edition: "gh")
        let orbs = try XCTUnwrap(deck.first { $0.name == "Impaling Eruption" }), other = try XCTUnwrap(deck.first { $0.name == "Frost Armor" })
        spellweaver.handCards = [orbs.cardId!, other.cardId!]
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .air }!].state = .strong
        let turn = PlayerTurnController(characterID: spellweaver.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: orbs, bottom: other)
        let printed = orbs.actions?.first?.value?.intValue ?? 0
        turn.executeCurrentAction()
        XCTAssertEqual(turn.currentAttackValue(), printed + 2)
        XCTAssertFalse(gm.game.isElementAvailable(.air))
        XCTAssertEqual(spellweaver.bonusChargesUsed[69], 1)
    }

    // MARK: - Start and end of turn

    private func startTurn(_ character: GameCharacter, deck: String) throws -> PlayerTurnController {
        let cards = gm.editionStore.abilities(forDeck: deck, edition: "gh").filter { !character.activeCards.contains($0.cardId ?? 0) }
        character.handCards = [cards[0].cardId!, cards[1].cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: cards[0], bottom: cards[1])
        return turn
    }

    /// Lumbering Bash: "At the start of your next five turns, perform Heal 2, Range 2."
    func testLumberingBashHealsAtTheStartOfTheTurn() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [143]
        let turn = try startTurn(cragheart, deck: "cragheart")
        XCTAssertEqual(turn.topActions.first?.type, .heal)
        XCTAssertEqual(PlayerTurnController.bonusCard(of: turn.topActions[0]), 143)
        turn.setBottomFirst(true)
        XCTAssertEqual(turn.bottomActions.first?.type, .heal, "it moves to whichever half goes first")
        XCTAssertNotEqual(turn.topActions.first.flatMap(PlayerTurnController.bonusCard), 143)
        turn.executeCurrentAction()
        guard case .selectingHealTarget(_, let value, _) = coord.interactionMode else { return XCTFail("a heal to aim") }
        XCTAssertEqual(value, 2)
        XCTAssertEqual(cragheart.bonusChargesUsed[143], 1)
    }

    /// Auto Turret: "At the end of your next five turns, perform Attack 2, Range 5."
    func testAutoTurretAttacksAtTheEndOfTheTurn() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        tinkerer.activeCards = [54]
        let turn = try startTurn(tinkerer, deck: "tinkerer")
        let last = try XCTUnwrap(turn.bottomActions.last)
        XCTAssertEqual(last.type, .attack)
        XCTAssertEqual(last.value?.intValue, 2)
        XCTAssertEqual(PlayerTurnController.bonusCard(of: last), 54)
    }

    /// Nature's Lift: on a ranged attack while Air is strong or waning, consume it for +2 Range.
    func testNaturesLiftConsumesAirForRange() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [129]
        _ = try bandit(at: HexCoord(6, 3))
        let deck = gm.editionStore.abilities(forDeck: "cragheart", edition: "gh")
        let boulder = try XCTUnwrap(deck.first { $0.name == "Massive Boulder" }), other = try XCTUnwrap(deck.first { $0.name == "Avalanche" })
        cragheart.handCards = [boulder.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: cragheart.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: boulder, bottom: other)
        turn.executeCurrentAction()
        XCTAssertEqual(turn.currentAttackRange(), 3, "no Air, no lift")
        XCTAssertNil(cragheart.bonusChargesUsed[129])

        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .air }!].state = .waning
        let next = PlayerTurnController(characterID: cragheart.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = next
        next.selectCards(top: boulder, bottom: other)
        next.executeCurrentAction()
        XCTAssertEqual(next.currentAttackRange(), 5)
        XCTAssertFalse(gm.game.isElementAvailable(.air))
        XCTAssertEqual(cragheart.bonusChargesUsed[129], 1)
    }

    func testUnendingChantDoublesCurses() async throws {
        let soothsinger = add("music-note", at: HexCoord(3, 3))
        soothsinger.activeCards = [358]
        let piece = try bandit(at: HexCoord(4, 3))
        let curses = gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse)
        await coord.performAttack(attacker: .character(soothsinger.id), target: piece,
                                  attack: AttackParameters(value: 1, conditions: [.curse]),
                                  drawCard: { AttackModifier(type: .plus0) })
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse), curses + 2)
        XCTAssertEqual(soothsinger.bonusChargesUsed[358], 1)
    }

    /// Stone Pummel: a melee attack with an obstacle beside the Cragheart destroys it for +3 and
    /// marks a charge; with no obstacle, nothing happens and no charge is used.
    func testStonePummelDestroysAnObstacleForThree() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [137]
        let target = try bandit(at: HexCoord(4, 3))
        XCTAssertEqual(coord.attackValueWithBonuses(3, attacker: .character(cragheart.id), target: target), 3, "no obstacle")
        XCTAssertEqual(cragheart.bonusChargesUsed[137] ?? 0, 0)
        coord.boardState.placeObstacle(at: HexCoord(2, 3))
        XCTAssertEqual(coord.attackValueWithBonuses(3, attacker: .character(cragheart.id), target: target), 6)
        XCTAssertNil(coord.boardState.cells[HexCoord(2, 3)]?.overlay, "the obstacle is destroyed")
        XCTAssertEqual(cragheart.bonusChargesUsed[137], 1)
        let far = try bandit(at: HexCoord(6, 3))
        coord.boardState.placeObstacle(at: HexCoord(2, 3))
        XCTAssertEqual(coord.attackValueWithBonuses(3, attacker: .character(cragheart.id), target: far), 3, "not a melee attack")
    }

    // MARK: - Bonuses around the character's own actions

    private func startTurn(_ character: GameCharacter, top: Int, bottom: Int) throws -> PlayerTurnController {
        let deck = gm.editionStore.abilities(forDeck: character.name, edition: "gh")
        let a = try XCTUnwrap(deck.first { $0.cardId == top }), b = try XCTUnwrap(deck.first { $0.cardId == bottom })
        character.handCards = [top, bottom]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: a, bottom: b)
        return turn
    }

    /// Vengeful Barrage: each time the Berserker suffers damage, Attack 3 back, a charge each time.
    func testVengefulBarrageAttacksBack() async throws {
        let berserker = add("lightning", at: HexCoord(3, 3))
        berserker.health = 20
        berserker.maxHealth = 20
        berserker.activeCards = [345]
        let piece = try bandit(at: HexCoord(4, 3))
        await attack(berserker, from: piece)
        XCTAssertEqual(berserker.health, 17)
        XCTAssertLessThan(coord.entity(for: piece)?.health ?? 50, 50, "the Berserker attacked back")
        XCTAssertEqual(berserker.bonusChargesUsed[345], 1)
    }

    /// A card with a bonus on each half: in play for its round half, Vengeful Barrage is +1
    /// Attack this round, not the attacks back.
    func testARoundHalfHasItsOwnBonus() throws {
        let berserker = add("lightning", at: HexCoord(3, 3))
        berserker.activeCards = [345]
        berserker.roundBonusCards = [345]
        XCTAssertEqual(coord.chargedBonuses(of: berserker).map(\.bonus), [.roundAttackBonus(1, .any)])
        berserker.roundBonusCards = []
        XCTAssertEqual(coord.chargedBonuses(of: berserker).map(\.bonus), [.attackOnDamage(3)])
    }

    /// Grim Bargain: before an attack, Curse an ally within Range 2 for two more targets (a charge
    /// only if the bargain is taken); its round half doubles the next attack.
    func testGrimBargainCursesAnAllyForTargets() async throws {
        let plague = add("squidface", at: HexCoord(3, 3))
        let ally = add("brute", at: HexCoord(4, 3))
        _ = try bandit(at: HexCoord(6, 6))
        plague.activeCards = [316]
        let turn = try startTurn(plague, top: 289, bottom: 289 == 289 ? 290 : 289)
        let curses = ally.attackModifierDeck.undrawnCount(of: .curse)
        turn.executeCurrentAction()
        for _ in 0..<20 where plague.bonusChargesUsed[316] == nil { await Task.yield() }
        XCTAssertEqual(ally.attackModifierDeck.undrawnCount(of: .curse), curses + 1, "the ally is cursed")
        XCTAssertEqual(plague.bonusChargesUsed[316], 1)
    }

    func testGrimBargainCanBeDeclined() async throws {
        let plague = add("squidface", at: HexCoord(3, 3))
        _ = add("brute", at: HexCoord(4, 3))
        _ = try bandit(at: HexCoord(6, 6))
        plague.activeCards = [316]
        coord.autoResolvePrompts = false
        let turn = try startTurn(plague, top: 289, bottom: 290)
        turn.executeCurrentAction()
        for _ in 0..<20 where coord.pendingFigureChoice == nil { await Task.yield() }
        XCTAssertEqual(coord.pendingFigureChoice?.declineTitle, "No Bargain")
        coord.resolveFigureChoice(nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(plague.bonusChargesUsed[316], "declined: no charge")
    }

    func testGrimBargainsRoundHalfDoublesTheNextAttack() throws {
        let plague = add("squidface", at: HexCoord(3, 3))
        _ = try bandit(at: HexCoord(4, 3))
        plague.activeCards = [316]
        plague.roundBonusCards = [316]
        let turn = try startTurn(plague, top: 289, bottom: 290)
        turn.executeCurrentAction()
        XCTAssertTrue(coord.turnLog.contains { $0.message.contains("attack is doubled") })
        XCTAssertFalse(plague.activeCards.contains(316), "once only")
    }

    /// Wings of the Night: a Move 2 before each attack action, a charge each time.
    func testWingsOfTheNightMovesBeforeAnAttack() throws {
        let shroud = add("eclipse", at: HexCoord(3, 3))
        _ = try bandit(at: HexCoord(6, 6))
        shroud.activeCards = [270]
        let turn = try startTurn(shroud, top: 262, bottom: 263)
        turn.executeCurrentAction()
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("moving first") }
        XCTAssertEqual(range, 2)
        XCTAssertEqual(shroud.bonusChargesUsed[270], 1)
        XCTAssertEqual(turn.currentSteps[1].type, .attack, "then the attack")
    }

    /// Black Knives: after an attack made while invisible, Attack 2, Range 3.
    func testBlackKnivesFollowAnAttackWhileInvisible() throws {
        let shroud = add("eclipse", at: HexCoord(3, 3))
        _ = try bandit(at: HexCoord(4, 3))
        shroud.activeCards = [261]
        coord.applyCondition(.invisible, to: .character(shroud.id))
        let turn = try startTurn(shroud, top: 262, bottom: 263)
        let before = turn.currentSteps.count
        turn.executeCurrentAction()
        XCTAssertEqual(turn.currentSteps.count, before + 1)
        let knives = turn.currentSteps[1]
        XCTAssertEqual(knives.type, .attack)
        XCTAssertEqual(PlayerTurnController.bonusCard(of: knives), 261)
    }

    /// Eyes of the Night: invisible enemies can be targeted. Dancing Shadows: attacks on the
    /// character this round have disadvantage (two cards drawn).
    func testEyesOfTheNightAndDancingShadows() async throws {
        let shroud = add("eclipse", at: HexCoord(3, 3))
        let piece = try bandit(at: HexCoord(4, 3))
        coord.applyCondition(.invisible, to: piece)
        XCTAssertFalse(coord.targetableEnemies(of: .character(shroud.id), range: 1).contains(piece))
        shroud.activeCards = [283]
        XCTAssertTrue(coord.targetableEnemies(of: .character(shroud.id), range: 1).contains(piece))

        shroud.activeCards = [267]
        shroud.roundBonusCards = [267]
        shroud.health = 20
        shroud.maxHealth = 20
        var draws = 0
        await coord.performAttack(attacker: piece, target: .character(shroud.id), attack: AttackParameters(value: 1),
                                  drawCard: { draws += 1; return AttackModifier(type: .plus0) })
        XCTAssertEqual(draws, 2, "disadvantage: two cards")
    }
}
