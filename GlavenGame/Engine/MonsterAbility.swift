import Foundation

/// A monster attack, resolved from one Attack action on its ability card combined with the
/// monster's stat card (GH p.29–31).
struct MonsterAttackSpec: Equatable {
    /// Final attack value (never below 0 — an Attack 0 still draws a modifier).
    var value: Int
    /// Attack range; 1 for melee.
    var range: Int
    var isRanged: Bool
    var targetCount: Int
    var pierce: Int
    var push: Int
    var pull: Int
    /// Conditions applied to every target (card sub-actions + stat-card attack effects).
    var conditions: [ConditionName]
    /// Area-of-effect pattern string, if any.
    var area: String?
    /// The monster attacks with advantage (stat-card "advantage" trait, e.g. Sun Demon).
    var advantage: Bool
    /// "Target all enemies within N" (all adjacent enemies = 1) instead of focus + Target N.
    var allEnemiesWithin: Int? = nil
    /// "Target one enemy with all attacks": every one of the Target N attacks hits the focus.
    var allAttacksOnFocus: Bool = false
}

/// Movement granted by a Move action on a monster ability card.
struct MonsterMoveSpec: Equatable {
    var value: Int
    var jump: Bool
}

/// Pure parsing helpers for monster ability cards.
enum MonsterAbility {

    /// The signed "+X"/"-X" modifier carried by a card value.
    static func signedValue(_ action: ActionModel) -> Int {
        let v = action.value?.intValue ?? 0
        switch action.valueType {
        case .minus, .subtract: return -v
        default: return v
        }
    }

    /// Elements an element action refers to ("fire", "fire:earth", "wild").
    static func elements(of action: ActionModel) -> [ElementType] {
        guard action.type == .element, let raw = action.value?.stringValue else { return [] }
        return raw.split(separator: ":").compactMap { ElementType(rawValue: String($0)) }
    }

    static func isConsume(_ action: ActionModel) -> Bool {
        action.type == .element && (action.valueType == .minus || action.valueType == .subtract)
    }

    /// All element-consume actions anywhere in the card (top-level or nested under an attack/heal).
    static func elementConsumes(in actions: [ActionModel]) -> [ActionModel] {
        var result: [ActionModel] = []
        for action in actions {
            if isConsume(action) { result.append(action) }
            result.append(contentsOf: elementConsumes(in: action.subActions ?? []))
        }
        return result
    }

    /// The consumes that belong to one ability (printed under an attack, a heal, a shield…): paid
    /// only when that ability is performed (FAQ).
    static func attachedConsumes(of action: ActionModel) -> [ActionModel] {
        guard !isConsume(action) else { return [] }
        return elementConsumes(in: action.subActions ?? [])
    }

    /// A card's actions with its groupings opened: a `grid` or `box` only lays abilities out
    /// side by side, and a `concatenation` of abilities ("…and…") is those abilities in order.
    /// A consume printed beside an attack to change it (the Wind Demon's "Air: +1 Attack" and a
    /// larger area) becomes that attack's own.
    static func flattened(_ actions: [ActionModel]) -> [ActionModel] {
        var result: [ActionModel] = []
        for action in actions {
            guard isGrouping(action) else {
                result.append(action)
                continue
            }
            var members: [ActionModel] = []
            for member in flattened(action.subActions ?? []) {
                if isConsume(member), let last = members.indices.last, members[last].type == .attack,
                   !(member.subActions ?? []).isEmpty,
                   (member.subActions ?? []).allSatisfy({ $0.type == .attack && ($0.valueType == .add || $0.valueType == .subtract) }) {
                    members[last].subActions = (members[last].subActions ?? []) + [member]
                } else {
                    members.append(member)
                }
            }
            result += members
        }
        return result
    }

    /// Whether an action only groups others. A concatenation that names whom it affects (or only
    /// lists conditions, pushes and pulls) is one ability: "Wound and Poison all adjacent enemies".
    static func isGrouping(_ action: ActionModel) -> Bool {
        switch action.type {
        case .grid, .box, .forceBox, .boxFhSubActions:
            return true
        case .concatenation:
            return !(action.subActions ?? []).allSatisfy { [.condition, .push, .pull, .specialTarget].contains($0.type) }
        default:
            return false
        }
    }

    // MARK: - Whom an ability affects

    /// The figures a `specialTarget` names: "self", "enemiesAdjacent", "enemiesRange:3",
    /// "enemyAdjacent", "alliesAdjacentAffect", "alliesRange:3", "selfAlliesRange:2",
    /// "selfAlliesAffect", "enemies"…
    struct Affected: Equatable {
        enum Side { case enemies, allies }
        /// The monster itself is among them.
        var includesSelf = false
        /// Enemies or allies; nil when it is the monster alone.
        var side: Side?
        /// How far they may be; nil for every one of them on the map ("all enemies").
        var range: Int?
        /// One figure only ("target one adjacent enemy").
        var onlyOne = false
    }

