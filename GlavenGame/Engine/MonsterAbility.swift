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
                value += signedValue(sub)
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
