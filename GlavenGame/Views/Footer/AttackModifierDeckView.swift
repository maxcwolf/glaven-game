import SwiftUI

struct AttackModifierDeckView: View {
    let label: String
    @Binding var deck: AttackModifierDeck
    let onDraw: () -> AttackModifier?
    let onShuffle: () -> Void

    @Environment(\.uiScale) private var scale
    @State private var lastDrawn: AttackModifier?
    @State private var showDeckDialog = false
    @State private var isFlipped = false
    @State private var flipID = 0
    @State private var showFullscreen = false

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)

            Button {
                SoundPlayer.play(.cardFlip)
                // Reset flip, draw card, then flip
                isFlipped = false
                flipID += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    lastDrawn = onDraw()
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isFlipped = true
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    ZStack {
                        // Card back (face down)
                        AttackModifierCardBack(size: 44)
                            .opacity(isFlipped && lastDrawn != nil ? 0 : 1)
                            .rotation3DEffect(
                                .degrees(isFlipped && lastDrawn != nil ? 180 : 0),
                                axis: (x: 0, y: 1, z: 0)
                            )

                        // Card front (drawn card)
                        if let card = lastDrawn ?? deck.currentCard {
                            AttackModifierCardView(modifier: card, size: 44)
                                .opacity(isFlipped || lastDrawn == nil ? 1 : 0)
                                .rotation3DEffect(
                                    .degrees(isFlipped || deck.currentCard != nil && lastDrawn == nil ? 0 : -180),
                                    axis: (x: 0, y: 1, z: 0)
                                )
                                .onTapGesture {
                                    showFullscreen = true
                                }
                        }
                    }
                    .id(flipID)

                    Text("\(deck.remainingCount)")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .onLongPressGesture {
                showDeckDialog = true
            }
        }
        .sheet(isPresented: $showDeckDialog) {
            AttackModifierDeckDialog(
                label: label,
                deck: $deck,
                shuffleAction: onShuffle
            )
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            if let card = lastDrawn ?? deck.currentCard {
                FullscreenCardView(content: .attackModifier(card))
            }
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            if let card = lastDrawn ?? deck.currentCard {
                FullscreenCardView(content: .attackModifier(card))
                    .frame(minWidth: 500, minHeight: 500)
            }
        }
        #endif
    }
}
