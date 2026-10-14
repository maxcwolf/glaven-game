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
                        // The drift animates the offset alone: started with withAnimation it took
                        // every change of its update with it, the macOS window growing to fill the
                        // screen included, so the menu crept from a corner to full size over 45 s.
                        .animation(driftAnimation) { $0.offset(Self.driftOffset(in: geo.size, drifted: drift)) }
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
            drift = true
        }
    }

    /// The camera's slow wander, back and forth (none when motion is reduced).
    private var driftAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Self.driftDuration).repeatForever(autoreverses: true)
    }

    /// Where the map sits at either end of its wander.
    static func driftOffset(in size: CGSize, drifted: Bool) -> CGSize {
        let x = size.width * driftFraction
        let y = size.height * driftFraction * 0.6
        return drifted ? CGSize(width: -x, height: y) : CGSize(width: x, height: -y)
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
