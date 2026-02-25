import SwiftUI

struct MonsterView: View {
    @Bindable var monster: GameMonster
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.editionTheme) private var theme
    @Environment(\.isCompact) private var isCompact
    @State private var monsterGlow: Double = 0.4
    @State private var showStats = false

    private var monsterAccentColor: Color {
        monster.isBoss ? GlavenTheme.boss : GlavenTheme.elite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            // Top section: info + ability card
            monsterTopSection

            // Standees in flowing grid
            if !monster.aliveEntities.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: (isCompact ? 150 : 200) * scale))], spacing: 6) {
                    ForEach(monster.aliveEntities.sorted(by: { a, b in
                        if a.type != b.type {
                            return a.type == .elite || (a.type == .boss && b.type != .elite)
                        }
                        return a.number < b.number
                    }), id: \.id) { entity in
                        StandeeView(entity: entity, monster: monster)
                    }
                }
            }
        }
        .padding(16 * scale)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(monster.off ? 0.6 : 1.0)
        .saturation(monster.off ? 0.15 : 1.0)
        .animateIf(gameManager.settingsManager.animations, .easeInOut(duration: 0.3), value: monster.off)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(monster.active ? monsterAccentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: monster.active ? monsterAccentColor.opacity(monsterGlow) : Color.black.opacity(0.3), radius: monster.active ? 8 : 4)
        .onChange(of: monster.active) { _, isActive in
            if isActive {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    monsterGlow = 0.8
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    monsterGlow = 0.4
                }
            }
        }
        .contextMenu {
            Button { showStats = true } label: {
                Label("View Stats", systemImage: "chart.bar")
            }
            Button {
                monster.off.toggle()
            } label: {
                Label(monster.off ? "Show" : "Hide", systemImage: monster.off ? "eye" : "eye.slash")
            }
            Divider()
            Button(role: .destructive) {
                gameManager.game.figures.removeAll { $0.id == "mon-\(monster.edition)-\(monster.name)" }
            } label: {
                Label("Remove Monster", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showStats) {
            MonsterStatsSheet(monster: monster)
        }
        .onTapGesture(count: 2) {
            if gameManager.game.state == .next {
                gameManager.roundManager.toggleFigure(.monster(monster))
            }
        }
    }

    // MARK: - Top Section

    @ViewBuilder
    private var monsterInfoColumn: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack {
                ThumbnailImage(
                    image: ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name),
                    size: 40,
                    cornerRadius: 8,
                    fallbackColor: monster.isBoss ? GlavenTheme.boss.opacity(0.5) : GlavenTheme.normalType.opacity(0.5)
                )

                VStack(alignment: .leading) {
                    Button { showStats = true } label: {
                        Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(theme.titleFont(size: 18 * scale))
                            .foregroundStyle(GlavenTheme.primaryText)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Button {
                            monster.level = max(0, monster.level - 1)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(monster.level <= 0)

                        Text("Level \(monster.level)")
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(GlavenTheme.secondaryText)

                        Button {
                            monster.level = min(7, monster.level + 1)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .disabled(monster.level >= 7)
                    }
                }

                Spacer()

                Button {
                    monster.off.toggle()
                } label: {
                    Image(systemName: monster.off ? "eye.slash" : "eye")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(monster.off ? GlavenTheme.secondaryText : GlavenTheme.primaryText)
                        .padding(6 * scale)
                        .background(GlavenTheme.primaryText.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            monsterStatsBlock

            // Entity type pickers
            if !monster.isBoss {
                HStack(spacing: 12) {
                    StandeePickerView(label: "Normal", type: .normal, monster: monster, color: GlavenTheme.normalType)
                    StandeePickerView(label: "Elite", type: .elite, monster: monster, color: GlavenTheme.elite)
                }
            } else {
                StandeePickerView(label: "Boss", type: .boss, monster: monster, color: GlavenTheme.boss)
            }
        }
    }

    @ViewBuilder
    private var monsterTopSection: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: 8 * scale) {
                monsterInfoColumn
                if let ability = gameManager.monsterManager.currentAbility(for: monster) {
                    MonsterAbilityView(ability: ability, monster: monster)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12 * scale) {
                monsterInfoColumn
                if let ability = gameManager.monsterManager.currentAbility(for: monster) {
                    MonsterAbilityView(ability: ability, monster: monster)
                        .frame(maxWidth: 300 * scale)
                }
            }
        }
    }

    @ViewBuilder
    private var monsterStatsBlock: some View {
        if monster.isBoss {
            if let stat = monster.stat(for: .boss) {
                singleStatRow(stat: stat, color: GlavenTheme.boss)
            }
        } else {
            let normalStat = monster.stat(for: .normal)
            let eliteStat = monster.stat(for: .elite)
            if normalStat != nil || eliteStat != nil {
                HStack(spacing: 0) {
                    if let ns = normalStat {
                        statColumn(stat: ns, label: "Normal", color: GlavenTheme.normalType)
                    }
                    if normalStat != nil && eliteStat != nil {
                        Divider()
                            .frame(height: 50 * scale)
                            .background(GlavenTheme.primaryText.opacity(0.15))
                    }
                    if let es = eliteStat {
                        statColumn(stat: es, label: "Elite", color: GlavenTheme.elite)
                    }
                }
                .padding(.vertical, 6 * scale)
                .padding(.horizontal, 8 * scale)
                .background(GlavenTheme.primaryText.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func statColumn(stat: MonsterStatModel, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(label)
                .font(.system(size: 11 * scale))
                .fontWeight(.bold)
                .foregroundStyle(color)
            HStack(spacing: 10 * scale) {
                statItem(icon: "hp", value: stat.health, color: color)
                statItem(icon: "attack", value: stat.attack, color: color)
                statItem(icon: "move", value: stat.movement, color: color)
                if let range = stat.range, range.intValue > 0 {
                    statItem(icon: "range", value: range, color: color)
                }
                // Shield from stat actions
                if let actions = stat.actions {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        if action.type == .shield, let v = action.value {
                            HStack(spacing: 2) {
                                GameIcon(
                                    image: ImageLoader.actionIcon("shield"),
                                    fallbackSystemName: "shield.fill",
                                    size: 14,
                                    color: color
                                )
                                Text("\(v.intValue)")
                                    .font(.system(size: 12 * scale))
                                    .fontWeight(.bold)
                                    .foregroundStyle(color)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4 * scale)
    }

    @ViewBuilder
    private func singleStatRow(stat: MonsterStatModel, color: Color) -> some View {
        HStack(spacing: 10 * scale) {
            statItem(icon: "hp", value: stat.health, color: color)
            statItem(icon: "attack", value: stat.attack, color: color)
            statItem(icon: "move", value: stat.movement, color: color)
            if let range = stat.range, range.intValue > 0 {
                statItem(icon: "range", value: range, color: color)
            }
            // Show shield from actions
            if let actions = stat.actions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    if action.type == .shield, let v = action.value {
                        HStack(spacing: 2) {
                            GameIcon(image: ImageLoader.actionIcon("shield"), fallbackSystemName: "shield.fill", size: 14, color: color)
                            Text("\(v.intValue)")
                                .font(.system(size: 12 * scale))
                                .fontWeight(.bold)
                                .foregroundStyle(color)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6 * scale)
        .padding(.horizontal, 8 * scale)
        .background(GlavenTheme.primaryText.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func statItem(icon: String, value: IntOrString?, color: Color) -> some View {
        if let v = value {
            HStack(spacing: 2) {
                GameIcon(
                    image: statImage(icon),
                    fallbackSystemName: statFallback(icon),
                    size: 14,
                    color: color
                )
                Text("\(v.intValue)")
                    .font(.system(size: 12 * scale))
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
    }

    private func statImage(_ icon: String) -> PlatformImage? {
        // stats/ has diamond-shaped icons; action/ has the same icons in action style
        ImageLoader.statsIcon(icon) ?? ImageLoader.actionIcon(icon == "hp" ? "heal" : icon)
    }

    private func statFallback(_ icon: String) -> String {
        switch icon {
        case "hp": return "heart.fill"
        case "attack": return "burst.fill"
        case "move": return "figure.walk"
        case "range": return "scope"
        case "shield": return "shield.fill"
        default: return "circle.fill"
        }
    }
}
