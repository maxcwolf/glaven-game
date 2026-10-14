import SwiftUI

/// Which cards of the hand to discard before the scenario begins (Harrower Hive: three each).
struct StartDiscardPicker: View {
    @Environment(GameManager.self) private var gameManager
    let pending: BoardCoordinator.PendingStartDiscard
    let character: GameCharacter
    let coordinator: BoardCoordinator
    @State private var chosen: [Int] = []

    private var hand: [AbilityModel] {
        let deck = gameManager.characterManager.abilities(for: character)
        return character.handCards.compactMap { id in deck.first { $0.cardId == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.characterName(character.id))
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
            Text(pending.penalty.map { "\($0) Choose \(pending.count == 1 ? "the card" : "the \(pending.count) cards") you \(pending.lose ? "lose" : "discard") (\(chosen.count) of \(pending.count))." }
                 ?? "This scenario begins with \(pending.count) of your cards discarded. Choose them (\(chosen.count) of \(pending.count)); they come back when you rest.")
                .font(.body)
                .foregroundStyle(BoardTheme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(hand) { card in
                        let id = card.cardId ?? 0
                        AbilityCardTile(card: card, character: character, selected: chosen.contains(id), width: 120)
                            .onTapGesture {
                                if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) }
                                else if chosen.count < pending.count { chosen.append(id) }
                            }
                            .accessibilityAddTraits(chosen.contains(id) ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("\(pending.lose ? "Lose" : "Discard") \(pending.count)") {
                    coordinator.resolveStartDiscard(chosen)
                }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.brass)
                .controlSize(.large)
                .disabled(chosen.count != pending.count)
            }
        }
        .padding(20)
        .frame(maxWidth: 720)
        .boardPanel()
        .padding()
    }
}
