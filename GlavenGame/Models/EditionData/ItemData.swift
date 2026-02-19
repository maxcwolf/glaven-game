import Foundation

struct ItemData: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var cost: Int
    var count: Int
    var edition: String
    var slot: ItemSlot
    var spent: Bool
    var consumed: Bool
    var minusOne: Int
    var slots: Int
    var unlockProsperity: Int
    var unlockScenario: String?
    var random: Bool
    var actions: [ActionModel]?
    var effects: [ActionModel]?
    var summon: SummonDataModel?
    var resources: [String: Int]?
    var resourcesAny: [[String: Int]]?
    var requiredBuilding: String?
    var requiredBuildingLevel: Int?
    var requiredItems: [Int]?

    enum CodingKeys: String, CodingKey {
        case id, name, cost, count, edition, slot, spent, consumed, minusOne, slots
        case unlockProsperity, unlockScenario, random, actions, effects, summon
        case resources, resourcesAny, requiredBuilding, requiredBuildingLevel, requiredItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cost = try container.decodeIfPresent(Int.self, forKey: .cost) ?? 0
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        edition = try container.decodeIfPresent(String.self, forKey: .edition) ?? ""
        slot = try container.decodeIfPresent(ItemSlot.self, forKey: .slot) ?? .small
        spent = try container.decodeIfPresent(Bool.self, forKey: .spent) ?? false
        consumed = try container.decodeIfPresent(Bool.self, forKey: .consumed) ?? false
        minusOne = try container.decodeIfPresent(Int.self, forKey: .minusOne) ?? 0
        slots = try container.decodeIfPresent(Int.self, forKey: .slots) ?? 1
        unlockProsperity = try container.decodeIfPresent(Int.self, forKey: .unlockProsperity) ?? 0
        // unlockScenario can be a String or a dictionary like {"name": 2, "edition": "jotl"}
        if let str = try? container.decodeIfPresent(String.self, forKey: .unlockScenario) {
            unlockScenario = str
        } else if let dict = try? container.decodeIfPresent([String: IntOrString].self, forKey: .unlockScenario) {
            let edition = dict["edition"]?.stringValue ?? ""
            let name = dict["name"]?.stringValue ?? ""
            unlockScenario = "\(edition)-\(name)"
        } else {
            unlockScenario = nil
        }
        random = try container.decodeIfPresent(Bool.self, forKey: .random) ?? false
        actions = try container.decodeIfPresent([ActionModel].self, forKey: .actions)
        effects = try container.decodeIfPresent([ActionModel].self, forKey: .effects)
        summon = try container.decodeIfPresent(SummonDataModel.self, forKey: .summon)
        resources = try container.decodeIfPresent([String: Int].self, forKey: .resources)
        resourcesAny = try container.decodeIfPresent([[String: Int]].self, forKey: .resourcesAny)
        requiredBuilding = try container.decodeIfPresent(String.self, forKey: .requiredBuilding)
        requiredBuildingLevel = try container.decodeIfPresent(Int.self, forKey: .requiredBuildingLevel)
        requiredItems = try container.decodeIfPresent([Int].self, forKey: .requiredItems)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(edition)
    }

    static func == (lhs: ItemData, rhs: ItemData) -> Bool {
        lhs.id == rhs.id && lhs.edition == rhs.edition
    }

    /// Display key like "gh-001"
    var itemKey: String {
        "\(edition)-\(id)"
    }

    /// Whether this item is available at a given prosperity level
    func availableAtProsperity(_ level: Int) -> Bool {
        !random && unlockProsperity <= level && unlockScenario == nil
    }

    /// Whether this is a brewable item (requires alchemist building).
    var isBrewable: Bool {
        requiredBuilding == "alchemist" && (resources != nil || resourcesAny != nil)
    }

    /// Herb resources needed to brew this item.
    var herbResources: [String: Int] {
        resources ?? [:]
    }

}

enum ItemSlot: String, Codable, CaseIterable {
    case head
    case body
    case legs
    case onehand
    case twohand
    case small

    var displayName: String {
        switch self {
        case .head: return "Head"
        case .body: return "Body"
        case .legs: return "Legs"
        case .onehand: return "One Hand"
        case .twohand: return "Two Hands"
        case .small: return "Small Item"
        }
    }

    var icon: String {
        switch self {
        case .head: return "eyeglasses"
        case .body: return "tshirt"
        case .legs: return "shoe"
        case .onehand: return "hand.raised"
        case .twohand: return "hands.clap"
        case .small: return "bag"
        }
    }
}
