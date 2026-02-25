import SwiftUI

struct AttackModifierSelectSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var drawnCard: AttackModifier?
    @State private var drawnFrom: String?

    private var characters: [GameCharacter] {
        gameManager.game.characters.filter { !$0.exhausted && !$0.absent }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Drawn card display
                    if let card = drawnCard {
                        drawnCardView(card)
                    }

                    // Monster deck
                    deckSection(
                        title: "Monster Deck",
                        icon: "pawprint.fill",
                        color: .red,
                        deck: gameManager.game.monsterAttackModifierDeck
                    ) {
                        if let card = gameManager.attackModifierManager.drawMonsterCard() {
                            drawnCard = card
                            drawnFrom = "Monster"
                        }
                    } onShuffle: {
                        gameManager.attackModifierManager.shuffleDeck(&gameManager.game.monsterAttackModifierDeck)
                    }

                    // Ally deck
                    deckSection(
                        title: "Ally Deck",
                        icon: "person.2.fill",
                        color: .green,
                        deck: gameManager.game.allyAttackModifierDeck
                    ) {
                        if let card = gameManager.attackModifierManager.drawAllyCard() {
                            drawnCard = card
                            drawnFrom = "Ally"
                        }
                    } onShuffle: {
                        gameManager.attackModifierManager.shuffleDeck(&gameManager.game.allyAttackModifierDeck)
                    }

                    // Character decks
                    ForEach(characters, id: \.id) { character in
                        let charName = character.title.isEmpty
                            ? character.name.replacingOccurrences(of: "-", with: " ").capitalized
                            : character.title
                        deckSection(
                            title: charName,
                            icon: "person.fill",
                            color: Color(hex: character.color) ?? .blue,
                            deck: character.attackModifierDeck
                        ) {
                            if let card = gameManager.attackModifierManager.drawCharacterCard(for: character) {
                                drawnCard = card
                                drawnFrom = charName
                            }
                        } onShuffle: {
                            gameManager.attackModifierManager.shuffleDeck(&character.attackModifierDeck)
                        }
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Attack Modifier Decks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func drawnCardView(_ card: AttackModifier) -> some View {
        VStack(spacing: 8) {
            if let from = drawnFrom {
                Text("Drawn from \(from)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            HStack(spacing: 8) {
                Text(card.displayText)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(colorForCard(card))

                if card.rolling {
                    Image(systemName: "arrow.forward.circle")
                        .foregroundStyle(.orange)
                }
                if card.shuffle {
                    Image(systemName: "shuffle")
                        .foregroundStyle(.orange)
                }
            }

            if !card.effects.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(card.effects.enumerated()), id: \.offset) { _, effect in
                        Text(effectLabel(effect))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func deckSection(title: String, icon: String, color: Color, deck: AttackModifierDeck, onDraw: @escaping () -> Void, onShuffle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlavenTheme.primaryText)
                Spacer()

                Text("\(deck.remainingCount) left")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onDraw()
                    }
                } label: {
                    Label("Draw", systemImage: "hand.draw.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.2))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if deck.needsShuffle {
                    Button {
                        onShuffle()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Current card mini display
                if let current = deck.currentCard {
                    Text(current.displayText)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(colorForCard(current))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorForCard(current).opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func effectLabel(_ effect: AttackModifierEffect) -> String {
        if let value = effect.value {
            return "\(effect.type.rawValue.capitalized) \(value.stringValue)"
        }
        return effect.type.rawValue.capitalized
    }

    private func colorForCard(_ card: AttackModifier) -> Color {
        switch card.type {
        case .bless: return .yellow
        case .curse: return .purple
        case .null_: return .red
        case .double_: return .yellow
        default:
            if card.value > 0 { return .green }
            if card.value < 0 { return .red }
            return GlavenTheme.primaryText
        }
    }
}
