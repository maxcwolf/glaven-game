import Foundation

/// Where a scenario's objectives stand and where its lettered spawn hexes are, by map tile and
/// in the tile's own coordinates (as the map data's overlays are). The map data has neither;
/// these are written by hand into `Resources/ScenarioMaps/placements/<edition>.json`.
struct ScenarioPlacements: Codable, Equatable {
    /// By tile ref ("m1a").
    var tiles: [String: Tile]
    /// Objectives (1-based) the party must keep from harm without their being allies: monsters
    /// attack them, characters can't, and nothing heals them (captives, a gate under siege).
    var protect: [Int]?
    /// What the scenario book asks of the objectives, where the scenario data has no rule for it.
    var goal: Goal?

    struct Goal: Codable, Equatable {
        /// The goal in the book's words, for the scenario brief: "Destroy all altars."
        var text: String?
        /// Objectives (1-based) to destroy, every one of each, to win.
        var destroy: [Int]?
        /// Monster types to kill, every one that appears, to win ("ooze").
        var kill: [String]?
        /// An escort to bring somewhere to win.
        var arrive: Arrival?
        /// Whether every enemy must be dead to win as well. Without `destroy`, `kill` or
        /// `arrive` that is the goal anyway.
        var enemies: Bool?
        /// The scenario is lost when this many of an objective are killed: "1": 1.
        var lostAt: [String: Int]?

        /// Whether winning takes something other than killing every enemy.
        var replacesKillAll: Bool { destroy != nil || kill != nil || arrive != nil }
    }

    struct Arrival: Codable, Equatable {
        /// Which objective (1-based) makes the trip.
        var objective: Int
        /// The letter of the hex to reach.
        var marker: String
        /// How many must arrive.
        var count: Int
        /// Whether ending a turn next to the lettered hex is arriving (an altar can't be stood on).
        var adjacent: Bool?
    }

    struct Tile: Codable, Equatable {
        var objectives: [Objective]?
        /// Spawn hexes by marker letter: "a" → [[x, y], …].
        var markers: [String: [[Int]]]?
    }

    struct Objective: Codable, Equatable {
        /// Which of the scenario's objectives (1-based, as its room data refers to them).
        var objective: Int
        /// The hexes it covers; it stands on the first. An objective drawn on the map as an
        /// obstacle covers the obstacle's hexes, which are cleared when it is destroyed.
        var cells: [[Int]]
        /// It bars the door on its hex: the door can't be opened, and opens when it is destroyed.
        var door: Bool?
    }
}

/// A place for one objective on the board, from the placements of a revealed tile.
struct ObjectiveSlot: Codable, Equatable, Sendable {
    /// Which of the scenario's objectives stands here (1-based).
    let objective: Int
    /// Where it stands.
    let coord: HexCoord
    /// Every hex it covers, `coord` included.
    let cells: [HexCoord]
    /// Whether it bars the door on its hex.
    var barsDoor: Bool = false
}

/// Loads the hand-written placements shipped with the app.
final class ScenarioPlacementStore {
    static let shared = ScenarioPlacementStore()

    private var cache: [String: [String: ScenarioPlacements]] = [:]

    private init() {}

    /// The placements for a scenario by its map index ("22"), nil when none are written yet.
    func placements(for index: String, edition: String = "gh") -> ScenarioPlacements? {
        all(edition: edition)[index]
    }

    /// Every scenario's placements, by map index.
    func all(edition: String = "gh") -> [String: ScenarioPlacements] {
        if let loaded = cache[edition] { return loaded }
        let url = appResourceBundle.url(forResource: edition, withExtension: "json",
                                        subdirectory: "ScenarioMaps/placements")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let loaded = data.flatMap { try? JSONDecoder().decode([String: ScenarioPlacements].self, from: $0) } ?? [:]
        cache[edition] = loaded
        return loaded
    }
}
