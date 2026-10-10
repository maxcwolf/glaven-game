import Foundation

/// Locked doors (`ScenarioPlacements.Lock`): doors a scenario rule keeps shut until a pressure
/// plate is stood on, a round has passed, treasure is looted or elites are killed — and doors
/// that stay open only while a plate is held.
extension BoardCoordinator {

    /// The locks of the scenario on the board.
    var scenarioLocks: [ScenarioPlacements.Lock] { scenarioData?.placements?.locks ?? [] }

    /// Which of the scenario's locks is on a door: the one between the door's two tiles.
    func lockIndex(for door: DoorInfo) -> Int? {
        guard let from = (door.fromTileRef ?? boardState.cells[door.coord]?.tileRef)?.lowercased() else { return nil }
        let sides: Set<String> = [from, door.childTileRef.lowercased()]
        return scenarioLocks.firstIndex { Set($0.between.map { $0.lowercased() }) == sides }
    }

    /// The lock on the door at a hex, while it is locked.
    func lock(at hex: HexCoord) -> ScenarioPlacements.Lock? {
        guard boardState.isLockedDoor(hex), let door = boardState.doors.first(where: { $0.coord == hex }) else { return nil }
        return lockIndex(for: door).map { scenarioLocks[$0] }
    }

    /// Where the characters still in the scenario stand.
    private var standingCharacters: [HexCoord] {
        (gameManager?.game.characters ?? []).filter { !$0.absent && !$0.exhausted }
            .compactMap { boardState.piecePositions[.character($0.id)] }
    }

    /// The revealed hexes of the pressure plates with these letters.
    private func plateHexes(_ letters: [String]) -> [HexCoord] {
        letters.flatMap { boardState.markerHexes[$0] ?? [] }
    }

    /// Every pressure plate in play on the revealed map: those a lock or the goal names for this
    /// many characters, and any the scenario lists besides.
    var pressurePlateHexes: Set<HexCoord> {
        guard let placements = scenarioData?.placements else { return [] }
        var letters = placements.plates ?? []
        for lock in placements.locks ?? [] {
            letters += (lock.plate ?? []) + (lock.held ?? []) + (lock.allOnPlates.map(platesInPlay) ?? [])
        }
        if let plates = placements.goal?.occupy { letters += platesInPlay(plates) }
        for fact in (placements.rules ?? []).flatMap({ $0.when ?? [] }) {
            if let plates = fact.occupied { letters += platesInPlay(plates) }
        }
        return Set(plateHexes(letters))
    }

    /// Whether a lock's key has been turned. Plates are judged as a turn ends, rounds as one does.
    private func keyTurned(_ lock: ScenarioPlacements.Lock, turnEnded: Bool, roundEnded: Bool) -> Bool {
        let standing = standingCharacters
        if let letters = lock.plate {
            return turnEnded && plateHexes(letters).contains(where: standing.contains)
        }
        if let plates = lock.allOnPlates {
            let hexes = Set(plateHexes(platesInPlay(plates)))
            return turnEnded && !standing.isEmpty && standing.allSatisfy(hexes.contains)
        }
        if let round = lock.afterRound {
            let played = gameManager?.game.round ?? 0
            return played > round || (roundEnded && played >= round)
        }
        if let count = lock.looted { return boardState.goalTreasuresLooted >= count }
        if let count = lock.eliteKills { return boardState.eliteKills >= count }
        return false
    }

    /// Turn every key that can be turned and bring the doors in line: locked ones stay shut to
    /// anyone walking in, released ones open (revealing their rooms), and held ones open and shut
    /// with the plates. Call when the board changes: a room revealed, a turn or round ended, a
    /// figure moved, treasure looted, an elite killed.
    func updateLocks(turnEnded: Bool = false, roundEnded: Bool = false) {
        let locks = scenarioLocks
        guard !locks.isEmpty else { return }
        let released = boardState.releasedLocks
        for (index, lock) in locks.enumerated() where lock.held == nil && !boardState.releasedLocks.contains(index) {
            if keyTurned(lock, turnEnded: turnEnded, roundEnded: roundEnded) { boardState.releasedLocks.insert(index) }
        }

        let standing = standingCharacters
        var locked: Set<HexCoord> = []
        var opening: [HexCoord] = []
        var shutting: [HexCoord] = []
        for door in boardState.doors {
            guard let index = lockIndex(for: door) else { continue }
            let lock = locks[index]
            if let letters = lock.held {
                locked.insert(door.coord)
                let held = plateHexes(letters).contains(where: standing.contains)
                if held, !door.isOpen {
                    opening.append(door.coord)
                } else if held, boardState.shutDoors.contains(door.coord) {
                    boardState.shutDoors.remove(door.coord)
                    log("A door opens", category: .door)
                } else if !held, door.isOpen, !boardState.shutDoors.contains(door.coord) {
                    shutting.append(door.coord)
                }
            } else if boardState.releasedLocks.contains(index) {
                if !door.isOpen, lock.unlocksOnly != true { opening.append(door.coord) }
            } else if !door.isOpen {
                locked.insert(door.coord)
            }
        }
        boardState.lockedDoors = locked
        for hex in shutting { shutDoor(at: hex) }
        // Opening a door reveals a room, whose own doors are then looked at in turn.
        for hex in opening where boardState.doors.contains(where: { $0.coord == hex && !$0.isOpen }) {
            openDoor(at: hex)
        }
        showLocksAndPlates()
        // A rule may wait on a lock (the tomb's guardians, once the plate is stood on).
        if boardState.releasedLocks != released {
            gameManager?.scenarioRulesManager.evaluateRules(phase: .figureChange)
        }
    }

    /// A held door closes: whoever stands in the doorway suffers trap damage and is moved to the
    /// nearest empty hex. The room behind stays revealed.
    private func shutDoor(at hex: HexCoord) {
        boardState.shutDoors.insert(hex)
        log("A door closes", category: .door)
        for piece in boardState.pieces(at: hex).sorted() {
            let damage = gameManager?.levelManager.trap() ?? 2
            log("\(name(piece)) is caught in the doorway and suffers \(damage) damage", category: .damage)
            guard !sufferDamage(damage, to: piece), let free = nearestEmptyHex(to: hex) else { continue }
            boardState.removePiece(piece)
            boardState.placePiece(piece, at: free)
            boardScene?.finishMove(id: piece, at: free, offsetCol: offsetCol, offsetRow: offsetRow)
        }
    }

    /// Draw the padlocks and the pressure plates as they stand.
    func showLocksAndPlates() {
        boardScene?.showLocks(on: boardState.lockedDoors.filter(boardState.isClosedDoor),
                              plates: pressurePlateHexes, offsetCol: offsetCol, offsetRow: offsetRow)
    }
}
