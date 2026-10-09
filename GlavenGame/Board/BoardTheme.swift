import SwiftUI

/// The board's visual tokens: surfaces, the brass accent, result colours, radii and type. New
/// board UI takes its look from here rather than from one-off colours and sizes.
enum BoardTheme {
    // Surfaces
    static let panel = Color(red: 0.11, green: 0.09, blue: 0.08).opacity(0.94)
    static let raised = Color(red: 0.17, green: 0.14, blue: 0.11)
    /// Behind full-screen sheets and menus.
    static let sheet = Color(red: 0.09, green: 0.075, blue: 0.065)
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

    /// A side-column card (party, monsters, log): the panel surface with a faint brass edge.
    func sidePanelStyle() -> some View {
        background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border.opacity(0.35), lineWidth: 1))
    }
}

/// The board's two button looks: brass for the one thing to do next, quiet for the rest.
struct BoardButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet }
    var kind: Kind = .quiet
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1)
            .fixedSize()   // a button's words never wrap
            .font(BoardTheme.font(size: compact ? 13 : 15, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(kind == .primary ? BoardTheme.sheet : BoardTheme.text)
            .padding(.horizontal, compact ? 12 : 16)
            .frame(minHeight: compact ? 36 : 44)
            .background(kind == .primary ? BoardTheme.brass : BoardTheme.raised, in: Capsule())
            .overlay(Capsule().stroke(kind == .primary ? .clear : BoardTheme.border.opacity(0.6), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == BoardButtonStyle {
    /// The next thing to do: brass.
    static var boardPrimary: BoardButtonStyle { BoardButtonStyle(kind: .primary) }
    /// Everything else: quiet.
    static var boardQuiet: BoardButtonStyle { BoardButtonStyle(kind: .quiet) }
    static var boardQuietCompact: BoardButtonStyle { BoardButtonStyle(kind: .quiet, compact: true) }
    /// The next thing to do, in a row of small buttons.
    static var boardPrimaryCompact: BoardButtonStyle { BoardButtonStyle(kind: .primary, compact: true) }
}
