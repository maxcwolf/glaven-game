import SwiftUI

/// The Enhancer (GH p.42–43): pick one of the character's cards, then a slot on it, then what to
/// put there. An enhancement is for good, so each purchase is confirmed first.
struct EnhancementSheet: View {
    @Environment(GameManager.self) private var gameManager
    let character: GameCharacter
    @State private var cardId: Int?
    @State private var pending: Purchase?
    /// Off for snapshots: ImageRenderer draws neither scroll views nor navigation stacks.
    var scrolls = true
    /// The card shown first (otherwise the lowest-level one).
    var startCard: Int? = nil

    struct Purchase: Identifiable {
        let slot: CardEnhancing.Slot
        let enhancement: EnhancementAction
        let cost: Int
        var id: String { "\(slot.id)-\(enhancement.rawValue)" }
    }

    private var enhancer: EnhancementsManager { gameManager.enhancementsManager }
    private var name: String { GameText.characterName(character, labels: gameManager.editionStore) }
    private var open: Bool { enhancer.enhancerOpen(edition: character.edition) }

    /// The character's cards that have slots, lowest level first.
    private var cards: [AbilityModel] {
        gameManager.characterManager.cardPool(for: character)
            .filter { !CardEnhancing.slots(of: $0).isEmpty }
            .sorted { (CardPool.level(of: $0) ?? 1, $0.cardId ?? 0) < (CardPool.level(of: $1) ?? 1, $1.cardId ?? 0) }
    }

    private var selected: AbilityModel? { cards.first { $0.cardId == cardId } }

    var onDone: () -> Void = {}

