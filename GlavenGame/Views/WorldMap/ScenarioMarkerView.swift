import SwiftUI

struct ScenarioMarkerView: View {
    let scenario: ScenarioData
    let zoom: CGFloat
    let isCompleted: Bool
    let isAvailable: Bool
    let isBlocked: Bool
    let isLocked: Bool
    let onTap: () -> Void

    private var coords: WorldMapCoordinates { scenario.coordinates! }

    private var tileImage: PlatformImage? {
        ImageLoader.worldMapScenario(
            edition: scenario.edition,
            index: scenario.index,
            customImage: coords.image
        )
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                tileImageView
                    .modifier(ScenarioStateModifier(
                        isCompleted: isCompleted,
                        isAvailable: isAvailable,
                        isBlocked: isBlocked,
                        isLocked: isLocked
                    ))

                // Index label — always white-on-dark since it sits on the tile image
                Text("#\(scenario.index)")
                    .font(.system(size: max(8, 10 * zoom), weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .padding(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .buttonStyle(.plain)
        .frame(
            width: (coords.width ?? 0) * zoom,
            height: (coords.height ?? 0) * zoom
        )
        .position(
            x: ((coords.x ?? 0) + (coords.width ?? 0) / 2) * zoom,
            y: ((coords.y ?? 0) + (coords.height ?? 0) / 2) * zoom
        )
    }

    @ViewBuilder
    private var tileImageView: some View {
        if let img = tileImage {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #else
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
            #endif
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(GlavenTheme.secondaryText.opacity(0.3))
                .overlay {
                    Text(scenario.index)
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
        }
    }
}

// MARK: - State Visual Modifier

private struct ScenarioStateModifier: ViewModifier {
    let isCompleted: Bool
    let isAvailable: Bool
    let isBlocked: Bool
    let isLocked: Bool

    func body(content: Content) -> some View {
        if isCompleted {
            content
                .saturation(0.6)
                .opacity(0.7)
        } else if isBlocked {
            content
                .colorMultiply(.red)
                .opacity(0.5)
        } else if isLocked {
            content
                .saturation(0.0)
                .opacity(0.4)
        } else {
            content
        }
    }
}
