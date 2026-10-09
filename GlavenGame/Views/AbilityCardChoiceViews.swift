import SwiftUI

/// An ability card as printed: the card scan when the game has it, the drawn card otherwise.
/// Selected cards get a brass edge and a check.
struct AbilityCardTile: View {
    @Environment(GameManager.self) private var gameManager
    let card: AbilityModel
    let character: GameCharacter
    var selected = false
    var width: CGFloat = 150

    private var height: CGFloat { width * 1.4 }

    var body: some View {
        face
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: BoardTheme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.small)
                .stroke(selected ? BoardTheme.brass : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BoardTheme.brass, .black)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if !enhancements.isEmpty {
                    Label(enhancements.joined(separator: ", "), systemImage: "sparkles")
                        .font(BoardTheme.font(size: 11, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(BoardTheme.scrim)
                }
            }
            .opacity(selected ? 1 : 0.85)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var enhancements: [String] { CardEnhancing.summary(of: card, enhancements: character.enhancements) }

    private var accessibilityText: String {
        let level = CardPool.level(of: card).map { "level \($0)" } ?? "level X"
        let enhanced = enhancements.isEmpty ? "" : ", enhanced: \(enhancements.joined(separator: ", "))"
        return "\(card.name ?? "Card"), \(level), initiative \(card.initiative)\(enhanced)"
    }

    @ViewBuilder
    private var face: some View {
        if let id = card.cardId, let image = ImageLoader.abilityCardImage(edition: character.edition, cardId: id) {
            #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            #endif
        } else {
            BoardAbilityCardView(card: card, characterColor: Color(hex: character.color) ?? .blue,
                                 highlight: .none, width: width, height: height,
                                 labelResolver: { gameManager.editionStore.resolveCustomText($0, edition: character.edition) })
        }
    }
}

/// Levelling up: pick one new ability card of the character's level or lower (GH p.44).
struct LevelUpCardSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    let character: GameCharacter
    @State private var picked: Int?

    private var cards: [AbilityModel] {
        gameManager.characterManager.choosableCards(for: character)
            .sorted { (CardPool.level(of: $0) ?? 0, $0.cardId ?? 0) > (CardPool.level(of: $1) ?? 0, $1.cardId ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose one card to add to \(name)'s pool. It can be of level \(character.level) or lower.")
                        .font(.body)
                        .foregroundStyle(BoardTheme.secondaryText)
                    let levels = Array(Set(cards.compactMap { CardPool.level(of: $0) })).sorted(by: >)
                    ForEach(levels, id: \.self) { level in
                        Text("LEVEL \(level)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BoardTheme.brass)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(cards.filter { CardPool.level(of: $0) == level }) { card in
                                AbilityCardTile(card: card, character: character, selected: picked == card.cardId)
                                    .onTapGesture { picked = card.cardId }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(BoardTheme.sheet)
            .navigationTitle("\(name) — Level \(character.level)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Card") {
                        if let picked { gameManager.characterManager.chooseCard(picked, for: character) }
                        dismiss()
                    }
                    .disabled(picked == nil)
                }
            }
        }
    }

    private var name: String { GameText.characterName(character, labels: gameManager.editionStore) }
}

/// Before a scenario: which cards from the pool the character brings, up to their hand size.
struct HandSheet: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    var onDone: () -> Void = {}
    @State private var hand: Set<Int> = []

    private var pool: [AbilityModel] {
        gameManager.characterManager.cardPool(for: character)
            .sorted { (CardPool.level(of: $0) ?? 1, $0.cardId ?? 0) < (CardPool.level(of: $1) ?? 1, $1.cardId ?? 0) }
    }

    private var size: Int { min(character.handSize, pool.count) }
    private var name: String { GameText.characterName(character, labels: gameManager.editionStore) }

    var body: some View {
        TownDialog(title: "\(name)'s Hand", subtitle: "The cards the \(name) takes into the next scenario",
                   doneDisabled: hand.count != size, onCancel: onDone, onDone: save) {
            Text("\(hand.count) of \(size) cards")
                .font(BoardTheme.font(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(hand.count == size ? BoardTheme.sheet : BoardTheme.text)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(hand.count == size ? BoardTheme.brass : BoardTheme.raised, in: Capsule())
                .fixedSize()
            Button("Cancel", action: onDone)
                .buttonStyle(.boardQuiet)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap a card to take it or leave it. The \(name) takes \(size) cards; each level up adds a card to choose from.")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                GeometryReader { geo in
                    let fit = Self.layout(count: pool.count, in: geo.size)
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.width), spacing: Self.gap), count: fit.columns),
                                  alignment: .leading, spacing: Self.gap) {
                            ForEach(pool) { card in
                                let id = card.cardId ?? 0
                                let chosen = hand.contains(id)
                                AbilityCardTile(card: card, character: character, selected: chosen, width: fit.width)
                                    .opacity(chosen ? 1 : 0.6)
                                    .onTapGesture {
                                        if chosen { hand.remove(id) } else if hand.count < size { hand.insert(id) }
                                    }
                            }
                        }
                        .padding(.top, 6)
                    }
                    .scrollDisabled(fit.fits)
                }
            }
            .padding(18)
        }
        .onAppear {
            let poolIds = Set(pool.compactMap(\.cardId))
            hand = Set(character.handCards.filter(poolIds.contains).prefix(size))
        }
    }

    private func save() {
        let ordered = pool.compactMap(\.cardId).filter(hand.contains)
        gameManager.characterManager.setHand(ordered, for: character)
        onDone()
    }

    static let gap: CGFloat = 12

    /// The largest cards that show the whole pool at once in `space`, in 5 to 10 columns; with
    /// a pool too big for that, 8 columns that scroll.
    static func layout(count: Int, in space: CGSize) -> (columns: Int, width: CGFloat, fits: Bool) {
        var best: (columns: Int, width: CGFloat)?
        for columns in 5...10 {
            let width = (space.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let rows = (count + columns - 1) / columns
            let height = CGFloat(rows) * width * 1.4 + gap * CGFloat(max(0, rows - 1)) + 6
            if height <= space.height, width > (best?.width ?? 0) { best = (columns, width) }
        }
        if let best { return (best.columns, floor(best.width), true) }
        let width = (space.width - gap * 7) / 8
        return (8, floor(max(80, width)), false)
    }
}