    var body: some View {
        TownDialog(title: "The Enhancer", subtitle: "\(name) \u{00B7} enhancements stay on a card for good",
                   portrait: (ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                              Color(hex: character.color) ?? BoardTheme.border),
                   onDone: onDone) {
            TownGold(amount: character.loot)
        } content: {
            HStack(alignment: .top, spacing: 16) {
                scrolling {
                    VStack(alignment: .leading, spacing: 10) {
                        if !open { lockedNote }
                        TownSmallCaps(text: "Choose a card")
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 4), alignment: .leading, spacing: 8) {
                            ForEach(cards) { card in
                                AbilityCardTile(card: card, character: character, selected: card.cardId == cardId, width: 96)
                                    .opacity(card.cardId == cardId ? 1 : 0.7)
                                    .onTapGesture { cardId = card.cardId; pending = nil }
                            }
                        }
                    }
                }
                .frame(width: 410)
                scrolling {
                    HStack(alignment: .top, spacing: 14) {
                        if let card = selected {
                            AbilityCardTile(card: card, character: character, selected: true, width: 210)
                        }
                        slotsPanel
                    }
                }
            }
            .padding(18)
        }
        .onAppear { if cardId == nil { cardId = startCard ?? cards.first?.cardId } }
    }

    @ViewBuilder
    private func scrolling<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        if scrolls { ScrollView { inner() } } else { inner().frame(maxHeight: .infinity, alignment: .top) }
    }

    private var lockedNote: some View {
        Label("The Enhancer opens once the party earns The Power of Enhancement, from Frozen Hollow.",
              systemImage: "lock.fill")
            .font(BoardTheme.font(size: 14))
            .foregroundStyle(BoardTheme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
    }

    // MARK: - Slots

    @ViewBuilder
    private var slotsPanel: some View {
        if let card = selected {
            VStack(alignment: .leading, spacing: 14) {
                Text(card.name ?? "Card")
                    .font(BoardTheme.display(24))
                    .foregroundStyle(BoardTheme.text)
                let count = EnhancementsManager.enhancementCount(on: card.cardId ?? 0, in: character.enhancements)
                Text("Level \(CardPool.level(of: card).map(String.init) ?? "X") · \(count == 0 ? "nothing enhanced yet" : "\(count) enhanced")")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                if count > 0 {
                    Text("Each enhancement already on a card adds \(character.edition == "fh" ? 50 : 75) gold.")
                        .font(BoardTheme.font(size: 12))
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                ForEach(CardEnhancing.slots(of: card)) { slot in
                    slotRow(slot, card: card)
                }
            }
        } else {
            Text("Choose a card.")
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }

    private func slotRow(_ slot: CardEnhancing.Slot, card: AbilityModel) -> some View {
        let current = EnhancementsManager.enhancement(on: slot.cardId, half: slot.half, actionIndex: slot.actionIndex,
                                                      slotIndex: slot.slotIndex, in: character.enhancements)
        let options = CardEnhancing.options(for: slot, edition: character.edition)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(slot.type))
                    .foregroundStyle(BoardTheme.brass)
                    .accessibilityLabel(Self.shapeName(slot.type))
                Text(Self.line(slot))
                    .font(BoardTheme.font(size: 15, weight: .semibold))
                    .foregroundStyle(BoardTheme.text)
                Spacer()
                let slotsOnLine = slot.action.enhancementTypes?.count ?? 1
                Text((slot.half == "top" ? "TOP" : "BOTTOM")
                     + (slotsOnLine > 1 ? " · SLOT \(slot.slotIndex + 1) OF \(slotsOnLine)" : ""))
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .kerning(1.1)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            if slot.type == .hex, slot.action.type == .area, let pattern = slot.action.value?.stringValue {
                // Which marked hex this slot fills (Brute Force has two, one per slot).
                let marked = CardEnhancing.markedHexes(in: slot.action)
                AreaPatternView(pattern: pattern,
                                highlighted: marked.indices.contains(slot.slotIndex) ? marked[slot.slotIndex] : nil)
                    .padding(.vertical, 2)
            }
            if let current {
                Label(current.action.displayName, systemImage: "sparkles")
                    .font(BoardTheme.font(size: 14, weight: .semibold))
                    .foregroundStyle(BoardTheme.gain)
            } else if options.isEmpty {
                Text("The Enhancer can't do this one yet.")
                    .font(BoardTheme.font(size: 12))
                    .foregroundStyle(BoardTheme.secondaryText)
            } else if let pending, pending.slot.id == slot.id {
                // An enhancement is for good, so it's confirmed here first.
                HStack(spacing: 8) {
                    Text("\(pending.enhancement.displayName) for \(pending.cost) gold?")
                        .font(BoardTheme.font(size: 13, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                    Spacer(minLength: 4)
                    Button("Keep") { self.pending = nil }
                        .buttonStyle(.boardQuietCompact)
                    Button("Enhance") {
                        enhancer.buy(pending.enhancement, in: pending.slot, card: card, for: character)
                        self.pending = nil
                    }
                    .buttonStyle(.boardPrimaryCompact)
                    .accessibilityLabel("Enhance with \(pending.enhancement.displayName) for \(pending.cost) gold")
                }
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        let cost = CardEnhancing.cost(option, in: slot, card: card, enhancements: character.enhancements,
                                                      edition: character.edition)
                        let problem = enhancer.purchaseProblem(option, in: slot, card: card, for: character)
                        Button {
                            pending = Purchase(slot: slot, enhancement: option, cost: cost)
                        } label: {
                            HStack(spacing: 6) {
                                Text(option.displayName).foregroundStyle(BoardTheme.text)
                                Text("\(cost)").foregroundStyle(problem == nil ? BoardTheme.victory : BoardTheme.secondaryText)
                            }
                            .font(BoardTheme.font(size: 13, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 11)
                            .frame(minHeight: 32)
                            .background(BoardTheme.raised, in: Capsule())
                            .overlay(Capsule().stroke(problem == nil ? BoardTheme.brass.opacity(0.7) : BoardTheme.border.opacity(0.5)))
                            .opacity(problem == nil ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .disabled(problem != nil)
                        .accessibilityLabel("\(option.displayName), \(cost) gold")
                        .accessibilityHint(problem == .tooExpensive ? "Not enough gold" : "")
                    }
                }
            }
        }
        .padding(12)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }

    /// The printed line a slot sits on: "Attack 3", or "Attack 3 · Pierce 2" for a sub-action.
    static func line(_ slot: CardEnhancing.Slot) -> String {
        var host = slot.host
        host.subActions = nil
        let main = GameText.actionTitle(host)
        guard slot.actionIndex >= 100 else { return GameText.actionTitle(slot.action) }
        return "\(main) · \(GameText.actionTitle(slot.action))"
    }

    static func symbol(_ type: EnhancementSlotType) -> String {
        switch type {
        case .square: return "square"
        case .circle: return "circle"
        case .diamond: return "diamond"
        case .diamond_plus: return "plus.diamond"
        case .hex: return "hexagon"
        case .any: return "star"
        }
    }

    static func shapeName(_ type: EnhancementSlotType) -> String {
        switch type {
        case .square: return "Square slot"
        case .circle: return "Circle slot"
        case .diamond: return "Diamond slot"
        case .diamond_plus: return "Diamond-plus slot"
        case .hex: return "Hex slot"
        case .any: return "Any slot"
        }
    }
}
