import SwiftUI

struct ScenarioHeaderView: View {
    @Environment(GameManager.self) private var gameManager
    @State private var showRoomSheet = false
    @State private var showSectionSheet = false
    @State private var showMapSheet = false
    @State private var showFinishAlert = false
    @State private var showCancelAlert = false
    private let mapStore = ScenarioMapStore.shared

    private var scenario: Scenario? { gameManager.game.scenario }

    var body: some View {
        if let scenario = scenario {
            HStack(spacing: 12) {
                // Scenario name
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(scenario.data.index) \(scenario.data.name)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text("Rooms: \(scenario.revealedRooms.count)/\(scenario.totalRoomCount)")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                // Map button (GH only)
                if gameManager.game.edition == "gh",
                   mapStore.hasMap(for: scenario.data.index) {
                    Button {
                        showMapSheet = true
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Open Room button
                if !scenario.adjacentUnrevealedRooms.isEmpty {
                    Button {
                        showRoomSheet = true
                    } label: {
                        Label("Room", systemImage: "door.left.hand.open")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Add Section button
                if let edition = gameManager.game.edition,
                   !gameManager.scenarioManager.availableSections(for: edition).isEmpty {
                    Button {
                        showSectionSheet = true
                    } label: {
                        Label("Section", systemImage: "doc.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Finish button
                Menu {
                    Button {
                        showFinishAlert = true
                    } label: {
                        Label("Success", systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive) {
                        gameManager.scenarioManager.finishScenario(success: false)
                    } label: {
                        Label("Failure", systemImage: "xmark.circle")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showCancelAlert = true
                    } label: {
                        Label("Cancel Scenario", systemImage: "xmark.octagon")
                    }
                } label: {
                    Image(systemName: "flag.checkered")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .sheet(isPresented: $showRoomSheet) {
                RoomRevealSheet()
            }
            .sheet(isPresented: $showSectionSheet) {
                SectionSelectionSheet()
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showMapSheet) {
                ScenarioMapSheetWrapper()
            }
            #else
            .sheet(isPresented: $showMapSheet) {
                ScenarioMapSheetWrapper()
            }
            #endif
            .alert("Complete Scenario?", isPresented: $showFinishAlert) {
                Button("Apply Rewards") {
                    gameManager.scenarioManager.finishScenario(success: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let rewards = scenario.data.rewards {
                    Text(rewardsSummary(rewards))
                }
            }
            .alert("Cancel Scenario?", isPresented: $showCancelAlert) {
                Button("Cancel Scenario", role: .destructive) {
                    gameManager.scenarioManager.cancelScenario()
                }
                Button("Keep Playing", role: .cancel) {}
            } message: {
                Text("All scenario progress will be lost.")
            }
        }
    }

    private func rewardsSummary(_ rewards: ScenarioRewards) -> String {
        var parts: [String] = []
        if let gold = rewards.gold { parts.append("\(gold.stringValue) Gold") }
        if let xp = rewards.experience { parts.append("\(xp.stringValue) XP") }
        if let rep = rewards.reputation { parts.append("\(rep.stringValue) Reputation") }
        if let pros = rewards.prosperity { parts.append("\(pros.stringValue) Prosperity") }
        if let globals = rewards.globalAchievements { parts.append(contentsOf: globals.map { "Achievement: \($0)" }) }
        if let party = rewards.partyAchievements { parts.append(contentsOf: party.map { "Party: \($0)" }) }
        return parts.isEmpty ? "No rewards" : parts.joined(separator: "\n")
    }
}

// MARK: - Section Selection Sheet

private struct SectionSelectionSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection: ScenarioData?
    @State private var showConclusionConfirm = false

    private var sections: [ScenarioData] {
        guard let edition = gameManager.game.edition else { return [] }
        return gameManager.scenarioManager.availableSections(for: edition)
    }

    private func sectionDisplayName(_ section: ScenarioData) -> String {
        section.name
            .replacingOccurrences(of: "%scenario.conclusion%", with: "Conclusion")
            .replacingOccurrences(of: "%data.scenario%", with: gameManager.game.scenario?.data.name ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sections) { section in
                        sectionRow(section)
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Add Section")
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 350)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Apply Conclusion?", isPresented: $showConclusionConfirm) {
                Button("Apply Rewards") {
                    if let section = selectedSection {
                        gameManager.scenarioManager.addSection(section.index)
                        gameManager.scenarioManager.finishScenario(success: true)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) { selectedSection = nil }
            } message: {
                if let section = selectedSection {
                    Text("Section \(section.index) is a scenario conclusion. This will end the scenario and apply rewards.")
                }
            }
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: ScenarioData) -> some View {
        Button {
            if section.isConclusion {
                selectedSection = section
                showConclusionConfirm = true
            } else {
                gameManager.scenarioManager.addSection(section.index)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                // Section index badge
                Text(section.index)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(section.isConclusion ? GlavenTheme.positive : GlavenTheme.accentText)
                    .frame(minWidth: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(sectionDisplayName(section))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        // Conclusion badge
                        if section.isConclusion {
                            Label("Conclusion", systemImage: "flag.checkered")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(GlavenTheme.positive)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(GlavenTheme.positive.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        // Monster count
                        if let monsters = section.monsters, !monsters.isEmpty {
                            Label("\(monsters.count)", systemImage: "pawprint.fill")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }

                        // Room count
                        if let rooms = section.rooms, !rooms.isEmpty {
                            Label("\(rooms.count)", systemImage: "door.left.hand.open")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }

                        // Rewards indicator
                        if section.rewards != nil {
                            Image(systemName: "gift.fill")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                    }
                }

                Spacer()

                Image(systemName: section.isConclusion ? "flag.checkered" : "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(section.isConclusion ? GlavenTheme.positive : GlavenTheme.accentText)
            }
            .padding(12)
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
