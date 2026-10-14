import SwiftUI

/// Which half of the card to highlight, if any.
enum CardHighlight {
    case none
    case top       // Using top actions (dims bottom)
    case bottom    // Using bottom actions (dims top)
}

/// An ability card drawn by the app (the "Drawn Cards" style, and wherever there's no scan): the
/// initiative, the name, and each half as `CardText` lines — every ability with everything printed
/// under it — in plain type that shrinks to fit the half.
struct BoardAbilityCardView: View {
    let card: AbilityModel
    let characterColor: Color
    let highlight: CardHighlight
    let width: CGFloat
    let height: CGFloat

    /// Optional role badge text (e.g. "TOP — Init 79", "BOTTOM").
    var roleBadge: String?
    var roleBadgeColor: Color = .yellow

    /// Resolves `%data.custom...%` placeholder strings to human-readable text.
    var labelResolver: ((String) -> String?)?

    /// Callback to show the full-size card image preview. Nil hides the magnifying glass.
    var onPreview: (() -> Void)?

    init(
        card: AbilityModel,
        characterColor: Color = .blue,
        highlight: CardHighlight = .none,
        width: CGFloat = 130,
        height: CGFloat = 220,
        roleBadge: String? = nil,
        roleBadgeColor: Color = .yellow,
        labelResolver: ((String) -> String?)? = nil,
        onPreview: (() -> Void)? = nil
    ) {
        self.card = card
        self.characterColor = characterColor
        self.highlight = highlight
        self.width = width
        self.height = height
        self.roleBadge = roleBadge
        self.roleBadgeColor = roleBadgeColor
        self.labelResolver = labelResolver
        self.onPreview = onPreview
    }

