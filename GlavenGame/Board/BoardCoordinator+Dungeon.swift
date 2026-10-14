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
