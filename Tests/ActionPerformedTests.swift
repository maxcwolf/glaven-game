import XCTest
import SwiftData
@testable import GlavenGameLib

/// What comes with performing an action, and only with performing it (GH p.16–18, 23, 28 and the
/// FAQ): its experience, an infusion printed on its own, and the lost icon all need at least one
/// of the action's abilities to have been performed; once one has been, the experience, the
/// infusions and any harm to the character's own side can't be left out.
@MainActor
final class ActionPerformedTests: XCTestCase {

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
    private func add(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        return character
    }

    @discardableResult
    private func addMonster(_ name: String = "bandit-guard", at hex: HexCoord, health: Int = 30) -> GameMonsterEntity {
        let piece = coord.spawnMonster(name: name, type: .normal, at: hex, origin: .placed)!
        guard case .monster(_, let standee) = piece else { fatalError() }
        let entity = coord.monsterEntity(name: name, standee: standee)!
        entity.maxHealth = health
        entity.health = health
        return entity
    }

    private func card(_ name: String, of deck: String) throws -> AbilityModel {
        try XCTUnwrap(gm.editionStore.abilities(forDeck: deck, edition: "gh").first { $0.name == name }, name)
    }

    private func turn(for character: GameCharacter, top: AbilityModel, bottom: AbilityModel, bottomFirst: Bool = false)
        -> PlayerTurnController {
        character.handCards = [top.cardId!, bottom.cardId!]
        let turn = PlayerTurnController(characterID: character.id, coordinator: coord, gameManager: gm)
        coord.activePlayerTurn = turn
        turn.selectCards(top: top, bottom: bottom)
        if bottomFirst { turn.setBottomFirst(true) }
        return turn
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return true
    }

    /// Answer the attack the board is waiting on by attacking the first target offered.
    private func attackFirstTarget(_ turn: PlayerTurnController, file: StaticString = #filePath, line: UInt = #line) async {
        guard case .selectingAttackTarget(_, _, let targets) = coord.interactionMode, let target = targets.sorted().first else {
            return XCTFail("the attack waits for a target", file: file, line: line)
        }
        coord.handlePieceTap(target)
        let done = await waitUntil { !turn.isWaiting }
        XCTAssertTrue(done, "the attack resolves", file: file, line: line)
    }

    private func finish(_ turn: PlayerTurnController) {
        var guardCount = 0
        while turn.phase != .turnComplete, guardCount < 40 {
            turn.skipRemainingActions()
            guardCount += 1
        }
    }

    private func state(_ element: ElementType) -> ElementState {
        gm.game.elementBoard.first { $0.type == element }!.state
    }

    // MARK: - Nothing performed, nothing gained

