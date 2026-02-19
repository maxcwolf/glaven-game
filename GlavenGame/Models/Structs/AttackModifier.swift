import Foundation

struct AttackModifier: Codable, Hashable, Identifiable {
    var id: String
    var type: AttackModifierType
    var value: Int
    var valueType: AttackModifierValueType
    var effects: [AttackModifierEffect]
    var rolling: Bool
    var shuffle: Bool
    var active: Bool
    var revealed: Bool
    var character: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, value, valueType, effects, rolling, shuffle, active, revealed, character
    }

    init(id: String = UUID().uuidString, type: AttackModifierType, value: Int = 0,
         valueType: AttackModifierValueType = .default, effects: [AttackModifierEffect] = [],
         rolling: Bool = false, shuffle: Bool = false, active: Bool = false,
         revealed: Bool = false, character: Bool = false) {
        self.id = id
        self.type = type
        self.value = value
        self.valueType = valueType
        self.effects = effects
        self.rolling = rolling
        self.shuffle = shuffle
        self.active = active
        self.revealed = revealed
        self.character = character
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try container.decode(AttackModifierType.self, forKey: .type)
        self.value = try container.decodeIfPresent(Int.self, forKey: .value) ?? 0
        self.valueType = try container.decodeIfPresent(AttackModifierValueType.self, forKey: .valueType) ?? .default
        self.effects = try container.decodeIfPresent([AttackModifierEffect].self, forKey: .effects) ?? []
        self.rolling = try container.decodeIfPresent(Bool.self, forKey: .rolling) ?? false
        self.shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        self.active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
        self.revealed = try container.decodeIfPresent(Bool.self, forKey: .revealed) ?? false
        self.character = try container.decodeIfPresent(Bool.self, forKey: .character) ?? false
    }

    var displayText: String {
        switch type {
        case .bless: return "x2"
        case .curse: return "x0"
        case .double_: return "x2"
        case .null_: return "MISS"
        default:
            if valueType == .multiply {
                return "x\(value)"
            }
            return value >= 0 ? "+\(value)" : "\(value)"
        }
    }

    static func defaultMonsterDeck() -> [AttackModifier] {
        var deck: [AttackModifier] = []
        // 6x +0
        for _ in 0..<6 { deck.append(AttackModifier(type: .plus0)) }
        // 5x +1
        for _ in 0..<5 { deck.append(AttackModifier(type: .plus1, value: 1)) }
        // 5x -1
        for _ in 0..<5 { deck.append(AttackModifier(type: .minus1, value: -1)) }
        // 1x +2
        deck.append(AttackModifier(type: .plus2, value: 2))
        // 1x -2
        deck.append(AttackModifier(type: .minus2, value: -2))
        // 1x x2 (double)
        deck.append(AttackModifier(type: .double_, value: 2, valueType: .multiply, shuffle: true))
        // 1x x0 (null/miss)
        deck.append(AttackModifier(type: .null_, value: 0, valueType: .multiply, shuffle: true))
        return deck
    }
}
