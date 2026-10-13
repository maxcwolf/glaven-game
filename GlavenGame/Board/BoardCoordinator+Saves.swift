import Foundation

// MARK: - Sparing what the party protects

/// "Any character may lose one card from their hand to negate any one source of damage" to a
/// captive Orchid (Tribal Assault), or to the crystal, twice (Crystalline Cave): the scenario's
/// `saves`. Asked as the damage is about to be suffered; the card may come from any hand.
extension BoardCoordinator {

    /// The party's choice, pending: the objective about to suffer, and what losing a card saves.
    struct PendingSave: Identifiable {
        let id = UUID()
        let objective: PieceID
        let name: String
        let damage: Int
        let sourceDescription: String
        let health: Int
        /// How many more times this objective can be spared (nil: no limit).
        let left: Int?
        /// The characters who have a card to lose, with those cards.
        let hands: [(characterID: String, cards: [Int])]
        var continuation: CheckedContinuation<(characterID: String, cardId: Int)?, Never>?

        /// Whether the scenario is lost with this objective.
        var losesTheScenario = false

        /// Whether the damage would destroy the objective.
        var destroys: Bool { damage >= health }
        /// Whether a card is plainly worth it: without one the scenario is lost here and now.
        var isDecisive: Bool { destroys && losesTheScenario }
    }

    /// The rule that lets `piece` be spared, and how many times are left of it.
    func save(for piece: PieceID) -> (objective: Int, left: Int?)? {
        guard let index = objectiveContainer(of: piece)?.objectiveIndex,
              let rule = scenarioData?.placements?.saves?.first(where: { $0.objective == index }) else { return nil }
        let left = rule.times.map { max(0, $0 - boardState.savesUsed[index, default: 0]) }
        return left == 0 ? nil : (index, left)
    }

    /// The characters who could lose a card from their hand now, with the cards.
    func savingHands() -> [(characterID: String, cards: [Int])] {
        (gameManager?.game.characters ?? []).filter { !$0.exhausted && !$0.absent && isOnBoard(.character($0.id)) }
            .map { ($0.id, losableHandCards(of: $0)) }
            .filter { !$0.1.isEmpty }
    }

    /// Ask whether a card is lost to spare `piece` this damage; true when one was. Without a
    /// rule for it, a use left or a card to lose, nothing is asked. Headless, a card is lost
    /// only when the damage would destroy what is protected and lose the scenario with it: from
    /// the fullest hand.
    @MainActor func promptSave(of piece: PieceID, damage: Int, source: String) async -> Bool {
        guard damage > 0, let rule = save(for: piece), let entity = entity(for: piece), entity.health > 0 else { return false }
        let hands = savingHands()
        guard !hands.isEmpty else { return false }
        let choice: (characterID: String, cardId: Int)?
        if autoResolvePrompts {
            let fullest = hands.max { ($0.cards.count, $1.characterID) < ($1.cards.count, $0.characterID) }
            choice = damage >= entity.health && losesTheScenario(with: rule.objective)
                ? fullest.flatMap { hand in hand.cards.last.map { (hand.characterID, $0) } } : nil
        } else {
            let generation = boardGeneration
            choice = await withCheckedContinuation { continuation in
                pendingSave = PendingSave(objective: piece, name: name(piece), damage: damage, sourceDescription: source,
                                          health: entity.health, left: rule.left, hands: hands, continuation: continuation,
                                          losesTheScenario: losesTheScenario(with: rule.objective))
            }
            // The board was left while the party chose: nothing is lost and no damage is taken.
            guard isCurrentBoard(generation) else { return true }
        }
        guard let choice, let character = gameManager?.game.characters.first(where: { $0.id == choice.characterID }),
              losableHandCards(of: character).contains(choice.cardId),
              let index = character.handCards.firstIndex(of: choice.cardId) else { return false }
        gameManager?.characterManager.onBeforeMutate?()
        character.lostCards.append(character.handCards.remove(at: index))
        boardState.savesUsed[rule.objective, default: 0] += 1
        boardScene?.play(.lose)
        let leftNow = rule.left.map { $0 - 1 }
        log("\(characterName(character.id)) loses a card from hand to spare \(name(piece)) \(damage) damage"
            + (leftNow.map { " (\($0 == 0 ? "the last time" : "\($0) more time\($0 == 1 ? "" : "s")"))" } ?? ""), category: .damage)
        return true
    }

    /// Whether one more of this objective destroyed loses the scenario (the goal's `lostAt`).
    func losesTheScenario(with objective: Int) -> Bool {
        guard let limit = scenarioGoal?.lostAt?[String(objective)],
              let container = gameManager?.game.objectives.first(where: { $0.objectiveIndex == objective }) else { return false }
        return container.entities.filter(\.dead).count + 1 >= limit
    }

    /// The party's answer: who loses which card, or no one (nil).
    func resolvePendingSave(by characterID: String?, losing cardId: Int?) {
        guard let pending = pendingSave else { return }
        pendingSave = nil
        if let characterID, let cardId {
            pending.continuation?.resume(returning: (characterID, cardId))
        } else {
            pending.continuation?.resume(returning: nil)
        }
    }
}
