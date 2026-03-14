import SwiftUI

/// Renders a visual overlay sticker on the world map at its defined coordinates.
/// Stickers are placed as scenario completion rewards and persist across the campaign.
struct OverlayStickerView: View {
    let overlay: WorldMapOverlay
    let edition: String
    let zoom: CGFloat

    private var coords: WorldMapCoordinates { overlay.coordinates }

    private var stickerImage: PlatformImage? {
        ImageLoader.worldMapOverlay(edition: edition, name: overlay.name)
    }

    var body: some View {
        stickerContent
            .frame(
                width: (coords.width ?? 60) * zoom,
                height: (coords.height ?? 60) * zoom
            )
            .position(
                x: ((coords.x ?? 0) + (coords.width ?? 60) / 2) * zoom,
                y: ((coords.y ?? 0) + (coords.height ?? 60) / 2) * zoom
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stickerContent: some View {
        if let img = stickerImage {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #else
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
            #endif
        } else {
            // Fallback: show sticker name as a label when image is not available
            Text(overlay.name)
                .font(.system(size: max(6, 8 * zoom), weight: .bold))
                .foregroundStyle(.white)
                .padding(2 * zoom)
                .background(
                    RoundedRectangle(cornerRadius: 3 * zoom)
                        .fill(Color.orange.opacity(0.8))
                )
        }
    }
}
