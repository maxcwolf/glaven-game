import XCTest
import SpriteKit
@testable import GlavenGameLib

/// Every figure's token shows who it is (portrait, rank, standee number, owner) and how it is
/// doing (health and conditions), and keeps showing it after spawns, damage and board rebuilds.
@MainActor
final class BoardTokenTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }
    private var scene: BoardScene { coord.boardScene! }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        XCTAssertNotNil(coord.boardScene)
    }

    private var monsterPieces: [PieceID] {
        coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
    }

    private func freeHex() throws -> HexCoord {
        try XCTUnwrap(coord.boardState.cells.keys.sorted().first {
            coord.boardState.isPassable($0) && !coord.boardState.isOccupied($0)
        })
    }

    private func placeCharacters() {
        for character in gm.game.characters {
            let free = coord.boardState.startingLocations.first { !coord.boardState.isOccupied($0) }!
            coord.placeCharacter(characterID: character.id, at: free)
        }
    }

    func testMonsterTokensShowPortraitStandeeAndRank() throws {
        XCTAssertFalse(monsterPieces.isEmpty)
        for piece in monsterPieces {
            guard case .monster(let name, let standee) = piece else { continue }
            let node = try XCTUnwrap(scene.pieceNode(for: piece), "\(piece)")
            let entity = try XCTUnwrap(coord.monsterEntity(name: name, standee: standee))
            XCTAssertNotNil(node.childNode(withName: "portrait"), "\(piece) shows the monster's portrait")
            XCTAssertEqual(node.appearance.badge, "\(standee)")
            switch entity.type {
            case .normal: XCTAssertEqual(node.appearance.rank, .normal)
            case .elite: XCTAssertEqual(node.appearance.rank, .elite)
            case .boss: XCTAssertEqual(node.appearance.rank, .boss)
            }
            XCTAssertFalse(node.appearance.isPlayerSide)
        }
        XCTAssertTrue(monsterPieces.contains { scene.pieceNode(for: $0)?.appearance.rank == .elite },
                      "Black Barrow starts with an elite guard")
    }

    func testCharacterTokensUseTheirPortraitAndColour() throws {
        placeCharacters()
        for character in gm.game.characters {
            let node = try XCTUnwrap(scene.pieceNode(for: .character(character.id)))
            XCTAssertNotNil(node.childNode(withName: "portrait"))
            XCTAssertEqual(node.appearance.rimColor, SKColor(hex: character.color))
            XCTAssertTrue(node.appearance.isPlayerSide)
            XCTAssertEqual(node.status?.health, character.maxHealth)
        }
    }

    func testTokensFollowHealthAndConditions() throws {
        let piece = try XCTUnwrap(monsterPieces.first)
        let entity = try XCTUnwrap(coord.entity(for: piece))
        let node = try XCTUnwrap(scene.pieceNode(for: piece))
        XCTAssertEqual(node.status, PieceStatus(health: entity.maxHealth, maxHealth: entity.maxHealth, conditions: []))

        coord.sufferDamage(2, to: piece)
        XCTAssertEqual(node.status?.health, entity.maxHealth - 2)

        coord.applyCondition(.poison, to: piece)
        coord.applyCondition(.immobilize, to: piece)
        XCTAssertEqual(node.shownConditions, [.immobilize, .poison])
        XCTAssertNotNil(node.childNode(withName: "//condition-poison"))

        // Healing a poisoned figure removes the poison instead of restoring health (p.23).
        coord.heal(piece, amount: 1)
        XCTAssertEqual(node.shownConditions, [.immobilize])
        XCTAssertEqual(node.status?.health, entity.health)
    }

    func testAtMostFourConditionIconsAreShown() throws {
        let piece = try XCTUnwrap(monsterPieces.first)
        for condition in [ConditionName.poison, .wound, .immobilize, .disarm, .muddle] {
            coord.applyCondition(condition, to: piece)
        }
        let node = try XCTUnwrap(scene.pieceNode(for: piece))
        XCTAssertEqual(node.status?.conditions.count, 5)
        XCTAssertEqual(node.shownConditions.count, PieceSpriteNode.maxConditionIcons)
    }

    /// Regression: monsters entering mid-scenario (spawns, summons) were drawn as normals because
    /// elite styling was applied only when the whole board was built.
    func testSpawnedEliteLooksElite() throws {
        let hex = try freeHex()
        let piece = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .elite, at: hex, origin: .spawned))
        let node = try XCTUnwrap(scene.pieceNode(for: piece))
        XCTAssertEqual(node.appearance.rank, .elite)
        XCTAssertEqual(node.appearance.rimColor, PieceAppearance.eliteRim)
        XCTAssertNotNil(node.status, "a spawned token shows its health at once")
    }

    func testSummonTokenTakesItsOwnersColour() throws {
        placeCharacters()
        let tinkerer = try XCTUnwrap(gm.game.characters.first { $0.name == "tinkerer" })
        let data = try XCTUnwrap(tinkerer.characterData?.availableSummons?.first)
        gm.characterManager.addSummon(from: data, for: tinkerer)
        let summon = try XCTUnwrap(tinkerer.summons.last)
        coord.placeSummon(summonID: summon.id, characterID: tinkerer.id, at: try freeHex())

        let node = try XCTUnwrap(scene.pieceNode(for: .summon(id: summon.id)))
        XCTAssertEqual(node.appearance.rank, .summon)
        XCTAssertEqual(node.appearance.rimColor, SKColor(hex: tinkerer.color))
        XCTAssertTrue(node.appearance.isPlayerSide)
        XCTAssertFalse(node.appearance.initials.isEmpty)
    }

    /// Rebuilding the board (undo, room reveal) keeps every token's health and conditions.
    func testRebuildKeepsTokenState() throws {
        let piece = try XCTUnwrap(monsterPieces.first)
        coord.sufferDamage(1, to: piece)
        coord.applyCondition(.wound, to: piece)
        coord.restore(from: coord.snapshot())

        let rebuilt = try XCTUnwrap(scene.pieceNode(for: piece))
        let entity = try XCTUnwrap(coord.entity(for: piece))
        XCTAssertEqual(rebuilt.status?.health, entity.health)
        XCTAssertEqual(rebuilt.shownConditions, [.wound])
    }
}
