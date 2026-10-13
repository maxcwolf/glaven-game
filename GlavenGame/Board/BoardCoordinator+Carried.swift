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
            // The one the scenario is about holds it: the character on its quest, or bearing its item.
            if let theirs = party.first(where: { thing.onlyQuest != nil && $0.personalQuest == thing.onlyQuest })
                ?? party.first(where: { character in thing.item.map { character.items.contains($0) } ?? false }) {
                give(thing.name, to: theirs.id, how: "holds")
            } else if autoResolvePrompts {
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
            if thing.passes == true, let hex = boardState.piecePositions[.character(character.id)] {
                boardState.carriedLying[thing.name] = hex
                log("\(characterName(character.id)) drops the \(thing.name)", category: .loot, trace: "at \(hex)")
            } else {
                // What doesn't change hands goes with its holder.
                boardState.carriedGone[thing.name] = "lost"
            }
        }
        syncCarriedSprites()
    }

    /// Whether a carried thing is still to be had: no one holds it, it lies nowhere and it
    /// isn't out of the scenario.
    private func isUnclaimed(_ thing: ScenarioPlacements.Carried) -> Bool {
        boardState.carriedBy[thing.name] == nil && boardState.carriedLying[thing.name] == nil && boardState.carriedGone[thing.name] == nil
    }

    /// Whether `characterID` may loot the treasure tile `id`: a tile that gives a thing only one
    /// quest's character may take (the Occult Dagger) is theirs alone, where someone is on it.
    func mayLootTreasure(_ id: String, characterID: String) -> Bool {
        guard let quest = carriedThings.first(where: { $0.treasure == id && $0.onlyQuest != nil && isUnclaimed($0) })?.onlyQuest,
              let party = gameManager?.game.characters.filter({ !$0.absent }), party.contains(where: { $0.personalQuest == quest })
        else { return true }
        return party.first { $0.id == characterID }?.personalQuest == quest
    }

    /// `characterID` has looted the treasure tile `id`: the next thing that tile gives is theirs.
    func noteTreasureLooted(_ id: String, by characterID: String) {
        guard let thing = carriedThings.first(where: { $0.treasure == id && isUnclaimed($0) }) else { return }
        give(thing.name, to: characterID, how: "now holds")
    }

    /// The Pierce what the attacker carries adds against this target (the Occult Dagger against
    /// the Harvester).
    func carriedPierce(of attacker: PieceID, against target: PieceID) -> Int {
        guard case .character(let id) = attacker, case .monster(let name, _) = target else { return 0 }
        return carried(by: id).filter { $0.against == name }.reduce(0) { $0 + ($1.pierce ?? 0) }
    }

    /// What has lost the scenario by a holder's exhaustion, in the brief's words.
    func carriedLoss() -> String? {
        carriedThings.first { $0.lostWithHolder == true && boardState.carriedGone[$0.name] == "lost" }
            .map { "The character holding the \($0.name) is exhausted." }
    }

    /// The carried things a loot of `coords` by `characterID` takes: what lies on them, and — for
    /// a Loot action — what a holder standing on them holds.
    func carriedTaken(by characterID: String, lootingHexes coords: [HexCoord], byLootAction: Bool) -> [String] {
        let hexes = Set(coords)
        return carriedThings.map(\.name).filter { name in
            if let lying = boardState.carriedLying[name] { return hexes.contains(lying) }
            guard byLootAction, carriedThings.first(where: { $0.name == name })?.passes == true,
                  let holder = boardState.carriedBy[name], holder != characterID,
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
            guard thing.passes == true, let holder = boardState.carriedBy[thing.name], holder != id else { return nil }
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

    // MARK: What only its holder harms, and its charge

    /// The carried thing without whose holder `target` takes no damage, when `source` isn't
    /// that holder (the Staff of Xorn and the Harrower Infesters).
    func carriedWard(of target: PieceID, against source: PieceID?) -> ScenarioPlacements.Carried? {
        guard case .monster(let name, _) = target,
              let thing = carriedThings.first(where: { $0.soleHarmTo?.contains(name) == true }) else { return nil }
        if case .character(let id)? = source, boardState.carriedBy[thing.name] == id { return nil }
        return thing
    }

    /// The holder of a thing has done `damage` to one of the monsters only they harm: it is
    /// charged by as much, up to its full charge.
    func chargeCarried(for target: PieceID, by source: PieceID?, damage: Int) {
        guard damage > 0, case .monster(let name, _) = target, case .character(let id)? = source,
              let thing = carriedThings.first(where: { $0.soleHarmTo?.contains(name) == true && boardState.carriedBy[$0.name] == id })
        else { return }
        let full = fullCharge(of: thing)
        let before = boardState.carriedCharge[thing.name, default: 0]
        let now = full.map { min($0, before + damage) } ?? before + damage
        guard now != before else { return }
        boardState.carriedCharge[thing.name] = now
        log("The \(thing.name) is charged: \(now)\(full.map { " of \($0)" } ?? "")", category: .info)
        if let full, now >= full { log("The \(thing.name) is fully charged", category: .round) }
    }

    /// The charge a thing holds when full, if it is one that is charged.
    func fullCharge(of thing: ScenarioPlacements.Carried) -> Int? {
        guard let formula = thing.charge, let game = gameManager?.game else { return nil }
        return evaluateEntityValue(.string(formula), level: game.level, characterCount: game.characterCount)
    }

    /// Whether `name` is fully charged.
    func isFullyCharged(_ name: String) -> Bool {
        guard let thing = carriedThings.first(where: { $0.name == name }), let full = fullCharge(of: thing) else { return true }
        return boardState.carriedCharge[name, default: 0] >= full
    }

    // MARK: Discarding it for what it does

    static let keepItTitle = "Keep It"

    /// What `characterID` could discard where they stand, each with the monster that would
    /// suffer for it and how much.
    func spendable(by characterID: String) -> [(thing: ScenarioPlacements.Carried, target: PieceID, damage: Int)] {
        guard let game = gameManager?.game, let here = boardState.piecePositions[.character(characterID)] else { return [] }
        return carried(by: characterID).compactMap { thing in
            guard let spend = thing.spend else { return nil }
            let lettered = boardState.markerHexes[spend.marker] ?? []
            guard lettered.contains(here) || (spend.adjacent == true && lettered.contains { boardState.areAdjacent($0, here) }),
                  let target = boardState.piecePositions.keys.sorted().first(where: { if case .monster(spend.to, _) = $0 { return true }; return false })
            else { return nil }
            let damage = evaluateEntityValue(.string(spend.damage), level: game.level, characterCount: game.characterCount)
            return damage > 0 ? (thing, target, damage) : nil
        }
    }

    /// A character's turn has ended: where they could discard something they carry, they are
    /// asked before the next figure acts.
    func noteCarriedSpends(after characterID: String) {
        if !spendable(by: characterID).isEmpty, !pendingSpends.contains(characterID) { pendingSpends.append(characterID) }
    }

    /// Ask each such character, thing by thing: discard it and the monster suffers, or keep it.
    @MainActor func resolveCarriedSpends() async {
        let generation = boardGeneration
        while !pendingSpends.isEmpty, isCurrentBoard(generation), scenarioResult == nil {
            let characterID = pendingSpends.removeFirst()
            for offer in spendable(by: characterID) {
                guard isOnBoard(offer.target) else { break }
                let chosen = await chooseFigure([offer.target], title: Self.carriedTitle(offer.thing.name),
                                                question: "Discard it? \(name(offer.target)) suffers \(offer.damage) damage.",
                                                declineTitle: Self.keepItTitle)
                guard isCurrentBoard(generation) else { return }
                guard chosen != nil, boardState.carriedBy[offer.thing.name] == characterID, isOnBoard(offer.target) else { continue }
                gameManager?.characterManager.onBeforeMutate?()
                boardState.carriedBy[offer.thing.name] = nil
                boardState.carriedGone[offer.thing.name] = "spent"
                log("\(characterName(characterID)) discards the \(offer.thing.name): \(name(offer.target)) suffers \(offer.damage) damage", category: .damage)
                sufferDamage(offer.damage, to: offer.target, killer: .character(characterID))
                checkVictoryDefeat()
            }
        }
    }
}
