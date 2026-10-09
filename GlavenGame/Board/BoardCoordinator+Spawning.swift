import Foundation

/// Putting monsters onto the board: room reveals, scenario spawns and monster summons all go
/// through here so the game-state entity and the board piece are always created together.
extension BoardCoordinator {

    /// How a monster came into play — decides whether it acts this round and drops loot.
    enum SpawnOrigin {
        /// Placed by scenario setup or a room reveal: drops a money token when killed.
        case placed
        /// Spawned by a scenario rule: acts as if just revealed, drops no money token (p.47).
        case spawned
        /// Summoned by another monster: doesn't act this round, drops no money token (p.31).
        case summoned
    }

    /// Create a monster entity of `rawName` (which may carry a ":+N" level modifier) and place its
    /// piece at `coord`, or at the nearest empty hex if that one is taken.
    /// Returns nil if no standee is available or there is no room.
    @discardableResult
    func spawnMonster(name rawName: String, type: MonsterType, at coord: HexCoord,
                      origin: SpawnOrigin, health: IntOrString? = nil) -> PieceID? {
        guard let gameManager else { return nil }
        let game = gameManager.game
        let spec = MonsterNameSpec(rawName)
        let edition = game.edition ?? "gh"

        if !game.monsters.contains(where: { $0.name == spec.name }) {
            gameManager.monsterManager.addMonster(name: spec.name, edition: edition)
            if let created = game.monsters.first(where: { $0.name == spec.name }) {
                created.level = spec.level(forScenarioLevel: game.level)
            }
        }
        guard let monster = game.monsters.first(where: { $0.name == spec.name }) else {
            log("A monster could not be placed", category: .info, trace: "unknown monster \(rawName)")
            return nil
        }

        guard let number = gameManager.monsterManager.availableStandeeNumbers(for: monster).first else {
            log("No \(monsterTypeName(spec.name)) standee is left, so none is placed", category: .setup)
            return nil
        }
        let destination = !boardState.isOccupied(coord) && boardState.isPassable(coord)
            ? coord
            : nearestEmptyHex(to: coord)
        guard let destination else { return nil }

        gameManager.monsterManager.addEntity(type: type, to: monster, number: number)
        guard let entity = monster.entities.last(where: { $0.number == number && !$0.dead }) else { return nil }
        if let health {
            let characterCount = max(2, game.characters.filter { !$0.absent }.count)
            let hp = evaluateEntityValue(health, level: monster.level, characterCount: characterCount)
            if hp > 0 { entity.health = hp; entity.maxHealth = hp }
        }
        switch origin {
        case .placed: entity.summonState = nil
        case .spawned: entity.summonState = .active
        case .summoned: entity.summonState = .new
        }
        monster.off = false

        let pieceID = PieceID.monster(name: monster.name, standee: number)
        boardState.placePiece(pieceID, at: destination)
        if entity.type == .elite { boardState.eliteStandees.insert(pieceID) }
        boardScene?.addPieceSprite(id: pieceID, at: destination, offsetCol: offsetCol, offsetRow: offsetRow)

        // A monster entering play during a round draws its type's ability card now and acts
        // this round as if just revealed — unless it was summoned (p.31–32, p.47).
        let midRound = isMidRound
        if midRound && !monster.abilityDrawn {
            gameManager.monsterManager.drawAbility(for: monster)
        }
        if midRound && origin != .summoned {
            pendingRevealedStandees[monster.name, default: []].insert(number)
        }
        gameManager.monsterManager.applyStatEffects(for: monster, only: [number])
        return pieceID
    }

    /// Monster Summon ability: an empty hex adjacent to the summoner, as close to an enemy as
    /// possible; fails if there is none or no standee is available (p.31).
    @discardableResult
    func summonMonster(name: String, type: MonsterType, near summoner: PieceID) -> Bool {
        guard let origin = boardState.piecePositions[summoner] else { return false }
        let enemyPositions = boardState.piecePositions.compactMap { id, coord in
            areEnemies(summoner, id) ? coord : nil
        }
        let candidates = origin.neighbors.filter { isEmptyHex($0) }
        guard let spot = candidates.min(by: { a, b in
            let da = enemyPositions.map { a.distance(to: $0) }.min() ?? Int.max
            let db = enemyPositions.map { b.distance(to: $0) }.min() ?? Int.max
            return da == db ? (a.col, a.row) < (b.col, b.row) : da < db
        }) else { return false }
        guard let pieceID = spawnMonster(name: name, type: type, at: spot, origin: .summoned) else { return false }
        log("\(self.name(summoner)) summons \(self.name(pieceID))", category: .setup)
        return true
    }

    /// An empty hex: on the map, passable, no figure, and no overlay other than corridors or
    /// open doors (GH p.13).
    func isEmptyHex(_ coord: HexCoord) -> Bool {
        guard let cell = boardState.cells[coord], cell.passable, !boardState.isOccupied(coord) else { return false }
        switch cell.overlay {
        case nil:
            return true
        case .door:
            return boardState.doors.contains { $0.coord == coord && $0.isOpen }
        default:
            return false
        }
    }

    /// Breadth-first search outward for the nearest empty hex.
    func nearestEmptyHex(to coord: HexCoord) -> HexCoord? {
        // During setup the starting hexes are kept free for the party.
        let reserved = boardPhase == .setup ? Set(boardState.startingLocations) : []
        var visited: Set<HexCoord> = [coord]
        var queue = [coord]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            if isEmptyHex(current) && !reserved.contains(current) { return current }
            for neighbor in current.neighbors where !visited.contains(neighbor) && boardState.cells[neighbor] != nil {
                visited.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return nil
    }
}

// MARK: - Character summons

extension BoardCoordinator {

    /// Summon a figure for a character, from a card or an item: it goes in an empty hex next to
    /// them (p.26), which the player picks. False when there's no room (nothing is summoned).
    @discardableResult
    func beginSummonPlacement(_ summonData: SummonDataModel, for character: GameCharacter) -> Bool {
        guard let gameManager else { return false }
        let summoner = PieceID.character(character.id)
        let who = characterName(character.id)
        let summonName = summonData.name
        guard let charPos = boardState.piecePositions[summoner] else { return false }

        let emptyNeighbors = charPos.neighbors.filter { isEmptyHex($0) }
        guard !emptyNeighbors.isEmpty else {
            log("\(who) can\u{2019}t summon \(GameText.titleCased(summonName)): no empty hex next to them", category: .info)
            return false
        }

        gameManager.characterManager.addSummon(from: summonData, for: character)
        guard let summon = character.summons.last else { return false }

        let validHexes = Set(emptyNeighbors)
        pendingSummonPlacement = PendingSummonPlacement(
            summonID: summon.id,
            characterID: character.id,
            summonName: summonName,
            validHexes: validHexes,
            remaining: max(0, (summonData.count ?? 1) - 1),
            summonData: summonData
        )
        interactionMode = .placingSummon(summonID: summon.id, characterID: character.id, validHexes: validHexes)
        boardScene?.highlightHexes(validHexes, style: .summon, offsetCol: offsetCol, offsetRow: offsetRow)
        log("\(who) summons \(GameText.titleCased(summonName)). Choose a hex next to them", category: .info)
        return true
    }
}
