import SwiftUI

struct GameSetupView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.editionTheme) private var theme
    @State private var selectedLevel = 1
    @State private var selectedScenario: ScenarioData?
    @State private var scenarioSearch = ""
    @State private var sheetCharacter: GameCharacter?
    @State private var shopCharacter: GameCharacter?
    @State private var levelUpCharacter: GameCharacter?
    @State private var showWorldMap = false
    @State private var showCampaign = false

    /// Once the party has played, this is the town between scenarios.
    private var inTown: Bool {
        !gameManager.game.completedScenarios.isEmpty || !gameManager.game.campaignLog.isEmpty
    }

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

            // Top bar: back to the menu, the town and its standing, the campaign
            VStack {
                HStack(spacing: 12) {
                    Button {
                        gameManager.returnToMainMenu()
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
                    if inTown {
                        Text("Gloomhaven")
                            .font(theme.titleFont(size: 28))
                            .foregroundStyle(BoardTheme.text)
                        townChip("Prosperity \(prosperityLevel)", icon: "building.columns.fill")
                        townChip("Reputation \(gameManager.game.partyReputation)", icon: "shield.lefthalf.filled")
                    }
                    Button("Campaign", systemImage: "book.closed.fill") { showCampaign = true }
                        .buttonStyle(.bordered)
                        .tint(BoardTheme.brass)
                        .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.top, 8)
                Spacer()
            }
        }
        .sheet(item: $sheetCharacter) { character in
            CharacterSheetView(character: character)
        }
        .sheet(item: $shopCharacter) { character in
            ItemShopSheet(character: character)
        }
        .sheet(isPresented: $showWorldMap) {
            WorldMapView { scenario in selectedScenario = scenario }
        }
        .sheet(isPresented: $showCampaign) {
            PartySheetView()
        }
        .confirmationDialog(levelUpTitle, isPresented: Binding(
            get: { levelUpCharacter != nil }, set: { if !$0 { levelUpCharacter = nil } }
        ), titleVisibility: .visible) {
            Button("Level Up") {
                if let character = levelUpCharacter { gameManager.characterManager.levelUp(character) }
            }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text("More hit points, a perk to take, and the next level's ability cards.")
        }
    }

    private var levelUpTitle: String {
        guard let character = levelUpCharacter else { return "" }
        return "\(GameText.characterName(character, labels: gameManager.editionStore)) to level \(character.level + 1)?"
    }

    private var prosperityLevel: Int { gameManager.game.prosperityLevel }

    private func townChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BoardTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(BoardTheme.panel, in: Capsule())
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

            // The party, then the classes to recruit from
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(gameManager.game.characters.filter { !$0.absent }, id: \.id) { character in
                        TownPartyRow(character: character,
                                     onSheet: { sheetCharacter = character },
                                     onShop: { shopCharacter = character },
                                     onLevelUp: { levelUpCharacter = character })
                            .padding(.bottom, 6)
                    }
                    if !gameManager.game.characters.isEmpty {
                        Text("RECRUIT")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BoardTheme.brass)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.top, 6)
                    }
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

    /// Always present, so adding the first character doesn't push the rows below it down
    /// (a second tap would land on the wrong character).
    private var difficultyHint: some View {
        ScenarioLevelLine(text: Self.difficultyHint(for: gameManager))
    }

    static func difficultyHint(for gameManager: GameManager) -> String {
        guard !gameManager.game.characters.isEmpty else {
            return "Add characters to set the scenario level"
        }
        return "Scenario level \(gameManager.levelManager.scenarioLevel()) · \(gameManager.game.difficulty.description)"
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
                Button("World Map", systemImage: "map") { showWorldMap = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(BoardTheme.brass)
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

/// The line under the difficulty buttons. It always takes one line of space, so adding the first
/// character doesn't push the class list down.
struct ScenarioLevelLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(GlavenTheme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }
}
