import SwiftUI

/// Variants the group plays by instead of the rulebook, for this campaign. Every one starts off;
/// the scenario brief lists those that are on.
struct TableRulesSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    /// Off for snapshots: ImageRenderer draws neither scroll views nor navigation stacks.
    var scrolls = true

    var body: some View {
        if scrolls {
            NavigationStack {
                ScrollView { content }
                    .background(BoardTheme.sheet)
                    .navigationTitle("Table Rules")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        } else {
            content.background(BoardTheme.sheet)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ways your group plays differently from the rulebook. They apply to this campaign only.")
                .font(.subheadline)
                .foregroundStyle(BoardTheme.secondaryText)
            ForEach(TableRules.all) { rule in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.title)
                            .font(.headline)
                            .foregroundStyle(BoardTheme.text)
                        Text(rule.rulebook)
                            .font(.caption)
                            .foregroundStyle(BoardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle(rule.title, isOn: binding(rule))
                        .labelsHidden()
                        .tint(BoardTheme.brass)
                }
                .padding(12)
                .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            }
        }
        .padding(20)
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
