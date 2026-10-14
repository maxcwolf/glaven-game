import Foundation

/// A random dungeon on the board (rulebook pp. 50–51; `RandomDungeon`, `docs/random-dungeons.md`).
extension BoardCoordinator {
    /// The room card of the random dungeon room a tile belongs to.
    func dungeonRoomCard(ofTile ref: String) -> DungeonRoomCard? {
        guard let scenario = gameManager?.game.scenario, let dungeon = scenario.randomDungeon else { return nil }
        let edition = scenario.data.edition
        return dungeon.allRooms.lazy.compactMap { DungeonCardStore.shared.room(named: $0.room.room, edition: edition) }
            .first { card in card.tiles.contains { $0.ref.lowercased() == ref.lowercased() } }
    }

    /// RD-3: a room with two exits may be left by either; as one is opened the other is closed
    /// off — its door taken away and its half-hex a wall again — so the dungeon is three rooms
    /// whichever way the party goes, and "every door open" means the last room is reached.
    func closeOffOtherExits(besides door: DoorInfo) {
        guard let from = door.fromTileRef, let card = dungeonRoomCard(ofTile: from) else { return }
        let tiles = Set(card.tiles.map { $0.ref.lowercased() })
        let others = boardState.doors.filter { other in
            !other.isOpen && other.coord != door.coord && tiles.contains(other.fromTileRef?.lowercased() ?? "")
        }
        for other in others {
            boardState.doors.removeAll { $0.coord == other.coord }
            boardState.cells[other.coord] = nil
            boardScene?.removeOverlaySprite(at: other.coord, offsetCol: offsetCol, offsetRow: offsetRow)
            log("The other way out is closed off", category: .setup)
        }
    }
}

extension BoardCoordinator {
    /// RD-7: a random dungeon's treasure tile holds what its monster card prints, never anything
    /// of the campaign. `id` is `rnd-<monster card>-<number>`. Returns what was found, to log.
    func lootDungeonTreasure(_ id: String, by character: GameCharacter) -> String? {
        let parts = id.split(separator: "-").map(String.init)
        guard parts.count == 3, let scenario = gameManager?.game.scenario, let store = gameManager?.editionStore,
              let card = ScenarioManager.dungeonMonsterCards(edition: scenario.data.edition, editionStore: store)
                .first(where: { $0.index == parts[1] }),
              let treasure = card.overlays?.first(where: { $0.type == "treasure" && $0.marker?.stringValue == parts[2] })
        else { return nil }
        let values = treasure.values ?? []
        let number = values.first.flatMap { Int($0.stringValue) } ?? 0
        let me = PieceID.character(character.id)
        let enemies = boardState.piecePositions.keys.sorted().filter { piece in
            if case .monster = piece { return areEnemies(piece, me) }
            return false
        }
        switch treasure.value {
        case "gold":
            character.loot += number
            return "\(number) gold"
        case "heal":
            let healed = heal(me, amount: number, source: me)
            return "heals \(healed)"
        case "cureConditions":
            character.entityConditions.removeAll { $0.name.isNegative && !$0.permanent }
            syncPieceVisuals()
            return "every negative condition cured"
        case "recoverLost":
            if character.lostCards.count <= 1 || autoResolvePrompts {
                recover(Array(character.lostCards.suffix(1)), for: character, fromLost: true)
            } else {
                pendingRecovery = PendingRecovery(characterID: character.id, count: 1, itemName: "Treasure", fromLost: true)
            }
            return "a lost card recovered"
        case "refreshItem":
            let count = number
            let options = refreshableItems(of: character, excluding: "", consumedSmallOnly: true)
            if options.count <= count || autoResolvePrompts {
                refreshItems(options.prefix(count).map(\.itemKey), for: character)
            } else {
                pendingItemRefresh = PendingItemRefresh(characterID: character.id, count: count,
                                                        options: options.map(\.itemKey), itemName: "Treasure")
            }
            return "\(count) small items refreshed"
        case "enemiesDamage":
            for enemy in enemies { _ = sufferDamage(number, to: enemy, killer: me) }
            return "every enemy suffers \(number) damage"
        case "enemiesCondition":
            let condition = values.first.flatMap { ConditionName(rawValue: $0.stringValue) }
            if let condition { for enemy in enemies { applyCondition(condition, to: enemy, by: me) } }
            return "every enemy gains \(condition.map(GameText.conditionName) ?? "a condition")"
        default:
            return nil
        }
    }
}

