import SwiftUI

/// The scenario's intro: its name, the goal, how it can be lost and its special rules. Shown as
/// a scenario begins and again from the Goal chip in the HUD.
struct ScenarioBriefCard: View {
    let brief: ScenarioBrief
    /// "Begin" as the scenario starts, "Close" when reopened.
    let buttonTitle: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 18) {
                Text(brief.title)
                    .font(BoardTheme.display(40))
                    .foregroundStyle(BoardTheme.text)
                    .accessibilityAddTraits(.isHeader)

                section("Goal", systemImage: "scope", tint: BoardTheme.victory) {
                    Text(brief.goal)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BoardTheme.text)
                }

                section("You lose if", systemImage: "xmark.shield", tint: BoardTheme.defeat) {
                    bullets(brief.defeat)
                }

                if !brief.rules.isEmpty {
                    section("Special rules", systemImage: "scroll", tint: BoardTheme.brass) {
                        // Most scenarios have a rule or two; a long list (GH 42) scrolls.
                        if brief.rules.joined().count > 520 {
                            ScrollView { bullets(brief.rules) }
                                .frame(height: 280)
                        } else {
                            bullets(brief.rules)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text(buttonTitle)
                            .font(.headline)
                            .frame(minWidth: 140, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BoardTheme.brass)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(maxWidth: 620)
            .fixedSize(horizontal: false, vertical: true)   // as tall as its contents, not the screen
            .boardPanel()
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenario \(brief.title)")
    }

    private func section<Content: View>(_ title: String, systemImage: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            content()
        }
    }

    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\u{2022}").foregroundStyle(BoardTheme.secondaryText)
                    Text(line)
                        .font(.body)
                        .foregroundStyle(BoardTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
