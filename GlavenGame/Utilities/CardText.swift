import Foundation

/// A line of a card half as the drawn card shows it.
struct CardLine: Equatable {
    enum Kind: Equatable {
        /// An ability, with its icon: "Attack 3, Range 2".
        case ability
        /// What is printed under an ability: "Pierce 2", "Target all adjacent enemies".
        case detail
        /// The card's own words: "Gain 1 Shield each time you Retaliate this round."
        case note
        /// Small marks: "+2 XP", "Persistent", "Lost", "4 uses".
        case badge
        /// An area of effect, drawn as hexes (the pattern of `ActionHex.parse`).
        case area(String)
    }

    var kind: Kind
    var text: String
    var depth: Int
    /// The icon: the ability's type, with a condition's or element's name.
    var icon: ActionType?
    var iconValue: String?
}

/// A card half as lines of text, for the drawn cards: every ability with everything printed under
/// it, so a player reading the drawn card plays the same card as one reading the scan.
enum CardText {
    /// The lines of a card half, and the actions it couldn't say (shown by their bare title; a
    /// test keeps it empty for every character card).
    static func lines(of actions: [ActionModel]?, resolve: @escaping (String) -> String? = { _ in nil })
        -> (lines: [CardLine], unread: [ActionModel]) {
        var writer = Writer(resolve: resolve)
        writer.say(actions ?? [], depth: 0)
        return (writer.lines, writer.unread)
    }

    private struct Writer {
        let resolve: (String) -> String?
        var lines: [CardLine] = []
        var unread: [ActionModel] = []

        private static let containers: Set<ActionType> = [.concatenation, .grid, .box, .forceBox, .boxFhSubActions]
        private static let words: Set<ActionType> = [.custom, .special, .trigger, .text, .grant, .hint, .nonCalc]

        mutating func say(_ actions: [ActionModel], depth: Int) {
            // A group's card marks (persistent, uses, XP, lost) are one line.
            let marks = actions.filter { $0.type == .card || $0.type == .experience }
            for action in actions where action.type != .card && action.type != .experience {
                say(action, depth: depth)
            }
            if let badge = CardText.badge(marks) {
                lines.append(CardLine(kind: .badge, text: badge, depth: depth))
            }
        }

        mutating func say(_ action: ActionModel, depth: Int) {
            let subs = action.subActions ?? []
            switch action.type {
            case _ where Self.containers.contains(action.type):
                // A container's own value is layout (":1", a grid's columns) unless it names a text.
                if action.value?.stringValue.hasPrefix("%") == true, let text = words(action), !text.isEmpty {
                    lines.append(CardLine(kind: .note, text: text, depth: depth))
                }
                say(subs, depth: depth)
            case .concatenationSpacer:
                break
            case _ where Self.words.contains(action.type):
                if let text = words(action) {
                    if !text.isEmpty { lines.append(CardLine(kind: .note, text: text, depth: depth)) }
                } else {
                    unread.append(action)
                }
                say(subs, depth: depth + 1)
            case .element:
                let names = CardText.elementNames(action.value?.stringValue ?? "")
                let consume = action.valueType == .minus
                lines.append(CardLine(kind: .ability, text: consume ? "Consume \(names):" : "Infuse \(names)", depth: depth,
                                      icon: .element, iconValue: action.value?.stringValue.split(separator: ":").first.map(String.init)))
                say(subs, depth: depth + 1)
            case .specialTarget:
                lines.append(CardLine(kind: .detail, text: CardText.target(action.value?.stringValue ?? ""), depth: depth))
                say(subs, depth: depth + 1)
            case .area:
                lines.append(CardLine(kind: .area(action.value?.stringValue ?? ""), text: "", depth: depth))
            case .summon, .spawn:
                summon(action, depth: depth)
                say(subs, depth: depth + 1)
            case .attack, .damage, .move, .heal, .shield, .retaliate, .loot, .push, .pull, .pierce, .range, .target,
                 .teleport, .condition, .jump, .fly, .suffer, .sufferDamage, .immune, .removeNegativeConditions,
                 .refreshItem, .refreshSpent, .forceRefresh, .swing:
                // Range and Target read with the ability ("Attack 3, Range 2"); the rest under it.
                let inline = subs.filter { ($0.type == .range || $0.type == .target) && $0.subActions == nil }
                let title = ([CardText.title(action)] + inline.map(CardText.title)).joined(separator: ", ")
                let isDetail = depth > 0 && [.pierce, .jump, .fly, .push, .pull, .range, .target].contains(action.type)
                lines.append(CardLine(kind: isDetail ? .detail : .ability, text: title, depth: depth,
                                      icon: action.type, iconValue: action.value?.stringValue))
                say(subs.filter { sub in !inline.contains(where: { $0.id == sub.id }) }, depth: depth + 1)
            default:
                unread.append(action)
                lines.append(CardLine(kind: .ability, text: GameText.actionTitle(action), depth: depth, icon: action.type))
                say(subs, depth: depth + 1)
            }
        }

