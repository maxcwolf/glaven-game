import Foundation

/// The scenario's goal and loss conditions as the scenario book prints them
/// (`ScenarioPlacements.Goal`, written into `ScenarioMaps/placements/gh.json`): what the party
/// must destroy, kill, loot, reach or escape through, and what loses it.
extension BoardCoordinator {

    /// The written goal of the scenario on the board.
    var scenarioGoal: ScenarioPlacements.Goal? { scenarioData?.placements?.goal }

    /// The tag on an escort that reached where it was going: off the board, alive and counted.
    static let arrivedTag = "arrived"

    // MARK: - Lookups

    /// The objectives of the scenario's objective `index` (1-based) in play.
    private func objectiveEntities(_ index: Int) -> [GameObjectiveEntity] {
        gameManager?.game.objectives.filter { $0.objectiveIndex == index }.flatMap(\.entities) ?? []
    }

    /// The characters taking part in the scenario.
    private var party: [GameCharacter] { gameManager?.game.characters.filter { !$0.absent } ?? [] }

    /// Every hex of a letter on the whole map, revealed or not.
    private func allHexes(lettered marker: String) -> [HexCoord] {
        guard let scenarioData else { return [] }
        return BoardBuilder.markerSites(marker, in: scenarioData).map(\.coord)
    }

    /// The exit hexes on the board as it stands.
    func exitHexes(_ exit: ScenarioPlacements.Exit) -> Set<HexCoord> {
        var hexes: Set<HexCoord> = []
        if let marker = exit.marker { hexes.formUnion(boardState.markerHexes[marker] ?? []) }
        if let tile = exit.tile?.lowercased() {
            hexes.formUnion(boardState.cells.values.filter { $0.tileRef.lowercased() == tile && $0.passable }.map(\.coord))
        }
        if exit.start == true { hexes.formUnion(boardState.startingLocations) }
        return hexes
    }

    /// The letters of the pressure plates in play for this many characters.
    func platesInPlay(_ plates: ScenarioPlacements.Plates) -> [String] {
        plates.markers + (plates.more?[String(min(4, max(2, party.count)))] ?? [])
    }

    /// The id the map data gives a treasure tile that is the scenario's goal.
    static let goalTreasureID = "goal"

    /// Whether every treasure tile with this id on the map has been looted: each tile that holds
    /// one is revealed and none is left on the board.
    func treasureIsLooted(_ id: String) -> Bool {
        guard let scenarioData else { return false }
        let tiles = Set(BoardBuilder.findPlacements(in: scenarioData.mapTileData).filter { placement in
            placement.tile.overlays.contains { $0.ref.type == "treasure" && $0.ref.id == id }
        }.map { $0.tile.ref.lowercased() })
        let revealed = Set(boardState.visibleRooms.map { $0.lowercased() })
        return !tiles.isEmpty && tiles.isSubset(of: revealed)
            && !boardState.cells.values.contains { $0.overlay == .treasure && $0.treasureID == id }
    }

    /// Whether every goal treasure tile on the map has been looted.
    private var goalTreasureIsLooted: Bool { treasureIsLooted(Self.goalTreasureID) }

    // MARK: - Things that happen toward the goal

    /// An escort ended its turn where the scenario sends it (Hail beside the altar, a villager
    /// on the docks): it leaves the board, safe, and counts toward the goal.
    func noteEscortArrival(_ pieceID: PieceID) {
        guard let arrival = scenarioGoal?.arrive, let container = objectiveContainer(of: pieceID),
              container.objectiveIndex == arrival.objective, let entity = entity(for: pieceID) as? GameObjectiveEntity,
              let hex = boardState.piecePositions[pieceID], let lettered = boardState.markerHexes[arrival.marker],
              lettered.contains(hex) || (arrival.adjacent == true && lettered.contains { $0.distance(to: hex) == 1 })
        else { return }
        let who = name(pieceID)
        entity.off = true
        entity.tags.append(Self.arrivedTag)
        removePieceFromBoard(pieceID)
        boardState.objectiveSites[entity.number] = nil
        let arrived = objectiveEntities(arrival.objective).filter { $0.tags.contains(Self.arrivedTag) }.count
        log(arrival.count > 1 ? "\(who) is safe (\(arrived) of \(arrival.count))" : "\(who) is there", category: .round)
        checkVictoryDefeat()
    }

    /// Whether the scenario's goal treasure can only be looted with a Loot action.
    var goalTreasureNeedsLootAction: Bool { scenarioData?.placements?.lootActionOnly == true }

    /// A character looted a goal treasure tile.
    func noteGoalTreasureLooted(by characterID: String) {
        if !boardState.goalLooters.contains(characterID) { boardState.goalLooters.append(characterID) }
        updateItemBars()
    }

    /// Whether a character may loot a goal treasure tile: where every character must loot one,
    /// each loots only one.
    func mayLootGoalTreasure(_ characterID: String) -> Bool {
        scenarioGoal?.loot != "each" || !boardState.goalLooters.contains(characterID)
    }

