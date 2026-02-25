import SwiftUI

/// Displays scenario setup information before the first round begins.
/// Shows monsters, objectives, and loot deck configuration.
struct ScenarioSetupView: View {
    @Environment(GameManager.self) private var gameManager
    @State private var showSpoilers = false

    private var scenario: Scenario? { gameManager.game.scenario }
    private var scenarioData: ScenarioData? { scenario?.data }

    private var playerCount: Int {
        max(2, gameManager.game.activeCharacters.count)
    }

    /// Monsters from initial rooms only (non-spoiler)
    private var initialMonsters: [String] {
        guard let data = scenarioData else { return [] }
        var names: Set<String> = []
        if let rooms = data.rooms {
            for room in rooms where room.isInitial {
                for standee in room.monster ?? [] {
                    if standee.monsterType(forPlayerCount: playerCount) != nil {
                        names.insert(standee.name)
                    }
                }
            }
        }
        return names.sorted()
    }

    /// All monsters in the scenario (spoiler mode)
    private var allMonsters: [String] {
        guard let data = scenarioData else { return [] }
        return (data.monsters ?? []).sorted()
    }

    private var displayedMonsters: [String] {
        showSpoilers ? allMonsters : initialMonsters
    }

    private var objectives: [ObjectiveData] {
        scenarioData?.objectives ?? []
    }

    var body: some View {
        if let data = scenarioData {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "map.fill")
                        .foregroundStyle(GlavenTheme.accentText)
                    Text("Scenario Setup")
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    Spacer()
                    Toggle("Spoilers", isOn: $showSpoilers)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    Text("Spoilers")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }

                // Monster list
                if !displayedMonsters.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Monsters")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        FlowLayout(spacing: 6) {
                            ForEach(displayedMonsters, id: \.self) { name in
                                monsterBadge(name: name, edition: data.edition)
                            }
                        }
                    }
                }

                // Objectives
                if !objectives.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Objectives")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        ForEach(Array(objectives.enumerated()), id: \.offset) { _, obj in
                            HStack(spacing: 8) {
                                Image(systemName: obj.isEscort ? "shield.checkered" : "target")
                                    .font(.caption)
                                    .foregroundStyle(obj.isEscort ? .green : GlavenTheme.accentText)
                                Text(obj.name ?? "Objective")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.primaryText)
                                if let hp = obj.health {
                                    Text("HP: \(hp.stringValue)")
                                        .font(.caption2)
                                        .foregroundStyle(GlavenTheme.secondaryText)
                                }
                                if obj.isEscort {
                                    Text("Escort")
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                // Loot deck config
                if let lootConfig = data.lootDeckConfig {
                    lootConfigSection(lootConfig)
                }

                // Room count
                if let rooms = data.rooms {
                    let initialCount = rooms.filter(\.isInitial).count
                    HStack(spacing: 4) {
                        Image(systemName: "door.left.hand.open")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("\(rooms.count) rooms (\(initialCount) initial)")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func monsterBadge(name: String, edition: String) -> some View {
        HStack(spacing: 4) {
            ThumbnailImage(
                image: ImageLoader.monsterThumbnail(edition: edition, name: name),
                size: 22,
                cornerRadius: 4,
                fallbackColor: .red
            )
            Text(name.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(GlavenTheme.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(GlavenTheme.primaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func lootConfigSection(_ config: LootDeckConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Loot Deck")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(GlavenTheme.secondaryText)

            FlowLayout(spacing: 4) {
                if let v = config.coin1, v > 0 { lootBadge("1 Coin", count: v, color: .yellow) }
                if let v = config.coin2, v > 0 { lootBadge("2 Coin", count: v, color: .yellow) }
                if let v = config.coin3, v > 0 { lootBadge("3 Coin", count: v, color: .yellow) }
                if let v = config.lumber, v > 0 { lootBadge("Lumber", count: v, color: .brown) }
                if let v = config.metal, v > 0 { lootBadge("Metal", count: v, color: .gray) }
                if let v = config.hide, v > 0 { lootBadge("Hide", count: v, color: .orange) }
                if let v = config.arrowvine, v > 0 { lootBadge("Arrowvine", count: v, color: .green) }
                if let v = config.axenut, v > 0 { lootBadge("Axenut", count: v, color: .brown) }
                if let v = config.corpsecap, v > 0 { lootBadge("Corpsecap", count: v, color: .purple) }
                if let v = config.flamefruit, v > 0 { lootBadge("Flamefruit", count: v, color: .red) }
                if let v = config.rockroot, v > 0 { lootBadge("Rockroot", count: v, color: .gray) }
                if let v = config.snowthistle, v > 0 { lootBadge("Snowthistle", count: v, color: .cyan) }
                if let v = config.random, v > 0 { lootBadge("Random", count: v, color: .secondary) }
                if let v = config.special1, v > 0 { lootBadge("Special", count: v, color: .indigo) }
                if let v = config.special2, v > 0 { lootBadge("Special 2", count: v, color: .indigo) }
            }
        }
    }

    @ViewBuilder
    private func lootBadge(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Text("\(count)")
                .fontWeight(.bold)
            Text(label)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

