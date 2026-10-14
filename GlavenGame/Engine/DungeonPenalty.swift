import Foundation

/// What a room card's penalty does when its room is revealed (RD-6), one value per printed text.
/// The printed text is on the card (`DungeonRoomCard.minor`, `major`); this is the game's reading
/// of it, checked against the text by `testEveryPenaltyIsRead`.
indirect enum DungeonPenalty: Equatable {
    /// Whom a penalty on characters touches.
    enum Who: Equatable {
        /// Every character.
        case everyone
        /// The character who opened the door (in the first room: the one the players choose).
        case opener
    }

    /// Conditions given (`permanent`: they can't be removed for the rest of the scenario).
    case conditions([ConditionName], Who, permanent: Bool = false)
    /// Curse cards shuffled into each character's deck, `times` each.
    case curses(times: Int)
    case damage(Int, Who)
    case loseCards(Int, Who)
    case discardCards(Int, Who)
    /// Items: every spendable one spent; one small one consumed; or every one consumed and spent.
    case spendAllSpendable
    case consumeSmallItem
    case consumeAndSpendAll
    /// Bless cards added to the monster attack modifier deck.
    case monsterBlessings(Int)
    case elementsInert
    /// For the rest of the scenario characters can't consume elements.
    case noConsuming
    /// Every enemy gains a Shield; for the round or for the scenario.
    case enemyShield(Int, permanent: Bool)
    /// Every enemy gains "Retaliate X, Range R"; for the round or for the scenario.
    case enemyRetaliate(Int, range: Int, permanent: Bool)
    /// Every enemy adds to its attacks (and moves, and range).
    case enemyAttack(Int)
    case enemyMoveAndRange(Int)
    /// Every enemy heals this much at the start of each of its turns.
    case enemyHealEachTurn(Int)
    /// Every enemy gains Strengthen; `permanent`: for the rest of the scenario.
    case enemyStrengthen(permanent: Bool)
    case eliteInvisible
    /// A normal enemy in this room becomes elite.
    case upgradeNormalInRoom
    /// Enemies of the previous room put back: elite or normal, how many.
    case replaceInPreviousRoom(elite: Bool, count: Int)
    /// Two penalties at once.
    case both(DungeonPenalty, DungeonPenalty)

    /// The penalties of each room card: (minor, major), as printed.
    static let byRoom: [String: (minor: DungeonPenalty, major: DungeonPenalty)] = [
        "Alcove": (.enemyShield(1, permanent: false), .enemyShield(1, permanent: true)),
        "Altar": (.monsterBlessings(3), .monsterBlessings(7)),
        "Armory": (.conditions([.poison], .everyone), .enemyAttack(1)),
        "Burrow": (.conditions([.stun], .opener), .conditions([.muddle, .poison, .wound], .everyone)),
        "Cabin": (.loseCards(1, .opener), .loseCards(2, .opener)),
        "Cave": (.damage(6, .opener), .both(.damage(6, .opener), .conditions([.stun], .opener))),
        "Clearing": (.elementsInert, .noConsuming),
        "Corridor": (.conditions([.immobilize], .everyone), .conditions([.stun], .everyone)),
        "Crossroads": (.discardCards(2, .everyone), .loseCards(1, .everyone)),
        "Dead-End": (.damage(3, .everyone), .damage(7, .everyone)),
        "Den": (.enemyRetaliate(2, range: 3, permanent: false), .enemyRetaliate(2, range: 3, permanent: true)),
        "Encampment": (.upgradeNormalInRoom, .replaceInPreviousRoom(elite: true, count: 1)),
        "Hallway": (.consumeSmallItem, .consumeAndSpendAll),
        "Hovel": (.conditions([.wound], .everyone), .conditions([.wound], .everyone, permanent: true)),
        "Library": (.enemyStrengthen(permanent: false), .enemyStrengthen(permanent: true)),
        "Passage": (.eliteInvisible, .enemyHealEachTurn(1)),
        "Road": (.replaceInPreviousRoom(elite: false, count: 1), .replaceInPreviousRoom(elite: false, count: 2)),
        "Sewer": (.conditions([.muddle], .everyone), .conditions([.muddle], .everyone, permanent: true)),
        "Trail": (.spendAllSpendable, .enemyMoveAndRange(1)),
        "Tunnel": (.curses(times: 1), .curses(times: 3)),
    ]
}

/// How hard the players make the dungeon (RD-6).
enum DungeonPenaltyLevel: String, Codable, CaseIterable {
    /// No penalties.
    case none
    /// The suggested: none in the first room, the second room's minor, the third's major.
    case suggested
    /// The major penalty of every room, the first included.
    case major

    var label: String {
        switch self {
        case .none: return "None"
        case .suggested: return "Suggested"
        case .major: return "Major"
        }
    }

    var explanation: String {
        switch self {
        case .none: return "No room's penalty falls."
        case .suggested: return "The second room's minor penalty, the third's major."
        case .major: return "Every room's major penalty, the first's as you start."
        }
    }

    /// The penalty of the room at `depth` (1–3), if any.
    func penalty(of room: String, depth: Int) -> DungeonPenalty? {
        guard let both = DungeonPenalty.byRoom[room] else { return nil }
        switch self {
        case .none: return nil
        case .suggested: return depth == 2 ? both.minor : depth >= 3 ? both.major : nil
        case .major: return both.major
        }
    }
}
