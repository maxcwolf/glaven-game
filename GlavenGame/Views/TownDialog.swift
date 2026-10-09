import SwiftUI

/// A large dialog over the dimmed town, in the board's look: a header with a title, a note
/// under it and Done, and the content below. It takes most of the screen, so a character sheet
/// or the shop reads as a page rather than a small form.
struct TownDialog<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    /// A character's portrait beside the title, ringed in their class colour.
    var portrait: (image: PlatformImage?, color: Color)? = nil
    let onDone: () -> Void
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BoardTheme.scrim.ignoresSafeArea()
                    .onTapGesture(perform: onDone)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    header
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(width: min(geo.size.width - 64, 1240), height: max(320, geo.size.height - 48))
                .background(BoardTheme.sheet, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(BoardTheme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 30, y: 10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let portrait {
                Group {
                    if let image = portrait.image {
                        #if os(macOS)
                        Image(nsImage: image).resizable().scaledToFill()
                        #else
                        Image(uiImage: image).resizable().scaledToFill()
                        #endif
                    } else {
                        portrait.color.opacity(0.4)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().stroke(portrait.color, lineWidth: 2.5))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BoardTheme.display(30))
                    .foregroundStyle(BoardTheme.text)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(BoardTheme.font(size: 13, weight: .medium))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
            Button("Done", action: onDone)
                .buttonStyle(.boardPrimary)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(BoardTheme.border.opacity(0.4)).frame(height: 1) }
    }
}

/// A titled section in a town dialog: "Perks · 1 TO TAKE".
struct TownSection<Content: View>: View {
    var title: String?
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(BoardTheme.display(21))
                        .foregroundStyle(BoardTheme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    if let detail {
                        Text(detail.uppercased())
                            .font(BoardTheme.font(size: 11, weight: .bold))
                            .kerning(1.1)
                            .foregroundStyle(BoardTheme.brass)
                            .lineLimit(1)
                    }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }
}

/// A brass check box, ticked or not.
struct TownCheckBox: View {
    let ticked: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(ticked ? BoardTheme.brass : Color.clear)
            .frame(width: 16, height: 16)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ticked ? BoardTheme.brass : BoardTheme.border, lineWidth: 1.5))
            .overlay {
                if ticked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(BoardTheme.sheet)
                }
            }
    }
}

/// An amount of gold: a coin and the number, in gold.
struct TownGold: View {
    let amount: Int
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(BoardTheme.victory)
                .frame(width: size, height: size)
                .overlay(Text("$").font(BoardTheme.font(size: 11, weight: .heavy)).foregroundStyle(BoardTheme.sheet))
            Text("\(amount)")
                .font(BoardTheme.font(size: size + 2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(BoardTheme.victory)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) gold")
    }
}
