import SwiftUI

extension View {
    @ViewBuilder
    func animateIf<V: Equatable>(_ condition: Bool, _ animation: Animation, value: V) -> some View {
        if condition {
            self.animation(animation, value: value)
        } else {
            self
        }
    }
}

enum GlavenTheme {
    /// Toggled from the app root when light mode changes. Views re-render via `.id()`.
    nonisolated(unsafe) static var isLight = false
    /// Active theme name: "default", "fh", "modern", "bb"
    nonisolated(unsafe) static var activeTheme = "default"

    static var isModern: Bool { activeTheme == "modern" }
    static var isFH: Bool { activeTheme == "fh" }
    static var isBB: Bool { activeTheme == "bb" }

    // MARK: - Backgrounds

    static var background: Color {
        if isModern {
            return isLight
                ? Color(red: 0.94, green: 0.94, blue: 0.95)    // neutral light gray
                : Color(red: 0.055, green: 0.122, blue: 0.122) // #0e1f1f
        }
        if isFH {
            return isLight
                ? Color(red: 0.87, green: 0.90, blue: 0.93)    // cool parchment
                : Color(red: 0.10, green: 0.14, blue: 0.20)    // cool dark blue
        }
        if isBB {
            return isLight
                ? Color(red: 0.94, green: 0.94, blue: 0.95)
                : Color(red: 0.055, green: 0.122, blue: 0.122)
        }
        return isLight
            ? Color(red: 0.894, green: 0.855, blue: 0.808)     // warm parchment cream
            : Color(red: 0.145, green: 0.176, blue: 0.208)     // #253038
    }

    static var cardBackground: Color {
        if isModern {
            return isLight
                ? Color(red: 0.98, green: 0.98, blue: 0.98)
                : Color(red: 0.10, green: 0.16, blue: 0.16)
        }
        if isFH {
            return isLight
                ? Color(red: 0.90, green: 0.93, blue: 0.95)
                : Color(red: 0.12, green: 0.16, blue: 0.22)
        }
        if isBB {
            return isLight
                ? Color(red: 0.98, green: 0.98, blue: 0.98)
                : Color(red: 0.10, green: 0.16, blue: 0.16)
        }
        return isLight
            ? Color(red: 0.929, green: 0.902, blue: 0.863)     // slightly lighter warm cream
            : Color(red: 0.16, green: 0.20, blue: 0.24)        // ~#283340
    }

    static var headerFooterBackground: Color {
        if isModern {
            return isLight
                ? Color(red: 0.90, green: 0.90, blue: 0.91)
                : Color(red: 0.04, green: 0.08, blue: 0.08).opacity(0.95)
        }
        if isFH {
            return isLight
                ? Color(red: 0.78, green: 0.82, blue: 0.86)
                : Color.black.opacity(0.85)
        }
        return isLight
            ? Color(red: 0.82, green: 0.78, blue: 0.72)
            : Color.black.opacity(0.85)
    }

    // MARK: - Text

    static var primaryText: Color {
        if isModern {
            return isLight
                ? Color(red: 0.12, green: 0.12, blue: 0.13)
                : .white
        }
        return isLight
            ? Color(red: 0.165, green: 0.133, blue: 0.094)     // warm dark brown
            : .white
    }

    static var secondaryText: Color {
        if isModern {
            return isLight
                ? Color(red: 0.45, green: 0.45, blue: 0.47)
                : Color(red: 0.45, green: 0.45, blue: 0.47)
        }
        if isFH {
            return isLight
                ? Color(red: 0.42, green: 0.48, blue: 0.54)
                : Color(red: 0.55, green: 0.65, blue: 0.75)
        }
        return isLight
            ? Color(red: 0.47, green: 0.44, blue: 0.37)        // warm gray-brown
            : Color(red: 0.596, green: 0.690, blue: 0.710)     // #98b0b5
    }

