import Foundation

/// Identifies a figure on the board.
enum PieceID: Hashable, Codable, Sendable {
    /// A player character, identified by their GameCharacter.id (e.g. "gh-brute")
    case character(String)
    /// A monster standee, identified by monster name + standee number
    case monster(name: String, standee: Int)
    /// A summon, identified by its UUID string
    case summon(id: String)
    /// An objective/escort token
    case objective(id: Int)
}

/// A fixed order (characters, monsters by name and standee, summons, objectives) for every place
/// where figures are visited one by one, so a game doesn't depend on dictionary iteration order.
extension PieceID: Comparable {
    private var sortKey: (Int, String, Int) {
        switch self {
        case .character(let id): return (0, id, 0)
        case .monster(let name, let standee): return (1, name, standee)
        case .summon(let id): return (2, id, 0)
        case .objective(let id): return (3, "", id)
        }
    }

    static func < (lhs: PieceID, rhs: PieceID) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

extension PieceID: CustomStringConvertible {
    var description: String {
        switch self {
        case .character(let id):
            return "char(\(id))"
        case .monster(let name, let standee):
            return "\(name)#\(standee)"
        case .summon(let id):
            return "summon(\(id.prefix(8)))"
        case .objective(let id):
            return "obj(\(id))"
        }
    }
}
