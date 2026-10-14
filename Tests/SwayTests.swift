import XCTest
@testable import GlavenGameLib

/// A boss whose specials drive the party off, draw it in and turn one of them
/// (`ScenarioPlacements.Sway`, `BoardCoordinator+Sway`): the Betrayer of the Lost Temple (#79).
@MainActor
final class SwayTests: XCTestCase {

    private func simulator(_ characters: [String] = ["brute", "spellweaver"]) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "79", options: .init(characters: characters, seed: 1, autoResolvePrompts: true))
        sim.gm.game.round = 1
        for _ in 0..<10 {
            guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
            sim.coord.boardState.lockedDoors.removeAll()
            sim.coord.openDoor(at: door.coord)
        }
        // Only the Betrayer is left of the monsters.
        for piece in sim.coord.boardState.piecePositions.keys.sorted() {
            if case .monster(let name, _) = piece, name != "the-betrayer" { sim.coord.removePieceFromBoard(piece); (sim.coord.entity(for: piece) as? GameMonsterEntity)?.dead = true }
        }
        return sim
    }

    private func boss(_ sim: ScenarioSimulator) throws -> (piece: PieceID, hex: HexCoord) {
        let piece = try XCTUnwrap(sim.coord.boardState.piecePositions.keys.sorted().first { if case .monster("the-betrayer", _) = $0 { return true }; return false })
        return (piece, try XCTUnwrap(sim.coord.boardState.piecePositions[piece]))
    }

    private func stand(_ sim: ScenarioSimulator, _ piece: PieceID, on hex: HexCoord) {
        sim.coord.boardState.removePiece(piece)
        sim.coord.boardState.placePiece(piece, at: hex)
    }

    private func floor(_ sim: ScenarioSimulator, where test: (HexCoord) -> Bool) throws -> HexCoord {
        let board = sim.coord.boardState
        return try XCTUnwrap(board.cells.keys.sorted().first { board.isPassable($0) && board.cells[$0]?.overlay == nil && board.piece(at: $0) == nil && test($0) })
    }

    private func special(_ number: Int, _ sim: ScenarioSimulator) async throws {
        let betrayer = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "the-betrayer" })
        let deck = sim.gm.monsterManager.abilities(for: betrayer)
        let card = try XCTUnwrap(deck.firstIndex { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == number } })
        betrayer.abilities = [card]
        betrayer.ability = 0
        betrayer.abilityDrawn = true
        sim.gm.game.state = .next
        await MonsterTurnController(coordinator: sim.coord, gameManager: sim.gm).executeMonsterGroup(betrayer)
    }

    private func summon(for owner: GameCharacter, at hex: HexCoord, _ sim: ScenarioSimulator) -> GameSummon {
        let summon = GameSummon(uuid: GameRandom.uuid(), name: "Test Ally", number: owner.summons.count + 1, health: 8, maxHealth: 8, level: 1,
                                attack: .int(2), movement: 2, range: 0)
        summon.state = .active
        owner.summons.append(summon)
        sim.coord.boardState.placePiece(.summon(id: summon.id), at: hex)
        return summon
    }

    /// Special 1: "all characters and character summons are forced to perform 'Move 4' in
    /// initiative order such that they end the movement as far away from the Betrayer as possible."
    func testItsFirstSpecialDrivesThePartyAway() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        func far(_ hex: HexCoord?) -> Int { hex.flatMap { coord.boardState.range(from: $0, to: betrayer.hex) } ?? -1 }
        // The Brute three hexes off, the Spellweaver immobilized as far, a summon of the Brute's four off.
        let three = coord.boardState.cells.keys.sorted().filter { coord.boardState.isPassable($0) && coord.boardState.cells[$0]?.overlay == nil
            && coord.boardState.piece(at: $0) == nil && far($0) == 3 }
        XCTAssertGreaterThanOrEqual(three.count, 2)
        stand(sim, .character(brute.id), on: three[0])
        stand(sim, .character(weaver.id), on: three[three.count - 1])
        weaver.entityConditions.append(EntityCondition(name: .immobilize))
        let ally = summon(for: brute, at: try floor(sim) { far($0) == 4 }, sim)
        // What "as far as a Move 4 gets them" is, by the board's own measure.
        func farthest(_ piece: PieceID) throws -> Int {
            let here = try XCTUnwrap(coord.boardState.piecePositions[piece])
            let (enemies, allies) = coord.movementSets(for: piece)
            let reach = Pathfinder.reachableHexes(board: coord.boardState, from: here, range: 4, mode: .normal, avoidTraps: true,
                                                  canOpenDoors: false, occupiedByEnemy: enemies, occupiedByAlly: allies)
            return (reach.keys.filter { coord.boardState.piece(at: $0) == nil } + [here]).map(far).max() ?? 0
        }
        let allyBest = try farthest(.summon(id: ally.id))
        try await special(1, sim)
        XCTAssertFalse(coord.boardState.piecePositions.keys.filter { if case .monster("giant-viper", _) = $0 { return true }; return false }.isEmpty,
                       "its vipers are summoned first")
        XCTAssertEqual(far(coord.boardState.piecePositions[.summon(id: ally.id)]), allyBest, "the summon went first, as far as it could")
        XCTAssertGreaterThan(allyBest, 4)
        let bruteNow = far(coord.boardState.piecePositions[.character(brute.id)])
        XCTAssertGreaterThan(bruteNow, 3, "the Brute is driven off")
        XCTAssertLessThanOrEqual(bruteNow, 7, "by no more than a Move 4")
        XCTAssertEqual(far(coord.boardState.piecePositions[.character(weaver.id)]), 3, "immobilized, the Spellweaver stays")
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })

        // Alone on the board, from each of several places: always to the farthest hex a Move 4 reaches.
        coord.boardState.removePiece(.character(weaver.id))
        coord.boardState.removePiece(.summon(id: ally.id))
        brute.summons.removeAll()
        // (From every side of it: the lowest-numbered hex in reach is the farthest only on one.)
        for start in three {
            for piece in coord.boardState.piecePositions.keys.sorted() { if case .monster("giant-viper", _) = piece { coord.sufferDamage(999, to: piece) } }
            stand(sim, .character(brute.id), on: start)
            let best = try farthest(.character(brute.id))
            await coord.driveOff(from: betrayer.piece)
            XCTAssertEqual(far(coord.boardState.piecePositions[.character(brute.id)]), best, "from \(start)")
        }
    }

    /// Special 2: "All characters and character summons are forced to move to the closest hex
    /// adjacent to the Betrayer. The character who will play two cards latest in the turn order
    /// is mind controlled for this round", their summons with them.
    func testItsSecondSpecialDrawsThePartyInAndTurnsTheLastToAct() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        func far(_ hex: HexCoord?) -> Int { hex.flatMap { coord.boardState.range(from: $0, to: betrayer.hex) } ?? -1 }
        stand(sim, .character(brute.id), on: try floor(sim) { far($0) == 5 })
        stand(sim, .character(weaver.id), on: try floor(sim) { far($0) == 4 })
        let ally = summon(for: weaver, at: try floor(sim) { far($0) == 6 }, sim)
        // Both have two cards down; the Spellweaver's are the slower.
        for (character, initiative) in [(brute, 20), (weaver, 70)] {
            let hand = sim.hand(of: character)
            coord.selectedCardPairs[character.id] = (top: hand[0], bottom: hand[1])
            character.initiative = initiative
        }
        try await special(2, sim)
        for piece in [PieceID.character(brute.id), .character(weaver.id), .summon(id: ally.id)] {
            XCTAssertEqual(far(coord.boardState.piecePositions[piece]), 1, "\(piece) is drawn to its side")
        }
        XCTAssertEqual(coord.boardState.turned, [.character(weaver.id), .summon(id: ally.id)], "the last to play, and her summon")
        XCTAssertFalse(coord.turnLog.contains { $0.message.contains("as printed on its stat card") })

        // Her summon turns on the party; the Brute's wouldn't.
        let turn = SummonAI.computeTurn(summon: ally, ownerCharacterID: weaver.id, board: coord.boardState, gameState: sim.gm.game)
        XCTAssertEqual(turn.attackTargets, [.character(brute.id)])
        coord.boardState.turned = []
        XCTAssertTrue(SummonAI.computeTurn(summon: ally, ownerCharacterID: weaver.id, board: coord.boardState, gameState: sim.gm.game)
            .attackTargets.allSatisfy { if case .monster = $0 { return true }; return false })

        // A long rest plays no cards: with the Spellweaver resting it is the Brute who is taken.
        weaver.longRest = true
        coord.selectedCardPairs[weaver.id] = nil
        try await special(2, sim)
        XCTAssertEqual(coord.boardState.turned, [.character(brute.id)])
    }

    /// "On their turn, they will perform a 'Move 2' and then the top action of their
    /// leading-initiative card, after which both played cards are discarded even if they would
    /// normally be lost."
    func testAMindControlledCharacterTurnsOnTheParty() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let hand = sim.hand(of: brute)
        // A leading card whose top is an attack and is lost when played; any other for the second.
        func attacks(_ card: AbilityModel) -> Bool { MonsterAbility.flattened(card.actions ?? []).contains { $0.type == .attack } }
        let leading = try XCTUnwrap(hand.first { attacks($0) && ($0.lost ?? false) } ?? hand.first(where: attacks), "a Brute card with an attack on top")
        let second = try XCTUnwrap(hand.first { $0.cardId != leading.cardId })
        coord.selectedCardPairs[brute.id] = (top: leading, bottom: second)
        coord.boardState.turned = [.character(brute.id)]
        // The Spellweaver three hexes from the Brute, the Betrayer far from both.
        let start = try floor(sim) { (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 5 }
        stand(sim, .character(brute.id), on: start)
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: start) == 3
            && (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 5 })
        weaver.maxHealth = 40
        weaver.health = 40
        let lines = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        let said = coord.turnLog.dropFirst(lines).map(\.message)
        let now = try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])
        XCTAssertLessThanOrEqual(coord.boardState.range(from: start, to: now) ?? 9, 2, "Move 2")
        XCTAssertTrue(coord.boardState.areAdjacent(now, try XCTUnwrap(coord.boardState.piecePositions[.character(weaver.id)])), "toward the Spellweaver")
        XCTAssertTrue(said.contains { $0.hasPrefix("Brute attacks Spellweaver") }, "\(said)")
        XCTAssertFalse(said.contains { $0.contains("Betrayer") && $0.contains("attacks") })
        // Both cards in the discard pile, lost icon or not; neither in hand.
        for card in [leading, second] {
            let id = try XCTUnwrap(card.cardId)
            XCTAssertTrue(brute.discardedCards.contains(id), "\(card.name ?? "") is discarded")
            XCTAssertFalse(brute.handCards.contains(id))
            XCTAssertFalse(brute.lostCards.contains(id))
        }

        // Too far to reach in a Move 2: two hexes nearer, and no attack.
        coord.selectedCardPairs[brute.id] = (top: leading, bottom: second)
        let from = try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: from) == 6 })
        let quietly = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        XCTAssertEqual(coord.boardState.range(from: from, to: try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])), 2)
        XCTAssertFalse(coord.turnLog.dropFirst(quietly).contains { $0.message.hasPrefix("Brute attacks") })

        // A top with no attack: the Move, and nothing else.
        let quiet = try XCTUnwrap(hand.first { !attacks($0) && $0.cardId != leading.cardId && $0.cardId != second.cardId })
        coord.selectedCardPairs[brute.id] = (top: quiet, bottom: second)
        weaver.health = weaver.maxHealth
        let before = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        XCTAssertFalse(coord.turnLog.dropFirst(before).contains { $0.message.hasPrefix("Brute attacks") })
        XCTAssertEqual(weaver.health, weaver.maxHealth)
    }

    /// A top action of the controlled character's card, made by hand (the first card of the hand, its top replaced).
    private func controlled(_ sim: ScenarioSimulator, top actions: [ActionModel]) throws -> GameCharacter {
        let brute = sim.gm.game.characters[0]
        let hand = sim.hand(of: brute)
        var leading = try XCTUnwrap(hand.first)
        leading.actions = actions
        let second = try XCTUnwrap(hand.dropFirst().first)
        sim.coord.selectedCardPairs[brute.id] = (top: leading, bottom: second)
        sim.coord.boardState.turned = [.character(brute.id)]
        return brute
    }

    private func said(_ sim: ScenarioSimulator, since lines: Int) -> [String] { sim.coord.turnLog.dropFirst(lines).map(\.message) }

    /// "Then the top action": a Move in it takes them on toward the party, and its attack follows.
    func testAMoveOnTheTopTakesThemFurther() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = try controlled(sim, top: [ActionModel(type: .move, value: .int(3)), ActionModel(type: .attack, value: .int(2))])
        let weaver = sim.gm.game.characters[1]
        let start = try floor(sim) { (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 6 }
        stand(sim, .character(brute.id), on: start)
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: start) == 5
            && coord.boardState.steps(from: $0, to: start) == 5 })
        weaver.maxHealth = 40
        weaver.health = 40
        let lines = coord.turnLog.count
        await coord.mindControlledTurn(of: brute)
        let now = try XCTUnwrap(coord.boardState.piecePositions[.character(brute.id)])
        XCTAssertTrue(coord.boardState.areAdjacent(now, try XCTUnwrap(coord.boardState.piecePositions[.character(weaver.id)])),
                      "Move 2 and Move 3 bring them beside the Spellweaver")
        XCTAssertTrue(said(sim, since: lines).contains { $0.hasPrefix("Brute attacks Spellweaver") }, "\(said(sim, since: lines))")
    }

    /// A Heal with a range goes to the most hurt of themselves and the monsters in reach; a heal
    /// with none, to themselves.
    func testAHealOnTheTopHealsTheirNewSide() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let boss = try XCTUnwrap(coord.entity(for: betrayer.piece))
        let healRange3 = ActionModel(type: .heal, value: .int(3), subActions: [ActionModel(type: .range, value: .int(3))])
        let brute = try controlled(sim, top: [healRange3])
        let weaver = sim.gm.game.characters[1]
        stand(sim, .character(weaver.id), on: try floor(sim) { (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 8 })
        stand(sim, .character(brute.id), on: try floor(sim) { coord.boardState.range(from: $0, to: betrayer.hex) == 2
            && LineOfSight.hasLOS(from: $0, to: betrayer.hex, board: coord.boardState) })
        boss.health = boss.maxHealth - 6
        brute.health = brute.maxHealth - 1
        weaver.health = weaver.maxHealth - 6
        await coord.mindControlledTurn(of: brute)
        XCTAssertEqual(boss.health, boss.maxHealth - 3, "the Betrayer, most hurt and in reach, is healed")
        XCTAssertEqual(brute.health, brute.maxHealth - 1)
        XCTAssertEqual(weaver.health, weaver.maxHealth - 6, "never the party")

        _ = try controlled(sim, top: [ActionModel(type: .heal, value: .int(3), subActions: [ActionModel(type: .specialTarget, value: .string("self"))])])
        await coord.mindControlledTurn(of: brute)
        XCTAssertEqual(brute.health, brute.maxHealth, "Heal 3, self")
        XCTAssertEqual(boss.health, boss.maxHealth - 3)
    }

    /// A Shield or Retaliate is theirs for the round; an infusion is made; a negative condition
    /// goes on the party and a positive one on themselves; Loot takes the money in reach; a bonus
    /// that stays with its card isn't performed.
    func testTheRestOfTheTopAction() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = try controlled(sim, top: [
            ActionModel(type: .shield, value: .int(2)),
            ActionModel(type: .retaliate, value: .int(1)),
            ActionModel(type: .element, value: .string("fire")),
            ActionModel(type: .condition, value: .string("poison"), subActions: [ActionModel(type: .range, value: .int(3))]),
            ActionModel(type: .condition, value: .string("strengthen")),
            ActionModel(type: .loot, value: .int(1)),
            ActionModel(type: .card, value: .string("persistent")),
        ])
        let weaver = sim.gm.game.characters[1]
        let start = try floor(sim) { (coord.boardState.range(from: $0, to: betrayer.hex) ?? 0) >= 6 }
        stand(sim, .character(brute.id), on: start)
        stand(sim, .character(weaver.id), on: try floor(sim) { coord.boardState.range(from: $0, to: start) == 3
            && LineOfSight.hasLOS(from: $0, to: start, board: coord.boardState) })
        let money = sim.gm.game.characters[0].loot
        let retaliates = brute.retaliate.count
        let lines = coord.turnLog.count
        // Money beside every hex the Move 2 could end on.
        for hex in coord.boardState.cells.keys where (coord.boardState.range(from: hex, to: start) ?? 9) <= 2 && coord.boardState.isPassable(hex) {
            coord.boardState.placeLoot(at: hex)
        }
        await coord.mindControlledTurn(of: brute)
        XCTAssertEqual(brute.shield?.value?.intValue, 2)
        XCTAssertEqual(brute.retaliate.count, retaliates + 1)
        XCTAssertNotEqual(sim.gm.game.elementBoard.first { $0.type == .fire }?.state, .inert, "fire infused")
        XCTAssertTrue(coord.isConditionActive(.poison, on: .character(weaver.id)), "Poison on the party")
        XCTAssertFalse(coord.isConditionActive(.poison, on: .character(brute.id)))
        XCTAssertTrue(brute.entityConditions.contains { $0.name == .strengthen }, "Strengthen on themselves")
        XCTAssertGreaterThan(brute.loot, money, "money in reach looted")
        XCTAssertTrue(said(sim, since: lines).contains { $0.contains("isn\u{2019}t performed") }, "the persistent bonus is left: its card is discarded")
    }

    /// FAQ: "The bosses two abilities can affect invisible characters. They also require LOS."
    /// Who is out of its sight isn't driven off, drawn in or turned.
    func testOnlyThoseInItsSightAreMovedOrTurned() async throws {
        let sim = try simulator()
        let coord = sim.coord
        let betrayer = try boss(sim)
        let brute = sim.gm.game.characters[0], weaver = sim.gm.game.characters[1]
        let board = coord.boardState
        let hidden = try floor(sim) { !LineOfSight.hasLOS(from: betrayer.hex, to: $0, board: board) }
        let seen = try floor(sim) { $0 != hidden && LineOfSight.hasLOS(from: betrayer.hex, to: $0, board: board)
            && (board.range(from: $0, to: betrayer.hex) ?? 0) >= 3 }
        stand(sim, .character(brute.id), on: hidden)
        stand(sim, .character(weaver.id), on: seen)
        coord.applyCondition(.invisible, to: .character(weaver.id))
        await coord.driveOff(from: betrayer.piece)
        XCTAssertEqual(board.piecePositions[.character(brute.id)], hidden, "out of sight: not driven")
        XCTAssertNotEqual(board.piecePositions[.character(weaver.id)], seen, "in sight, invisible or not: driven off")

        stand(sim, .character(weaver.id), on: seen)
        let hand = sim.hand(of: brute), other = sim.hand(of: weaver)
        coord.selectedCardPairs[brute.id] = (top: hand[0], bottom: hand[1])
        coord.selectedCardPairs[weaver.id] = (top: other[0], bottom: other[1])
        brute.initiative = 99
        weaver.initiative = 10
        await coord.drawInAndTurn(by: betrayer.piece)
        XCTAssertEqual(board.piecePositions[.character(brute.id)], hidden, "out of sight: not drawn in")
        XCTAssertTrue(board.areAdjacent(try XCTUnwrap(board.piecePositions[.character(weaver.id)]), betrayer.hex))
        XCTAssertFalse(board.turned.contains(.character(brute.id)), "the last to act is out of sight")
        XCTAssertTrue(board.turned.contains(.character(weaver.id)), "the last to act of those it sees")
    }

    /// In a round of play: the Betrayer's second special takes someone still to act, their turn
    /// is played for them, and the control ends with the round.
    func testMindControlInARoundOfPlay() async throws {
        var controlled = 0
        for seed in 1...6 {
            let sim = try ScenarioSimulator(scenario: "79", options: .init(characters: ["brute", "spellweaver", "tinkerer"], seed: UInt64(seed)))
            for _ in 0..<10 {
                guard let door = sim.coord.boardState.doors.first(where: { !$0.isOpen }) else { break }
                sim.coord.boardState.lockedDoors.removeAll()
                sim.coord.openDoor(at: door.coord)
            }
            let betrayer = try XCTUnwrap(sim.gm.game.monsters.first { $0.name == "the-betrayer" })
            let deck = sim.gm.monsterManager.abilities(for: betrayer)
            let card = try XCTUnwrap(deck.firstIndex { ($0.actions ?? []).contains { $0.type == .special && $0.value?.intValue == 2 } })
            betrayer.abilities = [card, card, card]
            betrayer.ability = -1
            _ = await sim.play(rounds: 2)
            XCTAssertTrue(sim.violations.isEmpty, "seed \(seed): \(sim.violations)")
            XCTAssertTrue(sim.coord.boardState.turned.isEmpty || sim.coord.scenarioResult != nil, "seed \(seed): the control ends with the round")
            let lines = sim.transcript
            if let taken = lines.firstIndex(where: { $0.contains("takes control of") }) {
                let who = lines[taken].components(separatedBy: "takes control of ").last?.components(separatedBy: " for the round").first ?? "?"
                XCTAssertTrue(lines[taken...].contains { $0.hasPrefix("\(who) is mind controlled") }, "seed \(seed): \(who)'s turn is played for them")
                controlled += 1
            }
        }
        XCTAssertGreaterThan(controlled, 0, "someone is taken in one of these games")
    }
}