        /// An action's printed words: "" when it has none, nil when they can't be found.
        private func words(_ action: ActionModel) -> String? {
            let raw = action.value?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
            guard raw.hasPrefix("%") else { return CardText.plain(raw) }
            if raw == CardText.unwritten { return "See the printed card: this half isn't in the game's data yet." }
            if let text = resolve(raw) { return CardText.plain(text) }
            return raw.hasPrefix("%game.") ? CardText.plain(raw) : nil
        }

        private mutating func summon(_ action: ActionModel, depth: Int) {
            guard let summon = action.summonValueObject else {
                let name = action.value?.stringValue ?? ""
                lines.append(CardLine(kind: .ability, text: name.isEmpty ? "Summon" : "Summon \(GameText.titleCased(name))",
                                      depth: depth, icon: .summon))
                return
            }
            let count = (summon.count ?? 1) > 1 ? "\(summon.count ?? 1) " : ""
            let name = summon.name.contains("-") || summon.name == summon.name.lowercased() ? GameText.titleCased(summon.name) : summon.name
            lines.append(CardLine(kind: .ability, text: "Summon \(count)\(name)", depth: depth, icon: .summon))
            var stats = ["HP \(summon.health.stringValue)"]
            if let move = summon.movement?.stringValue, move != "0" { stats.append("Move \(move)") }
            if let attack = summon.attack?.stringValue { stats.append("Attack \(attack)") }
            if let range = summon.range?.stringValue, range != "0" { stats.append("Range \(range)") }
            if summon.flying == true { stats.append("Flying") }
            lines.append(CardLine(kind: .detail, text: CardText.plain(stats.joined(separator: " · ")), depth: depth + 1))
            say(summon.traits, depth: depth + 1)
        }
    }

    /// The data's mark for a card half not written yet (three of the Beast Tyrant's cards).
    static let unwritten = "%character.abilities.wip%"

    /// A card the data doesn't have whole: the drawn card can't stand in for its scan.
    static func isUnwritten(_ card: AbilityModel) -> Bool {
        func has(_ actions: [ActionModel]) -> Bool {
            actions.contains { $0.value?.stringValue == unwritten || has($0.subActions ?? []) }
        }
        return has((card.actions ?? []) + (card.bottomActions ?? []))
    }

    // MARK: - Words

    /// "Attack 3", "Attack +1", "Move 4", "Suffer 2 damage", "Poison".
    static func title(_ action: ActionModel) -> String {
        let raw = plain(action.value?.stringValue ?? "")
        let sign: String
        switch action.valueType {
        case .plus, .add, .addition: sign = "+"
        case .minus, .subtract: sign = "−"
        default: sign = ""
        }
        let value = raw.isEmpty ? "" : " \(sign)\(raw)"
        switch action.type {
        case .attack: return "Attack\(value)"
        case .damage: return "Damage\(value)"
        case .move: return "Move\(value)"
        case .heal: return "Heal\(value)"
        case .shield: return "Shield\(value)"
        case .retaliate: return "Retaliate\(value)"
        case .loot: return "Loot\(value)"
        case .push: return "Push\(value)"
        case .pull: return "Pull\(value)"
        case .pierce: return "Pierce\(value)"
        case .range: return "Range\(value)"
        case .target: return "Target\(value)"
        case .teleport: return "Teleport\(value)"
        case .jump: return "Jump"
        case .fly: return "Flying"
        case .suffer, .sufferDamage: return "Suffer \(raw) damage"
        case .condition: return ConditionName(rawValue: raw).map(GameText.conditionName) ?? GameText.titleCased(raw)
        default: return GameText.actionTitle(action)
        }
    }

