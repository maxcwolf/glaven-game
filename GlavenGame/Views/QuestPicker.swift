import SwiftUI

/// A recruit keeps one of the two personal quests dealt to them; completing it means retiring.
struct QuestPicker: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    let onDone: () -> Void

    private var manager: CharacterManager { gameManager.characterManager }

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Personal Quest")
                    .font(BoardTheme.display(30))
                    .foregroundStyle(BoardTheme.text)
                Text("\(GameText.characterName(character, labels: gameManager.editionStore)), keep one. Complete it and you retire, often unlocking a new class.")
                    .font(.body)
                    .foregroundStyle(BoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .top, spacing: 14) {
                    ForEach(character.questChoices, id: \.self) { id in
                        if let quest = manager.personalQuest(id, edition: character.edition) {
                            questCard(quest) {
                                manager.chooseQuest(id, for: character)
                                onDone()
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 700)
            .fixedSize(horizontal: false, vertical: true)
            .boardPanel()
            .padding(24)
        }
    }

    private func questCard(_ quest: PersonalQuest, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 10) {
                Text(quest.name)
                    .font(BoardTheme.display(24))
                    .foregroundStyle(BoardTheme.text)
                ForEach(Array(quest.requirements.enumerated()), id: \.offset) { _, requirement in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(requirement.target)×")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(BoardTheme.brass)
                        Text(requirement.text)
                            .font(.subheadline)
                            .foregroundStyle(BoardTheme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let unlocks = quest.unlocks {
                    Label("Unlocks the \(unlocks)", systemImage: "lock.open")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Keep this personal quest")
    }
}
