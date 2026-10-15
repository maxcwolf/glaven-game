import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The app's icon (Settings → Look): the crest, or one of the other designs. Their art is drawn in
/// `docs/app-icons/*.svg` and rendered by `scripts/app-icons/render.py` into the asset catalog
/// (the iPadOS icons) and `Resources/Images/app-icons` (the picker and the Mac's Dock).
enum AppIconChoice: String, CaseIterable, Identifiable {
    case crest
    case hexBlade = "hex-blade"
    case spectacles
    case critical
    case elements

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crest: return "Crest"
        case .hexBlade: return "Hex & Blade"
        case .spectacles: return "Spectacles"
        case .critical: return "Critical"
        case .elements: return "Elements"
        }
    }

    /// The alternate icon set in the asset catalog, named in project.yml's
    /// ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES; nil for the primary icon, the crest.
    var alternateIconName: String? {
        switch self {
        case .crest: return nil
        case .hexBlade: return "AppIcon-HexBlade"
        case .spectacles: return "AppIcon-Spectacles"
        case .critical: return "AppIcon-Critical"
        case .elements: return "AppIcon-Elements"
        }
    }

    /// The art, full-bleed (the picker's thumbnail), or shaped as a macOS icon (the Dock's).
    func image(shaped: Bool = false) -> PlatformImage? {
        ImageLoader.appIcon(rawValue + (shaped ? "-mac" : ""))
    }
}

enum AppIcon {
    /// Shows the chosen icon. iPadOS keeps it, on the Home Screen, and tells the player it changed;
    /// a Mac shows it in the Dock while the game runs, so it's set again at every launch.
    @MainActor
    static func apply(_ choice: AppIconChoice) {
        #if os(macOS)
        NSApplication.shared.applicationIconImage = choice.image(shaped: true)
        #else
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != choice.alternateIconName else { return }
        app.setAlternateIconName(choice.alternateIconName) { error in
            if let error { print("App icon not changed to \(choice.label): \(error.localizedDescription)") }
        }
        #endif
    }
}
