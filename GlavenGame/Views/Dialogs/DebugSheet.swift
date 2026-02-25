import SwiftUI

struct DebugSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var logOutput = ""

    private var game: GameState { gameManager.game }

    var body: some View {
        NavigationStack {
            List {
                gameStateSection
                scenarioSection
                campaignSection
                charactersSection
                decksSection
                dataStoreSection
                actionsSection
                logSection
            }
            .scrollContentBackground(.hidden)
            .background(GlavenTheme.background)
            .navigationTitle("Debug")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Sections

    @ViewBuilder
    private var gameStateSection: some View {
        Section("Game State") {
            debugRow("Edition", value: game.edition ?? "none")
            debugRow("Phase", value: game.state.rawValue)
            debugRow("Round", value: "\(game.round)")
            debugRow("Level", value: "\(game.level)")
            debugRow("Characters", value: "\(game.characters.count)")
            debugRow("Monsters", value: "\(game.monsters.count)")
            debugRow("Objectives", value: "\(game.objectives.count)")
            debugRow("Total Figures", value: "\(game.figures.count)")
        }
    }

    @ViewBuilder
    private var scenarioSection: some View {
        Section("Scenario") {
            if let scenario = game.scenario {
                debugRow("Index", value: scenario.data.index)
                debugRow("Name", value: scenario.data.name)
                debugRow("Edition", value: scenario.data.edition)
                debugRow("Rooms Revealed", value: "\(scenario.revealedRooms.count)")
                debugRow("Rules Applied", value: "\(scenario.appliedRules.count)")
            } else {
                Text("No active scenario")
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var campaignSection: some View {
        Section("Campaign") {
            debugRow("Party", value: game.partyName.isEmpty ? "(unnamed)" : game.partyName)
            debugRow("Reputation", value: "\(game.partyReputation)")
            debugRow("Prosperity", value: "\(game.partyProsperity)")
            debugRow("Completed Scenarios", value: "\(game.completedScenarios.count)")
            debugRow("Global Achievements", value: "\(game.globalAchievements.count)")
            debugRow("Party Achievements", value: "\(game.partyAchievements.count)")
            debugRow("Looted Treasures", value: "\(game.lootedTreasures.count)")
            debugRow("Retired Characters", value: "\(game.retiredCharacters.count)")
            debugRow("Campaign Log", value: "\(game.campaignLog.count) entries")
        }
    }

    @ViewBuilder
    private var charactersSection: some View {
        Section("Characters") {
            ForEach(game.characters, id: \.id) { character in
                DisclosureGroup {
                    characterDebugRows(character)
                } label: {
                    HStack {
                        Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                            .fontWeight(.medium)
                        Spacer()
                        Text("Lv \(character.level)")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func characterDebugRows(_ character: GameCharacter) -> some View {
        debugRow("Level", value: "\(character.level)")
        debugRow("HP", value: "\(character.health)/\(character.maxHealth)")
        debugRow("XP", value: "\(character.experience)")
        debugRow("Gold", value: "\(character.loot)")
        debugRow("Initiative", value: "\(character.initiative)")
        debugRow("Hand", value: "\(character.handCards.count)/\(character.handSize)")
        debugRow("Items", value: "\(character.items.count)")
        debugRow("Conditions", value: "\(character.entityConditions.count)")
        debugRow("Summons", value: "\(character.summons.count)")
        debugRow("Perks", value: "\(character.selectedPerks.reduce(0, +))")
        debugRow("Exhausted", value: "\(character.exhausted)")
        debugRow("Active", value: "\(character.active)")
    }

    @ViewBuilder
    private var decksSection: some View {
        Section("Decks") {
            debugRow("Monster AM", value: "\(game.monsterAttackModifierDeck.cards.count) cards")
            debugRow("Ally AM", value: "\(game.allyAttackModifierDeck.cards.count) cards")
            debugRow("Loot Deck", value: "\(game.lootDeck.cards.count) cards")
        }
    }

    @ViewBuilder
    private var dataStoreSection: some View {
        Section("Data Store") {
            let store = gameManager.editionStore
            debugRow("Editions", value: "\(store.editions.count)")
            ForEach(store.editions) { edition in
                DisclosureGroup(edition.edition) {
                    editionDebugRows(edition.edition)
                }
            }
        }
    }

    @ViewBuilder
    private func editionDebugRows(_ edition: String) -> some View {
        let store = gameManager.editionStore
        debugRow("Characters", value: "\(store.characters(for: edition).count)")
        debugRow("Monsters", value: "\(store.monsters(for: edition).count)")
        debugRow("Scenarios", value: "\(store.scenarios(for: edition).count)")
        debugRow("Items", value: "\(store.items(for: edition).count)")
        debugRow("Treasures", value: "\(store.treasures(for: edition).count)")
        debugRow("Battle Goals", value: "\(store.battleGoals(for: edition).count)")
        debugRow("Personal Quests", value: "\(store.personalQuests(for: edition).count)")
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section("Debug Actions") {
            Button("Force Save") {
                gameManager.saveGame()
                logOutput = "Game saved at \(Date())"
            }
            Button("Export Snapshot to Log") {
                if let data = gameManager.exportGameData(),
                   let json = String(data: data, encoding: .utf8) {
                    let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                    logOutput = "Snapshot size: \(size)\n\(String(json.prefix(2000)))"
                }
            }
            Button("Reset Round") {
                gameManager.pushUndoState()
                game.round = 0
                game.state = .draw
                logOutput = "Round reset to 0"
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        if !logOutput.isEmpty {
            Section("Log") {
                Text(logOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(GlavenTheme.secondaryText)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func debugRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(GlavenTheme.primaryText)
                .textSelection(.enabled)
        }
    }
}
