import SwiftUI

/// How a character's ability cards are shown (Settings → Cards).
enum CardStyle: String, CaseIterable {
    /// The printed cards, scanned: the way the game is played.
    case scans
    /// The app's own drawing of each card: its text plainer, easier to read at a glance.
    case drawn

    var label: String {
        switch self {
        case .scans: return "Card Scans"
        case .drawn: return "Drawn Cards"
        }
    }
}

private struct CardStyleKey: EnvironmentKey {
    static let defaultValue: CardStyle = .scans
}

private struct CardScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// The players' card style, set from the settings at the root of the app.
    var cardStyle: CardStyle {
        get { self[CardStyleKey.self] }
        set { self[CardStyleKey.self] = newValue }
    }

    /// The players' card size (1 = as designed), set from the settings at the root of the app.
    var cardScale: CGFloat {
        get { self[CardScaleKey.self] }
        set { self[CardScaleKey.self] = newValue }
    }
}

/// A character's ability card as the players chose to see it: the scan, or the drawn card (also
/// wherever there's no scan). Every place a character's card is shown draws it through this, so
/// the style and the size take effect everywhere at once, mid-scenario too.
struct AbilityCardFace: View {
    @Environment(\.cardStyle) private var style
    @Environment(\.cardScale) private var scale

    let card: AbilityModel
    let edition: String
    var color: Color = .blue
    /// The card's height at the default card size.
    let height: CGFloat
    /// Grown or shrunk by the players' card size; off where the card is already sized to fit
    /// (town's card grids, the full-size preview).
    var followsCardSize = true
    var labelResolver: ((String) -> String?)?
    /// Room kept clear in the drawn card's top-right corner for a button laid over it.
    var cornerInset: CGFloat = 0

    /// Width to height of a card (the scans are 400 × 600).
    static let aspect: CGFloat = 1.5

    /// The card's size at `height` and the players' card size.
    static func size(height: CGFloat, scale: CGFloat) -> CGSize {
        let tall = height * scale
        return CGSize(width: (tall / aspect).rounded(), height: tall.rounded())
    }

    /// The scan to show, or nil for the drawn card. A card the data doesn't have whole shows its
    /// scan in either style.
    static func scan(of card: AbilityModel, edition: String, style: CardStyle) -> PlatformImage? {
        guard style == .scans || CardText.isUnwritten(card), let id = card.cardId else { return nil }
        return ImageLoader.abilityCardImage(edition: edition, cardId: id)
    }

    var body: some View {
        let size = Self.size(height: height, scale: followsCardSize ? scale : 1)
        Group {
            if let image = Self.scan(of: card, edition: edition, style: style) {
                #if os(macOS)
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                #endif
            } else {
                BoardAbilityCardView(card: card, characterColor: color, highlight: .none,
                                     width: size.width, height: size.height, labelResolver: labelResolver,
                                     cornerInset: cornerInset)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
