import Foundation

struct ScenarioData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(index)" }
    var index: String
    var name: String
    var edition: String
    var initial: Bool?
    var random: Bool?
    var solo: String?
    var spotlight: Bool?
    var conclusion: Bool?
    var repeatable: Bool?
    var named: Bool?
    var hideIndex: Bool?
    var spoiler: Bool?
    var complexity: Int?
    var level: Int?
    var group: String?
    var flowChartGroup: String?
    var parent: String?
    var eventType: String?
    var marker: String?
    var retirement: String?
    var errata: String?
    var monsters: [String]?
    var allies: [String]?
    var allied: [String]?
    var drawExtra: [String]?
    var rooms: [RoomData]?
    var objectives: [ObjectiveData]?
    var rules: [ScenarioRule]?
    var unlocks: [String]?
    var blocks: [String]?
    var requires: [[String]]?
    var requirements: [ScenarioRequirement]?
    var links: [String]?
    var forcedLinks: [String]?
    var parentSections: [[String]]?
    var blockedSections: [String]?
    var rewards: ScenarioRewards?
    var lootDeckConfig: LootDeckConfig?
    var resetRound: String?
    var allyDeck: Bool?
    var coordinates: WorldMapCoordinates?
    var overlays: [ScenarioOverlay]?

    var isConclusion: Bool { conclusion ?? false }
    var isInitial: Bool { initial ?? false }
    var isRepeatable: Bool { repeatable ?? false }
}

// MARK: - Room Data

struct RoomData: Codable, Hashable {
    var roomNumber: Int
    var ref: String?
    var initial: Bool?
    var marker: IntOrString?
    var rooms: [Int]?
    var treasures: [IntOrString]?
    var monster: [MonsterStandeeData]?
    var allies: [String]?
    var objectives: [IntOrString]?

    var isInitial: Bool { initial ?? false }

    var adjacentRooms: [Int] { rooms ?? [] }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomNumber = try container.decode(Int.self, forKey: .roomNumber)
        ref = try container.decodeIfPresent(String.self, forKey: .ref)
        marker = try container.decodeIfPresent(IntOrString.self, forKey: .marker)
        rooms = try container.decodeIfPresent([Int].self, forKey: .rooms)
        treasures = try container.decodeIfPresent([IntOrString].self, forKey: .treasures)
        monster = try container.decodeIfPresent([MonsterStandeeData].self, forKey: .monster)
        allies = try container.decodeIfPresent([String].self, forKey: .allies)
        objectives = try container.decodeIfPresent([IntOrString].self, forKey: .objectives)
        // initial can be Bool or String "true"/"false"
        if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .initial) {
            initial = boolVal
        } else if let strVal = try? container.decodeIfPresent(String.self, forKey: .initial) {
            initial = strVal.lowercased() == "true"
        } else {
            initial = nil
        }
    }
}

// MARK: - Monster Standee Data

struct MonsterStandeeData: Codable, Hashable {
    var name: String
    var marker: String?
    var tags: [String]?
    var type: String?       // "normal", "elite", "boss" — always spawns if present
    var player2: String?    // type for 2+ players
    var player3: String?    // type for 3+ players
    var player4: String?    // type for 4+ players
    var health: String?     // override health expression
    var number: Int?        // specific standee number

    func monsterType(forPlayerCount playerCount: Int) -> MonsterType? {
        if let type = type {
            return MonsterType(rawValue: type)
        }
        if playerCount >= 4, let p4 = player4 {
            return MonsterType(rawValue: p4)
        }
        if playerCount >= 3, let p3 = player3 {
            return MonsterType(rawValue: p3)
        }
        if playerCount >= 2, let p2 = player2 {
            return MonsterType(rawValue: p2)
        }
        return nil
    }
}

// MARK: - Objective Data

struct ObjectiveData: Codable, Hashable {
    var name: String?
    var health: IntOrString?
    var marker: String?
    var escort: Bool?
    var initiative: IntOrString?
    var tags: [String]?
    var allyDeck: Bool?
    var trackDamage: Bool?

    var isEscort: Bool { escort ?? false }
    var resolvedInitiative: Int {
        switch initiative {
        case .int(let v): return v
        case .string(let s): return Int(s) ?? 99
        case nil: return 99
        }
    }
}

// MARK: - Scenario Requirement

struct ScenarioRequirement: Codable, Hashable {
    var global: [String]?
    var party: [String]?
    var buildings: [String]?
    var campaignSticker: [String]?
    var puzzle: [String]?
    var characters: [String]?
    var scenarios: [[String]]?
}

// MARK: - Scenario Rewards

struct ScenarioRewards: Codable, Hashable {
    var globalAchievements: [String]?
    var partyAchievements: [String]?
    var lostPartyAchievements: [String]?
    var campaignSticker: [String]?
    var envelopes: [String]?
    var gold: IntOrString?
    var collectiveGold: IntOrString?
    var experience: IntOrString?
    var reputation: IntOrString?
    var prosperity: IntOrString?
    var perks: IntOrString?
    var morale: IntOrString?
    var inspiration: IntOrString?
    var items: [String]?
    var chooseItem: [[String]]?
    var itemDesigns: [String]?
    var chooseLocation: [String]?
    var randomItem: String?
    var randomItems: String?
    var itemBlueprints: [String]?
    var randomItemBlueprint: Int?
    var randomItemBlueprints: String?
    var events: [String]?
    var eventDecks: [String]?
    var removeEvents: [String]?
    var resources: [ResourceReward]?
    var collectiveResources: [ResourceReward]?
    var lootDeckCards: [Int]?
    var removeLootDeckCards: [Int]?
    var townGuardAm: [String]?
    var unlockCharacter: String?
    var chooseUnlockCharacter: [String]?
    var calendarSection: [String]?
    var calendarSectionConditional: [String]?
    var calendarSectionManual: [CalendarSectionManual]?
    var calendarIgnore: Bool?
    var lootingGold: IntOrString?
    var reputationFactions: [String]?
    var factionUnlock: String?
    var battleGoals: Int?
    var pet: String?
    var repeatScenario: Bool?
    var randomSideScenario: Int?
    var custom: String?
    var ignoredBonus: [String]?
    var overlaySticker: WorldMapOverlay?
    var overlayCampaignSticker: WorldMapOverlay?
}

struct ResourceReward: Codable, Hashable {
    var type: String
    var value: IntOrString
}

struct CalendarSectionManual: Codable, Hashable {
    var section: String
    var hint: String?
}

// MARK: - World Map Coordinates

struct WorldMapCoordinates: Codable, Hashable {
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?
    var gridLocation: String?
    var image: String?
}

// MARK: - World Map Overlay

struct WorldMapOverlay: Codable, Hashable {
    var name: String = ""
    var location: String = ""
    var coordinates: WorldMapCoordinates = WorldMapCoordinates()
}

// MARK: - Scenario Overlay

struct ScenarioOverlay: Codable, Hashable {
    var type: String?
    var value: String?
    var values: [IntOrString]?
    var count: Int?
    var marker: IntOrString?
}

// MARK: - Loot Deck Config

struct LootDeckConfig: Codable, Hashable {
    // Loot deck configuration — counts per type
    var lumber: Int?
    var metal: Int?
    var hide: Int?
    var arrowvine: Int?
    var axenut: Int?
    var corpsecap: Int?
    var flamefruit: Int?
    var rockroot: Int?
    var snowthistle: Int?
    var coin1: Int?
    var coin2: Int?
    var coin3: Int?
    var random: Int?
    var special1: Int?
    var special2: Int?
}
