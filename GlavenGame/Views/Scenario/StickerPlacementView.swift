import SwiftUI

/// Celebratory view showing an overlay sticker being placed on the world map
/// after a scenario is completed. Shows a zoomed-in portion of the map centered
/// on the sticker's coordinates with an animated placement effect.
struct StickerPlacementView: View {
    let overlay: WorldMapOverlay
    let edition: String
    let onDismiss: () -> Void

    @State private var stickerAppeared = false
    @State private var stickerScale: CGFloat = 3.0
    @State private var stickerOpacity: CGFloat = 0.0

    private var mapImage: PlatformImage? {
        ImageLoader.worldMapBase(edition: edition)
    }

    private var stickerImage: PlatformImage? {
        ImageLoader.worldMapOverlay(edition: edition, name: overlay.name)
    }

    private var stickerX: CGFloat { overlay.coordinates.x ?? 0 }
    private var stickerY: CGFloat { overlay.coordinates.y ?? 0 }
    private var stickerW: CGFloat { overlay.coordinates.width ?? 80 }
    private var stickerH: CGFloat { overlay.coordinates.height ?? 80 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Sticker Placed!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.primaryText)
                .padding(.top, 16)

            Text(overlay.location.isEmpty ? overlay.name.replacingOccurrences(of: "-", with: " ").capitalized : overlay.location)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
                .padding(.bottom, 12)

            // Zoomed map with sticker
            GeometryReader { geo in
                mapWithSticker(viewSize: geo.size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .background(GlavenTheme.background)
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 450)
        #endif
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3)) {
                stickerAppeared = true
                stickerScale = 1.0
                stickerOpacity = 1.0
            }
        }
    }

    @ViewBuilder
    private func mapWithSticker(viewSize: CGSize) -> some View {
        let zoom: CGFloat = calculateZoom(viewSize: viewSize)
        let centerX = (stickerX + stickerW / 2)
        let centerY = (stickerY + stickerH / 2)

        ZStack(alignment: .topLeading) {
            // Map background (zoomed into sticker area)
            if let img = mapImage {
                #if os(macOS)
                Image(nsImage: img)
                    .resizable()
                #else
                Image(uiImage: img)
                    .resizable()
                #endif
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }

            // Sticker overlay with animation
            stickerContent
                .frame(width: stickerW * zoom, height: stickerH * zoom)
                .position(
                    x: (stickerX + stickerW / 2) * zoom,
                    y: (stickerY + stickerH / 2) * zoom
                )
                .scaleEffect(stickerScale)
                .opacity(stickerOpacity)
                .shadow(color: .yellow.opacity(stickerAppeared ? 0.6 : 0), radius: 20)
        }
        .frame(
            width: mapWidth * zoom,
            height: mapHeight * zoom
        )
        .offset(
            x: viewSize.width / 2 - centerX * zoom,
            y: viewSize.height / 2 - centerY * zoom
        )
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
            // Fallback: decorative sticker with name
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                    )

                VStack(spacing: 2) {
                    Image(systemName: "seal.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                    Text(overlay.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(4)
            }
        }
    }

    private var mapWidth: CGFloat {
        // Use known GH map dimensions, or fall back to a reasonable default
        2958
    }

    private var mapHeight: CGFloat {
        2410
    }

    private func calculateZoom(viewSize: CGSize) -> CGFloat {
        // Zoom so the sticker area fills about 1/3 of the view
        let targetViewPortion: CGFloat = 3.0
        let zoomX = viewSize.width * targetViewPortion / mapWidth
        let zoomY = viewSize.height * targetViewPortion / mapHeight
        return max(zoomX, zoomY)
    }
}
