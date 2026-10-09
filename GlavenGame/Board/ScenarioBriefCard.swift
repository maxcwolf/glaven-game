import SwiftUI

/// The scenario's intro: its name, the goal, how it can be lost and its special rules. Shown as
/// a scenario begins and again from the Goal chip in the HUD.
struct ScenarioBriefCard: View {
    let brief: ScenarioBrief
    /// "Begin" as the scenario starts, "Close" when reopened.
    let buttonTitle: String
    let onDismiss: () -> Void
    /// Each character's battle goal (name, goal), shown as a reminder.
    var battleGoals: [(character: String, goal: BattleGoal)] = []
    /// The table rules this campaign plays by, as a reminder.
    var tableRules: [String] = []

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)   // the card's own button closes it
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

                if !brief.monsters.isEmpty {
                    section("Monsters", systemImage: "pawprint", tint: BoardTheme.secondaryText) {
                        monsterRow
                    }
                }

                if brief.map != nil || !brief.rewards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if let map = brief.map { detailRow("Map", map) }
                        if !brief.rewards.isEmpty { detailRow("Rewards", brief.rewards.joined(separator: " · ")) }
                    }
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

                if !battleGoals.isEmpty {
                    section("Battle goals", systemImage: "checkmark.square", tint: BoardTheme.brass) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(battleGoals, id: \.character) { entry in
                                (Text("\(entry.character) · \(entry.goal.name): ").bold() + Text(entry.goal.text))
                                    .font(.subheadline)
                                    .foregroundStyle(BoardTheme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !tableRules.isEmpty {
                    section("Table rules", systemImage: "list.bullet.rectangle", tint: BoardTheme.secondaryText) {
                        bullets(tableRules)
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

    /// The scenario's monsters as portraits, named.
    private var monsterRow: some View {
        // Wraps when a scenario has many (Infernal Throne has seven).
        FlowLayout(spacing: 10) {
            ForEach(brief.monsters, id: \.self) { monster in
                VStack(spacing: 4) {
                    Group {
                        if let image = ImageLoader.monsterThumbnail(edition: brief.edition, name: monster) {
                            #if os(macOS)
                            Image(nsImage: image).resizable().scaledToFill()
                            #else
                            Image(uiImage: image).resizable().scaledToFill()
                            #endif
                        } else {
                            Circle().fill(BoardTheme.raised)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BoardTheme.border, lineWidth: 1))
                    Text(GameText.monsterName(monster, edition: brief.edition))
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(BoardTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(width: 76)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "MAP   3 rooms · start in L1a"
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(BoardTheme.secondaryText)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(BoardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