    /// As a round ends, where characters leave through the exit one by one: those standing on an
    /// exit hex leave the scenario and take no further part in it.
    func letCharactersLeave() {
        guard let exit = scenarioGoal?.escape, exit.leave == true else { return }
        let exits = exitHexes(exit)
        for character in party where !character.exhausted {
            guard let hex = boardState.piecePositions[.character(character.id)], exits.contains(hex) else { continue }
            boardState.escapedCharacters.append(character.id)
            log("\(characterName(character.id)) escapes", category: .round)
            leaveScenario(character)
        }
    }

    /// Whether everyone has left through the exit (which, with everyone gone, is a win).
    var everyoneEscaped: Bool {
        // Someone exhausted on the way (where that doesn't lose the scenario) isn't waited for.
        guard scenarioGoal?.escape?.leave == true, party.contains(where: { boardState.escapedCharacters.contains($0.id) })
        else { return false }
        return party.allSatisfy { boardState.escapedCharacters.contains($0.id) || $0.exhausted }
    }

    /// A character is exhausted at `hex`: the reason that loses the scenario, if it does.
    func exhaustionLoss(of character: GameCharacter, at hex: HexCoord?) -> String? {
        guard let goal = scenarioGoal, let ways = goal.lostIfExhausted, !boardState.escapedCharacters.contains(character.id)
        else { return nil }
        if let tile = goal.lostIfExhaustedOnceRevealed?.lowercased(),
           !boardState.visibleRooms.contains(where: { $0.lowercased() == tile }) { return nil }
        let who = characterName(character.id)
        if ways.contains("any") { return "\(who) is exhausted." }
        if ways.contains("beforeLoot") {
            let done = goal.loot == "each" ? boardState.goalLooters.contains(character.id) : goalTreasureIsLooted
            if !done { return "\(who) is exhausted before the treasure is looted." }
        }
        if ways.contains("offExit"), let exit = goal.escape {
            let onExit = hex.map(exitHexes(exit).contains) ?? false
            if !onExit { return "\(who) is exhausted away from the exit." }
        }
        return nil
    }

    // MARK: - Judging

    /// What has lost the scenario, in the brief's words, if anything has.
    func goalLost(_ goal: ScenarioPlacements.Goal) -> String? {
        for (key, limit) in (goal.lostAt ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let index = Int(key) else { continue }
            guard objectiveEntities(index).filter(\.dead).count >= limit,
                  let name = gameManager?.game.objectives.first(where: { $0.objectiveIndex == index })?.name else { continue }
            return ScenarioBrief.lossLine(name: name, limit: limit)
        }
        let kills = gameManager?.game.scenario?.killCounts ?? [:]
        for name in goal.lostIfKilled ?? [] where (kills[name] ?? 0) > 0 {
            return "A \(monsterTypeName(name)) is killed."
        }
        return nil
    }

