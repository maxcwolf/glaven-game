import SwiftUI

// MARK: - Sheet Type Enum

/// All sheets that can be presented from GameBoardView, consolidated into a single
/// enum to avoid SwiftUI's "parentEnvironment != nil" crash from too many `.sheet()` modifiers.
enum GameBoardSheet: String, Identifiable {
    var id: String { rawValue }

    // Add figures
    case addCharacter, addMonster, addObjective
    // Scenario
    case scenarioSelection, worldMap, scenarioMap, randomScenario, randomMonsterCard
    case conclusionSuccess, conclusionFailure, treasureLoot
    // Party & campaign
    case partySheet, itemBrowser, randomItem, partyTreasures
    case scenarioChart
    // Game management
    case saveSlots, attackModifierSelect, actionHistory
    // Settings & info
    case preferences, keyboardShortcuts, about, debug
    // Standalone tools
    case amTool, lootDeckTool, initiativeTool, decksViewer
    case treasuresTool, randomMonsterCardsTool
    // Editors
    case editionEditor, characterEditor, monsterEditor, deckEditor, actionEditor
}

struct GameBoardView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var activeSheet: GameBoardSheet?

    var body: some View {
        NavigationStack {
            GameBoardContent(activeSheet: $activeSheet)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        HamburgerMenuView(activeSheet: $activeSheet)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 12) {
                            PlusMenuView(activeSheet: $activeSheet)
                            GearMenuView(activeSheet: $activeSheet)
                        }
                    }
                }
                #if os(iOS)
                .sheet(item: Binding(
                    get: { activeSheet == .scenarioMap ? nil : activeSheet },
                    set: { activeSheet = $0 }
                )) { sheet in
                    sheetContent(for: sheet)
                }
                .fullScreenCover(item: Binding(
                    get: { activeSheet == .scenarioMap ? activeSheet : nil },
                    set: { activeSheet = $0 }
                )) { sheet in
                    sheetContent(for: sheet)
                }
                #else
                .sheet(item: $activeSheet) { sheet in
                    sheetContent(for: sheet)
                }
                #endif
                .focusable()
                .onKeyPress(.space) {
                    handleNextRound()
                    return .handled
                }
                .onKeyPress(characters: .init(charactersIn: "s")) { press in
                    if press.modifiers.contains(.command) {
                        gameManager.saveGame()
                        return .handled
                    }
                    return .ignored
                }
        }
    }

    // MARK: - Sheet Content Router

    @ViewBuilder
    private func sheetContent(for sheet: GameBoardSheet) -> some View {
        switch sheet {
        // Add figures
        case .addCharacter: AddCharacterSheet()
        case .addMonster: AddMonsterSheet()
        case .addObjective: AddObjectiveSheet()
        // Scenario
        case .scenarioSelection: ScenarioSelectionSheet()
        case .worldMap: WorldMapView()
        case .scenarioMap: ScenarioMapSheetWrapper()
        case .randomScenario: RandomScenarioSheet()
        case .randomMonsterCard: RandomMonsterCardSheet()
        case .conclusionSuccess: ScenarioConclusionSheet(success: true)
        case .conclusionFailure: ScenarioConclusionSheet(success: false)
        case .treasureLoot: TreasureLootSheet()
        // Party & campaign
        case .partySheet: PartySheetView()
        case .itemBrowser: ItemBrowserSheet()
        case .randomItem: RandomItemSheet()
        case .partyTreasures: PartyTreasuresSheet()
        case .scenarioChart: ScenarioChartSheet()
        // Game management
        case .saveSlots: SaveSlotsSheet()
        case .attackModifierSelect: AttackModifierSelectSheet()
        case .actionHistory: ActionHistorySheet()
        // Settings & info
        case .preferences: PreferencesSheet()
        case .keyboardShortcuts: KeyboardShortcutsSheet()
        case .about: AboutSheet()
        case .debug: DebugSheet()
        // Standalone tools
        case .amTool: AttackModifierToolSheet()
        case .lootDeckTool: LootDeckToolSheet()
        case .initiativeTool: InitiativeToolSheet()
        case .decksViewer: DecksViewerSheet()
        case .treasuresTool: TreasuresToolSheet()
        case .randomMonsterCardsTool: RandomMonsterCardsToolSheet()
        // Editors
        case .editionEditor: EditionEditorSheet()
        case .characterEditor: CharacterEditorSheet()
        case .monsterEditor: MonsterEditorSheet()
        case .deckEditor: DeckEditorSheet()
        case .actionEditor: ActionEditorSheet()
        }
    }

    // MARK: - Helpers

    private func handleNextRound() {
        if gameManager.game.state == .draw {
            if gameManager.roundManager.drawAvailable() {
                gameManager.roundManager.nextGameState()
            }
        } else {
            gameManager.roundManager.nextGameState()
        }
    }
}

