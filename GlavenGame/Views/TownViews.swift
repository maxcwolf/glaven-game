import SwiftUI

/// A panel in town, in the board's look.
struct TownPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }
}

/// "Party · 2 OF 4": a panel's title, and a brass note on the right.
struct TownPanelHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail)
                    .font(BoardTheme.font(size: 12, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(BoardTheme.brass)
            }
        }
    }
}

/// A small label in capitals over a group ("MONSTERS", "RECRUIT").
struct TownSmallCaps: View {
    let text: String
    var lit = false

    var body: some View {
        Text(text.uppercased())
            .font(BoardTheme.font(size: 11, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(lit ? BoardTheme.brass : BoardTheme.secondaryText)
    }
}

/// The town's standing in the top bar: "Prosperity 2".
struct TownChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(BoardTheme.font(size: 13, weight: .semibold))
            .foregroundStyle(BoardTheme.text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(BoardTheme.raised, in: Capsule())
            .overlay(Capsule().stroke(BoardTheme.border.opacity(0.6), lineWidth: 1))
            .fixedSize()
    }
}

/// The world map around a scenario's spot, with its sticker: where the party is headed.
struct ScenarioBanner: View {
    let scenario: ScenarioData
    let edition: String
    var height: CGFloat = 180

    /// The part of the map shown, in its pixels.
    static let cropSize = CGSize(width: 1040, height: 380)

    var body: some View {
        if let coords = scenario.coordinates, let x = coords.x, let y = coords.y,
           let map = ImageLoader.worldMapCrop(edition: edition,
                                              around: CGRect(x: x, y: y, width: coords.width ?? 0, height: coords.height ?? 0),
                                              size: Self.cropSize) {
            ZStack {
                picture(map).resizable().aspectRatio(contentMode: .fill)
                if let sticker = ImageLoader.worldMapScenario(edition: edition, index: scenario.index, customImage: coords.image) {
                    picture(sticker).resizable().scaledToFit()
                        .frame(height: height * 0.55)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, BoardTheme.panel], startPoint: .top, endPoint: .bottom).frame(height: 60)
            }
            .clipShape(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Where \(scenario.name) is on the world map")
        }
    }

    private func picture(_ image: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }
}
