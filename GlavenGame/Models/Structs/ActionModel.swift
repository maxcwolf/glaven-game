import Foundation

/// Lightweight summon stats decoded from a summon action's `valueObject` JSON key.
/// Separate from `SummonDataModel` to avoid recursive struct (SummonDataModel contains ActionModel).
struct SummonValueObject: Codable, Hashable {
    var name: String
    var health: IntOrString
    var attack: IntOrString?
    var movement: IntOrString?
    var range: IntOrString?
    var flying: Bool?
    var level: Int?
    var count: Int?

    /// Convert to `SummonDataModel` for use with `CharacterManager.addSummon`.
    func toSummonData() -> SummonDataModel {
        var data = SummonDataModel(name: name, health: health)
        data.attack = attack
        data.movement = movement
        data.range = range
        data.flying = flying
        data.level = level
        data.count = count
        return data
    }
}

struct ActionModel: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: ActionType
    var value: IntOrString?
    var valueType: ActionValueType?
    var subActions: [ActionModel]?
    var small: Bool?
    var hidden: Bool?
    var enhancementTypes: [EnhancementSlotType]?
    /// Embedded summon stats from `valueObject` JSON key (character summon cards).
    var summonValueObject: SummonValueObject?
    /// Monsters summoned by a monster ability (`valueObject: [{"monster": {...}}]`).
    var monsterSummons: [MonsterSummonSpec]?

    enum CodingKeys: String, CodingKey {
        case type, value, valueType, subActions, small, hidden, enhancementTypes, valueObject
    }

    init(type: ActionType, value: IntOrString? = nil, valueType: ActionValueType? = nil, subActions: [ActionModel]? = nil, small: Bool? = nil, hidden: Bool? = nil, enhancementTypes: [EnhancementSlotType]? = nil) {
        self.type = type
        self.value = value
        self.valueType = valueType
        self.subActions = subActions
        self.small = small
        self.hidden = hidden
        self.enhancementTypes = enhancementTypes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(ActionType.self, forKey: .type)
        value = try container.decodeIfPresent(IntOrString.self, forKey: .value)
        valueType = try container.decodeIfPresent(ActionValueType.self, forKey: .valueType)
        subActions = try container.decodeIfPresent([ActionModel].self, forKey: .subActions)
        small = try container.decodeIfPresent(Bool.self, forKey: .small)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        enhancementTypes = try container.decodeIfPresent([EnhancementSlotType].self, forKey: .enhancementTypes)
        // Decode valueObject as SummonValueObject (single object for character summons).
        // Silently ignore arrays (monster summon format) or missing keys.
        summonValueObject = try? container.decodeIfPresent(SummonValueObject.self, forKey: .valueObject)
        monsterSummons = (try? container.decodeIfPresent([MonsterSummonSpec.Wrapper].self, forKey: .valueObject))?
            .map { entry in
                var spec = entry.monster
                spec.count = entry.count ?? spec.count
                return spec
            }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(valueType, forKey: .valueType)
        try container.encodeIfPresent(subActions, forKey: .subActions)
        try container.encodeIfPresent(small, forKey: .small)
        try container.encodeIfPresent(hidden, forKey: .hidden)
        try container.encodeIfPresent(enhancementTypes, forKey: .enhancementTypes)
        if let monsterSummons {
            try container.encode(monsterSummons.map { MonsterSummonSpec.Wrapper(monster: $0, count: $0.count) },
                                 forKey: .valueObject)
        } else {
            try container.encodeIfPresent(summonValueObject, forKey: .valueObject)
        }
    }
}

/// A monster placed by a monster's Summon ability (e.g. Cultist → Living Bones).
struct MonsterSummonSpec: Codable, Hashable {
    var name: String
    var type: MonsterType?
    var player2: MonsterType?
    var player3: MonsterType?
    var player4: MonsterType?
    var health: IntOrString?
    /// How many are summoned (the data writes it beside the monster); one when absent.
    var count: Int?

    struct Wrapper: Codable, Hashable {
        var monster: MonsterSummonSpec
        var count: Int?
    }

    /// Normal or elite for the given character count, or nil when this entry isn't for that
    /// count: a boss's summon lists one entry per player count ("two normal for two characters,
    /// one of each for three…"), and only those written for the count at the table are summoned.
    func type(forPlayerCount count: Int) -> MonsterType? {
        if let type { return type }
        switch count {
        case ...2: return player2
        case 3: return player3
        default: return player4
        }
    }

    /// What this entry summons for the given character count: `count` of its type, or nothing.
    func summoned(forPlayerCount players: Int) -> [MonsterType] {
        guard let type = type(forPlayerCount: players) else { return [] }
        return Array(repeating: type, count: max(1, count ?? 1))
    }
}
