import SwiftUI

/// The main menu's backdrop: the Gloomhaven world map, close in and drifting slowly across the
/// land, darkened at the edges so the menu reads over it. Still under Reduce Motion.
struct MenuKeyArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    /// How far the camera wanders, as a fraction of the screen.
    static let driftFraction: CGFloat = 0.06
    static let driftDuration: Double = 45

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let map = ImageLoader.worldMapBase(edition: "gh") {
                    mapImage(map)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.45)
                        .offset(x: drift ? -geo.size.width * Self.driftFraction : geo.size.width * Self.driftFraction,
                                y: drift ? geo.size.height * Self.driftFraction * 0.6 : -geo.size.height * Self.driftFraction * 0.6)
                        .clipped()
                } else {
                    Color(red: 0.12, green: 0.1, blue: 0.09)
                }
                // Darken it so the title and buttons read: a shade over everything, a deeper one
                // behind the menu in the middle, and a vignette at the edges.
                Color.black.opacity(0.5)
                RadialGradient(colors: [.black.opacity(0.55), .clear], center: .center,
                               startRadius: 0, endRadius: min(geo.size.width, geo.size.height) * 0.45)
                RadialGradient(colors: [.clear, .black.opacity(0.85)], center: .center,
                               startRadius: min(geo.size.width, geo.size.height) * 0.35,
                               endRadius: max(geo.size.width, geo.size.height) * 0.75)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Self.driftDuration).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    @ViewBuilder
    private func mapImage(_ image: PlatformImage) -> some View {
        #if os(macOS)
        Image(nsImage: image).resizable()
        #else
        Image(uiImage: image).resizable()
        #endif
    }
}
