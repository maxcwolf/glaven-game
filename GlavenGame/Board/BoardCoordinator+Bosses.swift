import Foundation

/// Bosses that go from one marked place to the next (`ScenarioPlacements.Cycle`): the Gloom jumps
/// between three hexes, the Dark Rider appears on six in turn and is gone after every melee
/// attack, the Bandit Commander jumps to each locked door and opens it.
extension BoardCoordinator {

    func cycle(of monsterName: String) -> ScenarioPlacements.Cycle? {
        scenarioData?.placements?.cycles?[monsterName]
    }

    /// Whether a monster type is kept off the map between its appearances.
    func comesAndGoes(_ monsterName: String) -> Bool {
        cycle(of: monsterName)?.appears == true
    }

    /// The next hex of a monster's cycle — the closest unoccupied one if another figure stands
    /// there — moving the cycle on. Letters not on the revealed map are passed over.
    func takeNextCycleHex(for pieceID: PieceID) -> HexCoord? {
        guard case .monster(let name, _) = pieceID, let letters = cycle(of: name)?.letters, !letters.isEmpty else { return nil }
        let step = boardState.cycleSteps[name, default: 0]
        for offset in 0..<letters.count {
            guard let hex = boardState.markerHexes[letters[(step + offset) % letters.count]]?.first else { continue }
            boardState.cycleSteps[name] = step + offset + 1
            if boardState.piecePositions[pieceID] == hex || isEmptyHex(hex) { return hex }
            return nearestEmptyHex(to: hex)
        }
        return nil
    }

    /// Put a figure straight onto a hex, however far away.
    @MainActor private func jump(_ pieceID: PieceID, to hex: HexCoord) async {
        guard let from = boardState.piecePositions[pieceID], from != hex else { return }
        let generation = boardGeneration
        await animateMove(pieceID, along: [from, hex], as: .teleport)
        guard isCurrentBoard(generation), isOnBoard(pieceID) else { return }
        boardState.movePiece(pieceID, to: hex)
        syncPieceVisuals()
    }

    /// The Gloom's jump: to the next marked hex of its cycle.
    @MainActor func jumpAlongCycle(_ pieceID: PieceID) async {
        guard let hex = takeNextCycleHex(for: pieceID) else { return }
        log("\(name(pieceID)) jumps across the room", category: .move, trace: "to \(hex)")
        await jump(pieceID, to: hex)
    }

    /// The Bandit Commander's jump: into the doorway of the next locked door in order, which
    /// opens and reveals its room. Returns false where the scenario has no such cycle.
    @MainActor func jumpToNextDoor(_ pieceID: PieceID) async -> Bool {
        guard case .monster(let name, _) = pieceID, cycle(of: name)?.doors == true, !scenarioLocks.isEmpty else { return false }
        let step = boardState.cycleSteps[name, default: 0]
        boardState.cycleSteps[name] = step + 1
        let index = step % scenarioLocks.count
        guard let door = boardState.doors.first(where: { lockIndex(for: $0) == index }) else { return true }
        log("\(self.name(pieceID)) jumps to a door", category: .move, trace: "at \(door.coord)")
        if !door.isOpen { openDoor(at: door.coord) }
        guard isOnBoard(pieceID) else { return true }
        // The room it reveals may have put a figure in the doorway.
        let free = boardState.piecePositions[pieceID] == door.coord || !boardState.isOccupied(door.coord)
        if let hex = free ? door.coord : nearestEmptyHex(to: door.coord) { await jump(pieceID, to: hex) }
        return true
    }

    /// A monster that comes and goes, off the map as its turn starts, appears on its next hex.
    /// Returns whether it is on the map.
    @discardableResult
    func appearIfOffMap(_ pieceID: PieceID) -> Bool {
        if isOnBoard(pieceID) { return true }
        guard case .monster(let name, let standee) = pieceID, comesAndGoes(name),
              let entity = monsterEntity(name: name, standee: standee), !entity.dead,
              let hex = takeNextCycleHex(for: pieceID) else { return false }
        boardState.placePiece(pieceID, at: hex)
        if entity.type == .elite { boardState.eliteStandees.insert(pieceID) }
        boardScene?.addPieceSprite(id: pieceID, at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.play(.summon)
        syncPieceVisuals()
        log("\(self.name(pieceID)) appears", category: .setup, trace: "at \(hex)")
        return true
    }

    /// Such a monster is gone again right after any melee attack it makes.
    func leaveAfterMeleeAttack(_ pieceID: PieceID) {
        guard case .monster(let name, _) = pieceID, cycle(of: name)?.leavesAfterMelee == true, isOnBoard(pieceID),
              entity(for: pieceID)?.health ?? 0 > 0 else { return }
        log("\(self.name(pieceID)) vanishes", category: .move)
        removePieceFromBoard(pieceID)
    }
}
