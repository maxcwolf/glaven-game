import SwiftUI

/// The card to play for an item: one card for a half now (Ring of Haste, Ring of Brutality,
/// Staff of Command), or two for another turn this round (Second Chance Ring), the first leading.
struct CardPlayPicker: View {
    @Environment(GameManager.self) private var gameManager
    let pending: BoardCoordinator.PendingCardPlay
    let character: GameCharacter
    let coordinator: BoardCoordinator
    @State private var chosen: [Int] = []

    private var cards: [AbilityModel] {
        let deck = gameManager.characterManager.abilities(for: character)
        return pending.options.compactMap { id in deck.first { $0.cardId == id } }
    }

    static func detail(_ kind: BoardCoordinator.PendingCardPlay.Kind) -> String {
        switch kind {
        case .half(let top):
            return "Play one card from your hand and perform its \(top ? "top" : "bottom") half now."
        case .anotherTurn(let after):
            return "Play two cards for another turn this round. The first one leads: its initiative must be later than \(after)."
        }
    }

    /// Whether the cards chosen can be played: one for a half; two, the first later, for a turn.
    static func canPlay(_ chosen: [Int], kind: BoardCoordinator.PendingCardPlay.Kind, initiative: (Int) -> Int) -> Bool {
        switch kind {
        case .half: return chosen.count == 1
        case .anotherTurn(let after): return chosen.count == 2 && initiative(chosen[0]) > after
        }
    }

    var body: some View {
        let ready = Self.canPlay(chosen, kind: pending.kind) { id in cards.first { $0.cardId == id }?.initiative ?? 0 }
        VStack(alignment: .leading, spacing: 12) {
            Text(pending.itemName)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
            Text(Self.detail(pending.kind))
                .font(.body)
                .foregroundStyle(BoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cards) { card in
                        let id = card.cardId ?? 0
                        AbilityCardTile(card: card, character: character, selected: chosen.contains(id), width: 120)
                            .overlay(alignment: .bottom) {
                                if pending.count == 2, let index = chosen.firstIndex(of: id) {
                                    Text(index == 0 ? "Lead · \(card.initiative)" : "Second")
                                        .font(BoardTheme.font(size: 11, weight: .bold))
                                        .foregroundStyle(BoardTheme.sheet)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(BoardTheme.brass, in: Capsule())
                                        .padding(.bottom, 4)
                                }
                            }
                            .onTapGesture { toggle(id) }
                            .accessibilityAddTraits(chosen.contains(id) ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Don\u{2019}t Use It") { coordinator.resolveCardPlay([]) }
                    .buttonStyle(.boardQuiet)
                Button(pending.count == 2 ? "Take Another Turn" : "Play This Card") {
                    coordinator.resolveCardPlay(chosen)
                }
                .buttonStyle(.boardPrimary)
                .disabled(!ready)
            }
        }
        .padding(20)
        .frame(maxWidth: 760)
        .boardPanel()
        .padding()
    }

    private func toggle(_ id: Int) {
        if let index = chosen.firstIndex(of: id) {
            chosen.remove(at: index)
        } else if chosen.count < pending.count {
            chosen.append(id)
        } else if pending.count == 1 {
            chosen = [id]
        }
    }
}
