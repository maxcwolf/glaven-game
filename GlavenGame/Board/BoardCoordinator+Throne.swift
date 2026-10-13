import Foundation

/// An objective that is a boss's hit points and jumps about the map (`ScenarioPlacements.Throne`):
/// the altar of the Infernal Throne and the Prime Demon.
extension BoardCoordinator {

    var scenarioThrone: ScenarioPlacements.Throne? { scenarioData?.placements?.throne }

    /// The altar, while it stands on the board.
    func throneAltar() -> (piece: PieceID, hex: HexCoord, entity: any Entity)? {
        guard let throne = scenarioThrone,
              let number = boardState.objectiveSites.filter({ $0.value.objective == throne.objective }).keys.sorted().first,
              let hex = boardState.piecePositions[.objective(id: number)], let entity = entity(for: .objective(id: number)) else { return nil }
        return (.objective(id: number), hex, entity)
    }

    /// The boss, while it stands on the board.
    func throneBoss() -> (piece: PieceID, entity: any Entity)? {
        guard let throne = scenarioThrone,
              let piece = boardState.piecePositions.keys.sorted().first(where: { if case .monster(throne.boss, _) = $0 { return true }; return false }),
              let entity = entity(for: piece) else { return nil }
        return (piece, entity)
    }

    /// The altar has the boss's hit points from the moment both are on the board.
    func shareThroneHealth() {
        guard let altar = throneAltar(), let boss = throneBoss(), altar.entity.maxHealth != boss.entity.maxHealth else { return }
        altar.entity.maxHealth = boss.entity.maxHealth
        altar.entity.health = boss.entity.health
    }

    /// The altar has just been damaged: the boss has what it has left, and falls with it.
    func shareThroneDamage(with damaged: PieceID, killer: PieceID?) {
        guard let altar = throneAltar(), altar.piece == damaged, let boss = throneBoss() else { return }
        boss.entity.health = max(0, altar.entity.health)
        boardScene?.refreshStatus(of: boss.piece)
        if boss.entity.health <= 0 {
            log("\(name(boss.piece)) falls with the altar", category: .death)
            handleDeath(of: boss.piece, killer: killer)
        }
    }

    /// The tiles on either side of a door.
    private func sides(of door: DoorInfo) -> Set<String> {
        var sides: Set<String> = [door.childTileRef.lowercased()]
        if let from = (door.fromTileRef ?? boardState.cells[door.coord]?.tileRef)?.lowercased() { sides.insert(from) }
        return sides
    }

    private func isOnTheMap(_ tile: String) -> Bool {
        let doors = Set(boardState.doors.map(\.coord))
        return boardState.cells.values.contains { $0.tileRef.lowercased() == tile && !doors.contains($0.coord) }
    }

    /// "If the altar moves into an unrevealed room, that room is immediately revealed, opening
    /// all doors between it and other revealed rooms."
    private func reveal(tile: String) {
        for _ in 0..<4 {
            guard let door = boardState.doors.first(where: { door in
                !door.isOpen && sides(of: door).contains(tile) && sides(of: door).subtracting([tile]).allSatisfy(isOnTheMap)
            }) else { return }
            openDoor(at: door.coord)
        }
    }

    /// The boss's special: the altar jumps to the next hex of its cycle — whoever or whatever is
    /// there goes to the nearest empty hex — and summons the demon of that place.
    @MainActor func throneMoves(special index: Int) async {
        guard let throne = scenarioThrone, let altar = throneAltar(), let placements = scenarioData?.placements else { return }
        let generation = boardGeneration
        // Where it stands in its cycle (it starts on one of the letters; off them all, before the first).
        let here = throne.cycle.firstIndex { (boardState.markerHexes[$0] ?? []).contains(altar.hex) }
        let letter = throne.cycle[((here ?? -1) + 1) % throne.cycle.count]
        if boardState.markerHexes[letter]?.isEmpty ?? true,
           let tile = placements.tiles.first(where: { $0.value.markers?[letter] != nil })?.key.lowercased() {
            log("The altar\u{2019}s next place is out of sight: its room is revealed", category: .door)
            reveal(tile: tile)
            guard isCurrentBoard(generation), scenarioResult == nil else { return }
        }
        guard let destination = boardState.markerHexes[letter]?.sorted().first, let altarNow = throneAltar() else {
            log("The altar finds no hex (\(letter)) to jump to", category: .info)
            return
        }
        // Who stands there makes room.
        if let figure = boardState.piece(at: destination), figure != altarNow.piece, let free = nearestEmptyHex(to: destination) {
            log("\(name(figure)) is moved aside [to \(free)]", category: .move)
            await animateMove(figure, along: [destination, free], as: .teleport)
            guard isCurrentBoard(generation), isOnBoard(figure) else { return }
            boardState.movePiece(figure, to: free)
        }
        // The altar and its stone go together.
        let from = altarNow.hex
        let stone = boardState.cells[from]
        log("The altar jumps to (\(letter))", category: .move, trace: "to \(destination)")
        await animateMove(altarNow.piece, along: [from, destination], as: .teleport)
        guard isCurrentBoard(generation), boardState.piecePositions[altarNow.piece] != nil else { return }
        if stone?.overlay == .obstacle {
            boardState.removeObstacle(at: from)
            boardScene?.removeOverlaySprite(at: from, offsetCol: offsetCol, offsetRow: offsetRow)
        }
        boardState.movePiece(altarNow.piece, to: destination)
        if stone?.overlay == .obstacle, boardState.cells[destination]?.overlay == nil {
            boardState.cells[destination]?.overlay = .obstacle
            boardState.cells[destination]?.overlaySubType = stone?.overlaySubType
            boardState.cells[destination]?.overlayImageName = stone?.overlayImageName
            boardState.cells[destination]?.passable = false
            if let art = stone?.overlayImageName ?? stone?.overlaySubType.map({ "obstacle-\($0)" }) {
                boardScene?.addOverlaySprite(imageName: art, at: destination, offsetCol: offsetCol, offsetRow: offsetRow)
            }
        }
        if case .objective(let number) = altarNow.piece, let site = boardState.objectiveSites[number] {
            boardState.objectiveSites[number] = ObjectiveSlot(objective: site.objective, coord: destination, cells: [destination])
        }
        syncPieceVisuals()
        // "The altar then summons one … demon. The type depends on the location."
        guard let demon = throne.summons[letter], let gameManager else { return }
        let elite = gameManager.game.characterCount >= throne.eliteFrom[min(max(0, index), throne.eliteFrom.count - 1)]
        if let summoned = spawnMonster(name: demon, type: elite ? .elite : .normal, at: destination, origin: .summoned) {
            log("The altar summons \(name(summoned))", category: .info)
        } else {
            log("The altar has no \(GameText.monsterName(demon)) left to summon", category: .info)
        }
    }
}
