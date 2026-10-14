import XCTest
@testable import GlavenGameLib

/// Walls broken down by damage (`ScenarioPlacements.Walls`, `BoardCoordinator+Walls`): the
/// Harrower Hive (#76), which has no doors.
@MainActor
final class WallTests: XCTestCase {

    private func simulator(_ characters: [String] = ["brute", "spellweaver"], level: Int? = nil) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "76", options: .init(characters: characters, seed: 1, autoResolvePrompts: true,
                                                                        scenarioLevel: level))
        sim.gm.game.round = 1
        return sim
    }

    /// The wall between two tiles (the lowest hex of them).
    private func wall(_ sim: ScenarioSimulator, from: String, to: String) throws -> (hex: HexCoord, piece: PieceID, entity: GameObjectiveEntity) {
        let board = sim.coord.boardState
        let door = try XCTUnwrap(board.doors.filter { !$0.isOpen && $0.fromTileRef?.lowercased() == from && $0.childTileRef.lowercased() == to }
            .min { $0.coord < $1.coord }, "no wall from \(from) to \(to)")
        let piece = try XCTUnwrap(board.piece(at: door.coord), "nothing stands on the wall at \(door.coord)")
        return (door.coord, piece, try XCTUnwrap(sim.coord.entity(for: piece) as? GameObjectiveEntity))
    }

    private func walls(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.doors.filter { !$0.isOpen }.compactMap { sim.coord.boardState.piece(at: $0.coord) }.sorted()
    }

    private func monsters(_ sim: ScenarioSimulator) -> [PieceID] {
        sim.coord.boardState.piecePositions.keys.filter { if case .monster = $0 { return true }; return false }.sorted()
    }

    private func visible(_ sim: ScenarioSimulator) -> Set<String> { Set(sim.coord.boardState.visibleRooms.map { $0.lowercased() }) }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        if let other = sim.coord.boardState.piece(at: hex), other != piece { sim.coord.boardState.removePiece(other) }
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func floor(_ sim: ScenarioSimulator, beside hex: HexCoord, on tile: String) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.neighbors(of: hex).sorted().first {
            board.isPassable($0) && board.cells[$0]?.tileRef.lowercased() == tile && board.cells[$0]?.overlay == nil
        }, "no floor of \(tile) beside \(hex)")
    }

    /// "Each wall has C+(L/2) hit points (rounded up)": every wall the map shows has them, and
    /// more walls come into sight with each room.
    func testEveryWallInSightHasItsHitPoints() throws {
        let sim = try simulator(level: 1)
        let coord = sim.coord
        XCTAssertEqual(walls(sim).count, 2, "the starting tile has two")
        XCTAssertEqual(coord.boardState.doors.count, 2)
        for piece in walls(sim) {
            let entity = try XCTUnwrap(coord.entity(for: piece))
            XCTAssertEqual(entity.maxHealth, 3, "2 characters + half of level 1, rounded up")
            XCTAssertEqual(entity.health, 3)
            XCTAssertEqual(coord.name(piece).hasPrefix("Wall"), true)
        }
        XCTAssertTrue(coord.unplacedObjectiveEntities().isEmpty, "none is left waiting for a wall")
        XCTAssertEqual(try wall(try simulator(["brute", "spellweaver", "cragheart", "scoundrel"], level: 7), from: "b1b", to: "h2a").entity.maxHealth, 8,
                       "4 characters + half of level 7, rounded up")
        XCTAssertEqual(try wall(try simulator(level: 0), from: "b1b", to: "h2a").entity.maxHealth, 2)

        // H2a brings its own walls into sight, each with its hit points.
        let first = try wall(sim, from: "b1b", to: "h2a")
        coord.sufferDamage(999, to: first.piece, killer: .character(sim.gm.game.characters[0].id))
        XCTAssertGreaterThan(coord.boardState.doors.count, 2)
        XCTAssertEqual(walls(sim).count, coord.boardState.doors.filter { !$0.isOpen }.count, "every wall standing has its objective")
        XCTAssertTrue(coord.unplacedObjectiveEntities().isEmpty)
        XCTAssertTrue(coord.boardState.openObjectiveSlots.isEmpty)
    }

    /// There are no doors: no one opens a wall by walking into it, or passes it with a jump.
    func testAWallIsNotOpenedByWalkingIntoIt() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let target = try wall(sim, from: "b1b", to: "h2a")
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let beside = try floor(sim, beside: target.hex, on: "b1b")
        stand(sim, brute, on: beside)
        XCTAssertTrue(coord.boardState.isLockedDoor(target.hex))
        XCTAssertNil(Pathfinder.findPath(board: coord.boardState, from: beside, to: target.hex, canOpenDoors: true))
        XCTAssertTrue(coord.adjacentDoors(from: beside).isEmpty, "nothing to open")
        _ = await coord.moveAlong(brute, path: [beside, target.hex], style: .jump)
        XCTAssertEqual(visible(sim), ["b1b"], "nothing is revealed")
        XCTAssertFalse(coord.boardState.doors.contains { $0.isOpen })
    }

    /// On the board a wall carries no padlock — it is a wall, not a locked door — and once it is
    /// broken down a corridor is drawn where it stood; tapped, each says what it is.
    func testAWallIsDrawnAsAWallThenAsACorridor() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "76" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        let scene = try XCTUnwrap(coord.boardScene)
        let wall = try XCTUnwrap(coord.boardState.doors.map(\.coord).min())
        XCTAssertTrue(coord.boardState.isLockedDoor(wall))
        coord.showLocksAndPlates()
        XCTAssertTrue(scene.lockedHexes.isEmpty, "no padlock on a wall")
        XCTAssertEqual(scene.overlayImageName(at: wall)?.contains("breakable-wall"), true)
        coord.explainHex(at: wall)
        XCTAssertEqual(coord.explanation?.title.hasPrefix("Wall"), true)

        coord.sufferDamage(999, to: try XCTUnwrap(coord.boardState.piece(at: wall)), killer: .character(gm.game.characters[0].id))
        XCTAssertEqual(scene.overlayImageName(at: wall), BoardScene.corridorOverBrokenWall)
        coord.explainHex(at: wall)
        XCTAssertEqual(coord.explanation?.title, "Corridor")
        // Drawn again from nothing (a save loaded, a turn undone), it is still a corridor.
        scene.buildBoard(from: coord.boardState, scenario: try XCTUnwrap(coord.scenarioData), offsetCol: coord.offsetCol, offsetRow: coord.offsetRow)
        XCTAssertEqual(scene.overlayImageName(at: wall), BoardScene.corridorOverBrokenWall)
        let standing = try XCTUnwrap(coord.standingWalls.min())
        XCTAssertEqual(scene.overlayImageName(at: standing)?.contains("breakable-wall"), true)
    }

    /// "Characters can target and attack the walls like any regular enemy, but character summons
    /// will not attack walls unless directly controlled by a character."
    func testACharacterAttacksAWallAndASummonLeavesItAlone() throws {
        let sim = try simulator()
        let coord = sim.coord
        let target = try wall(sim, from: "b1b", to: "h2a")
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let beside = try floor(sim, beside: target.hex, on: "b1b")
        stand(sim, brute, on: beside)
        XCTAssertTrue(coord.targetableEnemies(of: brute, range: 1).contains(target.piece))
        XCTAssertTrue(coord.targetableEnemies(of: brute, range: 3).contains(target.piece))
        coord.sufferDamage(1, to: target.piece, killer: brute)
        XCTAssertEqual(target.entity.health, target.entity.maxHealth - 1, "it is damaged like an enemy")
        coord.applyCondition(.poison, to: target.piece)
        XCTAssertTrue(target.entity.entityConditions.isEmpty, "a wall takes no condition")

        let foes = PlayerSideAI.hostileMonsters(board: coord.boardState, gameState: sim.gm.game, includeInvisible: false)
        XCTAssertFalse(foes.contains(target.piece), "nothing acting by itself goes for a wall")
        XCTAssertTrue(foes.allSatisfy { if case .monster = $0 { return true }; return false })
    }

    /// "When any wall is destroyed, the room or rooms on the other side are revealed and a
    /// corridor overlay tile is placed on top of the wall hex. Additionally, when any wall is
    /// destroyed, all enemies adjacent to it gain STUN."
    func testAWallBrokenDownRevealsItsRoomAndStunsTheEnemiesBesideIt() throws {
        let sim = try simulator()
        let coord = sim.coord
        let target = try wall(sim, from: "b1b", to: "h2a")
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let weaver = PieceID.character(sim.gm.game.characters[1].id)
        let beside = try floor(sim, beside: target.hex, on: "b1b")
        stand(sim, weaver, on: beside)
        XCTAssertEqual(visible(sim), ["b1b"])

        coord.sufferDamage(target.entity.health, to: target.piece, killer: brute)
        XCTAssertTrue(target.entity.dead)
        XCTAssertNil(coord.boardState.piecePositions[target.piece])
        XCTAssertTrue(visible(sim).contains("h2a"), "the room behind it is revealed")
        XCTAssertFalse(visible(sim).contains("e1b"), "and no other")
        XCTAssertEqual(coord.boardState.doors.first { $0.coord == target.hex }?.isOpen, true)
        XCTAssertFalse(coord.boardState.isStandingWall(target.hex))
        XCTAssertFalse(coord.standingWalls.contains(target.hex))
        XCTAssertNotNil(Pathfinder.findPath(board: coord.boardState, from: beside, to: target.hex, canOpenDoors: true), "a corridor now")
        XCTAssertFalse(monsters(sim).isEmpty, "its monsters with it")
        XCTAssertFalse(coord.isConditionActive(.stun, on: weaver), "the party isn't stunned")
        for piece in monsters(sim) {
            let hex = try XCTUnwrap(coord.boardState.piecePositions[piece])
            XCTAssertEqual(coord.isConditionActive(.stun, on: piece), coord.boardState.areAdjacent(hex, target.hex), "\(piece) at \(hex)")
            coord.entity(for: piece)?.entityConditions.removeAll()
        }

        // A second wall, with one monster beside it and the rest away from it.
        let all = monsters(sim)
        let next = try wall(sim, from: "h2a", to: "g2a")
        let near = try floor(sim, beside: next.hex, on: "h2a")
        let board = coord.boardState
        stand(sim, all[0], on: near)
        for piece in all.dropFirst() {
            guard let hex = board.piecePositions[piece], board.areAdjacent(hex, next.hex) else { continue }
            let away = try XCTUnwrap(board.cells.keys.sorted().first {
                board.isPassable($0) && board.cells[$0]?.overlay == nil && board.piece(at: $0) == nil && !board.areAdjacent($0, next.hex)
                    && board.cells[$0]?.tileRef.lowercased() == "h2a"
            })
            stand(sim, piece, on: away)
        }
        XCTAssertFalse(coord.isConditionActive(.stun, on: all[0]))
        coord.sufferDamage(999, to: next.piece, killer: brute)
        XCTAssertTrue(coord.isConditionActive(.stun, on: all[0]), "the enemy beside the wall is stunned")
        for piece in all.dropFirst() where board.piecePositions[piece] != nil {
            XCTAssertFalse(coord.isConditionActive(.stun, on: piece), "\(piece) stood away from it")
        }
        // Those of the room just revealed that stand beside the wall are stunned with it.
        for piece in monsters(sim) where !all.contains(piece) {
            let hex = try XCTUnwrap(board.piecePositions[piece])
            XCTAssertEqual(coord.isConditionActive(.stun, on: piece), board.areAdjacent(hex, next.hex), "\(piece) at \(hex)")
        }
    }

    /// "The room or rooms on the other side": a wall at the corner of three tiles has two rooms
    /// behind it, and both are revealed — the walls between them standing as they were.
    func testAWallAtTheCornerOfThreeTilesRevealsBothRooms() throws {
        let sim = try simulator()
        let coord = sim.coord
        let scenario = try XCTUnwrap(coord.scenarioData)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let first = try wall(sim, from: "b1b", to: "h2a")
        XCTAssertEqual(BoardBuilder.tiles(touching: first.hex, in: scenario), ["b1b", "h2a"])
        coord.sufferDamage(999, to: first.piece, killer: brute)
        XCTAssertEqual(visible(sim), ["b1b", "h2a"])

        // Of H2a's walls into G2a, one also touches B4b.
        let board = coord.boardState
        let corner = try XCTUnwrap(board.doors.first {
            !$0.isOpen && $0.childTileRef.lowercased() == "g2a" && BoardBuilder.tiles(touching: $0.coord, in: scenario) == ["b4b", "g2a", "h2a"]
        })
        let plain = try wall(sim, from: "h2a", to: "b4b")
        coord.sufferDamage(999, to: try XCTUnwrap(board.piece(at: corner.coord)), killer: brute)
        XCTAssertEqual(visible(sim), ["b1b", "h2a", "g2a", "b4b"])
        XCTAssertEqual(sim.gm.game.scenario?.revealedRooms.sorted(), [1, 3, 4, 5])
        XCTAssertTrue(board.isStandingWall(plain.hex), "the wall from H2a into the second room still stands")
        XCTAssertEqual(coord.entity(for: plain.piece)?.health, plain.entity.maxHealth)
        XCTAssertEqual(walls(sim).count, board.doors.filter { !$0.isOpen }.count, "every wall of the new rooms has its objective")
        // The corridor joins all three.
        let touched = Set(board.neighbors(of: corner.coord).filter { hex in !board.doors.contains { $0.coord == hex } }
            .compactMap { board.cells[$0]?.tileRef.lowercased() })
        XCTAssertEqual(touched, ["b4b", "g2a", "h2a"])
    }

    /// "Reveal all rooms and kill all enemies": a wall into each room is enough — the others may
    /// stand — and no room may be left unseen.
    func testTheGoalNeedsEveryRoomNotEveryWall() throws {
        let sim = try simulator()
        let coord = sim.coord
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        func killEveryone() {
            for piece in monsters(sim) { coord.sufferDamage(999, to: piece, killer: brute) }
        }
        var broken = 0
        while !coord.everyRoomIsRevealed {
            killEveryone()
            coord.checkVictoryDefeat(turnEnded: true)
            XCTAssertNil(coord.pendingResult, "a room is still unseen")
            let shown = visible(sim)
            // (The last room, A3a, holds no one: leave a room with monsters for the end.)
            let next = try XCTUnwrap(coord.boardState.doors.filter { !$0.isOpen && !shown.contains($0.childTileRef.lowercased()) }
                .min { ($0.childTileRef.lowercased() == "e1b" ? 1 : 0, $0.coord) < ($1.childTileRef.lowercased() == "e1b" ? 1 : 0, $1.coord) })
            coord.sufferDamage(999, to: try XCTUnwrap(coord.boardState.piece(at: next.coord)), killer: brute)
            broken += 1
            XCTAssertLessThan(broken, 10)
        }
        XCTAssertEqual(visible(sim).count, 7)
        XCTAssertEqual(ScenarioBrief.make(for: try XCTUnwrap(sim.gm.game.scenario).data, labels: sim.gm.editionStore).goal,
                       "Reveal all rooms and kill all enemies.")
        XCTAssertFalse(walls(sim).isEmpty, "walls are left standing")
        XCTAssertFalse(monsters(sim).isEmpty)
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertNil(coord.pendingResult, "enemies are left")
        killEveryone()
        coord.checkVictoryDefeat(turnEnded: true)
        XCTAssertEqual(coord.pendingResult, .victory)
    }

    /// The whole map: 23 walls, each with an objective while it stands.
    func testTheHiveHasTwentyThreeWalls() throws {
        let sim = try simulator()
        let coord = sim.coord
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        var seen: Set<HexCoord> = []
        for _ in 0..<30 {
            seen.formUnion(coord.boardState.doors.map(\.coord))
            // (A wall seen from the far side of its connector is on the map all the same.)
            for door in coord.boardState.doors {
                XCTAssertEqual(coord.boardState.cells[door.coord]?.overlay, .door, "the wall at \(door.coord) has no hex")
            }
            guard let piece = walls(sim).first else { break }
            coord.sufferDamage(999, to: piece, killer: brute)
        }
        XCTAssertEqual(seen.count, 23)
        XCTAssertTrue(coord.boardState.doors.allSatisfy { $0.isOpen })
        XCTAssertTrue(coord.boardState.doors.allSatisfy { $0.subType == BoardBuilder.breakableWallSubType })
        XCTAssertTrue(coord.standingWalls.isEmpty)
    }
}

