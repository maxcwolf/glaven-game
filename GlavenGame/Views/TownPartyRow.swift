import SwiftUI

/// A party member in town: who they are, their level and progress to the next, their gold, and
/// what they can do between scenarios — level up, take perks, open their sheet, go shopping.
struct TownPartyRow: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    var onSheet: () -> Void
    var onShop: () -> Void
    var onLevelUp: () -> Void

    private var nextThreshold: Int? {
        character.level < 9 ? GameCharacter.xpThresholds[character.level] : nil
    }

    var body: some View {
        let manager = gameManager.characterManager
        let perks = manager.perksAvailable(for: character)
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
            HStack(spacing: 8) {
                if manager.canLevelUp(character) {
                    Button("Level Up", systemImage: "arrow.up.circle.fill", action: onLevelUp)
                        .buttonStyle(.borderedProminent)
                        .tint(BoardTheme.gain)
                }
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
