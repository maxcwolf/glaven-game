import XCTest
import SwiftUI
import SwiftData
@testable import GlavenGameLib

/// Items on the board (GH p.26): usable on the character's own turn when their moment comes,
/// then spent or consumed, and counted for Professional and Purist.
@MainActor
final class BoardItemTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var brute: GameCharacter { gm.game.characters[0] }

    override func setUp() async throws {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        gm.game.level = 1
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(3, 3))
        // Boots, Goggles, Piercing Bow, War Hammer, Poison Dagger, Healing and Power Potions
        brute.items = ["gh-1", "gh-6", "gh-9", "gh-10", "gh-11", "gh-12", "gh-14"]
        // The tallies live on the scenario.
        let data = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.game.scenario = Scenario(data: data)
    }

    private func card(_ name: String) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: "brute", edition: "gh").first { $0.name == name }, name)
    }

    /// Trample on top (Attack 3), its Move 4 on the bottom.
    private func startTurn() throws -> PlayerTurnController {
        let trample = try card("Trample"), other = try card("Spare Dagger")
        brute.handCards = [trample.cardId!, other.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: trample, bottom: other)
        return turn
    }

    private func usable() -> [String] { coord.usableItems().map(\.itemKey).sorted() }

    func testBootsAddTwoToTheMoveAndAreSpent() throws {
        let turn = try startTurn()
        turn.swapCards()          // Trample's bottom: Move 4
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        XCTAssertEqual(usable(), ["gh-1", "gh-12"], "during a move: the boots, and the potion any time")

        let boots = try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-1" })
        XCTAssertTrue(coord.useItem(boots))
        guard case .selectingMove(_, let range, _, _, _) = coord.interactionMode else { return XCTFail("still moving") }
        XCTAssertEqual(range, 6)
        XCTAssertTrue(brute.spentItems.contains("gh-1"))
        XCTAssertFalse(coord.useItem(boots), "a spent item can't be used again")
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: brute.name).itemUses, 1)
    }

    func testAttackItemsJoinTheAttack() async throws {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        let bandit = try XCTUnwrap(coord.entity(for: piece))
        bandit.health = 99
        bandit.maxHealth = 99
        let turn = try startTurn()
        turn.executeCurrentAction()   // Attack 3, melee
        XCTAssertEqual(usable(), ["gh-10", "gh-11", "gh-12", "gh-14", "gh-6"],
                       "no Piercing Bow on a melee attack, no boots outside a move")

        for key in ["gh-14", "gh-11", "gh-6"] {
            XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first { $0.itemKey == key })), key)
        }
        XCTAssertEqual(turn.currentAttackValue(), 4, "Minor Power Potion: +1")
        XCTAssertEqual(turn.pendingConditions, [.poison])
        XCTAssertTrue(turn.pendingAdvantage)
        XCTAssertEqual(brute.consumedItems, ["gh-14"])
        XCTAssertEqual(brute.spentItems, ["gh-11", "gh-6"])

        coord.handlePieceTap(piece)
        let deadline = Date().addingTimeInterval(3)
        while turn.currentActionIndex == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(bandit.entityConditions.contains { $0.name == .poison })
        XCTAssertEqual(coord.lastModifierReveal?.advantage, true, "Eagle-Eye Goggles: the attack draws with advantage")
    }

    func testAPotionHealsAnyTimeInTheTurnAndIsGone() throws {
        brute.health = 4
        _ = try startTurn()
        let potion = try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-12" })
        XCTAssertTrue(coord.useItem(potion))
        XCTAssertEqual(brute.health, 7)
        XCTAssertTrue(brute.consumedItems.contains("gh-12"))
        XCTAssertFalse(usable().contains("gh-12"))
    }

    func testNothingIsUsableOutsideTheCharactersTurn() {
        XCTAssertTrue(coord.usableItems().isEmpty)
    }

    /// Every item the board plays exists, and every question it asks reads cleanly.
    func testTheItemTablesMatchTheData() throws {
        let keys = Array(BoardItemEffect.byItem.keys) + DefenseItem.all.map(\.key)
            + Array(PassiveItems.defaultAttack.keys) + Array(PassiveItems.defaultMove.keys)
            + Array(PassiveItems.flying) + Array(PassiveItems.immunities.keys) + Array(PassiveItems.meleePierce.keys)
            + Array(PassiveItems.meleePush.keys)
            + [PassiveItems.unmovable, PassiveItems.muddleToStrengthen, PassiveItems.chainHood,
               PassiveItems.necklaceOfTeeth, PassiveItems.imposingBlade, DefenseItem.ironHelmet,
               PassiveItems.shoesOfHappiness, PassiveItems.enduranceFootwraps, PassiveItems.steelSabatons,
               PassiveItems.hornedHelm, PassiveItems.halberd] + Array(PassiveItems.hazardProof)
        XCTAssertEqual(Set(keys).count, keys.count, "no item in two tables")
        for key in keys {
            let id = try XCTUnwrap(Int(key.dropFirst(3)))
            XCTAssertNotNil(gm.editionStore.itemData(id: id, edition: "gh"), key)
        }
        for item in DefenseItem.all { XCTAssertEqual(PlayerTextTests.lint(item.question), [], item.question) }
        XCTAssertEqual(DefenseItem.all.first { $0.key == "gh-30" }?.question, "Give the attacker disadvantage and gain Shield 1?")
        XCTAssertEqual(DefenseItem.all.first { $0.key == "gh-46" }?.question, "Gain Shield 1 and Retaliate 2 against this attack?")
    }

    private func use(_ key: String) throws {
        XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first { $0.itemKey == key }, key)), key)
    }

    func testRocketBootsAddThreeAndJump() throws {
        brute.items = ["gh-96"]
        let turn = try startTurn()
        turn.swapCards()
        turn.setBottomFirst(true)
        turn.executeCurrentAction()
        try use("gh-96")
        guard case .selectingMove(_, let range, _, _, let mode) = coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(range, 7)
        XCTAssertEqual(mode, .jump)
    }

    func testTheStarEarringRefreshesHealsAndRecovers() throws {
        brute.items = ["gh-69", "gh-1"]
        _ = try startTurn()
        brute.spentItems = ["gh-1"]
        brute.health = 2
        brute.discardedCards = [3]
        try use("gh-69")
        XCTAssertEqual(brute.spentItems, [], "the boots are ready again")
        XCTAssertEqual(brute.consumedItems, ["gh-69"])
        XCTAssertEqual(brute.health, 5)
        XCTAssertTrue(brute.discardedCards.isEmpty)
    }

    func testAWandInfusesAndASkullCursesTheAdjacent() throws {
        brute.items = ["gh-85", "gh-119"]
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        _ = try startTurn()
        try use("gh-85")
        XCTAssertEqual(gm.game.elementBoard.first { $0.type == .fire }?.state, .new)
        let curses = gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse)
        try use("gh-119")
        XCTAssertEqual(gm.game.monsterAttackModifierDeck.undrawnCount(of: .curse), curses + 1)
        XCTAssertNotNil(coord.entity(for: piece))
    }

    func testABladeNeedsItsElementAndConsumesIt() throws {
        brute.items = ["gh-79"]   // Inferno Blade
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        let turn = try startTurn()
        turn.executeCurrentAction()   // Attack 3, melee
        XCTAssertEqual(usable(), [], "no fire to consume")
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .fire }!].state = .strong
        XCTAssertEqual(usable(), ["gh-79"])
        try use("gh-79")
        XCTAssertEqual(turn.currentAttackValue(), 5)
        XCTAssertFalse(gm.game.isElementAvailable(.fire))
        XCTAssertTrue(brute.spentItems.isEmpty, "the blade has no use limit but its element")
    }

    func testTheHawkHelmReachesFurther() throws {
        brute.items = ["gh-31"]
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(6, 3), origin: .placed)   // 3 away
        let far = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(7, 3), origin: .placed))
        let dagger = try card("Spare Dagger"), trample = try card("Trample")
        brute.handCards = [dagger.cardId!, trample.cardId!]
        let turn = PlayerTurnController(characterID: brute.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: dagger, bottom: trample)
        turn.executeCurrentAction()   // Attack 3, Range 3
        guard case .selectingAttackTarget(_, _, let before) = coord.interactionMode else { return XCTFail() }
        XCTAssertFalse(before.contains(far))
        try use("gh-31")
        guard case .selectingAttackTarget(_, let range, let after) = coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(range, 4)
        XCTAssertTrue(after.contains(far))
        XCTAssertEqual(turn.currentAttackRange(), 4)
    }

    func testTheBloodyAxeCostsHealth() throws {
        brute.items = ["gh-117"]
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        let turn = try startTurn()
        turn.executeCurrentAction()
        let health = brute.health
        try use("gh-117")
        XCTAssertEqual(brute.health, health - 2)
        XCTAssertEqual(turn.currentAttackValue(), 4)
    }

    func testTheLongSpearTurnsTheAttackIntoALine() async throws {
        brute.items = ["gh-26"]
        let near = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed)
        let turn = try startTurn()
        turn.executeCurrentAction()   // Trample: Attack 3, a single melee target
        try use("gh-26")
        XCTAssertNotNil(turn.pendingAreaPattern)
        XCTAssertEqual(usable(), [], "an area attack isn't a single target any more")
        coord.handlePieceTap(near)
        let deadline = Date().addingTimeInterval(3)
        while turn.currentActionIndex == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(coord.turnLog.contains { $0.message.contains("area attack hits 2 enemies") },
                      coord.turnLog.suffix(5).map(\.message).joined(separator: " / "))
    }

    // MARK: - Always on

    func testTheHalberdReachesTwoHexes() throws {
        brute.items = ["gh-68"]
        let far = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(5, 3), origin: .placed))
        let turn = try startTurn()
        turn.executeCurrentAction()
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode else { return XCTFail() }
        XCTAssertTrue(targets.contains(far))
        XCTAssertEqual(turn.currentAttackRange(), 1, "still a melee attack")
    }

    func testTheMaskOfTerrorPushesOnMeleeAttacks() throws {
        brute.items = ["gh-66"]
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        let turn = try startTurn()
        turn.executeCurrentAction()
        XCTAssertEqual(turn.pendingPush, 1)
    }

    func testBladesAndSandalsMakeTheBasicActionsStronger() throws {
        brute.items = ["gh-67", "gh-57", "gh-71"]
        let turn = try startTurn()
        turn.useDefaultAction()
        XCTAssertEqual(turn.currentAttackValue(), 4, "Balanced Blade: Attack 4")

        let next = try startTurn()
        next.skipRemainingActions()   // the top half
        next.useDefaultAction()
        guard case .selectingMove(_, let range, _, _, let mode) = coord.interactionMode else { return XCTFail() }
        XCTAssertEqual(range, 4, "Serene Sandals: Move 4")
        XCTAssertEqual(mode, .fly, "Boots of Levitation")
    }

    func testTheDrakescaleHelmTurnsMuddleIntoStrengthen() {
        brute.items = ["gh-108"]
        coord.applyCondition(.muddle, to: .character(brute.id))
        XCTAssertEqual(brute.entityConditions.map(\.name), [.strengthen])
    }

    func testHeavyGreavesCantBePushed() async {
        brute.items = ["gh-22"]
        await coord.performPushPull(target: .character(brute.id), attackerPos: HexCoord(2, 3), steps: 2, isPush: true)
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], HexCoord(3, 3))
        if case .selectingPushPullHex = coord.interactionMode { XCTFail("no push to choose") }
    }

    func testAKillOnYourTurnFeedsTheNecklaceAndTheBlade() throws {
        brute.items = ["gh-106", "gh-134"]
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        _ = try startTurn()
        brute.health = 5
        coord.sufferDamage(99, to: piece, killer: .character(brute.id))
        XCTAssertEqual(brute.health, 6, "Necklace of Teeth: Heal 1")
        XCTAssertEqual(brute.shield?.value?.intValue, 1, "Imposing Blade: Shield 1 this round")
    }

    func testTheChainHoodShieldsTheSurrounded() async throws {
        brute.items = ["gh-76"]
        var attacker: PieceID?
        for hex in [HexCoord(4, 3), HexCoord(2, 3), HexCoord(3, 2)] {
            attacker = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: hex, origin: .placed))
        }
        let health = brute.health
        await coord.performAttack(attacker: try XCTUnwrap(attacker), target: .character(brute.id),
                                  attack: AttackParameters(value: 3), drawCard: { AttackModifier.standard(.plus0) })
        XCTAssertEqual(brute.health, health - 2)
    }

    // MARK: - Movement

    private let sixHexesEast = (3...9).map { HexCoord($0, 3) }

    func testTheShoesAndFootwrapsRewardALongMove() async throws {
        brute.items = ["gh-72", "gh-97"]
        let turn = try startTurn()
        brute.health = 5
        let xp = brute.experience
        await coord.moveAlong(.character(brute.id), path: sixHexesEast, style: .normal)
        XCTAssertEqual(turn.hexesMoved, 6)
        coord.applyEndOfTurnItems(turn)
        XCTAssertEqual(brute.experience, xp + 1, "Shoes of Happiness")
        XCTAssertEqual(brute.health, 6, "Endurance Footwraps")
    }

    func testPushingDoesntCountAsMoving() async throws {
        let turn = try startTurn()
        await coord.moveAlong(.character(brute.id), path: [HexCoord(3, 3), HexCoord(4, 3)], style: .forced)
        XCTAssertEqual(turn.hexesMoved, 0)
    }

    func testSteelSabatonsShieldAStandStill() throws {
        brute.items = ["gh-50"]
        let turn = try startTurn()
        coord.applyEndOfTurnItems(turn)
        XCTAssertEqual(brute.shield?.value?.intValue, 1)
    }

    func testTheHornedHelmAddsOneAfterALongMove() async throws {
        brute.items = ["gh-107"]
        let turn = try startTurn()
        await coord.moveAlong(.character(brute.id), path: Array(sixHexesEast.prefix(5)), style: .normal)
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(8, 3), origin: .placed)
        turn.executeCurrentAction()   // Trample: Attack 3
        XCTAssertEqual(turn.currentAttackValue(), 4)
    }

    func testMagmaWadersWalkThroughHazardsAndHeal() async throws {
        brute.items = ["gh-99"]
        coord.boardState.placeHazard(at: HexCoord(4, 3))
        _ = try startTurn()
        brute.health = 5
        await coord.moveAlong(.character(brute.id), path: [HexCoord(3, 3), HexCoord(4, 3), HexCoord(5, 3)], style: .normal)
        XCTAssertEqual(brute.health, 7, "no hazard damage, and Heal 2")
    }

    func testProtectiveCharmMakesTheWearerImmune() {
        brute.items = ["gh-52"]
        coord.applyCondition(.poison, to: .character(brute.id))
        coord.applyCondition(.muddle, to: .character(brute.id))
        XCTAssertEqual(brute.entityConditions.map(\.name), [.muddle])
    }

    func testSilentStilettoPiercesOnMeleeAttacks() throws {
        brute.items = ["gh-137"]
        coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed)
        let turn = try startTurn()
        turn.executeCurrentAction()   // Trample: Attack 3, Pierce 2
        XCTAssertEqual(turn.pendingPierce, 3)
    }

    // MARK: - When an enemy attacks

    /// A Bandit Guard beside the Brute attacks for `value`, drawing +0s; the Brute has nothing to
    /// lose to negate it, so the only prompt is the item. `answer` is the player's reply.
    private func banditAttacks(for value: Int, answer: Bool) async throws -> (item: String?, guardPiece: PieceID) {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        brute.handCards = []
        brute.discardedCards = []
        coord.autoResolvePrompts = false
        let attack = Task { @MainActor in
            await self.coord.performAttack(attacker: piece, target: .character(self.brute.id),
                                           attack: AttackParameters(value: value),
                                           drawCard: { AttackModifier(type: .plus0) })
        }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingItemUse == nil && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        let offered = coord.pendingItemUse?.itemName
        coord.resolvePendingItemUse(answer)
        _ = await attack.value
        return (offered, piece)
    }

    func testLeatherArmorGivesTheAttackerDisadvantage() async throws {
        brute.items = ["gh-4"]
        let (offered, _) = try await banditAttacks(for: 2, answer: true)
        XCTAssertEqual(offered, "Leather Armor")
        XCTAssertEqual(coord.lastModifierReveal?.disadvantage, true)
        XCTAssertEqual(coord.lastModifierReveal?.drawn.count, 2, "two cards drawn, the worse one taken")
        XCTAssertTrue(brute.spentItems.contains("gh-4"))
        XCTAssertEqual(gm.scenarioStatsManager.stats(for: brute.name).itemUses, 1)
    }

    func testHeaterShieldBlocksOneDamage() async throws {
        brute.items = ["gh-8"]
        let health = brute.health
        let (offered, _) = try await banditAttacks(for: 3, answer: true)
        XCTAssertEqual(offered, "Heater Shield")
        XCTAssertEqual(brute.health, health - 2, "Attack 3, +0, Shield 1")
        XCTAssertTrue(brute.spentItems.contains("gh-8"))
    }

    func testHideArmorGuardsTwiceBeforeItIsSpent() async throws {
        brute.items = ["gh-3"]
        let health = brute.health
        let (offered, guardPiece) = try await banditAttacks(for: 3, answer: true)
        XCTAssertEqual(offered, "Hide Armor")
        XCTAssertEqual(brute.health, health - 2)
        XCTAssertEqual(brute.itemSlotsUsed["gh-3"], 1)
        XCTAssertFalse(brute.spentItems.contains("gh-3"), "one use left")
        let restored = brute.toSnapshot().toRuntime(editionStore: gm.editionStore)
        XCTAssertEqual(restored.itemSlotsUsed, ["gh-3": 1], "the marked use is saved")

        let second = Task { @MainActor in
            await self.coord.performAttack(attacker: guardPiece, target: .character(self.brute.id),
                                           attack: AttackParameters(value: 3), drawCard: { AttackModifier(type: .plus0) })
        }
        let deadline = Date().addingTimeInterval(3)
        while coord.pendingItemUse == nil && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        coord.resolvePendingItemUse(true)
        _ = await second.value
        XCTAssertEqual(brute.health, health - 4)
        XCTAssertTrue(brute.spentItems.contains("gh-3"))
        XCTAssertNil(brute.itemSlotsUsed["gh-3"])
    }

    func testTowerShieldGivesShieldTwo() async throws {
        brute.items = ["gh-32"]
        let health = brute.health
        let (offered, _) = try await banditAttacks(for: 3, answer: true)
        XCTAssertEqual(offered, "Tower Shield")
        XCTAssertEqual(brute.health, health - 1)
    }

    func testSpikedShieldRetaliatesOnTheAdjacentAttacker() async throws {
        brute.items = ["gh-46"]
        let (_, guardPiece) = try await banditAttacks(for: 3, answer: true)
        let bandit = try XCTUnwrap(coord.entity(for: guardPiece))
        XCTAssertEqual(bandit.health, bandit.maxHealth - 2)
    }

    func testStuddedLeatherGivesDisadvantageAndShield() async throws {
        brute.items = ["gh-30"]
        let health = brute.health
        let (offered, _) = try await banditAttacks(for: 3, answer: true)
        XCTAssertEqual(offered, "Studded Leather")
        XCTAssertEqual(coord.lastModifierReveal?.disadvantage, true)
        XCTAssertEqual(brute.health, health - 2, "+0 either way, Shield 1")
    }

    func testADeclinedItemStaysReady() async throws {
        brute.items = ["gh-8"]
        let health = brute.health
        _ = try await banditAttacks(for: 3, answer: false)
        XCTAssertEqual(brute.health, health - 3)
        XCTAssertTrue(brute.spentItems.isEmpty)
    }

    func testTheIronHelmetTurnsAnEnemysDoubleIntoPlusZero() async throws {
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        let double = { AttackModifier.standard(.double_) }
        brute.items = []
        var health = brute.health
        await coord.performAttack(attacker: piece, target: .character(brute.id), attack: AttackParameters(value: 3), drawCard: double)
        XCTAssertEqual(brute.health, health - 6, "without the helmet: Attack 3, \u{00D7}2")

        brute.items = ["gh-7"]
        health = brute.health
        await coord.performAttack(attacker: piece, target: .character(brute.id), attack: AttackParameters(value: 3), drawCard: double)
        XCTAssertEqual(brute.health, health - 3)
    }

    func testHeadlessPlayNeverSpendsDefenceItems() async throws {
        brute.items = ["gh-4", "gh-8"]
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        await coord.performAttack(attacker: piece, target: .character(brute.id), attack: AttackParameters(value: 2))
        XCTAssertNil(coord.pendingItemUse)
        XCTAssertTrue(brute.spentItems.isEmpty)
    }

    // MARK: - Minor Stamina Potion

    func testAStaminaPotionRecoversTheChosenCards() throws {
        brute.items = ["gh-13"]
        _ = try startTurn()
        brute.discardedCards = [3, 4, 5]
        let potion = try XCTUnwrap(coord.usableItems().first { $0.itemKey == "gh-13" })
        XCTAssertTrue(coord.useItem(potion))
        let pending = try XCTUnwrap(coord.pendingRecovery, "three discards: the player picks two")
        XCTAssertEqual(pending.count, 2)
        coord.resolveRecovery([5, 3, 4])
        XCTAssertEqual(brute.discardedCards, [4], "only two come back")
        XCTAssertTrue(brute.handCards.contains(5) && brute.handCards.contains(3))
        XCTAssertTrue(brute.consumedItems.contains("gh-13"))
    }

    func testWithTwoDiscardsTheyBothComeBack() throws {
        brute.items = ["gh-13"]
        _ = try startTurn()
        brute.discardedCards = [3, 4]
        XCTAssertTrue(coord.useItem(try XCTUnwrap(coord.usableItems().first)))
        XCTAssertNil(coord.pendingRecovery)
        XCTAssertTrue(brute.discardedCards.isEmpty)
    }

    // MARK: - Items with a choice

    func testAManaPotionInfusesTheChosenElements() throws {
        brute.items = ["gh-48"]   // Major Mana Potion: two
        _ = try startTurn()
        try use("gh-48")
        XCTAssertEqual(coord.pendingElementChoice?.count, 2)
        coord.resolveElementChoice([.fire, .fire, .ice, .dark])
        let infused = gm.game.elementBoard.filter { $0.state == .new }.map(\.type)
        XCTAssertEqual(Set(infused), [.fire, .ice], "two different elements, no more")
        XCTAssertNil(coord.pendingElementChoice)
    }

    func testAMinorCurePotionRemovesTheChosenCondition() throws {
        brute.items = ["gh-89"]
        _ = try startTurn()
        coord.applyCondition(.poison, to: .character(brute.id))
        coord.applyCondition(.wound, to: .character(brute.id))
        try use("gh-89")
        XCTAssertEqual(coord.pendingConditionRemoval?.options.sorted { $0.rawValue < $1.rawValue }, [.poison, .wound])
        coord.resolveConditionRemoval(.wound)
        XCTAssertEqual(brute.entityConditions.map(\.name), [.poison])
    }

    /// `ITEM_RENDER_OUT=/tmp/i.png swift test --filter testRenderElementChoice` renders the picker.
    func testRenderElementChoice() throws {
        guard let out = ProcessInfo.processInfo.environment["ITEM_RENDER_OUT"] else {
            throw XCTSkip("set ITEM_RENDER_OUT to render the element picker")
        }
        GlavenFont.registerFonts()
        let pending = BoardCoordinator.PendingElementChoice(characterID: brute.id, count: 2, itemName: "Major Mana Potion")
        let view = ElementChoicePrompt(pending: pending, coordinator: coord)
            .frame(width: 700, height: 300).background(Color.black)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: out))
    }
}
