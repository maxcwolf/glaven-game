import SwiftUI

/// Standalone Decks Viewer for browsing monster and character ability decks.
struct DecksViewerSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEdition: String = "gh"
    @State private var showMonsters = true
    @State private var selectedLevel: Int = 1
    @State private var expandedDecks: Set<String> = []

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var monsterDecks: [(name: String, abilities: [AbilityModel])] {
        let monsters = gameManager.editionStore.monsters(for: selectedEdition)
        return monsters.compactMap { monster in
            let deckName = monster.deck ?? monster.name
            let abilities = gameManager.editionStore.abilities(forDeck: deckName, edition: selectedEdition)
            guard !abilities.isEmpty else { return nil }
            return (name: monster.name, abilities: abilities)
        }.sorted { $0.name < $1.name }
    }

    private var characterDecks: [(name: String, abilities: [AbilityModel])] {
        let characters = gameManager.editionStore.characters(for: selectedEdition)
        return characters.compactMap { char in
            let deckName = char.deck ?? char.name
            let abilities = gameManager.editionStore.abilities(forDeck: deckName, edition: selectedEdition)
            guard !abilities.isEmpty else { return nil }
            return (name: char.name, abilities: abilities)
        }.sorted { $0.name < $1.name }
    }

    private var currentDecks: [(name: String, abilities: [AbilityModel])] {
        showMonsters ? monsterDecks : characterDecks
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(currentDecks, id: \.name) { deck in
                            deckSection(deck)
                        }
                    }
                    .padding()
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Decks Viewer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 450, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedEdition) { _, _ in
                expandedDecks = []
            }
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Edition", selection: $selectedEdition) {
                    ForEach(editions, id: \.self) { edition in
                        Text(edition.uppercased()).tag(edition)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker("Type", selection: $showMonsters) {
                    Text("Monsters").tag(true)
                    Text("Characters").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            if showMonsters {
                HStack {
                    Text("Level")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Picker("Level", selection: $selectedLevel) {
                        ForEach(0...7, id: \.self) { level in
                            Text("\(level)").tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlavenTheme.cardBackground)
    }

    // MARK: - Deck Section

    @ViewBuilder
    private func deckSection(_ deck: (name: String, abilities: [AbilityModel])) -> some View {
        let isExpanded = expandedDecks.contains(deck.name)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedDecks.remove(deck.name)
                    } else {
                        expandedDecks.insert(deck.name)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: showMonsters ? "pawprint.fill" : "person.fill")
                        .foregroundStyle(showMonsters ? .red : .blue)
                        .frame(width: 24)

                    Text(deck.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GlavenTheme.primaryText)

                    Spacer()

                    Text("\(deck.abilities.count) cards")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                // Ability cards
                VStack(spacing: 8) {
                    ForEach(deck.abilities.sorted(by: { $0.initiative < $1.initiative })) { ability in
                        abilityRow(ability)
                    }
                }
                .padding(12)
            }
        }
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Ability Row

    @ViewBuilder
    private func abilityRow(_ ability: AbilityModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header line
            HStack {
                // Initiative badge
                Text("\(ability.initiative)")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.orange))

                if let name = ability.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GlavenTheme.primaryText)
                }

                Spacer()

                if let cardId = ability.cardId {
                    Text("#\(cardId)")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }

                if ability.shuffle == true {
                    Image(systemName: "shuffle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Top actions
            if let actions = ability.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        actionText(action, indent: 0)
                    }
                }
            }

            // Bottom actions
            if let bottomActions = ability.bottomActions, !bottomActions.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(bottomActions.enumerated()), id: \.offset) { _, action in
                        actionText(action, indent: 0)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Text

    @ViewBuilder
    private func actionText(_ action: ActionModel, indent: Int) -> some View {
        HStack(spacing: 4) {
            if indent > 0 {
                Spacer()
                    .frame(width: CGFloat(indent) * 12)
            }

            Text(actionDescription(action))
                .font(.caption)
                .foregroundStyle(colorForAction(action))

            if let subs = action.subActions, !subs.isEmpty, action.type != .monsterType {
                // Show inline sub-actions
                ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                    if sub.type != .target && sub.type != .range {
                        Text(actionDescription(sub))
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
        }

        // MonsterType sections (non-recursive, one level deep)
        if action.type == .monsterType {
            if let subs = action.subActions {
                ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                    actionLineView(sub, indent: indent + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func actionLineView(_ action: ActionModel, indent: Int) -> some View {
        HStack(spacing: 4) {
            if indent > 0 {
                Spacer()
                    .frame(width: CGFloat(indent) * 12)
            }

            Text(actionDescription(action))
                .font(.caption)
                .foregroundStyle(colorForAction(action))

            if let subs = action.subActions, !subs.isEmpty {
                ForEach(Array(subs.enumerated()), id: \.offset) { _, sub in
                    if sub.type != .target && sub.type != .range {
                        Text(actionDescription(sub))
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
        }
    }

    private func actionDescription(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        switch action.type {
        case .attack: return "Attack \(value)"
        case .move: return "Move \(value)"
        case .range: return "Range \(value)"
        case .target: return "Target \(value)"
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .condition:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        case .element: return "Element: \(value)"
        case .summon: return "Summon: \(value)"
        case .spawn: return "Spawn: \(value)"
        case .push: return "Push \(value)"
        case .pull: return "Pull \(value)"
        case .pierce: return "Pierce \(value)"
        case .sufferDamage: return "Suffer \(value) damage"
        case .loot: return "Loot \(value)"
        case .teleport: return "Teleport \(value)"
        case .jump: return "Jump"
        case .fly: return "Fly"
        case .swing: return "Swing"
        case .switchType: return "Switch Type"
        case .monsterType: return "[\(value)]"
        case .specialTarget: return "Target: \(value)"
        case .concatenation: return "and"
        case .grant: return "Grant: \(value)"
        case .area: return "AoE"
        default: return "\(action.type.rawValue) \(value)".trimmingCharacters(in: .whitespaces)
        }
    }

    private func colorForAction(_ action: ActionModel) -> Color {
        switch action.type {
        case .attack: return .red
        case .move, .teleport, .jump, .fly: return .blue
        case .heal: return .green
        case .shield: return .yellow
        case .retaliate: return .orange
        case .condition: return .purple
        case .element: return .cyan
        case .summon, .spawn: return .mint
        case .monsterType: return .gray
        default: return GlavenTheme.primaryText
        }
    }
}
