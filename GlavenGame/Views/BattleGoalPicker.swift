import SwiftUI

/// Before setting out: each character in turn keeps one of the two battle goals dealt to them.
/// Back returns to the previous character, or (from the first) to town; the goals dealt stand.
struct BattleGoalPicker: View {
    @Environment(GameManager.self) private var gameManager
    var onBack: () -> Void = {}
    let onDone: () -> Void
    @State private var index = 0

    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    var body: some View {
        if index < party.count {
            let character = party[index]
            let name = GameText.characterName(character, labels: gameManager.editionStore)
            TownDialog(title: "Battle Goal", subtitle: Self.subtitle(name: name, index: index, of: party.count),
                       portrait: (ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                                  Color(hex: character.color) ?? BoardTheme.border),
                       size: CGSize(width: 760, height: 520), doneTitle: "Back", doneProminent: false,
                       onCancel: {}, onDone: back) {
                EmptyView()
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Meet it in a scenario you win for its checkmarks; every three earn a perk.")
                        .font(BoardTheme.font(size: 13))
                        .foregroundStyle(BoardTheme.secondaryText)
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(character.battleGoalCardIds.enumerated()), id: \.offset) { pick, cardId in
                            if let goal = gameManager.scenarioManager.battleGoal(cardId) {
                                goalCard(goal) {
                                    gameManager.scenarioManager.chooseBattleGoal(pick, for: character)
                                    withAnimation(.snappy) { index += 1 }
                                    if index >= party.count { onDone() }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .id(character.id)
            .transition(.opacity)
        }
    }

    /// "Brute, 1 of 2 · keep one, secretly".
    static func subtitle(name: String, index: Int, of count: Int) -> String {
        "\(name), \(index + 1) of \(count) \u{00B7} keep one, secretly"
    }

    private func back() {
        if index > 0 { withAnimation(.snappy) { index -= 1 } } else { onBack() }
    }

    private func goalCard(_ goal: BattleGoal, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(goal.name)
                    .font(BoardTheme.display(21))
                    .foregroundStyle(BoardTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<goal.checks, id: \.self) { _ in TownCheckBox(ticked: true) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(goal.checks) checkmark\(goal.checks == 1 ? "" : "s")")
            }
            Text(goal.text)
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Keep This Goal", action: choose)
                .buttonStyle(.boardPrimaryCompact)
                .accessibilityLabel("Keep \(goal.name)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }
}