    /// Whether everything the goal asks for holds right now. Where characters must stand is
    /// judged only as a turn ends (`turnEnded`).
    func goalMet(_ goal: ScenarioPlacements.Goal, turnEnded: Bool = true) -> Bool {
        guard let game = gameManager?.game, let scenario = game.scenario else { return false }
        let allRoomsRevealed = boardState.doors.allSatisfy(\.isOpen)
        let hostile = game.monsters.filter { !MonsterAI.isAllyFaction($0) && goal.spare?.contains($0.name) != true }

        for index in goal.destroy ?? [] {
            let all = objectiveEntities(index)
            guard !all.isEmpty, all.allSatisfy(\.dead), allRoomsRevealed else { return false }
        }
        for name in goal.kill ?? [] {
            // Every room of the map the scenario puts one in must be revealed, so none is still
            // to come.
            let rooms = (scenario.data.rooms ?? []).filter { room in
                room.ref != nil && (room.monster ?? []).contains { MonsterNameSpec($0.name).name == name }
            }
            guard rooms.allSatisfy({ scenario.revealedRooms.contains($0.roomNumber) }),
                  let monster = game.monsters.first(where: { $0.name == name }),
                  !monster.entities.isEmpty, monster.aliveEntities.isEmpty else { return false }
        }
        if let wanted = goal.killCount {
            let characters = max(2, party.count)
            guard let needed = ScenarioExpression.integerValue(wanted.count, variables: ["C": characters, "L": game.level])
            else { return false }
            let counted = wanted.of ?? hostile.map(\.name)
            guard counted.reduce(0, { $0 + (scenario.killCounts[$1] ?? 0) }) >= needed else { return false }
        }
        switch goal.enemies ?? (goal.spare != nil ? "all" : nil) {
        case "all":
            guard hostile.contains(where: { !$0.entities.isEmpty }), allRoomsRevealed,
                  hostile.allSatisfy({ $0.off || $0.aliveEntities.isEmpty }) else { return false }
        case "revealed":
            guard hostile.contains(where: { !$0.entities.isEmpty }),
                  hostile.allSatisfy({ $0.off || $0.aliveEntities.isEmpty }) else { return false }
        default: break
        }
        if let tiles = goal.reveal {
            let revealed = Set(boardState.visibleRooms.map { $0.lowercased() })
            for tile in tiles {
                guard tile == "*" ? allRoomsRevealed : revealed.contains(tile.lowercased()) else { return false }
            }
        }
        switch goal.loot {
        case "goal": guard goalTreasureIsLooted else { return false }
        case "each": guard !party.isEmpty, party.allSatisfy({ boardState.goalLooters.contains($0.id) }) else { return false }
        default: break
        }
        for id in goal.lootIDs ?? [] {
            guard treasureIsLooted(id) else { return false }
        }
        if let arrival = goal.arrive {
            guard objectiveEntities(arrival.objective).filter({ $0.tags.contains(Self.arrivedTag) }).count >= arrival.count
            else { return false }
        }

        if let alternatives = goal.either {
            guard alternatives.contains(where: { goalMet($0, turnEnded: turnEnded) }) else { return false }
        }

        guard goal.escape != nil || goal.occupy != nil || goal.reach != nil else { return true }
        guard turnEnded else { return false }
        let standing = party.filter { !$0.exhausted }.compactMap { boardState.piecePositions[.character($0.id)] }
        if let exit = goal.escape {
            if exit.leave == true {
                guard everyoneEscaped else { return false }
            } else {
                let exits = exitHexes(exit)
                guard !standing.isEmpty, standing.allSatisfy(exits.contains) else { return false }
            }
        }
        if let plates = goal.occupy {
            let hexes = platesInPlay(plates).flatMap(allHexes(lettered:))
            guard !hexes.isEmpty, hexes.allSatisfy(standing.contains) else { return false }
        }
        if let reach = goal.reach {
            let hexes = allHexes(lettered: reach.marker).filter { boardState.cells[$0] != nil }
            guard standing.contains(where: { at in
                hexes.contains(at) || (reach.adjacent == true && hexes.contains { $0.distance(to: at) == 1 })
            }) else { return false }
        }
        return true
    }

    // MARK: - What rules ask of the board

    /// Whether something a rule waits for has happened (`ScenarioRule.when`).
    func boardFactHolds(_ fact: BoardFact) -> Bool {
        if let saved = fact.saved {
            let arrived = (gameManager?.game.figures ?? []).reduce(0) { count, figure in
                guard case .objective(let container) = figure else { return count }
                return count + container.entities.filter { $0.tags.contains(Self.arrivedTag) }.count
            }
            guard arrived >= saved else { return false }
        }
        if let lock = fact.lock, !boardState.releasedLocks.contains(lock) { return false }
        if let room = fact.unrevealed, gameManager?.game.scenario?.revealedRooms.contains(room) != false { return false }
        if let looted = fact.looted {
            if looted == Self.goalTreasureID {
                guard treasureIsLooted(looted) else { return false }
            } else if Int(looted) != nil {
                guard treasureIsLooted(looted) else { return false }
            } else {
                // The goal treasure of one map tile.
                let tile = looted.lowercased()
                guard boardState.visibleRooms.contains(where: { $0.lowercased() == tile }),
                      !boardState.cells.values.contains(where: {
                          $0.tileRef.lowercased() == tile && $0.overlay == .treasure && $0.treasureID == Self.goalTreasureID
                      }) else { return false }
            }
        }
        return true
    }

    /// The piece of a figure in the game.
    func pieceID(of entity: any Entity) -> PieceID? {
        if let character = entity as? GameCharacter { return .character(character.id) }
        if let summon = entity as? GameSummon { return .summon(id: summon.id) }
        if let objective = entity as? GameObjectiveEntity { return .objective(id: objective.number) }
        if let standee = entity as? GameMonsterEntity,
           let monster = gameManager?.game.monsters.first(where: { $0.entities.contains { $0 === standee } }) {
            return .monster(name: monster.name, standee: standee.number)
        }
        return nil
    }

    /// Whether a figure stands where a rule's identifier asks: on a map tile, or within range of
    /// a lettered hex or an objective.
    func stands(_ entity: any Entity, where identifier: ScenarioFigureRuleIdentifier) -> Bool {
        guard let piece = pieceID(of: entity), let hex = boardState.piecePositions[piece] else { return false }
        if let tile = identifier.tile, boardState.cells[hex]?.tileRef.lowercased() != tile.lowercased() { return false }
        if let near = identifier.near {
            var places = near.marker.flatMap { boardState.markerHexes[$0] } ?? []
            if let objective = near.objective {
                places += boardState.piecePositions.compactMap { id, place in
                    guard case .objective = id, objectiveContainer(of: id)?.name == objective,
                          (self.entity(for: id) as? GameObjectiveEntity)?.dead == false else { return nil }
                    return place
                }
            }
            guard places.contains(where: { $0.distance(to: hex) <= near.range }) else { return false }
        }
        return true
    }
}
