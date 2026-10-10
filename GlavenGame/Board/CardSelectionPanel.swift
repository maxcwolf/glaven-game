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
        VStack(alignment: .leading, spacing: 10) {
            header
            // The hand as the real cards, one row; scrolls when it doesn't fit.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(handCards.enumerated()), id: \.offset) { index, card in
                        cardButton(card, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)   // room for a chosen card to rise
            }
        }
        .padding(.vertical, 14)
        .background(BoardTheme.sheet)
        .background(BoardTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(BoardTheme.border.opacity(0.5)).frame(height: 1)
        }
        // Note: .id(charID) is applied externally in BoardView to reset @State
    }

    /// The character, what to do, and the rest and confirm buttons.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(GameText.characterName(character, labels: gameManager.editionStore))
                .font(BoardTheme.display(24))
                .foregroundStyle(BoardTheme.text)
            Text(Self.instruction(chosen: selectedCards.count))
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 8)
            if character.discardedCards.count >= 2 {
                Button {
                    coordinator.chooseLongRest(for: character.id)
                } label: {
                    Text("Long Rest")
                        .font(BoardTheme.font(size: 13, weight: .medium))
                        .foregroundStyle(BoardTheme.brass)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .overlay(Capsule().stroke(BoardTheme.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Heal 2 HP, recover discarded cards to hand, permanently lose one. Acts last (initiative 99).")
            }
            if selectedCards.count == 2 {
                Button("Confirm") {
                    confirmSelection()
                }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.brass)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
    }

    /// What the header asks for, by how many cards are chosen.
    static func instruction(chosen: Int) -> String {
        switch chosen {
        case 0: return "Choose two cards; the first sets your initiative"
        case 1: return "Choose a second card"
        default: return "Tap a chosen card to make it lead, or another card to play it instead of the second"
        }
    }

    /// A card in the hand: the real card, risen and ringed when chosen, with its role.
    private func cardButton(_ card: AbilityModel, index: Int) -> some View {
        let isTop = topCardIndex == index
        let isBtm = btmCardIndex == index
        let chosen = isTop || isBtm
        return Button {
            toggleCardSelection(index)
        } label: {
            cardFace(card)
                .frame(height: Self.cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(chosen ? BoardTheme.brass : .clear, lineWidth: 3))
                .overlay(alignment: .bottom) {
                    if chosen {
                        Text(isTop ? "Lead · \(card.initiative)" : "Second")
                            .font(BoardTheme.font(size: 12, weight: .bold))
                            .foregroundStyle(isTop ? BoardTheme.sheet : BoardTheme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isTop ? BoardTheme.brass : BoardTheme.raised, in: Capsule())
                            .overlay(Capsule().stroke(BoardTheme.brass, lineWidth: isTop ? 0 : 1))
                            .offset(y: 10)
                    }
                }
                .offset(y: chosen ? -10 : 0)
                .animation(.snappy, value: chosen)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // The card full size, for reading its text.
            if let id = card.cardId {
                Button {
                    coordinator.showCardPreview(cardId: id)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(BoardTheme.font(size: 12, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .frame(width: 28, height: 28)
                        .background(BoardTheme.sheet.opacity(0.8), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: chosen ? -10 : 0)
                .accessibilityLabel("Show \(card.name ?? "the card") full size")
            }
        }
        .accessibilityLabel("\(card.name ?? "Card"), initiative \(card.initiative)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityHint(isTop ? "Leads: sets your initiative" : (isBtm ? "Second card" : "Choose this card"))
    }

    static let cardHeight: CGFloat = 190

    /// The card's scan, or its text when there's no scan (other editions).
    @ViewBuilder
    private func cardFace(_ card: AbilityModel) -> some View {
        if let id = card.cardId, let image = ImageLoader.abilityCardImage(edition: character.edition, cardId: id) {
            #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            #endif
        } else {
            BoardAbilityCardView(card: card, characterColor: characterColor, highlight: .none,
                                 width: 130, height: Self.cardHeight, labelResolver: labelResolver)
        }
    }

    // MARK: - Selection Logic

    private func toggleCardSelection(_ index: Int) {
        selectedCards = Self.selection(selectedCards, tapping: index)
        BoardSoundPlayer.play(.cardPick)
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
