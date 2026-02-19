import SwiftUI

/// Which half of the card to highlight, if any.
enum CardHighlight {
    case none
    case top       // Using top actions (dims bottom)
    case bottom    // Using bottom actions (dims top)
}

/// Reusable view that renders a Gloomhaven ability card with top/bottom action halves.
/// Used in card selection, execution display, and damage mitigation.
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

    /// Tooltip text currently shown on hover.
    @State private var hoveredTooltip: String?

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
                            .font(.system(size: 8))
                    }
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(roleBadgeColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(roleBadgeColor.opacity(0.15))
            }

            // ─── Card Header: Initiative + Name ───
            HStack(spacing: 6) {
                Text("\(card.initiative)")
                    .font(.system(size: scaledFont(22), weight: .heavy, design: .monospaced))
                    .foregroundStyle(highlight == .top ? .yellow : .white)

                Text(card.name ?? "Card \(card.cardId ?? 0)")
                    .font(.system(size: scaledFont(10), weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            .padding(.trailing, onPreview != nil ? scaledFont(18) : 8)
            .padding(.vertical, 4)

            // ─── Top Half: Actions ───
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(flattenedActions(card.actions).enumerated()), id: \.offset) { _, action in
                    actionRow(action)
                }
                if card.lost == true {
                    lostBadge
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .overlay(
                highlight == .top ? RoundedRectangle(cornerRadius: 4)
                    .stroke(.yellow.opacity(0.4), lineWidth: 1.5)
                    .padding(2) : nil
            )
            .opacity(highlight == .bottom ? 0.35 : 1.0)

            // ─── Divider ───
            Rectangle()
                .fill(characterColor.opacity(0.5))
                .frame(height: 1.5)

            // ─── Bottom Half: Actions ───
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(flattenedActions(card.bottomActions).enumerated()), id: \.offset) { _, action in
                    actionRow(action)
                }
                if card.bottomLost == true {
                    lostBadge
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(characterColor.opacity(0.08))
            .overlay(
                highlight == .bottom ? RoundedRectangle(cornerRadius: 4)
                    .stroke(.cyan.opacity(0.4), lineWidth: 1.5)
                    .padding(2) : nil
            )
            .opacity(highlight == .top ? 0.35 : 1.0)
        }
        .frame(width: width, height: height)
        .background(Color.white.opacity(0.05))
        .overlay {
            if let tooltip = hoveredTooltip {
                VStack {
                    Spacer()
                    Text(tooltip)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.95))
                        .multilineTextAlignment(.leading)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
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
                        .font(.system(size: scaledFont(10), weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(4)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            onPreview?()
        }
        .animation(.easeInOut(duration: 0.15), value: hoveredTooltip)
    }

    private var borderColor: Color {
        switch highlight {
        case .top: return .yellow
        case .bottom: return .cyan
        case .none: return .white.opacity(0.12)
        }
    }

    private func scaledFont(_ baseSize: CGFloat) -> CGFloat {
        let scale = width / 130.0
        return baseSize * scale
    }

    // MARK: - Sub-views

    private var lostBadge: some View {
        Text("LOSS")
            .font(.system(size: scaledFont(8), weight: .heavy, design: .monospaced))
            .foregroundStyle(.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.red.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Action Rendering

    private static let skipActionTypes: Set<ActionType> = [
        .concatenation, .concatenationSpacer, .box, .grid,
        .hint, .nonCalc, .forceBox, .specialTarget, .text
    ]

    private static let containerTypes: Set<ActionType> = [
        .concatenation, .box, .grid
    ]

    private func isPlaceholder(_ value: String) -> Bool {
        value.hasPrefix("%") && value.hasSuffix("%")
    }

    @ViewBuilder
    private func actionRow(_ action: ActionModel) -> some View {
        if Self.skipActionTypes.contains(action.type) {
            // Container/meta — subActions already flattened
        } else if action.type == .custom {
            customActionView(action)
        } else if action.type == .card {
            cardActionView(action)
        } else if action.type == .experience {
            xpBadge(action)
        } else if action.type == .grant {
            grantActionView(action)
        } else if action.type == .suffer || action.type == .sufferDamage {
            sufferActionView(action)
        } else if action.type == .special || action.type == .trigger {
            specialTextView(action)
        } else if action.type == .area {
            areaActionView()
        } else if action.type == .teleport {
            teleportActionView(action)
        } else if isPlaceholder(action.value?.stringValue ?? "") {
            // Skip unresolvable placeholder values
        } else {
            standardActionRow(action)
        }
    }

    /// Renders a custom action: resolves placeholder text and renders subActions.
    @ViewBuilder
    private func customActionView(_ action: ActionModel) -> some View {
        let rawText = action.value?.stringValue ?? ""
        let resolvedText: String? = {
            if isPlaceholder(rawText), let resolver = labelResolver {
                return resolver(rawText)
            } else if !rawText.isEmpty && !isPlaceholder(rawText) {
                return rawText
            }
            return nil
        }()

        if let text = resolvedText, !text.isEmpty {
            Text(text)
                .font(.system(size: scaledFont(9)))
                .foregroundStyle(.white.opacity(0.6))
                .italic()
                .lineLimit(3)
        }

        // Render subActions of custom actions (e.g. attack/range details)
        if let subs = action.subActions {
            ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                indentedSubAction(sub)
            }
        }
    }

    /// Renders a `.card` action — primarily XP badges (value "experience:N").
    @ViewBuilder
    private func cardActionView(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? ""
        if value.hasPrefix("experience:") {
            let amount = value.replacingOccurrences(of: "experience:", with: "")
            xpBadgeText("XP +\(amount)")
        }
        // Other card subtypes silently ignored
    }

    /// Renders an `.experience` action as an XP badge.
    @ViewBuilder
    private func xpBadge(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? "1"
        xpBadgeText("XP +\(value)")
    }

    private func xpBadgeText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: scaledFont(8), weight: .bold, design: .monospaced))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.yellow.opacity(0.15))
            .clipShape(Capsule())
    }

    /// Renders a `.grant` action with its subActions.
    @ViewBuilder
    private func grantActionView(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? ""
        if !value.isEmpty && !isPlaceholder(value) {
            Text(value)
                .font(.system(size: scaledFont(9)))
                .foregroundStyle(.white.opacity(0.6))
                .italic()
                .lineLimit(2)
        }
        if let subs = action.subActions {
            ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                indentedSubAction(sub)
            }
        }
    }

    /// Renders `.suffer` / `.sufferDamage` actions.
    @ViewBuilder
    private func sufferActionView(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? ""
        HStack(spacing: 3) {
            BundledImage(ImageLoader.actionIcon("damage"), size: scaledFont(11), systemName: "heart.slash")
                .foregroundStyle(.red.opacity(0.7))
                .frame(width: scaledFont(12))
            Text("Suffer \(value) damage")
                .font(.system(size: scaledFont(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// Renders `.special` / `.trigger` as descriptive text.
    @ViewBuilder
    private func specialTextView(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? ""
        if !value.isEmpty {
            let displayText: String = {
                if isPlaceholder(value), let resolver = labelResolver {
                    return resolver(value) ?? ""
                }
                return value
            }()
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.system(size: scaledFont(9)))
                    .foregroundStyle(.white.opacity(0.6))
                    .italic()
                    .lineLimit(2)
            }
        }
    }

    /// Renders `.area` as an indicator.
    @ViewBuilder
    private func areaActionView() -> some View {
        HStack(spacing: 3) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: scaledFont(9)))
                .foregroundStyle(.orange.opacity(0.7))
                .frame(width: scaledFont(12))
            Text("Area effect")
                .font(.system(size: scaledFont(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// Renders `.teleport` action.
    @ViewBuilder
    private func teleportActionView(_ action: ActionModel) -> some View {
        let value = action.value?.stringValue ?? ""
        HStack(spacing: 3) {
            BundledImage(ImageLoader.actionIcon("teleport"), size: scaledFont(11), systemName: "arrow.triangle.swap")
                .foregroundStyle(.purple)
                .frame(width: scaledFont(12))
            Text("Teleport \(value)")
                .font(.system(size: scaledFont(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// Standard action rendering with icon + text + inline subs + condition/element subs.
    @ViewBuilder
    private func standardActionRow(_ action: ActionModel) -> some View {
        HStack(spacing: 3) {
            actionIconView(action.type, value: action.value?.stringValue, size: scaledFont(11))
                .frame(width: scaledFont(12))

            Text(describeAction(action))
                .font(.system(size: scaledFont(10), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            if let subs = action.subActions {
                let inlineSubs = subs.filter { $0.type == .range || $0.type == .target }
                ForEach(Array(inlineSubs.enumerated()), id: \.offset) { _, sub in
                    Text(describeAction(sub))
                        .font(.system(size: scaledFont(9)))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .onHover { hovering in
            let tip = tooltipForAction(action)
            hoveredTooltip = hovering && !tip.isEmpty ? tip : nil
        }

        if let subs = action.subActions {
            let detailSubs = subs.filter { $0.type == .condition || $0.type == .element || $0.type == .custom }
            ForEach(Array(detailSubs.enumerated()), id: \.offset) { _, sub in
                indentedSubAction(sub)
            }
        }
    }

    /// Renders a sub-action indented under its parent.
    @ViewBuilder
    private func indentedSubAction(_ sub: ActionModel) -> some View {
        if sub.type == .custom {
            let text = sub.value?.stringValue ?? ""
            let displayText: String = {
                if isPlaceholder(text), let resolver = labelResolver {
                    return resolver(text) ?? ""
                }
                return text
            }()
            if !displayText.isEmpty {
                HStack(spacing: 3) {
                    Spacer().frame(width: scaledFont(12))
                    Text(displayText)
                        .font(.system(size: scaledFont(8)))
                        .foregroundStyle(.white.opacity(0.5))
                        .italic()
                        .lineLimit(2)
                }
            }
        } else if Self.skipActionTypes.contains(sub.type) {
            // skip
        } else if sub.type == .card {
            let value = sub.value?.stringValue ?? ""
            if value.hasPrefix("experience:") {
                let amount = value.replacingOccurrences(of: "experience:", with: "")
                HStack(spacing: 3) {
                    Spacer().frame(width: scaledFont(12))
                    xpBadgeText("XP +\(amount)")
                }
            }
        } else if sub.type == .experience {
            let value = sub.value?.stringValue ?? "1"
            HStack(spacing: 3) {
                Spacer().frame(width: scaledFont(12))
                xpBadgeText("XP +\(value)")
            }
        } else {
            HStack(spacing: 3) {
                Spacer().frame(width: scaledFont(12))
                actionIconView(sub.type, value: sub.value?.stringValue, size: scaledFont(10))
                    .frame(width: scaledFont(10))
                Text(describeAction(sub))
                    .font(.system(size: scaledFont(9)))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .onHover { hovering in
                let tip = tooltipForAction(sub)
                hoveredTooltip = hovering && !tip.isEmpty ? tip : nil
            }
        }
    }

    private func flattenedActions(_ actions: [ActionModel]?) -> [ActionModel] {
        guard let actions else { return [] }
        var result: [ActionModel] = []
        for action in actions {
            if Self.containerTypes.contains(action.type), let subs = action.subActions {
                result.append(contentsOf: flattenedActions(subs))
            } else {
                result.append(action)
            }
        }
        return result
    }

    // MARK: - Action Helpers

    @ViewBuilder
    private func actionIconView(_ type: ActionType, value: String? = nil, size: CGFloat) -> some View {
        if type == .condition, let name = value {
            BundledImage(ImageLoader.conditionIcon(name), size: size, systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colorForAction(type))
        } else if type == .element, let name = value {
            BundledImage(ImageLoader.elementIcon(name), size: size, systemName: "flame.fill")
                .foregroundStyle(colorForAction(type))
        } else {
            BundledImage(ImageLoader.actionIcon(type.rawValue), size: size, systemName: fallbackIconName(for: type))
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

    private func describeAction(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        let prefix = action.valueType == .plus ? "+" : (action.valueType == .minus ? "-" : "")
        switch action.type {
        case .attack: return "Attack \(prefix)\(value)"
        case .move: return "Move \(prefix)\(value)"
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .range: return "Rng \(prefix)\(value)"
        case .target: return "Tgt \(prefix)\(value)"
        case .condition: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case .element: return value.capitalized
        case .push: return "Push \(value)"
        case .pull: return "Pull \(value)"
        case .pierce: return "Pierce \(value)"
        case .loot: return "Loot \(value)"
        case .fly: return "Flying"
        case .jump: return "Jump"
        case .summon, .spawn: return "Summon"
        case .teleport: return "Teleport \(value)"
        case .suffer, .sufferDamage: return "Suffer \(value) damage"
        case .experience: return "XP +\(value)"
        default: return "\(action.type.rawValue.capitalized) \(value)".trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Tooltips

    private func tooltipForAction(_ action: ActionModel) -> String {
        switch action.type {
        case .attack:
            return "Attack: Deal damage to a target equal to your attack value, modified by an attack modifier card."
        case .move:
            return "Move: Move up to the listed number of hexes. Cannot move through enemies or obstacles."
        case .heal:
            return "Heal: Restore hit points to a figure. Also removes Wound and Poison."
        case .shield:
            return "Shield: Reduce each incoming attack by the shield value. Lasts until end of round unless persistent."
        case .retaliate:
            return "Retaliate: When attacked from within the specified range, deal this damage back to the attacker after their attack resolves."
        case .range:
            return "Range: This attack can target enemies within this many hexes. Range 1 = adjacent only (melee)."
        case .target:
            return "Target: This attack can hit this many different targets within range."
        case .push:
            return "Push: After the attack, force the target this many hexes away from you. Target must move to empty hexes."
        case .pull:
            return "Pull: After the attack, force the target this many hexes toward you. Target must move to empty hexes."
        case .pierce:
            return "Pierce: Ignore this much of the target's Shield value when calculating damage."
        case .loot:
            return "Loot: Pick up all money tokens and treasure tiles within the specified range."
        case .fly:
            return "Flying: Ignore all enemies, obstacles, and hazards during movement. Must end on an empty hex."
        case .jump:
            return "Jump: Ignore all enemies and obstacles during movement (but not the destination hex)."
        case .summon, .spawn:
            return "Summon: Place a summoned ally on an adjacent empty hex. Summons act on your initiative with their own ability cards."
        case .condition:
            return tooltipForCondition(action.value?.stringValue ?? "")
        case .element:
            return tooltipForElement(action.value?.stringValue ?? "")
        default:
            return ""
        }
    }

    private func tooltipForCondition(_ name: String) -> String {
        switch name.lowercased() {
        case "stun":
            return "Stun: Target cannot perform any actions or use items on their next turn. Removed at end of their next turn."
        case "muddle":
            return "Muddle: Target gains Disadvantage on all attacks (draw 2 modifier cards, use the worse one). Removed at end of their next turn."
        case "wound":
            return "Wound: Target suffers 1 damage at the start of each of their turns. Removed by any Heal ability."
        case "poison":
            return "Poison: Target adds +1 to all damage from attacks against them. Removed by any Heal ability (which heals 0 instead)."
        case "immobilize":
            return "Immobilize: Target cannot perform any Move abilities. Removed at end of their next turn."
        case "disarm":
            return "Disarm: Target cannot perform any Attack abilities. Removed at end of their next turn."
        case "invisible":
            return "Invisible: Target cannot be focused or targeted by enemies. Removed at end of their next turn."
        case "strengthen":
            return "Strengthen: Target gains Advantage on all attacks (draw 2 modifier cards, use the better one). Removed at end of their next turn."
        case "curse":
            return "Curse: Add a null (x0) card to the target's attack modifier deck. Removed when drawn."
        case "bless":
            return "Bless: Add a 2x card to the target's attack modifier deck. Removed when drawn."
        case "regenerate":
            return "Regenerate: Heal 1 at the start of each of the target's turns."
        case "ward":
            return "Ward: The next time this figure takes damage, it is halved (rounded down). Then Ward is removed."
        case "brittle":
            return "Brittle: The next time this figure takes damage, it is doubled. Then Brittle is removed."
        case "bane":
            return "Bane: Target suffers 10 damage at end of their next turn, then Bane is removed."
        case "dodge":
            return "Dodge: The next attack targeting this figure gains Disadvantage. Then Dodge is removed."
        default:
            return "\(name.replacingOccurrences(of: "-", with: " ").capitalized): A condition applied to the target."
        }
    }

    private func tooltipForElement(_ name: String) -> String {
        switch name.lowercased() {
        case "fire":
            return "Fire: Infuse the Fire element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Fire."
        case "ice":
            return "Ice: Infuse the Ice element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Ice."
        case "air":
            return "Air: Infuse the Air element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Air."
        case "earth":
            return "Earth: Infuse the Earth element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Earth."
        case "light":
            return "Light: Infuse the Light element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Light."
        case "dark":
            return "Dark: Infuse the Dark element. It becomes Strong this round, Waning next round, then Inert. Can be consumed by abilities that require Dark."
        default:
            return "\(name.capitalized): Infuse this element. Strong → Waning → Inert. Consumed by abilities that require it."
        }
    }
}
