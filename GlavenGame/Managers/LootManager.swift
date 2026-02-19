import Foundation

@Observable
final class LootManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?

    init(game: GameState) {
        self.game = game
    }

    func drawCard() -> Loot? {
        onBeforeMutate?()
        game.lootDeck.current += 1
        guard game.lootDeck.current < game.lootDeck.cards.count else {
            game.lootDeck.current -= 1
            return nil
        }
        return game.lootDeck.cards[game.lootDeck.current]
    }

    func getValue(for loot: Loot) -> Int {
        let playerCount = max(2, game.activeCharacters.count)
        switch playerCount {
        case 2: return loot.value2P
        case 3: return loot.value3P
        default: return loot.value4P
        }
    }

    func applyLoot(_ loot: Loot, to character: GameCharacter) {
        switch loot.type {
        case .money:
            character.loot += getValue(for: loot)
        default:
            // Resource loot types added to character progress
            character.loot += getValue(for: loot)
        }
    }

    func shuffleDeck() {
        game.lootDeck.cards.shuffle()
        game.lootDeck.current = -1
    }
}
