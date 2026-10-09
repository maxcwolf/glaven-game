import SwiftUI

/// A party member in town: who they are, their level and progress to the next, their gold, and
/// what they can do between scenarios — level up, take perks, open their sheet, go shopping.
struct TownPartyRow: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    var onSheet: () -> Void
    var onShop: () -> Void
    var onItems: () -> Void = {}
    var onEnhance: () -> Void = {}
    var onLevelUp: () -> Void
    var onChooseCard: () -> Void
    var onHand: () -> Void
    var onChooseQuest: () -> Void
    var onRetire: () -> Void

    private var nextThreshold: Int? {
        character.level < 9 ? GameCharacter.xpThresholds[character.level] : nil
    }

    /// Takes them out of the party (before the first scenario), or asks to dismiss them (in town).
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let manager = gameManager.characterManager
        let perks = manager.perksAvailable(for: character)
        let cardChoices = manager.pendingCardChoices(for: character)
        let classColor = Color(hex: character.color) ?? BoardTheme.border
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                portrait
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(classColor, lineWidth: 2.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(GameText.characterName(character, labels: gameManager.editionStore))
                            .font(BoardTheme.font(size: 17, weight: .semibold))
                            .foregroundStyle(BoardTheme.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Label("\(character.loot)", systemImage: "dollarsign.circle.fill")
                            .font(BoardTheme.font(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(BoardTheme.victory)
                            .accessibilityLabel("\(character.loot) gold")
                    }
                    Text(levelLine)
                        .font(BoardTheme.font(size: 13).monospacedDigit())
                        .foregroundStyle(BoardTheme.secondaryText)
                    if let next = nextThreshold {
                        XPBar(progress: Double(min(character.experience, next)) / Double(max(1, next)))
                            .accessibilityLabel("Experience \(character.experience) of \(next)")
                    }
                }
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(BoardTheme.font(size: 12, weight: .bold))
                            .foregroundStyle(BoardTheme.secondaryText)
                            .frame(width: 28, height: 28)
                            .background(BoardTheme.sheet.opacity(0.6), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(GameText.characterName(character, labels: gameManager.editionStore)) from the party")
                }
            }
            questLine
            FlowLayout(spacing: 6) {
                if manager.canLevelUp(character) {
                    Button("Level Up", systemImage: "arrow.up.circle.fill", action: onLevelUp)
                        .buttonStyle(.boardPrimaryCompact)
                } else if cardChoices > 0 {
                    Button(cardChoices == 1 ? "Choose a Card" : "Choose \(cardChoices) Cards",
                           systemImage: "rectangle.stack.badge.plus", action: onChooseCard)
                        .buttonStyle(.boardPrimaryCompact)
                }
                Button("Hand", systemImage: "rectangle.stack", action: onHand)
                    .buttonStyle(.boardQuietCompact)
                if perks > 0 {
                    Button("\(perks) Perk\(perks == 1 ? "" : "s")", systemImage: "star.circle.fill", action: onSheet)
                        .buttonStyle(.boardPrimaryCompact)
                } else {
                    Button("Sheet", systemImage: "person.text.rectangle", action: onSheet)
                        .buttonStyle(.boardQuietCompact)
                }
                Button("Shop", systemImage: "bag", action: onShop)
                    .buttonStyle(.boardQuietCompact)
                if !character.items.isEmpty {
                    // Brought / owned, so an item left at home is never a surprise.
                    Button("Items \(character.carriedItems.count)/\(character.items.count)", systemImage: "shield.lefthalf.filled",
                           action: onItems)
                        .buttonStyle(.boardQuietCompact)
                        .accessibilityLabel("Items, bringing \(character.carriedItems.count) of \(character.items.count)")
                }
                if gameManager.enhancementsManager.enhancerOpen(edition: character.edition) {
                    Button("Enhance", systemImage: "sparkles", action: onEnhance)
                        .buttonStyle(.boardQuietCompact)
                }
            }
        }
        .padding(12)
        .background(BoardTheme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
    }

    /// The personal quest: its name and progress, or a button to choose one / to retire.
    @ViewBuilder
    private var questLine: some View {
        let manager = gameManager.characterManager
        HStack(spacing: 8) {
            Image(systemName: "scroll").foregroundStyle(BoardTheme.brass).accessibilityHidden(true)
            if let id = character.personalQuest, let quest = manager.personalQuest(id, edition: character.edition) {
                let met = quest.requirements.enumerated().filter { index, req in
                    (index < character.personalQuestProgress.count ? character.personalQuestProgress[index] : 0) >= req.target
                }.count
                Text("\(quest.name) · \(met) of \(quest.requirements.count) done")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if manager.questComplete(character) {
                    Button("Retire", systemImage: "figure.walk.departure", action: onRetire)
                        .buttonStyle(.boardPrimaryCompact)
                }
            } else {
                Text("No personal quest")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                Spacer(minLength: 4)
                Button("Choose Quest", systemImage: "scroll.fill", action: onChooseQuest)
                    .buttonStyle(.boardPrimaryCompact)
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

/// Progress toward the next level, in brass.
struct XPBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(BoardTheme.sheet)
                Capsule().fill(BoardTheme.brass).frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 5)
    }
}
