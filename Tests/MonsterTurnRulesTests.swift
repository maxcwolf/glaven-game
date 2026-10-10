import XCTest
import SwiftData
@testable import GlavenGameLib

/// The monster rules (rulebook pp. 29–32 and the official FAQ's "Monster Turns"), played on a
/// board through the turn controller: when a card's Shield starts, what an element is consumed
/// for, whom a heal reaches, how a disarmed or muddled monster moves, and the abilities that
/// affect several figures.
@MainActor
final class MonsterTurnRulesTests: XCTestCase {

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
        // Every monster draw a +0, so an attack does what it prints.
        let zeros = (0..<30).map { _ in AttackModifier.standard(.plus0) }
        gm.game.monsterAttackModifierDeck = AttackModifierDeck(attackModifiers: zeros, cards: zeros)
        gm.game.allyAttackModifierDeck = AttackModifierDeck(attackModifiers: zeros, cards: zeros)
    }

    // MARK: - Setting up

    @discardableResult
    private func character(_ name: String, at hex: HexCoord, initiative: Int = 50) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        character.health = 30
        character.maxHealth = 30
        character.handCards = []
        character.initiative = initiative
        return character
    }

    private func piece(_ character: GameCharacter) -> PieceID { .character(character.id) }

    @discardableResult
    private func monster(_ name: String, _ type: MonsterType = .normal, at hex: HexCoord,
                         origin: BoardCoordinator.SpawnOrigin = .placed) throws -> (piece: PieceID, entity: GameMonsterEntity) {
        let piece = try XCTUnwrap(coord.spawnMonster(name: name, type: type, at: hex, origin: origin))
        guard case .monster(_, let standee) = piece else { throw XCTSkip("not a monster") }
        return (piece, try XCTUnwrap(coord.monsterEntity(name: name, standee: standee)))
    }

    private func type(_ name: String) throws -> GameMonster {
        try XCTUnwrap(gm.game.monsters.first { $0.name == name }, "no \(name) in the game")
    }

    /// Make `cardId` the card the type has drawn this round.
    @discardableResult
    private func draw(_ cardId: Int, for name: String) throws -> GameMonster {
        let monster = try type(name)
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == cardId }, "card \(cardId)")]
        monster.ability = 0
        monster.abilityDrawn = true
        monster.drawnInitiative = deck.first { $0.cardId == cardId }?.initiative
        return monster
    }

    /// The type takes its turn (all of it, or only the standees named).
    private func act(_ name: String, only: [GameMonsterEntity]? = nil) async throws {
        await MonsterTurnController(coordinator: coord, gameManager: gm)
            .executeMonsterGroup(try type(name), only: only.map { Set($0.map(\.number)) })
    }

    private func element(_ type: ElementType) -> ElementState {
        gm.game.elementBoard.first { $0.type == type }!.state
    }

    private func make(_ type: ElementType, _ state: ElementState) {
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == type }!].state = state
    }

    private func isActive(_ condition: ConditionName, on entity: any Entity) -> Bool {
        entity.entityConditions.contains { $0.name == condition && !$0.expired }
    }

    private func hex(_ piece: PieceID) throws -> HexCoord {
        try XCTUnwrap(coord.boardState.piecePositions[piece])
    }

    /// What the stat card alone gives a monster of this kind.
    private func statValue(_ kind: ActionType, _ name: String, _ type: MonsterType = .normal) throws -> Int {
        try self.type(name).stat(for: type)?.actions?.first { $0.type == kind }?.value?.intValue ?? 0
    }

    /// A character's attack with a +0 drawn.
    private func strike(_ target: PieceID, by attacker: GameCharacter, for value: Int) async {
        _ = await coord.performAttack(attacker: piece(attacker), target: target, attack: AttackParameters(value: value),
                                      drawCard: { AttackModifier(type: .plus0) })
    }

    /// The values of the attacks logged against a figure, in order.
    private func attackValues(on name: String) -> [Int] {
        coord.turnLog.compactMap { entry in
            // "… attacks Brute: 3 …" — whatever is said of the attack before the colon.
            guard let named = entry.message.range(of: " attacks \(name)"),
                  let colon = entry.message.range(of: ": ", range: named.upperBound..<entry.message.endIndex) else { return nil }
            return entry.message[colon.upperBound...].split(separator: " ").first.flatMap { Int($0) }
        }
    }

    private func endRound() {
        gm.game.state = .next
        gm.roundManager.nextGameState()
    }

    // MARK: - Shield and Retaliate on an ability card (MON-8)

    /// The FAQ's case: the Guards drew "Shield 1, Retaliate 2" (initiative 15). A character
    /// acting before them hits a guard that has neither; once it has taken its turn it has
    /// both, until the round ends.
    func testAGuardsCardShieldStartsWithItsTurnAndLastsTheRound() async throws {
        let brute = character("brute", at: HexCoord(4, 5), initiative: 4)
        let guardian = try monster("bandit-guard", at: HexCoord(5, 5))
        guardian.entity.health = 20
        guardian.entity.maxHealth = 20
        try draw(524, for: "bandit-guard")
        gm.monsterManager.applyStatEffects(for: try type("bandit-guard"))
        XCTAssertEqual(coord.shield(of: guardian.piece), 0, "the card is drawn, the guard hasn't acted")

        await strike(guardian.piece, by: brute, for: 3)
        XCTAssertEqual(guardian.entity.health, 17, "no Shield yet")
        XCTAssertEqual(brute.health, 30, "no Retaliate yet")

        try await act("bandit-guard")
        XCTAssertEqual(coord.shield(of: guardian.piece), 1)
        await strike(guardian.piece, by: brute, for: 3)
        XCTAssertEqual(guardian.entity.health, 15, "Shield 1 from its turn on")
        XCTAssertEqual(brute.health, 28, "and Retaliate 2")

        endRound()
        XCTAssertEqual(coord.shield(of: guardian.piece), 0, "until the end of the round")
        XCTAssertTrue(guardian.entity.retaliate.isEmpty)
    }

    /// Revealing the card gives nothing, through the round's own draw.
    func testDrawingTheCardGivesNoShieldBeforeTheMonsterActs() throws {
        character("brute", at: HexCoord(2, 2))
        let guardian = try monster("bandit-guard", at: HexCoord(8, 8))
        let guards = try type("bandit-guard")
        let deck = gm.monsterManager.abilities(for: guards)
        guards.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 524 })]
        guards.ability = -1
        gm.roundManager.nextGameState()
        XCTAssertEqual(gm.monsterManager.currentAbility(for: guards)?.cardId, 524)
        XCTAssertNil(guardian.entity.shield, "Shield 1 waits for the guard's turn")
        XCTAssertTrue(guardian.entity.retaliate.isEmpty, "and so does Retaliate 2")
    }

    /// A monster stunned on its turn performs nothing, so it gains no Shield from its card; the
    /// stat card's Shield is its own whatever happens, and the two add.
    func testAStunnedMonsterKeepsOnlyItsStatCardsShield() async throws {
        character("brute", at: HexCoord(1, 1))
        let stunned = try monster("living-bones", at: HexCoord(5, 5))
        let free = try monster("living-bones", at: HexCoord(8, 8))
        stunned.entity.entityConditions = [EntityCondition(name: .stun)]
        let own = try statValue(.shield, "living-bones")
        XCTAssertGreaterThan(own, 0, "Living Bones have a Shield on their stat card")
        try draw(523, for: "living-bones")   // Shield 1, Heal 2 self
        XCTAssertEqual(coord.shield(of: stunned.piece), own, "always on")

        try await act("living-bones")
        XCTAssertEqual(coord.shield(of: stunned.piece), own, "stunned: no Shield from the card")
        XCTAssertEqual(coord.shield(of: free.piece), own + 1, "the card's adds to the stat card's")
    }

    /// A monster summoned this round takes no turn, so it never has the card's Shield.
    func testAMonsterSummonedThisRoundHasNoCardShield() async throws {
        character("brute", at: HexCoord(1, 1))
        let first = try monster("bandit-guard", at: HexCoord(5, 5))
        try draw(524, for: "bandit-guard")
        let summoned = try monster("bandit-guard", at: HexCoord(8, 8), origin: .summoned)
        try await act("bandit-guard")
        XCTAssertEqual(coord.shield(of: first.piece), 1)
        XCTAssertEqual(coord.shield(of: summoned.piece), 0, "it didn't act")
        XCTAssertTrue(summoned.entity.retaliate.isEmpty)
    }

    /// Retaliate from the card adds to the stat card's, from the monster's turn on.
    func testACardsRetaliateAddsToTheStatCards() async throws {
        let brute = character("brute", at: HexCoord(4, 5), initiative: 4)
        let guardian = try monster("inox-guard", .elite, at: HexCoord(5, 5))
        guardian.entity.health = 30
        guardian.entity.maxHealth = 30
        let own = try statValue(.retaliate, "inox-guard", .elite)
        XCTAssertGreaterThan(own, 0)
        try draw(524, for: "inox-guard")
        gm.monsterManager.applyStatEffects(for: try type("inox-guard"))

        await strike(guardian.piece, by: brute, for: 2)
        XCTAssertEqual(brute.health, 30 - own, "the stat card's Retaliate alone")
        try await act("inox-guard")
        await strike(guardian.piece, by: brute, for: 2)
        XCTAssertEqual(brute.health, 30 - own - (own + 2), "the two add")
    }

    /// Where monsters act as a group with no board, the card's Shield starts as the type's turn
    /// does — not when the card is drawn — and a stunned monster has none.
    func testOffTheBoardTheCardsShieldStartsWithTheTypesTurn() throws {
        gm.monsterManager.addMonster(name: "bandit-guard", edition: "gh")
        let guards = try type("bandit-guard")
        gm.monsterManager.addEntity(type: .normal, to: guards)
        gm.monsterManager.addEntity(type: .normal, to: guards)
        guards.entities[1].entityConditions = [EntityCondition(name: .stun)]
        try draw(524, for: "bandit-guard")
        gm.monsterManager.applyStatEffects(for: guards)
        XCTAssertNil(guards.entities[0].shield)

        gm.roundManager.figuresTakeOwnTurns = false
        gm.roundManager.toggleFigure(.monster(guards))
        XCTAssertEqual(guards.entities[0].shield?.value?.intValue, 1)
        XCTAssertEqual(guards.entities[0].retaliate.count, 1)
        XCTAssertNil(guards.entities[1].shield, "stunned")
    }

    /// Savvas Icestorm (711): "Shield 1, affect self and all allies within Range 2" — the one
    /// that performs it and its allies within two hexes, of whatever type; no one further off.
    func testAnIcestormShieldsItselfAndTheAlliesWithinTwo() async throws {
        character("brute", at: HexCoord(0, 11))
        let caster = try monster("savvas-icestorm", at: HexCoord(5, 5))
        let far = try monster("savvas-icestorm", at: HexCoord(10, 5))
        let near = try monster("bandit-guard", at: HexCoord(7, 5))
        let distant = try monster("bandit-guard", at: HexCoord(8, 5))
        // Too far to move into range or attack: the Icestorm stays where it is.
        caster.entity.entityConditions = [EntityCondition(name: .immobilize)]
        try draw(711, for: "savvas-icestorm")
        try await act("savvas-icestorm", only: [caster.entity])
        XCTAssertEqual(coord.shield(of: caster.piece), 1)
        XCTAssertEqual(coord.shield(of: near.piece), 1, "an ally two hexes away")
        XCTAssertEqual(coord.shield(of: distant.piece), 0, "three hexes away")
        XCTAssertEqual(coord.shield(of: far.piece), 0, "another Icestorm, out of range, that hasn't acted")
    }

    /// The Colorless (#81), special 2: "…Heal 4 self, Shield 1". A Shield printed in a boss
    /// special is gained when the boss performs it, until the end of the round.
    func testABossSpecialsShieldIsGainedWhenItIsPerformed() async throws {
        character("brute", at: HexCoord(1, 1))
        character("tinkerer", at: HexCoord(1, 3))
        let boss = try monster("the-colorless", .boss, at: HexCoord(8, 8))
        try draw(572, for: "the-colorless")   // special 2
        XCTAssertEqual(coord.shield(of: boss.piece), 0)
        try await act("the-colorless")
        XCTAssertEqual(coord.shield(of: boss.piece), 1)
        endRound()
        XCTAssertEqual(coord.shield(of: boss.piece), 0)
    }

    // MARK: - Grouped abilities (MON-1, MON-7)

    /// Wind Demon card 648 (initiative 37) prints its attack and its Air bonus side by side in
    /// a grid: it is an attack all the same.
    func testAWindDemonAttacksWithTheCardThatPrintsItsAttackInAGrid() async throws {
        let brute = character("brute", at: HexCoord(5, 5))
        try monster("wind-demon", at: HexCoord(7, 5))
        try draw(648, for: "wind-demon")
        var attacked: [PieceID] = []
        coord.attackObserver = { _, target in attacked.append(target) }
        try await act("wind-demon")
        XCTAssertEqual(attacked, [piece(brute)], "it moves in and attacks")
        let base = try XCTUnwrap(try type("wind-demon").stat(for: .normal)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(attackValues(on: "Brute"), [base], "Attack +0")
    }

    /// The same card with Air to consume: +1 Attack and the larger area, and the Air is used.
    func testAWindDemonsGridCardTakesItsAirBonus() async throws {
        character("brute", at: HexCoord(5, 5))
        character("tinkerer", at: HexCoord(5, 6))
        try monster("wind-demon", at: HexCoord(7, 5))
        try draw(648, for: "wind-demon")
        make(.air, .strong)
        try await act("wind-demon")
        let base = try XCTUnwrap(try type("wind-demon").stat(for: .normal)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(attackValues(on: "Brute").first, base + 1, "Air: +1 Attack")
        XCTAssertNotEqual(element(.air), .strong, "consumed")
    }

    // MARK: - Elements (ELE-4)

    /// The playthrough's case: Night Demons drew "Attack −2, Range 3, Target 3; Dark: Muddle".
    /// The only one left is disarmed: it doesn't attack, so Dark isn't consumed.
    func testADisarmedMonsterConsumesNothingForItsAttack() async throws {
        let brute = character("brute", at: HexCoord(5, 5))
        let demon = try monster("night-demon", at: HexCoord(7, 5))
        demon.entity.entityConditions = [EntityCondition(name: .disarm)]
        try draw(663, for: "night-demon")
        make(.dark, .strong)
        try await act("night-demon")
        XCTAssertEqual(element(.dark), .strong, "no attack, no consumption")
        XCTAssertFalse(isActive(.muddle, on: brute))
    }

    /// The first monster that does attack consumes, once, and every monster of the type acting
    /// after it has the bonus.
    func testTheFirstMonsterToAttackConsumesForThoseAfterIt() async throws {
        let brute = character("brute", at: HexCoord(5, 5))
        let tinkerer = character("tinkerer", at: HexCoord(5, 10))
        let disarmed = try monster("night-demon", at: HexCoord(7, 5))
        try monster("night-demon", at: HexCoord(3, 5))      // in range of the Brute only
        try monster("night-demon", at: HexCoord(7, 10))     // in range of the Tinkerer only
        disarmed.entity.entityConditions = [EntityCondition(name: .disarm)]
        try draw(663, for: "night-demon")
        make(.dark, .strong)
        try await act("night-demon")
        XCTAssertNotEqual(element(.dark), .strong, "the second demon attacked: consumed")
        XCTAssertEqual(coord.turnLog.filter { $0.message.hasSuffix("consumed") }.count, 1, "once for the type")
        XCTAssertTrue(isActive(.muddle, on: brute), "the demon that consumed")
        XCTAssertTrue(isActive(.muddle, on: tinkerer), "and the one acting after it")
    }

    /// A monster that can't get to anyone makes no attack: nothing is consumed for it.
    func testAMonsterThatCannotAttackConsumesNothing() async throws {
        character("brute", at: HexCoord(0, 0))
        try monster("night-demon", at: HexCoord(11, 11))
        try draw(664, for: "night-demon")   // Move −1, Attack +1; Dark: +2 Attack
        make(.dark, .strong)
        try await act("night-demon")
        XCTAssertEqual(element(.dark), .strong)
        XCTAssertTrue(attackValues(on: "Brute").isEmpty)
    }

    /// A consume that stands on its own on the card isn't tied to an ability: the first monster
    /// to act pays for it, whatever else it does (Night Demon 661, "Dark: Invisible, self").
    func testAConsumeOnItsOwnIsPaidByTheFirstMonsterToAct() async throws {
        character("brute", at: HexCoord(0, 0))
        let first = try monster("night-demon", at: HexCoord(11, 11))
        let second = try monster("night-demon", at: HexCoord(11, 9))
        try draw(661, for: "night-demon")
        make(.dark, .strong)
        try await act("night-demon")
        XCTAssertNotEqual(element(.dark), .strong)
        XCTAssertEqual(coord.turnLog.filter { $0.message.hasSuffix("consumed") }.count, 1)
        XCTAssertTrue(isActive(.invisible, on: first.entity))
        XCTAssertTrue(isActive(.invisible, on: second.entity), "every monster of the type has the bonus")
    }

    /// Savvas Icestorm (708): "Push 2, all adjacent enemies; Air: Push 4 instead."
    func testAnIcestormPushesFurtherWithAir() async throws {
        let brute = character("brute", at: HexCoord(4, 5))
        let icestorm = try monster("savvas-icestorm", at: HexCoord(3, 5))
        try draw(708, for: "savvas-icestorm")
        try await act("savvas-icestorm")
        XCTAssertEqual(try hex(piece(brute)).distance(to: try hex(icestorm.piece)), 3, "Push 2")
        XCTAssertEqual(element(.air), .inert)
    }

    func testAnIcestormsAirPushIsFourInstead() async throws {
        let brute = character("brute", at: HexCoord(4, 5))
        let icestorm = try monster("savvas-icestorm", at: HexCoord(3, 5))
        try draw(708, for: "savvas-icestorm")
        make(.air, .strong)
        try await act("savvas-icestorm")
        XCTAssertEqual(try hex(piece(brute)).distance(to: try hex(icestorm.piece)), 5, "Push 4 instead of 2")
        XCTAssertNotEqual(element(.air), .strong)
    }

    /// No one beside it to push: the push isn't performed, and its Air isn't consumed.
    func testAPushWithNoOneToPushConsumesNothing() async throws {
        character("brute", at: HexCoord(11, 11))
        let icestorm = try monster("savvas-icestorm", at: HexCoord(0, 0))
        icestorm.entity.entityConditions = [EntityCondition(name: .disarm)]
        try draw(708, for: "savvas-icestorm")
        make(.air, .strong)
        try await act("savvas-icestorm")
        XCTAssertEqual(element(.air), .strong)
    }

    /// Lurker (612): "Shield 1; Ice: Shield 2 instead" — its Ice is consumed as it shields.
    func testALurkersIceIsConsumedForItsShield() async throws {
        character("brute", at: HexCoord(1, 1))
        let lurker = try monster("lurker", at: HexCoord(8, 8))
        try draw(612, for: "lurker")
        make(.ice, .strong)
        let own = try statValue(.shield, "lurker")
        try await act("lurker")
        XCTAssertEqual(coord.shield(of: lurker.piece), own + 2)
        XCTAssertNotEqual(element(.ice), .strong)
    }

    // MARK: - Heals (MON-9)

    private func hurt(_ entity: GameMonsterEntity, by damage: Int, of health: Int = 20) {
        entity.maxHealth = health
        entity.health = health - damage
    }

    /// A monster's Heal goes to itself or the ally within range that has lost the most.
    func testAMonstersHealGoesToTheMostDamagedAllyInRange() async throws {
        let shaman = try monster("vermling-shaman", at: HexCoord(5, 5))
        let scratched = try monster("bandit-guard", at: HexCoord(6, 5))
        let wounded = try monster("bandit-guard", at: HexCoord(7, 5))
        let dying = try monster("bandit-guard", at: HexCoord(10, 5))   // five hexes away
        hurt(shaman.entity, by: 2)
        hurt(scratched.entity, by: 1)
        hurt(wounded.entity, by: 6)
        hurt(dying.entity, by: 15)
        try draw(590, for: "vermling-shaman")   // Move +0, Heal 3, Range 3
        try await act("vermling-shaman")
        XCTAssertEqual(wounded.entity.health, 20 - 6 + 3, "the worst hurt within three hexes")
        XCTAssertEqual(scratched.entity.health, 19)
        XCTAssertEqual(shaman.entity.health, 18)
        XCTAssertEqual(dying.entity.health, 5, "out of range")
    }

    /// Shaman / Inox Necromancer card 594: "Heal 1, affect all adjacent allies".
    func testAShamansHealReachesEveryAdjacentAlly() async throws {
        let shaman = try monster("vermling-shaman", at: HexCoord(5, 5))
        let left = try monster("bandit-guard", at: HexCoord(4, 5))
        let right = try monster("bandit-guard", at: HexCoord(6, 5))
        let apart = try monster("bandit-guard", at: HexCoord(8, 5))
        for entity in [shaman.entity, left.entity, right.entity, apart.entity] { hurt(entity, by: 5) }
        try draw(594, for: "vermling-shaman")
        try await act("vermling-shaman")
        XCTAssertEqual(left.entity.health, 16)
        XCTAssertEqual(right.entity.health, 16, "every adjacent ally, not one figure")
        XCTAssertEqual(apart.entity.health, 15, "not adjacent")
        XCTAssertEqual(shaman.entity.health, 15, "its allies, not itself")
    }

    /// Captain of the Guard, special 1: "Heal 2, affect self and all allies".
    func testTheCaptainsHealReachesHimselfAndEveryAlly() async throws {
        character("brute", at: HexCoord(0, 0))
        character("tinkerer", at: HexCoord(0, 2))
        let captain = try monster("captain-of-the-guard", .boss, at: HexCoord(6, 6))
        let near = try monster("city-guard", at: HexCoord(7, 6))
        let far = try monster("city-guard", at: HexCoord(11, 11))
        for entity in [captain.entity, near.entity, far.entity] { hurt(entity, by: 5) }
        try draw(575, for: "captain-of-the-guard")   // special 1
        try await act("captain-of-the-guard")
        XCTAssertEqual(captain.entity.health, 17)
        XCTAssertEqual(near.entity.health, 17)
        XCTAssertEqual(far.entity.health, 17, "all allies, however far")
    }

    /// Sun Demon 652: "Heal 3, Range 3" heals one figure…
    func testASunDemonsHealIsForOneFigure() async throws {
        let demon = try monster("sun-demon", at: HexCoord(5, 5))
        let first = try monster("bandit-guard", at: HexCoord(6, 5))
        let second = try monster("bandit-guard", at: HexCoord(7, 5))
        hurt(first.entity, by: 6)
        hurt(second.entity, by: 4)
        try draw(652, for: "sun-demon")
        try await act("sun-demon")
        XCTAssertEqual(first.entity.health, 17)
        XCTAssertEqual(second.entity.health, 16)
        _ = demon
    }

    /// …and with Light consumed, "affect all allies within range instead".
    func testASunDemonsLightHealReachesEveryAllyInRange() async throws {
        try monster("sun-demon", at: HexCoord(5, 5))
        let first = try monster("bandit-guard", at: HexCoord(6, 5))
        let second = try monster("bandit-guard", at: HexCoord(7, 5))
        let beyond = try monster("bandit-guard", at: HexCoord(10, 5))
        for entity in [first.entity, second.entity, beyond.entity] { hurt(entity, by: 6) }
        try draw(652, for: "sun-demon")
        make(.light, .strong)
        try await act("sun-demon")
        XCTAssertEqual(first.entity.health, 17)
        XCTAssertEqual(second.entity.health, 17, "all allies within three hexes")
        XCTAssertEqual(beyond.entity.health, 14, "five hexes away")
        XCTAssertNotEqual(element(.light), .strong)
    }

    /// Savvas Lavaflow 722: "Heal 4, Range 3; Earth: Target 3" — the three that have lost most.
    func testALavaflowsEarthHealReachesThree() async throws {
        try monster("savvas-lavaflow", at: HexCoord(5, 5))
        let guards = try [HexCoord(6, 5), HexCoord(7, 5), HexCoord(4, 5), HexCoord(3, 5)].map { try monster("bandit-guard", at: $0) }
        for (guardian, damage) in zip(guards, [8, 6, 5, 2]) { hurt(guardian.entity, by: damage) }
        try draw(722, for: "savvas-lavaflow")
        make(.earth, .strong)
        try await act("savvas-lavaflow")
        XCTAssertEqual(guards.map(\.entity.health), [16, 18, 19, 18], "the three worst hurt heal 4; the fourth nothing")
    }

    func testALavaflowsHealIsForOneWithoutEarth() async throws {
        try monster("savvas-lavaflow", at: HexCoord(5, 5))
        let guards = try [HexCoord(6, 5), HexCoord(7, 5)].map { try monster("bandit-guard", at: $0) }
        for (guardian, damage) in zip(guards, [8, 6]) { hurt(guardian.entity, by: damage) }
        try draw(722, for: "savvas-lavaflow")
        try await act("savvas-lavaflow")
        XCTAssertEqual(guards.map(\.entity.health), [16, 14])
    }

    // MARK: - Abilities on several figures (MON-1, MON-7)

    /// Savvas Lavaflow 721: "All enemies suffer 2 damage. Fire: Wound all enemies. Earth:
    /// Disarm all enemies." — all of them, not the ones beside it.
    func testALavaflowWoundsAndDisarmsEveryEnemy() async throws {
        let beside = character("brute", at: HexCoord(4, 5))
        let across = character("tinkerer", at: HexCoord(11, 11))
        try monster("savvas-lavaflow", at: HexCoord(3, 5))
        try draw(721, for: "savvas-lavaflow")
        make(.fire, .strong)
        make(.earth, .strong)
        try await act("savvas-lavaflow")
        for enemy in [beside, across] {
            XCTAssertEqual(enemy.health, 28, "all enemies suffer 2")
            XCTAssertTrue(isActive(.wound, on: enemy), "Fire: Wound all enemies")
            XCTAssertTrue(isActive(.disarm, on: enemy), "Earth: Disarm all enemies")
        }
    }

    /// Living Corpse 564: "Muddle and Immobilize, target one adjacent enemy" — its focus when
    /// that one is adjacent, not whoever comes first on the board.
    func testALivingCorpseGrabsItsFocus() async throws {
        let later = character("brute", at: HexCoord(4, 5), initiative: 60)
        let focus = character("tinkerer", at: HexCoord(6, 5), initiative: 10)
        let corpse = try monster("living-corpse", at: HexCoord(5, 5))
        corpse.entity.entityConditions = [EntityCondition(name: .immobilize)]   // both stay adjacent
        XCTAssertLessThan(piece(later), piece(focus), "the Brute sorts first")
        try draw(564, for: "living-corpse")
        try await act("living-corpse")
        XCTAssertTrue(isActive(.muddle, on: focus))
        XCTAssertTrue(isActive(.immobilize, on: focus), "the focus: it acts first of the two beside it")
        XCTAssertFalse(isActive(.muddle, on: later))
        XCTAssertFalse(isActive(.immobilize, on: later))
    }

    /// Night Demon 667: "All adjacent enemies and allies suffer 1 damage."
    func testANightDemonHurtsEnemiesAndAlliesBesideIt() async throws {
        let brute = character("brute", at: HexCoord(4, 5))
        let demon = try monster("night-demon", at: HexCoord(5, 5))
        let ally = try monster("bandit-guard", at: HexCoord(6, 5))
        let apart = try monster("bandit-guard", at: HexCoord(9, 9))
        try draw(667, for: "night-demon")
        try await act("night-demon")
        XCTAssertEqual(ally.entity.health, ally.entity.maxHealth - 1, "the ally beside it")
        XCTAssertEqual(apart.entity.health, apart.entity.maxHealth)
        XCTAssertTrue(coord.turnLog.contains { $0.message == "Brute suffers 1 damage" }, "and the enemy")
        _ = (brute, demon)
    }

    // MARK: - The Captain of the Guard's order

    /// "All allies add +1 Attack to all attacks this round": the Captain's allies — not the
    /// monsters fighting him, and not himself (his own special prints Attack +1).
    func testTheCaptainsOrderIsForHisAlliesOnly() async throws {
        let brute = character("brute", at: HexCoord(5, 5))
        character("tinkerer", at: HexCoord(0, 0))
        let captain = try monster("captain-of-the-guard", .boss, at: HexCoord(6, 5))
        let guardian = try monster("city-guard", at: HexCoord(4, 5))
        let demon = try monster("earth-demon", at: HexCoord(7, 5))   // fights on the party's side
        try type("earth-demon").isAlly = true
        guardian.entity.health = 30
        guardian.entity.maxHealth = 30
        captain.entity.health = 60
        captain.entity.maxHealth = 60

        try draw(572, for: "captain-of-the-guard")   // special 2
        try await act("captain-of-the-guard")
        let captainAttack = try XCTUnwrap(try type("captain-of-the-guard").stat(for: .boss)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(attackValues(on: "Brute"), [captainAttack + 1], "his special's own +1, and no more")

        try draw(527, for: "city-guard")   // Move +0, Attack +0
        try await act("city-guard")
        let guardAttack = try XCTUnwrap(try type("city-guard").stat(for: .normal)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(attackValues(on: "Brute").last, guardAttack + 1, "his ally adds +1")

        try draw(638, for: "earth-demon")   // Move +0, Attack +0
        var demonAttacks = 0
        coord.attackObserver = { attacker, _ in if attacker == demon.piece { demonAttacks += 1 } }
        let before = coord.turnLog.count
        try await act("earth-demon")
        let demonAttack = try XCTUnwrap(try type("earth-demon").stat(for: .normal)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(demonAttacks, 1)
        let logged = coord.turnLog[before...].compactMap { entry in
            entry.message.components(separatedBy: " attacks ").dropFirst().first?
                .components(separatedBy: ": ").dropFirst().first?.split(separator: " ").first.flatMap { Int($0) }
        }
        XCTAssertEqual(logged, [demonAttack], "the Captain's enemy gains nothing from his order")

        endRound()
        XCTAssertFalse(guardian.entity.tags.contains { $0.hasPrefix(MonsterAbility.roundAttackTag) }, "this round only")
        _ = brute
    }

    // MARK: - Disarmed and muddled monsters (MON-5, MON-6)

    /// A disarmed monster moves as if it had no attack: toward its focus, as near as it can —
    /// not to the range of the attack it can't make.
    func testADisarmedArcherClosesInOnItsFocus() async throws {
        let brute = character("brute", at: HexCoord(2, 5))
        let archers = try [HexCoord(6, 5), HexCoord(6, 8)].map { try monster("bandit-archer", at: $0) }
        let range = try XCTUnwrap(try type("bandit-archer").stat(for: .normal)?.rangeValue(characterCount: 2, level: 1))
        XCTAssertEqual(try hex(archers[0].piece).distance(to: HexCoord(2, 5)), range, "in range as it stands")
        archers[0].entity.entityConditions = [EntityCondition(name: .disarm)]
        try draw(533, for: "bandit-archer")   // Move +0, Attack +0
        var moved: [PieceID: Int] = [:]
        coord.moveObserver = { piece, path, _ in moved[piece, default: 0] += path.count - 1 }
        var attackers: [PieceID] = []
        coord.attackObserver = { attacker, _ in attackers.append(attacker) }
        try await act("bandit-archer", only: [archers[0].entity])
        XCTAssertEqual(moved[archers[0].piece], 2, "its whole Move, toward the Brute")
        XCTAssertEqual(try hex(archers[0].piece).distance(to: try hex(piece(brute))), range - 2)
        XCTAssertTrue(attackers.isEmpty, "and no attack")
    }

    /// Able to attack from where it stands, an archer stays there.
    func testAnArcherInRangeStaysPut() async throws {
        character("brute", at: HexCoord(2, 5))
        let archer = try monster("bandit-archer", at: HexCoord(6, 5))
        try draw(533, for: "bandit-archer")
        var moves = 0
        coord.moveObserver = { _, _, _ in moves += 1 }
        try await act("bandit-archer")
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(try hex(archer.piece), HexCoord(6, 5))
        XCTAssertEqual(attackValues(on: "Brute").count, 1)
    }

    /// Beside its focus a disarmed archer stays: it has no Disadvantage to lose.
    func testADisarmedArcherDoesNotStepAwayFromItsFocus() async throws {
        character("brute", at: HexCoord(5, 5))
        let archer = try monster("bandit-archer", at: HexCoord(6, 5))
        archer.entity.entityConditions = [EntityCondition(name: .disarm)]
        try draw(533, for: "bandit-archer")
        try await act("bandit-archer")
        XCTAssertEqual(try hex(archer.piece), HexCoord(6, 5))
    }

    /// An archer beside its focus steps away to attack without Disadvantage…
    func testAnArcherStepsAwayFromAnAdjacentFocus() async throws {
        character("brute", at: HexCoord(5, 5))
        let archer = try monster("bandit-archer", at: HexCoord(6, 5))
        try draw(533, for: "bandit-archer")
        try await act("bandit-archer")
        XCTAssertGreaterThan(try hex(archer.piece).distance(to: HexCoord(5, 5)), 1)
        XCTAssertEqual(attackValues(on: "Brute").count, 1)
    }

    /// …but not a muddled one: it has Disadvantage wherever it stands (FAQ).
    func testAMuddledArcherDoesNotStepAwayFromItsFocus() async throws {
        character("brute", at: HexCoord(5, 5))
        let archer = try monster("bandit-archer", at: HexCoord(6, 5))
        archer.entity.entityConditions = [EntityCondition(name: .muddle)]
        try draw(533, for: "bandit-archer")
        try await act("bandit-archer")
        XCTAssertEqual(try hex(archer.piece), HexCoord(6, 5), "it attacks from where it is")
        XCTAssertEqual(attackValues(on: "Brute").count, 1)
    }

    /// A ranged monster whose card has no attack moves as for a melee attack: up to its focus.
    func testARangedMonsterWithNoAttackOnItsCardMovesUpToItsFocus() async throws {
        character("brute", at: HexCoord(2, 5))
        let imp = try monster("forest-imp", at: HexCoord(5, 5))
        let range = try XCTUnwrap(try type("forest-imp").stat(for: .normal)?.rangeValue(characterCount: 2, level: 1))
        XCTAssertGreaterThanOrEqual(range, 3, "the Brute is in range already")
        try draw(679, for: "forest-imp")   // Move +1, Heal 2 Range 3
        try await act("forest-imp")
        XCTAssertEqual(try hex(imp.piece).distance(to: HexCoord(2, 5)), 1, "beside the Brute")
    }

    /// The fourth thing a monster weighs in choosing where to attack from: with the focus
    /// attacked without Disadvantage and as many targets either way, the hex from which its
    /// other target has no Disadvantage either — though it costs more movement.
    func testAShamanAvoidsDisadvantageOnItsSecondTarget() async throws {
        // Between its two targets: every hex one step away that is off its focus is beside the
        // other target; two steps away it is clear of both.
        let focus = character("brute", at: HexCoord(4, 5), initiative: 10)
        let other = character("tinkerer", at: HexCoord(6, 5), initiative: 60)
        let shaman = try monster("vermling-shaman", at: HexCoord(5, 5))
        try draw(595, for: "vermling-shaman")   // Move +1, Attack −1, Target 2
        var moved = 0
        coord.moveObserver = { _, path, _ in moved += path.count - 1 }
        var attacked: [PieceID] = []
        coord.attackObserver = { _, target in attacked.append(target) }
        try await act("vermling-shaman")
        XCTAssertEqual(attacked, [piece(focus), piece(other)], "the focus, then its second target")
        let end = try hex(shaman.piece)
        XCTAssertGreaterThan(end.distance(to: HexCoord(4, 5)), 1, "no Disadvantage on the focus")
        XCTAssertGreaterThan(end.distance(to: HexCoord(6, 5)), 1, "nor on the second target")
        XCTAssertEqual(moved, 2, "though one step would have cleared the focus")
    }

    // MARK: - Loot and summons (MON-9)

    /// Monster Loot takes the money tokens around it, which are lost with it: no one has them,
    /// and it drops only its own when it dies.
    func testAMonstersLootTakesCoinsAndTheyAreLost() async throws {
        let brute = character("brute", at: HexCoord(0, 0))
        let scout = try monster("vermling-scout", at: HexCoord(8, 8))
        scout.entity.entityConditions = [EntityCondition(name: .immobilize)]
        coord.boardState.placeLoot(at: HexCoord(9, 8), count: 2)
        coord.boardState.placeLoot(at: HexCoord(8, 8))
        coord.boardState.placeLoot(at: HexCoord(10, 8))   // two hexes away
        coord.boardState.cells[HexCoord(7, 8)]?.overlay = .treasure
        coord.boardState.cells[HexCoord(7, 8)]?.treasureID = "7"
        let (money, tokens) = (brute.loot, brute.lootCards.count)
        try draw(675, for: "vermling-scout")   // Move +1 Jump, Loot 1
        try await act("vermling-scout")
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(9, 8)])
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(8, 8)])
        XCTAssertEqual(coord.boardState.lootTokens[HexCoord(10, 8)], 1, "out of its reach")
        XCTAssertEqual(coord.boardState.cells[HexCoord(7, 8)]?.overlay, .treasure, "a treasure tile beside it is left alone")
        XCTAssertEqual(coord.boardState.cells[HexCoord(7, 8)]?.treasureID, "7")
        XCTAssertEqual(brute.loot, money, "no one gains them")
        XCTAssertEqual(brute.lootCards.count, tokens)

        coord.sufferDamage(99, to: scout.piece, killer: piece(brute))
        coord.sweepDeadFigures()
        XCTAssertEqual(coord.boardState.lootTokens[HexCoord(8, 8)], 1, "its own token, not the three it took")
    }

    /// A monster's summon goes on the empty hex beside the summoner nearest an enemy, takes no
    /// turn the round it arrives, and leaves no money token.
    func testASummonedMonsterStandsNearestTheEnemyAndWaitsARound() async throws {
        let brute = character("brute", at: HexCoord(9, 5))
        let cultist = try monster("cultist", at: HexCoord(4, 5))
        try draw(609, for: "cultist")   // Summon Living Bones, suffer 2
        try await act("cultist")
        let bones = try type("living-bones")
        let summoned = try XCTUnwrap(bones.aliveEntities.first)
        let summonedPiece = PieceID.monster(name: "living-bones", standee: summoned.number)
        XCTAssertEqual(try hex(summonedPiece), HexCoord(5, 5), "beside the Cultist, toward the Brute")
        XCTAssertEqual(summoned.summonState, .new)
        XCTAssertEqual(cultist.entity.health, cultist.entity.maxHealth - 2)

        try draw(519, for: "living-bones")   // Move +0, Attack +0
        var acted = 0
        coord.moveObserver = { piece, _, _ in if piece == summonedPiece { acted += 1 } }
        coord.attackObserver = { attacker, _ in if attacker == summonedPiece { acted += 1 } }
        try await act("living-bones")
        XCTAssertEqual(acted, 0, "not in the round it was summoned")
        XCTAssertEqual(try hex(summonedPiece), HexCoord(5, 5))

        coord.sufferDamage(99, to: summonedPiece, killer: piece(brute))
        coord.sweepDeadFigures()
        XCTAssertNil(coord.boardState.lootTokens[HexCoord(5, 5)], "a summoned monster drops nothing")

        // The next round it acts like any other.
        endRound()
        let again = try monster("living-bones", at: HexCoord(5, 5), origin: .summoned)
        endRound()
        try draw(519, for: "living-bones")
        var moved = 0
        coord.moveObserver = { piece, _, _ in if piece == again.piece { moved += 1 } }
        try await act("living-bones")
        XCTAssertEqual(moved, 1, "from the next round on it takes its turns")
    }

    /// With every standee of the type on the board, nothing is summoned.
    func testNoMonsterIsSummonedWithoutAFreeStandee() async throws {
        character("brute", at: HexCoord(11, 11))
        let cultist = try monster("cultist", at: HexCoord(4, 5))
        gm.monsterManager.addMonster(name: "living-bones", edition: "gh")
        let limit = try type("living-bones").maxCount
        for index in 0..<limit { try monster("living-bones", at: HexCoord(index, 0)) }
        try draw(609, for: "cultist")
        try await act("cultist")
        XCTAssertEqual(try type("living-bones").aliveEntities.count, limit, "no eleventh Living Bones")
        XCTAssertEqual(cultist.entity.health, cultist.entity.maxHealth - 2, "it still suffers the damage")
    }

    // MARK: - Order and focus on the board (RND-7, MON-2, MON-4, MON-6, MON-7, MON-14)

    /// Elites act before normals, each in ascending standee order.
    func testElitesActBeforeNormalsEachInStandeeOrder() async throws {
        character("brute", at: HexCoord(0, 0))
        let spots = [HexCoord(11, 3), HexCoord(11, 5), HexCoord(11, 7), HexCoord(11, 9), HexCoord(11, 11)]
        let kinds: [MonsterType] = [.normal, .elite, .normal, .elite, .normal]
        let guards = try zip(spots, kinds).map { try monster("bandit-guard", $1, at: $0) }
        try draw(527, for: "bandit-guard")   // Move +0, Attack +0: each walks toward the Brute in its turn
        var order: [Int] = []
        coord.moveObserver = { piece, _, _ in
            if case .monster(_, let standee) = piece, !order.contains(standee) { order.append(standee) }
        }
        try await act("bandit-guard")
        let elites = guards.filter { $0.entity.type == .elite }.map(\.entity.number).sorted()
        let normals = guards.filter { $0.entity.type == .normal }.map(\.entity.number).sorted()
        XCTAssertEqual(order, elites + normals)
    }

    /// With no one to focus on a monster neither moves nor attacks, and still does the rest of
    /// its card.
    func testAMonsterWithNoFocusStillPerformsItsOtherAbilities() async throws {
        let hidden = character("brute", at: HexCoord(4, 5))
        hidden.entityConditions = [EntityCondition(name: .invisible)]
        let guardian = try monster("bandit-guard", at: HexCoord(8, 5))
        try draw(530, for: "bandit-guard")   // Move −1, Attack +0, Strengthen self
        var moves = 0
        coord.moveObserver = { _, _, _ in moves += 1 }
        try await act("bandit-guard")
        XCTAssertEqual(moves, 0)
        XCTAssertTrue(attackValues(on: "Brute").isEmpty)
        XCTAssertTrue(guardian.entity.entityConditions.contains { $0.name == .strengthen }, "Strengthen, self")
    }

    /// A monster that can attack from where it stands doesn't move.
    func testAMonsterBesideItsFocusStaysPut() async throws {
        character("brute", at: HexCoord(4, 5))
        let guardian = try monster("bandit-guard", at: HexCoord(5, 5))
        try draw(527, for: "bandit-guard")
        var moves = 0
        coord.moveObserver = { _, _, _ in moves += 1 }
        try await act("bandit-guard")
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(try hex(guardian.piece), HexCoord(5, 5))
        XCTAssertEqual(attackValues(on: "Brute").count, 1)
    }

    /// A corridor one hex wide along row 5, from column 0 to `length - 1`.
    private func corridor(length: Int) {
        for hex in Array(coord.boardState.cells.keys) where hex.row != 5 || hex.col >= length {
            coord.boardState.cells[hex] = nil
        }
    }

    /// A monster that can end no nearer its focus doesn't move: its allies fill the hexes its
    /// Move reaches.
    func testAMonsterThatCannotGetNearerDoesNotMove() async throws {
        corridor(length: 10)
        character("brute", at: HexCoord(9, 5))
        let mover = try monster("living-corpse", at: HexCoord(2, 5))
        let ahead = try [HexCoord(3, 5), HexCoord(4, 5)].map { try monster("living-corpse", at: $0) }
        try draw(565, for: "living-corpse")   // Move +1 (2 in all), Attack −1
        var moves = 0
        coord.moveObserver = { piece, _, _ in if piece == mover.piece { moves += 1 } }
        try await act("living-corpse", only: [mover.entity])
        XCTAssertEqual(moves, 0)
        XCTAssertEqual(try hex(mover.piece), HexCoord(2, 5))
        _ = ahead
    }

    /// Each Attack line on a card is an attack of its own, and may be made on the focus again.
    func testEachAttackLineHitsTheFocusAgain() async throws {
        let brute = character("brute", at: HexCoord(4, 5))
        try monster("rending-drake", at: HexCoord(5, 5))
        try draw(554, for: "rending-drake")   // Attack −1, Attack −1, Attack −2
        var targets: [PieceID] = []
        coord.attackObserver = { _, target in targets.append(target) }
        try await act("rending-drake")
        XCTAssertEqual(targets, Array(repeating: piece(brute), count: 3))
        let base = try XCTUnwrap(try type("rending-drake").stat(for: .normal)?.attackValue(characterCount: 2, level: 1))
        XCTAssertEqual(attackValues(on: "Brute"), [base - 1, base - 1, base - 2])
    }

    /// Each monster finds its focus as its own turn starts, with the monsters before it where
    /// they moved to: the first takes the only hex beside the Brute, so the second goes for the
    /// Tinkerer.
    func testTheSecondMonsterFocusesAfterTheFirstHasMoved() async throws {
        corridor(length: 12)
        let brute = character("brute", at: HexCoord(0, 5), initiative: 10)
        let first = try monster("bandit-guard", .elite, at: HexCoord(2, 5))
        let second = try monster("bandit-guard", at: HexCoord(3, 5))
        let tinkerer = character("tinkerer", at: HexCoord(7, 5), initiative: 90)
        try draw(525, for: "bandit-guard")   // Move +1, Attack −1
        var attacks: [PieceID: [PieceID]] = [:]
        coord.attackObserver = { attacker, target in attacks[attacker, default: []].append(target) }
        try await act("bandit-guard")
        XCTAssertEqual(attacks[first.piece], [piece(brute)])
        XCTAssertEqual(attacks[second.piece], [piece(tinkerer)], "the hex beside the Brute is taken")
    }

    /// An invisible character can't be focused on and blocks the way like an obstacle.
    func testAnInvisibleCharacterBlocksAMonstersWay() async throws {
        corridor(length: 10)
        let hidden = character("brute", at: HexCoord(4, 5), initiative: 10)
        hidden.entityConditions = [EntityCondition(name: .invisible)]
        let beyond = character("tinkerer", at: HexCoord(0, 5), initiative: 90)
        let guardian = try monster("bandit-guard", at: HexCoord(7, 5))
        try draw(527, for: "bandit-guard")
        var attacked: [PieceID] = []
        coord.attackObserver = { _, target in attacked.append(target) }
        try await act("bandit-guard")
        XCTAssertTrue(attacked.isEmpty, "neither the invisible Brute nor the Tinkerer behind him")
        XCTAssertEqual(try hex(guardian.piece), HexCoord(7, 5), "no way past: no focus, no move")
        _ = beyond
    }

    /// Without the invisibility the same guard walks up and attacks.
    func testAVisibleCharacterInTheWayIsAttacked() async throws {
        corridor(length: 10)
        let brute = character("brute", at: HexCoord(4, 5), initiative: 10)
        character("tinkerer", at: HexCoord(0, 5), initiative: 90)
        try monster("bandit-guard", at: HexCoord(7, 5))
        try draw(527, for: "bandit-guard")
        var attacked: [PieceID] = []
        coord.attackObserver = { _, target in attacked.append(target) }
        try await act("bandit-guard")
        XCTAssertEqual(attacked, [piece(brute)])
    }
}
