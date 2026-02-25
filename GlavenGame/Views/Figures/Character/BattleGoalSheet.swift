import SwiftUI

struct BattleGoalSheet: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if character.battleGoalCardIds.isEmpty {
                    drawSection
                } else {
                    goalsSection
                }
                Spacer()
            }
            .padding()
            .background(GlavenTheme.background)
            .navigationTitle("Battle Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var drawSection: some View {
        VStack(spacing: 12) {
            Text("Draw two battle goals to choose from.")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)

            Button {
                drawBattleGoals()
            } label: {
                Label("Draw Battle Goals", systemImage: "rectangle.stack")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private var goalsSection: some View {
        VStack(spacing: 12) {
            Text("Select your battle goal:")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)

            ForEach(Array(character.battleGoalCardIds.enumerated()), id: \.offset) { index, cardId in
                if let goal = gameManager.editionStore.battleGoal(cardId: cardId) {
                    BattleGoalRow(
                        goal: goal,
                        isSelected: character.selectedBattleGoal == index
                    ) {
                        gameManager.pushUndoState()
                        character.selectedBattleGoal = character.selectedBattleGoal == index ? nil : index
                    }
                }
            }

            Divider().background(GlavenTheme.primaryText.opacity(0.2))

            Button(role: .destructive) {
                gameManager.pushUndoState()
                character.battleGoalCardIds = []
                character.selectedBattleGoal = nil
            } label: {
                Label("Discard & Redraw", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }

    private func drawBattleGoals() {
        gameManager.pushUndoState()
        guard let edition = gameManager.game.edition else { return }
        let allGoals = gameManager.editionStore.battleGoals(for: edition)
        guard allGoals.count >= 2 else { return }

        // Exclude goals already assigned to other characters
        let usedCardIds = Set(
            gameManager.game.characters
                .filter { $0.id != character.id }
                .flatMap { $0.battleGoalCardIds }
        )
        let available = allGoals.filter { !usedCardIds.contains($0.cardId) }
        guard available.count >= 2 else { return }

        let shuffled = available.shuffled()
        character.battleGoalCardIds = [shuffled[0].cardId, shuffled[1].cardId]
        character.selectedBattleGoal = nil
    }
}

private struct BattleGoalRow: View {
    let goal: BattleGoalData
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : GlavenTheme.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    HStack(spacing: 4) {
                        ForEach(0..<goal.checks, id: \.self) { _ in
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(GlavenTheme.positive)
                        }
                        Text(goal.checks == 1 ? "check" : "checks")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
                Spacer()
                Text("#\(goal.cardId)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .padding(12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : GlavenTheme.primaryText.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : GlavenTheme.primaryText.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
