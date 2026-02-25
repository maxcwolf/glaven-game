import SwiftUI

struct AttackModifierDeckDialog: View {
    let label: String
    @Binding var deck: AttackModifierDeck
    let shuffleAction: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var scale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Deck summary
                    deckSummary

                    // Drawn cards
                    if !drawnCards.isEmpty {
                        cardSection(title: "Drawn (\(drawnCards.count))", cards: drawnCards, dimmed: true)
                    }

                    // Remaining cards (face down - just show count by type)
                    remainingSection
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("\(label) Deck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        shuffleAction()
                        dismiss()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }
            }
        }
    }

    private var drawnCards: [AttackModifier] {
        guard deck.current >= 0 else { return [] }
        return Array(deck.cards[0...min(deck.current, deck.cards.count - 1)]).reversed()
    }

    private var remainingCards: [AttackModifier] {
        guard deck.current + 1 < deck.cards.count else { return [] }
        return Array(deck.cards[(deck.current + 1)...])
    }

    // MARK: - Deck Summary

    @ViewBuilder
    private var deckSummary: some View {
        HStack(spacing: 20) {
            summaryBadge(value: "\(deck.attackModifiers.count)", label: "Total", color: .white)
            summaryBadge(value: "\(drawnCards.count)", label: "Drawn", color: .orange)
            summaryBadge(value: "\(deck.remainingCount)", label: "Remaining", color: .green)

            if deck.needsShuffle {
                HStack(spacing: 4) {
                    Image(systemName: "shuffle")
                        .foregroundStyle(.yellow)
                    Text("Needs Shuffle")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func summaryBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(GlavenFont.title(size: 24))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
    }

    // MARK: - Card Section

    @ViewBuilder
    private func cardSection(title: String, cards: [AttackModifier], dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)], spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    cardCell(card: card)
                        .opacity(dimmed ? 0.7 : 1.0)
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Remaining Section

    @ViewBuilder
    private var remainingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remaining (\(deck.remainingCount))")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            // Group remaining by type and count
            let grouped = Dictionary(grouping: remainingCards, by: { cardKey($0) })
            let sorted = grouped.sorted { a, b in a.key < b.key }

            ForEach(sorted, id: \.key) { key, cards in
                if let sample = cards.first {
                    HStack {
                        cardCell(card: sample)
                            .frame(width: 80)
                        Text("x\(cards.count)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Spacer()
                        if sample.rolling {
                            Image(systemName: "arrow.forward.circle")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Card Cell

    @ViewBuilder
    private func cardCell(card: AttackModifier) -> some View {
        VStack(spacing: 2) {
            AttackModifierCardView(modifier: card, size: 50)

            if card.rolling {
                Image(systemName: "arrow.forward.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
            }
        }
    }

    // cardDisplayText and cardColor removed — now using AttackModifierCardView

    private func cardKey(_ card: AttackModifier) -> String {
        "\(card.type.rawValue)-\(card.value)-\(card.rolling)-\(card.effects.map(\.type.rawValue).joined())"
    }
}
