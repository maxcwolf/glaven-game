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
        let edition = scenario.data.edition
        let key = "\(edition)-\(scenario.data.index)-\(index)"
        gameManager.game.lootedTreasures.insert(key)
        gameManager.game.campaignLog.append(
            CampaignLogEntry(
                type: .treasureLooted,
                message: "Treasure #\(index) looted in Scenario #\(scenario.data.index)"
            )
        )

        // Apply the treasure reward
        if let treasureIdx = Int(index),
           let rewardString = gameManager.editionStore.treasureReward(index: treasureIdx, edition: edition) {
            applyTreasureReward(rewardString, edition: edition)
        }
    }

    /// Apply a treasure reward string to the active party/characters.
    private func applyTreasureReward(_ rewardString: String, edition: String) {
        let parts = rewardString.split(separator: "|").map(String.init)
        for part in parts {
            applySingleReward(part, edition: edition)
        }
    }

    private func applySingleReward(_ reward: String, edition: String) {
        let components = reward.split(separator: ":", maxSplits: 1).map(String.init)
        let type = components[0]
        let value = components.count > 1 ? components[1] : nil

        switch type {
        case "gold", "goldFh":
            if let v = value.flatMap({ Int($0) }) {
                // Distribute gold to the active (non-exhausted) character with lowest gold, or all equally
                for character in gameManager.game.activeCharacters where !character.exhausted {
                    character.loot += v
                    break // Give to first active character (the looter)
                }
            }
        case "experience", "experienceFh":
            if let v = value.flatMap({ Int($0) }) {
                for character in gameManager.game.activeCharacters where !character.exhausted {
                    character.experience += v
                    break
                }
            }
        case "item", "itemFh":
            // Unlock specific items for the party
            if let value = value {
                for idStr in value.split(separator: "+") {
                    if let id = Int(idStr) {
                        gameManager.game.unlockedItems.insert("\(edition)-\(id)")
                    }
                }
            }
        case "itemDesign":
            if let value = value, let id = Int(value) {
                gameManager.game.unlockedItems.insert("\(edition)-\(id)")
            }
        case "randomItemDesign":
            // Random item design — player should draw from random item pool
            // Handled via the existing random item dialog flow
            break
        case "scenario":
            // Scenario unlock is handled by scenario completion flow
            break
        case "battleGoal":
            if let v = value.flatMap({ Int($0) }) {
                for character in gameManager.game.activeCharacters where !character.exhausted {
                    character.battleGoalProgress += v
                    break
                }
            }
        case "damage":
            if let v = value.flatMap({ Int($0) }) {
                for character in gameManager.game.activeCharacters where !character.exhausted {
                    gameManager.entityManager.changeHealth(character, amount: -v)
                    break
                }
            }
        case "heal":
            if let v = value.flatMap({ Int($0) }) {
                for character in gameManager.game.activeCharacters where !character.exhausted {
                    gameManager.entityManager.changeHealth(character, amount: v)
                    break
                }
            }
        case "condition":
            if let value = value {
                let conditions = value.split(separator: "+").map(String.init)
                for condStr in conditions {
                    if let condName = ConditionName(rawValue: condStr) {
                        for character in gameManager.game.activeCharacters where !character.exhausted {
                            gameManager.entityManager.addCondition(condName, to: character)
                            break
                        }
                    }
                }
            }
        case "partyAchievement":
            if let value = value {
                gameManager.game.partyAchievements.insert(value)
            }
        default:
            break
        }
    }
}
