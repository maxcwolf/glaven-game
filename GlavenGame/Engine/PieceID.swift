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
