import Foundation

enum ElementState: String, Codable, CaseIterable {
    case strong, waning, inert, new, consumed, partlyConsumed, always
}
