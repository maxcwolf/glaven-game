import SwiftUI

struct ItemDetailSheet: View {
    let item: ItemData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header with item card background
                    headerSection

                    // Properties
                    propertiesSection

                    // Effects & Actions
                    if let effects = item.effects, !effects.isEmpty {
                        actionsSection(title: "Effects", actions: effects)
                    }
                    if let actions = item.actions, !actions.isEmpty {
                        actionsSection(title: "Actions", actions: actions)
                    }

                    // Summon
                    if let summon = item.summon {
                        summonSection(summon)
                    }

                    // Unlock requirements
                    if item.unlockProsperity > 1 || item.unlockScenario != nil || item.random {
                        unlockSection
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Item #\(item.id)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 340, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 10) {
            // Slot icon
            Image(systemName: item.slot.icon)
                .font(.system(size: 36))
                .foregroundStyle(slotColor)
                .frame(width: 64, height: 64)
                .background(slotColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            // Name
            Text(item.name)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.primaryText)
                .multilineTextAlignment(.center)

            // Slot & cost badges
            HStack(spacing: 10) {
                Label(item.slot.displayName, systemImage: item.slot.icon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(slotColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(slotColor.opacity(0.12))
                    .clipShape(Capsule())

                if item.cost > 0 {
                    Label("\(item.cost)g", systemImage: "dollarsign.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.12))
                        .clipShape(Capsule())
                }

                if item.spent {
                    Text("Spent")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }

                if item.consumed {
                    Text("Consumed")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Properties

    @ViewBuilder
    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Properties")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            propertyRow(icon: "number.circle", label: "Item ID", value: item.itemKey.uppercased())
            propertyRow(icon: "doc.on.doc", label: "Available", value: "\(item.count) in shop")

            if item.minusOne > 0 {
                propertyRow(icon: "minus.circle", label: "Penalty", value: "\(item.minusOne) \u{00D7} -1 card\(item.minusOne > 1 ? "s" : "")")
            }

            if item.slots > 1 {
                propertyRow(icon: "square.grid.2x2", label: "Slots Used", value: "\(item.slots)")
            }

            propertyRow(icon: "tag", label: "Edition", value: item.edition.uppercased())
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func propertyRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }

    // MARK: - Actions / Effects

    @ViewBuilder
    private func actionsSection(title: String, actions: [ActionModel]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                actionRow(action)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func actionRow(_ action: ActionModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconForAction(action.type))
                .font(.caption)
                .foregroundStyle(colorForAction(action.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(describeAction(action))
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.primaryText)

                // Sub-actions
                if let subs = action.subActions {
                    ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                        Text("  \(describeAction(sub))")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Summon

    @ViewBuilder
    private func summonSection(_ summon: SummonDataModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summon")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            HStack(spacing: 16) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 24))
                    .foregroundStyle(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summon.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(GlavenTheme.primaryText)

                    HStack(spacing: 12) {
                        statBadge(icon: "heart.fill", value: summon.health.stringValue, color: .red)
                        if let atk = summon.attack { statBadge(icon: "burst.fill", value: atk.stringValue, color: .orange) }
                        if let mov = summon.movement { statBadge(icon: "figure.walk", value: mov.stringValue, color: .blue) }
                        if let rng = summon.range, rng.intValue > 0 { statBadge(icon: "scope", value: rng.stringValue, color: .green) }
                        if summon.flying == true {
                            Image(systemName: "wind")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func statBadge(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock Requirements")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            if item.unlockProsperity > 1 {
                propertyRow(icon: "building.2.crop.circle", label: "Prosperity", value: "Level \(item.unlockProsperity)+")
            }
            if let scenario = item.unlockScenario {
                propertyRow(icon: "map", label: "Scenario", value: "#\(scenario)")
            }
            if item.random {
                propertyRow(icon: "dice", label: "Source", value: "Treasure / Random")
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private var slotColor: Color {
        switch item.slot {
        case .head: return .purple
        case .body: return .blue
        case .legs: return .green
        case .onehand: return .orange
        case .twohand: return .red
        case .small: return .cyan
        }
    }

    private func iconForAction(_ type: ActionType) -> String {
        switch type {
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .retaliate: return "arrow.uturn.left.circle"
        case .move: return "figure.walk"
        case .attack: return "burst.fill"
        case .condition: return "exclamationmark.triangle"
        case .element: return "flame.fill"
        case .push: return "arrow.right.circle"
        case .pull: return "arrow.left.circle"
        case .pierce: return "arrow.right.to.line"
        case .range: return "scope"
        case .target: return "target"
        case .fly: return "wind"
        case .jump: return "arrow.up.circle"
        case .loot: return "dollarsign.circle"
        case .refreshItem, .refreshSpent: return "arrow.counterclockwise"
        case .custom: return "text.bubble"
        default: return "circle.fill"
        }
    }

    private func colorForAction(_ type: ActionType) -> Color {
        switch type {
        case .heal: return .red
        case .shield: return .blue
        case .retaliate: return .orange
        case .move: return .blue
        case .attack: return .red
        case .condition: return .yellow
        case .element: return .purple
        case .loot: return .yellow
        default: return GlavenTheme.secondaryText
        }
    }

    private func describeAction(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        switch action.type {
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .move: return "+\(value) Move"
        case .attack: return "+\(value) Attack"
        case .condition: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case .element: return "\(value.capitalized) Element"
        case .push: return "Push \(value)"
        case .pull: return "Pull \(value)"
        case .pierce: return "Pierce \(value)"
        case .range: return "+\(value) Range"
        case .target: return "+\(value) Target"
        case .fly: return "Flying"
        case .jump: return "Jump"
        case .loot: return "Loot \(value)"
        case .refreshItem, .refreshSpent: return "Refresh spent items"
        case .custom: return value
        default: return "\(action.type.rawValue.capitalized) \(value)"
        }
    }
}
