import Foundation

enum SummonState: String, Codable, CaseIterable {
    case new = "new"
    case active = "true"
    case spent = "false"
}
