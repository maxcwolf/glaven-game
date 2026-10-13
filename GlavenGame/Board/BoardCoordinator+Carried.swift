import Foundation

// MARK: - Things that are carried

/// A thing one character holds through a scenario (`ScenarioPlacements.carried`): the doll of
/// the Well of the Unfortunate, the Lurker King's claw. Someone holds it or it lies on a hex;
/// it passes to a character who performs a Loot action with the holder (or the hex it lies on)
/// in the loot's range, is picked up like a treasure tile where it lies, and is left in the hex
/// of a holder who is exhausted.
extension BoardCoordinator {

    var carriedThings: [ScenarioPlacements.Carried] { scenarioData?.placements?.carried ?? [] }

    /// The character holding `name`, if anyone is.
    func holder(of name: String) -> GameCharacter? {
        boardState.carriedBy[name].flatMap { id in gameManager?.game.characters.first { $0.id == id } }
    }

    /// What `characterID` holds.
    func carried(by characterID: String) -> [ScenarioPlacements.Carried] {
        carriedThings.filter { boardState.carriedBy[$0.name] == characterID }
    }

    /// What the holder's Moves gain or lose for what they carry (the claw: −2).
    func carriedMoveBonus(of pieceID: PieceID) -> Int {
        guard case .character(let id) = pieceID else { return 0 }
        return carried(by: id).reduce(0) { $0 + ($1.move ?? 0) }
    }

    // MARK: Who holds it first

    static func carriedTitle(_ name: String) -> String { "The \(name)" }

    /// As the scenario starts: a thing the players give to one of them is asked for (with no
    /// one to ask, the first character holds it).
    func assignCarriedAtSetup() {
        let party = (gameManager?.game.characters ?? []).filter { !$0.absent && !$0.exhausted && isOnBoard(.character($0.id)) }
        for thing in carriedThings where thing.start == "choose" && boardState.carriedBy[thing.name] == nil
            && boardState.carriedLying[thing.name] == nil {
            guard let first = party.first else { continue }
            if autoResolvePrompts {
                give(thing.name, to: first.id, how: "holds")
            } else {
                let generation = boardGeneration
                Task { @MainActor in
                    let chosen = await self.chooseFigure(party.map { PieceID.character($0.id) }, title: Self.carriedTitle(thing.name),
                                                         question: "Who holds the \(thing.name)?")
                    guard self.isCurrentBoard(generation), self.boardState.carriedBy[thing.name] == nil else { return }
                    if case .character(let id)? = chosen { self.give(thing.name, to: id, how: "holds") }
                }
            }
        }
    }

    /// `name` is now `characterID`'s.
    func give(_ name: String, to characterID: String, how: String) {
        gameManager?.characterManager.onBeforeMutate?()
        boardState.carriedLying[name] = nil
        boardState.carriedBy[name] = characterID
        log("\(characterName(characterID)) \(how) the \(name)", category: .loot)
        syncCarriedSprites()
        checkVictoryDefeat()
    }

    // MARK: Changing hands

    /// A monster has died where it stood: what it drops instead of a money token lies there.
    /// True when it dropped something.
    func dropCarried(byDeathOf monsterName: String, at hex: HexCoord) -> Bool {
        let dropped = carriedThings.filter { $0.droppedBy == monsterName && boardState.carriedBy[$0.name] == nil
            && boardState.carriedLying[$0.name] == nil }
        for thing in dropped {
            boardState.carriedLying[thing.name] = hex
            log("The \(thing.name) drops", category: .loot, trace: "at \(hex)")
        }
        if !dropped.isEmpty { syncCarriedSprites() }
        return !dropped.isEmpty
    }

    /// A holder is exhausted: what they held lies in the hex they occupied.
    func dropCarried(of character: GameCharacter) {
        let held = carried(by: character.id)
        guard !held.isEmpty else { return }
        for thing in held {
            boardState.carriedBy[thing.name] = nil
            if let hex = boardState.piecePositions[.character(character.id)] {
                boardState.carriedLying[thing.name] = hex
                log("\(characterName(character.id)) drops the \(thing.name)", category: .loot, trace: "at \(hex)")
            }
        }
        syncCarriedSprites()
    }

    /// The carried things a loot of `coords` by `characterID` takes: what lies on them, and — for
    /// a Loot action — what a holder standing on them holds.
    func carriedTaken(by characterID: String, lootingHexes coords: [HexCoord], byLootAction: Bool) -> [String] {
        let hexes = Set(coords)
        return carriedThings.map(\.name).filter { name in
            if let lying = boardState.carriedLying[name] { return hexes.contains(lying) }
            guard byLootAction, let holder = boardState.carriedBy[name], holder != characterID,
                  let at = boardState.piecePositions[.character(holder)] else { return false }
            return hexes.contains(at)
        }
    }

    /// Whether a Loot of `range` by `pieceID` would take a carried thing: one lying in range and
    /// sight, or one held by another character there.
    func carriedInLootRange(of pieceID: PieceID, range: Int) -> [HexCoord] {
        guard case .character(let id) = pieceID, let pos = boardState.piecePositions[pieceID] else { return [] }
        let places = carriedThings.compactMap { thing -> HexCoord? in
            if let lying = boardState.carriedLying[thing.name] { return lying }
            guard let holder = boardState.carriedBy[thing.name], holder != id else { return nil }
            return boardState.piecePositions[.character(holder)]
        }
        return places.filter { hex in
            boardState.isWithin(range, from: pos, to: hex) && (hex == pos || LineOfSight.hasLOS(from: pos, to: hex, board: boardState))
        }
    }

    /// Show what lies on the board.
    func syncCarriedSprites() {
        boardScene?.showCarried(boardState.carriedLying, offsetCol: offsetCol, offsetRow: offsetRow)
    }
}