    static var normalType: Color {
        if isModern {
            return secondaryText
        }
        return isLight
            ? Color(red: 0.42, green: 0.40, blue: 0.35)
            : Color(red: 0.596, green: 0.690, blue: 0.710)     // #98b0b5
    }

    // MARK: - Accents (work on both backgrounds)

    static var accentText: Color {
        if isModern {
            return isLight
                ? Color(red: 0.20, green: 0.50, blue: 0.65)
                : Color(red: 0.40, green: 0.75, blue: 0.90)
        }
        if isFH {
            return isLight
                ? Color(red: 0.30, green: 0.45, blue: 0.58)
                : Color(red: 0.635, green: 0.733, blue: 0.820) // #a2bbd1
        }
        return isLight
            ? Color(red: 0.10, green: 0.46, blue: 0.64)        // deeper blue for light bg
            : Color(red: 0.337, green: 0.784, blue: 0.937)     // light blue
    }

    static let elite = Color(red: 0.925, green: 0.651, blue: 0.063)    // #eca610
    static let boss = Color(red: 0.886, green: 0.259, blue: 0.122)     // #e2421f
    static let positive = Color(red: 0.490, green: 0.659, blue: 0.165) // #7da82a
    static let negative = Color(red: 0.886, green: 0.259, blue: 0.122)

    // MARK: - Phase badges (always on colored bg → white text)

    static let drawPhaseColor = Color(red: 0.490, green: 0.659, blue: 0.165)
    static let nextPhaseColor = Color(red: 0.337, green: 0.784, blue: 0.937)

    /// Display name for a theme
    static func themeName(_ theme: String) -> String {
        switch theme {
        case "fh": return "Frosthaven"
        case "modern": return "Modern"
        case "bb": return "Buttons & Bugs"
        default: return "Gloomhaven"
        }
    }

    /// All available themes
    static let allThemes = ["default", "fh", "modern", "bb"]
}

// MARK: - Edition Theme

/// Edition-specific visual theme providing fonts, colors, and textures.
struct EditionTheme {
    let edition: String

    /// Title font — respects active theme override.
    /// Modern theme always uses system font. FH theme uses GermaniaOne. Default uses PirataOne.
    func titleFont(size: CGFloat) -> Font {
        if GlavenTheme.isModern {
            return .system(size: size, weight: .bold, design: .rounded)
        }
        let effectiveEdition = GlavenTheme.isFH ? "fh" : (GlavenTheme.isBB ? "fh" : edition)
        switch effectiveEdition {
        case "fh": return GlavenFont.fhTitle(size: size)
        default: return GlavenFont.title(size: size)
        }
    }

    /// Accent color — delegates to GlavenTheme which already handles theme variants.
    var accent: Color {
        GlavenTheme.accentText
    }

    /// Card background tint
    var cardTint: Color {
        GlavenTheme.cardBackground
    }

    /// Secondary text color
    var secondaryText: Color {
        GlavenTheme.secondaryText
    }

    static let gh = EditionTheme(edition: "gh")
    static let fh = EditionTheme(edition: "fh")
    static let jotl = EditionTheme(edition: "jotl")

    static func forEdition(_ edition: String?) -> EditionTheme {
        switch edition {
        case "fh": return .fh
        case "jotl": return .jotl
        default: return .gh
        }
    }
}

// MARK: - Environment Key

struct EditionThemeKey: EnvironmentKey {
    static let defaultValue = EditionTheme.gh
}

extension EnvironmentValues {
    var editionTheme: EditionTheme {
        get { self[EditionThemeKey.self] }
        set { self[EditionThemeKey.self] = newValue }
    }
}

/// A parchment background texture view
struct ParchmentBackground: View {
    var edition: String?

    var body: some View {
        if let img = ImageLoader.backgroundTexture(edition: edition) {
            platformImage(img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        } else {
            GlavenTheme.background.ignoresSafeArea()
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
}
