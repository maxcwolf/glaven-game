import Foundation

struct WorldMapDimensions: Codable {
    var width: Double
    var height: Double
}

struct EditionInfo: Codable, Identifiable {
    var id: String { edition }
    var edition: String
    var conditions: [ConditionName]?
    var extensions: [String]?
    var extends: [String]?
    var logoUrl: String?
    var worldMap: WorldMapDimensions?

    var displayName: String {
        switch edition {
        case "gh": return "Gloomhaven"
        case "fh": return "Frosthaven"
        case "jotl": return "Jaws of the Lion"
        case "cs": return "Crimson Scales"
        case "gh2e": return "Gloomhaven 2E"
        default: return edition.uppercased()
        }
    }
}
