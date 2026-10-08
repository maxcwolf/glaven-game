import SwiftUI

/// Before setting out: each character in turn keeps one of the two battle goals dealt to them.
struct BattleGoalPicker: View {
    @Environment(GameManager.self) private var gameManager
    let onDone: () -> Void
    @State private var index = 0

    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
            if index < party.count {
                let character = party[index]
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Battle Goal")
                            .font(BoardTheme.display(30))
                            .foregroundStyle(BoardTheme.text)
                        Spacer()
                        Text("\(index + 1) of \(party.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(BoardTheme.secondaryText)
                    }
                    Text("\(GameText.characterName(character, labels: gameManager.editionStore)), keep one. Meet it in a successful scenario for its checkmarks; every three checkmarks earn a perk.")
                        .font(.body)
                        .foregroundStyle(BoardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 14) {
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
                .padding(28)
                .frame(maxWidth: 640)
                .fixedSize(horizontal: false, vertical: true)
                .boardPanel()
                .padding(24)
                .id(character.id)
                .transition(.opacity)
            }
        }
    }

    private func goalCard(_ goal: BattleGoal, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(goal.name)
                        .font(BoardTheme.display(24))
                        .foregroundStyle(BoardTheme.text)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<goal.checks, id: \.self) { _ in
                            Image(systemName: "checkmark.square.fill")
                        }
                    }
                    .foregroundStyle(BoardTheme.brass)
                    .accessibilityLabel("\(goal.checks) checkmark\(goal.checks == 1 ? "" : "s")")
                }
                Text(goal.text)
                    .font(.body)
                    .foregroundStyle(BoardTheme.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Keep this battle goal")
    }
}
