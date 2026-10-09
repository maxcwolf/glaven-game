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
                   "saw", "three-spears"]
            .flatMap { gm.editionStore.abilities(forDeck: $0, edition: "gh") }
        for key in ChargedBonus.byCard.keys {
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
}
