import SwiftUI

/// The half of an ability card being played this turn, as the card prints it: the top half for
/// the top action, the bottom half for the bottom one. A label above names the card and the half
/// (the clipped card can't show its title on a bottom half). The magnifier opens the whole card.
struct ActiveCardHalf: View {
    let card: AbilityModel
    let isTop: Bool
    let characterColor: Color
    var labelResolver: ((String) -> String?)?
    var onPreview: (() -> Void)?

    static let cardSize = CGSize(width: 140, height: 240)
    /// The part of the card shown: a little over half, so the initiative in the middle shows.
    static let shownFraction: CGFloat = 0.56

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(BoardTheme.font(size: 11, weight: .heavy))
                .foregroundStyle(isTop ? Color.yellow : Color.cyan)
                .lineLimit(1)
            BoardAbilityCardView(card: card, characterColor: characterColor,
                                 highlight: isTop ? .top : .bottom,
                                 width: Self.cardSize.width, height: Self.cardSize.height,
                                 labelResolver: labelResolver, onPreview: onPreview)
                .frame(height: Self.cardSize.height * Self.shownFraction, alignment: isTop ? .top : .bottom)
                .clipped()
        }
        .frame(width: Self.cardSize.width)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isTop ? "Top" : "Bottom") of \(card.name ?? "the card")")
    }

    private var label: String {
        let name = card.name ?? "Card"
        // The top half shows the card's title; the clipped bottom half doesn't, so name it there.
        return isTop ? "TOP · INITIATIVE \(card.initiative)" : "BOTTOM · \(name)".uppercased()
    }
}
