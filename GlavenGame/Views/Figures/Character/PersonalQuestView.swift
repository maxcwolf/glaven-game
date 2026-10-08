import SwiftUI

/// A character's personal quest: its name, what it asks, and how far along they are. The game
/// counts what it can see; requirements it can't (a map region, an enhancement) are counted by hand.
struct PersonalQuestView: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager

    private var manager: CharacterManager { gameManager.characterManager }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let id = character.personalQuest, let quest = manager.personalQuest(id, edition: character.edition) {
                    header(quest)
                    ForEach(Array(quest.requirements.enumerated()), id: \.offset) { index, requirement in
                        requirementRow(requirement, index: index)
                    }
                    if let unlocks = quest.unlocks {
                        Label("Retiring unlocks the \(unlocks).", systemImage: "lock.open")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                } else {
                    Label("No personal quest yet. Choose one in town.", systemImage: "scroll")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
            }
            .padding()
        }
    }

    private func header(_ quest: PersonalQuest) -> some View {
        HStack {
            Image(systemName: "scroll.fill").foregroundStyle(GlavenTheme.accentText)
            Text(quest.name)
                .font(GlavenFont.title(size: 24))
                .foregroundStyle(GlavenTheme.primaryText)
            Spacer()
            if manager.questComplete(character) {
                Label("Complete", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private func requirementRow(_ requirement: PersonalQuest.Requirement, index: Int) -> some View {
        let progress = index < character.personalQuestProgress.count ? character.personalQuestProgress[index] : 0
        let waiting = requirement.after.contains { earlier in
            (earlier < character.personalQuestProgress.count ? character.personalQuestProgress[earlier] : 0)
                < (manager.personalQuest(character.personalQuest ?? "", edition: character.edition)?.requirements[earlier].target ?? 0)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(requirement.text)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.primaryText)
                Spacer()
                Text("\(progress) / \(requirement.target)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(progress >= requirement.target ? .green : GlavenTheme.accentText)
            }
            HStack(spacing: 10) {
                if requirement.tracking == .manual && !waiting {
                    Button { manager.adjustQuest(index, by: -1, for: character) } label: {
                        Image(systemName: "minus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(progress <= 0)
                    .accessibilityLabel("One less")
                }
                ProgressView(value: Double(min(progress, requirement.target)), total: Double(max(1, requirement.target)))
                    .tint(GlavenTheme.accentText)
                if requirement.tracking == .manual && !waiting {
                    Button { manager.adjustQuest(index, by: 1, for: character) } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(progress >= requirement.target)
                    .accessibilityLabel("One more")
                }
            }
            .foregroundStyle(GlavenTheme.accentText)
            Text(waiting ? "After the one above." : (requirement.tracking == .manual ? "Counted by hand." : "Counted by the game."))
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
