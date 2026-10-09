import Foundation

/// City and road events (GH p.38). Each deck starts as cards 01–30, shuffled; events add more.
/// A city event is resolved each time the party is back in Gloomhaven, and a road event before
/// travelling to a scenario whose card shows the road. The players read the card, pick A or B,
/// and the first outcome whose condition holds applies. Afterwards the card is removed from the
/// game or returned to the bottom of its deck, as the card says.
@Observable
final class EventCardManager {

    enum Deck: String, CaseIterable { case city, road }

    /// Choices an outcome may ask for. Anything left unchosen falls back to a default.
    struct Choices: Equatable {
        /// For each "choose one" effect, in the order they appear: which one (default the first).
        var chosen: [Int] = []
        /// Character id → the cards they start the next scenario with in their discard pile.
        var discards: [String: [Int]] = [:]
        /// Who takes an effect meant for one character (default the first in the party).
        var oneCharacter: String?
    }

    /// What an option led to: the outcome's text and its effects in words.
    struct Resolution: Equatable {
        let narrative: String
        let effects: [String]
    }

    private let game: GameState
    private let editionStore: EditionDataStore
    private let scenarioManager: ScenarioManager
    private let itemManager: ItemManager

    init(game: GameState, editionStore: EditionDataStore, scenarioManager: ScenarioManager, itemManager: ItemManager) {
        self.game = game
        self.editionStore = editionStore
        self.scenarioManager = scenarioManager
        self.itemManager = itemManager
    }

    private var edition: String { game.edition ?? "gh" }
    private var party: [GameCharacter] { game.characters.filter { !$0.absent } }

    // MARK: - Decks

    /// The deck, top card first.
    func deck(_ deck: Deck) -> [String] {
        // A plain read once started: going through the mutating accessor would write the game's
        // events on every call and keep re-rendering any view that shows a deck.
        game.events.peek(deck.rawValue) ?? game.events.cards(deck.rawValue)
    }

    private func setDeck(_ deck: Deck, _ cards: [String]) {
        game.events.setCards(deck.rawValue, cards)
    }

    /// The card on top of the deck (it stays there until it's resolved).
    func topCard(_ deck: Deck) -> EventCardData? {
        guard let id = self.deck(deck).first else { return nil }
        return card(deck, id)
    }

    func card(_ deck: Deck, _ id: String) -> EventCardData? {
        editionStore.events(for: edition).first { $0.type == deck.rawValue && $0.cardId == id }
    }

    /// Add a card to a deck and shuffle it in (an event's "add event" effect).
    func addCard(_ deck: Deck, _ id: String) {
        guard card(deck, id) != nil else { return }
        game.events.add(id, to: deck.rawValue)
    }

    // MARK: - When events happen

    /// Whether setting out for `scenario` takes a road event.
    func needsRoadEvent(for scenario: ScenarioData) -> Bool {
        if game.tableRules.noFirstRoadEvent, game.completedScenarios.isEmpty { return false }
        return scenario.eventType == "road"
    }

    // MARK: - Outcomes

    /// The outcome an option leads to: the first whose condition holds.
    func outcome(_ event: EventCardData, option label: String) -> EventOutcome? {
        guard let option = event.options?.first(where: { $0.label == label }) else { return nil }
        return option.outcomes?.first { holds($0.condition) }
    }

    /// Whether a condition holds for the party right now.
    func holds(_ condition: EventCondition?) -> Bool {
        guard let condition else { return true }
        let values = condition.values ?? []
        let ints = values.compactMap(\.intValue)
        switch condition.type {
        case "otherwise": return true
        case "character": return values.compactMap(\.stringValue).contains { name in party.contains { $0.name == name } }
        case "reputationGT": return ints.first.map { game.partyReputation > $0 } ?? false
        case "reputationLT": return ints.first.map { game.partyReputation < $0 } ?? false
        case "payCollectiveGold": return ints.first.map { totalGold >= $0 } ?? false
        case "payGold": return ints.first.map { price in party.allSatisfy { $0.loot >= price } } ?? false
        case "payCollectiveGoldConditional": return conditionalPrice(condition).map { totalGold >= $0 } ?? false
        case "payCollectiveItem": return ints.first.map { owner(ofItem: $0) != nil } ?? false
        default: return false
        }
    }

    private var totalGold: Int { party.reduce(0) { $0 + $1.loot } }

