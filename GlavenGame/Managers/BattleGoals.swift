import Foundation

/// A battle goal as the player reads it.
struct BattleGoal: Equatable, Identifiable {
    let id: String
    let name: String
    let text: String
    let checks: Int
}

/// Dealing battle goals (GH p.15): before each scenario every character is dealt two from the
/// shuffled deck and keeps one, which pays its checkmarks on a success.
extension ScenarioManager {

    func battleGoal(_ cardId: String) -> BattleGoal? {
        let edition = game.edition ?? "gh"
        guard let data = editionStore.battleGoals(for: edition).first(where: { $0.cardId == cardId }) else { return nil }
        let text = editionStore.resolveLabel(key: "battleGoals.\(cardId).text", edition: edition) ?? ""
        return BattleGoal(id: cardId, name: data.name, text: text, checks: data.checks)
    }

    /// Deal two goals to each character in the party, none shared.
    func dealBattleGoals() {
        // Goals already dealt for this scenario stand (they're cleared when it ends): quitting
        // while choosing and setting out again mustn't deal a fresh pair.
        let held = Set(game.characters.flatMap(\.battleGoalCardIds))
        var deck = editionStore.battleGoals(for: game.edition ?? "gh").map(\.cardId)
            .filter { !held.contains($0) }
            .shuffled(using: &GameRandom.shared)
        for character in game.characters where !character.absent && character.battleGoalCardIds.isEmpty {
            character.battleGoalCardIds = Array(deck.prefix(2))
            character.selectedBattleGoal = nil
            deck.removeFirst(min(2, deck.count))
        }
    }

    /// Keep one of the two goals dealt.
    func chooseBattleGoal(_ index: Int, for character: GameCharacter) {
        guard index >= 0, index < character.battleGoalCardIds.count else { return }
        character.selectedBattleGoal = index
    }

    /// The goal a character kept, if any.
    func chosenBattleGoal(of character: GameCharacter) -> BattleGoal? {
        guard let index = character.selectedBattleGoal, index < character.battleGoalCardIds.count else { return nil }
        return battleGoal(character.battleGoalCardIds[index])
    }

    /// Whether everyone in the party has kept a goal.
    var battleGoalsChosen: Bool {
        game.characters.filter { !$0.absent }.allSatisfy { $0.selectedBattleGoal != nil }
    }
}
