import Foundation

enum DifficultyMode: Int, CaseIterable, Codable {
    case story    = -2
    case easy     = -1
    case normal   =  0
    case hard     =  1
    case veryHard =  2

    var label: String {
        switch self {
        case .story:    return "Story"
        case .easy:     return "Easy"
        case .normal:   return "Normal"
        case .hard:     return "Hard"
        case .veryHard: return "Very Hard"
        }
    }

    var shortLabel: String {
        switch self {
        case .story:    return "Story"
        case .easy:     return "Easy"
        case .normal:   return "Normal"
        case .hard:     return "Hard"
        case .veryHard: return "V.Hard"
        }
    }

    var description: String {
        switch self {
        case .story:    return "Scenario level −2 (min 0). Recommended for learning."
        case .easy:     return "Scenario level −1 (min 0)."
        case .normal:   return "Standard scenario level."
        case .hard:     return "Scenario level +1. Increased monster stats."
        case .veryHard: return "Scenario level +2. Maximum challenge."
        }
    }
}
