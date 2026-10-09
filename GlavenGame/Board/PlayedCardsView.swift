import SwiftUI

/// The two cards a character plays this turn, as the real cards: the card giving the top half
/// with its bottom dimmed, the card giving the bottom half with its top dimmed, and the half
/// being performed ringed in brass. Tapping a card shows it full size.
struct PlayedCardsView: View {
    let turn: PlayerTurnController
    let edition: String
    var characterColor: Color = BoardTheme.brass
    var labelResolver: ((String) -> String?)?
    var onPreview: (AbilityModel) -> Void = { _ in }

    static let cardHeight: CGFloat = 150

    var body: some View {
        HStack(spacing: 8) {
            if let top = turn.topCard {
                card(top, half: .top, active: turn.phase == .executeTopAction)
            }
            if let bottom = turn.bottomCard {
                card(bottom, half: .bottom, active: turn.phase == .executeBottomAction)
            }
        }
    }

    enum Half { case top, bottom }

    private func card(_ card: AbilityModel, half: Half, active: Bool) -> some View {
        Button {
            onPreview(card)
        } label: {
            lit(card, half: half, active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.name ?? "Card"), \(half == .top ? "top" : "bottom") half\(active ? ", being performed" : "")")
        .accessibilityHint("Shows the card full size")
    }

    /// The card with the half it doesn't give dimmed, and the half being performed ringed.
    private func lit(_ card: AbilityModel, half: Half, active: Bool) -> some View {
        face(card)
            .frame(height: Self.cardHeight)
            .overlay {
                // The half this card doesn't give is dimmed; so is all of it once the turn is done.
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Rectangle().fill(.black.opacity(dimsTop(half) ? 0.62 : 0))
                        Rectangle().fill(.black.opacity(dimsBottom(half) ? 0.62 : 0))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if active {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(BoardTheme.brass, lineWidth: 2.5)
                            .frame(height: geo.size.height / 2 + 2)
                            .offset(y: half == .top ? -1 : geo.size.height / 2 - 1)
                    }
                }
            }
    }

    private var done: Bool { turn.phase == .turnComplete }
    private func dimsTop(_ half: Half) -> Bool { done || half == .bottom }
    private func dimsBottom(_ half: Half) -> Bool { done || half == .top }

    @ViewBuilder
    private func face(_ card: AbilityModel) -> some View {
        if let id = card.cardId, let image = ImageLoader.abilityCardImage(edition: edition, cardId: id) {
            #if os(macOS)
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            #endif
        } else {
            BoardAbilityCardView(card: card, characterColor: characterColor, highlight: .none,
                                 width: 100, height: Self.cardHeight, labelResolver: labelResolver)
        }
    }
}

/// The turn's quieter choices: swap the cards and pick which half goes first (before acting),
/// the basic action, and skipping the rest of the half. They wrap rather than run out of the
/// panel when it's narrow.
struct TurnChoiceButtons: View {
    let turn: PlayerTurnController

    var body: some View {
        FlowLayout(spacing: 8) {
            if !turn.hasActed {
                // Either card may provide the top half, and either half may go first.
                Button("Swap Cards") { turn.swapCards() }
                    .help("Use the other card's top half and this card's bottom half")
                Button(turn.bottomFirst ? "Top First" : "Bottom First") {
                    turn.setBottomFirst(!turn.bottomFirst)
                }
                .accessibilityValue(turn.bottomFirst ? "Bottom half first" : "Top half first")
            }
            if turn.canUseDefaultAction {
                Button(turn.defaultActionTitle) { turn.useDefaultAction() }
            }
            Button("Skip Rest of Half") { turn.skipRemainingActions() }
        }
        .buttonStyle(.boardQuietCompact)
    }
}
