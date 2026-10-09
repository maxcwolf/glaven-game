import Foundation

/// Player-facing names and phrases. The battle log, prompts, buttons and the main menu all take
/// their wording from here, so the game reads the same everywhere and never shows internal ids
/// ("gh-brute", "bandit-guard #2") or enum names ("sufferDamage").
enum GameText {

    /// "bandit-guard" → "Bandit Guard", "gh-brute" → "Brute" (an edition prefix is dropped).
    static func titleCased(_ slug: String) -> String {
        var name = slug
        for prefix in ["gh-", "fh-", "jotl-", "cs-", "toa-", "bb-", "gh2e-"] where name.hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
            break
        }
        return name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// "sufferDamage" → "Suffer Damage".
    static func words(fromCamelCase raw: String) -> String {
        var result = ""
        for character in raw {
            if character.isUppercase, !result.isEmpty { result.append(" ") }
            result.append(character)
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    // MARK: - Figures

    /// A character's name: the player's own title if they gave one, else the class name.
    static func characterName(_ character: GameCharacter, labels: EditionDataStore? = nil) -> String {
        if !character.title.isEmpty { return character.title }
        return className(character.name, edition: character.edition, labels: labels)
    }

    /// A character class's name, e.g. "Brute".
    static func className(_ name: String, edition: String, labels: EditionDataStore? = nil) -> String {
        labels?.resolveLabel(key: "character.\(edition).\(name)", edition: edition) ?? titleCased(name)
    }

    /// A monster type's name, e.g. "Bandit Guard".
    static func monsterName(_ name: String, edition: String? = nil, labels: EditionDataStore? = nil) -> String {
        if let edition, let label = labels?.resolveLabel(key: "monster.\(name)", edition: edition) {
            return label
        }
        return titleCased(name)
    }

    /// One standee, e.g. "Bandit Guard 2".
    static func standeeName(_ name: String, standee: Int, edition: String? = nil,
                            labels: EditionDataStore? = nil) -> String {
        "\(monsterName(name, edition: edition, labels: labels)) \(standee)"
    }

    /// The name of whatever stands on the board as `piece`.
    static func pieceName(_ piece: PieceID, game: GameState?, labels: EditionDataStore? = nil) -> String {
        switch piece {
        case .character(let id):
            if let character = game?.characters.first(where: { $0.id == id }) {
                return characterName(character, labels: labels)
            }
            return titleCased(id)
        case .monster(let name, let standee):
            let edition = game?.monsters.first(where: { $0.name == name })?.edition ?? game?.edition
            return standeeName(name, standee: standee, edition: edition, labels: labels)
        case .summon(let id):
            for character in game?.characters ?? [] {
                if let summon = character.summons.first(where: { $0.id == id }) {
                    return titleCased(summon.name)
                }
            }
            return "Summon"
        case .objective(let id):
            let container = game?.objectives.first { $0.entities.contains { $0.number == id } }
            if let name = container?.name, !name.isEmpty { return name }
            return "Objective"
        }
    }

    // MARK: - Game terms

    static func conditionName(_ condition: ConditionName) -> String {
        words(fromCamelCase: condition.rawValue)
    }

    static func elementName(_ element: ElementType) -> String {
        words(fromCamelCase: element.rawValue)
    }

    // MARK: - Actions

    /// What an ability does, as a button or prompt names it: "Attack 3, Range 2", "Move 4",
    /// "Poison", "Infuse Fire". The switch has no default, so a new action type can't ship
    /// without wording.
    static func actionTitle(_ action: ActionModel) -> String {
        let raw = action.value?.stringValue ?? ""
        let sign = action.valueType == .plus ? "+" : (action.valueType == .minus ? "−" : "")
        let value = raw.isEmpty ? "" : " \(sign)\(raw)"
        let base: String
        switch action.type {
        case .attack: base = "Attack\(value)"
        case .damage: base = "Damage\(value)"
        case .heal: base = "Heal\(value)"
        case .move: base = "Move\(value)"
        case .push: base = "Push\(value)"
        case .pull: base = "Pull\(value)"
        case .pierce: base = "Pierce\(value)"
        case .range: base = "Range\(value)"
        case .target: base = "Target\(value)"
        case .condition:
            base = ConditionName(rawValue: raw).map(conditionName) ?? titleCased(raw)
        case .shield: base = "Shield\(value)"
        case .retaliate: base = "Retaliate\(value)"
        case .element:
            base = ElementType(rawValue: raw).map { "Infuse \(elementName($0))" } ?? "Infuse Element"
        case .elementHalf: base = "Infuse Element"
        case .summon: base = raw.isEmpty ? "Summon" : "Summon \(titleCased(raw))"
        case .spawn: base = "Summon"
        case .area: base = "Area Attack"
        case .fly: base = "Fly"
        case .jump: base = "Jump"
        case .teleport: base = "Teleport\(value)"
        case .swing: base = "Swing"
        case .trigger: base = "Trigger"
        case .loot: base = "Loot\(value)"
        case .grid, .box, .forceBox, .boxFhSubActions, .nonCalc, .extra, .text, .card, .hint, .grant:
            base = "Card Effect"
        case .custom, .special: base = "Special Effect"
        case .specialTarget: base = "Special Target"
        case .concatenation, .concatenationSpacer: base = "Combined Effect"
        case .suffer, .sufferDamage: base = "Suffer\(value) Damage"
        case .experience: base = raw.isEmpty ? "Gain XP" : "Gain \(raw) XP"
        case .forceRefresh, .refreshItem: base = "Refresh an Item"
        case .refreshSpent: base = "Refresh Spent Items"
        case .monsterType, .switchType: base = "Change Monster Type"
        case .immune: base = ConditionName(rawValue: raw).map { "Immune to \(conditionName($0))" } ?? "Become Immune"
        case .removeNegativeConditions: base = "Remove Negative Conditions"
        }
        guard action.type == .attack || action.type == .heal || action.type == .condition,
              let range = action.subActions?.first(where: { $0.type == .range })?.value?.stringValue else {
            return base
        }
        return "\(base), Range \(range)"
    }

    /// How an element stands, for its tooltip and VoiceOver: "Fire: strong".
    static func elementStateDescription(_ element: ElementType, _ state: ElementState) -> String {
        let detail: String
        switch state {
        case .inert: detail = "inert"
        case .new: detail = "infused this turn, usable from the next turn"
        case .strong: detail = "strong"
        case .waning: detail = "waning"
        case .consumed, .partlyConsumed: detail = "consumed"
        case .always: detail = "always available"
        }
        return "\(elementName(element)): \(detail)"
    }

    /// What an attack modifier card adds besides its number: "Poison", "Pierce 2", "Rolling".
    static func modifierEffects(_ card: AttackModifier) -> [String] {
        var parts: [String] = card.effects.map { effect in
            let raw = effect.value?.stringValue ?? ""
            switch effect.type {
            case .condition:
                return ConditionName(rawValue: raw).map(conditionName) ?? titleCased(raw)
            case .element, .elementHalf:
                return ElementType(rawValue: raw).map { "Infuse \(elementName($0))" } ?? "Infuse Element"
            case .elementConsume:
                return ElementType(rawValue: raw).map { "Consume \(elementName($0))" } ?? "Consume Element"
            case .or_: return "Choice"
            case .custom, .specialTarget, .changeType: return "Special"
            case .sufferDamage: return raw.isEmpty ? "Suffer Damage" : "Suffer \(raw) Damage"
            case .target: return "Add Target"
            default:
                let name = words(fromCamelCase: effect.type.rawValue)
                return raw.isEmpty ? name : "\(name) \(raw)"
            }
        }
        if card.rolling { parts.insert("Rolling", at: 0) }
        return parts
    }

    /// A perk in the rulebook's words: "Remove two \u{2212}1 cards", "Replace one +0 card with one
    /// +2 card", "Add three rolling Push 1 cards", "Ignore negative item effects and add one +1 card".
    static func perkText(_ perk: PerkModel) -> String {
        let cards = perk.cards ?? []
        let phrases = cards.map { cardPhrase($0.attackModifier, count: $0.count) }
        if let custom = perk.custom, !custom.isEmpty {
            let rule = perkRules[custom] ?? custom
            guard !phrases.isEmpty else { return rule }
            return "\(rule) and add \(list(phrases))"
        }
        switch perk.type {
        case .add: return "Add \(list(phrases))"
        case .remove: return "Remove \(list(phrases))"
        case .replace:
            guard let first = phrases.first, phrases.count > 1 else { return "Replace \(list(phrases))" }
            return "Replace \(first) with \(list(Array(phrases.dropFirst())))"
        case .custom: return "A special rule"
        }
    }

    /// The perks that are rules rather than cards, named by placeholder in the edition data.
    private static let perkRules = [
        "%game.custom.perks.ignoreNegativeItem%": "Ignore negative item effects",
        "%game.custom.perks.ignoreNegativeScenario%": "Ignore negative scenario effects",
    ]

    /// "one \u{2212}1 card", "three rolling Push 1 cards", "two +1 Wound cards".
    private static func cardPhrase(_ card: AttackModifier, count: Int) -> String {
        let numbers = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        var words = [count < numbers.count ? numbers[count] : "\(count)"]
        if card.rolling { words.append("rolling") }
        let effects = modifierEffects(card).filter { $0 != "Rolling" }
        // A rolling +0 card is named by what it does ("rolling Push 1"), as the cards print it.
        if !(card.rolling && card.type == .plus0 && !effects.isEmpty) { words.append(modifierValue(card.type)) }
        words += effects
        words.append(count == 1 ? "card" : "cards")
        return words.joined(separator: " ")
    }

    /// "+1", "\u{2212}2", "\u{00D7}2", "Null".
    static func modifierValue(_ type: AttackModifierType) -> String {
        switch type {
        case .plus0: return "+0"
        case .plus1: return "+1"
        case .plus2: return "+2"
        case .plus3: return "+3"
        case .plus4: return "+4"
        case .plusX: return "+X"
        case .minus1, .minus1extra: return "\u{2212}1"
        case .minus2: return "\u{2212}2"
        case .double_: return "\u{00D7}2"
        case .null_: return "Null"
        default: return words(fromCamelCase: type.rawValue).capitalized
        }
    }

    /// "Fire", "Fire and Ice", "Fire, Ice and Air".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
