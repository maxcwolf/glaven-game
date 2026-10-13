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
    func forgoTargets(for characterID: String) -> [PieceID] {
        guard let rules = scenarioData?.placements?.forgo, !rules.isEmpty,
              let here = boardState.piecePositions[.character(characterID)] else { return [] }
        return boardState.neighbors(of: here).compactMap { boardState.piece(at: $0) }.filter { piece in
            guard let index = objectiveContainer(of: piece)?.objectiveIndex else { return false }
            return rules.contains { $0.objective == index }
        }.sorted()
    }

    /// How many of an objective have been freed.
    func freedCount(_ objective: Int) -> Int {
        objectiveEntities(objective).filter { $0.tags.contains(Self.freedTag) }.count
    }

    /// The captive leaves the map, safe: it is no longer there to be killed, and whoever the
    /// scenario says grows stronger for it does (Redthorn: +1 Attack for each captive freed).
    func free(_ piece: PieceID, by characterID: String) {
        guard let container = objectiveContainer(of: piece), let index = container.objectiveIndex,
              let rule = scenarioData?.placements?.forgo?.first(where: { $0.objective == index }),
              let entity = entity(for: piece) as? GameObjectiveEntity, isOnBoard(piece) else { return }
        gameManager?.characterManager.onBeforeMutate?()
        let who = name(piece)
        entity.off = true
        entity.tags.append(Self.freedTag)
        removePieceFromBoard(piece)
        boardState.objectiveSites[entity.number] = nil
        log("\(characterName(characterID)) gives up an action to free \(who) (\(freedCount(index)) freed)", category: .round)
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
