import SwiftUI

/// SwiftUI panel for selecting ability cards during the card selection phase.
/// Cards display top and bottom action halves like physical Gloomhaven cards.
/// First selected card = TOP (uses top actions, sets initiative).
/// Second selected card = BTM (uses bottom actions).
struct CardSelectionPanel: View {
    @Environment(GameManager.self) private var gameManager
    @Bindable var coordinator: BoardCoordinator

    @State private var selectedCards: [Int] = [] // ordered: [0]=top card, [1]=bottom card

    /// The character currently selecting cards.
    let character: GameCharacter

    /// Character's theme color.
    private var characterColor: Color {
        Color(hex: character.color) ?? .blue
    }

    /// Available hand cards for this character.
    private var handCards: [AbilityModel] {
        let deckName = character.characterData?.deck ?? character.name
        guard let deckData = gameManager.editionStore.deckData(
            name: deckName, edition: character.edition
        ) else { return [] }

        return character.handCards.compactMap { cardId in
            deckData.abilities.first(where: { $0.cardId == cardId })
        }
    }

    private var topCardIndex: Int? { selectedCards.count >= 1 ? selectedCards[0] : nil }
    private var btmCardIndex: Int? { selectedCards.count >= 2 ? selectedCards[1] : nil }

    private var labelResolver: ((String) -> String?) {
        { gameManager.editionStore.resolveCustomText($0, edition: character.edition) }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Select 2 Cards")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("— \(GameText.characterName(character))")
                    .font(.subheadline)
                    .foregroundStyle(characterColor)

                Spacer()

                if selectedCards.count == 1 {
                    Text("Pick a second card. The first card sets your initiative.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                } else if selectedCards.count == 2 {
                    Text("Tap a chosen card to make it lead, another card to play it instead of the second. You pick top and bottom halves on your turn.")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.8))
                }
            }
            .padding(.horizontal)

            // Card scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(handCards.enumerated()), id: \.offset) { index, card in
                        let isTop = topCardIndex == index
                        let isBtm = btmCardIndex == index
                        let highlight: CardHighlight = isTop ? .top : (isBtm ? .bottom : .none)

                        BoardAbilityCardView(
                            card: card,
                            characterColor: characterColor,
                            highlight: highlight,
                            width: 130,
                            // One height for every card, so choosing one doesn't resize the panel.
                            height: 240,
                            roleBadge: isTop ? "LEAD · \(card.initiative)" : (isBtm ? "SECOND" : nil),
                            roleBadgeColor: isTop ? .yellow : .cyan,
                            labelResolver: labelResolver,
                            onPreview: card.cardId.map { id in { coordinator.showCardPreview(cardId: id) } }
                        )
                        .onTapGesture {
                            toggleCardSelection(index)
                        }
                        .accessibilityAddTraits(isTop || isBtm ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(isTop ? "Leads: sets your initiative" : (isBtm ? "Second card" : "Choose this card"))
                    }
                }
                .padding(.horizontal)
            }

            // Bottom buttons
            HStack(spacing: 16) {
                if character.discardedCards.count >= 2 {
                    Button("Long Rest") {
                        coordinator.chooseLongRest(for: character.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .help("Heal 2 HP, recover discarded cards to hand, permanently lose one. Acts last (initiative 99).")
                }

                Spacer()

                if selectedCards.count == 2 {
                    Button("Confirm") {
                        confirmSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Opaque: the battle log behind mustn't show through the cards.
                Color.black
                characterColor.opacity(0.2)
                LinearGradient(
                    colors: [characterColor.opacity(0.1), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(characterColor.opacity(0.3), lineWidth: 1)
        )
        // Note: .id(charID) is applied externally in BoardView to reset @State
    }

    // MARK: - Selection Logic

    private func toggleCardSelection(_ index: Int) {
        selectedCards = Self.selection(selectedCards, tapping: index)
    }

    /// The cards chosen after tapping `index` (in order: lead, second). A chosen card's tap makes
    /// it lead when two are chosen, or puts it back; another card joins, or, with two already
    /// chosen, takes the second card's place, so a mis-tap is never stuck.
    static func selection(_ selected: [Int], tapping index: Int) -> [Int] {
        if let i = selected.firstIndex(of: index) {
            if selected.count == 2 {
                return selected.reversed()
            }
            var remaining = selected
            remaining.remove(at: i)
            return remaining
        }
        if selected.count < 2 { return selected + [index] }
        return [selected[0], index]
    }

    private func confirmSelection() {
        guard selectedCards.count == 2 else { return }

        let cards = handCards
        let topIdx = selectedCards[0]
        let btmIdx = selectedCards[1]

        guard topIdx < cards.count, btmIdx < cards.count else { return }

        // The first selected card leads (its initiative is used).
        coordinator.chooseCards(for: character.id, leading: cards[topIdx], other: cards[btmIdx])
    }
}
