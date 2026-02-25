import SwiftUI

/// Standalone Loot Deck tool for managing and drawing from the loot deck.
struct LootDeckToolSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var lastDrawn: Loot?
    @State private var showConfig = false

    private var deck: LootDeck { gameManager.game.lootDeck }

    private var drawnCards: [Loot] {
        guard deck.current >= 0 else { return [] }
        return Array(deck.cards.prefix(deck.current + 1)).reversed()
    }

    private var playerCount: Int {
        max(2, gameManager.game.activeCharacters.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Draw area
                drawSection

                Divider()

                // Card list
                ScrollView {
                    VStack(spacing: 12) {
                        deckStatusSection

                        if !drawnCards.isEmpty {
                            drawnCardsSection
                        }

                        remainingSection
                    }
                    .padding()
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Loot Deck")
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
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            gameManager.lootManager.shuffleDeck()
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                        Button {
                            showConfig = true
                        } label: {
                            Label("Configure Deck", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showConfig) {
                LootDeckConfigSheet()
            }
        }
    }

    // MARK: - Draw Section

    @ViewBuilder
    private var drawSection: some View {
        VStack(spacing: 12) {
            if let loot = lastDrawn {
                // Show the drawn card
                VStack(spacing: 4) {
                    Image(systemName: iconForLoot(loot.type))
                        .font(.system(size: 40))
                        .foregroundStyle(colorForLoot(loot.type))

                    Text(displayName(loot.type))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.primaryText)

                    let value = gameManager.lootManager.getValue(for: loot)
                    if value > 0 {
                        Text("+\(value)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(colorForLoot(loot.type))
                    }
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(GlavenTheme.secondaryText.opacity(0.3))
            }

            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let card = gameManager.lootManager.drawCard() {
                            lastDrawn = card
                        }
                    }
                } label: {
                    Label("Draw", systemImage: "hand.draw.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(GlavenTheme.accentText.opacity(0.2))
                        .foregroundStyle(GlavenTheme.accentText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(deck.remainingCount <= 0)

                Text("\(deck.remainingCount) left")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(GlavenTheme.cardBackground)
    }

    // MARK: - Deck Status

    @ViewBuilder
    private var deckStatusSection: some View {
        HStack(spacing: 20) {
            VStack(spacing: 2) {
                Text("\(deck.cards.count)")
                    .font(GlavenFont.title(size: 24))
                    .foregroundStyle(.white)
                Text("Total")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            VStack(spacing: 2) {
                Text("\(max(0, deck.current + 1))")
                    .font(GlavenFont.title(size: 24))
                    .foregroundStyle(.orange)
                Text("Drawn")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            VStack(spacing: 2) {
                Text("\(deck.remainingCount)")
                    .font(GlavenFont.title(size: 24))
                    .foregroundStyle(.green)
                Text("Remaining")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Drawn Cards

    @ViewBuilder
    private var drawnCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drawn (\(drawnCards.count))")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            ForEach(drawnCards) { loot in
                lootRow(loot, dimmed: true)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Remaining

    @ViewBuilder
    private var remainingSection: some View {
        let remaining = deck.current + 1 < deck.cards.count
            ? Array(deck.cards.suffix(from: deck.current + 1))
            : []

        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remaining (\(remaining.count))")
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)

                let grouped = Dictionary(grouping: remaining) { $0.type }
                ForEach(grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { type in
                    HStack {
                        Image(systemName: iconForLoot(type))
                            .foregroundStyle(colorForLoot(type))
                            .frame(width: 24)
                        Text(displayName(type))
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.primaryText)
                        Spacer()
                        Text("x\(grouped[type]?.count ?? 0)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Loot Row

    @ViewBuilder
    private func lootRow(_ loot: Loot, dimmed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForLoot(loot.type))
                .font(.system(size: 16))
                .foregroundStyle(colorForLoot(loot.type))
                .frame(width: 24)

            Text(displayName(loot.type))
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.primaryText)

            Spacer()

            let value = gameManager.lootManager.getValue(for: loot)
            if value > 0 {
                Text("+\(value)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(colorForLoot(loot.type))
            }
        }
        .opacity(dimmed ? 0.7 : 1.0)
    }

    // MARK: - Helpers

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

// MARK: - Loot Deck Configuration

struct LootDeckConfigSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var goldCount = 12
    @State private var lumberCount = 2
    @State private var metalCount = 2
    @State private var hideCount = 2
    @State private var herbCount = 2
    @State private var randomItemCount = 0
    @State private var includeHerbs = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Base Cards") {
                    Stepper("Gold: \(goldCount)", value: $goldCount, in: 0...20)
                }

                Section("Resources (FH)") {
                    Stepper("Lumber: \(lumberCount)", value: $lumberCount, in: 0...6)
                    Stepper("Metal: \(metalCount)", value: $metalCount, in: 0...6)
                    Stepper("Hide: \(hideCount)", value: $hideCount, in: 0...6)
                }

                Section("Herbs") {
                    Toggle("Include Herbs", isOn: $includeHerbs)
                    if includeHerbs {
                        Stepper("Each Herb: \(herbCount)", value: $herbCount, in: 0...4)
                    }
                }

                Section("Special") {
                    Stepper("Random Items: \(randomItemCount)", value: $randomItemCount, in: 0...4)
                }

                Section {
                    Button("Build Deck") {
                        buildAndApplyDeck()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("Configure Loot Deck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func buildAndApplyDeck() {
        gameManager.lootManager.onBeforeMutate?()

        var cards: [Loot] = []
        var cardId = 1

        for _ in 0..<goldCount {
            cards.append(Loot(type: .money, cardId: cardId))
            cardId += 1
        }
        for _ in 0..<lumberCount {
            cards.append(Loot(type: .lumber, cardId: cardId))
            cardId += 1
        }
        for _ in 0..<metalCount {
            cards.append(Loot(type: .metal, cardId: cardId))
            cardId += 1
        }
        for _ in 0..<hideCount {
            cards.append(Loot(type: .hide, cardId: cardId))
            cardId += 1
        }
        if includeHerbs {
            let herbs: [LootType] = [.arrowvine, .axenut, .corpsecap, .flamefruit, .rockroot, .snowthistle]
            for herb in herbs {
                for _ in 0..<herbCount {
                    cards.append(Loot(type: herb, cardId: cardId))
                    cardId += 1
                }
            }
        }
        for _ in 0..<randomItemCount {
            cards.append(Loot(type: .random_item, cardId: cardId))
            cardId += 1
        }

        cards.shuffle()
        gameManager.game.lootDeck = LootDeck(cards: cards, current: -1, active: true)
    }
}
