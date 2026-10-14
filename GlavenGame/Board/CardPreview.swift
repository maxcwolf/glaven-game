import SwiftUI

/// A character's card as large as the screen allows, for reading it, in the players' card style;
/// the turn button beside it shows the card in the other style (the printed scan or the drawn
/// card) while it is open.
struct CardPreview: View {
    @Environment(\.cardStyle) private var style
    let card: AbilityModel
    let character: GameCharacter
    var labelResolver: ((String) -> String?)?
    var onClose: () -> Void

    /// Shown in the other style than the players' own.
    @State private var turned = false

    private var shown: CardStyle { turned ? style.other : style }
    private var canTurn: Bool { AbilityCardFace.hasBothStyles(card, edition: character.edition) }

    /// The card's height: as tall as the space allows with a margin, up to 720 points.
    static func height(in space: CGSize) -> CGFloat {
        max(200, min(720, space.height - 80, (space.width - 160) * AbilityCardFace.aspect))
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 16) {
                face(height: Self.height(in: geo.size))
                if canTurn { turnButton }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func face(height: CGFloat) -> some View {
        AbilityCardFace(card: card, edition: character.edition, color: Color(hex: character.color) ?? .blue,
                        height: height, followsCardSize: false, labelResolver: labelResolver)
            .environment(\.cardStyle, shown)
            .id(shown)
            .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.6)))
            .shadow(color: .black.opacity(0.5), radius: 20)
            .overlay(alignment: .topTrailing) { closeButton }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(card.name ?? "Card")
    }

    /// Turns the card to the other style.
    private var turnButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { turned.toggle() }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(BoardTheme.font(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(BoardTheme.brass.opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 6)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shown == .scans ? "Show the drawn card" : "Show the printed card")
        .help(shown == .scans ? "Show the drawn card" : "Show the printed card")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(BoardTheme.font(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .padding(4)
    }
}
