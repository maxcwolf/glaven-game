import SwiftUI

struct AbilityCardsSheet: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: Int?

    private var allAbilities: [AbilityModel] {
        guard let data = character.characterData else { return [] }
        let deckName = data.deck ?? character.name
        return gameManager.editionStore.abilities(forDeck: deckName, edition: character.edition)
    }

    private var availableLevels: [String] {
        var levels: Set<String> = []
        for ability in allAbilities {
            if let level = ability.level {
                levels.insert(level.stringValue)
            }
        }
        return levels.sorted { a, b in
            if a == "X" { return true }
            if b == "X" { return false }
            return (Int(a) ?? 99) < (Int(b) ?? 99)
        }
    }

    private var filteredAbilities: [AbilityModel] {
        if let level = selectedLevel {
            return allAbilities.filter { ($0.level?.intValue ?? 0) == level }
        }
        return allAbilities.filter {
            let lvl = $0.level?.intValue ?? 0
            let lvlStr = $0.level?.stringValue ?? ""
            return lvl <= character.level || lvlStr == "X"
        }
    }

    private var handSize: Int {
        character.characterData?.resolvedHandSize ?? 10
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Level filter bar
                levelFilterBar

                // Hand size indicator
                HStack {
                    Text("Hand Size: \(handSize)")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Spacer()
                    Text("\(filteredAbilities.count) cards")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                // Card grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 12)
                    ], spacing: 12) {
                        ForEach(filteredAbilities) { ability in
                            AbilityCardView(ability: ability)
                        }
                    }
                    .padding()
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Ability Cards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var levelFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                levelButton(nil, label: "All")
                ForEach(availableLevels, id: \.self) { level in
                    if level == "X" {
                        levelButton(nil, label: "X", isX: true)
                    } else if let lvl = Int(level) {
                        levelButton(lvl, label: "Lv \(lvl)")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func levelButton(_ level: Int?, label: String, isX: Bool = false) -> some View {
        Button {
            selectedLevel = level
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedLevel == level ? GlavenTheme.accentText.opacity(0.3) : GlavenTheme.primaryText.opacity(0.08))
                .foregroundStyle(selectedLevel == level ? GlavenTheme.accentText : GlavenTheme.primaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ability Card View

private struct AbilityCardView: View {
    let ability: AbilityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack {
                Text("#\(ability.cardId ?? 0)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)

                Text(ability.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .lineLimit(1)

                Spacer()

                // Level badge
                if let level = ability.level {
                    Text("Lv \(level.stringValue)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(levelColor(level).opacity(0.2))
                        .foregroundStyle(levelColor(level))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().background(GlavenTheme.primaryText.opacity(0.1))

            // Initiative
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
                Text("Initiative \(ability.initiative)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.primaryText)

                Spacer()

                // Flags
                if ability.lost == true {
                    flagBadge("Lost", color: .red)
                }
                if ability.persistent == true {
                    flagBadge("Persistent", color: .blue)
                }
                if ability.shuffle == true {
                    flagBadge("Shuffle", color: .orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            // Top actions
            if let actions = ability.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        actionRow(action)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            // Bottom actions
            if let actions = ability.bottomActions, !actions.isEmpty {
                Divider()
                    .background(GlavenTheme.primaryText.opacity(0.05))
                    .padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bottom")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        actionRow(action)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            // XP
            if let xp = ability.xp, xp > 0 {
                HStack {
                    Spacer()
                    Label("\(xp) XP", systemImage: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
        }
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(GlavenTheme.primaryText.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionRow(_ action: ActionModel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconForAction(action.type))
                .font(.caption2)
                .foregroundStyle(colorForAction(action.type))
                .frame(width: 14)
            Text(describeAction(action))
                .font(.caption)
                .foregroundStyle(GlavenTheme.primaryText)
        }

        // Show sub-actions indented (one level only)
        if let subs = action.subActions {
            ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                HStack(spacing: 4) {
                    Spacer().frame(width: 12)
                    Image(systemName: iconForAction(sub.type))
                        .font(.caption2)
                        .foregroundStyle(colorForAction(sub.type))
                        .frame(width: 14)
                    Text(describeAction(sub))
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func flagBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9))
            .fontWeight(.bold)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func levelColor(_ level: IntOrString) -> Color {
        let str = level.stringValue
        if str == "X" { return .purple }
        let lvl = level.intValue
        switch lvl {
        case 1: return .green
        case 2: return .teal
        case 3: return .blue
        case 4: return .indigo
        case 5: return .purple
        case 6: return .orange
        case 7: return .red
        case 8: return .pink
        case 9: return .yellow
        default: return .gray
        }
    }

    private func iconForAction(_ type: ActionType) -> String {
        switch type {
        case .attack: return "burst.fill"
        case .move: return "figure.walk"
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .retaliate: return "arrow.uturn.left.circle"
        case .range: return "scope"
        case .target: return "target"
        case .condition: return "exclamationmark.triangle"
        case .element: return "flame.fill"
        case .push: return "arrow.right.circle"
        case .pull: return "arrow.left.circle"
        case .pierce: return "arrow.right.to.line"
        case .loot: return "dollarsign.circle"
        case .fly: return "wind"
        case .jump: return "arrow.up.circle"
        case .summon, .spawn: return "person.badge.plus"
        case .area: return "square.grid.3x3.topleft.filled"
        case .custom: return "text.bubble"
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
        case .summon, .spawn: return .cyan
        default: return GlavenTheme.secondaryText
        }
    }

    private func describeAction(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        let prefix = action.valueType == .plus ? "+" : (action.valueType == .minus ? "-" : "")
        switch action.type {
        case .attack: return "\(prefix)\(value) Attack"
        case .move: return "\(prefix)\(value) Move"
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .range: return "\(prefix)\(value) Range"
        case .target: return "\(prefix)\(value) Target"
        case .condition: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case .element: return "\(value.capitalized) Element"
        case .push: return "Push \(value)"
        case .pull: return "Pull \(value)"
        case .pierce: return "Pierce \(value)"
        case .loot: return "Loot \(value)"
        case .fly: return "Flying"
        case .jump: return "Jump"
        case .summon, .spawn: return "Summon \(value.replacingOccurrences(of: "-", with: " ").capitalized)"
        case .area: return "Area"
        case .custom: return value
        case .concatenation: return "and"
        default: return "\(action.type.rawValue.capitalized) \(value)"
        }
    }
}
