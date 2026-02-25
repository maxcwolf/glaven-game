import SwiftUI

struct MonsterStatsSheet: View {
    let monster: GameMonster
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editionTheme) private var theme
    @State private var selectedLevel: Int

    init(monster: GameMonster) {
        self.monster = monster
        self._selectedLevel = State(initialValue: monster.level)
    }

    private var monsterData: MonsterData? { monster.monsterData }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monsterHeader
                    levelPicker
                    statsContent
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Monster Stats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var monsterHeader: some View {
        HStack(spacing: 14) {
            ThumbnailImage(
                image: ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name),
                size: 56,
                cornerRadius: 10,
                fallbackColor: monster.isBoss ? GlavenTheme.boss.opacity(0.5) : GlavenTheme.normalType.opacity(0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(theme.titleFont(size: 22))
                    .foregroundStyle(GlavenTheme.primaryText)

                HStack(spacing: 8) {
                    if monster.isBoss {
                        typeBadge("Boss", color: GlavenTheme.boss)
                    } else {
                        typeBadge("Normal + Elite", color: GlavenTheme.normalType)
                    }
                    if monsterData?.flying == true {
                        Label("Flying", systemImage: "bird.fill")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func typeBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Level Picker

    @ViewBuilder
    private var levelPicker: some View {
        VStack(spacing: 6) {
            Text("Level")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)

            HStack(spacing: 4) {
                ForEach(0...7, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        Text("\(level)")
                            .font(.system(size: 16, weight: level == selectedLevel ? .bold : .regular))
                            .monospacedDigit()
                            .frame(width: 36, height: 36)
                            .background(level == selectedLevel ? GlavenTheme.accentText : GlavenTheme.primaryText.opacity(0.08))
                            .foregroundStyle(level == selectedLevel ? .white : GlavenTheme.secondaryText)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedLevel == monster.level {
                Text("Current level")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.positive)
            }
        }
    }

    // MARK: - Stats Content

    @ViewBuilder
    private var statsContent: some View {
        if monster.isBoss {
            if let stat = monsterData?.stat(for: .boss, at: selectedLevel) {
                statCard(stat: stat, label: "Boss", color: GlavenTheme.boss)
            } else {
                noStatsView
            }
        } else {
            let normalStat = monsterData?.stat(for: .normal, at: selectedLevel)
            let eliteStat = monsterData?.stat(for: .elite, at: selectedLevel)

            if normalStat != nil || eliteStat != nil {
                HStack(alignment: .top, spacing: 12) {
                    if let ns = normalStat {
                        statCard(stat: ns, label: "Normal", color: GlavenTheme.normalType)
                    }
                    if let es = eliteStat {
                        statCard(stat: es, label: "Elite", color: GlavenTheme.elite)
                    }
                }
            } else {
                noStatsView
            }
        }
    }

    @ViewBuilder
    private var noStatsView: some View {
        Text("No stats available for level \(selectedLevel)")
            .font(.subheadline)
            .foregroundStyle(GlavenTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - Stat Card

    @ViewBuilder
    private func statCard(stat: MonsterStatModel, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Type label
            Text(label)
                .font(.headline)
                .foregroundStyle(color)

            // Core stats grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                statRow(icon: "heart.fill", label: "Health", value: stat.health, color: .red)
                statRow(icon: "burst.fill", label: "Attack", value: stat.attack, color: color)
                statRow(icon: "figure.walk", label: "Move", value: stat.movement, color: color)
                if let range = stat.range, range.intValue > 0 {
                    statRow(icon: "scope", label: "Range", value: range, color: color)
                }
            }

            // Shield / Retaliate from actions
            if let actions = stat.actions {
                let shields = actions.filter { $0.type == .shield }
                let retaliates = actions.filter { $0.type == .retaliate }

                if !shields.isEmpty || !retaliates.isEmpty {
                    Divider().background(GlavenTheme.primaryText.opacity(0.1))
                    HStack(spacing: 12) {
                        ForEach(shields, id: \.id) { action in
                            statRow(icon: "shield.fill", label: "Shield", value: action.value, color: GlavenTheme.nextPhaseColor)
                        }
                        ForEach(retaliates, id: \.id) { action in
                            statRow(icon: "arrow.uturn.backward", label: "Retaliate", value: action.value, color: .orange)
                        }
                    }
                }

                // Other notable actions
                let otherActions = actions.filter { $0.type != .shield && $0.type != .retaliate && $0.hidden != true }
                if !otherActions.isEmpty {
                    Divider().background(GlavenTheme.primaryText.opacity(0.1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                        ForEach(otherActions, id: \.id) { action in
                            actionLabel(action, color: color)
                        }
                    }
                }
            }

            // Immunities
            if let immunities = stat.immunities, !immunities.isEmpty {
                Divider().background(GlavenTheme.primaryText.opacity(0.1))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Immunities")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    FlowLayout(spacing: 4) {
                        ForEach(immunities, id: \.self) { immunity in
                            HStack(spacing: 3) {
                                BundledImage(
                                    ImageLoader.conditionIcon(immunity.rawValue),
                                    size: 14,
                                    systemName: "bolt.fill"
                                )
                                Text(immunity.rawValue.capitalized)
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Stat Row

    @ViewBuilder
    private func statRow(icon: String, label: String, value: IntOrString?, color: Color) -> some View {
        if let v = value {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(v.intValue)")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(GlavenTheme.primaryText)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
            }
        }
    }

    // MARK: - Action Label

    @ViewBuilder
    private func actionLabel(_ action: ActionModel, color: Color) -> some View {
        HStack(spacing: 4) {
            BundledImage(
                ImageLoader.actionIcon(action.type.rawValue),
                size: 14,
                systemName: MonsterActionRow.actionFallback(action.type)
            )
            Text(actionDescription(action))
                .font(.caption)
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }

    private func actionDescription(_ action: ActionModel) -> String {
        let typeName = action.type.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
        if let value = action.value {
            let prefix: String
            switch action.valueType {
            case .plus: prefix = "+"
            case .minus: prefix = "-"
            default: prefix = ""
            }
            return "\(typeName) \(prefix)\(value.intValue)"
        }
        return typeName
    }
}
