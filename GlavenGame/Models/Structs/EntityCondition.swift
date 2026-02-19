import Foundation

struct EntityCondition: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: ConditionName
    var value: Int
    var state: EntityConditionState
    var permanent: Bool
    var expired: Bool
    var highlight: Bool

    enum CodingKeys: String, CodingKey {
        case name, value, state, permanent, expired, highlight
    }

    init(name: ConditionName, value: Int = 0, state: EntityConditionState = .new, permanent: Bool = false) {
        self.name = name
        self.value = value
        self.state = state
        self.permanent = permanent
        self.expired = false
        self.highlight = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(ConditionName.self, forKey: .name)
        value = try container.decodeIfPresent(Int.self, forKey: .value) ?? 0
        state = try container.decodeIfPresent(EntityConditionState.self, forKey: .state) ?? .new
        permanent = try container.decodeIfPresent(Bool.self, forKey: .permanent) ?? false
        expired = try container.decodeIfPresent(Bool.self, forKey: .expired) ?? false
        highlight = try container.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
    }

    var types: [ConditionType] {
        Condition.conditionTypes(for: name)
    }

    var isPositive: Bool { name.isPositive }
    var isNegative: Bool { name.isNegative }
}