extension BoardCoordinator {
    /// RD-6: the penalty of the room just revealed behind `door`, at the difficulty chosen.
    func applyDungeonPenalty(behind door: DoorInfo) {
        guard let scenario = gameManager?.game.scenario, let dungeon = scenario.randomDungeon,
              let card = dungeonRoomCard(ofTile: door.childTileRef),
              let entry = dungeon.allRooms.first(where: { $0.room.room == card.name }),
              let penalty = (dungeon.penalties ?? .suggested).penalty(of: card.name, depth: entry.path.count + 1)
        else { return }
        let opener: String? = {
            if case .character(let id) = actingPiece { return id }
            return nil
        }()
        log("\(card.name): \(entry.path.count + 1 == 2 && (dungeon.penalties ?? .suggested) == .suggested ? card.minor : card.major)",
            category: .setup)
        let previous = entry.path.isEmpty ? nil : dungeon.room(at: Array(entry.path.dropLast()))
        apply(penalty, opener: opener, room: cells(ofRoom: card), previous: previous)
        syncPieceVisuals()
    }

    /// The board's hexes of a dungeon room.
    func cells(ofRoom card: DungeonRoomCard) -> Set<HexCoord> {
        let tiles = Set(card.tiles.map { $0.ref.lowercased() })
        return Set(boardState.cells.values.filter { tiles.contains($0.tileRef.lowercased()) }.map(\.coord))
    }

