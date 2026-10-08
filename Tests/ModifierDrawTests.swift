import XCTest
@testable import GlavenGameLib

/// Attack modifier draws: the player draws for their own attacks with one tap; monsters and
/// summons draw for themselves unless the player asks to draw every attack. Every draw shows in
/// the tray with its cards and the attack's sum.
@MainActor
final class ModifierDrawTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(.character(gm.game.characters[0].id), at: HexCoord(3, 3))
    }

    private var brute: PieceID { .character(gm.game.characters[0].id) }

    private func addGuard(at hex: HexCoord) throws -> PieceID {
        try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        return condition()
    }

    /// A monster's attack draws without asking; the cards and sum land in the tray.
    func testMonsterAttackDrawsForItself() async throws {
        let guardPiece = try addGuard(at: HexCoord(4, 3))
        let deckBefore = gm.game.monsterAttackModifierDeck.remainingCount
        let attack = Task { @MainActor in
            await self.coord.performAttack(attacker: guardPiece, target: self.brute, attack: AttackParameters(value: 2))
        }
        // Either the attack finishes, or it stops only to ask how the Brute takes the damage.
        let settled = await waitUntil { self.coord.pendingDamage != nil || self.coord.lastModifierReveal?.sum != nil }
        XCTAssertTrue(settled)
        XCTAssertNil(coord.pendingModifierDraw, "no draw prompt for a monster's attack")
        let reveal = try XCTUnwrap(coord.lastModifierReveal)
        XCTAssertFalse(reveal.drawnByPlayer)
        XCTAssertEqual(reveal.attacker, guardPiece)
        XCTAssertEqual(reveal.defender, brute)
        XCTAssertFalse(reveal.drawn.isEmpty)
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.remainingCount, deckBefore - reveal.drawn.count)
        XCTAssertNotNil(reveal.sum, "the sum is shown once the attack has resolved")
        coord.resolvePendingDamage(choice: .takeDamage)
        _ = await attack.value
    }

    /// The player's attack waits for one tap on the deck, which draws and resolves it.
    func testPlayerAttackWaitsForOneTap() async throws {
        let guardPiece = try addGuard(at: HexCoord(4, 3))
        let attack = Task { @MainActor in
            await self.coord.performAttack(attacker: self.brute, target: guardPiece, attack: AttackParameters(value: 3))
        }
        let prompted = await waitUntil { self.coord.pendingModifierDraw != nil }
        XCTAssertTrue(prompted, "the player's own attack waits for the draw")
        XCTAssertEqual(coord.pendingModifierDraw?.attackerPiece, brute)

        coord.drawPendingModifiers()
        _ = await attack.value
        XCTAssertNil(coord.pendingModifierDraw)
        let reveal = try XCTUnwrap(coord.lastModifierReveal)
        XCTAssertTrue(reveal.drawnByPlayer)
        XCTAssertNotNil(reveal.sum)
        XCTAssertTrue(reveal.sum!.hasSuffix("damage") || reveal.sum == "miss")
    }

    /// "Draw for every attack" brings back the prompt for monsters.
    func testDrawingEveryAttackIsASetting() async throws {
        gm.settingsManager.drawAllModifiers = true
        let guardPiece = try addGuard(at: HexCoord(4, 3))
        XCTAssertTrue(coord.playerDrawsModifiers(for: guardPiece))
        let attack = Task { @MainActor in
            await self.coord.performAttack(attacker: guardPiece, target: self.brute, attack: AttackParameters(value: 2))
        }
        let prompted = await waitUntil { self.coord.pendingModifierDraw != nil }
        XCTAssertTrue(prompted)
        coord.drawPendingModifiers()
        let settled = await waitUntil { self.coord.pendingDamage != nil || self.coord.lastModifierReveal?.sum != nil }
        XCTAssertTrue(settled)
        coord.resolvePendingDamage(choice: .takeDamage)
        _ = await attack.value
    }

    /// With advantage both draws are shown, and only the kept one counts.
    func testAdvantageShowsBothDrawsAndMarksTheOneKept() {
        let deck: [AttackModifier] = [AttackModifier(type: .minus1, value: -1, valueType: .minus),
                                      AttackModifier(type: .plus2, value: 2, valueType: .plus)]
        var index = 0
        let draw = CombatResolver.drawModifiersDetailed(advantage: true, disadvantage: false) {
            defer { index += 1 }
            return index < deck.count ? deck[index] : nil
        }
        XCTAssertEqual(draw.drawn.map(\.value), [-1, 2])
        XCTAssertEqual(draw.selected.map(\.value), [2])
        let reveal = BoardCoordinator.ModifierReveal(attacker: brute, defender: brute, drawn: draw.drawn,
                                                     selected: draw.selected, advantage: true,
                                                     disadvantage: false, drawnByPlayer: true)
        XCTAssertFalse(reveal.applies(at: 0))
        XCTAssertTrue(reveal.applies(at: 1))
    }

    func testModifierEffectsAreNamed() {
        var card = AttackModifier(type: .plus1, value: 1, valueType: .plus, rolling: true)
        card.effects = [AttackModifierEffect(type: .condition, value: .string("poison")),
                        AttackModifierEffect(type: .pierce, value: .int(2))]
        XCTAssertEqual(GameText.modifierEffects(card), ["Rolling", "Poison", "Pierce 2"])
        for text in GameText.modifierEffects(card) {
            XCTAssertEqual(PlayerTextTests.lint(text), [], text)
        }
    }
}
