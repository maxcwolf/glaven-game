import SwiftUI

struct ScenarioRulesView: View {
    @Environment(GameManager.self) private var gameManager

    private var scenario: Scenario? { gameManager.game.scenario }

    private var visibleRules: [(index: Int, rule: ScenarioRule)] {
        guard let scenario = scenario, let rules = scenario.data.rules else { return [] }
        return rules.enumerated().compactMap { index, rule in
            // Show rules that have notes
            guard rule.note != nil || rule.noteTop != nil else { return nil }
            return (index, rule)
        }
    }

    var body: some View {
        if !visibleRules.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleRules, id: \.index) { item in
                    ScenarioRuleRow(rule: item.rule, index: item.index, scenario: scenario!)
                }
            }
        }
    }
}

private struct ScenarioRuleRow: View {
    let rule: ScenarioRule
    let index: Int
    let scenario: Scenario

    private var isApplied: Bool {
        scenario.appliedRules.contains(scenario.ruleKey(index: index))
    }

    private var isDisabled: Bool {
        scenario.disabledRules.contains(index)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            if let noteTop = rule.noteTop {
                Text(noteTop)
                    .font(.caption2)
                    .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
            } else if let note = rule.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(isDisabled ? Color.secondary : Color.primary)
            }

            Spacer()

            if let round = rule.round {
                Text("R: \(round)")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .opacity(isDisabled ? 0.5 : 1.0)
        .strikethrough(isDisabled)
    }

    private var statusColor: Color {
        if isDisabled { return Color.gray }
        if isApplied { return Color.green }
        return Color.orange
    }
}