    /// "Earth", "Fire and Earth", "any element".
    static func elementNames(_ value: String) -> String {
        value.split(separator: ":").map { part in
            if part == "wild" { return "any element" }
            return ElementType(rawValue: String(part)).map(GameText.elementName) ?? GameText.titleCased(String(part))
        }.joined(separator: " and ")
    }

    /// Who a special target reaches: "Target all adjacent enemies", "Affect you and all allies
    /// within Range 4", "Self".
    static func target(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let instead = trimmed.hasSuffix(" instead") ? " instead" : ""
        let spec = trimmed.replacingOccurrences(of: " instead", with: "")
        switch spec {
        case "self": return "Self"
        case "enemiesMovedThrough": return "Target all enemies moved through"
        case "alliesEnemies": return "Target all allies and enemies"
        default: break
        }
        let withSelf = spec.hasPrefix("self")
        let rest = withSelf ? String(spec.dropFirst(4)).lowercasedFirst : spec
        let adjacent = rest.contains("Adjacent")
        let reach = rest.split(separator: ":").last.flatMap { Int($0.prefix(while: \.isNumber)) }
        let exact = rest.contains("RangeExact")
        let noun: String
        let verb: String
        if rest.hasPrefix("allies") { noun = adjacent ? "all adjacent allies" : "all allies"; verb = "Affect" }
        else if rest.hasPrefix("ally") { noun = adjacent ? "one adjacent ally" : "one ally"; verb = "Affect" }
        else if rest.hasPrefix("enemies") { noun = adjacent ? "all adjacent enemies" : "all enemies"; verb = "Target" }
        else if rest.hasPrefix("enemy") { noun = adjacent ? "one adjacent enemy" : "one enemy"; verb = "Target" }
        else { return GameText.titleCased(spec) + instead }
        let within = reach.map { exact ? " at exactly Range \($0)" : " within Range \($0)" } ?? ""
        return "\(verb) \(withSelf ? "you and " : "")\(noun)\(within)\(instead)"
    }

    /// The marks of a group: "Persistent · 4 uses, 2 with +1 XP · +2 XP · Lost".
    static func badge(_ marks: [ActionModel]) -> String? {
        var parts: [String] = []
        var uses = 0
        var xpUses: [Int] = []
        var lost = false
        for mark in marks {
            let value = mark.value?.stringValue ?? ""
            if mark.type == .experience { parts.append("+\(value.isEmpty ? "1" : value) XP"); continue }
            switch value {
            case "persistent": parts.append("Persistent")
            case "round": parts.append("Round bonus")
            case "lost": lost = true
            case "slot": uses += 1
            default:
                if value.hasPrefix("slotXp:") { uses += 1; xpUses.append(Int(value.dropFirst(7)) ?? 1) }
                else if value.hasPrefix("experience:") { parts.append("+\(value.dropFirst(11)) XP") }
                else if !value.isEmpty { parts.append(GameText.titleCased(value)) }
            }
        }
        if uses > 0 {
            let xp = xpUses.isEmpty ? "" : ", \(xpUses.count) with +\(xpUses.max() ?? 1) XP"
            parts.append("\(uses) \(uses == 1 ? "use" : "uses")\(xp)")
        }
        if lost { parts.append("Lost when used up") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The data's own words for a few of its marks.
    private static let marks = ["ondeath": "On death:", "advantage": "Advantage", "disadvantage": "Disadvantage"]

    /// Custom text without the data's markup ("%game.condition.poison%" → "Poison", "Shield1" →
    /// "Shield 1").
    static func plain(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "%game\\.[a-zA-Z]+\\.([a-zA-Z]+)(?::[^%]*)?%") else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), let name = Range(match.range(at: 1), in: text) else { continue }
            let word = String(text[name])
            result.replaceSubrange(range, with: marks[word.lowercased()] ?? GameText.titleCased(word))
        }
        result = result.replacingOccurrences(of: "<br>", with: " ")
        result = result.replacingOccurrences(of: "([a-z])([0-9])", with: "$1 $2", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
