import SwiftUI

struct ScenarioSelectionSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    @State private var showSoloScenarios = false

    private var scenarios: [ScenarioData] {
        guard let edition = gameManager.game.edition else { return [] }
        return gameManager.scenarioManager.availableScenarios(for: edition)
            .filter { $0.solo == nil }
    }

    private var soloScenarios: [ScenarioData] {
        guard let edition = gameManager.game.edition else { return [] }
        let characters = gameManager.game.characters
        return gameManager.scenarioManager.availableScenarios(for: edition)
            .filter { scenario in
                guard scenario.solo != nil else { return false }
                // Only show solo scenarios for characters in the party
                return characters.contains { $0.name == scenario.solo && $0.edition == scenario.edition }
            }
    }

    private var filteredScenarios: [ScenarioData] {
        let source = showSoloScenarios ? soloScenarios : scenarios
        if searchText.isEmpty { return source }
        let query = searchText.lowercased()
        return source.filter {
            $0.name.lowercased().contains(query) || $0.index.lowercased().contains(query)
                || ($0.solo?.lowercased().contains(query) ?? false)
        }
    }

    /// Scenarios linked/unlocked from recently completed ones
    private var linkedScenarios: [ScenarioData] {
        guard let edition = gameManager.game.edition else { return [] }
        let allScenarios = gameManager.editionStore.scenarios(for: edition)
        let availableIDs = Set(scenarios.map(\.index))

        var linked: [ScenarioData] = []
        for completedID in gameManager.game.completedScenarios {
            let parts = completedID.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == edition else { continue }
            let completedIndex = String(parts[1])
            if let completedScenario = allScenarios.first(where: { $0.index == completedIndex }) {
                let unlockIndices = (completedScenario.unlocks ?? []) + (completedScenario.links ?? [])
                for idx in unlockIndices {
                    if availableIDs.contains(idx),
                       let scenario = scenarios.first(where: { $0.index == idx }),
                       !linked.contains(where: { $0.index == scenario.index }) {
                        linked.append(scenario)
                    }
                }
            }
        }
        return linked.sorted { (Int($0.index) ?? 999) < (Int($1.index) ?? 999) }
    }

    private var groupedScenarios: [(String, [ScenarioData])] {
        let grouped = Dictionary(grouping: filteredScenarios) { $0.flowChartGroup ?? "Other" }
        return grouped.sorted { a, b in
            if a.key == "Other" { return false }
            if b.key == "Other" { return true }
            return a.key < b.key
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Linked / suggested scenarios
                if searchText.isEmpty, !linkedScenarios.isEmpty {
                    Section(header: Label("Suggested Next", systemImage: "arrow.right.circle")) {
                        ForEach(linkedScenarios) { scenario in
                            Button {
                                gameManager.startScenarioOnBoard(scenario)
                                dismiss()
                            } label: {
                                ScenarioRowView(scenario: scenario, highlighted: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(groupedScenarios, id: \.0) { group, scenarios in
                    Section(header: Text(formatGroupName(group))) {
                        ForEach(scenarios) { scenario in
                            Button {
                                gameManager.startScenarioOnBoard(scenario)
                                dismiss()
                            } label: {
                                ScenarioRowView(scenario: scenario)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search scenarios")
            .navigationTitle(showSoloScenarios ? "Solo Scenarios" : "Select Scenario")
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSoloScenarios.toggle()
                    } label: {
                        Label(showSoloScenarios ? "All" : "Solo",
                              systemImage: showSoloScenarios ? "person.3" : "person")
                    }
                }
            }
        }
    }

    private func formatGroupName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private struct ScenarioRowView: View {
    let scenario: ScenarioData
    var highlighted: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(scenario.index)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(highlighted ? GlavenTheme.accentText : GlavenTheme.primaryText)
                .frame(width: 50, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if let monsters = scenario.monsters {
                        Label("\(monsters.count)", systemImage: "figure.stand")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    if let rooms = scenario.rooms {
                        Label("\(rooms.count)", systemImage: "door.left.hand.open")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    if scenario.isConclusion {
                        Text("Conclusion")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if let solo = scenario.solo {
                        Text(solo.replacingOccurrences(of: "-", with: " ").capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
