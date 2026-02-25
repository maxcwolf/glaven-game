import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

enum ImageLoader {
    static func characterThumbnail(edition: String, name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/character/thumbnail", filename: "\(edition)-\(name)", ext: "png")
    }

    static func monsterThumbnail(edition: String, name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/monster/thumbnail", filename: "\(edition)-\(name)", ext: "png")
    }

    static func characterIcon(edition: String, name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/character/icons", filename: "\(edition)-\(name)", ext: "svg")
    }

    static func conditionIcon(_ name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/condition", filename: name, ext: "svg")
    }

    static func elementIcon(_ name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/element", filename: name, ext: "svg")
    }

    static func actionIcon(_ name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/action", filename: name, ext: "svg")
    }

    static func statusIcon(_ name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/status", filename: name, ext: "svg")
    }

    static func statsIcon(_ name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/stats", filename: name, ext: "svg")
    }

    static func logo() -> PlatformImage? {
        loadImage(subdirectory: "Images", filename: "glaven-logo", ext: "png")
    }

    // MARK: - World Map

    static func worldMapBase(edition: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/world-map/\(edition)", filename: "map", ext: "jpg")
    }

    static func worldMapScenario(edition: String, index: String, customImage: String? = nil) -> PlatformImage? {
        let filename: String
        if let custom = customImage {
            filename = custom
        } else {
            let numericIndex = index.replacingOccurrences(of: "[a-zA-Z]+", with: "", options: .regularExpression)
            let padded = String(repeating: "0", count: max(0, 3 - numericIndex.count)) + numericIndex
            filename = "\(edition)-\(padded)"
        }
        return loadImage(subdirectory: "Images/world-map/\(edition)/scenarios", filename: filename, ext: "png")
    }

    static func worldMapOverlay(edition: String, name: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/world-map/\(edition)/overlays", filename: "\(edition)-\(name)", ext: "png")
    }

    // MARK: - Textures

    static func backgroundTexture(edition: String?) -> PlatformImage? {
        let name: String
        switch edition {
        case "fh": name = "bg-fh"
        default: name = "bg-gh"
        }
        return loadImage(subdirectory: "Images/textures", filename: name, ext: "jpg")
    }

    static func barTexture() -> PlatformImage? {
        loadImage(subdirectory: "Images/textures", filename: "bar", ext: "jpg")
    }

    // MARK: - Card Images

    static func amCardImage(_ type: String) -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/attackmodifier", filename: type, ext: "png")
    }

    static func amCardBack() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/attackmodifier", filename: "am-back", ext: "png")
    }

    static func monsterAbilityFront() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/monster-ability", filename: "monster-ability-front", ext: "png")
    }

    static func monsterAbilityBack() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/monster-ability", filename: "monster-ability-back", ext: "png")
    }

    static func monsterAbilityRepeat() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/monster-ability", filename: "monster-ability-front-repeat", ext: "png")
    }

    static func monsterAbilityBottom() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/monster-ability", filename: "monster-ability-front-bottom", ext: "png")
    }

    static func itemCardFront() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/items", filename: "item-front", ext: "png")
    }

    static func itemCardBack() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/items", filename: "item-back", ext: "png")
    }

    static func characterMat() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/character", filename: "char-mat", ext: "png")
    }

    static func characterAbilityBack() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/character", filename: "character-ability-back", ext: "png")
    }

    static func battleGoalFront() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/battlegoal", filename: "battle-goal-front", ext: "png")
    }

    static func battleGoalBack() -> PlatformImage? {
        loadImage(subdirectory: "Images/cards/battlegoal", filename: "battle-goal-back", ext: "png")
    }

    /// Returns the GitHub-hosted URL for a monster ability card image.
    /// - Parameters:
    ///   - deckName: The deck identifier (e.g. "guard", "archer"). Falls back to monster name when no explicit deck is set.
    ///   - cardIndex: Zero-based position of the card in the ordered deck array.
    static func monsterAbilityCardURL(deckName: String, cardIndex: Int) -> URL? {
        // Maps GlavenGame deck names to the abbreviated filename component used in
        // gloomhaven-card-browser's image repository (images branch).
        let abbrevs: [String: String] = [
            "ancient-artillery": "aa",
            "archer":            "ar",
            "boss":              "bo",
            "cave-bear":         "cb",
            "cultist":           "cu",
            "deep-terror":       "dt",
            "earth-demon":       "ed",
            "flame-demon":       "fld",
            "frost-demon":       "frd",
            "giant-viper":       "gv",
            "guard":             "gu",
            "harrower-infester": "hi",
            "hound":             "ho",
            "imp":               "im",
            "living-bones":      "lb",
            "living-corpse":     "lc",
            "living-spirit":     "ls",
            "lurker":            "lu",
            "night-demon":       "nd",
            "ooze":              "oo",
            "rending-drake":     "rd",
            "savvas-icestorm":   "si",
            "savvas-lavaflow":   "sl",
            "scout":             "sc",
            "shaman":            "sh",
            "spitting-drake":    "spd",
            "stone-golem":       "sg",
            "sun-demon":         "sud",
            "wind-demon":        "wd",
        ]
        guard let abbrev = abbrevs[deckName] else { return nil }
        let imageNumber = cardIndex + 1   // 1-indexed filenames
        let path = "monster-ability-cards/gloomhaven/\(deckName)/gh-ma-\(abbrev)-\(imageNumber).png"
        let base = "https://raw.githubusercontent.com/cmlenius/gloomhaven-card-browser/images/images/"
        return URL(string: base + path)
    }

    private static func loadImage(subdirectory: String, filename: String, ext: String) -> PlatformImage? {
        // Try PNG first (pre-rendered, reliable), then fall back to original format
        let pngResult: PlatformImage? = {
            if ext != "png", let url = appResourceBundle.url(forResource: filename, withExtension: "png", subdirectory: subdirectory) {
                #if os(macOS)
                return NSImage(contentsOf: url)
                #else
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
                #endif
            }
            return nil
        }()
        if let png = pngResult { return png }

        guard let url = appResourceBundle.url(forResource: filename, withExtension: ext, subdirectory: subdirectory) else {
            return nil
        }
        #if os(macOS)
        return NSImage(contentsOf: url)
        #else
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
        #endif
    }
}

