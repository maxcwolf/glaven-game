import XCTest
import SwiftData
@testable import GlavenGameLib

/// Monster ability cards' printed text, done on the board: traps, damage around the monster,
/// bonuses against flanked targets, disadvantage against it.
@MainActor
final class MonsterTextTests: XCTestCase {

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

    private func character(_ name: String, at hex: HexCoord) -> GameCharacter {
        gm.characterManager.addCharacter(name: name, edition: "gh")
        let character = gm.game.characters.last!
        coord.boardState.placePiece(.character(character.id), at: hex)
        character.health = 30
        character.maxHealth = 30
        character.handCards = []
        return character
    }

    /// Put a monster on the board with `cardId` as its drawn ability card, and play its turn.
    @discardableResult
    private func play(_ name: String, card cardId: Int, at hex: HexCoord, also: [HexCoord] = []) async throws -> PieceID {
        let piece = try XCTUnwrap(coord.spawnMonster(name: name, type: .normal, at: hex, origin: .placed))
        for other in also { coord.spawnMonster(name: name, type: .normal, at: other, origin: .placed) }
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == name })
        let deck = gm.monsterManager.abilities(for: monster)
        let index = try XCTUnwrap(deck.firstIndex { $0.cardId == cardId }, "card \(cardId)")
        monster.abilities = [index]
        monster.ability = 0
        monster.abilityDrawn = true
        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        return piece
    }

    /// Bandit Archer (card 538): "Create a 3 damage trap in an adjacent empty hex closest to an enemy."
    func testAnArcherSetsATrapTowardTheEnemy() async throws {
        _ = character("brute", at: HexCoord(8, 3))
        let archer = try await play("bandit-archer", card: 538, at: HexCoord(3, 3))
        let archerHex = try XCTUnwrap(coord.boardState.piecePositions[archer])
        let traps = coord.boardState.cells.values.filter(\.isTrap)
        XCTAssertEqual(traps.count, 1)
        let trap = try XCTUnwrap(traps.first)
        XCTAssertTrue(trap.coord.isAdjacent(to: archerHex))
        XCTAssertEqual(trap.trapDamage, 3)
        let closer = archerHex.neighbors.filter { coord.isEmptyHex($0) || $0 == trap.coord }.map { $0.distance(to: HexCoord(8, 3)) }.min() ?? 0
        XCTAssertEqual(trap.coord.distance(to: HexCoord(8, 3)), closer, "the hex nearest the Brute")
    }

    /// Ancient Artillery (701): "All adjacent enemies suffer 2 damage."
    func testArtilleryHurtsTheEnemiesBesideIt() async throws {
        let beside = character("brute", at: HexCoord(4, 3))
        let health = beside.health
        try await play("ancient-artillery", card: 701, at: HexCoord(3, 3))
        XCTAssertLessThanOrEqual(beside.health, health - 2)
    }

    /// Giant Viper (689): "All attacks targeting the Giant Viper this round gain disadvantage."
    func testAGiantViperIsHardToHitThisRound() async throws {
        _ = character("brute", at: HexCoord(6, 3))
        let viper = try await play("giant-viper", card: 689, at: HexCoord(3, 3))
        XCTAssertTrue(coord.disadvantagedThisRound.contains(viper))
    }

    /// Hound (542): "+2 Attack if the target is adjacent to any of the Hound's allies."
    func testAHoundBitesHarderWhenItsPackFlanks() async throws {
        let brute = character("brute", at: HexCoord(4, 3))
        _ = brute
        func lastAttackValue() -> Int? {
            coord.turnLog.last { $0.message.contains("attacks Brute: ") }
                .flatMap { $0.message.components(separatedBy: "attacks Brute: ").last?.split(separator: " ").first }
                .flatMap { Int($0) }
        }
        // Every draw a +0, so the attack's value is what the log shows.
        let zeros = (0..<20).map { _ in AttackModifier.standard(.plus0) }
        gm.game.monsterAttackModifierDeck = AttackModifierDeck(attackModifiers: zeros, cards: zeros)
        let first = try await play("hound", card: 542, at: HexCoord(3, 3))
        let alone = try XCTUnwrap(lastAttackValue())
        coord.spawnMonster(name: "hound", type: .normal, at: HexCoord(5, 3), origin: .placed)
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "hound" })
        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster, only: [1])
        _ = first
        XCTAssertEqual(lastAttackValue(), alone + 2)
    }

    /// Cultist (604): "On death: Attack +2" around where it falls, and not on its own turn.
    func testACultistAttacksAsItDies() async throws {
        let brute = character("brute", at: HexCoord(4, 3))
        let piece = try await play("cultist", card: 604, at: HexCoord(3, 3))
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("attacks as it dies") }, "alive, it doesn't")
        let health = brute.health
        let attacksBefore = coord.turnLog.filter { $0.message.contains("attacks Brute") }.count
        coord.sufferDamage(99, to: piece, killer: .character(brute.id))
        await coord.resolveDeathAttacks()
        XCTAssertTrue(coord.turnLog.contains { $0.message.contains("attacks as it dies") })
        XCTAssertEqual(coord.turnLog.filter { $0.message.contains("attacks Brute") }.count, attacksBefore + 1)
        _ = health
    }

    /// Lurker (612): "Shield 1; consume Ice: Shield 2 instead" — 2, not 3, and not 1.
    func testALurkersIceShieldReplacesItsShield() async throws {
        _ = character("brute", at: HexCoord(6, 3))
        gm.game.elementBoard[gm.game.elementBoard.firstIndex { $0.type == .ice }!].state = .strong
        let piece = try XCTUnwrap(coord.spawnMonster(name: "lurker", type: .normal, at: HexCoord(3, 3), origin: .placed))
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "lurker" })
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 612 })]
        monster.ability = 0
        monster.abilityDrawn = true
        gm.monsterManager.applyStatEffects(for: monster)
        let entity = try XCTUnwrap(coord.entity(for: piece))
        let before = entity.shield?.value?.intValue ?? 0
        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual((entity.shield?.value?.intValue ?? 0) - before, 1, "Shield 1 became Shield 2")
    }

    /// Ooze (696): suffer 2 damage, then split: the new Ooze has the summoner's hit points.
    func testAnOozeSplitsWithItsHitPoints() async throws {
        _ = character("brute", at: HexCoord(8, 3))
        let piece = try XCTUnwrap(coord.spawnMonster(name: "ooze", type: .normal, at: HexCoord(3, 3), origin: .placed))
        let parent = try XCTUnwrap(coord.entity(for: piece) as? GameMonsterEntity)
        parent.health = 5
        let monster = try XCTUnwrap(gm.game.monsters.first { $0.name == "ooze" })
        let deck = gm.monsterManager.abilities(for: monster)
        monster.abilities = [try XCTUnwrap(deck.firstIndex { $0.cardId == 696 })]
        monster.ability = 0
        monster.abilityDrawn = true
        await MonsterTurnController(coordinator: coord, gameManager: gm).executeMonsterGroup(monster)
        XCTAssertEqual(parent.health, 3, "it suffers 2 first")
        let child = try XCTUnwrap(monster.aliveEntities.first { $0.number != parent.number })
        XCTAssertEqual(child.health, 3)
    }
}
