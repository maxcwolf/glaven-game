import SwiftUI

struct MonsterAbilityView: View {
    let ability: AbilityModel
    @Bindable var monster: GameMonster
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.editionTheme) private var theme
    @State private var showFullscreen = false

    private var hasBottomActions: Bool {
        if let ba = ability.bottomActions, !ba.isEmpty { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactCardHeader
            abilityActions
            abilityFooter
            InteractiveActionsView(ability: ability, monster: monster)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { showFullscreen = true }
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            MonsterAbilitySheet(ability: ability, monster: monster)
        }
        #else
        .sheet(isPresented: $showFullscreen) {
            MonsterAbilitySheet(ability: ability, monster: monster)
                .frame(minWidth: 500, minHeight: 600)
        }
        #endif
    }

    // MARK: - Compact Card Header

    @ViewBuilder
    private var compactCardHeader: some View {
        ZStack(alignment: .topLeading) {
            MonsterAbilityCardBackground(hasBottomActions: false)

            HStack {
                Text("\(ability.initiative)")
                    .font(theme.titleFont(size: 18 * scale))
                    .foregroundStyle(.white)
                    .frame(width: 34 * scale, height: 34 * scale)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )

                Spacer()

                if ability.shuffle == true {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(6 * scale)
        }
        .frame(height: 56 * scale)
        .clipped()
    }

    // MARK: - Actions

    @ViewBuilder
    private var abilityActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let actions = ability.actions {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    if action.hidden != true {
                        MonsterActionRow(action: action, monster: monster, indent: 0, overrideType: nil)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    @ViewBuilder
    private var abilityFooter: some View {
        let showFooter = ability.shuffle == true || ability.lost == true || ability.persistent == true
        if showFooter {
            HStack(spacing: 8) {
                Spacer()
                if ability.shuffle == true {
                    footerBadge("arrow.triangle.2.circlepath", label: "Shuffle")
                }
                if ability.lost == true {
                    footerBadge("xmark.circle", label: "Lost")
                }
                if ability.persistent == true {
                    footerBadge("infinity", label: "Persistent")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func footerBadge(_ icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundStyle(GlavenTheme.secondaryText)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }
}

// MARK: - Separate view to avoid type-check explosion

struct MonsterActionRow: View {
    let action: ActionModel
    let monster: GameMonster
    let indent: Int
    let overrideType: MonsterType?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainContent
            subActionsContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch action.type {
        case .condition:
            conditionContent
        case .element:
            elementContent
        case .monsterType:
            monsterTypeContent
        case .box, .forceBox:
            boxContent
        case .concatenation:
            concatenationContent
        case .summon, .spawn:
            summonContent
        case .area:
            areaContent
        default:
            defaultContent
        }
    }

    // Only render sub-actions for default types (others handle their own subs)
    @ViewBuilder
    private var subActionsContent: some View {
        switch action.type {
        case .condition, .element, .monsterType, .box, .forceBox, .concatenation, .summon, .spawn, .grid, .area:
            EmptyView()
        default:
            if let subs = action.subActions {
                ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                    if sub.hidden != true {
                        MonsterActionRow(action: sub, monster: monster, indent: indent + 1, overrideType: overrideType)
                    }
                }
            }
        }
    }

    // MARK: - Condition

    @ViewBuilder
    private var conditionContent: some View {
        let condName = action.value?.stringValue ?? ""
        HStack(spacing: 4) {
            indentSpacer
            BundledImage(ImageLoader.conditionIcon(condName), size: 14, systemName: "bolt.fill")
            Text(condName.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.caption).fontWeight(.medium).foregroundStyle(.white)
        }
    }

    // MARK: - Element

    @ViewBuilder
    private var elementContent: some View {
        let elemName = action.value?.stringValue ?? ""
        let isConsume = action.valueType == .minus
        if isConsume, let subs = action.subActions, !subs.isEmpty {
            HStack(spacing: 4) {
                indentSpacer
                BundledImage(ImageLoader.elementIcon(elemName), size: 14, systemName: Self.elementFallback(elemName))
                    .opacity(0.5)
                Text(":").font(.caption).foregroundStyle(GlavenTheme.secondaryText)
            }
            ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                if sub.hidden != true {
                    MonsterActionRow(action: sub, monster: monster, indent: indent + 1, overrideType: overrideType)
                }
            }
        } else {
            HStack(spacing: 4) {
                indentSpacer
                BundledImage(ImageLoader.elementIcon(elemName), size: 14, systemName: Self.elementFallback(elemName))
                Text(elemName.capitalized).font(.caption).fontWeight(.medium).foregroundStyle(.white)
            }
        }
    }

    // MARK: - Monster Type Section

    @ViewBuilder
    private var monsterTypeContent: some View {
        let typeName = action.value?.stringValue ?? "normal"
        let mType: MonsterType = typeName.lowercased() == "elite" ? .elite : .normal
        let color: Color = mType == .elite ? GlavenTheme.elite : GlavenTheme.normalType

        HStack(spacing: 4) {
            indentSpacer
            Text(typeName.capitalized + ":").font(.caption).fontWeight(.bold).foregroundStyle(color)
        }
        if let subs = action.subActions {
            ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                if sub.hidden != true {
                    MonsterActionRow(action: sub, monster: monster, indent: indent + 1, overrideType: mType)
                }
            }
        }
    }

    // MARK: - Box

    @ViewBuilder
    private var boxContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let subs = action.subActions {
                ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                    if sub.hidden != true {
                        MonsterActionRow(action: sub, monster: monster, indent: 0, overrideType: overrideType)
                    }
                }
            }
        }
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .padding(.leading, CGFloat(indent * 16))
    }

    // MARK: - Concatenation

    @ViewBuilder
    private var concatenationContent: some View {
        HStack(spacing: 4) {
            indentSpacer
            if let subs = action.subActions {
                ForEach(Array(subs.enumerated()), id: \.offset) { idx, sub in
                    if sub.hidden != true {
                        if idx > 0 {
                            Text(",").font(.caption2).foregroundStyle(GlavenTheme.secondaryText)
                        }
                        MonsterInlineAction(action: sub, monster: monster, overrideType: overrideType)
                    }
                }
            }
        }
    }

    // MARK: - Summon / Spawn

    @ViewBuilder
    private var summonContent: some View {
        HStack(spacing: 4) {
            indentSpacer
            Image(systemName: "person.badge.plus").font(.caption).foregroundStyle(GlavenTheme.positive)
            Text(action.type == .spawn ? "Spawn:" : "Summon:")
                .font(.caption).fontWeight(.medium).foregroundStyle(GlavenTheme.positive)
            if let name = action.value?.stringValue {
                Text(name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption).foregroundStyle(.white)
            }
        }
    }

    // MARK: - Area (AoE Hex Grid)

    @ViewBuilder
    private var areaContent: some View {
        HStack(spacing: 4) {
            indentSpacer
            if let pattern = action.value?.stringValue {
                HexGridView(pattern: pattern, small: action.small == true)
            }
        }
    }

    // MARK: - Default

    @ViewBuilder
    private var defaultContent: some View {
        HStack(spacing: 4) {
            indentSpacer
            BundledImage(ImageLoader.actionIcon(action.type.rawValue), size: 14, systemName: Self.actionFallback(action.type))
            MonsterValueLabel(action: action, monster: monster, overrideType: overrideType)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var indentSpacer: some View {
        if indent > 0 {
            Spacer().frame(width: CGFloat(indent * 16))
        }
    }

    static func elementFallback(_ name: String) -> String {
        switch name.lowercased() {
        case "fire": return "flame.fill"
        case "ice": return "snowflake"
        case "air", "wind": return "wind"
        case "earth": return "leaf.fill"
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "sparkles"
        }
    }

    static func actionFallback(_ type: ActionType) -> String {
        switch type {
        case .attack: return "sword.2.crossed"
        case .move: return "figure.walk"
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .retaliate: return "arrow.uturn.backward"
        case .range: return "scope"
        case .condition: return "bolt.fill"
        case .element: return "sparkles"
        case .push: return "arrow.right"
        case .pull: return "arrow.left"
        case .target: return "target"
        case .loot: return "bag.fill"
        case .pierce: return "arrow.up.right"
        case .fly: return "bird.fill"
        case .jump: return "arrow.up"
        case .teleport: return "arrow.triangle.swap"
        default: return "circle.fill"
        }
    }
}

// MARK: - Value label (separated to reduce type-check)

struct MonsterValueLabel: View {
    let action: ActionModel
    let monster: GameMonster
    let overrideType: MonsterType?

    var body: some View {
        if monster.isBoss {
            bossLabel
        } else if let mt = overrideType {
            singleTypeLabel(mt)
        } else {
            dualTypeLabel
        }
    }

    @ViewBuilder
    private var bossLabel: some View {
        Text(resolved(overrideType ?? .boss))
            .font(.caption).fontWeight(.medium).foregroundStyle(GlavenTheme.boss)
    }

    @ViewBuilder
    private func singleTypeLabel(_ mt: MonsterType) -> some View {
        Text(resolved(mt))
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(mt == .elite ? GlavenTheme.elite : Color.white)
    }

    @ViewBuilder
    private var dualTypeLabel: some View {
        HStack(spacing: 2) {
            Text(resolved(.normal)).font(.caption).fontWeight(.medium).foregroundStyle(.white)
            Text("/").font(.caption2).foregroundStyle(GlavenTheme.secondaryText)
            Text(resolved(.elite)).font(.caption).fontWeight(.medium).foregroundStyle(GlavenTheme.elite)
        }
    }

    private func resolved(_ monsterType: MonsterType) -> String {
        let typeName = "\(action.type)".capitalized
        guard let value = action.value else { return typeName }
        if action.valueType == .plus || action.valueType == .minus {
            if let stat = monster.stat(for: monsterType) {
                let base: Int
                switch action.type {
                case .attack: base = stat.attack?.intValue ?? 0
                case .move: base = stat.movement?.intValue ?? 0
                case .range: base = stat.range?.intValue ?? 0
                default: base = 0
                }
                if base > 0 {
                    let modifier = action.valueType == .minus ? -value.intValue : value.intValue
                    return "\(typeName) \(base + modifier)"
                }
            }
        }
        let prefix: String
        switch action.valueType {
        case .plus: prefix = "+"
        case .minus: prefix = "-"
        default: prefix = ""
        }
        return "\(typeName) \(prefix)\(value.intValue)"
    }
}

// MARK: - Inline action for concatenation

struct MonsterInlineAction: View {
    let action: ActionModel
    let monster: GameMonster
    let overrideType: MonsterType?

    var body: some View {
        switch action.type {
        case .condition:
            conditionInline
        case .element:
            elementInline
        default:
            defaultInline
        }
    }

    @ViewBuilder
    private var conditionInline: some View {
        let condName = action.value?.stringValue ?? ""
        HStack(spacing: 2) {
            BundledImage(ImageLoader.conditionIcon(condName), size: 12, systemName: "bolt.fill")
            Text(condName.replacingOccurrences(of: "-", with: " ").capitalized)
                .font(.caption2).foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var elementInline: some View {
        let elemName = action.value?.stringValue ?? ""
        BundledImage(ImageLoader.elementIcon(elemName), size: 12, systemName: MonsterActionRow.elementFallback(elemName))
    }

    @ViewBuilder
    private var defaultInline: some View {
        HStack(spacing: 2) {
            BundledImage(ImageLoader.actionIcon(action.type.rawValue), size: 12, systemName: MonsterActionRow.actionFallback(action.type))
            MonsterValueLabel(action: action, monster: monster, overrideType: overrideType)
        }
    }
}

// MARK: - Monster Ability Card Background

/// Renders a card-textured background using the monster ability PNG assets.
/// Uses the front header image overlaid on a vertically-repeating body texture,
/// matching the Angular app's layered CSS pseudo-element approach.
struct MonsterAbilityCardBackground: View {
    var hasBottomActions: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Body fill: repeating texture
                if let repeatImg = ImageLoader.monsterAbilityRepeat() {
                    platformImage(repeatImg)
                        .resizable(resizingMode: .tile)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(0.85)
                }

                // Header overlay: non-repeating front image
                let frontImg = hasBottomActions ? ImageLoader.monsterAbilityBottom() : ImageLoader.monsterAbilityFront()
                if let img = frontImg {
                    VStack(spacing: 0) {
                        platformImage(img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width)
                            .clipped()
                        Spacer(minLength: 0)
                    }
                    .opacity(0.9)
                }

                // Subtle darkening gradient for readability
                LinearGradient(
                    colors: [Color.black.opacity(0.2), Color.black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }
}
