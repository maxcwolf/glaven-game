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
        case .story:    return "Story: party level \u{2212}2, never under 0"
        case .easy:     return "Easy: party level \u{2212}1, never under 0"
        case .normal:   return "Normal: the party\u{2019}s level"
        case .hard:     return "Hard: party level +1"
        case .veryHard: return "Very hard: party level +2"
        }
    }
}