/// A SwiftUI view that loads a bundled image with a fallback.
struct BundledImage: View {
    let image: PlatformImage?
    var size: CGFloat = 24
    var fallbackSystemName: String?
    var fallbackView: AnyView?
    var useTemplate: Bool = false
    @Environment(\.uiScale) private var scale

    init(_ image: PlatformImage?, size: CGFloat = 24, @ViewBuilder fallback: () -> some View) {
        self.image = image
        self.size = size
        self.fallbackView = AnyView(fallback())
    }

    init(_ image: PlatformImage?, size: CGFloat = 24, systemName: String, useTemplate: Bool = false) {
        self.image = image
        self.size = size
        self.fallbackSystemName = systemName
        self.useTemplate = useTemplate
    }

    private var scaledSize: CGFloat { size * scale }

    var body: some View {
        if let img = image {
            #if os(macOS)
            Image(nsImage: img)
                .renderingMode(useTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize, height: scaledSize)
            #else
            Image(uiImage: img)
                .renderingMode(useTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize, height: scaledSize)
            #endif
        } else if let sysName = fallbackSystemName {
            Image(systemName: sysName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize, height: scaledSize)
        } else if let fv = fallbackView {
            fv
        }
    }
}

/// A compact icon + value display matching the Angular app's stat display pattern.
struct GameIcon: View {
    let image: PlatformImage?
    let fallbackSystemName: String
    var size: CGFloat = 12
    var color: Color = .white
    @Environment(\.uiScale) private var scale

    private var scaledSize: CGFloat { size * scale }

    var body: some View {
        if let img = image {
            #if os(macOS)
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize, height: scaledSize)
                .foregroundStyle(color)
            #else
            Image(uiImage: img)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledSize, height: scaledSize)
                .foregroundStyle(color)
            #endif
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: scaledSize * 0.75))
                .foregroundStyle(color)
        }
    }
}

/// Convenience for thumbnail images with rounded clipping.
struct ThumbnailImage: View {
    let image: PlatformImage?
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 8
    var fallbackColor: Color = .gray
    @Environment(\.uiScale) private var scale

    private var scaledSize: CGFloat { size * scale }
    private var scaledRadius: CGFloat { cornerRadius * scale }

    var body: some View {
        if let img = image {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: scaledSize, height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: scaledRadius))
            #else
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: scaledSize, height: scaledSize)
                .clipShape(RoundedRectangle(cornerRadius: scaledRadius))
            #endif
        } else {
            RoundedRectangle(cornerRadius: scaledRadius)
                .fill(fallbackColor)
                .frame(width: scaledSize, height: scaledSize)
        }
    }
}
