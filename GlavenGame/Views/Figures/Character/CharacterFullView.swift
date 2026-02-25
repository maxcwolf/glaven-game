import SwiftUI

struct CharacterFullView: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editionTheme) private var theme

    private var className: String {
        character.name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var characterColor: Color {
        Color(hex: character.color) ?? .blue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Hero section
                    heroSection

                    // Health bar
                    healthSection

                    // Stats grid
                    statsGrid

                    // Active conditions
                    if !character.entityConditions.isEmpty {
                        conditionsSection
                    }

                    // Summons
                    if !character.summons.isEmpty {
                        summonsSection
                    }

                    // Hand summary
                    handSummary

                    // Items summary
                    if !character.items.isEmpty {
                        itemsSummary
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle(character.title.isEmpty ? className : character.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        HStack(spacing: 16) {
            ThumbnailImage(
                image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                size: 80,
                cornerRadius: 16,
                fallbackColor: characterColor
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(className)
                    .font(theme.titleFont(size: 22))
                    .foregroundStyle(GlavenTheme.primaryText)

                if !character.title.isEmpty {
                    Text(character.title)
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }

                HStack(spacing: 12) {
                    Label("Lv \(character.level)", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(characterColor)

                    if character.initiative > 0 {
                        Label("Init \(character.initiative)", systemImage: "number.circle")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.accentText)
                    }
                }

                // Status badges
                HStack(spacing: 6) {
                    if character.exhausted {
                        statusBadge("Exhausted", color: .red)
                    }
                    if character.absent {
                        statusBadge("Absent", color: .gray)
                    }
                    if character.longRest {
                        statusBadge("Long Rest", color: .blue)
                    }
                    if character.retired {
                        statusBadge("Retired", color: .purple)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [characterColor.opacity(0.15), GlavenTheme.cardBackground],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Health

    @ViewBuilder
    private var healthSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Health")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(character.health) / \(character.maxHealth)")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(healthColor)
            }

            GeometryReader { geo in
                let fraction = character.maxHealth > 0 ? Double(character.health) / Double(character.maxHealth) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(GlavenTheme.primaryText.opacity(0.1))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(healthColor.opacity(0.7))
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 12)

            HStack(spacing: 20) {
                Button {
                    gameManager.entityManager.changeHealth(character, amount: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    gameManager.entityManager.changeHealth(character, amount: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var healthColor: Color {
        let fraction = character.maxHealth > 0 ? Double(character.health) / Double(character.maxHealth) : 0
        if fraction > 0.5 { return .green }
        if fraction > 0.25 { return .orange }
        return .red
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard("XP", value: "\(character.experience)", icon: "star.fill", color: .blue)
            statCard("Gold", value: "\(character.loot)", icon: "dollarsign.circle.fill", color: .yellow)
            statCard("Hand", value: "\(character.handSize)", icon: "hand.raised.fill", color: .orange)
            statCard("Items", value: "\(character.items.count)", icon: "bag.fill", color: .purple)
        }
    }

    @ViewBuilder
    private func statCard(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(GlavenTheme.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Conditions

    @ViewBuilder
    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Active Conditions")
                    .font(.subheadline.weight(.semibold))
            }

            FlowLayout(spacing: 6) {
                ForEach(character.entityConditions, id: \.name) { ec in
                    HStack(spacing: 4) {
                        Text(ec.name.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                        if ec.value > 0 {
                            Text("\(ec.value)")
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(conditionColor(ec.name).opacity(0.15))
                    .foregroundStyle(conditionColor(ec.name))
                    .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func conditionColor(_ name: ConditionName) -> Color {
        let types = Condition.conditionTypes(for: name)
        if types.contains(.positive) { return .green }
        if types.contains(.negative) { return .red }
        return .orange
    }

    // MARK: - Summons

    @ViewBuilder
    private var summonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("Summons (\(character.summons.count))")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(character.summons, id: \.uuid) { summon in
                HStack {
                    Text(summon.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    Spacer()
                    Text("\(summon.health)/\(summon.maxHealth) HP")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(summon.dead ? .red : GlavenTheme.secondaryText)
                    if summon.dead {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Hand Summary

    @ViewBuilder
    private var handSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(GlavenTheme.accentText)
                Text("Ability Cards")
                    .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 16) {
                miniStat("In Hand", value: character.handCards.count, color: .green)
                miniStat("Discard", value: character.discardedCards.count, color: .orange)
                miniStat("Lost", value: character.lostCards.count, color: .red)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func miniStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Items Summary

    @ViewBuilder
    private var itemsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.purple)
                Text("Equipped Items (\(character.items.count))")
                    .font(.subheadline.weight(.semibold))
            }

            ForEach(character.items, id: \.self) { itemKey in
                let parts = itemKey.split(separator: "-", maxSplits: 1)
                let edition = parts.count > 0 ? String(parts[0]) : ""
                let itemId = parts.count > 1 ? Int(String(parts[1])) ?? 0 : 0
                let item = gameManager.editionStore.itemData(id: itemId, edition: edition)

                HStack {
                    Image(systemName: item?.slot.icon ?? "bag")
                        .foregroundStyle(.purple.opacity(0.7))
                        .frame(width: 20)
                    Text(item?.name ?? "Item \(itemId)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    Spacer()
                    if let item = item {
                        Text("\(item.cost)g")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
