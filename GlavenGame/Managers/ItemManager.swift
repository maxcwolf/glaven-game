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

    /// Whether the item is in the city's supply: unlocked by the party's prosperity level, or
    /// added by an item design, a scenario reward, a treasure or a random item draw. Scenario
    /// reward items, treasure items and random item designs start out of the supply.
    func isItemAvailable(_ item: ItemData) -> Bool {
        // Explicitly unlocked items (designs, rewards nobody could take, random draws)
        let key = "\(item.edition)-\(item.id)"
        if game.unlockedItems.contains(key) { return true }

        // Random items are never in the general pool
        if item.random { return false }

        // Scenario-based unlocks
        if let scenarioReq = item.unlockScenario {
            return game.completedScenarios.contains("\(item.edition)-\(scenarioReq)")
        }

        // Prosperity-based availability (items without a prosperity level are never in the
        // starting supply)
        return item.unlockProsperity > 0 && item.unlockProsperity <= game.prosperityLevel
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

    // MARK: - Buying and Selling

    /// The change to every shop price from the party's reputation (p.48): 1 gold off at +3,
    /// 2 at +7, 3 at +11, 4 at +15, 5 at +19, and as much more at −3, −7, −11, −15, −19.
    static func reputationPriceModifier(_ reputation: Int) -> Int {
        if reputation >= 3 { return -((reputation + 1) / 4) }
        if reputation <= -3 { return (-reputation + 1) / 4 }
        return 0
    }

    /// What the item costs the party now, with the reputation discount or surcharge.
    func price(_ item: ItemData) -> Int {
        max(0, item.cost + Self.reputationPriceModifier(game.partyReputation))
    }

    /// What selling the item back pays: half its printed price, rounded down (p.47).
    func salePrice(_ item: ItemData) -> Int {
        item.cost / 2
    }

    /// Why a character can't buy an item, or nil when they can.
    enum PurchaseProblem: Equatable { case alreadyOwned, soldOut, tooExpensive }

    func purchaseProblem(_ item: ItemData, for character: GameCharacter) -> PurchaseProblem? {
        if character.items.contains(item.itemKey) { return .alreadyOwned }
        if !inStock(item) { return .soldOut }
        if character.loot < price(item) { return .tooExpensive }
        return nil
    }

    /// Buy an item from the shop: a character owns one copy at most, the shop holds only as
    /// many copies as the item's count, and it costs its price in gold. Returns whether it sold.
    @discardableResult
    func buy(_ item: ItemData, for character: GameCharacter) -> Bool {
        guard purchaseProblem(item, for: character) == nil else { return false }
        onBeforeMutate?()
        character.loot -= price(item)
        character.items.append(item.itemKey)
        editionStore.fitLoadout(character, unlimited: game.tableRules.bringEveryItem)   // left at home if there's no room for it
        return true
    }

    /// Bring an owned item to the next scenario, or leave it at home; the reason it can't be
    /// brought, if it doesn't fit beside the others.
    @discardableResult
    func setBringing(_ key: String, _ bringing: Bool, for character: GameCharacter) -> ItemLoadout.Problem? {
        guard character.items.contains(key) else { return nil }
        if bringing {
            guard character.itemsLeftBehind.contains(key) else { return nil }
            if let problem = bringingProblem(key, for: character) { return problem }
            onBeforeMutate?()
            character.itemsLeftBehind.removeAll { $0 == key }
        } else {
            guard !character.itemsLeftBehind.contains(key) else { return nil }
            onBeforeMutate?()
            character.itemsLeftBehind.append(key)
            // Leaving Cloak of Pockets at home leaves the small items it made room for.
            editionStore.fitLoadout(character, unlimited: game.tableRules.bringEveryItem)
        }
        return nil
    }

    /// Why an item left at home can't be brought beside what the character is bringing.
    func bringingProblem(_ key: String, for character: GameCharacter) -> ItemLoadout.Problem? {
        guard !game.tableRules.bringEveryItem else { return nil }
        return ItemLoadout.problem(bringing: key, beside: character.carriedItems.filter { $0 != key }, level: character.level,
                            item: { self.editionStore.itemData(key: $0) })
    }

    /// Sell an item back to the shop for half its price, rounded down (p.47).
    @discardableResult
    func sell(_ item: ItemData, for character: GameCharacter) -> Bool {
        guard let index = character.items.firstIndex(of: item.itemKey) else { return false }
        onBeforeMutate?()
        character.items.remove(at: index)
        character.itemsLeftBehind.removeAll { $0 == item.itemKey }
        character.loot += salePrice(item)
        return true
    }

    // MARK: - Random Item Draw

    /// Draw a random item that hasn't been unlocked yet.
    /// - Parameters:
    ///   - blueprint: If true, draw from blueprint items (FH); otherwise random items
    ///   - from: Minimum item ID range (inclusive, -1 for no minimum)
    ///   - to: Maximum item ID range (inclusive, -1 for no maximum)
    /// - Returns: A random item, or nil if none available.
    func drawRandomItem(blueprint: Bool = false, from: Int = -1, to: Int = -1) -> ItemData? {
        Self.drawRandomItem(game: game, editionStore: editionStore, blueprint: blueprint, from: from, to: to)
    }

    /// A random item design not yet unlocked (shared with treasure rewards).
    static func drawRandomItem(game: GameState, editionStore: EditionDataStore,
                               blueprint: Bool = false, from: Int = -1, to: Int = -1) -> ItemData? {
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
        return candidates.randomElement(using: &GameRandom.shared)
    }

    /// Draw a random item design and add it to the city's supply.
    func drawAndUnlockRandomItem(blueprint: Bool = false) -> ItemData? {
        guard let drawn = drawRandomItem(blueprint: blueprint) else { return nil }
        onBeforeMutate?()
        let key = "\(drawn.edition)-\(drawn.id)"
        game.unlockedItems.insert(key)
        return drawn
    }
}
