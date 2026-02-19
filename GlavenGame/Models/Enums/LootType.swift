import Foundation

enum LootType: String, Codable, CaseIterable {
    case money
    case lumber, metal, hide
    case arrowvine, axenut, corpsecap, flamefruit, rockroot, snowthistle
    case random_item
    case special1, special2
}

enum LootClass: String, Codable, CaseIterable {
    case money, material_resources, herb_resources, random_item, special
}

func lootClass(for type: LootType) -> LootClass {
    switch type {
    case .money: return .money
    case .lumber, .metal, .hide: return .material_resources
    case .arrowvine, .axenut, .corpsecap, .flamefruit, .rockroot, .snowthistle: return .herb_resources
    case .random_item: return .random_item
    case .special1, .special2: return .special
    }
}
