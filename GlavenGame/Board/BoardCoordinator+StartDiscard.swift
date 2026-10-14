import Foundation

/// "Each character discards three ability cards at the start of the scenario as a scenario
/// effect" (Harrower Hive): the scenario's `discardAtStart`. Asked of each character in turn
/// before the cards of the first round are chosen; the cards come back with the first rest.
extension BoardCoordinator {

    /// A character's choice, pending: which cards of the hand to discard.
    struct PendingStartDiscard: Identifiable {
        let id = UUID()
        let characterID: String
        let count: Int
        /// A random dungeon room's penalty, not the scenario's start: the cards are lost (`lose`)
        /// or discarded as the room opens.
        var penalty: String? = nil
        var lose = false
    }

    /// How many cards `character` has still to discard before the first round. Nothing else
    /// discards a card that early, so the discard pile itself says who has done it.
    func startDiscardOwed(by character: GameCharacter) -> Int {
        guard let count = scenarioData?.placements?.discardAtStart, gameManager?.game.round == 0,
              !character.absent, !character.exhausted else { return 0 }
        return min(max(0, count - character.discardedCards.count), character.handCards.count)
    }

    /// Have every character who owes cards discard them, then go on. Headless, the last cards of
    /// the hand go.
    func discardAtTheStart(then proceed: @escaping () -> Void) {
        guard let character = gameManager?.game.characters.first(where: { startDiscardOwed(by: $0) > 0 }) else {
            proceed()
            return
        }
        let owed = startDiscardOwed(by: character)
        if autoResolvePrompts {
            makeStartDiscard(Array(character.handCards.suffix(owed)), by: character)
            discardAtTheStart(then: proceed)
        } else {
            afterStartDiscards = proceed
            pendingStartDiscard = PendingStartDiscard(characterID: character.id, count: owed)
        }
    }

    /// The character's answer: exactly as many cards of the hand as are owed.
    func resolveStartDiscard(_ cards: [Int]) {
        guard let pending = pendingStartDiscard,
              let character = gameManager?.game.characters.first(where: { $0.id == pending.characterID }),
              cards.count == pending.count, Set(cards).count == cards.count,
              cards.allSatisfy(character.handCards.contains) else { return }
        pendingStartDiscard = nil
        if pending.penalty != nil {
            payPenaltyCards(cards, by: character, lose: pending.lose)
            askNextPenaltyCards()
            return
        }
        makeStartDiscard(cards, by: character)
        let proceed = afterStartDiscards
        afterStartDiscards = nil
        discardAtTheStart(then: proceed ?? {})
    }

    private func makeStartDiscard(_ cards: [Int], by character: GameCharacter) {
        for card in cards {
            guard let index = character.handCards.firstIndex(of: card) else { continue }
            character.discardedCards.append(character.handCards.remove(at: index))
        }
        log("\(characterName(character.id)) discards \(cards.count) card\(cards.count == 1 ? "" : "s") before the scenario begins", category: .round)
    }

    // MARK: - Cards a dungeon room's penalty takes (Cabin, Crossroads)

    /// Each character's cards owed to a penalty, asked one character at a time; headless, the
    /// last cards of the hand go.
    func owePenaltyCards(_ count: Int, by characters: [GameCharacter], lose: Bool, penalty: String) {
        for character in characters {
            let owed = min(count, character.handCards.count)
            guard owed > 0 else { continue }
            if autoResolvePrompts {
                payPenaltyCards(Array(character.handCards.suffix(owed)), by: character, lose: lose)
            } else {
                penaltyCardsOwed.append(PendingStartDiscard(characterID: character.id, count: owed, penalty: penalty, lose: lose))
            }
        }
        askNextPenaltyCards()
    }

    func askNextPenaltyCards() {
        guard pendingStartDiscard == nil, !penaltyCardsOwed.isEmpty else { return }
        pendingStartDiscard = penaltyCardsOwed.removeFirst()
    }

    private func payPenaltyCards(_ cards: [Int], by character: GameCharacter, lose: Bool) {
        for card in cards {
            guard let index = character.handCards.firstIndex(of: card) else { continue }
            let removed = character.handCards.remove(at: index)
            if lose { character.lostCards.append(removed) } else { character.discardedCards.append(removed) }
        }
        log("\(characterName(character.id)) \(lose ? "loses" : "discards") \(cards.count) card\(cards.count == 1 ? "" : "s")", category: .round)
    }
}
