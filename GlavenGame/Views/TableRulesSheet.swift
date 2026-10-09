import SwiftUI

/// Variants the group plays by instead of the rulebook, for this campaign. Every one starts off;
/// the scenario brief lists those that are on.
struct TableRulesSheet: View {
    @Environment(GameManager.self) private var gameManager
    var onDone: () -> Void = {}
    /// Off for snapshots: ImageRenderer doesn't draw scroll views.
    var scrolls = true

    var body: some View {
        TownDialog(title: "Table Rules", subtitle: "This campaign only", size: CGSize(width: 680, height: 500), onDone: onDone) {
            if scrolls { ScrollView { content } } else { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ways your group plays differently from the rulebook.")
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.secondaryText)
            TownSection {
                ForEach(Array(TableRules.all.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Rectangle().fill(BoardTheme.border.opacity(0.3)).frame(height: 1) }
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.title)
                                .font(BoardTheme.font(size: 15, weight: .semibold))
                                .foregroundStyle(BoardTheme.text)
                            Text(rule.rulebook)
                                .font(BoardTheme.font(size: 12))
                                .foregroundStyle(BoardTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        TownSwitch(label: rule.title, isOn: binding(rule))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(_ rule: TableRules.Rule) -> Binding<Bool> {
        Binding(get: { gameManager.game.tableRules[keyPath: rule.keyPath] },
                set: { gameManager.setTableRule(rule.keyPath, $0) })
    }

    /// "Rulebook", or the number of table rules on.
    static func summary(_ rules: TableRules) -> String {
        let on = rules.inPlay.count
        return on == 0 ? "Table rules: the rulebook" : "Table rules: \(on) change\(on == 1 ? "" : "s") from the rulebook"
    }
}
