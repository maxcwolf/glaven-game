import Foundation

enum EntityConditionState: String, Codable, CaseIterable {
    case new, normal, expire, removed, turn
}
