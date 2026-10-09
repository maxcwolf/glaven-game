import SwiftUI

/// The Enhancer (GH p.42–43): pick one of the character's cards, then a slot on it, then what to
/// put there. An enhancement is for good, so each purchase is confirmed first.
struct EnhancementSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    let character: GameCharacter
    @State private var cardId: Int?
    @State private var pending: Purchase?
    /// Off for snapshots: ImageRenderer draws neither scroll views nor navigation stacks.
    var scrolls = true

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

    var body: some View {
        if scrolls {
            NavigationStack { sheet }
        } else {
            content.onAppear { if cardId == nil { cardId = cards.first?.cardId } }
        }
    }

    @ViewBuilder
    private func scrolling<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
        if scrolls { ScrollView { inner() } } else { inner().frame(maxHeight: .infinity, alignment: .top) }
    }

    private var content: some View {
            HStack(alignment: .top, spacing: 0) {
                scrolling {
                    VStack(alignment: .leading, spacing: 12) {
                        if !open { lockedNote }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                            ForEach(cards) { card in
                                AbilityCardTile(card: card, character: character, selected: card.cardId == cardId, width: 130)
                                    .onTapGesture { cardId = card.cardId }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
                Divider().opacity(0.3)
                scrolling {
                    slotsPanel
                        .padding(20)
                }
                .frame(width: 380)
            }
            .background(Color(red: 0.09, green: 0.075, blue: 0.065))
    }

    private var sheet: some View {
            content
            .navigationTitle("The Enhancer — \(name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("\(character.loot) gold", systemImage: "circle.hexagongrid.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(BoardTheme.brass)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(pending.map(confirmTitle) ?? "", isPresented: Binding(
                get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                if let pending, let card = selected {
                    Button("Enhance for \(pending.cost) gold") {
                        enhancer.buy(pending.enhancement, in: pending.slot, card: card, for: character)
                        self.pending = nil
                    }
                    Button("Cancel", role: .cancel) { self.pending = nil }
                }
            } message: {
                Text("An enhancement stays on the card for good.")
            }
            .onAppear { if cardId == nil { cardId = cards.first?.cardId } }
    }

    private var lockedNote: some View {
        Label("The Enhancer opens once the party earns The Power of Enhancement, from Frozen Hollow.",
              systemImage: "lock.fill")
            .font(.body)
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
                    .font(BoardTheme.display(26))
                    .foregroundStyle(BoardTheme.text)
                let count = EnhancementsManager.enhancementCount(on: card.cardId ?? 0, in: character.enhancements)
                Text("Level \(CardPool.level(of: card).map(String.init) ?? "X") · \(count) enhanced · \(character.loot) gold to spend")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
                if count > 0 {
                    Text("Each enhancement already on a card adds \(character.edition == "fh" ? 50 : 75) gold.")
                        .font(.caption)
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                ForEach(CardEnhancing.slots(of: card)) { slot in
                    slotRow(slot, card: card)
                }
            }
        } else {
            Text("Choose a card.")
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
                    .font(.headline)
                    .foregroundStyle(BoardTheme.text)
                Spacer()
                let slotsOnLine = slot.action.enhancementTypes?.count ?? 1
                Text((slot.half == "top" ? "TOP" : "BOTTOM")
                     + (slotsOnLine > 1 ? " · SLOT \(slot.slotIndex + 1) OF \(slotsOnLine)" : ""))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            if let current {
                Label(current.action.displayName, systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BoardTheme.gain)
            } else if options.isEmpty {
                Text("The Enhancer can't do this one yet.")
                    .font(.caption)
                    .foregroundStyle(BoardTheme.secondaryText)
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
                                Text("\(cost)g").foregroundStyle(problem == nil ? BoardTheme.brass : BoardTheme.defeat)
                            }
                            .font(.subheadline.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(BoardTheme.panel, in: Capsule())
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
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
    }

    private func confirmTitle(_ purchase: Purchase) -> String {
        "\(purchase.enhancement.displayName) on \(Self.line(purchase.slot))?"
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
