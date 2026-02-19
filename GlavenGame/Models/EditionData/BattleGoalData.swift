import Foundation

struct BattleGoalData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(cardId)" }
    var cardId: String
    var name: String
    var checks: Int
    var edition: String

    enum CodingKeys: String, CodingKey {
        case cardId, name, checks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try container.decode(String.self, forKey: .cardId)
        name = try container.decode(String.self, forKey: .name)
        checks = try container.decodeIfPresent(Int.self, forKey: .checks) ?? 1
        edition = ""
    }
}
