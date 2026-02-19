import Foundation

@Observable
final class AttackModifierManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?

    init(game: GameState) {
        self.game = game
    }

    // NOTE: drawCard does NOT call onBeforeMutate — callers must call it
    // before passing the inout reference, to avoid simultaneous access
    // (toSnapshot reads game while inout holds exclusive write access).
    private func drawCard(from deck: inout AttackModifierDeck) -> AttackModifier? {
        deck.current += 1
        guard deck.current < deck.cards.count else {
            deck.current -= 1
            return nil
        }
        return deck.cards[deck.current]
    }

    func shuffleDeck(_ deck: inout AttackModifierDeck) {
        // Remove bless/curse from used cards
        var newCards = deck.attackModifiers.filter { !$0.type.isSpecial }
        // Add any remaining undrawn special cards
        if deck.current + 1 < deck.cards.count {
            for i in (deck.current + 1)..<deck.cards.count {
                if deck.cards[i].type.isSpecial {
                    newCards.append(deck.cards[i])
                }
            }
        }
        newCards.shuffle()
        deck.cards = newCards
        deck.current = -1
        deck.discards = []
    }

    private func addCardToDeck(_ deck: inout AttackModifierDeck, card: AttackModifier) {
        let insertRange = max(0, deck.cards.count - deck.current - 1)
        if insertRange > 0 {
            deck.cards.insert(card, at: deck.current + 1 + Int.random(in: 0..<insertRange))
        } else {
            deck.cards.append(card)
        }
    }

    // MARK: - Public entry points (snapshot before inout borrow)

    func drawMonsterCard() -> AttackModifier? {
        onBeforeMutate?()
        return drawCard(from: &game.monsterAttackModifierDeck)
    }

    func drawAllyCard() -> AttackModifier? {
        onBeforeMutate?()
        return drawCard(from: &game.allyAttackModifierDeck)
    }

    func drawCharacterCard(for character: GameCharacter) -> AttackModifier? {
        onBeforeMutate?()
        return drawCard(from: &character.attackModifierDeck)
    }

    func addBless(to target: AttackModifierTarget) {
        onBeforeMutate?()
        let card = AttackModifier(type: .bless, value: 2, valueType: .multiply, shuffle: true)
        switch target {
        case .monster:
            addCardToDeck(&game.monsterAttackModifierDeck, card: card)
        case .character(let c):
            addCardToDeck(&c.attackModifierDeck, card: card)
        }
    }

    // MARK: - Perk Deck Building

    func buildCharacterDeck(for character: GameCharacter) {
        guard let perks = character.characterData?.perks else { return }
        var baseDeck = AttackModifier.defaultMonsterDeck()

        for (index, perk) in perks.enumerated() {
            let timesSelected = index < character.selectedPerks.count ? character.selectedPerks[index] : 0
            guard timesSelected > 0 else { continue }
            for _ in 0..<timesSelected {
                applyPerk(perk, to: &baseDeck)
            }
        }

        // Mark all cards as character cards
        for i in baseDeck.indices {
            baseDeck[i].character = true
        }

        character.attackModifierDeck = AttackModifierDeck(
            attackModifiers: baseDeck,
            cards: baseDeck.shuffled()
        )
    }

    private func applyPerk(_ perk: PerkModel, to deck: inout [AttackModifier]) {
        guard let cards = perk.cards else { return }
        switch perk.type {
        case .add:
            for perkCard in cards {
                for _ in 0..<perkCard.count {
                    deck.append(perkCard.attackModifier)
                }
            }
        case .remove:
            for perkCard in cards {
                for _ in 0..<perkCard.count {
                    if let idx = deck.firstIndex(where: { matchesPerkCard($0, perkCard.attackModifier) }) {
                        deck.remove(at: idx)
                    }
                }
            }
        case .replace:
            guard cards.count >= 2 else { return }
            let removeCard = cards[0]
            for _ in 0..<removeCard.count {
                if let idx = deck.firstIndex(where: { matchesPerkCard($0, removeCard.attackModifier) }) {
                    deck.remove(at: idx)
                }
            }
            for addCard in cards.dropFirst() {
                for _ in 0..<addCard.count {
                    deck.append(addCard.attackModifier)
                }
            }
        case .custom:
            break
        }
    }

    private func matchesPerkCard(_ card: AttackModifier, _ template: AttackModifier) -> Bool {
        card.type == template.type
            && card.value == template.value
            && card.valueType == template.valueType
            && card.effects == template.effects
            && card.rolling == template.rolling
    }

    func addCurse(to target: AttackModifierTarget) {
        onBeforeMutate?()
        let card = AttackModifier(type: .curse, value: 0, valueType: .multiply, shuffle: true)
        switch target {
        case .monster:
            addCardToDeck(&game.monsterAttackModifierDeck, card: card)
        case .character(let c):
            addCardToDeck(&c.attackModifierDeck, card: card)
        }
    }
}

enum AttackModifierTarget {
    case monster
    case character(GameCharacter)
}
