import SwiftUI

struct ScenarioChartSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroup: String? = nil

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var allScenarios: [ScenarioData] {
        gameManager.editionStore.scenarios(for: edition)
            .filter { $0.parent == nil && $0.group != "randomMonsterCard" && $0.group != "randomDungeonCard" }
            .sorted { (Int($0.index) ?? 999) < (Int($1.index) ?? 999) }
    }

    private var groups: [String] {
        let allGroups = Set(allScenarios.compactMap { $0.flowChartGroup ?? $0.group })
        return allGroups.sorted()
    }

    private var displayedScenarios: [ScenarioData] {
        if let group = selectedGroup {
            return allScenarios.filter { ($0.flowChartGroup ?? $0.group) == group }
        }
        return allScenarios
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupPicker
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedScenarios) { scenario in
                            scenarioNode(scenario)
                        }
                    }
                    .padding()
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Scenario Chart")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Group Picker

    @ViewBuilder
    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                groupChip("All", selected: selectedGroup == nil) {
                    selectedGroup = nil
                }
                ForEach(groups, id: \.self) { group in
                    groupChip(group.replacingOccurrences(of: "-", with: " ").capitalized,
                              selected: selectedGroup == group) {
                        selectedGroup = group
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(GlavenTheme.cardBackground)
    }

    @ViewBuilder
    private func groupChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(selected ? .bold : .medium)
                .foregroundStyle(selected ? .white : GlavenTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? GlavenTheme.accentText : GlavenTheme.primaryText.opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scenario Node

    @ViewBuilder
    private func scenarioNode(_ scenario: ScenarioData) -> some View {
        let status = scenarioStatus(scenario)

        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 10) {
                // Index badge
                Text("#\(scenario.index)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(statusColor(status))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.name)
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        statusBadge(status)

                        if scenario.isConclusion {
                            badge("Conclusion", color: .orange)
                        }
                        if scenario.solo != nil {
                            badge("Solo", color: .purple)
                        }
                        if let group = scenario.flowChartGroup ?? scenario.group {
                            badge(group.replacingOccurrences(of: "-", with: " ").capitalized,
                                  color: .secondary)
                        }
                    }
                }

                Spacer()
            }

            // Connections
            connectionsView(scenario)
        }
        .padding(12)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(statusColor(status).opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func connectionsView(_ scenario: ScenarioData) -> some View {
        let unlocks = scenario.unlocks ?? []
        let links = scenario.links ?? []
        let blocks = scenario.blocks ?? []

        if !unlocks.isEmpty || !links.isEmpty || !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if !unlocks.isEmpty {
                    connectionRow("Unlocks", indices: unlocks, color: .green)
                }
                if !links.isEmpty {
                    connectionRow("Links to", indices: links, color: .blue)
                }
                if !blocks.isEmpty {
                    connectionRow("Blocks", indices: blocks, color: .red)
                }
            }
        }
    }

    @ViewBuilder
    private func connectionRow(_ label: String, indices: [String], color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
            ForEach(indices, id: \.self) { idx in
                let targetStatus = scenarioStatusByIndex(idx)
                Text("#\(idx)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(statusColor(targetStatus))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(statusColor(targetStatus).opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Status

    private enum ScenarioStatus {
        case completed, available, locked, blocked, active
    }

    private func scenarioStatus(_ scenario: ScenarioData) -> ScenarioStatus {
        let key = "\(edition)-\(scenario.index)"
        if gameManager.game.scenario?.data.index == scenario.index
            && gameManager.game.scenario?.data.edition == scenario.edition {
            return .active
        }
        if gameManager.game.completedScenarios.contains(key) {
            return .completed
        }
        if gameManager.scenarioManager.isBlocked(scenario) {
            return .blocked
        }
        if gameManager.scenarioManager.isAvailable(scenario) {
            return .available
        }
        return .locked
    }

    private func scenarioStatusByIndex(_ index: String) -> ScenarioStatus {
        if let scenario = gameManager.editionStore.scenarioData(index: index, edition: edition) {
            return scenarioStatus(scenario)
        }
        return .locked
    }

    private func statusColor(_ status: ScenarioStatus) -> Color {
        switch status {
        case .completed: return .green
        case .available: return GlavenTheme.accentText
        case .locked: return .gray
        case .blocked: return .red
        case .active: return .yellow
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: ScenarioStatus) -> some View {
        badge(statusLabel(status), color: statusColor(status))
    }

    private func statusLabel(_ status: ScenarioStatus) -> String {
        switch status {
        case .completed: return "Completed"
        case .available: return "Available"
        case .locked: return "Locked"
        case .blocked: return "Blocked"
        case .active: return "Active"
        }
    }

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }
}
