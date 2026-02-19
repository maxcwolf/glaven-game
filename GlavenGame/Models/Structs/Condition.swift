import Foundation

struct Condition: Codable, Hashable {
    var name: ConditionName
    var value: Int

    init(name: ConditionName, value: Int = 0) {
        self.name = name
        self.value = value
    }

    var types: [ConditionType] {
        Condition.conditionTypes(for: name)
    }

    static func conditionTypes(for name: ConditionName) -> [ConditionType] {
        switch name {
        case .stun:
            return [.standard, .negative, .turn, .entity]
        case .immobilize:
            return [.standard, .negative, .afterTurn, .entity]
        case .disarm:
            return [.standard, .negative, .afterTurn, .entity]
        case .wound:
            return [.standard, .negative, .apply, .entity]
        case .muddle:
            return [.standard, .negative, .afterTurn, .entity]
        case .poison:
            return [.standard, .negative, .entity]
        case .invisible:
            return [.standard, .positive, .afterTurn, .entity]
        case .strengthen:
            return [.standard, .positive, .afterTurn, .entity]
        case .curse:
            return [.standard, .negative, .amDeck]
        case .bless:
            return [.standard, .positive, .amDeck]
        case .regenerate:
            return [.standard, .positive, .apply, .entity]
        case .ward:
            return [.standard, .positive, .entity]
        case .brittle:
            return [.standard, .negative, .entity]
        case .bane:
            return [.standard, .negative, .afterTurn, .entity]
        case .impair:
            return [.standard, .negative, .afterTurn, .entity]
        case .dodge:
            return [.standard, .positive, .afterTurn, .entity]
        case .chill:
            return [.standard, .negative, .entity, .stackable]
        case .infect:
            return [.standard, .negative, .entity]
        case .rupture:
            return [.standard, .negative, .entity]
        case .empower:
            return [.standard, .positive, .amDeck]
        case .safeguard:
            return [.standard, .positive, .afterTurn, .entity]
        case .enfeeble:
            return [.standard, .negative, .amDeck]
        case .shield:
            return [.special, .entity]
        case .heal:
            return [.special, .clearHeal]
        case .retaliate:
            return [.special, .entity]
        case .plague:
            return [.negative, .entity]
        case .poison_x:
            return [.negative, .entity, .stack]
        case .wound_x:
            return [.negative, .entity, .stack]
        case .push, .pull:
            return [.special]
        }
    }
}