    private func apply(_ penalty: DungeonPenalty, opener: String?, room: Set<HexCoord> = [], previous: RandomDungeon.Room? = nil) {
        guard let game = gameManager?.game else { return }
        let party = game.characters.filter { !$0.absent && !$0.exhausted }
        func targets(_ who: DungeonPenalty.Who) -> [GameCharacter] {
            switch who {
            case .everyone: return party
            case .opener: return party.filter { $0.id == opener }.isEmpty ? Array(party.prefix(1)) : party.filter { $0.id == opener }
            }
        }
        let enemies = boardState.piecePositions.keys.sorted().filter { piece in
            if case .monster = piece { return !isPlayerSide(piece) }
            return false
        }
        switch penalty {
        case .both(let first, let second):
            apply(first, opener: opener, room: room, previous: previous)
            apply(second, opener: opener, room: room, previous: previous)
        case .upgradeNormalInRoom:
            let normals = enemies.filter { boardState.piecePositions[$0].map(room.contains) == true && !boardState.eliteStandees.contains($0) }
            guard let first = normals.first else { break }
            guard normals.count > 1, !autoResolvePrompts else { makeElite(first); break }
            Task { @MainActor in
                let chosen = await chooseFigure(normals, title: "The room's penalty",
                                                question: "Which normal enemy becomes elite?") ?? first
                makeElite(chosen)
                syncPieceVisuals()
            }
        case .replaceInPreviousRoom(let elite, let count):
            if let previous { replaceEnemies(of: previous, elite: elite, count: count) }
        case .conditions(let conditions, let who, let permanent):
            for character in targets(who) {
                for condition in conditions {
                    applyCondition(condition, to: .character(character.id))
                    if permanent, let index = character.entityConditions.lastIndex(where: { $0.name == condition }) {
                        character.entityConditions[index].permanent = true
                    }
                }
            }
        case .curses(let times):
            for character in party {
                for _ in 0..<times where game.hasSpecialCardLeft(.curse, forMonsterDeck: false) {
                    character.attackModifierDeck.addCard(type: .curse)
                }
            }
        case .damage(let amount, let who):
            for character in targets(who) { _ = sufferOwnDamage(amount, characterID: character.id, source: "The room's penalty") }
        case .monsterBlessings(let count):
            for _ in 0..<count where game.hasSpecialCardLeft(.bless, forMonsterDeck: true) {
                game.monsterAttackModifierDeck.addCard(type: .bless)
            }
        case .elementsInert:
            for index in game.elementBoard.indices { game.elementBoard[index].state = .inert }
        case .enemyStrengthen(permanent: false):
            for enemy in enemies { applyCondition(.strengthen, to: enemy) }
        case .eliteInvisible:
            for enemy in enemies where boardState.eliteStandees.contains(enemy) { applyCondition(.invisible, to: enemy) }
        case .enemyStrengthen(permanent: true):
            for enemy in enemies {
                applyCondition(.strengthen, to: enemy)
                if case .monster(let name, let standee) = enemy, let entity = monsterEntity(name: name, standee: standee),
                   let index = entity.entityConditions.lastIndex(where: { $0.name == .strengthen }) {
                    entity.entityConditions[index].permanent = true
                }
            }
        case .enemyShield(let amount, let permanent):
            addDungeonEffect(ScenarioPlacements.Effect(on: "monsters", shield: String(amount), round: permanent ? nil : game.round))
        case .enemyAttack(let amount):
            addDungeonEffect(ScenarioPlacements.Effect(on: "monsters", attack: amount))
        case .enemyRetaliate(let amount, let range, let permanent):
            addDungeonEffect(ScenarioPlacements.Effect(on: "monsters", round: permanent ? nil : game.round,
                                                       retaliate: amount, retaliateRange: range))
        case .loseCards(let count, let who):
            owePenaltyCards(count, by: targets(who), lose: true, penalty: "The room's penalty.")
        case .discardCards(let count, let who):
            owePenaltyCards(count, by: targets(who), lose: false, penalty: "The room's penalty.")
        case .spendAllSpendable:
            for character in party { useUp(character, spend: true, consume: false) }
        case .consumeAndSpendAll:
            for character in party { useUp(character, spend: true, consume: true) }
        case .consumeSmallItem:
            for character in party { consumeOneSmallItem(of: character) }
        case .noConsuming:
            addDungeonEffect(ScenarioPlacements.Effect(on: "party", noConsuming: true))
        case .enemyHealEachTurn(let amount):
            addDungeonEffect(ScenarioPlacements.Effect(on: "monsters", healEachTurn: amount))
        case .enemyMoveAndRange(let amount):
            addDungeonEffect(ScenarioPlacements.Effect(on: "monsters", move: amount, range: amount))
        default:
            // Lasting penalties and those the players choose for are still to come
            // (docs/random-dungeons.md).
            log("This penalty isn't played yet", category: .setup)
        }
    }
}

extension BoardCoordinator {
    /// A lasting penalty, kept on the scenario (and in the save) as a standing effect.
    func addDungeonEffect(_ effect: ScenarioPlacements.Effect) {
        gameManager?.game.scenario?.dungeonEffects.append(effect)
    }

    /// A standing effect's heal at the start of each turn (Passage's major penalty).
    func healAtTurnStart(_ pieceID: PieceID) {
        let amount = scenarioEffects(on: pieceID).reduce(0) { $0 + ($1.healEachTurn ?? 0) }
        guard amount > 0 else { return }
        let healed = heal(pieceID, amount: amount, source: pieceID)
        if healed > 0 { log("\(name(pieceID)) heals \(healed)", category: .heal) }
    }

