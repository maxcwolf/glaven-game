import SwiftUI

/// A party member in town: who they are, their level and progress to the next, their gold, and
/// what they can do between scenarios — level up, take perks, open their sheet, go shopping.
struct TownPartyRow: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    var onSheet: () -> Void
    var onShop: () -> Void
    var onLevelUp: () -> Void
    var onChooseCard: () -> Void
    var onHand: () -> Void
    var onChooseQuest: () -> Void
    var onRetire: () -> Void

    private var nextThreshold: Int? {
        character.level < 9 ? GameCharacter.xpThresholds[character.level] : nil
    }

    var body: some View {
        let manager = gameManager.characterManager
        let perks = manager.perksAvailable(for: character)
        let cardChoices = manager.pendingCardChoices(for: character)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                portrait
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(hex: character.color) ?? .gray, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameText.characterName(character, labels: gameManager.editionStore))
                        .font(.headline)
                        .foregroundStyle(BoardTheme.text)
                    Text(levelLine)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                Spacer()
                Label("\(character.loot)", systemImage: "dollarsign.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(BoardTheme.victory)
                    .accessibilityLabel("\(character.loot) gold")
            }
            if let next = nextThreshold {
                ProgressView(value: Double(min(character.experience, next)), total: Double(next))
                    .tint(BoardTheme.brass)
                    .accessibilityLabel("Experience \(character.experience) of \(next)")
            }
            questLine
            HStack(spacing: 8) {
                if manager.canLevelUp(character) {
                    Button("Level Up", systemImage: "arrow.up.circle.fill", action: onLevelUp)
                        .buttonStyle(.borderedProminent)
                        .tint(BoardTheme.gain)
                } else if cardChoices > 0 {
                    Button(cardChoices == 1 ? "Choose a Card" : "Choose \(cardChoices) Cards",
                           systemImage: "rectangle.stack.badge.plus", action: onChooseCard)
                        .buttonStyle(.borderedProminent)
                        .tint(BoardTheme.brass)
                }
                Button("Hand", systemImage: "rectangle.stack", action: onHand)
                    .buttonStyle(.bordered)
                    .tint(.gray)
                Button(perks > 0 ? "\(perks) Perk\(perks == 1 ? "" : "s")" : "Sheet",
                       systemImage: perks > 0 ? "star.circle.fill" : "person.text.rectangle", action: onSheet)
                    .buttonStyle(.bordered)
                    .tint(perks > 0 ? BoardTheme.brass : .gray)
                Button("Shop", systemImage: "bag.fill", action: onShop)
                    .buttonStyle(.bordered)
                    .tint(.gray)
            }
            .font(.subheadline)
            .controlSize(.small)
        }
        .padding(12)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
    }

    /// The personal quest: its name and progress, or a button to choose one / to retire.
    @ViewBuilder
    private var questLine: some View {
        let manager = gameManager.characterManager
        HStack(spacing: 8) {
            Image(systemName: "scroll").foregroundStyle(BoardTheme.brass)
            if let id = character.personalQuest, let quest = manager.personalQuest(id, edition: character.edition) {
                let met = quest.requirements.enumerated().filter { index, req in
                    (index < character.personalQuestProgress.count ? character.personalQuestProgress[index] : 0) >= req.target
                }.count
                Text("\(quest.name) · \(met) of \(quest.requirements.count) done")
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if manager.questComplete(character) {
                    Button("Retire", systemImage: "figure.walk.departure", action: onRetire)
                        .buttonStyle(.borderedProminent)
                        .tint(BoardTheme.brass)
                        .controlSize(.small)
                }
            } else {
                Text("No personal quest")
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.secondaryText)
                Spacer(minLength: 4)
                Button("Choose Quest", systemImage: "scroll.fill", action: onChooseQuest)
                    .buttonStyle(.borderedProminent)
                    .tint(BoardTheme.brass)
                    .controlSize(.small)
            }
        }
    }

    private var levelLine: String {
        guard let next = nextThreshold else { return "Level \(character.level) · \(character.experience) XP" }
        return "Level \(character.level) · \(character.experience) / \(next) XP"
    }

    @ViewBuilder
    private var portrait: some View {
        if let image = ImageLoader.characterThumbnail(edition: character.edition, name: character.name) {
            #if os(macOS)
            Image(nsImage: image).resizable().scaledToFill()
            #else
            Image(uiImage: image).resizable().scaledToFill()
            #endif
        } else {
            Circle().fill(BoardTheme.raised)
        }
    }
}
