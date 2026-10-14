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

    /// Room kept clear in the top-right corner for a button laid over the card (the hand's magnifier).
    var cornerInset: CGFloat = 0

    init(
        card: AbilityModel,
        characterColor: Color = .blue,
        highlight: CardHighlight = .none,
        width: CGFloat = 130,
        height: CGFloat = 220,
        roleBadge: String? = nil,
        roleBadgeColor: Color = .yellow,
        labelResolver: ((String) -> String?)? = nil,
        onPreview: (() -> Void)? = nil,
        cornerInset: CGFloat = 0
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
        self.cornerInset = cornerInset
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
            .padding(.trailing, max(cornerInset, onPreview != nil ? scaled(18) : scaled(8)))
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
        return FirstThatFits {
            ForEach(Self.fits, id: \.self) { fit in
                halfLines(lines, lost: lost, fit: fit)
            }
            halfLines(lines, lost: lost, fit: 0.45)   // the last resort, clipped
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    /// A line of a half as laid out: an ability with the area it attacks beside it, as printed.
    struct Row {
        var line: CardLine
        var area: String?
    }

    static func rows(_ lines: [CardLine]) -> [Row] {
        var rows: [Row] = []
        for line in lines {
            if case .area(let pattern) = line.kind, let last = rows.last, last.line.kind == .ability, last.area == nil {
                rows[rows.count - 1].area = pattern
            } else {
                rows.append(Row(line: line))
            }
        }
        return rows
    }

    private func halfLines(_ lines: [CardLine], lost: Bool, fit: CGFloat) -> some View {
        // The half's closing marks (XP, persistent, uses) share a row with LOST when they fit.
        let closing = lines.last.flatMap { $0.kind == .badge && $0.depth == 0 ? $0 : nil }
        let rows = Self.rows(closing == nil ? lines : Array(lines.dropLast()))
        return VStack(alignment: .leading, spacing: scaled(2.5) * fit) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .center, spacing: scaled(4) * fit) {
                    lineView(row.line, fit: fit)
                    if let area = row.area {
                        Spacer(minLength: 0)
                        AreaPatternView(pattern: area, radius: scaled(7) * fit)
                    }
                }
                .padding(.leading, CGFloat(row.line.depth) * scaled(9) * fit)
            }
            if closing != nil || lost {
                RowOrColumn(spacing: scaled(3) * fit) { closingMarks(closing, lost: lost, fit: fit) }
            }
        }
        .padding(.horizontal, scaled(7))
        .padding(.vertical, scaled(5) * fit)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func closingMarks(_ closing: CardLine?, lost: Bool, fit: CGFloat) -> some View {
        if let closing { lineView(closing, fit: fit) }
        if lost { lostBadge(fit: fit) }
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
                .fixedSize(horizontal: false, vertical: true)
                .background(BoardTheme.brass.opacity(0.15), in: RoundedRectangle(cornerRadius: size(6)))
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

/// The first of its subviews (one half's lines at shrinking type) whose height, measured at the
/// space's own width, fits the space. The others are laid out of sight, where the half clips them.
struct FirstThatFits: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = ProposedViewSize(width: bounds.width, height: nil)
        let chosen = subviews.indices.first { subviews[$0].sizeThatFits(width).height <= bounds.height }
            ?? subviews.indices.last
        for index in subviews.indices {
            let origin = index == chosen ? bounds.origin : CGPoint(x: bounds.minX - 100_000, y: bounds.minY)
            subviews[index].place(at: origin, proposal: width)
        }
    }
}

/// Its subviews in a row when they fit the width side by side, else one under another at the
/// full width (where a long mark wraps).
struct RowOrColumn: Layout {
    var spacing: CGFloat

    private func inRow(_ width: CGFloat?, _ subviews: Subviews) -> Bool {
        let total = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
            + spacing * CGFloat(max(0, subviews.count - 1))
        return total <= (width ?? .infinity)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        if inRow(proposal.width, subviews) {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                          height: sizes.map(\.height).max() ?? 0)
        }
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(width: proposal.width ?? sizes.map(\.width).max() ?? 0,
                      height: sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        let row = inRow(bounds.width, subviews)
        for subview in subviews {
            let size = row ? subview.sizeThatFits(.unspecified)
                : subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: point, proposal: ProposedViewSize(size))
            if row { point.x += size.width + spacing } else { point.y += size.height + spacing }
        }
    }
}
