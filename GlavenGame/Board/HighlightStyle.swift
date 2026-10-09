import SpriteKit

/// What a highlighted hex is for. Each kind of choice has its own hue, from a colour-blind-safe
/// palette (Okabe–Ito), and its own shape cue, so colour is never the only signal.
enum HighlightStyle: CaseIterable {
    case place, move, jump, fly, teleport, attack, condition, heal, summon, forcedMove

    /// The cue drawn inside the hex besides the tinted fill.
    enum Cue: Equatable {
        /// Solid outline only.
        case outline
        /// Dashed outline (jumping and teleporting skip what's in between).
        case dashed
        /// A second, inner outline (flying).
        case doubleRing
        /// A target reticle (attacks and conditions on enemies).
        case reticle
        /// A plus sign (healing).
        case plus
        /// An arrowhead (push and pull).
        case chevron
        /// A small dot in the centre (where to place something).
        case dot
    }

    var color: SKColor {
        switch self {
        case .place, .summon: return SKColor(red: 0.94, green: 0.89, blue: 0.26, alpha: 1)   // yellow
        case .move, .jump, .fly: return SKColor(red: 0.34, green: 0.71, blue: 0.91, alpha: 1)  // sky blue
        case .teleport: return SKColor(red: 0.0, green: 0.45, blue: 0.70, alpha: 1)          // blue
        case .attack: return SKColor(red: 0.84, green: 0.37, blue: 0.0, alpha: 1)            // vermilion
        case .condition: return SKColor(red: 0.80, green: 0.47, blue: 0.65, alpha: 1)        // reddish purple
        case .heal: return SKColor(red: 0.0, green: 0.62, blue: 0.45, alpha: 1)              // bluish green
        case .forcedMove: return SKColor(red: 0.90, green: 0.62, blue: 0.0, alpha: 1)        // orange
        }
    }

    var cue: Cue {
        switch self {
        case .place: return .dot
        case .summon: return .dot
        case .move: return .outline
        case .jump, .teleport: return .dashed
        case .fly: return .doubleRing
        case .attack, .condition: return .reticle
        case .heal: return .plus
        case .forcedMove: return .chevron
        }
    }

    /// How a choice reads in VoiceOver and in tests.
    var name: String {
        switch self {
        case .place: return "starting hex"
        case .move: return "move"
        case .jump: return "jump"
        case .fly: return "fly"
        case .teleport: return "teleport"
        case .attack: return "attack target"
        case .condition: return "condition target"
        case .heal: return "heal target"
        case .summon: return "summon placement"
        case .forcedMove: return "push or pull"
        }
    }
}