/// "Each character discards three ability cards at the start of the scenario as a scenario
/// effect" (`ScenarioPlacements.discardAtStart`, `BoardCoordinator+StartDiscard`): the Harrower
/// Hive (#76).
@MainActor
final class StartDiscardTests: XCTestCase {

    private func simulator(_ index: String = "76", asking: Bool) throws -> ScenarioSimulator {
        try ScenarioSimulator(scenario: index, options: .init(characters: ["brute", "spellweaver"], seed: 1, autoResolvePrompts: !asking))
    }

    /// Each character is asked in turn, before anyone chooses cards for the first round, and
    /// must name exactly three cards of their hand.
    func testEachCharacterChoosesThreeCardsToDiscardBeforeTheFirstRound() throws {
        let sim = try simulator(asking: true)
        let coord = sim.coord
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let bruteHand = brute.handCards, weaverHand = weaver.handCards
        XCTAssertEqual(coord.pendingStartDiscard?.characterID, brute.id)
        XCTAssertEqual(coord.pendingStartDiscard?.count, 3)
        XCTAssertNil(coord.cardSelectingCharacterID, "no one chooses cards yet")
        XCTAssertEqual(coord.startDiscardOwed(by: weaver), 3)

        // Too few, a card twice, a card that isn't in the hand: none is an answer.
        coord.resolveStartDiscard(Array(bruteHand.prefix(2)))
        coord.resolveStartDiscard([bruteHand[0], bruteHand[0], bruteHand[1]])
        coord.resolveStartDiscard([bruteHand[0], bruteHand[1], -7])
        coord.resolveStartDiscard(Array(bruteHand.prefix(4)))
        XCTAssertEqual(coord.pendingStartDiscard?.characterID, brute.id)
        XCTAssertEqual(brute.handCards, bruteHand)
        XCTAssertTrue(brute.discardedCards.isEmpty)

        let chosen = [bruteHand[1], bruteHand[4], bruteHand[0]]
        coord.resolveStartDiscard(chosen)
        XCTAssertEqual(brute.discardedCards, chosen, "discarded, not lost")
        XCTAssertTrue(brute.lostCards.isEmpty)
        XCTAssertEqual(brute.handCards, bruteHand.filter { !chosen.contains($0) })
        XCTAssertEqual(coord.pendingStartDiscard?.characterID, weaver.id, "then the next character")
        XCTAssertNil(coord.cardSelectingCharacterID)

        coord.resolveStartDiscard(Array(weaverHand.suffix(3)))
        XCTAssertNil(coord.pendingStartDiscard)
        XCTAssertEqual(weaver.handCards.count, weaverHand.count - 3)
        XCTAssertEqual(weaver.discardedCards.count, 3)
        XCTAssertNotNil(coord.cardSelectingCharacterID, "and then the first round's cards are chosen")
        XCTAssertTrue(sim.gm.game.characters.allSatisfy { coord.startDiscardOwed(by: $0) == 0 }, "no one is asked twice")
    }