// MARK: - Main Content (isolated observation scope)

/// Extracted to limit @Observable tracking — only re-evaluates when theme/animation state changes,
/// not when activeSheet changes in the parent.
private struct GameBoardContent: View {
    @Environment(GameManager.self) private var gameManager
    @Binding var activeSheet: GameBoardSheet?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            HintBarView(activeSheet: $activeSheet)
            FigureListView(activeSheet: $activeSheet)
            FooterView()
        }
        .background(GlavenTheme.background)
        .id("\(gameManager.settingsManager.lightMode)-\(gameManager.settingsManager.effectiveTheme(edition: gameManager.game.edition))")
        .animateIf(gameManager.settingsManager.animations, .easeInOut(duration: 0.3), value: gameManager.game.state)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Hint Bar (isolated observation scope)

/// Extracted so hintState computation (which reads characters, scenario, monsters, state)
/// doesn't widen GameBoardView's observation scope.
private struct HintBarView: View {
    @Environment(GameManager.self) private var gameManager
    @Binding var activeSheet: GameBoardSheet?

    private var hintState: HintState {
        let hasCharacters = !gameManager.game.characters.isEmpty
        let hasScenario = gameManager.game.scenario != nil
        let hasMonsters = !gameManager.game.monsters.isEmpty
        let isDrawPhase = gameManager.game.state == .draw

        if !hasCharacters {
            return .addCharacters
        } else if !hasScenario && !hasMonsters {
            return .setScenario
        } else if isDrawPhase && gameManager.game.characters.contains(where: {
            !$0.exhausted && !$0.absent && !$0.longRest && $0.initiative <= 0
        }) {
            return .drawInitiative
        } else {
            return .none
        }
    }

