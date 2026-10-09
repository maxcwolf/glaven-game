import SwiftUI

/// A recruit keeps one of the two personal quests dealt to them; completing it means retiring.
/// Choosing can wait (Later); a character just recruited can instead be taken back (Cancel).
struct QuestPicker: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    /// The character was just recruited: Cancel undoes the recruitment rather than waiting.
    var recruiting = false
    var onCancel: () -> Void = {}
    let onDone: () -> Void

    private var manager: CharacterManager { gameManager.characterManager }
    private var name: String { GameText.characterName(character, labels: gameManager.editionStore) }

    var body: some View {
        TownDialog(title: "Personal Quest", subtitle: "\(name) keeps one of two",
                   portrait: (ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                              Color(hex: character.color) ?? BoardTheme.border),
                   size: CGSize(width: 760, height: 520), doneTitle: recruiting ? "Cancel" : "Later",
                   doneProminent: false, onCancel: recruiting ? {} : nil, onDone: recruiting ? onCancel : onDone) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text(recruiting ? "Fulfil it to retire, often unlocking a new class. Cancel takes back the recruit."
                                : "Fulfil it to retire, often unlocking a new class.")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                HStack(alignment: .top, spacing: 12) {
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
            .padding(18)
        }
    }

    private func questCard(_ quest: PersonalQuest, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(quest.name)
                .font(BoardTheme.display(21))
                .foregroundStyle(BoardTheme.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(quest.requirements.enumerated()), id: \.offset) { _, requirement in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(requirement.target)")
                        .font(BoardTheme.font(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(BoardTheme.brass)
                    Text(requirement.text)
                        .font(BoardTheme.font(size: 13))
                        .foregroundStyle(BoardTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            if let reward = quest.reward {
                Label(reward, systemImage: quest.unlocks == nil ? "envelope" : "lock.open")
                    .font(BoardTheme.font(size: 12, weight: .semibold))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            Button("Keep This Quest", action: choose)
                .buttonStyle(.boardPrimaryCompact)
                .accessibilityLabel("Keep \(quest.name)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }
}
