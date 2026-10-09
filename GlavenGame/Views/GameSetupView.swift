import SwiftUI

struct GameSetupView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.editionTheme) private var theme
    @State private var selectedLevel = 1
    @State private var selectedScenario: ScenarioData?
    @State private var scenarioSearch = ""
    @State private var sheetCharacter: GameCharacter?
    @State private var shopCharacter: GameCharacter?
    @State private var itemsCharacter: GameCharacter?
    @State private var showTableRules = false
    @State private var enhanceCharacter: GameCharacter?
    @State private var levelUpCharacter: GameCharacter?
    @State private var cardChoiceCharacter: GameCharacter?
    @State private var handCharacter: GameCharacter?
    @State private var questCharacter: GameCharacter?
    @State private var retiringCharacter: GameCharacter?
    /// A party member the player tapped in the recruit list in town, waiting for confirmation.
    @State private var dismissingCharacter: GameCharacter?
    @State private var showSanctuary = false
    @State private var showWorldMap = false
    @State private var showCampaign = false
    /// Events to resolve before setting out, in order; the first is showing.
    @State private var events: [EventCardManager.Deck] = []
    /// Set out for this scenario once the events are resolved.
    @State private var settingOutFor: ScenarioData?
    /// Choosing battle goals, the last step before setting out.
    @State private var choosingGoals = false

    enum RecruitTap: Equatable { case add, remove, confirmDismissal }

    /// What tapping a row of the recruit list does: before the first scenario a party member's
    /// row takes them out again; in town it asks first, since everything they earned goes too.
    static func recruitTap(isAdded: Bool, inTown: Bool) -> RecruitTap {
        guard isAdded else { return .add }
        return inTown ? .confirmDismissal : .remove
    }

    /// Once the party has played, this is the town between scenarios.
    /// What the party can do in town now, so a tip comes up as soon as something new can be.
    private var townLearningKey: String {
        let manager = gameManager.characterManager
        let party = gameManager.game.characters.filter { !$0.absent }.map { character in
            "\(character.id):\(manager.canLevelUp(character)):\(manager.perksAvailable(for: character)):"
                + "\(character.personalQuest ?? "-"):\(character.loot > 0)"
        }
        return "\(gameManager.game.learningMode)|" + party.joined(separator: ",")
    }

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

    /// The scenario to preselect: the only one available, if there's just one.
    static func onlyChoice(_ scenarios: [ScenarioData]) -> ScenarioData? {
        scenarios.count == 1 ? scenarios.first : nil
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
        GeometryReader { geo in
            let compact = geo.size.width < 1300
            VStack(spacing: 0) {
                topBar
                HStack(alignment: .top, spacing: 16) {
                    partyPanel
                        .frame(width: compact ? 350 : 400)
                    scenarioPanel
                    scenarioListPanel
                        .frame(width: compact ? 240 : 280)
                }
                .padding(16)
            }
        }
        .background(BoardTheme.sheet.ignoresSafeArea())
        // With only one scenario to play (a new campaign's Black Barrow), it's chosen.
        .onAppear {
            if selectedScenario == nil { selectedScenario = Self.onlyChoice(availableScenarios) }
        }
        .overlay {
            if showSanctuary {
                SanctuarySheet { showSanctuary = false }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let character = questCharacter {
                QuestPicker(character: character) { questCharacter = nil }
                    .transition(.opacity)
            }
        }
        .confirmationDialog(dismissingCharacter.map { "Dismiss \(GameText.characterName($0, labels: gameManager.editionStore))?" } ?? "",
                            isPresented: Binding(get: { dismissingCharacter != nil },
                                                 set: { if !$0 { dismissingCharacter = nil } }),
                            titleVisibility: .visible) {
            if let character = dismissingCharacter {
                Button("Dismiss for Good", role: .destructive) {
                    gameManager.characterManager.removeCharacter(character)
                    dismissingCharacter = nil
                }
            }
            Button("Keep Them", role: .cancel) { dismissingCharacter = nil }
        } message: {
            Text("They leave the party with their experience, gold, items and perks. This can't be undone.")
        }
        .confirmationDialog(retireTitle, isPresented: Binding(
            get: { retiringCharacter != nil }, set: { if !$0 { retiringCharacter = nil } }
        ), titleVisibility: .visible) {
            Button("Retire", role: .destructive) {
                if let character = retiringCharacter { gameManager.characterManager.retireCharacter(character) }
            }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text("They leave the party for good. Their quest's reward is unlocked, and prosperity rises.")
        }
        .overlay {
            if choosingGoals {
                BattleGoalPicker(onDone: departure)
                    .transition(.opacity)
            }
        }
        .modifier(TownLearning(key: townLearningKey))
        .overlay {
            if let character = sheetCharacter {
                CharacterSheetView(character: character,
                                   onShop: { shopCharacter = character },
                                   onDone: { sheetCharacter = nil })
                    .id(character.id)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let character = shopCharacter {
                ItemShopSheet(character: character) { shopCharacter = nil }
                    .id(character.id)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let deck = events.first {
                EventSheet(deck: deck, onDone: { finishEvent(deck) }, onClose: closeEvents)
                    .id("\(deck)-\(events.count)")
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showTableRules) {
            TableRulesSheet()
        }
        .sheet(item: $itemsCharacter) { character in
            ItemLoadoutSheet(character: character)
        }
        .sheet(item: $enhanceCharacter) { character in
            EnhancementSheet(character: character)
        }
        .sheet(item: $cardChoiceCharacter) { character in
            LevelUpCardSheet(character: character)
        }
        .sheet(item: $handCharacter) { character in
            HandSheet(character: character)
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
                if let character = levelUpCharacter, gameManager.characterManager.levelUp(character) {
                    cardChoiceCharacter = character   // then pick the new level's card
                }
            }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text("More hit points, a perk to take, and a new ability card to choose.")
        }
    }

    /// Before setting out: the city event owed for this visit, then a road event if the way to the
    /// scenario is by road (GH p.38).
    private func setOut(for scenario: ScenarioData) {
        var queue: [EventCardManager.Deck] = []
        if gameManager.game.events.cityEventDue { queue.append(.city) }
        if gameManager.eventCardManager.needsRoadEvent(for: scenario) { queue.append(.road) }
        settingOutFor = scenario
        if queue.isEmpty { chooseGoals() } else {
            gameManager.prepareEvents(queue, departingFor: scenario)
            events = queue
        }
    }

    /// Deal battle goals, then set out once everyone has kept one.
    private func chooseGoals() {
        gameManager.scenarioManager.dealBattleGoals()
        gameManager.saveGame()   // the dealt goals are kept if the app quits before setting out
        withAnimation(.snappy) { choosingGoals = true }
    }

    private func departure() {
        choosingGoals = false
        guard let scenario = settingOutFor else { return }
        settingOutFor = nil
        gameManager.saveGame()
        gameManager.startScenarioOnBoard(scenario)
    }

    /// Put the events off: they stay due, and setting out waits until they're resolved.
    private func closeEvents() {
        events = []
        settingOutFor = nil
    }

    private func finishEvent(_ deck: EventCardManager.Deck) {
        if deck == .city { gameManager.game.events.cityEventDue = false }
        events.removeFirst()
        if events.isEmpty, settingOutFor != nil { chooseGoals() }
    }

    private var retireTitle: String {
        guard let character = retiringCharacter else { return "" }
        return "Retire \(GameText.characterName(character, labels: gameManager.editionStore))?"
    }

    /// Deal two quests (unless two are waiting already) and let the character keep one.
    private func chooseQuest(for character: GameCharacter) {
        if character.questChoices.isEmpty { gameManager.characterManager.dealQuests(to: character) }
        questCharacter = character
    }

    private var levelUpTitle: String {
        guard let character = levelUpCharacter else { return "" }
        return "\(GameText.characterName(character, labels: gameManager.editionStore)) to level \(character.level + 1)?"
    }

    private var prosperityLevel: Int { gameManager.game.prosperityLevel }

    private var party: [GameCharacter] { gameManager.game.characters.filter { !$0.absent } }

    // MARK: - Top bar

    /// Back to the menu, where the party is, the town's standing, and what can be done in town.
    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                gameManager.returnToMainMenu()
            } label: {
                Image(systemName: "chevron.left")
                    .font(BoardTheme.font(size: 16, weight: .semibold))
                    .foregroundStyle(BoardTheme.text)
                    .frame(width: 40, height: 40)
                    .background(BoardTheme.raised, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Main menu")
            VStack(alignment: .leading, spacing: 0) {
                Text(inTown ? "Gloomhaven" : "New Campaign")
                    .font(BoardTheme.display(24))
                    .foregroundStyle(BoardTheme.text)
                Text(Self.townSubtitle(scenariosPlayed: gameManager.game.completedScenarios.count, inTown: inTown))
                    .font(BoardTheme.font(size: 12, weight: .medium))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if inTown {
                TownChip(icon: "building.columns.fill", text: "Prosperity \(prosperityLevel)")
                TownChip(icon: "shield.lefthalf.filled", text: "Reputation \(gameManager.game.partyReputation)")
            }
            Spacer(minLength: 8)
            if gameManager.game.events.cityEventDue {
                Button("City Event", systemImage: "building.2.fill") {
                    gameManager.prepareEvents([.city])
                    events = [.city]
                }
                .buttonStyle(.boardPrimaryCompact)
            }
            if inTown {
                Button("Sanctuary", systemImage: "sun.max") { showSanctuary = true }
                    .buttonStyle(.boardQuietCompact)
            }
            Button("Campaign", systemImage: "book.closed") { showCampaign = true }
                .buttonStyle(.boardQuietCompact)
            Button("How to Play", systemImage: "book") { gameManager.boardCoordinator.openHowToPlay() }
                .buttonStyle(.boardQuietCompact)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(BoardTheme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(BoardTheme.border.opacity(0.5)).frame(height: 1) }
    }

    /// "Recruit your party and set out", or "In town · 3 scenarios played".
    /// A party back from a lost or abandoned scenario is in town, with nothing won yet.
    static func townSubtitle(scenariosPlayed: Int, inTown: Bool) -> String {
        guard scenariosPlayed > 0 else { return inTown ? "In town" : "Recruit your party and set out" }
        return "In town \u{00B7} \(scenariosPlayed) scenario\(scenariosPlayed == 1 ? "" : "s") played"
    }

    // MARK: - Party

    /// The party's cards, and the classes to recruit pinned at the bottom: adding someone never
    /// moves the class tiles, so a second tap can't land on the wrong class.
    private var partyPanel: some View {
        TownPanel {
            TownPanelHeading(title: "Party", detail: party.isEmpty ? "CHOOSE 2\u{2013}4" : "\(party.count) OF 4")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(party, id: \.id) { character in
                        TownPartyRow(character: character,
                                     onSheet: { sheetCharacter = character },
                                     onShop: { shopCharacter = character },
                                     onItems: { itemsCharacter = character },
                                     onEnhance: { enhanceCharacter = character },
                                     onLevelUp: { levelUpCharacter = character },
                                     onChooseCard: { cardChoiceCharacter = character },
                                     onHand: { handCharacter = character },
                                     onChooseQuest: { chooseQuest(for: character) },
                                     onRetire: { retiringCharacter = character },
                                     onRemove: { remove(character) })
                    }
                    if party.isEmpty {
                        Text("Recruit two to four characters from the classes below.")
                            .font(BoardTheme.font(size: 14))
                            .foregroundStyle(BoardTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            recruitStrip
        }
    }

    private func remove(_ character: GameCharacter) {
        switch Self.recruitTap(isAdded: true, inTown: inTown) {
        case .confirmDismissal: dismissingCharacter = character
        default: gameManager.characterManager.removeCharacter(character)
        }
    }

    private var recruitStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TownSmallCaps(text: "Recruit")
                Spacer()
                let highest = gameManager.characterManager.highestStartingLevel
                if highest > 1 {
                    Text("at level").font(BoardTheme.font(size: 12)).foregroundStyle(BoardTheme.secondaryText)
                    ForEach(1...highest, id: \.self) { level in
                        Button { selectedLevel = level } label: {
                            Text("\(level)")
                                .font(BoardTheme.font(size: 12, weight: .semibold))
                                .foregroundStyle(selectedLevel == level ? BoardTheme.sheet : BoardTheme.text)
                                .frame(width: 26, height: 26)
                                .background(selectedLevel == level ? BoardTheme.brass : BoardTheme.raised, in: Circle())
                                .frame(width: 30, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Recruit at level \(level)")
                        .accessibilityAddTraits(selectedLevel == level ? .isSelected : [])
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(allCharacters) { recruitTile($0) }
                }
            }
        }
        .padding(.top, 4)
    }

    private func recruitTile(_ character: CharacterData) -> some View {
        let isAdded = existingNames.contains(character.name)
        let full = !isAdded && gameManager.game.characters.count >= 4
        let classColor = Color(hex: character.color ?? "#808080") ?? .gray
        let name = GameText.className(character.name, edition: edition, labels: gameManager.editionStore)
        let level = min(selectedLevel, gameManager.characterManager.highestStartingLevel)
        return Button {
            if isAdded {
                if let member = gameManager.game.characters.first(where: { $0.name == character.name }) { remove(member) }
            } else {
                guard gameManager.game.characters.count < 4 else { return }
                gameManager.characterManager.addCharacter(name: character.name, edition: edition, level: level)
                // A recruit chooses their personal quest straight away.
                if let recruit = gameManager.game.characters.first(where: { $0.name == character.name }) {
                    chooseQuest(for: recruit)
                }
            }
        } label: {
            VStack(spacing: 4) {
                ThumbnailImage(image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                               size: 48, cornerRadius: 24, fallbackColor: classColor)
                    .overlay(Circle().stroke(isAdded ? classColor : BoardTheme.border.opacity(0.6), lineWidth: isAdded ? 2.5 : 1))
                    .overlay(alignment: .topTrailing) {
                        if isAdded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(BoardTheme.font(size: 16, weight: .bold))
                                .foregroundStyle(BoardTheme.brass, BoardTheme.sheet)
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(name)
                    .font(BoardTheme.font(size: 12, weight: isAdded ? .semibold : .regular))
                    .foregroundStyle(isAdded ? BoardTheme.text : BoardTheme.secondaryText)
                    .lineLimit(1)
                Text("\u{2665}\(character.healthForLevel(level)) \u{00B7} \(character.resolvedHandSize) cards")
                    .font(BoardTheme.font(size: 11).monospacedDigit())
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: 84)
            .padding(.vertical, 8)
            .background(isAdded ? classColor.opacity(0.14) : BoardTheme.raised.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(full)
        .opacity(full ? 0.4 : 1)
        .accessibilityLabel("\(name), \(character.healthForLevel(level)) hit points, \(character.resolvedHandSize) cards")
        .accessibilityValue(isAdded ? "in the party" : "")
        .accessibilityHint(isAdded ? "Takes them out of the party" : "Adds them to the party")
    }

    // MARK: - The scenario

    /// The chosen scenario: where it is on the map, its goal, monsters and rewards; then the
    /// difficulty, and Set Out.
    private var scenarioPanel: some View {
        TownPanel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let scenario = selectedScenario {
                        scenarioDetail(scenario)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "map").font(BoardTheme.font(size: 34)).foregroundStyle(BoardTheme.brass)
                            Text("Choose a scenario").font(BoardTheme.display(28)).foregroundStyle(BoardTheme.text)
                            Text("From the list, or on the World Map.")
                                .font(BoardTheme.font(size: 14)).foregroundStyle(BoardTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(BoardTheme.border.opacity(0.4)).frame(height: 1)
            settingsRows
            HStack {
                Spacer()
                setOutButton
            }
        }
    }

    @ViewBuilder
    private func scenarioDetail(_ scenario: ScenarioData) -> some View {
        let brief = ScenarioBrief.make(for: scenario, labels: gameManager.editionStore)
        ScenarioBanner(scenario: scenario, edition: edition)
        VStack(alignment: .leading, spacing: 2) {
            TownSmallCaps(text: "Next scenario", lit: true)
            Text(brief.title)
                .font(BoardTheme.display(36))
                .foregroundStyle(BoardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let map = brief.map {
                Text(map).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
            }
        }
        Label(brief.goal, systemImage: "scope")
            .font(BoardTheme.font(size: 16, weight: .semibold))
            .foregroundStyle(BoardTheme.text)
            .fixedSize(horizontal: false, vertical: true)
        if !brief.monsters.isEmpty {
            TownSmallCaps(text: "Monsters")
            FlowLayout(spacing: 10) {
                ForEach(brief.monsters, id: \.self) { monster in
                    let name = GameText.monsterName(monster, edition: brief.edition, labels: gameManager.editionStore)
                    VStack(spacing: 4) {
                        ThumbnailImage(image: ImageLoader.monsterThumbnail(edition: brief.edition, name: monster),
                                       size: 48, cornerRadius: 24, fallbackColor: BoardTheme.raised)
                            .overlay(Circle().stroke(BoardTheme.border, lineWidth: 1))
                        Text(name)
                            .font(BoardTheme.font(size: 11))
                            .foregroundStyle(BoardTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(width: 80)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(name)
                }
            }
        }
        if !brief.rewards.isEmpty {
            TownSmallCaps(text: "Rewards")
            Text(brief.rewards.joined(separator: " \u{00B7} "))
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Difficulty, the scenario level it gives, the table rules and learning mode.
    private var settingsRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                TownSmallCaps(text: "Difficulty")
                HStack(spacing: 0) {
                    ForEach(DifficultyMode.allCases, id: \.self) { mode in
                        let selected = gameManager.game.difficulty == mode
                        Button { gameManager.game.difficulty = mode } label: {
                            Text(mode.shortLabel)
                                .font(BoardTheme.font(size: 13, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(selected ? BoardTheme.sheet : BoardTheme.text)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(selected ? BoardTheme.brass : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(mode.description)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(BoardTheme.raised, in: Capsule())
                .fixedSize()
            }
            difficultyHint
            HStack(spacing: 16) {
                Button { showTableRules = true } label: {
                    Label(TableRulesSheet.summary(gameManager.game.tableRules), systemImage: "list.bullet.rectangle")
                        .font(BoardTheme.font(size: 13))
                        .foregroundStyle(gameManager.game.tableRules == TableRules() ? BoardTheme.secondaryText : BoardTheme.brass)
                        .lineLimit(1)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                learningModeRow
            }
        }
    }

    /// Set out: the events owed, then battle goals, then the board.
    private var setOutButton: some View {
        Button {
            if let scenario = selectedScenario { setOut(for: scenario) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Set Out").font(BoardTheme.display(24))
                    Text(setOutDetail)
                        .font(BoardTheme.font(size: 11, weight: .medium))
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(canStart ? BoardTheme.sheet : BoardTheme.secondaryText)
            .padding(.horizontal, 26)
            .frame(minHeight: 56)
            .background(canStart ? BoardTheme.brass : BoardTheme.raised, in: Capsule())
            .shadow(color: canStart ? BoardTheme.brass.opacity(0.35) : .clear, radius: 10, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("Set Out")
        .accessibilityHint(setOutDetail)
    }

    private var setOutDetail: String {
        Self.setOutDetail(hasParty: !gameManager.game.characters.isEmpty, scenario: selectedScenario != nil,
                          cityEvent: gameManager.game.events.cityEventDue,
                          roadEvent: selectedScenario.map { gameManager.eventCardManager.needsRoadEvent(for: $0) } ?? false)
    }

    /// What Set Out leads to: "City event, road event, then battle goals"; or what's missing.
    static func setOutDetail(hasParty: Bool, scenario: Bool, cityEvent: Bool, roadEvent: Bool) -> String {
        guard hasParty else { return "Recruit your party first" }
        guard scenario else { return "Choose a scenario first" }
        let events = [cityEvent ? "city event" : nil, roadEvent ? "road event" : nil].compactMap { $0 }
        guard !events.isEmpty else { return "Battle goals, then the board" }
        let text = events.joined(separator: ", ") + ", then battle goals"
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Scenario list

    private var scenarioListPanel: some View {
        TownPanel {
            TownPanelHeading(title: "Scenarios", detail: "\(availableScenarios.count) OPEN")
            if availableScenarios.count > 5 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(BoardTheme.secondaryText)
                    TextField("Search", text: $scenarioSearch)
                        .textFieldStyle(.plain)
                        .foregroundStyle(BoardTheme.text)
                    if !scenarioSearch.isEmpty {
                        Button { scenarioSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(BoardTheme.secondaryText)
                            .accessibilityLabel("Clear the search")
                    }
                }
                .font(BoardTheme.font(size: 14))
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.small))
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredScenarios) { scenarioRow($0) }
                }
            }
            .frame(maxHeight: .infinity)
            Button("World Map", systemImage: "map") { showWorldMap = true }
                .buttonStyle(.boardQuietCompact)
                .frame(maxWidth: .infinity)
        }
    }

    private func scenarioRow(_ scenario: ScenarioData) -> some View {
        let isSelected = selectedScenario?.id == scenario.id
        let hasMap = ScenarioMapStore.shared.hasMap(for: scenario.index)
        return Button {
            selectedScenario = scenario
        } label: {
            HStack(spacing: 10) {
                Text(scenario.index)
                    .font(BoardTheme.font(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.brass)
                    .minimumScaleFactor(0.7)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? BoardTheme.sheet.opacity(0.2) : BoardTheme.raised, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.name)
                        .font(BoardTheme.font(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.text)
                        .lineLimit(1)
                    if !hasMap {
                        Label("No map", systemImage: "exclamationmark.triangle.fill")
                            .font(BoardTheme.font(size: 11))
                            .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.defeat)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 46)
            .background(isSelected ? BoardTheme.brass : Color.clear, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scenario \(scenario.index), \(scenario.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Learning mode: tips the first time each rule comes up, and "Why?" on what the monsters
    /// do. On for a player's first campaign.
    private var learningModeRow: some View {
        Toggle(isOn: Binding(get: { gameManager.game.learningMode },
                             set: { gameManager.setLearningMode($0) })) {
            Label("Learning mode", systemImage: "lightbulb.fill")
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(gameManager.game.learningMode ? BoardTheme.brass : BoardTheme.secondaryText)
        }
        .toggleStyle(.switch)
        .tint(BoardTheme.brass)
        .fixedSize()
        .accessibilityHint("Explains each rule the first time it comes up, and \u{201C}Why?\u{201D} on what the monsters do")
    }

    /// Always present, so the rows below never move as the party changes.
    private var difficultyHint: some View {
        ScenarioLevelLine(text: Self.difficultyHint(for: gameManager))
    }

    static func difficultyHint(for gameManager: GameManager) -> String {
        guard !gameManager.game.characters.isEmpty else {
            return "Add characters to set the scenario level"
        }
        return "Scenario level \(gameManager.levelManager.scenarioLevel()) · \(gameManager.game.difficulty.description)"
    }
}

/// The line under the difficulty buttons. It always takes one line of space, so adding the first
/// character doesn't push the class list down.
struct ScenarioLevelLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(BoardTheme.font(size: 12))
            .foregroundStyle(BoardTheme.secondaryText)
            .lineLimit(1)
    }
}
