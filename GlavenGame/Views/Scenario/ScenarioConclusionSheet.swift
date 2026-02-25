import SwiftUI

struct ScenarioConclusionSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    let success: Bool

    private var scenario: Scenario? { gameManager.game.scenario }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Status icon
                    Image(systemName: success ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(success ? GlavenTheme.positive : Color.red)

                    Text(success ? "Scenario Complete!" : "Scenario Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.primaryText)

                    if let scenario = scenario {
                        Text("#\(scenario.data.index) \(scenario.data.name)")
                            .font(.headline)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        // Rewards
                        if success, let rewards = scenario.data.rewards {
                            RewardsSummaryView(rewards: rewards)
                        }

                        // Unlocks
                        if success, let unlocks = scenario.data.unlocks, !unlocks.isEmpty {
                            unlocksSection(unlocks)
                        }

                        // Stats
                        ScenarioStatsView()
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 16)

                    // Actions
                    HStack(spacing: 16) {
                        if success {
                            Button {
                                gameManager.scenarioManager.finishScenario(success: true)
                                dismiss()
                            } label: {
                                Text("Apply Rewards")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {
                                gameManager.scenarioManager.finishScenario(success: false)
                                dismiss()
                            } label: {
                                Text("End Scenario")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle(success ? "Victory" : "Defeat")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func unlocksSection(_ unlocks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unlocked Scenarios")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)
                .padding(.bottom, 2)

            ForEach(unlocks, id: \.self) { scenario in
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(GlavenTheme.accentText)
                    Text("Scenario \(scenario)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Rewards Summary

private struct RewardsSummaryView: View {
    let rewards: ScenarioRewards

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rewards")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)
                .padding(.bottom, 2)

            // Currency rewards
            if let gold = rewards.gold {
                rewardRow(icon: "dollarsign.circle.fill", text: "\(gold.stringValue) Gold per character", color: .yellow)
            }
            if let collectiveGold = rewards.collectiveGold {
                rewardRow(icon: "dollarsign.circle", text: "\(collectiveGold.stringValue) Collective Gold", color: .yellow)
            }
            if let xp = rewards.experience {
                rewardRow(icon: "star.circle.fill", text: "\(xp.stringValue) XP per character", color: .blue)
            }
            if let rep = rewards.reputation {
                rewardRow(icon: "person.2.circle.fill", text: "\(rep > 0 ? "+" : "")\(rep.stringValue) Reputation", color: .purple)
            }
            if let pros = rewards.prosperity {
                rewardRow(icon: "building.2.crop.circle.fill", text: "+\(pros.stringValue) Prosperity", color: .green)
            }

            // Morale / Inspiration (FH)
            if let morale = rewards.morale {
                rewardRow(icon: "face.smiling.inverse", text: "\(morale > 0 ? "+" : "")\(morale.stringValue) Morale", color: .mint)
            }
            if let inspiration = rewards.inspiration {
                rewardRow(icon: "sparkles", text: "+\(inspiration.stringValue) Inspiration", color: .purple)
            }

            // Perks
            if let perks = rewards.perks {
                rewardRow(icon: "list.bullet.rectangle.fill", text: "+\(perks.stringValue) Perk\(perks.intValue == 1 ? "" : "s")", color: .orange)
            }

            // Battle goals
            if let battleGoals = rewards.battleGoals {
                rewardRow(icon: "flag.fill", text: "+\(battleGoals) Battle Goal Check\(battleGoals == 1 ? "" : "s")", color: GlavenTheme.positive)
            }

            // Achievements
            if let globals = rewards.globalAchievements, !globals.isEmpty {
                rewardSection(title: "Global Achievements", icon: "trophy.circle.fill", color: .orange, items: globals)
            }
            if let party = rewards.partyAchievements, !party.isEmpty {
                rewardSection(title: "Party Achievements", icon: "flag.circle.fill", color: .mint, items: party)
            }
            if let lost = rewards.lostPartyAchievements, !lost.isEmpty {
                rewardSection(title: "Lost Achievements", icon: "flag.slash.circle", color: .red, items: lost)
            }
            if let stickers = rewards.campaignSticker, !stickers.isEmpty {
                rewardSection(title: "Campaign Stickers", icon: "seal.fill", color: .purple, items: stickers)
            }

            // Items
            if let items = rewards.items, !items.isEmpty {
                rewardSection(title: "Items", icon: "bag.fill", color: .cyan, items: items)
            }
            if let designs = rewards.itemDesigns, !designs.isEmpty {
                rewardSection(title: "Item Designs", icon: "pencil.and.ruler.fill", color: .cyan, items: designs)
            }
            if let blueprints = rewards.itemBlueprints, !blueprints.isEmpty {
                rewardSection(title: "Item Blueprints", icon: "doc.text.fill", color: .cyan, items: blueprints)
            }
            if rewards.randomItem != nil {
                rewardRow(icon: "questionmark.circle.fill", text: "Random Item", color: .cyan)
            }

            // Character unlock
            if let unlock = rewards.unlockCharacter {
                rewardRow(icon: "person.badge.plus", text: "Unlock: \(unlock.replacingOccurrences(of: "-", with: " ").capitalized)", color: GlavenTheme.accentText)
            }

            // Envelopes
            if let envelopes = rewards.envelopes, !envelopes.isEmpty {
                rewardSection(title: "Envelopes", icon: "envelope.fill", color: .indigo, items: envelopes)
            }

            // Resources (FH)
            if let resources = rewards.resources, !resources.isEmpty {
                ForEach(Array(resources.enumerated()), id: \.offset) { _, res in
                    rewardRow(icon: "cube.fill", text: "\(res.value.stringValue) \(res.type.capitalized)", color: .brown)
                }
            }

            // Pet
            if let pet = rewards.pet {
                rewardRow(icon: "pawprint.fill", text: "Pet: \(pet.replacingOccurrences(of: "-", with: " ").capitalized)", color: .pink)
            }

            // Events
            if let events = rewards.events, !events.isEmpty {
                rewardSection(title: "Add Events", icon: "calendar.badge.plus", color: .teal, items: events)
            }
            if let removeEvents = rewards.removeEvents, !removeEvents.isEmpty {
                rewardSection(title: "Remove Events", icon: "calendar.badge.minus", color: .red, items: removeEvents)
            }

            // Custom
            if let custom = rewards.custom, !custom.isEmpty {
                rewardRow(icon: "text.bubble", text: custom, color: GlavenTheme.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Components

    @ViewBuilder
    private func rewardRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }

    @ViewBuilder
    private func rewardSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(GlavenTheme.primaryText)
            }
            ForEach(items, id: \.self) { item in
                Text("  \(item.replacingOccurrences(of: "-", with: " ").capitalized)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
                    .padding(.leading, 28)
            }
        }
    }
}

// Helper for signed display
private extension IntOrString {
    var isPositive: Bool { intValue > 0 }
    static func > (lhs: IntOrString, rhs: Int) -> Bool { lhs.intValue > rhs }
}