    /// "payCollectiveGoldConditional": the price depends on reputation.
    private func conditionalPrice(_ condition: EventCondition) -> Int? {
        for alternative in condition.alternatives ?? [] {
            let ints = (alternative.values ?? []).compactMap(\.intValue)
            guard ints.count == 2 else { continue }
            let (price, reputation) = (ints[0], ints[1])
            if alternative.type.hasSuffix("ReputationLT"), game.partyReputation < reputation { return price }
            if alternative.type.hasSuffix("ReputationGT"), game.partyReputation > reputation { return price }
        }
        return nil
    }

    private func owner(ofItem id: Int) -> GameCharacter? {
        party.first { $0.items.contains("\(edition)-\(id)") }
    }

    /// The ability cards each character must put in their discard pile for the next scenario.
    func discardRequirements(_ event: EventCardData, option label: String, choices: Choices = Choices()) -> [String: Int] {
        var needed: [String: Int] = [:]
        func walk(_ effects: [EventEffect]) {
            var chooseIndex = 0
            for effect in effects where holds(effect.condition) {
                switch effect.type {
                case "discard":
                    for character in party { needed[character.id, default: 0] += effect.values?.first?.intValue ?? 1 }
                case "discardOne":
                    if let id = choices.oneCharacter ?? party.first?.id { needed[id, default: 0] += 1 }
                case "choose":
                    let pick = chooseIndex < choices.chosen.count ? choices.chosen[chooseIndex] : 0
                    chooseIndex += 1
                    if let sub = effect.subEffects, pick < sub.count { walk([sub[pick]]) }
                case "outcome":
                    if let target = effect.values?.first?.stringValue, let next = outcome(event, option: target) {
                        walk(next.effects ?? [])
                    }
                default: break
                }
            }
        }
        walk(outcome(event, option: label)?.effects ?? [])
        return needed
    }

    // MARK: - Resolving

    /// Resolve the top card of a deck with option `label`: pay any price, apply the outcome's
    /// effects, then remove the card or return it to the bottom.
    @discardableResult
    func resolve(_ deck: Deck, option label: String, choices: Choices = Choices()) -> Resolution? {
        guard let event = topCard(deck), let option = event.options?.first(where: { $0.label == label }),
              var outcome = outcome(event, option: label) else { return nil }
        var lines: [String] = []
        var narrative = outcome.narrative ?? ""
        var chooseIndex = 0
        pay(outcome.condition, lines: &lines)

        // "outcome A": the outcome of another option applies instead.
        if let redirect = outcome.effects?.first(where: { $0.type == "outcome" })?.values?.first?.stringValue,
           let next = self.outcome(event, option: redirect) {
            pay(next.condition, lines: &lines)
            narrative += next.narrative.map { "\n\n" + $0 } ?? ""
            outcome = EventOutcome(narrative: outcome.narrative, effects: next.effects, condition: nil,
                                   returnToDeck: outcome.returnToDeck ?? next.returnToDeck,
                                   removeFromDeck: outcome.removeFromDeck ?? next.removeFromDeck)
        }
        for effect in outcome.effects ?? [] where effect.type != "outcome" {
            apply(effect, choices: choices, chooseIndex: &chooseIndex, lines: &lines)
        }

        // The card's fate: the outcome's mark, else the option's; removed unless it says return.
        let returns = outcome.returnToDeck ?? option.returnToDeck ?? false
        var cards = self.deck(deck)
        cards.removeAll { $0 == event.cardId }
        if returns { cards.append(event.cardId) }
        setDeck(deck, cards)

        game.campaignLog.append(CampaignLogEntry(
            type: .eventResolved,
            message: "\(deck == .city ? "City" : "Road") event \(event.cardId), option \(label)",
            details: lines.isEmpty ? nil : lines.joined(separator: "; ")))
        return Resolution(narrative: narrative, effects: lines.isEmpty ? ["No effect."] : lines)
    }

    /// Pay what a condition costs when it holds.
    private func pay(_ condition: EventCondition?, lines: inout [String]) {
        guard let condition else { return }
        let price = (condition.values ?? []).first?.intValue ?? 0
        switch condition.type {
        case "payCollectiveGold": takeCollectiveGold(price, lines: &lines)
        case "payCollectiveGoldConditional": takeCollectiveGold(conditionalPrice(condition) ?? 0, lines: &lines)
        case "payGold":
            for character in party { character.loot = max(0, character.loot - price) }
            lines.append("Each character pays \(price) gold.")
        case "payCollectiveItem":
            if let owner = owner(ofItem: price), let index = owner.items.firstIndex(of: "\(edition)-\(price)") {
                owner.items.remove(at: index)
                lines.append("\(name(owner)) gives up \(itemName(price)).")
            }
        default: break
        }
        var ignored = 0
        for effect in condition.effects { apply(effect, choices: Choices(), chooseIndex: &ignored, lines: &lines) }
    }

