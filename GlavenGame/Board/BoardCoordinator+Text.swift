import Foundation

/// The board's headings, in the words the HUD shows. Kept out of the view so tests can check
/// them for every phase.
extension BoardCoordinator {

    /// The name of a figure in turn order: "Brute", "Bandit Guard".
    func figureName(_ figure: AnyFigure) -> String {
        switch figure {
        case .character(let character): return characterName(character.id)
        case .monster(let monster): return monsterTypeName(monster.name)
        case .objective(let objective): return objective.name.isEmpty ? "Objective" : objective.name
        }
    }

    /// The figure whose turn it is, during play.
    var currentTurnEntry: TurnOrderEntry? {
        guard boardPhase == .execution, turnOrder.indices.contains(currentTurnIndex) else { return nil }
        return turnOrder[currentTurnIndex]
    }

    /// The HUD's main heading: what is happening on the board right now.
    var phaseTitle: String {
        switch boardPhase {
        case .setup: return "Place Your Characters"
        case .cardSelection: return "Choose Cards"
        case .execution:
            guard let entry = currentTurnEntry else { return "Round in Progress" }
            return "\(figureName(entry.figure))\u{2019}s Turn \u{00B7} \(Int(entry.initiative.rounded(.up)))"
        case .roomReveal: return "New Room Revealed"
        case .scenarioEnd: return scenarioResult == .defeat ? "Scenario Failed" : "Scenario Complete"
        }
    }

    /// The round to show in the HUD, or nil before the first round. During card selection this is
    /// the round the cards are being chosen for (the game's round counter moves on when play starts).
    var displayedRound: Int? {
        guard let round = gameManager?.game.round else { return nil }
        switch boardPhase {
        case .setup: return nil
        case .cardSelection: return round + 1
        case .execution, .roomReveal, .scenarioEnd: return max(round, 1)
        }
    }
}
