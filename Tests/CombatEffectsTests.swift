import XCTest
import SwiftData
@testable import GlavenGameLib

/// Combat rules found in the October 2026 audit: what attack modifier cards give the attacker,
/// damage from every source being negatable, and bonuses that last the round.
@MainActor
final class CombatEffectsTests: XCTestCase {

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

    @discardableResult
    private func addCharacter(_ name: String = "brute", at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    @discardableResult
    private func addMonster(_ name: String, type: MonsterType = .normal, at hex: HexCoord) -> GameMonsterEntity {
        let piece = coord.spawnMonster(name: name, type: type, at: hex, origin: .placed)!
        guard case .monster(_, let standee) = piece else { fatalError() }
        return coord.monsterEntity(name: name, standee: standee)!
    }

    private func sequence(_ cards: [AttackModifier]) -> () -> AttackModifier? {
        var queue = cards
        return { queue.isEmpty ? nil : queue.removeFirst() }
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    // MARK: - Modifier cards' effects for the attacker (p.19)

    /// The Scoundrel's "+0 rolling, Invisible" makes the Scoundrel invisible, not the target.
    func testAnInvisibleModifierGoesToTheAttacker() async {
        let scoundrel = addCharacter("scoundrel", at: HexCoord(3, 3))
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 20
        let invisible = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .condition, value: .string("invisible"))],
                                       rolling: true)
        let banditPiece = PieceID.monster(name: "bandit-guard", standee: bandit.number)
        await coord.performAttack(attacker: .character(scoundrel.id), target: banditPiece, attack: AttackParameters(value: 2),
                                  drawCard: sequence([invisible, AttackModifier(type: .plus0)]))
        XCTAssertTrue(coord.isConditionActive(.invisible, on: .character(scoundrel.id)))
        XCTAssertFalse(coord.isConditionActive(.invisible, on: banditPiece))
    }

    /// "+0 rolling, Heal 1 self", "+1 Shield 1 self", "+0 rolling Fire": the attacker heals, is
    /// shielded for the round, and infuses — even when the attack kills.
    func testHealShieldAndElementModifiersGoToTheAttacker() async {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.health = 5
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 1
        let selfTarget = [AttackModifierEffect(type: .specialTarget, value: .string("self"))]
        let heal = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .heal, value: .int(2), effects: selfTarget)],
                                  rolling: true)
        let fire = AttackModifier(type: .plus0, effects: [AttackModifierEffect(type: .element, value: .string("fire"))], rolling: true)
        let shield = AttackModifier(type: .plus1, value: 1,
                                    effects: [AttackModifierEffect(type: .shield, value: .int(1), effects: selfTarget)])
        await coord.performAttack(attacker: .character(brute.id), target: .monster(name: "bandit-guard", standee: bandit.number),
                                  attack: AttackParameters(value: 2), drawCard: sequence([heal, fire, shield]))
        XCTAssertTrue(bandit.dead || !coord.isOnBoard(.monster(name: "bandit-guard", standee: bandit.number)), "the attack kills")
        XCTAssertEqual(brute.health, 7)
        XCTAssertEqual(brute.shield?.value?.intValue, 1)
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .fire }?.state, .new)
    }

    /// "Refresh an item" refreshes the attacker's spent item.
    func testARefreshItemModifierRefreshesASpentItem() async {
        let brute = addCharacter("brute", at: HexCoord(3, 3))
        brute.items = ["gh-1"]
        brute.spentItems = ["gh-1"]
        let bandit = addMonster("bandit-guard", at: HexCoord(4, 3))
        bandit.health = 20
        let refresh = AttackModifier(type: .plus1, value: 1, effects: [AttackModifierEffect(type: .refreshItem)])
        await coord.performAttack(attacker: .character(brute.id), target: .monster(name: "bandit-guard", standee: bandit.number),
                                  attack: AttackParameters(value: 2), drawCard: sequence([refresh]))
        XCTAssertTrue(brute.spentItems.isEmpty)
    }

    // MARK: - Damage from every source can be negated (p.22)

    /// Wound's damage as the turn starts is damage like any other: the character may lose a hand
    /// card to negate it.
    func testWoundDamageCanBeNegatedByLosingACard() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        await sim.play(rounds: 1)
        let brute = try XCTUnwrap(sim.gm.game.characters.first { $0.name == "brute" })
        XCTAssertFalse(brute.longRest)
        brute.entityConditions.append(EntityCondition(name: .wound))
        var lostCard: Int?
        var healthAtPrompt = 0
        await sim.play(rounds: 2) {
            guard lostCard == nil, let pending = sim.coord.pendingDamage, pending.sourceDescription == "Wound",
                  let card = sim.coord.losableHandCards(of: brute).first else { return }
            healthAtPrompt = brute.health
            lostCard = card
            sim.coord.resolvePendingDamage(choice: .loseHandCard(cardId: card))
        }
        let card = try XCTUnwrap(lostCard, "the wound's damage offered the choice")
        XCTAssertTrue(brute.lostCards.contains(card))
        XCTAssertTrue(sim.coord.turnLog.contains { $0.message.contains("loses a card from hand to prevent 1 damage") })
        XCTAssertGreaterThan(healthAtPrompt, 0)
        XCTAssertEqual(sim.violations, [])
    }
}
