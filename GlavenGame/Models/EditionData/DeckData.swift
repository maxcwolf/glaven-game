import Foundation

struct DeckData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(name)" }
    var name: String
    var edition: String
    var character: Bool?
    var abilities: [AbilityModel]

    init(name: String, edition: String, character: Bool? = nil, abilities: [AbilityModel] = []) {
        self.name = name
        self.edition = edition
        self.character = character
        self.abilities = abilities
    }
}
