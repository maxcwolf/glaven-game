import SwiftUI

/// The board's visual tokens: surfaces, the brass accent, result colours, radii and type. New
/// board UI takes its look from here rather than from one-off colours and sizes.
enum BoardTheme {
    // Surfaces
    static let panel = Color(red: 0.11, green: 0.09, blue: 0.08).opacity(0.94)
    static let raised = Color(red: 0.17, green: 0.14, blue: 0.11)
    static let scrim = Color.black.opacity(0.72)
    static let border = Color(red: 0.42, green: 0.33, blue: 0.15)

    // Accent and meaning
    /// Brass, the game's accent (#C8922E).
    static let brass = Color(red: 0.784, green: 0.573, blue: 0.180)
    static let victory = Color(red: 0.89, green: 0.70, blue: 0.24)
    static let defeat = Color(red: 0.86, green: 0.33, blue: 0.27)
    static let gain = Color(red: 0.45, green: 0.86, blue: 0.45)

    // Text
    static let text = Color(red: 0.96, green: 0.92, blue: 0.84)
    static let secondaryText = Color.white.opacity(0.72)
    /// No text on the board is smaller than this.
    static let minimumTextSize: CGFloat = 11

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 16
    }

    /// A fixed-size system font for compact board UI, never below `minimumTextSize`.
    static func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: max(size, minimumTextSize), weight: weight, design: design)
    }

    /// Pirata One, for screen titles and big numbers only.
    static func display(_ size: CGFloat) -> Font { GlavenFont.title(size: size) }
}

extension View {
    /// A board panel: the panel surface, a brass-tinted edge and a soft shadow.
    func boardPanel(radius: CGFloat = BoardTheme.Radius.large) -> some View {
        background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(BoardTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }
}
