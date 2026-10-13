import Foundation

// MARK: - Giving up an action for something the scenario offers

/// "A character adjacent to a captive Orchid may forgo an action (discarding one card instead)
/// to free that captive, which is removed from the map immediately" (Tribal Assault): the
/// scenario's `forgo`. Offered beside the basic action, for a half none of whose abilities has
/// been performed; the card is discarded as after a basic action.
extension BoardCoordinator {

    static let freedTag = "freed"

    /// What `characterID` could free now by giving up an action: the objectives beside them
    /// that the scenario lets a character free.
    /// `bottomAction`: the action that would be given up is a bottom one (a pump is cleansed
    /// only for a bottom action).
    func forgoTargets(for characterID: String, bottomAction: Bool) -> [PieceID] {
        guard scenarioData?.placements?.forgo?.isEmpty == false,
              let here = boardState.piecePositions[.character(characterID)] else { return [] }
        return boardState.neighbors(of: here).compactMap { boardState.piece(at: $0) }.filter { piece in
            guard let rule = forgoRule(for: piece), isOnBoard(piece) else { return false }
            return rule.bottom != true || bottomAction
        }.sorted()
    }

    /// The rule that lets an action be given up for `piece`.
    func forgoRule(for piece: PieceID) -> ScenarioPlacements.Forgo? {
        guard let index = objectiveContainer(of: piece)?.objectiveIndex else { return nil }
        return scenarioData?.placements?.forgo?.first { $0.objective == index }
    }

    /// The goal treasure tiles beside `characterID` that they could loot now by giving up an
    /// action: where the scenario offers that, and the character may still loot one.
    func forgoLootHexes(for characterID: String, bottomAction: Bool) -> [HexCoord] {
        guard let rule = scenarioData?.placements?.forgo?.first(where: { $0.treasure == true }),
              rule.bottom != true || bottomAction, mayLootGoalTreasure(characterID),
              let here = boardState.piecePositions[.character(characterID)] else { return [] }
        return boardState.neighbors(of: here).filter { hex in
            boardState.cells[hex]?.overlay == .treasure && boardState.cells[hex]?.treasureID == Self.goalTreasureID
        }.sorted()
    }

    /// The treasure tile beside the character is looted for the action given up, as a Loot
    /// action would loot it.
    func lootForAnActionGivenUp(_ hex: HexCoord, by characterID: String) {
        log("\(characterName(characterID)) gives up an action to loot the treasure beside them", category: .loot)
        lootHexes(for: .character(characterID), coords: [hex], byLootAction: true)
    }

    /// How many of an objective have been freed.
    func freedCount(_ objective: Int) -> Int {
        objectiveEntities(objective).filter { $0.tags.contains(Self.freedTag) }.count
    }

    /// The captive leaves the map, safe: it is no longer there to be killed, and whoever the
    /// scenario says grows stronger for it does (Redthorn: +1 Attack for each captive freed).
    func free(_ piece: PieceID, by characterID: String) {
        guard let container = objectiveContainer(of: piece), let index = container.objectiveIndex,
              let rule = forgoRule(for: piece),
              let entity = entity(for: piece) as? GameObjectiveEntity, isOnBoard(piece) else { return }
        gameManager?.characterManager.onBeforeMutate?()
        let who = name(piece)
        entity.off = true
        entity.tags.append(Self.freedTag)
        removePieceFromBoard(piece)
        boardState.objectiveSites[entity.number] = nil
        log("\(characterName(characterID)) gives up an action to \(rule.verb) \(who) (\(freedCount(index)) \(rule.verb)d)", category: .round)
        if let stronger = rule.strengthens,
           let ally = gameManager?.game.objectives.first(where: { $0.objectiveIndex == stronger }),
           let attack = ally.escortActions.firstIndex(where: { $0.type == .attack }) {
            ally.escortActions[attack].value = .int((ally.escortActions[attack].value?.intValue ?? 0) + 1)
            log("\(ally.title.isEmpty ? ally.name : ally.title) now attacks for \(ally.escortAttack)", category: .round)
        }
        gameManager?.scenarioRulesManager.evaluateRules()
        checkVictoryDefeat()
    }
}