    var body: some View {
        VStack(spacing: 0) {
            // ─── Role badge ───
            if let badge = roleBadge {
                HStack(spacing: 4) {
                    if roleBadgeColor == .yellow {
                        Image(systemName: "star.fill")
                            .font(BoardTheme.font(size: 11))
                    }
                    Text(badge)
                        .font(BoardTheme.font(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(roleBadgeColor)
                .frame(maxWidth: .infinity)
                // Clear of the preview button in the corner.
                .padding(.trailing, onPreview != nil ? scaled(18) : 0)
                .padding(.vertical, 3)
                .background(roleBadgeColor.opacity(0.15))
            }

            // ─── Initiative, name, level ───
            HStack(alignment: .center, spacing: scaled(6)) {
                Text("\(card.initiative)")
                    .font(.system(size: scaled(22), weight: .heavy, design: .monospaced))
                    .foregroundStyle(highlight == .top ? .yellow : .white)
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.name ?? "Card \(card.cardId ?? 0)")
                        .font(.system(size: scaled(11), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Level \(CardPool.level(of: card).map(String.init) ?? "X")")
                        .font(.system(size: scaled(8), weight: .semibold))
                        .foregroundStyle(characterColor.opacity(0.9))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, scaled(8))
            .padding(.trailing, onPreview != nil ? scaled(18) : scaled(8))
            .padding(.vertical, scaled(4))
            .background(characterColor.opacity(0.18))

            // The two halves share what's left evenly, as on the card.
            GeometryReader { geo in
                let each = max(0, (geo.size.height - 1.5) / 2)
                VStack(spacing: 0) {
                    half(card.actions, lost: card.lost == true)
                        .frame(height: each)
                        .opacity(highlight == .bottom ? 0.35 : 1.0)
                    Rectangle()
                        .fill(characterColor.opacity(0.6))
                        .frame(height: 1.5)
                    half(card.bottomActions, lost: card.bottomLost == true)
                        .frame(height: each)
                        .background(characterColor.opacity(0.08))
                        .opacity(highlight == .top ? 0.35 : 1.0)
                }
            }
        }
        .frame(width: width, height: height)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: highlight != .none ? 2.5 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if let onPreview {
                Button {
                    onPreview()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: scaled(10), weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(4)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Show the card full size")
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            onPreview?()
        }
    }

    private var borderColor: Color {
        switch highlight {
        case .top: return .yellow
        case .bottom: return .cyan
        case .none: return .white.opacity(0.12)
        }
    }

    /// A size at the card's width (the design is 130 points wide).
    private func scaled(_ base: CGFloat) -> CGFloat { base * width / 130 }

    // MARK: - A half

    /// The text shrinks, a step at a time, until the half's lines fit its height.
    private static let fits: [CGFloat] = [1, 0.9, 0.8, 0.7, 0.6, 0.5]

    private func half(_ actions: [ActionModel]?, lost: Bool) -> some View {
        let lines = CardText.lines(of: actions) { labelResolver?($0) }.lines
        return ViewThatFits(in: .vertical) {
            ForEach(Self.fits, id: \.self) { fit in
                halfLines(lines, lost: lost, fit: fit)
            }
            halfLines(lines, lost: lost, fit: 0.45)   // the last resort, clipped
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func halfLines(_ lines: [CardLine], lost: Bool, fit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(2.5) * fit) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line, fit: fit)
                    .padding(.leading, CGFloat(line.depth) * scaled(9) * fit)
            }
            if lost { lostBadge(fit: fit) }
        }
        .padding(.horizontal, scaled(7))
        .padding(.vertical, scaled(5) * fit)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: CardLine, fit: CGFloat) -> some View {
        let size = { (base: CGFloat) in scaled(base) * fit }
        switch line.kind {
        case .ability:
            HStack(alignment: .firstTextBaseline, spacing: size(3)) {
                if let icon = line.icon {
                    actionIconView(icon, value: line.iconValue, size: size(11))
                        .frame(width: size(12))
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + size(4) }
                }
                Text(line.text)
                    .font(.system(size: size(11.5), weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .detail:
            Text(line.text)
                .font(.system(size: size(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        case .note:
            Text(line.text)
                .font(.system(size: size(10)))
                .italic()
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        case .badge:
            Text(line.text)
                .font(.system(size: size(8.5), weight: .bold))
                .foregroundStyle(BoardTheme.brass)
                .padding(.horizontal, size(5))
                .padding(.vertical, size(1.5))
                .background(BoardTheme.brass.opacity(0.15), in: Capsule())
                .fixedSize(horizontal: false, vertical: true)
        case .area(let pattern):
            AreaPatternView(pattern: pattern, radius: size(7))
                .padding(.vertical, size(1))
        }
    }

    private func lostBadge(fit: CGFloat) -> some View {
        Text("LOST")
            .font(.system(size: scaled(8.5) * fit, weight: .heavy))
            .foregroundStyle(.red)
            .padding(.horizontal, scaled(5) * fit)
            .padding(.vertical, scaled(1.5) * fit)
            .background(.red.opacity(0.18), in: Capsule())
            .accessibilityLabel("Lost when performed")
    }

    // MARK: - Icons

    @ViewBuilder
    private func actionIconView(_ type: ActionType, value: String? = nil, size: CGFloat) -> some View {
        if type == .condition, let name = value {
            BundledImage(ImageLoader.conditionIcon(name), size: size, systemName: "exclamationmark.triangle.fill")
        } else if type == .element, let name = value {
            BundledImage(ImageLoader.elementIcon(name), size: size, systemName: "flame.fill")
        } else {
            BundledImage(ImageLoader.actionIcon(type.rawValue), size: size, systemName: fallbackIconName(for: type), useTemplate: true)
                .foregroundStyle(colorForAction(type))
        }
    }

    private func fallbackIconName(for type: ActionType) -> String {
        switch type {
        case .attack: return "burst.fill"
        case .move: return "figure.walk"
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .retaliate: return "arrow.uturn.left.circle"
        case .range: return "scope"
        case .target: return "target"
        case .condition: return "exclamationmark.triangle.fill"
        case .element: return "flame.fill"
        case .push: return "arrow.right.circle"
        case .pull: return "arrow.left.circle"
        case .pierce: return "arrow.right.to.line"
        case .loot: return "dollarsign.circle"
        case .fly: return "wind"
        case .jump: return "arrow.up.circle"
        case .summon, .spawn: return "person.badge.plus"
        default: return "circle.fill"
        }
    }

    private func colorForAction(_ type: ActionType) -> Color {
        switch type {
        case .attack: return .red
        case .move: return .blue
        case .heal: return .green
        case .shield: return .cyan
        case .retaliate: return .orange
        case .condition: return .yellow
        case .element: return .purple
        case .loot: return .yellow
        case .push, .pull: return .teal
        case .pierce: return .red.opacity(0.7)
        default: return .white.opacity(0.5)
        }
    }
}
