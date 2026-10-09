import SwiftUI

/// Which discarded cards to take back into the hand (Minor Stamina Potion: up to two).
struct RecoveryPicker: View {
    @Environment(GameManager.self) private var gameManager
    let pending: BoardCoordinator.PendingRecovery
    let character: GameCharacter
    let coordinator: BoardCoordinator
    @State private var chosen: [Int] = []

    private var discards: [AbilityModel] {
        let deck = gameManager.characterManager.abilities(for: character)
        return character.discardedCards.compactMap { id in deck.first { $0.cardId == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pending.itemName)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
            Text("Recover up to \(pending.count) discarded cards (\(chosen.count) of \(pending.count) chosen).")
                .font(.body)
                .foregroundStyle(BoardTheme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(discards) { card in
                        let id = card.cardId ?? 0
                        AbilityCardTile(card: card, character: character, selected: chosen.contains(id), width: 120)
                            .onTapGesture {
                                if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) }
                                else if chosen.count < pending.count { chosen.append(id) }
                            }
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button(chosen.isEmpty ? "Recover None" : "Recover \(chosen.count)") {
                    coordinator.resolveRecovery(chosen)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.brass)
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(maxWidth: 720)
        .boardPanel()
        .padding()
    }
}
