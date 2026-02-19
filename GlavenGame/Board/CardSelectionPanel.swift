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

                Text("— \(character.title.isEmpty ? character.name.replacingOccurrences(of: "-", with: " ").capitalized : character.title)")
                    .font(.subheadline)
                    .foregroundStyle(characterColor)

                Spacer()

                if selectedCards.count == 1 {
                    Text("Pick a second card for its bottom actions")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                } else if selectedCards.count == 2 {
                    Text("Tap a selected card to swap TOP/BTM roles")
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
                            height: (isTop || isBtm) ? 240 : 220,
                            roleBadge: isTop ? "TOP — Init \(card.initiative)" : (isBtm ? "BOTTOM" : nil),
                            roleBadgeColor: isTop ? .yellow : .cyan,
                            labelResolver: labelResolver,
                            onPreview: card.cardId.map { id in { coordinator.showCardPreview(cardId: id) } }
                        )
                        .onTapGesture {
                            toggleCardSelection(index)
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Bottom buttons
            HStack(spacing: 16) {
                if character.discardedCards.count >= 2 {
                    Button("Long Rest") {
                        character.initiative = 99
                        character.longRest = true
                        coordinator.log("\(character.id): Long rest selected", category: .rest)
                        coordinator.completeCardSelection(for: character.id)
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
                Color.black.opacity(0.85)
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
        if let i = selectedCards.firstIndex(of: index) {
            if selectedCards.count == 2 {
                // Tapping a selected card swaps the roles (top ↔ bottom)
                selectedCards = selectedCards.reversed()
            } else {
                // Deselect
                selectedCards.remove(at: i)
            }
        } else if selectedCards.count < 2 {
            selectedCards.append(index)
        }
    }

    private func confirmSelection() {
        guard selectedCards.count == 2 else { return }

        let cards = handCards
        let topIdx = selectedCards[0]
        let btmIdx = selectedCards[1]

        guard topIdx < cards.count, btmIdx < cards.count else { return }

        let topCard = cards[topIdx]
        let bottomCard = cards[btmIdx]

        // Initiative comes from the TOP card
        character.initiative = topCard.initiative

        // Store the selected pair so PlayerTurnController can use them
        coordinator.storeSelectedCards(for: character.id, top: topCard, bottom: bottomCard)

        coordinator.log("\(character.id): TOP \(topCard.name ?? "?") (init \(topCard.initiative)) / BTM \(bottomCard.name ?? "?")", category: .round)
        coordinator.completeCardSelection(for: character.id)
    }
}
