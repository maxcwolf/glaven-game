import SwiftUI

struct LootDeckSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var deck: LootDeck { gameManager.game.lootDeck }

    private var drawnCards: [Loot] {
        guard deck.current >= 0 else { return [] }
        return Array(deck.cards.prefix(deck.current + 1)).reversed()
    }

    private var remainingCards: [Loot] {
        guard deck.current + 1 < deck.cards.count else { return [] }
        return Array(deck.cards.suffix(from: deck.current + 1))
    }

    private var playerCount: Int {
        max(2, gameManager.game.activeCharacters.count)
    }

    var body: some View {
        NavigationStack {
            List {
                // Deck status
                Section {
                    HStack {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(GlavenTheme.accentText)
                        Text("Total Cards")
                            .foregroundStyle(GlavenTheme.primaryText)
                        Spacer()
                        Text("\(deck.cards.count)")
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.primaryText)
                    }
                    HStack {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(.orange)
                        Text("Drawn")
                            .foregroundStyle(GlavenTheme.primaryText)
                        Spacer()
                        Text("\(max(0, deck.current + 1))")
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                    HStack {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.green)
                        Text("Remaining")
                            .foregroundStyle(GlavenTheme.primaryText)
                        Spacer()
                        Text("\(deck.remainingCount)")
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("Deck Status")
                }

                // Drawn cards
                if !drawnCards.isEmpty {
                    Section {
                        ForEach(drawnCards) { loot in
                            lootRow(loot)
                        }
                    } header: {
                        Text("Drawn Cards")
                    }
                }

                // Remaining (face-down, just show count per type)
                if !remainingCards.isEmpty {
                    Section {
                        let grouped = Dictionary(grouping: remainingCards) { $0.type }
                        ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                            HStack {
                                Image(systemName: iconForLoot(type))
                                    .foregroundStyle(colorForLoot(type))
                                Text(displayName(type))
                                    .foregroundStyle(GlavenTheme.primaryText)
                                Spacer()
                                Text("\(grouped[type]?.count ?? 0) cards")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                        }
                    } header: {
                        Text("Remaining (\(remainingCards.count) cards)")
                    }
                }
            }
            .navigationTitle("Loot Deck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        gameManager.lootManager.shuffleDeck()
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lootRow(_ loot: Loot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForLoot(loot.type))
                .font(.system(size: 18))
                .foregroundStyle(colorForLoot(loot.type))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(loot.type))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(GlavenTheme.primaryText)

                Text("Card #\(loot.cardId)")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            Spacer()

            // Value for current player count
            let value = lootValue(loot)
            if value > 0 {
                Text("+\(value)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(colorForLoot(loot.type))
            }
        }
        .padding(.vertical, 2)
    }

    private func lootValue(_ loot: Loot) -> Int {
        gameManager.lootManager.getValue(for: loot)
    }

    private func displayName(_ type: LootType) -> String {
        switch type {
        case .money: return "Gold"
        case .lumber: return "Lumber"
        case .metal: return "Metal"
        case .hide: return "Hide"
        case .arrowvine: return "Arrowvine"
        case .axenut: return "Axenut"
        case .corpsecap: return "Corpsecap"
        case .flamefruit: return "Flamefruit"
        case .rockroot: return "Rockroot"
        case .snowthistle: return "Snowthistle"
        case .random_item: return "Random Item"
        case .special1: return "Special 1"
        case .special2: return "Special 2"
        }
    }

    private func iconForLoot(_ type: LootType) -> String {
        switch type {
        case .money: return "dollarsign.circle.fill"
        case .lumber: return "tree.fill"
        case .metal: return "hammer.fill"
        case .hide: return "square.fill"
        case .arrowvine, .axenut, .corpsecap, .flamefruit, .rockroot, .snowthistle:
            return "leaf.fill"
        case .random_item: return "gift.fill"
        case .special1, .special2: return "star.fill"
        }
    }

    private func colorForLoot(_ type: LootType) -> Color {
        switch type {
        case .money: return .yellow
        case .lumber: return .brown
        case .metal: return .gray
        case .hide: return .orange
        case .arrowvine: return .green
        case .axenut: return .brown
        case .corpsecap: return .purple
        case .flamefruit: return .red
        case .rockroot: return .gray
        case .snowthistle: return .cyan
        case .random_item: return .indigo
        case .special1, .special2: return .pink
        }
    }
}
