import SwiftUI

/// A map tile placed on the board: which tile, where its anchor hex sits, and how far it's turned.
struct UniqueTile: Identifiable {
    let id: String
    let ref: String
    let anchorCol: Int
    let anchorRow: Int
    let turns: Int
}

// MARK: - Image Cache

/// Caches loaded CGImages to avoid repeated disk I/O on every render pass.
final class MapImageCache {
    static let shared = MapImageCache()
    /// Decoded map tiles. A scenario uses a handful of the ~80 tiles (about 1 MB each decoded),
    /// so the cache is bounded rather than keeping every tile seen over a campaign.
    private let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    private init() {}

    func image(named name: String) -> CGImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }

        guard let url = appResourceBundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Images"
        ) else { return nil }

        let loaded: CGImage?
        #if canImport(AppKit)
        if let nsImage = NSImage(contentsOf: url) {
            loaded = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            loaded = nil
        }
        #else
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            loaded = uiImage.cgImage
        } else {
            loaded = nil
        }
        #endif

        if let img = loaded {
            cache.setObject(img, forKey: name as NSString, cost: img.bytesPerRow * img.height)
        }
        return loaded
    }
}
