import SwiftUI

/// The Sanctuary of the Great Oak: each character may donate 10 gold once per visit for two
/// blessings in their next scenario; every 100 gold the party gives raises prosperity.
struct SanctuarySheet: View {
    @Environment(GameManager.self) private var gameManager
    let onDone: () -> Void

    private var manager: CharacterManager { gameManager.characterManager }
    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    var body: some View {
        let given = gameManager.game.events.sanctuaryGold
        TownDialog(title: "Sanctuary of the Great Oak",
                   subtitle: "\(CharacterManager.donation) gold each for two blessings next scenario",
                   size: CGSize(width: 680, height: 520), onDone: onDone) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(party, id: \.id) { row($0) }
                    HStack(spacing: 8) {
                        TownSmallCaps(text: "Given so far")
                        Text(Self.progress(given))
                            .font(BoardTheme.font(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(BoardTheme.text)
                    }
                    .padding(.top, 4)
                    XPBar(progress: Double(given % 100) / 100, track: BoardTheme.raised)
                    Text("Every 100 gold the party gives raises the city's prosperity by one.")
                        .font(BoardTheme.font(size: 13))
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                .padding(18)
            }
        }
    }

    /// "30 of 100 gold" toward the next prosperity (130 given: "30 of 100 gold, 100 given before").
    static func progress(_ given: Int) -> String {
        let before = given / 100 * 100
        return "\(given % 100) of 100 gold" + (before > 0 ? ", \(before) given before" : "")
    }

    private func row(_ character: GameCharacter) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = ImageLoader.characterThumbnail(edition: character.edition, name: character.name) {
                    #if os(macOS)
                    Image(nsImage: image).resizable().scaledToFill()
                    #else
                    Image(uiImage: image).resizable().scaledToFill()
                    #endif
                } else {
                    BoardTheme.raised
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .accessibilityHidden(true)
            Text(GameText.characterName(character, labels: gameManager.editionStore))
                .font(BoardTheme.font(size: 15, weight: .semibold))
                .foregroundStyle(BoardTheme.text)
            TownGold(amount: character.loot, size: 13)
            Spacer()
            if gameManager.game.events.donatedThisVisit.contains(character.id) {
                Label("Blessed", systemImage: "sun.max.fill")
                    .font(BoardTheme.font(size: 13, weight: .semibold))
                    .foregroundStyle(BoardTheme.brass)
            } else {
                Button("Donate \(CharacterManager.donation)") { manager.donate(character) }
                    .buttonStyle(.boardPrimaryCompact)
                    .disabled(!manager.canDonate(character))
            }
        }
        .padding(12)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
