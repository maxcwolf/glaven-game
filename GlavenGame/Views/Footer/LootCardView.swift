import SwiftUI

struct LootCardView: View {
    let loot: Loot
    let playerCount: Int

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(tintColor)

            Text(valueText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(GlavenTheme.primaryText)

            Text(typeName)
                .font(.system(size: 8))
                .foregroundStyle(tintColor.opacity(0.8))
        }
    }

    private var value: Int {
        switch playerCount {
        case 2: return loot.value2P
        case 3: return loot.value3P
        default: return loot.value4P
        }
    }

    private var valueText: String {
        switch loot.type {
        case .random_item: return "?"
        case .special1, .special2: return "*"
        default: return "\(value)"
        }
    }

    private var typeName: String {
        switch loot.type {
        case .money: return "Gold"
        case .lumber: return "Lumber"
        case .metal: return "Metal"
        case .hide: return "Hide"
        case .random_item: return "Item"
        case .special1, .special2: return "Special"
        default: return loot.type.rawValue.capitalized
        }
    }

    private var iconName: String {
        switch lootClass(for: loot.type) {
        case .money: return "dollarsign.circle.fill"
        case .material_resources: return "cube.fill"
        case .herb_resources: return "leaf.fill"
        case .random_item: return "questionmark.circle.fill"
        case .special: return "star.fill"
        }
    }

    private var tintColor: Color {
        switch lootClass(for: loot.type) {
        case .money: return .yellow
        case .material_resources: return .brown
        case .herb_resources: return .green
        case .random_item: return .purple
        case .special: return .orange
        }
    }
}
