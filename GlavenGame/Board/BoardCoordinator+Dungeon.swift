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