    /// - Parameter baseRange: the range used when the text says "within range" without a number.
    static func affected(by specialTarget: String?, baseRange: Int) -> Affected {
        let raw = (specialTarget ?? "self").lowercased()
        var result = Affected(includesSelf: raw.hasPrefix("self"))
        let others = result.includesSelf ? String(raw.dropFirst(4)) : raw
        if others.hasPrefix("enem") {
            result.side = .enemies
        } else if others.hasPrefix("all") {
            result.side = .allies
        } else {
            result.includesSelf = true
            return result
        }
        result.onlyOne = others.hasPrefix("enemyadjacent") || others.hasPrefix("allyadjacent")
        if others.contains("adjacent") {
            result.range = 1
        } else if let colon = others.firstIndex(of: ":") {
            result.range = Int(others[others.index(after: colon)...]) ?? max(1, baseRange)
        } else if others.contains("range") {
            result.range = max(1, baseRange)
        }
        return result
    }

    // MARK: - What the turn performs

    /// A monster's allies add to their attacks this round (the Captain of the Guard's special):
    /// kept on each of them as a tag, "roundAttack:1", until the round ends.
    static let roundAttackTag = "roundAttack:"

    /// The kinds of action a monster's turn performs when they stand on a card (or in a boss
    /// special) as an ability of their own. Anything else would silently do nothing.
    static let performedKinds: Set<ActionType> = [
        .move, .attack, .heal, .teleport, .condition, .push, .pull, .concatenation, .element,
        .sufferDamage, .suffer, .loot, .summon, .shield, .retaliate, .custom, .special,
        .grid, .box, .forceBox, .boxFhSubActions,
        // Shown only: a note for the players.
        .hint
    ]

    /// What may be printed under an ability and is taken into account when it is performed.
    private static func performedParts(of kind: ActionType) -> Set<ActionType> {
        switch kind {
        case .attack:
            return [.attack, .range, .target, .pierce, .push, .pull, .condition, .area, .specialTarget,
                    .element, .concatenation, .custom, .summon]
        case .move: return [.jump, .custom]
        case .heal: return [.heal, .range, .target, .specialTarget, .element]
        case .shield, .retaliate: return [kind, .range, .specialTarget, .element, .custom]
        case .condition, .push, .pull: return [kind, .specialTarget, .element, .custom]
        case .summon: return [.custom]
        case .custom, .grid, .box, .forceBox, .boxFhSubActions: return performedKinds.union([.specialTarget])
        default: return []
        }
    }

    /// Every action on a card the monster's turn would not perform, as a path for a message
    /// ("grid > swing"). Empty when the whole card is carried out.
    static func unperformed(in actions: [ActionModel]) -> [String] {
        func check(_ action: ActionModel, allowed: Set<ActionType>, ability: ActionType?, path: String) -> [String] {
            let here = path.isEmpty ? action.type.rawValue : "\(path) > \(action.type.rawValue)"
            guard allowed.contains(action.type) else { return [here] }
            // A summon the data doesn't spell out as monsters (an objective, "a demon").
            if action.type == .summon && action.monsterSummons == nil { return [here] }
            var parts: Set<ActionType>
            var inner = ability
            switch action.type {
            case .element where isConsume(action):
                // Under an ability a consume changes that ability; on its own it holds abilities.
                parts = ability.map(performedParts) ?? performedKinds.union([.specialTarget])
            case .element:
                parts = []
            case .concatenation:
                parts = ability.map(performedParts) ?? performedKinds.union([.specialTarget])
            case .attack where ability == .attack:
                parts = performedParts(of: .attack)   // "+1 Attack" and what comes with it
            default:
                parts = performedParts(of: action.type)
                inner = [.custom, .grid, .box, .forceBox, .boxFhSubActions].contains(action.type) ? nil : action.type
            }
            return (action.subActions ?? []).flatMap { check($0, allowed: parts, ability: inner, path: here) }
        }
        return actions.flatMap { check($0, allowed: performedKinds, ability: nil, path: "") }
    }

    /// Element infusions of a card: top-level infusions, plus infusions inside element-consume
    /// blocks that were paid for (e.g. "any element: infuse fire").
    static func elementInfusions(in actions: [ActionModel], consumed: Set<UUID> = []) -> [ElementType] {
        var result: [ElementType] = []
        for action in actions where action.type == .element {
            if !isConsume(action) {
                result.append(contentsOf: elements(of: action))
            } else if consumed.contains(action.id) {
                result.append(contentsOf: elementInfusions(in: action.subActions ?? [], consumed: consumed))
            }
        }
        return result
    }

