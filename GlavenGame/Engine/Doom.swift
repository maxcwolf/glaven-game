import Foundation

/// The Doomstalker's dooms (GH): a doom card's bottom half puts the character's token on one
/// enemy, and the card stays in the active area with its effect on that enemy until the enemy
/// dies or another doom is played. A doom is kept as a marker on the doomed monster
/// ("doom:<character id>:<card id>:<marks>"), so it is saved with the game and undone with it.
struct Doom: Equatable, Hashable {
    let characterID: String
    let cardId: Int
    /// Inescapable Fate's marker, advanced at the start of the owner's turns.
    var marks: Int = 0

    static let prefix = "doom:"

    var marker: String { "\(Self.prefix)\(characterID):\(cardId):\(marks)" }

    init(characterID: String, cardId: Int, marks: Int = 0) {
        self.characterID = characterID
        self.cardId = cardId
        self.marks = marks
    }

    init?(marker: String) {
        guard marker.hasPrefix(Self.prefix) else { return nil }
        let parts = marker.dropFirst(Self.prefix.count).split(separator: ":", omittingEmptySubsequences: false)
        // The character id may itself contain colons in principle; the card and marks are the last two.
        guard parts.count >= 3, let card = Int(parts[parts.count - 2]), let marks = Int(parts[parts.count - 1]) else { return nil }
        self.characterID = parts.dropLast(2).joined(separator: ":")
        self.cardId = card
        self.marks = marks
    }

    /// The dooms on a figure, from its markers.
    static func dooms(in markers: [String]) -> [Doom] { markers.compactMap(Doom.init(marker:)) }

    /// What this doom does while it lasts.
    var effect: DoomEffect? { DoomEffect.byCard[cardId] }
}

/// Who a doom's attack bonus is for.
enum DoomBeneficiary: Equatable {
    /// The doom's owner only ("Add +2 Attack to all your attacks targeting this enemy").
    case owner
    /// Everyone on the owner's side but the owner ("All allies add +1 Attack…").
    case allies
    /// The owner and everyone on their side ("You and all allies…").
    case ownerAndAllies
    /// Summoned allies only ("All summoned allies add +2 Attack…").
    case summons
}

/// A doom's effect on its enemy, as printed on the bottom half of each doom card.
enum DoomEffect: Equatable {
    case attackBonus(Int, DoomBeneficiary)
    /// +X where X is the attack's range minus the hexes to the enemy (Predator and Prey).
    case rangeGapBonus
    case pierce(Int, DoomBeneficiary)
    case advantage(DoomBeneficiary)
    case curse(DoomBeneficiary)
    /// The enemy's Attack, Move and Range are reduced (Crippling Noose).
    case statPenalty(Int)
    /// The enemy suffers damage at the start of each of its turns (Race to the Grave).
    case damageAtTurnStart(Int)
    /// The owner heals each time the enemy suffers damage (Sap Life).
    case healOwnerWhenDamaged(Int)
    /// What happens when the enemy dies.
    case onDeath(DoomDeath)
    /// On death within range 2 of another enemy, every doom moves to that enemy (Rising Momentum).
    case transferOnDeath(range: Int)
    /// Advanced at the start of the owner's next turns; after that many the enemy dies (Inescapable Fate).
    case countdown(Int)

    /// By Doomstalker card id (Gloomhaven).
    static let byCard: [Int: DoomEffect] = [
        376: .attackBonus(2, .owner),                    // Rain of Arrows
        377: .statPenalty(1),                            // Crippling Noose
        378: .onDeath(.teleportOwner),                   // Felling Swoop
        379: .onDeath(.healOwner(4)),                    // Vital Charge
        380: .damageAtTurnStart(2),                      // Race to the Grave
        381: .attackBonus(1, .allies),                   // Multi-Pronged Assault
        382: .onDeath(.damageAdjacent(3)),               // Detonation
        383: .onDeath(.moveAdjacent(1)),                 // Frightening Curse
        388: .healOwnerWhenDamaged(2),                   // Sap Life
        389: .attackBonus(2, .summons),                  // The Hunt Begins
        391: .pierce(2, .ownerAndAllies),                // Expose
        393: .onDeath(.attack(value: 2, range: 3, targets: 3)), // Darkened Skies
        395: .advantage(.ownerAndAllies),                // Singular Focus
        397: .countdown(3),                              // Inescapable Fate
        399: .onDeath(.healOwnerAndAllies(2)),           // Nature's Hunger
        402: .curse(.ownerAndAllies),                    // Crashing Wave
        403: .transferOnDeath(range: 2),                 // Rising Momentum
        405: .rangeGapBonus,                             // Predator and Prey
    ]

    /// Whether `attacker` gets a bonus meant for `beneficiary` from `owner`'s doom.
    static func benefits(_ beneficiary: DoomBeneficiary, attacker: PieceID, owner: PieceID, isAlly: Bool,
                         isSummon: Bool) -> Bool {
        switch beneficiary {
        case .owner: return attacker == owner
        case .allies: return attacker != owner && isAlly
        case .ownerAndAllies: return attacker == owner || isAlly
        case .summons: return isSummon && isAlly
        }
    }
}

/// What a doom does as its enemy dies.
enum DoomDeath: Equatable {
    /// The owner teleports to the hex the enemy died in (Felling Swoop).
    case teleportOwner
    case healOwner(Int)
    /// The owner and every ally heal (Nature's Hunger).
    case healOwnerAndAllies(Int)
    /// Every enemy beside the hex it died in suffers damage (Detonation).
    case damageAdjacent(Int)
    /// Every enemy beside the hex it died in moves, the owner choosing where (Frightening Curse).
    case moveAdjacent(Int)
    /// The owner performs an attack (Darkened Skies: Attack 2, Range 3, Target 3).
    case attack(value: Int, range: Int, targets: Int)
}

extension MonsterAttackSpec {
    /// Crippling Noose: Attack and (for a ranged attack) Range reduced, never below 0 and 1.
    func reduced(by penalty: Int) -> MonsterAttackSpec {
        guard penalty > 0 else { return self }
        var spec = self
        spec.value = max(0, value - penalty)
        if isRanged { spec.range = max(1, range - penalty) }
        return spec
    }
}

extension GameMonsterEntity {
    /// Crippling Noose: how much the dooms on this monster reduce its Attack, Move and Range.
    var doomPenalty: Int {
        Doom.dooms(in: markers).reduce(0) { total, doom in
            if case .statPenalty(let n)? = doom.effect { return total + n }
            return total
        }
    }
}