    private func apply(_ effect: EventEffect, choices: Choices, chooseIndex: inout Int, lines: inout [String]) {
        guard holds(effect.condition) else { return }
        let values = effect.values ?? []
        let amount = values.first?.intValue ?? 0
        switch effect.type {
        case "noEffect": break
        case "reputation", "reputationAdditional":
            game.partyReputation = min(20, game.partyReputation + amount)
            lines.append("Reputation +\(amount).")
        case "loseReputation":
            game.partyReputation = max(-20, game.partyReputation - amount)
            lines.append("Reputation \u{2212}\(amount).")
        case "prosperity":
            game.partyProsperity += amount
            lines.append("Prosperity +\(amount).")
        case "loseProsperity":
            game.partyProsperity = max(0, game.partyProsperity - amount)
            lines.append("Prosperity \u{2212}\(amount).")
        case "gold", "goldAdditional":
            for character in party { character.loot += amount }
            lines.append("Each character gains \(amount) gold.")
        case "loseGold":
            for character in party { character.loot = max(0, character.loot - amount) }
            lines.append("Each character loses \(amount) gold.")
        case "experience":
            for character in party { character.experience += amount }
            lines.append("Each character gains \(amount) experience.")
        case "collectiveGold", "collectiveGoldAdditional":
            let shares = scenarioManager.collectiveGoldShares(total: amount)
            for character in party { character.loot += shares[character.id] ?? 0 }
            lines.append("The party gains \(amount) gold, shared out.")
        case "loseCollectiveGold":
            takeCollectiveGold(amount, lines: &lines)
        case "battleGoal":
            for character in party { character.addBattleGoalChecks(amount) }
            lines.append("Each character gains \(amount) battle goal checkmark\(amount == 1 ? "" : "s").")
        case "loseBattleGoal":
            for character in party { character.addBattleGoalChecks(-amount) }
            lines.append("Each character loses \(amount) battle goal checkmark\(amount == 1 ? "" : "s").")
        case "partyAchievement":
            for id in values.compactMap(\.stringValue) {
                game.partyAchievements.insert(id)
                lines.append("Party achievement: \(achievementName(id, kind: "partyAchievements")).")
            }
        case "globalAchievement":
            for id in values.compactMap(\.stringValue) {
                game.globalAchievements.insert(id)
                lines.append("Global achievement: \(achievementName(id, kind: "globalAchievements")).")
            }
        case "unlockScenario":
            for index in values.map(\.stringValue) {
                game.manualScenarios.insert("\(edition)-\(index)")
                let title = editionStore.scenarioData(index: index, edition: edition)
                    .map { ScenarioBrief.make(for: $0, labels: editionStore).title } ?? "#\(index)"
                lines.append("New scenario: \(title).")
            }
        case "event":
            let strings = values.compactMap(\.stringValue)
            if strings.count == 2, let deck = Deck(rawValue: strings[0]) {
                addCard(deck, strings[1])
                lines.append("A new \(deck.rawValue) event is shuffled into the deck.")
            }
        case "itemCollective":
            let id = amount
            let count = values.count > 1 ? max(1, values[1].intValue) : 1
            for _ in 0..<count {
                let key = "\(edition)-\(id)"
                if let taker = scenarioManager.eligibleItemRecipients(key).first {
                    taker.items.append(key)
                    editionStore.fitLoadout(taker, unlimited: game.tableRules.bringEveryItem)
                    lines.append("\(name(taker)) takes \(itemName(id)).")
                } else {
                    game.unlockedItems.insert(key)
                    lines.append("\(itemName(id)) goes to the shop.")
                }
            }
        case "itemDesign":
            game.unlockedItems.insert("\(edition)-\(amount)")
            lines.append("Item design: \(itemName(amount)), now in the shop.")
        case "randomItemDesign":
            if let item = itemManager.drawAndUnlockRandomItem() {
                lines.append("Item design: \(item.name), now in the shop.")
            }
        case "scenarioDamage":
            game.events.nextScenario.damage += amount
            lines.append("Everyone starts the next scenario with \(amount) damage.")
        case "scenarioCondition":
            for raw in values.compactMap(\.stringValue) {
                guard let condition = ConditionName(rawValue: raw) else { continue }
                game.events.nextScenario.conditions.append(condition)
                lines.append("Everyone starts the next scenario with \(GameText.conditionName(condition)).")
            }
        case "scenarioSingleMinus1":
            if let id = choices.oneCharacter ?? party.first?.id {
                game.events.nextScenario.minusOneCards[id, default: 0] += amount
                let who = party.first { $0.id == id }.map(name) ?? "One character"
                lines.append("\(who) adds \(amount) \u{2212}1 card\(amount == 1 ? "" : "s") for the next scenario.")
            }
        case "discard", "discardOne":
            for character in party {
                let cards = choices.discards[character.id] ?? []
                guard !cards.isEmpty else { continue }
                game.events.nextScenario.discards[character.id, default: []] += cards
            }
            lines.append(effect.type == "discard"
                         ? "Everyone starts the next scenario with \(amount) card\(amount == 1 ? "" : "s") discarded."
                         : "One character starts the next scenario with a card discarded.")
        case "consumeItem", "consumeCollectiveItem":
            let size = values.count > 1 ? values[1].stringValue : nil
            let takers = effect.type == "consumeItem" ? party : Array(party.prefix(1))
            for character in takers {
                if let key = character.items.first(where: { key in
                    !character.consumedItems.contains(key) && (size == nil || itemSlot(key) == size)
                }) {
                    character.consumedItems.insert(key)
                    lines.append("\(name(character))'s \(itemName(key)) is used up for the next scenario.")
                }
            }
        case "choose":
            let pick = chooseIndex < choices.chosen.count ? choices.chosen[chooseIndex] : 0
            chooseIndex += 1
            if let sub = effect.subEffects, pick < sub.count {
                apply(sub[pick], choices: choices, chooseIndex: &chooseIndex, lines: &lines)
            }
        default:
            break
        }
    }