    /// Items a penalty uses up: every unused spendable one spent (`spend`), every unused
    /// consumable one consumed (`consume`).
    func useUp(_ character: GameCharacter, spend: Bool, consume: Bool) {
        var used: [String] = []
        for key in character.carriedItems where !character.spentItems.contains(key) && !character.consumedItems.contains(key) {
            guard let item = itemData(key) else { continue }
            if spend && item.spent { character.spentItems.insert(key); used.append(item.name) }
            if consume && item.consumed { character.consumedItems.insert(key); used.append(item.name) }
        }
        if !used.isEmpty { log("\(characterName(character.id)) uses up \(GameText.list(used))", category: .info) }
    }

    /// Hallway's minor penalty: one small item consumed, the player's choice of those still
    /// ready (headless, the first).
    func consumeOneSmallItem(of character: GameCharacter) {
        let ready = character.carriedItems.filter { key in
            !character.consumedItems.contains(key) && itemData(key)?.slot == .small
        }
        guard !ready.isEmpty else { return }
        func consume(_ key: String) {
            character.consumedItems.insert(key)
            log("\(characterName(character.id)) consumes \(itemData(key)?.name ?? key)", category: .info)
        }
        guard ready.count > 1, !autoResolvePrompts else { consume(ready[0]); return }
        Task { @MainActor in
            let names = ready.map { itemData($0)?.name ?? $0 }
            let choice = await chooseOption(names, title: characterName(character.id),
                                            question: "The room's penalty: which small item do you consume?") ?? 0
            consume(ready[min(max(0, choice), ready.count - 1)])
        }
    }

    /// A normal monster made elite where it stands, keeping the damage it has taken.
    func makeElite(_ piece: PieceID) {
        guard case .monster(let name, let standee) = piece, let game = gameManager?.game,
              let monster = game.monsters.first(where: { $0.name == name }),
              let entity = monsterEntity(name: name, standee: standee), let stat = monster.stat(for: .elite) else { return }
        let health = evaluateEntityValue(stat.health ?? .int(0), level: monster.level, characterCount: game.characterCount)
        let taken = entity.maxHealth - entity.health
        entity.type = .elite
        entity.maxHealth = health
        entity.health = max(1, health - taken)
        entity.immunities = stat.immunities ?? []
        boardState.eliteStandees.insert(piece)
        log("\(self.name(piece)) becomes elite", category: .setup)
    }

    /// Road's and Encampment's major penalty: enemies of the room left behind set up again — the
    /// monster card's first such ones (for this many characters) whose number is clear.
    func replaceEnemies(of room: RandomDungeon.Room, elite: Bool, count: Int) {
        guard let scenario = gameManager?.game.scenario, let store = gameManager?.editionStore,
              let card = DungeonCardStore.shared.room(named: room.room, edition: scenario.data.edition),
              let monsterCard = ScenarioManager.dungeonMonsterCards(edition: scenario.data.edition, editionStore: store)
                .first(where: { $0.index == room.monsters }) else { return }
        let characters = gameManager?.game.characterCount ?? 2
        let placements = BoardBuilder.findPlacements(in: scenarioData?.mapTileData ?? VGBMapTileData(ref: "", doors: [], overlays: [], monsters: [], turns: 0))
        var placed = 0
        for entry in monsterCard.rooms?.first?.monster ?? [] where placed < count {
            guard entry.monsterType(forPlayerCount: characters) == (elite ? .elite : .normal),
                  let marker = entry.marker, let place = card.numbers[marker],
                  let tile = placements.first(where: { $0.tile.ref.lowercased() == place.tile.lowercased() }) else { continue }
            let hex = RandomDungeonMap.global(place.x, place.y, turns: tile.tile.turns, axis: tile.axis)
            guard boardState.piece(at: hex) == nil else { continue }
            if spawnMonster(name: entry.name, type: elite ? .elite : .normal, at: hex, origin: .spawned) != nil { placed += 1 }
        }
    }
}
