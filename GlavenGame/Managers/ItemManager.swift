import Foundation

@Observable
final class ItemManager {
    private let game: GameState
    private let editionStore: EditionDataStore
    var onBeforeMutate: (() -> Void)?

    init(game: GameState, editionStore: EditionDataStore) {
        self.game = game
        self.editionStore = editionStore
    }

    // MARK: - Item Availability

    /// Check if an item is available based on all unlock criteria.
    func isItemAvailable(_ item: ItemData) -> Bool {
        let edition = game.edition ?? "gh"

        // Random items are never in the general pool
        if item.random { return false }

        // Explicitly unlocked items
        let key = "\(item.edition)-\(item.id)"
        if game.unlockedItems.contains(key) { return true }

        // Prosperity-based availability
        if item.unlockProsperity > 0 && item.unlockProsperity <= game.partyProsperity {
            if item.unlockScenario == nil {
                return true
            }
        }

        // Scenario-based unlocks
        if let scenarioReq = item.unlockScenario {
            let scenarioKey = "\(item.edition)-\(scenarioReq)"
            if game.completedScenarios.contains(scenarioKey) {
                return true
            }
        }

        // Items with no restrictions (prosperity 0 means always available if not random and not scenario-locked)
        if item.unlockProsperity == 0 && item.unlockScenario == nil && !item.random {
            return true
        }

        return false
    }

    /// Get all available items for the current edition.
    func availableItems() -> [ItemData] {

        let edition = game.edition ?? "gh"
        return editionStore.items(for: edition).filter { isItemAvailable($0) }
    }

    /// Get all available items filtered by slot.
    func availableItems(slot: ItemSlot?) -> [ItemData] {
        let items = availableItems()
        guard let slot else { return items }
        return items.filter { $0.slot == slot }
    }

    // MARK: - Unlock Operations

    func unlockItem(_ item: ItemData) {

        onBeforeMutate?()
        let key = "\(item.edition)-\(item.id)"
        game.unlockedItems.insert(key)
    }

    func lockItem(_ item: ItemData) {

        onBeforeMutate?()
        let key = "\(item.edition)-\(item.id)"
        game.unlockedItems.remove(key)
    }

    func isExplicitlyUnlocked(_ item: ItemData) -> Bool {
        let key = "\(item.edition)-\(item.id)"
        return game.unlockedItems.contains(key)
    }

    /// Count of items currently owned by characters in the party.
    func ownedCount(_ item: ItemData) -> Int {
        let itemKey = "\(item.edition)-\(item.id)"
        return game.characters.reduce(0) { count, char in
            count + char.items.filter { $0 == itemKey }.count
        }
    }

    /// Whether the item still has copies available in the shop.
    func inStock(_ item: ItemData) -> Bool {
        ownedCount(item) < item.count
    }

    // MARK: - Random Item Draw

    /// Draw a random item that hasn't been unlocked yet.
    /// - Parameters:
    ///   - blueprint: If true, draw from blueprint items (FH); otherwise random items
    ///   - from: Minimum item ID range (inclusive, -1 for no minimum)
    ///   - to: Maximum item ID range (inclusive, -1 for no maximum)
    /// - Returns: A random item, or nil if none available.
    func drawRandomItem(blueprint: Bool = false, from: Int = -1, to: Int = -1) -> ItemData? {

        let edition = game.edition ?? "gh"
        let allItems = editionStore.items(for: edition)

        let candidates = allItems.filter { item in
            // Must be random or blueprint
            guard item.random || blueprint else { return false }

            // Not already unlocked
            let key = "\(item.edition)-\(item.id)"
            guard !game.unlockedItems.contains(key) else { return false }

            // ID range filter
            if from >= 0 && item.id < from { return false }
            if to >= 0 && item.id > to { return false }

            return true
        }

        guard !candidates.isEmpty else { return nil }
        return candidates.randomElement()
    }

    /// Unlock a randomly drawn item and return it.
    func drawAndUnlockRandomItem(blueprint: Bool = false) -> ItemData? {
        guard let drawn = drawRandomItem(blueprint: blueprint) else { return nil }
        onBeforeMutate?()
        let key = "\(drawn.edition)-\(drawn.id)"
        game.unlockedItems.insert(key)
        return drawn
    }
}
