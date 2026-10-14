import Foundation

/// A room card of the random dungeon deck (rulebook pp. 50–51): its map tile(s), twelve numbered
/// hexes where its monster card's figures, traps and treasure go, its obstacles, the A or B
/// entrances and exits, and the penalties for revealing it. The map data has none of this; the
/// cards are written by hand into `Resources/ScenarioMaps/placements/<edition>-dungeons.json`,
/// in tile coordinates.
struct DungeonRoomCard: Codable, Equatable {
    /// The noun of the room's title ("Trail"); the monster card gives the adjective.
    var name: String
    /// The number printed on the card.
    var card: Int
    /// The tiles of the room, the first one the room's own frame. A second tile is joined to the
    /// first as the card draws it.
    var tiles: [Tile]
    var entrances: [Passage]
    var exits: [Passage]
    /// Where each of the monster card's twelve numbers goes.
    var numbers: [String: Place]
    /// Obstacles and difficult terrain the card draws.
    var overlays: [Overlay]
    /// The penalties for revealing the room, as printed.
    var minor: String
    var major: String
    var notes: String?

    struct Tile: Codable, Equatable {
        var ref: String
        /// The turn (× 60° clockwise) at which the tile is drawn as on the card.
        var matchTurns: Int
        /// For a second tile: one hex where it meets the first, as its own coordinate (`second`)
        /// and as the coordinate the same place has in the first tile's frame (`first`).
        var join: Join?
    }

    struct Join: Codable, Equatable {
        var second: [Int]
        var first: [Int]
    }

    /// A hex on one of the room's tiles.
    struct Place: Codable, Equatable, Hashable {
        var tile: String
        var x: Int
        var y: Int
    }

    /// An entrance or exit: the half-hex at the edge of the tile, and its type.
    struct Passage: Codable, Equatable {
        var type: String
        var tile: String
        var x: Int
        var y: Int

        var place: Place { Place(tile: tile, x: x, y: y) }
    }

    struct Overlay: Codable, Equatable {
        /// "obstacle" or "difficult-terrain", as the map data names them.
        var type: String
        var subType: String
        var tile: String
        var cells: [[Int]]
    }

    /// The types of its entrances ("A", "B").
    var entranceTypes: Set<String> { Set(entrances.map(\.type)) }
}

/// Loads the room cards shipped with the app.
final class DungeonCardStore {
    static let shared = DungeonCardStore()

    private var cache: [String: [DungeonRoomCard]] = [:]

    private init() {}

    /// Every room card of an edition's dungeon deck, in the order written.
    func rooms(edition: String = "gh") -> [DungeonRoomCard] {
        if let loaded = cache[edition] { return loaded }
        struct File: Codable { var rooms: [DungeonRoomCard] }
        let url = appResourceBundle.url(forResource: "\(edition)-dungeons", withExtension: "json",
                                        subdirectory: "ScenarioMaps/placements")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let loaded = data.flatMap { try? JSONDecoder().decode(File.self, from: $0) }?.rooms ?? []
        cache[edition] = loaded
        return loaded
    }

    /// A room card by its name ("Trail").
    func room(named name: String, edition: String = "gh") -> DungeonRoomCard? {
        rooms(edition: edition).first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