    /// Take gold from the party one coin at a time from whoever has most (the players can settle
    /// it differently between themselves; the total is what the rules ask).
    private func takeCollectiveGold(_ amount: Int, lines: inout [String]) {
        var left = min(amount, totalGold)
        while left > 0, let richest = party.max(by: { $0.loot < $1.loot }), richest.loot > 0 {
            richest.loot -= 1
            left -= 1
        }
        lines.append("The party pays \(amount) gold.")
    }

    // MARK: - Words

    func name(_ character: GameCharacter) -> String {
        GameText.characterName(character, labels: editionStore)
    }

    private func itemName(_ id: Int) -> String {
        editionStore.itemData(id: id, edition: edition)?.name ?? "item \(id)"
    }

    private func itemName(_ key: String) -> String {
        Int(key.split(separator: "-").last ?? "").map(itemName) ?? key
    }

    private func itemSlot(_ key: String) -> String? {
        Int(key.split(separator: "-").last ?? "").flatMap { editionStore.itemData(id: $0, edition: edition)?.slot.rawValue }
    }

    private func achievementName(_ id: String, kind: String) -> String {
        editionStore.resolveLabel(key: "\(kind).\(id)", edition: edition) ?? GameText.titleCased(id)
    }

    /// Describe a choice's options ("Lose 5 gold each" / "Lose 1 reputation").
    func describe(_ effect: EventEffect) -> String {
        let amount = effect.values?.first?.intValue ?? 0
        switch effect.type {
        case "loseGold": return "Each character loses \(amount) gold"
        case "loseReputation": return "Lose \(amount) reputation"
        case "loseCollectiveGold": return "The party pays \(amount) gold"
        case "reputation": return "Gain \(amount) reputation"
        case "gold": return "Each character gains \(amount) gold"
        default: return GameText.words(fromCamelCase: effect.type).capitalized + (amount > 0 ? " \(amount)" : "")
        }
    }

    /// The "choose one" effects in an outcome, in order, so the screen can ask.
    func choices(in outcome: EventOutcome) -> [[EventEffect]] {
        (outcome.effects ?? []).filter { $0.type == "choose" }.compactMap(\.subEffects)
    }

    /// Whether an outcome has an effect for one character of the players' choice.
    func asksForOneCharacter(_ outcome: EventOutcome) -> Bool {
        (outcome.effects ?? []).contains { ["scenarioSingleMinus1", "discardOne"].contains($0.type) }
    }
}
