import SwiftUI

struct GameSetupView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.editionTheme) private var theme
    @State private var selectedLevel = 1
    @State private var selectedScenario: ScenarioData?
    @State private var scenarioSearch = ""

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var allCharacters: [CharacterData] {
        gameManager.editionStore.characters(for: edition).filter { isUnlocked($0) }
    }

    private var existingNames: Set<String> {
        Set(gameManager.game.characters.map(\.name))
    }

    private var availableScenarios: [ScenarioData] {
        gameManager.scenarioManager.availableScenarios(for: edition)
    }

    private var filteredScenarios: [ScenarioData] {
        guard !scenarioSearch.isEmpty else { return availableScenarios }
        let query = scenarioSearch.lowercased()
        return availableScenarios.filter {
            $0.name.lowercased().contains(query) || $0.index.contains(query)
        }
    }

    private var canStart: Bool {
        !gameManager.game.characters.isEmpty && selectedScenario != nil
    }

    private func isUnlocked(_ character: CharacterData) -> Bool {
        let isSpoiler = character.spoiler ?? false
        let isLocked = character.locked ?? false
        if !isSpoiler && !isLocked { return true }
        let key = "\(character.edition)-\(character.name)"
        return gameManager.game.unlockedCharacters.contains(key)
    }

    var body: some View {
        ZStack {
            // Textured background with dark translucent overlay
            ParchmentBackground(edition: edition)
                .overlay(
                    Color(red: 0.12, green: 0.14, blue: 0.18)
                        .opacity(GlavenTheme.isLight ? 0.15 : 0.75)
                )

            // Main content — centered panels with breathing room
            GeometryReader { geo in
                let panelHeight = min(geo.size.height - 120, 700)
                VStack(spacing: 20) {
                    HStack(spacing: 24) {
                        characterPanel
                            .frame(maxWidth: 420)
                        scenarioPanel
                            .frame(maxWidth: 420)
                    }
                    .frame(height: panelHeight)

                    // Start button
                    Button {
                        if let scenario = selectedScenario {
                            gameManager.startScenarioOnBoard(scenario)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Start Scenario")
                                .font(theme.titleFont(size: 20))
                        }
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(canStart ? Color.accentColor : GlavenTheme.primaryText.opacity(0.08))
                        .foregroundStyle(canStart ? .white : GlavenTheme.secondaryText)
                        .clipShape(Capsule())
                        .shadow(color: canStart ? Color.accentColor.opacity(0.4) : .clear, radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 32)

            // Floating back button — top-left, below title bar
            VStack {
                HStack {
                    Button {
                        gameManager.newGame()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                            Text("Menu")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(GlavenTheme.cardBackground.opacity(0.8))
                        .foregroundStyle(GlavenTheme.accentText)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.top, 8)
                Spacer()
            }
        }
    }

    // MARK: - Character Panel

    @ViewBuilder
    private var characterPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "person.3.fill")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.accentText)
                Text("Party")
                    .font(theme.titleFont(size: 18))
                    .foregroundStyle(GlavenTheme.primaryText)
                Spacer()
                if gameManager.game.characters.isEmpty {
                    Text("Choose 2\u{2013}4")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                } else {
                    Text("\(gameManager.game.characters.count) of 4")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.accentText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Level selector
            HStack(spacing: 0) {
                Text("Lvl")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(GlavenTheme.secondaryText)
                    .padding(.trailing, 8)
                ForEach(1...9, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        Text("\(level)")
                            .font(.caption)
                            .fontWeight(selectedLevel == level ? .bold : .regular)
                            .frame(width: 28, height: 28)
                            .background(selectedLevel == level ? Color.accentColor : GlavenTheme.primaryText.opacity(0.06))
                            .foregroundStyle(selectedLevel == level ? .white : GlavenTheme.secondaryText)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    if level < 9 {
                        Spacer(minLength: 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            difficultyRow
            difficultyHint

            Divider().opacity(0.2)

            // Character list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(allCharacters) { character in
                        characterRow(character)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(GlavenTheme.cardBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(GlavenTheme.primaryText.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private var difficultyRow: some View {
        HStack(spacing: 0) {
            Text("Diff")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.secondaryText)
                .frame(width: 28, alignment: .leading)
            ForEach(DifficultyMode.allCases, id: \.self) { mode in
                difficultyButton(mode)
                if mode != .veryHard {
                    Spacer(minLength: 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func difficultyButton(_ mode: DifficultyMode) -> some View {
        let isSelected = gameManager.game.difficulty == mode
        Button {
            gameManager.game.difficulty = mode
        } label: {
            Text(mode.shortLabel)
                .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(isSelected ? difficultyColor(mode) : GlavenTheme.primaryText.opacity(0.06))
                .foregroundStyle(isSelected ? .white : GlavenTheme.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var difficultyHint: some View {
        if !gameManager.game.characters.isEmpty {
            let scenLevel = gameManager.levelManager.scenarioLevel()
            Text("Scenario level: \(scenLevel) · \(gameManager.game.difficulty.description)")
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func difficultyColor(_ mode: DifficultyMode) -> Color {
        switch mode {
        case .story:    return .blue
        case .easy:     return .green
        case .normal:   return Color.accentColor
        case .hard:     return .orange
        case .veryHard: return .red
        }
    }

    @ViewBuilder
    private func characterRow(_ character: CharacterData) -> some View {
        let isAdded = existingNames.contains(character.name)
        let charColor = Color(hex: character.color ?? "#808080") ?? .gray

        Button {
            if isAdded {
                if let gameChar = gameManager.game.characters.first(where: { $0.name == character.name }) {
                    gameManager.characterManager.removeCharacter(gameChar)
                }
            } else {
                guard gameManager.game.characters.count < 4 else { return }
                gameManager.characterManager.addCharacter(name: character.name, edition: edition, level: selectedLevel)
            }
        } label: {
            HStack(spacing: 10) {
                ThumbnailImage(
                    image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                    size: 40,
                    cornerRadius: 8,
                    fallbackColor: charColor
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isAdded ? charColor : .clear, lineWidth: 2)
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 10, color: .red)
                            Text("\(character.healthForLevel(selectedLevel))")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        Text("Hand \(character.resolvedHandSize)")
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Spacer()

                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(charColor)
                        .font(.body)
                } else {
                    Circle()
                        .strokeBorder(GlavenTheme.primaryText.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isAdded ? charColor.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAdded && gameManager.game.characters.count >= 4)
        .opacity(!isAdded && gameManager.game.characters.count >= 4 ? 0.4 : 1)
    }

    // MARK: - Scenario Panel

    @ViewBuilder
    private var scenarioPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "map.fill")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.accentText)
                Text("Scenario")
                    .font(theme.titleFont(size: 18))
                    .foregroundStyle(GlavenTheme.primaryText)
                Spacer()
                if let s = selectedScenario {
                    Text(s.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.accentText)
                        .lineLimit(1)
                } else {
                    Text("\(availableScenarios.count) available")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search bar (only if many scenarios)
            if availableScenarios.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    TextField("Search", text: $scenarioSearch)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !scenarioSearch.isEmpty {
                        Button {
                            scenarioSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(GlavenTheme.primaryText.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider().opacity(0.2)

            // Scenario list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredScenarios) { scenario in
                        scenarioRow(scenario)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .background(GlavenTheme.cardBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(GlavenTheme.primaryText.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    @ViewBuilder
    private func scenarioRow(_ scenario: ScenarioData) -> some View {
        let isSelected = selectedScenario?.id == scenario.id
        let hasMap = ScenarioMapStore.shared.hasMap(for: scenario.index)

        Button {
            selectedScenario = isSelected ? nil : scenario
        } label: {
            HStack(spacing: 12) {
                // Scenario number badge
                Text(scenario.index)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? .white : GlavenTheme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor : GlavenTheme.primaryText.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                    HStack(spacing: 6) {
                        if let monsters = scenario.monsters, !monsters.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "pawprint.fill")
                                    .font(.system(size: 8))
                                Text("\(monsters.count)")
                                    .font(.caption2)
                            }
                            .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        if !hasMap {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                Text("No map")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.body)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
