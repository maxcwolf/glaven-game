import Foundation

struct PersonalQuestData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(cardId)" }
    var cardId: String
    var altId: String?
    var requirements: [PersonalQuestRequirement]
    var unlockCharacter: String?
    var openEnvelope: String?
    var spoiler: Bool?
    var errata: String?
    var edition: String = ""

    enum CodingKeys: String, CodingKey {
        case cardId, altId, requirements, unlockCharacter, openEnvelope, spoiler, errata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try container.decode(String.self, forKey: .cardId)
        altId = try container.decodeIfPresent(String.self, forKey: .altId)
        requirements = try container.decodeIfPresent([PersonalQuestRequirement].self, forKey: .requirements) ?? []
        unlockCharacter = try container.decodeIfPresent(String.self, forKey: .unlockCharacter)
        openEnvelope = try container.decodeIfPresent(String.self, forKey: .openEnvelope)
        spoiler = try container.decodeIfPresent(Bool.self, forKey: .spoiler)
        errata = try container.decodeIfPresent(String.self, forKey: .errata)
        edition = ""
    }
}

struct PersonalQuestRequirement: Codable, Hashable {
    var name: String
    var counter: IntOrString?
    var autotrack: String?
    var requires: [Int]?
}
