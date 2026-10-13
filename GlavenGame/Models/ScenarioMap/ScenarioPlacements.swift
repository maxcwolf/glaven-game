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
    /// Objectives a character may spare a source of damage by losing a card from their hand
    /// (the captive Orchids; the crystal, twice a scenario).
    var saves: [Save]?
    /// What a character beside an objective may give up an action for (the captive Orchids,
    /// freed).
    var forgo: [Forgo]?
    /// Things a character carries: the doll, the Lurker King's claw.
    var carried: [Carried]?
    /// Numbered tokens lying face down on lettered hexes, to be looted (Payment Due).
    var tokens: Tokens?
    /// What moves the party as each round ends (the wind of #71, the current of #88).
    var drift: Drift?
    /// Obstacles that roll along their rows as each round ends (#73's boulders).
    var rolling: Rolling?
    /// Water that rises on a tile as rounds end, and is bailed (#74's hold).
    var flood: Flood?
    /// Doors some monsters can't enter or pass through (#67's Arcane Golem, #73's Inox).
    var barred: [Barred]?
    /// Monster types set up asleep (#71's Spitting Drakes): each does nothing until a character or
    /// a character's summon attacks it, damages it, gives it a negative condition or ends a
    /// movement beside it; then it acts as a monster just spawned does.
    var asleep: [String]?
    /// Escorts (objectives, 1-based) whose attacks draw "from whichever attack modifier deck the
    /// players choose": a character's, asked as the escort attacks (Redthorn; the captive
    /// Orchids of Bandit's Wood).
    var drawsFromACharacter: [Int]?
    /// Objectives (1-based) dug up with movement: a character beside one spends movement points
    /// on it, one hit point each, in as many moves as it takes; nothing attacks it (the graves
    /// of the Overgrown Graveyard, 1+C movement each).
    var dig: [Int]?
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
    /// Map tiles laid out from the start though their room isn't revealed (the yard behind the
    /// gate of Gloomhaven Battlements A, with the archers on its battlements): only the monsters
    /// an earlier room's data puts on lettered hexes there are set up; the rest wait until the
    /// door opens or a character or ally gets onto one of the tiles.
    var laidOut: [String]?
    /// Obstacles no ability destroys (the dark pits, the battlements' wall sections).
    var indestructible: Indestructible?
    /// Numbered treasure whose reward is handed back when the scenario is lost, the tile being
    /// reset for the next attempt (Burning Mountain's chest).
    var resetOnLoss: [String]?
    /// Escorts (1-based objectives) that do nothing but still take a turn at their initiative,
    /// in which their conditions act: Wound hurts, and what lasts a turn runs out (Hail of
    /// Ruinous Rift, at 99).
    var passiveTurns: [Int]?

    /// What wins and loses a scenario. Everything set under "to win" must hold at once; any one
    /// of the losses loses. With nothing to win set, the goal is the default: every enemy dead
    /// with every room revealed.
    struct Goal: Codable, Equatable {
        /// The goal in the book's words, for the scenario brief: "Destroy all altars."
        var text: String?

        // MARK: To win

        /// Objectives (1-based) to destroy, every one of each.
        var destroy: [Int]?
        /// Objectives (1-based) all of which must be freed or cleansed by an action given up
        /// for it (`forgo`): the water pumps, however many the party's size sets up.
        var freed: [Int]?
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
        /// The conclusion section read when the scenario is won this way ("82-A"): its rewards
        /// are applied with the scenario's own. Set on the alternatives of `either`.
        var conclusion: String?

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
        /// Lost when no character stands in a room (the two rooms of Demonic Rift).
        var lostIfEmpty: [Vacancy]?
        /// Lost when fewer than this many characters are left unexhausted.
        var lostBelow: Int?

        /// Whether winning takes something other than killing every enemy.
        var replacesKillAll: Bool {
            destroy != nil || kill != nil || killCount != nil || reveal != nil || loot != nil || lootIDs != nil
                || arrive != nil || escape != nil || occupy != nil || reach != nil || enemies == "revealed"
                || either != nil || spare != nil || freed != nil
        }

        /// Whether part of the goal is where characters stand, judged as a turn ends.
        var isPositional: Bool {
            escape != nil || occupy != nil || reach != nil || (either ?? []).contains(where: \.isPositional)
        }
    }

    /// A room that mustn't be left without a character.
    struct Vacancy: Codable, Equatable {
        /// The map tiles that make the room.
        var tiles: [String]
        /// Only once a monster of this type has appeared (the Living Spirits of Section 1).
        var onceAppeared: String?
        /// The loss in the brief's words.
        var text: String
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
        /// The thing (`Carried.name`) whose holder it is that must get there; without one, any
        /// character.
        var holding: String?
        /// The thing must be fully charged (the Staff of Xorn).
        var charged: Bool?
        /// Whether ending a turn next to the lettered hex is enough (a well can't be stood on).
        var adjacent: Bool?
        /// Entering such a hex is enough: the character needn't end the turn (or even the
        /// move) there.
        var enter: Bool?
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
        /// The numbered tokens (`tokens`) that must all have been looted: [1, 2, 3, 4].
        var tokens: [Int]?
        /// It stays open only while a character stands on a plate with one of these letters,
        /// and shuts again when they step off.
        var held: [String]?
        /// The key unlocks it rather than opening it: a character still has to walk in.
        var unlocksOnly: Bool?
        /// A held door that opens for the first time only as a turn ends with a character on
        /// its plate; once it has, it opens and shuts with the plates like any held door.
        var firstAtTurnEnd: Bool?
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

    /// Obstacles that can't be destroyed: by overlay sub-type ("dark-pit", "wall-section") or
    /// every obstacle of a map tile (Noxious Cellar's centre room).
    struct Indestructible: Codable, Equatable {
        var subTypes: [String]?
        var tiles: [String]?
    }

    /// "Any character may lose one card from their hand to negate any one source of damage" to
    /// an objective: which objective (1-based), and how many times in the scenario (nil: as
    /// often as there are cards to lose).
    struct Save: Codable, Hashable {
        let objective: Int
        var times: Int?
    }

    /// "It cannot enter or pass through door 2" (#67); "The Inox on tile E cannot enter or pass
    /// through door 1" (#73): the door between two tiles, the monster types it is shut to, and —
    /// where the book speaks of the monsters of one tile — the tile they stand on.
    struct Barred: Codable, Hashable {
        let monsters: [String]
        let between: [String]
        var from: String?
    }

    /// "At the end of every even round for two characters or every round for three or four
    /// characters, one water tile is added to the B tile adjacent to any existing water tile. If a
    /// water tile cannot be placed because the B tile is full, the scenario is lost. Characters
    /// may pick up any water tile through normal looting and then get rid of it by ending their
    /// turn in one of the hexes e. Each character can only hold one water tile at a time." (#74)
    struct Flood: Codable, Hashable {
        /// The tile that fills.
        let tile: String
        /// The rounds at whose end a water tile is added, as a rule's `round` is written.
        let every: String
        /// The letter of the hexes a held water tile is got rid of on.
        let bail: String
        /// "Remove water tiles d for three characters": the letter, and for how many characters.
        var dry: Dry?
        /// What the players read when the tile is full.
        let lost: String

        struct Dry: Codable, Hashable {
            let marker: String
            let characters: Int
        }
    }

    /// "At the end of every round, both boulders in each row will move one, two, or three hexes
    /// to the left. The players choose the number of hexes moved, but … each row of boulders
    /// must move a different number of hexes" (#73). A row runs from the hex lettered `reenter`
    /// to the last hex of the map on the side the boulders roll toward: one that gets there is
    /// "immediately placed at b in its row and continues".
    struct Rolling: Codable, Hashable {
        /// The obstacles that roll, by the name of their art: "boulder-1".
        let subType: String
        /// The side they roll toward ("W").
        let side: String
        /// The letter of the hex of each row a boulder comes back in at.
        let reenter: String
        /// How far a row may roll: each row a different one of these.
        let steps: [Int]
    }

    /// "Strong winds will force characters and character summons to move one hex … at the end of
    /// every round" (#71); "all characters and character summons are forced to move one hex in
    /// the direction of the current at the end of each round" (#88). Sides of a hex are named as
    /// the map lies in the game: "NE", "E", "SE", "SW", "W", "NW".
    struct Drift: Codable, Hashable {
        /// What it is called: "wind", "current".
        let name: String
        /// The sides a figure may be moved toward in round 1, 2, 3… and round again: where two
        /// are written the players choose between those that are open.
        var directions: [[String]]?
        /// Or the sides by this round's initiative of a monster type's ability card.
        var byInitiative: ByInitiative?
        /// Only figures standing on these tiles are moved.
        var tiles: [String]?
        /// A figure directly behind an obstacle or wall hex (the hex the drift comes from) stays.
        var sheltered: Bool?
        /// Damage a figure suffers instead when another figure, an obstacle or a wall is in its way.
        var blocked: Int?
        /// "top": from the top of the map to the bottom; otherwise in initiative order.
        var order: String?

        struct ByInitiative: Codable, Hashable {
            let monster: String
            let even: [String]
            let odd: [String]
        }
    }

    /// "Shuffle numbered tokens 1–6 and place them face down on hexes (a). These tokens can be
    /// looted normally": how many there are and the letter of their hexes. Which number lies
    /// where isn't known until it is looted; a lock's `tokens` waits for some of them.
    struct Tokens: Codable, Hashable {
        let marker: String
        let count: Int
    }

    /// Something one character holds (a treasure tile on their mat): the doll of the Well of the
    /// Unfortunate, the Lurker King's claw. It changes hands only when another character performs
    /// a Loot action with its holder within the loot's range, and lies in the holder's hex, to be
    /// looted like a treasure tile, if they are exhausted.
    struct Carried: Codable, Hashable {
        /// What it is called in the data and to the players: "doll", "claw".
        let name: String
        /// "choose": the players choose who holds it as the scenario starts.
        var start: String?
        /// The monster that drops it where it dies, instead of a money token.
        var droppedBy: String?
        /// Added to every Move of its holder (−2 for the claw).
        var move: Int?
        /// The treasure tile whose looter holds it ("goal", "62"). Several things on tiles with
        /// one id are given in the order they are written (the Crystal of Zenith, then the
        /// Sphere of Midnight).
        var treasure: String?
        /// The personal quest (its card: "526", Vengeance) of the only character who may loot
        /// that tile, where someone in the party is on it.
        var onlyQuest: String?
        /// Whether it changes hands by a Loot action with its holder in range and lies where an
        /// exhausted holder stood (the doll, the claw). Otherwise it stays with whoever has it.
        var passes: Bool?
        /// Pierce added to its holder's attacks on the monster type `against` (the Occult
        /// Dagger: 4, against the Harvester).
        var pierce: Int?
        var against: String?
        /// The scenario is lost if its holder is exhausted (the artifacts of Burning Mountain).
        var lostWithHolder: Bool?
        /// The item ("gh-114") whose bearer holds it from the start, where no one is on
        /// `onlyQuest` (the Staff of Xorn is the Seeker's).
        var item: String?
        /// Monster types only its holder damages; each point of that damage charges it (the
        /// Harrower Infesters and the Staff of Xorn).
        var soleHarmTo: [String]?
        /// The charge it holds when full ("2xCx(L+1)").
        var charge: String?
        /// What its holder may discard it for as their turn ends at a lettered hex (the Crystal
        /// of Zenith beside the altar: the Colorless suffers 2×C damage).
        var spend: Spend?

        struct Spend: Codable, Hashable {
            /// The lettered hex ("a") the holder must end the turn on — or beside, with `adjacent`.
            let marker: String
            var adjacent: Bool?
            /// The damage ("2xC") the monster type `to` suffers.
            let damage: String
            let to: String
        }
    }

    /// "A character adjacent to a captive Orchid may forgo an action (discarding one card
    /// instead) to free that captive, which is removed from the map immediately": the objective
    /// (1-based) that is freed, and the objective whose attacks gain +1 for each one freed
    /// (Redthorn). `does` names it where it isn't freeing ("cleanse": the water pumps of the
    /// Ancient Cistern), and `bottom` is for what only a bottom action may be given up for.
    /// With `treasure` instead of an objective it is the goal treasure tile beside the
    /// character that the action is given up for: it is looted (Noxious Cellar).
    struct Forgo: Codable, Hashable {
        var objective: Int?
        var treasure: Bool?
        var strengthens: Int?
        var does: String?
        var bottom: Bool?

        /// What giving the action up does to the objective: "free", "cleanse".
        var verb: String { does ?? "free" }
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
        /// Added to each of their Move abilities (Plane of Water: −1).
        var move: Int?
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

/// What a scenario's traps do, as the map legend in the scenario book names them: "Damage
/// Trap", "Stun Trap" (no damage), "Poison and Damage Trap", "Immobilize and Poison Trap". The
/// map data only has the art each trap is drawn with, which doesn't say; these are written by
/// hand into `Resources/ScenarioMaps/placements/<edition>-traps.json`.
struct ScenarioTraps: Codable, Equatable {
    /// The page of the scenario book the legend is on.
    var page: Int?
    /// Each kind of trap the legend lists.
    var kinds: [Kind]

    struct Kind: Codable, Equatable {
        /// Whether springing it deals trap damage (2 + L).
        var damage: Bool
        /// The conditions it gives the figure that springs it, in the legend's order.
        var conditions: [ConditionName]
        /// How many of them the map sets up.
        var count: Int
        /// How many the legend counts, where that is more: the rest are placed by a rule
        /// during play (Well of the Unfortunate).
        var legend: Int?
        /// Which of the map's traps are this kind: those the map data draws with this art (its
        /// overlay sub-type: "spike", "bear" or "poison")…
        var art: String?
        /// …or those on these hexes, by tile in tile coordinates, where the art doesn't tell
        /// two kinds apart. With neither, every trap no other kind claims.
        var tiles: [String: [[Int]]]?

        var effect: TrapEffect { TrapEffect(damage: damage, conditions: conditions) }
    }

    /// The kind of the trap the map data has on `cell` of `tile`, drawn with `art`: one written
    /// for that hex, else one written for that art, else the kind written for all the rest.
    func kind(tile: String, cell: [Int], art: String?) -> Kind? {
        let ref = tile.lowercased()
        let hex = Array(cell.prefix(2))
        return kinds.first { $0.tiles?[ref]?.contains(hex) == true }
            ?? kinds.first { $0.tiles == nil && $0.art != nil && $0.art == art }
            ?? kinds.first { $0.tiles == nil && $0.art == nil }
    }
}

/// Loads the hand-written trap legends shipped with the app.
final class ScenarioTrapStore {
    static let shared = ScenarioTrapStore()

    private var cache: [String: [String: ScenarioTraps]] = [:]

    private init() {}

    /// The traps of a scenario by its map index ("15"), nil when its legend isn't written.
    func traps(for index: String, edition: String = "gh") -> ScenarioTraps? {
        all(edition: edition)[index]
    }

    /// Every scenario's traps, by map index.
    func all(edition: String = "gh") -> [String: ScenarioTraps] {
        if let loaded = cache[edition] { return loaded }
        let url = appResourceBundle.url(forResource: "\(edition)-traps", withExtension: "json",
                                        subdirectory: "ScenarioMaps/placements")
        let data = url.flatMap { try? Data(contentsOf: $0) }
        let loaded = data.flatMap { try? JSONDecoder().decode([String: ScenarioTraps].self, from: $0) } ?? [:]
        cache[edition] = loaded
        return loaded
    }
}
