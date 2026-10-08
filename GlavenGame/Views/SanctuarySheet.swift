import SwiftUI

/// The Sanctuary of the Great Oak: each character may donate 10 gold once per visit for two
/// blessings in their next scenario.
struct SanctuarySheet: View {
    @Environment(GameManager.self) private var gameManager
    let onDone: () -> Void

    private var manager: CharacterManager { gameManager.characterManager }
    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea().onTapGesture(perform: onDone)
                .accessibilityLabel("Close the sanctuary")
            VStack(alignment: .leading, spacing: 16) {
                Text("Sanctuary of the Great Oak")
                    .font(BoardTheme.display(30))
                    .foregroundStyle(BoardTheme.text)
                Text("Give \(CharacterManager.donation) gold for two blessings in your next scenario, once each visit. Every 100 gold the party gives raises the city's prosperity.")
                    .font(.body)
                    .foregroundStyle(BoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(party, id: \.id) { character in
                    HStack {
                        Text(GameText.characterName(character, labels: gameManager.editionStore))
                            .font(.headline)
                            .foregroundStyle(BoardTheme.text)
                        Text("\(character.loot) gold")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(BoardTheme.secondaryText)
                        Spacer()
                        if gameManager.game.events.donatedThisVisit.contains(character.id) {
                            Label("Blessed", systemImage: "sun.max.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BoardTheme.brass)
                        } else {
                            Button("Donate \(CharacterManager.donation)") { manager.donate(character) }
                                .buttonStyle(.borderedProminent)
                                .tint(BoardTheme.brass)
                                .disabled(!manager.canDonate(character))
                        }
                    }
                    .padding(12)
                    .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                }
                Text("Given so far: \(gameManager.game.events.sanctuaryGold) gold")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
                HStack {
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }
            .padding(28)
            .frame(maxWidth: 560)
            .fixedSize(horizontal: false, vertical: true)
            .boardPanel()
            .padding(24)
        }
    }
}