    /// The Move granted by the card, or nil when the card has no Move (the monster then does not
    /// move at all — GH p.30: "they do not move or attack unless these actions are on their card").
    static func move(in actions: [ActionModel], baseMove: Int) -> MonsterMoveSpec? {
        guard let move = actions.first(where: { $0.type == .move }) else { return nil }
        let value = move.valueType == .fixed ? (move.value?.intValue ?? 0) : baseMove + signedValue(move)
        let jump = (move.subActions ?? []).contains { $0.type == .jump }
        return MonsterMoveSpec(value: max(0, value), jump: jump)
    }

    /// Resolve one Attack action against the stat card.
    /// - Parameters:
    ///   - consumed: ids of the element-consume actions this monster type paid for this turn;
    ///     a matching consume block under the attack adds its bonuses.
    static func attack(_ action: ActionModel, stat: MonsterStatModel?, baseAttack: Int, baseRange: Int,
                       consumed: Set<UUID> = []) -> MonsterAttackSpec {
        var range = baseRange
        var value = action.valueType == .fixed ? (action.value?.intValue ?? 0) : baseAttack + signedValue(action)
        var cardSpecifiesRange = false
        var targetCount = 1
        var pierce = 0
        var push = 0
        var pull = 0
        var conditions: [ConditionName] = []
        var area: String?
        var advantage = false
        var specialTarget: String?

        func apply(_ sub: ActionModel) {
            switch sub.type {
            case .attack:
                // "+1 Attack", and what is printed with it (a larger area).
                value += signedValue(sub)
                for inner in sub.subActions ?? [] { apply(inner) }
            case .range:
                // A card range with no sign sets the range; "+X"/"-X" modifies the base range.
                cardSpecifiesRange = true
                if sub.valueType == nil || sub.valueType == .fixed {
                    range = sub.value?.intValue ?? 0
                } else {
                    range += signedValue(sub)
                }
            case .target:
                targetCount = max(targetCount, sub.value?.intValue ?? 1)
                if sub.valueType == .plus || sub.valueType == .add { targetCount = 1 + (sub.value?.intValue ?? 0) }
            case .pierce:
                pierce += sub.value?.intValue ?? 0
            case .push:
                push += sub.value?.intValue ?? 0
            case .pull:
                pull += sub.value?.intValue ?? 0
            case .condition:
                if let name = sub.value?.stringValue, let condition = ConditionName(rawValue: name),
                   !conditions.contains(condition) {
                    conditions.append(condition)
                }
            case .area:
                if let pattern = sub.value?.stringValue, !pattern.isEmpty { area = pattern }
            case .specialTarget:
                specialTarget = sub.value?.stringValue
            case .element where isConsume(sub):
                if consumed.contains(sub.id) {
                    for bonus in sub.subActions ?? [] { apply(bonus) }
                }
            case .concatenation:
                for inner in sub.subActions ?? [] { apply(inner) }
            default:
                break
            }
        }

        for sub in action.subActions ?? [] { apply(sub) }

        // Stat-card attack effects apply to every attack the monster makes.
        for statAction in stat?.actions ?? [] {
            switch statAction.type {
            case .condition, .pierce, .push, .pull:
                apply(statAction)
            case .target:
                targetCount = max(targetCount, statAction.value?.intValue ?? 1)
            case .custom:
                if statAction.value?.stringValue == "%game.custom.advantage%" { advantage = true }
            default:
                break
            }
        }

        // An attack is ranged when the monster has a base range or the card gives it one; for an
        // area attack the pattern decides (a pattern including the attacker's hex is melee).
        let isRanged = area.map { !AoEResolver.isMeleePattern($0) } ?? (baseRange > 0 || cardSpecifiesRange)
        // A melee area reaches as far as its pattern does, whatever the monster's base range.
        if let area, AoEResolver.isMeleePattern(area) {
            range = max(1, AoEResolver.parsePattern(area).filter(\.isTarget)
                .map { max(abs($0.cubeX), abs($0.cubeY), abs($0.cubeZ)) }.max() ?? 1)
        }
        var spec = MonsterAttackSpec(value: max(0, value), range: max(1, range), isRanged: isRanged,
                                     targetCount: targetCount, pierce: pierce, push: push, pull: pull,
                                     conditions: conditions, area: area, advantage: advantage)
        if let special = specialTarget?.lowercased() {
            if special.hasPrefix("enemiesadjacent") {
                spec.allEnemiesWithin = 1
                spec.range = 1
                spec.isRanged = false
            } else if special.hasPrefix("enemiesrange") {
                let n = Int(special.split(separator: ":").last ?? "") ?? spec.range
                spec.allEnemiesWithin = max(1, n)
                spec.range = max(1, n)
            } else if special == "enemyoneall" {
                spec.allAttacksOnFocus = true
            }
        }
        return spec
    }

    /// Whether the card has at least one Attack action.
    static func hasAttack(_ actions: [ActionModel]) -> Bool {
        actions.contains { $0.type == .attack }
    }
}
