import SwiftUI

struct PartyTreasuresSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var game: GameState { gameManager.game }

    private var groupedTreasures: [(scenario: String, treasures: [String])] {
        var groups: [String: [String]] = [:]
        for treasure in game.lootedTreasures {
            // Format: "{edition}-{scenarioIndex}-{treasureIndex}"
            let parts = treasure.split(separator: "-", maxSplits: 2)
            if parts.count >= 3 {
                let key = "\(parts[0])-\(parts[1])"
                groups[key, default: []].append(String(parts[2]))
            }
        }
        return groups.sorted(by: { $0.key < $1.key }).map { key, treasures in
            (scenario: key, treasures: treasures.sorted())
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if game.lootedTreasures.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "diamond")
                            .font(.system(size: 48))
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("No treasures collected yet")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Summary
                            HStack {
                                Image(systemName: "diamond.fill")
                                    .foregroundStyle(.yellow)
                                Text("Total Treasures: \(game.lootedTreasures.count)")
                                    .font(.headline)
                                    .foregroundStyle(GlavenTheme.primaryText)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlavenTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            // Per-scenario
                            ForEach(groupedTreasures, id: \.scenario) { group in
                                scenarioTreasureSection(group.scenario, treasures: group.treasures)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Party Treasures")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func scenarioTreasureSection(_ scenarioKey: String, treasures: [String]) -> some View {
        let parts = scenarioKey.split(separator: "-", maxSplits: 1)
        let edition = parts.count > 0 ? String(parts[0]) : ""
        let index = parts.count > 1 ? String(parts[1]) : ""
        let scenarioName = gameManager.editionStore.scenarioData(index: index, edition: edition)?.name ?? ""

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(GlavenTheme.accentText)
                Text("Scenario #\(index)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlavenTheme.primaryText)
                if !scenarioName.isEmpty {
                    Text(scenarioName)
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                Spacer()
            }

            ForEach(treasures, id: \.self) { treasure in
                HStack(spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Treasure #\(treasure)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(GlavenTheme.primaryText)
                        if let idx = Int(treasure),
                           let reward = gameManager.editionStore.treasureReward(index: idx, edition: edition) {
                            Text(gameManager.editionStore.treasureLabel(rewardString: reward, edition: edition))
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
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