    /// Played without prompts the cards go all the same; and the whole scenario plays on from there.
    func testWithoutPromptsTheCardsAreDiscardedAllTheSame() throws {
        let sim = try simulator(asking: false)
        for character in sim.gm.game.characters {
            XCTAssertEqual(character.discardedCards.count, 3, character.name)
            XCTAssertTrue(character.lostCards.isEmpty)
        }
        XCTAssertNil(sim.coord.pendingStartDiscard)
        XCTAssertNotNil(sim.coord.cardSelectingCharacterID)
    }

    /// Only at the start, and only where the scenario says so.
    func testNothingIsDiscardedLaterOrElsewhere() throws {
        let sim = try simulator(asking: false)
        let character = sim.gm.game.characters[0]
        sim.gm.game.round = 1
        character.handCards += character.discardedCards
        character.discardedCards = []
        XCTAssertEqual(sim.coord.startDiscardOwed(by: character), 0, "the first round has begun")
        sim.gm.game.round = 0
        XCTAssertEqual(sim.coord.startDiscardOwed(by: character), 3)
        character.exhausted = true
        XCTAssertEqual(sim.coord.startDiscardOwed(by: character), 0)

        let other = try simulator("1", asking: true)
        XCTAssertNil(other.coord.pendingStartDiscard)
        XCTAssertTrue(other.gm.game.characters.allSatisfy { $0.discardedCards.isEmpty })
        XCTAssertNotNil(other.coord.cardSelectingCharacterID)
    }

    /// A party playing the scenario through its policies answers the prompt and plays on.
    func testAPolicyPartyDiscardsAndPlays() async throws {
        let sim = try ScenarioSimulator(scenario: "76", options: .init(characters: ["brute", "spellweaver"], seed: 3))
        let hands = sim.gm.game.characters.map(\.handCards.count)
        XCTAssertNotNil(sim.coord.pendingStartDiscard)
        await sim.play(rounds: 1)
        XCTAssertNil(sim.coord.pendingStartDiscard)
        for (character, hand) in zip(sim.gm.game.characters, hands) {
            let held = character.handCards.count + character.discardedCards.count + character.lostCards.count + character.activeCards.count
            XCTAssertGreaterThanOrEqual(character.discardedCards.count + character.lostCards.count + character.activeCards.count, 3, character.name)
            XCTAssertEqual(held, hand, "no card has gone anywhere else")
        }
        XCTAssertTrue(sim.violations.isEmpty, "\(sim.violations)")
    }
}
