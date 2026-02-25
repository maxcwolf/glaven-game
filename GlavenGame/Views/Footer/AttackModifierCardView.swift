import SwiftUI

struct AttackModifierCardView: View {
    let modifier: AttackModifier
    var size: CGFloat = 50

    @Environment(\.uiScale) private var scale

    private var scaledSize: CGFloat { size * scale }

    /// Maps AM type to the PNG filename in cards/attackmodifier/
    private var cardImageName: String {
        switch modifier.type {
        case .plus0: return "plus0"
        case .plus1: return "plus1"
        case .plus2: return "plus2"
        case .plus3: return "plus3"
        case .plus4: return "plus4"
        case .minus1, .minus1extra: return "minus1"
        case .minus2: return "minus2"
        case .double_: return "double"
        case .null_: return "null"
        case .bless: return "bless"
        case .curse: return "curse"
        default: return "plus0"
        }
    }

    var body: some View {
        if let img = ImageLoader.amCardImage(cardImageName) {
            // Real card image
            platformImage(img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
        } else {
            // Fallback: styled text card
            fallbackCard
        }
    }

    @ViewBuilder
    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }

    @ViewBuilder
    private var fallbackCard: some View {
        VStack(spacing: 0) {
            Text(displayText)
                .font(GlavenFont.title(size: 16 * scale))
                .foregroundStyle(textColor)
        }
    }

    private var displayText: String {
        switch modifier.type {
        case .null_: return "Miss"
        case .double_: return "x2"
        case .bless: return "x2"
        case .curse: return "Miss"
        default:
            let v = modifier.value
            if v > 0 { return "+\(v)" }
            if v < 0 { return "\(v)" }
            return "+0"
        }
    }

    private var textColor: Color {
        switch modifier.type {
        case .null_, .curse: return .red
        case .double_, .bless: return .green
        case .plus1, .plus2, .plus3, .plus4: return .blue
        case .minus1, .minus2: return .red
        default: return .primary
        }
    }
}

/// A card-back view for face-down AM cards
struct AttackModifierCardBack: View {
    var size: CGFloat = 50

    @Environment(\.uiScale) private var scale
    private var scaledSize: CGFloat { size * scale }

    var body: some View {
        if let img = ImageLoader.amCardBack() {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
            #else
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
            #endif
        } else {
            RoundedRectangle(cornerRadius: 3 * scale)
                .fill(Color(red: 0.3, green: 0.2, blue: 0.1))
                .frame(width: scaledSize * 0.7, height: scaledSize)
                .overlay(
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}
