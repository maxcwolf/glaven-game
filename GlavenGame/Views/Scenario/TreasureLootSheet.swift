import SwiftUI

struct TreasureLootSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var scenario: Scenario? { gameManager.game.scenario }

    private var availableTreasures: [(index: String, roomNumber: Int, looted: Bool)] {
        guard let scenario = scenario else { return [] }
        let edition = scenario.data.edition
        let scenarioIndex = scenario.data.index
        var treasures: [(index: String, roomNumber: Int, looted: Bool)] = []

        for room in scenario.data.rooms ?? [] {
            guard scenario.revealedRooms.contains(room.roomNumber) else { continue }
            for treasure in room.treasures ?? [] {
                let key = "\(edition)-\(scenarioIndex)-\(treasure.stringValue)"
                let looted = gameManager.game.lootedTreasures.contains(key)
                treasures.append((index: treasure.stringValue, roomNumber: room.roomNumber, looted: looted))
            }
        }
        return treasures
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableTreasures.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "diamond")
                            .font(.system(size: 48))
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("No treasures in revealed rooms")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(availableTreasures, id: \.index) { treasure in
                            HStack {
                                Image(systemName: treasure.looted ? "diamond.fill" : "diamond")
                                    .foregroundStyle(treasure.looted ? .green : .yellow)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Treasure #\(treasure.index)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(GlavenTheme.primaryText)
                                    if let label = treasureLabel(for: treasure.index) {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(treasure.looted ? .green : GlavenTheme.accentText)
                                    }
                                    Text("Room \(treasure.roomNumber)")
                                        .font(.caption)
                                        .foregroundStyle(GlavenTheme.secondaryText)
                                }

                                Spacer()

                                if treasure.looted {
                                    Text("Looted")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Loot") {
                                        lootTreasure(treasure.index)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Scenario Treasures")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func treasureLabel(for treasureIndex: String) -> String? {
        guard let scenario = scenario,
              let idx = Int(treasureIndex),
              let rewardString = gameManager.editionStore.treasureReward(index: idx, edition: scenario.data.edition) else {
            return nil
        }
        return gameManager.editionStore.treasureLabel(rewardString: rewardString, edition: scenario.data.edition)
    }

    private func lootTreasure(_ index: String) {
        guard let scenario = scenario else { return }
        let key = "\(scenario.data.edition)-\(scenario.data.index)-\(index)"
        gameManager.game.lootedTreasures.insert(key)
        gameManager.game.campaignLog.append(
            CampaignLogEntry(
                type: .treasureLooted,
                message: "Treasure #\(index) looted in Scenario #\(scenario.data.index)"
            )
        )
    }
}
