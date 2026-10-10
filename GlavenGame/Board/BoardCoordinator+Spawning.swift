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
        // A room's monsters arrive with its door; one spawned or summoned later announces itself.
        if origin != .placed { boardScene?.play(.summon) }

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

// MARK: - Objectives and spawn markers

extension BoardCoordinator {

    /// Objectives in play that have no piece on the board yet, lowest number first.
    func unplacedObjectiveEntities() -> [(GameObjectiveContainer, GameObjectiveEntity)] {
        guard let game = gameManager?.game else { return [] }
        return game.objectives.flatMap { container in container.entities.map { (container, $0) } }
            .filter { !$0.1.dead && !$0.1.off && boardState.piecePositions[.objective(id: $0.1.number)] == nil }
            .sorted { $0.1.number < $1.1.number }
    }

    /// Stand each objective that isn't on the board yet on a place written for it in the revealed
    /// tiles (`ScenarioPlacements`). One with no place written stays off the board. Returns the
    /// pieces placed.
    @discardableResult
    func placeRevealedObjectives() -> [PieceID] {
        var placed: [PieceID] = []
        for (container, entity) in unplacedObjectiveEntities() {
            guard let index = container.objectiveIndex,
                  let slotIndex = boardState.openObjectiveSlots.firstIndex(where: { $0.objective == index }) else { continue }
            var slot = boardState.openObjectiveSlots[slotIndex]
            let piece = PieceID.objective(id: entity.number)
            // An escort whose hex is taken stands beside it; a thing on the map waits for its own.
            if boardState.isOccupied(slot.coord) {
                guard container.escort, let beside = nearestEmptyHex(to: slot.coord) else { continue }
                slot = ObjectiveSlot(objective: index, coord: beside, cells: [beside])
            }
            boardState.openObjectiveSlots.remove(at: slotIndex)
            boardState.placePiece(piece, at: slot.coord)
            boardState.objectiveSites[entity.number] = slot
            boardScene?.addPieceSprite(id: piece, at: slot.coord, offsetCol: offsetCol, offsetRow: offsetRow)
            placed.append(piece)
        }
        return placed
    }

    /// An objective left the board: an obstacle it was drawn as goes with it, and a door it
    /// barred opens.
    func clearObjectiveSite(_ number: Int) {
        guard let site = boardState.objectiveSites.removeValue(forKey: number) else { return }
        for hex in site.cells where boardState.cells[hex]?.overlay == .obstacle {
            boardState.removeObstacle(at: hex)
            boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        }
        if site.barsDoor, boardState.isClosedDoor(site.coord) { openDoor(at: site.coord) }
    }

    /// Whether an objective still bars the door on this hex.
    func isDoorBarred(at coord: HexCoord) -> Bool {
        boardState.objectiveSites.contains { number, site in
            site.barsDoor && site.coord == coord && boardState.piecePositions[.objective(id: number)] != nil
        }
    }

    /// Where a scenario rule's spawn at `marker` goes: the first free hex lettered with it, else
    /// (they are all taken) the first of them, the monster then standing as near as it can; or
    /// beside the objective that carries the letter (an imp at water pump "a"), or where one
    /// just destroyed stood (a corpse from grave "a"). Nil when the letter is nowhere on the
    /// revealed map.
    func spawnHex(forMarker marker: String) -> HexCoord? {
        if let hexes = boardState.markerHexes[marker], !hexes.isEmpty {
            return hexes.first(where: isEmptyHex) ?? hexes[0]
        }
        if let fallen = fallenFigure, fallen.markers.contains(marker) { return fallen.hex }
        guard let game = gameManager?.game else { return nil }
        let carriers = game.objectives.flatMap(\.entities)
            .filter { !$0.dead && ($0.marker == marker || $0.markers.contains(marker)) }
            .sorted { $0.number < $1.number }
            .compactMap { boardState.piecePositions[.objective(id: $0.number)] }
        // One for each that carries it: the next goes beside the one with the fewest already there.
        func crowd(_ hex: HexCoord) -> Int {
            hex.neighbors.filter { neighbor in
                boardState.pieces(at: neighbor).contains { if case .monster = $0 { return true }; return false }
            }.count
        }
        return carriers.enumerated().min { (crowd($0.element), $0.offset) < (crowd($1.element), $1.offset) }?.element
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
