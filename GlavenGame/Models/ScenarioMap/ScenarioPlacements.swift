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
    /// The scenario's goal and loss conditions as the scenario book prints them, where the
    /// scenario data has no rule for them.
    var goal: Goal?
    /// The goal treasure tiles can only be looted with a Loot action: ending a turn on one, or
    /// walking over it, doesn't pick it up.
    var lootActionOnly: Bool?
    /// Doors a scenario rule keeps locked, and what opens each.
    var locks: [Lock]?
    /// Letters that are pressure plates no lock or goal names, to be drawn as plates.
    var plates: [String]?
    /// Rules the scenario book prints and the scenario data leaves out, in the data's own rule
    /// format; they are added after the scenario's own.
    var rules: [ScenarioRule]?
    /// The scenario's own rules to leave out, by their place in its list (from 0): ones the data
    /// gets wrong or leaves for a person to trigger, written again in `rules`.
    var dropRules: [Int]?
    /// Monster types that aren't set up with their rooms: they wait for a rule's `setUp` (the
    /// Lurkers of Harried Village, until a villager is saved).
    var later: [String]?
    /// Standing effects on attacks and shields (the vocal chords of Realm of the Voice).
    var effects: [Effect]?
    /// The scenario's special rules in words, for the scenario brief: those the game enforces
    /// that the scenario data has no text for (or says less well).
    var notes: [String]?
    /// Monster types that are a third side: enemies to the characters and to all other
    /// monster types.
    var apart: [String]?
    /// Objectives (1-based) that are allies only to be healed: nothing attacks or affects them.
    var sheltered: [Int]?
    /// Monster types that, for a time, don't act and can't be affected by anything; figures
    /// move through their hexes but can't stop there.
    var inactive: [Inactive]?
    /// Objectives (1-based) the monsters that attack them go for first: one that can get
    /// within range to attack it this turn focuses on it, whoever is nearer (a gate, the crystal).
    var focusFirst: [Int]?
    /// Monster types that can't be damaged in any way; conditions and other effects of an
    /// attack still apply (the Living Spirits of Chained Isle).
    var undamageable: [String]?
    /// Each time one of some monster types dies, one of another is taken off the map.
    var reprieve: Reprieve?
    /// Monster types that don't move as their cards say: each turn they make for the nearest
    /// of some lettered hexes instead, then do the rest of their card (Vault of Secrets' guards).
    var march: [String: March]?
    /// There are two starting rooms, and no more than half the characters (rounded up) may
    /// start in the same one.
    var splitStart: Bool?
    /// What water hexes do in this scenario.
    var water: Water?
    /// Bosses that go from one marked hex (or locked door) to the next, by monster type.
    var cycles: [String: Cycle]?
    /// A boss's special abilities as this scenario prints them, in place of its stat card's
    /// (Battlements B: "Move+0, Attack+0" for both).
    var specials: [String: [[ActionModel]]]?
    /// What appears where an objective stood when it is destroyed, by objective (1-based): a
    /// Living Corpse from each grave dug up.
    var whenDestroyed: [String: MonsterStandeeData]?

    /// What wins and loses a scenario. Everything set under "to win" must hold at once; any one
    /// of the losses loses. With nothing to win set, the goal is the default: every enemy dead
    /// with every room revealed.
    struct Goal: Codable, Equatable {
        /// The goal in the book's words, for the scenario brief: "Destroy all altars."
        var text: String?

        // MARK: To win

        /// Objectives (1-based) to destroy, every one of each.
        var destroy: [Int]?
        /// Monster types to kill, every one ("jekserah"): each has appeared, every room that
        /// holds one is revealed, and none is alive.
        var kill: [String]?
        /// A number of enemies to kill.
        var killCount: KillCount?
        /// "all": every enemy dead with every room revealed. "revealed": every enemy on the
        /// board dead, whatever is still behind doors.
        var enemies: String?
        /// Monster types that needn't die for `enemies` (the City Guards of Back Alley Brawl).
        var spare: [String]?
        /// Map tiles to reveal ("m1a"), or "*" for every room.
        var reveal: [String]?
        /// "goal": every goal treasure tile looted. "each": every character has looted one.
        var loot: String?
        /// Numbered treasure tiles to loot ("62").
        var lootIDs: [String]?
        /// Any one of these as well (sacrifice the artifact, or escape with it).
        var either: [Goal]?
        /// An escort to bring somewhere.
        var arrive: Arrival?
        /// Where every character must be to escape.
        var escape: Exit?
        /// Pressure plates characters must all stand on at once.
        var occupy: Plates?
        /// A hex some character must end a turn on or beside.
        var reach: Reach?

        // MARK: Lost

        /// Lost when this many of an objective are killed: "1": 1.
        var lostAt: [String: Int]?
        /// Lost when a character is exhausted: "any", "offExit" (not standing on an exit hex),
        /// "beforeLoot" (before the loot the goal asks for is done).
        var lostIfExhausted: [String]?
        /// Exhaustion only loses once this tile is revealed.
        var lostIfExhaustedOnceRevealed: String?
        /// Lost when one of these monster types is killed.
        var lostIfKilled: [String]?
        /// Lost when a monster of these types stands on a hex with this letter (a guard on the
        /// alarm plate).
        var lostIfStands: Stands?

        /// Whether winning takes something other than killing every enemy.
        var replacesKillAll: Bool {
            destroy != nil || kill != nil || killCount != nil || reveal != nil || loot != nil || lootIDs != nil
                || arrive != nil || escape != nil || occupy != nil || reach != nil || enemies == "revealed"
                || either != nil || spare != nil
        }

        /// Whether part of the goal is where characters stand, judged as a turn ends.
        var isPositional: Bool {
            escape != nil || occupy != nil || reach != nil || (either ?? []).contains(where: \.isPositional)
        }
    }

    struct Stands: Codable, Equatable {
        var monsters: [String]
        var marker: String
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

    struct KillCount: Codable, Equatable {
        /// How many, as the book writes it: "5xC".
        var count: String
        /// Which monster types count; nil for any enemy.
        var of: [String]?
    }

    /// Exit hexes: the hexes of a letter, a whole tile, or the starting hexes.
    struct Exit: Codable, Equatable {
        var marker: String?
        var tile: String?
        var start: Bool?
        /// A character on an exit hex as a round ends leaves the scenario; it is won when all
        /// have left. Without it, all must stand on exit hexes at once.
        var leave: Bool?
    }

    struct Plates: Codable, Hashable {
        /// The letters of the plates in play for two characters.
        var markers: [String]
        /// More letters in play by character count: "3": ["b"], "4": ["b", "c"].
        var more: [String: [String]]?
    }

    struct Reach: Codable, Equatable {
        var marker: String
        /// Whether ending a turn next to the lettered hex is enough (a well can't be stood on).
        var adjacent: Bool?
    }

    /// A locked door (or the doors) between two tiles. Walking into it doesn't open it; one of
    /// the keys below does. With no key it opens only by a scenario rule or a monster's ability.
    struct Lock: Codable, Equatable {
        /// The two tiles the door joins ("d1a", "h3b").
        var between: [String]
        /// What the player is told about it: "Opens when a character ends a turn on the pressure plate."
        var note: String?
        /// A character ends a turn on a pressure plate with one of these letters.
        var plate: [String]?
        /// Every character stands on a pressure plate as a turn ends.
        var allOnPlates: Plates?
        /// This round has ended ("at the start of round 2" is after round 1).
        var afterRound: Int?
        /// This many goal treasure tiles have been looted.
        var looted: Int?
        /// This many elite monsters have been killed.
        var eliteKills: Int?
        /// It stays open only while a character stands on a plate with one of these letters,
        /// and shuts again when they step off.
        var held: [String]?
        /// The key unlocks it rather than opening it: a character still has to walk in.
        var unlocksOnly: Bool?
    }

    struct Tile: Codable, Equatable {
        var objectives: [Objective]?
        /// Lettered hexes by marker: "a" → [[x, y], …].
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

extension ScenarioPlacements {
    /// "Move 2 toward the closest pressure plate" in place of a monster type's own movement.
    struct March: Codable, Equatable {
        var toward: [String]
        var move: Int
        /// It opens a door by walking into it, revealing the room.
        var opensDoors: Bool?
    }

    /// A boss that goes round a set of places: the Gloom's jumps, the Dark Rider's appearances,
    /// the Bandit Commander's doors.
    struct Cycle: Codable, Equatable {
        /// The lettered hexes in order; after the last comes the first again.
        var letters: [String]?
        /// The scenario's locked doors (`locks`, in order) instead of letters: it jumps into
        /// the doorway and opens it.
        var doors: Bool?
        /// It isn't set up: off the map as its turn starts, it appears on its next hex.
        var appears: Bool?
        /// It leaves the map right after any melee attack it makes.
        var leavesAfterMelee: Bool?
    }

    struct Inactive: Codable, Equatable {
        var monsters: [String]
        /// The rounds in which they are inactive: `"odd"` or `"even"` (Fading Lighthouse's two groups).
        var rounds: String?
        /// Inactive until a rule's `setUp` names them (Lost Temple's Stone Golems).
        var untilSetUp: Bool?
    }

    /// The monster types of a scenario that are inactive in `round`, given those already woken.
    func inactiveMonsters(round: Int, woken: Set<String>) -> Set<String> {
        var names: Set<String> = []
        for entry in inactive ?? [] {
            if entry.untilSetUp == true { names.formUnion(Set(entry.monsters).subtracting(woken)) }
            if entry.rounds == "odd", round % 2 == 1 { names.formUnion(entry.monsters) }
            if entry.rounds == "even", round % 2 == 0 { names.formUnion(entry.monsters) }
        }
        return names
    }

    struct Water: Codable, Equatable {
        /// A character or character summon with Poison that enters a water hex suffers trap
        /// damage (Toxic Moor).
        var hurtsThePoisoned: Bool?
        /// Damage for any figure that ends its turn in a water hex ("1+L", Payment Due).
        var endOfTurn: String?
        /// A character who ends a turn on a water hex of these tiles is cleansed, once: the tile
        /// goes, and for the rest of the scenario they have Shield against these monsters'
        /// attacks and can't be poisoned (Corrupted Cove).
        var cleanses: Cleansing?

        struct Cleansing: Codable, Equatable {
            var tiles: [String]
            var shield: Int
            var against: [String]
        }
    }

    /// For every death of one of `killed`, one of `removes` leaves the map (Chained Isle: a
    /// Living Spirit for every demon).
    struct Reprieve: Codable, Equatable {
        var killed: [String]
        var removes: String
    }

    /// Something the scenario does to every attack of some figures, or to their Shield, for as
    /// long as it holds.
    struct Effect: Codable, Equatable {
        /// Whom it touches: `"monsters"` (the party's enemies), `"party"` (characters and their
        /// summons), or one monster type.
        var on: String
        /// Only while this objective (1-based) still stands.
        var whileStanding: Int?
        /// Only once this room is revealed.
        var room: Int?
        /// Only on a character who hasn't looted a goal treasure tile yet (not on summons).
        var untilLooted: Bool?
        /// They can't use any item.
        var noItems: Bool?
        /// Added to each of their attacks.
        var attack: Int?
        var advantage: Bool?
        var disadvantage: Bool?
        /// Added to their Shield (which never falls below none): a number, or a formula over X
        /// (what `per` counts), C and L.
        var shield: String?
        var per: Per?

        /// What X counts: an objective (1-based) or other monsters of a type on the board, or
        /// tokens of which one is lost each time a monster of a type dies.
        struct Per: Codable, Equatable {
            var objective: Int?
            var monster: String?
            var tokens: Int?
            var lostWith: String?
        }
    }
}

extension ScenarioRule {
    /// A rule that never applies: it holds the place of one left out.
    static let nothing: ScenarioRule = {
        guard let rule = try? JSONDecoder().decode(ScenarioRule.self, from: Data(#"{"round": "R < 0"}"#.utf8)) else {
            fatalError("an empty scenario rule decodes")
        }
        return rule
    }()
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