    /// Shield Bash's top (Attack 4, Stun; 2 XP; lost) with no enemy to attack: the action isn't
    /// performed, so there is no experience and the card is discarded, not lost.
    func testAnAttackWithNoTargetGivesNoExperienceAndKeepsTheCard() throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let bash = try card("Shield Bash", of: "brute"), other = try card("Trample", of: "brute")
        let turn = turn(for: brute, top: bash, bottom: other)
        while turn.phase == .executeTopAction { turn.executeCurrentAction() }
        XCTAssertEqual(brute.experience, 0, "no ability of the action was performed")
        finish(turn)
        XCTAssertEqual(brute.discardedCards.sorted(), [bash.cardId!, other.cardId!].sorted())
        XCTAssertTrue(brute.lostCards.isEmpty, "a lost icon costs the card only when the action is performed")
    }

    /// The same card with an enemy to hit: the experience comes without being asked for, and the
    /// card is lost.
    func testAnAttackOnATargetGivesItsExperienceAndLosesTheCard() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        addMonster(at: HexCoord(4, 3))
        let bash = try card("Shield Bash", of: "brute")
        let turn = turn(for: brute, top: bash, bottom: try card("Trample", of: "brute"))
        turn.executeCurrentAction()
        await attackFirstTarget(turn)
        XCTAssertEqual(brute.experience, 2, "the action's XP follows its attack")
        XCTAssertEqual(turn.currentActionIndex, turn.currentSteps.count, "with no step left to tap")
        finish(turn)
        XCTAssertEqual(brute.lostCards, [bash.cardId!])
    }

    /// Massive Boulder's top (Attack 3, Range 3; Earth): the infusion is printed on its own, and
    /// still needs an ability of the action to have been performed.
    func testAStandaloneInfusionNeedsAnAbilityPerformed() async throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        let boulder = try card("Massive Boulder", of: "cragheart"), other = try card("Rumbling Advance", of: "cragheart")
        let lonely = turn(for: cragheart, top: boulder, bottom: other)
        while lonely.phase == .executeTopAction { lonely.executeCurrentAction() }
        XCTAssertEqual(state(.earth), .inert, "no target: nothing was performed, so no Earth")

        addMonster(at: HexCoord(5, 3))
        let turn = turn(for: cragheart, top: boulder, bottom: other)
        turn.executeCurrentAction()
        await attackFirstTarget(turn)
        XCTAssertEqual(state(.earth), .new, "the attack was made: Earth, strong at the end of the turn")
    }

    /// A disarmed character can't make the attack, whoever is in range: Toxic Bolt's bottom
    /// (Attack 5, Range 2; 2 XP; lost) gives nothing and costs nothing.
    func testADisarmedCharacterGainsNothingFromAnAttack() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        addMonster(at: HexCoord(4, 3))
        tinkerer.entityConditions = [EntityCondition(name: .disarm, state: .normal)]
        let bolt = try card("Toxic Bolt", of: "tinkerer")
        let turn = turn(for: tinkerer, top: try card("Stun Shot", of: "tinkerer"), bottom: bolt, bottomFirst: true)
        while turn.phase == .executeBottomAction { turn.executeCurrentAction() }
        XCTAssertEqual(tinkerer.experience, 0)
        finish(turn)
        XCTAssertFalse(tinkerer.lostCards.contains(bolt.cardId!))
    }

    /// A Loot with nothing in range can't be performed (FAQ): Hook Gun's bottom (Loot 2; 1 XP;
    /// lost) gives no experience then, and the card is kept. With a coin there, both follow.
    func testALootWithNothingInRangeIsNotPerformed() throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let hook = try card("Hook Gun", of: "tinkerer"), other = try card("Stun Shot", of: "tinkerer")
        let empty = turn(for: tinkerer, top: other, bottom: hook, bottomFirst: true)
        while empty.phase == .executeBottomAction { empty.executeCurrentAction() }
        finish(empty)
        XCTAssertEqual(tinkerer.experience, 0)
        XCTAssertFalse(tinkerer.lostCards.contains(hook.cardId!))

        tinkerer.discardedCards = []
        coord.boardState.placeLoot(at: HexCoord(4, 3))
        let looting = turn(for: tinkerer, top: other, bottom: hook, bottomFirst: true)
        while looting.phase == .executeBottomAction { looting.executeCurrentAction() }
        finish(looting)
        XCTAssertEqual(tinkerer.experience, 1)
        XCTAssertTrue(tinkerer.lostCards.contains(hook.cardId!))
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(4, 3)])
    }

    /// Thief's Knack's top ("Disarm one adjacent trap", 2 XP) with no trap beside the Scoundrel.
    func testDisarmingWithNoTrapBesideGivesNoExperience() throws {
        let scoundrel = add("scoundrel", at: HexCoord(3, 3))
        let turn = turn(for: scoundrel, top: try card("Thief's Knack", of: "scoundrel"), bottom: try card("Quick Hands", of: "scoundrel"))
        while turn.phase == .executeTopAction { turn.executeCurrentAction() }
        XCTAssertEqual(scoundrel.experience, 0)
    }

    // MARK: - What is printed in a group beside an ability

    /// Flamethrower's XP 2 and Fire are printed together beside its attack; Burning Oil's Fire and
    /// XP 1 likewise. They come with the attack.
    func testGroupedExperienceAndInfusionComeWithTheAttack() async throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        addMonster(at: HexCoord(4, 3))
        let turn = turn(for: tinkerer, top: try card("Flamethrower", of: "tinkerer"), bottom: try card("Stun Shot", of: "tinkerer"))
        turn.executeCurrentAction()
        if case .selectingAttackTarget = coord.interactionMode { await attackFirstTarget(turn) }
        _ = await waitUntil { !turn.isWaiting }
        XCTAssertEqual(tinkerer.experience, 2)
        XCTAssertEqual(state(.fire), .new)
    }

    /// No card hides experience or an infusion where the turn can't see it: after a half is
    /// opened into steps, each is a step of its own, sits with a step (possibly under the text or
    /// range that qualifies it), or is the reward of an element bonus.
    func testEveryPrintedExperienceAndInfusionIsReachable() throws {
        let decks = ["brute", "tinkerer", "spellweaver", "scoundrel", "cragheart", "mindthief", "sun", "three-spears",
                     "circles", "eclipse", "squidface", "lightning", "music-note", "angry-face", "saw", "triangles", "two-mini"]
        func isEffect(_ action: ActionModel) -> Bool {
            (action.type == .element && !MonsterAbility.isConsume(action)) || PlayerTurnController.experience(in: action) != nil
        }
        /// Effects anywhere below `action`, outside element bonuses.
        func printed(_ action: ActionModel) -> Int {
            (action.subActions ?? []).reduce(0) { sum, sub in
                MonsterAbility.isConsume(sub) ? sum : sum + (isEffect(sub) ? 1 : 0) + printed(sub)
            }
        }
        var hidden: [String] = []
        for deck in decks {
            let cards = gm.editionStore.abilities(forDeck: deck, edition: "gh")
            XCTAssertFalse(cards.isEmpty, deck)
            for card in cards {
                for (half, actions) in [("top", card.actions ?? []), ("bottom", card.bottomActions ?? [])] {
                    for step in PlayerTurnController.steps(actions, labels: gm.editionStore, edition: "gh")
                    where step.type != .box && !MonsterAbility.isConsume(step) {
                        let seen = PlayerTurnController.attachedEffects(of: step).count
                        // Abilities printed inside another (a Command's attacks) carry their own.
                        let inner = (step.subActions ?? []).filter { [.attack, .move, .heal, .summon].contains($0.type) }
                            .reduce(0) { $0 + printed($1) }
                        if printed(step) - inner > seen { hidden.append("\(card.name ?? "?") (\(half)): \(step.type)") }
                    }
                }
            }
        }
        XCTAssertEqual(hidden, [], "experience or an infusion the turn never grants")
    }

    // MARK: - Once performed, nothing owed is left out

    /// "Skip Rest of Half" after the attack has been made doesn't forfeit the action's XP.
    func testSkippingTheRestOfAHalfKeepsItsExperience() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        addMonster(at: HexCoord(4, 3))
        // Overwhelming Assault: Attack 6, then 2 XP.
        let turn = turn(for: brute, top: try card("Overwhelming Assault", of: "brute"), bottom: try card("Trample", of: "brute"))
        turn.executeCurrentAction()
        await attackFirstTarget(turn)
        turn.skipRemainingActions()
        XCTAssertEqual(turn.phase, .executeBottomAction)
        XCTAssertEqual(brute.experience, 2)
    }

    /// Harm to the character that an action prints can't be skipped once the action is being
    /// performed (GH p.16): Blood Transfusion's "suffer 2 damage" follows its heal.
    func testHarmToOneselfCannotBeSkippedOncePerforming() async throws {
        let sawbones = add("saw", at: HexCoord(3, 3))
        let ally = add("brute", at: HexCoord(4, 3))
        ally.health = 2
        let transfusion = try XCTUnwrap(gm.editionStore.abilities(forDeck: "saw", edition: "gh").first { card in
            (card.actions ?? []).contains { $0.type == .sufferDamage || $0.type == .suffer }
        }, "the Sawbones card that heals for a price")
        let other = try XCTUnwrap(gm.editionStore.abilities(forDeck: "saw", edition: "gh").first { $0.cardId != transfusion.cardId })
        let turn = turn(for: sawbones, top: transfusion, bottom: other)
        let before = sawbones.health
        turn.executeCurrentAction()   // the heal: choose who
        if case .selectingHealTarget = coord.interactionMode {
            coord.handlePieceTap(.character(ally.id))
            _ = await waitUntil { !turn.isWaiting }
        }
        XCTAssertGreaterThan(ally.health, 2, "the heal was performed")
        turn.skipRemainingActions()
        _ = await waitUntil { sawbones.health < before || sawbones.handCards.count + sawbones.discardedCards.count < 2 }
        XCTAssertLessThan(sawbones.health, before, "its price is paid though the rest was skipped")
    }

    /// Skipping an attack's target choice takes the step back whole: the Earth it would have
    /// infused, and its part in performing the action (Crushing Grasp: Attack 3, Immobilize, Earth).
    func testSkippingATargetChoiceTakesTheStepBack() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        addMonster(at: HexCoord(4, 3))
        let grasp = try card("Crushing Grasp", of: "cragheart")
        let turn = turn(for: cragheart, top: grasp, bottom: try card("Rumbling Advance", of: "cragheart"))
        turn.executeCurrentAction()
        guard case .selectingAttackTarget = coord.interactionMode else { return XCTFail("the attack waits for a target") }
        XCTAssertEqual(state(.earth), .new)
        turn.skipCurrentAction()
        XCTAssertEqual(state(.earth), .inert, "no attack was made, so no Earth")
        finish(turn)
        XCTAssertTrue(cragheart.discardedCards.contains(grasp.cardId!))
    }

    // MARK: - Move 0

    /// A Move may be made for no hexes (FAQ), and counts as performing its action: Leaping
    /// Cleave's bottom (Move 3, Jump; Air) infuses Air for a Brute who stays put.
    func testAMoveMayBeMadeForNoHexes() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let turn = turn(for: brute, top: try card("Trample", of: "brute"), bottom: try card("Leaping Cleave", of: "brute"),
                        bottomFirst: true)
        turn.executeCurrentAction()
        guard case .selectingMove(_, _, let hexes, _, _) = coord.interactionMode else { return XCTFail("the move waits for a hex") }
        XCTAssertTrue(hexes.contains(HexCoord(3, 3)), "the character's own hex: Move 0")
        coord.handleHexTap(HexCoord(3, 3))
        _ = await waitUntil { !turn.isWaiting }
        XCTAssertEqual(coord.boardState.piecePositions[.character(brute.id)], HexCoord(3, 3))
        XCTAssertEqual(state(.air), .new)
    }

    // MARK: - Active bonuses belong to the half that was played

    /// Crackling Air's top is "on your next four attacks, +1 Attack"; its bottom a Move with a
    /// round's Retaliate for Fire. In play for the bottom, the card adds nothing to attacks.
    func testACardInPlayGivesOnlyTheBonusOfItsHalf() throws {
        let spellweaver = add("spellweaver", at: HexCoord(3, 3))
        spellweaver.activeCards = [69]
        XCTAssertEqual(coord.chargedBonuses(of: spellweaver).map(\.cardId), [69], "played for its top: the attack bonus")
        spellweaver.roundBonusCards = [69]
        spellweaver.bottomHalvesInPlay = [69]
        XCTAssertTrue(coord.chargedBonuses(of: spellweaver).isEmpty, "played for its bottom: no attack bonus")

        // Immortality's bottom (Move 2, Shield 2 this round) is not its top's "suffer no damage".
        let berserker = add("lightning", at: HexCoord(8, 8))
        berserker.activeCards = [346]
        berserker.roundBonusCards = [346]
        XCTAssertFalse(coord.negatesDamage(.character(berserker.id), amount: 3))
        berserker.roundBonusCards = []
        XCTAssertTrue(coord.negatesDamage(.character(berserker.id), amount: 3))
    }

    /// Every card with a bonus in the table gives it for exactly one of its halves.
    func testEveryBonusCardGivesItsBonusForOneHalfOnly() throws {
        let decks = ["brute", "tinkerer", "spellweaver", "scoundrel", "cragheart", "mindthief", "sun", "three-spears",
                     "circles", "eclipse", "squidface", "lightning", "music-note", "angry-face", "saw", "triangles", "two-mini"]
        let cards = decks.flatMap { gm.editionStore.abilities(forDeck: $0, edition: "gh") }
        var checked = 0
        for key in Set(ChargedBonus.byCard.keys).union(ChargedBonus.byRoundHalf.keys) {
            let id = try XCTUnwrap(Int(key.dropFirst("gh-".count)), key)
            let card = try XCTUnwrap(cards.first { $0.cardId == id }, key)
            let top = ChargedBonus.bonus(edition: "gh", card: card, top: true)
            let bottom = ChargedBonus.bonus(edition: "gh", card: card, top: false)
            XCTAssertTrue(top != nil || bottom != nil, "\(card.name ?? key) gives its bonus for neither half")
            if top != nil, bottom != nil {
                XCTAssertNotEqual(top, bottom, "\(card.name ?? key) gives the same bonus whichever half is played")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 40)
    }

    /// Crackling Air's bottom played with no Fire to consume: nothing lasting was gained, so the
    /// card goes to the discard pile, not the active area.
    func testARoundBonusInsideAnUnpaidElementBonusDoesNotKeepTheCardInPlay() async throws {
        let spellweaver = add("spellweaver", at: HexCoord(3, 3))
        let air = try card("Crackling Air", of: "spellweaver")
        let turn = turn(for: spellweaver, top: try card("Mana Bolt", of: "spellweaver"), bottom: air, bottomFirst: true)
        turn.executeCurrentAction()
        if case .selectingMove = coord.interactionMode {
            coord.handleHexTap(HexCoord(4, 3))
            _ = await waitUntil { !turn.isWaiting }
        }
        finish(turn)
        XCTAssertFalse(spellweaver.activeCards.contains(air.cardId!))
        XCTAssertTrue(spellweaver.discardedCards.contains(air.cardId!))
    }

    // MARK: - A summon and its card

    /// A summon's card stays in the active area only while the summon lives (GH p.26): when the
    /// Decoy dies, Harmless Contraption (a lost card) goes to the lost pile.
    func testADeadSummonsCardLeavesTheActiveArea() async throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let contraption = try card("Harmless Contraption", of: "tinkerer")
        let turn = turn(for: tinkerer, top: contraption, bottom: try card("Stun Shot", of: "tinkerer"))
        turn.executeCurrentAction()
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the Decoy waits for its hex") }
        coord.handleHexTap(HexCoord(4, 3))
        _ = await waitUntil { !turn.isWaiting }
        finish(turn)
        XCTAssertEqual(tinkerer.activeCards, [contraption.cardId!])
        let decoy = try XCTUnwrap(tinkerer.summons.first { !$0.dead })

        coord.sufferDamage(99, to: .summon(id: decoy.id))
        XCTAssertTrue(decoy.dead)
        XCTAssertTrue(tinkerer.activeCards.isEmpty, "the card left with its summon")
        XCTAssertEqual(tinkerer.lostCards, [contraption.cardId!])
    }

    // MARK: - Ending a bonus (GH p.25)

    /// A player may end an active bonus at any time: Frost Armor, played for its lost action,
    /// goes to the lost pile, and the next damage lands.
    func testAPlayerMayEndABonusAndItsCardGoesToItsPile() async throws {
        let spellweaver = add("spellweaver", at: HexCoord(3, 3))
        let armor = try card("Frost Armor", of: "spellweaver")
        let turn = turn(for: spellweaver, top: try card("Fire Orbs", of: "spellweaver"), bottom: armor)
        turn.setBottomFirst(true)
        for _ in 0..<12 where turn.phase == .executeBottomAction {
            turn.executeCurrentAction()
            _ = await waitUntil { !turn.isWaiting }
        }
        XCTAssertNotEqual(turn.phase, .executeBottomAction, "the bottom half is done")
        finish(turn)
        XCTAssertEqual(spellweaver.activeCards, [armor.cardId!], "in play")
        let listed = try XCTUnwrap(coord.activeCards(of: spellweaver).first)
        XCTAssertEqual(listed.line, "Frost Armor \u{00B7} 2 left")
        XCTAssertEqual(listed.consequence, "The card goes to the lost pile and its bonus ends.")

        XCTAssertTrue(coord.endActiveBonus(armor.cardId!, of: spellweaver))
        XCTAssertTrue(spellweaver.activeCards.isEmpty)
        XCTAssertEqual(spellweaver.lostCards, [armor.cardId!], "its action has the lost icon")
        XCTAssertTrue(coord.activeCards(of: spellweaver).isEmpty)
        let health = spellweaver.health
        coord.sufferDamage(2, to: .character(spellweaver.id))
        XCTAssertEqual(spellweaver.health, health - 2, "the bonus is over")
        XCTAssertFalse(coord.endActiveBonus(armor.cardId!, of: spellweaver), "nothing left to end")
    }

    /// A bonus without the lost icon goes back to the discard pile: Wall of Doom's bottom, "+1
    /// Attack to all your attacks this round".
    func testEndingABonusWithoutTheLostIconDiscardsIt() async throws {
        let brute = add("brute", at: HexCoord(3, 3))
        let wall = try card("Wall of Doom", of: "brute")
        let turn = turn(for: brute, top: try card("Trample", of: "brute"), bottom: wall)
        turn.setBottomFirst(true)
        for _ in 0..<12 where turn.phase == .executeBottomAction {
            turn.executeCurrentAction()
            _ = await waitUntil { !turn.isWaiting }
        }
        XCTAssertNotEqual(turn.phase, .executeBottomAction, "the bottom half is done")
        finish(turn)
        XCTAssertEqual(brute.activeCards, [wall.cardId!])
        XCTAssertEqual(coord.activeCards(of: brute).first?.line, "Wall of Doom \u{00B7} this round")
        XCTAssertEqual(coord.roundAttackBonus(for: .character(brute.id), ranged: false), 1)

        XCTAssertTrue(coord.endActiveBonus(wall.cardId!, of: brute))
        XCTAssertEqual(coord.roundAttackBonus(for: .character(brute.id), ranged: false), 0)
        XCTAssertTrue(brute.discardedCards.contains(wall.cardId!), "no lost icon: discarded")
        XCTAssertTrue(brute.lostCards.isEmpty && brute.roundBonusCards.isEmpty)
    }

    /// A summon's card leaving play takes the summon off the board (GH p.26).
    func testEndingASummonsCardRemovesTheSummon() async throws {
        let tinkerer = add("tinkerer", at: HexCoord(3, 3))
        let contraption = try card("Harmless Contraption", of: "tinkerer")
        let turn = turn(for: tinkerer, top: contraption, bottom: try card("Stun Shot", of: "tinkerer"))
        turn.executeCurrentAction()
        guard case .placingSummon = coord.interactionMode else { return XCTFail("the Decoy waits for its hex") }
        coord.handleHexTap(HexCoord(4, 3))
        _ = await waitUntil { !turn.isWaiting }
        finish(turn)
        let decoy = try XCTUnwrap(tinkerer.summons.first { !$0.dead })
        let listed = try XCTUnwrap(coord.activeCards(of: tinkerer).first)
        XCTAssertEqual(listed.summons.count, 1)
        XCTAssertTrue(listed.consequence.hasSuffix("leaves the board."), listed.consequence)
        XCTAssertEqual(PlayerTextTests.lint(listed.consequence), [])

        XCTAssertTrue(coord.endActiveBonus(contraption.cardId!, of: tinkerer))
        XCTAssertTrue(decoy.dead)
        XCTAssertFalse(coord.isOnBoard(.summon(id: decoy.id)), "the summon left with its card")
        XCTAssertTrue(tinkerer.activeCards.isEmpty)
        XCTAssertEqual(tinkerer.lostCards, [contraption.cardId!])
    }

    /// A turn step placed for a bonus (Lumbering Bash's heal as the turn starts) gives nothing
    /// once the player has ended that bonus.
    func testABonusEndedMidTurnNoLongerActs() throws {
        let cragheart = add("cragheart", at: HexCoord(3, 3))
        cragheart.activeCards = [143]   // Lumbering Bash: Heal 2, Range 2 at the start of the turn
        cragheart.health = 4
        let turn = turn(for: cragheart, top: try card("Massive Boulder", of: "cragheart"), bottom: try card("Rumbling Advance", of: "cragheart"))
        XCTAssertEqual(PlayerTurnController.bonusCard(of: turn.currentSteps[0]), 143, "the heal comes first")
        XCTAssertTrue(coord.endActiveBonus(143, of: cragheart))
        turn.executeCurrentAction()
        XCTAssertEqual(cragheart.health, 4, "no heal")
        XCTAssertNil(cragheart.bonusChargesUsed[143])
        guard case .idle = coord.interactionMode else { return XCTFail("nothing to choose") }
    }
}
