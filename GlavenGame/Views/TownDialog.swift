import SwiftUI

/// A large dialog over the dimmed town, in the board's look: a header with a title, a note
/// under it and Done, and the content below. It takes most of the screen, so a character sheet
/// or the shop reads as a page rather than a small form.
struct TownDialog<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    /// A character's portrait beside the title, ringed in their class colour.
    var portrait: (image: PlatformImage?, color: Color)? = nil
    /// The most room it takes; nil for nearly the whole screen. Small dialogs (table rules,
    /// credits) stay small.
    var size: CGSize? = nil
    /// "Done", or "Cancel" beside a separate confirm in `trailing`.
    var doneTitle = "Done"
    var doneDisabled = false
    /// Done in brass, or quiet when the dialog's choices are its own buttons (a quest picker's Later).
    var doneProminent = true
    /// What tapping outside does, when that isn't Done (it puts changes aside rather than saving them).
    var onCancel: (() -> Void)? = nil
    let onDone: () -> Void
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                BoardTheme.scrim.ignoresSafeArea()
                    .onTapGesture { (onCancel ?? onDone)() }
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    header
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(width: min(geo.size.width - 64, size?.width ?? 1240),
                       height: max(320, min(geo.size.height - 48, size?.height ?? .infinity)))
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
            Button(doneTitle, action: onDone)
                .buttonStyle(doneProminent ? .boardPrimary : .boardQuiet)
                .keyboardShortcut(.defaultAction)
                .disabled(doneDisabled)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(BoardTheme.border.opacity(0.4)).frame(height: 1) }
    }
}

extension TownDialog where Trailing == EmptyView {
    init(title: String, subtitle: String, size: CGSize? = nil, onDone: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, size: size, onDone: onDone, trailing: { EmptyView() }, content: content)
    }
}

/// Named choices in a capsule, the chosen one in brass.
struct TownSegmented<Value: Hashable>: View {
    let choices: [(value: Value, name: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices, id: \.value) { choice in
                let isSelected = choice.value == selection
                Button { selection = choice.value } label: {
                    Text(choice.name)
                        .font(BoardTheme.font(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.text)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? BoardTheme.brass : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(BoardTheme.raised, in: Capsule())
    }
}

/// A brass switch, labelled for accessibility.
struct TownSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? BoardTheme.brass : BoardTheme.raised)
                .frame(width: 46, height: 28)
                .overlay(Capsule().stroke(BoardTheme.border.opacity(isOn ? 0 : 0.6), lineWidth: 1))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(BoardTheme.text).frame(width: 22).padding(3)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
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
