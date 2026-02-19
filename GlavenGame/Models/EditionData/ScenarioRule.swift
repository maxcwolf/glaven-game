import Foundation

/// Treasures can be either an array of IntOrString or a single string
enum TreasuresValue: Codable, Hashable {
    case array([IntOrString])
    case single(String)

    var items: [IntOrString] {
        switch self {
        case .array(let arr): return arr
        case .single(let s): return [.string(s)]
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([IntOrString].self) {
            self = .array(arr)
        } else if let str = try? container.decode(String.self) {
            self = .single(str)
        } else {
            throw DecodingError.typeMismatch(TreasuresValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected array or string for treasures"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let arr): try container.encode(arr)
        case .single(let s): try container.encode(s)
        }
    }
}

struct ScenarioRule: Codable, Hashable {
    var round: String?
    var start: Bool?
    var always: Bool?
    var once: Bool?
    var alwaysApply: Bool?
    var alwaysApplyTurn: String?    // "turn", "after"
    var requiredRooms: [Int]?
    var requiredRules: [ScenarioRuleIdentifier]?
    var disablingRules: [ScenarioRuleIdentifier]?
    var requiredScenarios: [String]?
    var note: String?
    var noteTop: String?
    var rooms: [Int]?
    var sections: [String]?
    var figures: [ScenarioFigureRule]?
    var spawns: [MonsterSpawnData]?
    var objectiveSpawns: [ObjectiveSpawnData]?
    var elements: [ElementRuleData]?
    var elementTrigger: [ElementRuleData]?
    var treasures: TreasuresValue?
    var disableRules: [ScenarioRuleIdentifier]?
    var randomDungeon: RandomDungeonRule?
    var statEffects: [StatEffectRule]?
    var finish: String?             // "won", "lost", "round"

    var isAlways: Bool { always ?? false }
    var isOnce: Bool { once ?? false }
    var isStart: Bool { start ?? false }

    private enum CodingKeys: String, CodingKey {
        case round, start, always, once, alwaysApply, alwaysApplyTurn
        case requiredRooms, requiredRules, disablingRules, requiredScenarios
        case note, noteTop, rooms, sections, figures, spawns, objectiveSpawns
        case elements, elementTrigger, treasures, disableRules, randomDungeon
        case statEffects, finish
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        round = try c.decodeIfPresent(String.self, forKey: .round)
        alwaysApplyTurn = try c.decodeIfPresent(String.self, forKey: .alwaysApplyTurn)
        requiredRooms = try c.decodeIfPresent([Int].self, forKey: .requiredRooms)
        requiredRules = try c.decodeIfPresent([ScenarioRuleIdentifier].self, forKey: .requiredRules)
        disablingRules = try c.decodeIfPresent([ScenarioRuleIdentifier].self, forKey: .disablingRules)
        requiredScenarios = try c.decodeIfPresent([String].self, forKey: .requiredScenarios)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        noteTop = try c.decodeIfPresent(String.self, forKey: .noteTop)
        rooms = try c.decodeIfPresent([Int].self, forKey: .rooms)
        sections = try c.decodeIfPresent([String].self, forKey: .sections)
        figures = try c.decodeIfPresent([ScenarioFigureRule].self, forKey: .figures)
        spawns = try c.decodeIfPresent([MonsterSpawnData].self, forKey: .spawns)
        objectiveSpawns = try c.decodeIfPresent([ObjectiveSpawnData].self, forKey: .objectiveSpawns)
        elements = try c.decodeIfPresent([ElementRuleData].self, forKey: .elements)
        elementTrigger = try c.decodeIfPresent([ElementRuleData].self, forKey: .elementTrigger)
        treasures = try c.decodeIfPresent(TreasuresValue.self, forKey: .treasures)
        disableRules = try c.decodeIfPresent([ScenarioRuleIdentifier].self, forKey: .disableRules)
        randomDungeon = try c.decodeIfPresent(RandomDungeonRule.self, forKey: .randomDungeon)
        statEffects = try c.decodeIfPresent([StatEffectRule].self, forKey: .statEffects)
        finish = try c.decodeIfPresent(String.self, forKey: .finish)
        // Bool fields that can appear as strings "true"/"false" in JSON
        start = Self.decodeBool(c, key: .start)
        always = Self.decodeBool(c, key: .always)
        once = Self.decodeBool(c, key: .once)
        alwaysApply = Self.decodeBool(c, key: .alwaysApply)
    }

    private static func decodeBool(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Bool? {
        if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s.lowercased() == "true" }
        return nil
    }
}

// MARK: - Rule Identifier

struct ScenarioRuleIdentifier: Codable, Hashable {
    var edition: String?
    var scenario: String?
    var index: Int?
    var section: Bool?
}

// MARK: - Figure Rule

struct ScenarioFigureRule: Codable, Hashable {
    var identifier: ScenarioFigureRuleIdentifier?
    var type: String?               // "amAdd", "present", "dead", "damage", "heal", "setHp", "remove", etc.
    var value: IntOrString?
    var scenarioEffect: Bool?
}

struct ScenarioFigureRuleIdentifier: Codable, Hashable {
    var type: String?               // "character", "characterWithSummon", "objective", "monster"
    var name: String?               // regex pattern or exact name
    var marker: String?
    var edition: String?
    var tags: [String]?
    var health: String?             // health condition expression
    var hp: String?                 // hp condition
}

// MARK: - Monster Spawn Data

struct MonsterSpawnData: Codable, Hashable {
    var monster: MonsterStandeeData
    var count: IntOrString?
    var marker: String?
    var summon: Bool?
    var manual: Bool?
    var manualMin: Int?
    var manualMax: Int?

    var resolvedCount: Int {
        switch count {
        case .int(let v): return v
        case .string(let s): return Int(s) ?? 1
        case nil: return 1
        }
    }
    var isSummon: Bool { summon ?? false }
    var isManual: Bool { manual ?? false }
}

// MARK: - Objective Spawn Data

struct ObjectiveSpawnData: Codable, Hashable {
    var objective: ObjectiveData
    var count: IntOrString?
    var marker: String?

    var resolvedCount: Int {
        switch count {
        case .int(let v): return v
        case .string(let s): return Int(s) ?? 1
        case nil: return 1
        }
    }
}

// MARK: - Element Rule Data

struct ElementRuleData: Codable, Hashable {
    var type: String?               // element type name
    var state: String?              // element state name
}

// MARK: - Random Dungeon Rule

struct RandomDungeonRule: Codable, Hashable {
    var monsterCount: Int?
    var monsterCards: [String]?
    var dungeonCount: Int?
    var dungeonCards: [String]?
    var initial: Bool?
}

// MARK: - Stat Effect Rule

struct StatEffectRule: Codable, Hashable {
    var name: String?               // monster name
    var type: String?               // "normal", "elite", "boss"
    var stat: String?               // stat to modify: "health", "attack", "movement", "range"
    var value: IntOrString?
}
