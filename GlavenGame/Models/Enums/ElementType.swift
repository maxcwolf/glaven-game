import Foundation

enum ElementType: String, Codable, CaseIterable {
    case fire, ice, air, earth, light, dark, wild

    static let gameElements: [ElementType] = [.fire, .ice, .air, .earth, .light, .dark]
}