    var body: some View {
        if hintState != .none {
            Button {
                switch hintState {
                case .addCharacters:
                    activeSheet = .addCharacter
                case .setScenario:
                    activeSheet = .scenarioSelection
                case .drawInitiative, .none, .addMonsters:
                    break
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: hintState.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(GlavenTheme.accentText.opacity(0.2))
                        .clipShape(Circle())
                    Text(hintState.message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if hintState != .drawInitiative {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.accentText.opacity(0.6))
                    }
                }
                .foregroundStyle(GlavenTheme.accentText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [GlavenTheme.accentText.opacity(0.12), GlavenTheme.accentText.opacity(0.05)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(hintState == .drawInitiative)
            .accessibilityLabel(hintState.message)
            .accessibilityHint(hintState == .drawInitiative ? "Set initiative for each character first" : "Double tap to \(hintState.message.lowercased())")
        }
    }
}

// MARK: - Figure List (isolated observation scope)

/// Extracted so character/monster sorting only runs when figures actually change,
/// not on every GameBoardView body re-evaluation.
private struct FigureListView: View {
    @Environment(GameManager.self) private var gameManager
    @Binding var activeSheet: GameBoardSheet?
    @GestureState private var pinchScale: CGFloat = 1.0
    private let mapStore = ScenarioMapStore.shared

    private var sortedCharacters: [GameCharacter] {
        let chars = gameManager.game.characters
        if gameManager.game.state == .draw {
            return chars
        }
        return chars.sorted { $0.effectiveInitiative < $1.effectiveInitiative }
    }

    private var sortedMonsters: [AnyFigure] {
        gameManager.game.figures.filter {
            switch $0 {
            case .character:
                return false
            case .monster(let monster):
                return !monster.aliveEntities.isEmpty
            case .objective:
                return true
            }
        }.sorted { a, b in
            a.effectiveInitiative < b.effectiveInitiative
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Scenario setup (before first round)
                if gameManager.game.scenario != nil && gameManager.game.round == 0 {
                    ScenarioSetupView()
                }

                ForEach(sortedCharacters, id: \.id) { character in
                    CharacterView(character: character)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .draggable(character.id) {
                            Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                                .padding(8)
                                .background(GlavenTheme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            guard let sourceID = droppedIDs.first else { return false }
                            reorderCharacter(sourceID: sourceID, targetID: character.id)
                            return true
                        } isTargeted: { _ in }
                }

                ForEach(sortedMonsters) { figure in
                    switch figure {
                    case .monster(let monster):
                        MonsterView(monster: monster)
                    case .objective(let objective):
                        ObjectiveContainerView(objective: objective)
                    case .character:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .scaleEffect(pinchScale)
        }
        .gesture(
            MagnifyGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    let newScale = gameManager.settingsManager.uiScale * value.magnification
                    gameManager.settingsManager.uiScale = max(0.85, min(1.5, newScale))
                }
        )
        .overlay(alignment: .bottomTrailing) {
            if let scenario = gameManager.game.scenario,
               mapStore.hasMap(for: scenario.data.index) {
                VStack(spacing: 12) {
                    // Play on Board button — visible when scenario + characters exist but board isn't started
                    if gameManager.boardCoordinator.boardScene == nil,
                       !gameManager.game.activeCharacters.isEmpty {
                        Button {
                            gameManager.enterBoard()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 14))
                                Text("Play on Board")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.green.opacity(0.85))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                    }

                    Button {
                        activeSheet = .scenarioMap
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(GlavenTheme.accentText.opacity(0.85))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                }
                .padding(16)
            }
        }
    }

    private func reorderCharacter(sourceID: String, targetID: String) {
        guard sourceID != targetID else { return }
        let figures = gameManager.game.figures
        let srcFigureID = "char-\(sourceID)"
        let tgtFigureID = "char-\(targetID)"
        guard let sourceIdx = figures.firstIndex(where: { $0.id == srcFigureID }),
              let targetIdx = figures.firstIndex(where: { $0.id == tgtFigureID })
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            gameManager.game.figures.move(fromOffsets: IndexSet(integer: sourceIdx), toOffset: targetIdx > sourceIdx ? targetIdx + 1 : targetIdx)
        }
    }
}

// MARK: - Hamburger Menu (isolated observation scope)

/// Extracted so the many gameManager property accesses (edition, scenario, settings)
/// don't widen GameBoardView's observation scope.
private struct HamburgerMenuView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.showSidebar) private var showSidebarBinding
    @Binding var activeSheet: GameBoardSheet?

    var body: some View {
        Menu {
            // Scenario
            Menu {
                if gameManager.game.scenario == nil {
                    Button { activeSheet = .scenarioSelection } label: {
                        Label("Select Scenario", systemImage: "map")
                    }
                }
                Button { activeSheet = .worldMap } label: {
                    Label("World Map", systemImage: "map.fill")
                }
                Button { activeSheet = .randomScenario } label: {
                    Label("Random Scenario", systemImage: "dice.fill")
                }
                if !gameManager.game.monsters.isEmpty {
                    Button { activeSheet = .randomMonsterCard } label: {
                        Label("Random Monster Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                }
                if gameManager.game.scenario != nil {
                    Button { activeSheet = .treasureLoot } label: {
                        Label("Treasures", systemImage: "diamond.fill")
                    }
                    Divider()
                    Button { activeSheet = .conclusionSuccess } label: {
                        Label("Scenario Victory", systemImage: "checkmark.seal")
                    }
                    Button { activeSheet = .conclusionFailure } label: {
                        Label("Scenario Defeat", systemImage: "xmark.seal")
                    }
                }
            } label: {
                Label("Scenario", systemImage: "map")
            }

            // Party & campaign
            Button { activeSheet = .partySheet } label: {
                Label("Party Sheet", systemImage: "person.3")
            }
            Button { activeSheet = .itemBrowser } label: {
                Label("Item Browser", systemImage: "bag.fill")
            }
            Button { activeSheet = .randomItem } label: {
                Label("Random Item", systemImage: "gift")
            }
            Button { activeSheet = .partyTreasures } label: {
                Label("Party Treasures", systemImage: "diamond")
            }
            Button { activeSheet = .scenarioChart } label: {
                Label("Scenario Chart", systemImage: "point.3.connected.trianglepath.dotted")
            }

            Divider()

            // Game management
            Button { activeSheet = .saveSlots } label: {
                Label("Save / Load", systemImage: "tray.full")
            }
            Button { activeSheet = .attackModifierSelect } label: {
                Label("AM Decks", systemImage: "rectangle.stack.fill")
            }
            Button { activeSheet = .actionHistory } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            if let sidebarBinding = showSidebarBinding {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        sidebarBinding.wrappedValue.toggle()
                    }
                } label: {
                    Label(sidebarBinding.wrappedValue ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")
                }
            }

            Divider()

            Button(role: .destructive) { gameManager.newGame() } label: {
                Label("New Game", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }
}

// MARK: - Plus Menu

private struct PlusMenuView: View {
    @Binding var activeSheet: GameBoardSheet?

    var body: some View {
        Menu {
            Button { activeSheet = .addCharacter } label: {
                Label("Add Character", systemImage: "person.badge.plus")
            }
            Button { activeSheet = .addMonster } label: {
                Label("Add Monster", systemImage: "pawprint.fill")
            }
            Button { activeSheet = .addObjective } label: {
                Label("Add Objective", systemImage: "target")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }
}

// MARK: - Gear Menu

private struct GearMenuView: View {
    @Binding var activeSheet: GameBoardSheet?

    var body: some View {
        Menu {
            Button { activeSheet = .preferences } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button { activeSheet = .keyboardShortcuts } label: {
                Label("Shortcuts", systemImage: "keyboard")
            }
            Button { activeSheet = .about } label: {
                Label("About", systemImage: "info.circle")
            }
            Button { activeSheet = .debug } label: {
                Label("Debug", systemImage: "ant")
            }

            Divider()

            // Standalone tools
            Menu {
                Button { activeSheet = .amTool } label: {
                    Label("AM Deck Builder", systemImage: "rectangle.stack.badge.plus")
                }
                Button { activeSheet = .lootDeckTool } label: {
                    Label("Loot Deck", systemImage: "gift.fill")
                }
                Button { activeSheet = .initiativeTool } label: {
                    Label("Initiative Tracker", systemImage: "number.circle")
                }
                Button { activeSheet = .decksViewer } label: {
                    Label("Decks Viewer", systemImage: "rectangle.portrait.on.rectangle.portrait.fill")
                }
                Button { activeSheet = .treasuresTool } label: {
                    Label("Treasures", systemImage: "diamond.fill")
                }
                Button { activeSheet = .randomMonsterCardsTool } label: {
                    Label("Random Monster Cards", systemImage: "dice.fill")
                }
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }

            // Editors
            Menu {
                Button { activeSheet = .editionEditor } label: {
                    Label("Edition Editor", systemImage: "book.closed.fill")
                }
                Button { activeSheet = .characterEditor } label: {
                    Label("Character Editor", systemImage: "person.text.rectangle")
                }
                Button { activeSheet = .monsterEditor } label: {
                    Label("Monster Editor", systemImage: "pawprint")
                }
                Button { activeSheet = .deckEditor } label: {
                    Label("Deck Editor", systemImage: "rectangle.stack")
                }
                Button { activeSheet = .actionEditor } label: {
                    Label("Action Editor", systemImage: "bolt.circle")
                }
            } label: {
                Label("Editors", systemImage: "pencil.and.outline")
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }
}

private enum HintState {
    case addCharacters
    case setScenario
    case addMonsters
    case drawInitiative
    case none

    var message: String {
        switch self {
        case .addCharacters: return "Add Characters"
        case .setScenario: return "Set Scenario"
        case .addMonsters: return "Add Monsters"
        case .drawInitiative: return "Choose ability cards, set initiative, click Draw"
        case .none: return ""
        }
    }

    var icon: String {
        switch self {
        case .addCharacters: return "person.badge.plus"
        case .setScenario: return "map"
        case .addMonsters: return "pawprint.fill"
        case .drawInitiative: return "number.circle"
        case .none: return ""
        }
    }
}
