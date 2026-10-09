import SwiftUI

/// The campaign at a glance, in the board's look: the town's prosperity and the party's
/// reputation, achievements, the scenarios open and won, who's in the party, and what has
/// happened so far.
struct PartySheetView: View {
    @Environment(GameManager.self) private var gameManager
    var onDone: () -> Void = {}
    @State private var renaming = false
    @State private var nameText = ""
    @State private var showStatistics = false

    private var game: GameState { gameManager.game }
    private var edition: String { game.edition ?? "gh" }
    private var store: EditionDataStore { gameManager.editionStore }

    var body: some View {
        TownDialog(title: game.partyName.isEmpty ? "Campaign" : game.partyName, subtitle: subtitle, onDone: onDone) {
            Button("Rename", systemImage: "pencil") {
                nameText = game.partyName
                renaming = true
            }
            .buttonStyle(.boardQuietCompact)
            Button("Statistics", systemImage: "chart.bar") { showStatistics = true }
                .buttonStyle(.boardQuietCompact)
        } content: {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 14) { prosperity; reputation; achievements }
                }
                .frame(width: 360)
                ScrollView {
                    VStack(spacing: 14) { scenarios; party }
                }
                ScrollView { log }
                    .frame(width: 300)
            }
            .padding(18)
        }
        .alert("Name the Party", isPresented: $renaming) {
            TextField("Party name", text: $nameText)
            Button("Save") { gameManager.game.partyName = nameText.trimmingCharacters(in: .whitespacesAndNewlines) }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if showStatistics {
                PartyStatisticsSheet(onDone: { showStatistics = false })
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Words

    /// "Campaign · 2 scenarios won · begun Oct 8".
    private var subtitle: String {
        var parts = [game.partyName.isEmpty ? "Unnamed party" : "Campaign", Self.wonLine(won.count)]
        if let first = game.campaignLog.first?.timestamp {
            parts.append("begun \(first.formatted(.dateTime.month(.abbreviated).day()))")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    static func wonLine(_ count: Int) -> String {
        count == 0 ? "no scenarios won yet" : "\(count) scenario\(count == 1 ? "" : "s") won"
    }

    static let prosperityThresholds = [0, 4, 9, 15, 22, 30, 39, 50, 64]

    /// "3 to level 3", or "Highest level".
    static func prosperityToNext(checkmarks: Int, level: Int) -> String {
        guard level < prosperityThresholds.count else { return "Highest level" }
        return "\(prosperityThresholds[level] - checkmarks) to level \(level + 1)"
    }

    /// The checkmarks shown: from the current level's first to the threshold after next.
    static func prosperityWindow(level: Int) -> ClosedRange<Int> {
        let start = prosperityThresholds[level - 1] + 1
        let end = prosperityThresholds[min(level + 1, prosperityThresholds.count - 1)]
        return start...max(start, end)
    }

    /// "prices 1 gold lower", "prices as printed".
    static func reputationNote(_ reputation: Int) -> String {
        let modifier = ItemManager.reputationPriceModifier(reputation)
        return modifier == 0 ? "prices as printed" : "prices \(abs(modifier)) \(modifier < 0 ? "lower" : "higher")"
    }

    private var campaignScenarios: [ScenarioData] { Self.campaignScenarios(store.scenarios(for: edition)) }

    /// The campaign's scenarios: not solo scenarios, sections or random dungeons (95 in Gloomhaven).
    static func campaignScenarios(_ all: [ScenarioData]) -> [ScenarioData] {
        all.filter { $0.group == nil && $0.parent == nil }
    }

    private var won: [ScenarioData] {
        Self.number(game.completedScenarios.compactMap { id in
            guard id.hasPrefix("\(edition)-") else { return nil }
            return store.scenarioData(index: String(id.dropFirst(edition.count + 1)), edition: edition)
        })
    }

    private var open: [ScenarioData] {
        Self.number(gameManager.scenarioManager.availableScenarios(for: edition).filter { !game.completedScenarios.contains($0.id) })
    }

    static func number(_ scenarios: [ScenarioData]) -> [ScenarioData] {
        scenarios.sorted { (Int($0.index) ?? 999, $0.index) < (Int($1.index) ?? 999, $1.index) }
    }

    private func scenarioName(_ scenario: ScenarioData) -> String {
        "#\(scenario.index) " + (store.resolveLabel(key: "scenario.title.\(scenario.edition).\(scenario.index)", edition: scenario.edition)
            ?? scenario.name)
    }

    // MARK: - Left

    private var prosperity: some View {
        let level = game.prosperityLevel
        let checks = game.partyProsperity
        let window = Self.prosperityWindow(level: level)
        return TownSection(title: "Prosperity \(level)", detail: Self.prosperityToNext(checkmarks: checks, level: level)) {
            HStack(spacing: 2) {
                ForEach(Array(window), id: \.self) { n in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(n <= checks ? BoardTheme.brass : BoardTheme.raised)
                        .frame(height: 10)
                        .overlay(alignment: .trailing) {
                            if Self.prosperityThresholds.contains(n), n != window.upperBound {
                                Rectangle().fill(BoardTheme.text.opacity(0.5)).frame(width: 1.5, height: 16)
                            }
                        }
                }
            }
            .accessibilityHidden(true)
            note("\(checks) checkmark\(checks == 1 ? "" : "s"). The shop stocks items up to prosperity \(level), and new characters can start at level \(level).")
        }
        .accessibilityElement(children: .combine)
    }

    private var reputation: some View {
        let value = game.partyReputation
        let color = value >= 0 ? BoardTheme.gain : BoardTheme.defeat
        return TownSection(title: "Reputation \(value > 0 ? "+" : "")\(value)", detail: Self.reputationNote(value)) {
            GeometryReader { geo in
                let half = geo.size.width / 2
                let reach = half * CGFloat(abs(value)) / 20
                ZStack(alignment: .leading) {
                    Capsule().fill(BoardTheme.raised).frame(height: 8)
                    Capsule().fill(color).frame(width: reach, height: 8).offset(x: value >= 0 ? half : half - reach)
                    Rectangle().fill(BoardTheme.text.opacity(0.4)).frame(width: 1.5, height: 16).offset(x: half)
                    Circle().fill(color).frame(width: 14, height: 14).offset(x: half + (value >= 0 ? reach : -reach) - 7)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            .accessibilityHidden(true)
            HStack { TownSmallCaps(text: "\u{2212}20"); Spacer(); TownSmallCaps(text: "0"); Spacer(); TownSmallCaps(text: "+20") }
                .accessibilityHidden(true)
            note("Good deeds lower shop prices; bad ones raise them, and close some events' options.")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var achievements: some View {
        TownSection(title: "Achievements") {
            if game.globalAchievements.isEmpty && game.partyAchievements.isEmpty && game.campaignStickers.isEmpty {
                note("None yet. Scenarios and events award them.")
            }
            chips("Global", game.globalAchievements, key: "globalAchievements")
            chips("Party", game.partyAchievements, key: "partyAchievements")
            chips("Campaign", game.campaignStickers, key: "campaignStickers")
        }
    }

    @ViewBuilder
    private func chips(_ title: String, _ ids: Set<String>, key: String) -> some View {
        if !ids.isEmpty {
            TownSmallCaps(text: title)
            FlowLayout(spacing: 6) {
                ForEach(ids.sorted(), id: \.self) { id in
                    Text(store.resolveLabel(key: "\(key).\(id)", edition: edition) ?? GameText.titleCased(id))
                        .font(BoardTheme.font(size: 13, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(BoardTheme.raised, in: Capsule())
                        .overlay(Capsule().stroke(BoardTheme.border.opacity(0.6), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Middle

    private var scenarios: some View {
        let total = campaignScenarios.count
        return TownSection(title: "Scenarios", detail: "\(won.count) of \(total) won") {
            XPBar(progress: Double(won.count) / Double(max(1, total)), track: BoardTheme.raised)
            if !open.isEmpty {
                TownSmallCaps(text: "Open")
                ForEach(open) { scenario in
                    HStack(spacing: 8) {
                        Circle().fill(BoardTheme.brass).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(scenarioName(scenario))
                            .font(BoardTheme.font(size: 14, weight: .semibold))
                            .foregroundStyle(BoardTheme.text)
                    }
                }
            }
            if !won.isEmpty {
                TownSmallCaps(text: "Won")
                ForEach(won) { scenario in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BoardTheme.gain)
                            .accessibilityLabel("Won")
                        Text(scenarioName(scenario))
                            .font(BoardTheme.font(size: 14))
                            .foregroundStyle(BoardTheme.text.opacity(0.8))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var party: some View {
        let members = game.characters.filter { !$0.retired }
        return TownSection(title: "Party", detail: members.isEmpty ? nil : "\(members.count) of 4") {
            if members.isEmpty { note("No one yet. Recruit in town.") }
            ForEach(members, id: \.id) { character in
                HStack(spacing: 10) {
                    portrait(character.edition, character.name, color: Color(hex: character.color) ?? BoardTheme.border)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(GameText.characterName(character, labels: store))
                            .font(BoardTheme.font(size: 14, weight: .semibold))
                            .foregroundStyle(BoardTheme.text)
                        Text("Level \(character.level) \u{00B7} \(character.experience) XP \u{00B7} \(character.loot) gold")
                            .font(BoardTheme.font(size: 12))
                            .foregroundStyle(BoardTheme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            let retired = game.retiredCharacters.map {
                "\(GameText.className($0.name, edition: $0.edition, labels: store)) (level \($0.level))"
            }
            note(retired.isEmpty ? "Retired: none yet." : "Retired: \(GameText.list(retired)).")
        }
    }

    private func portrait(_ edition: String, _ name: String, color: Color) -> some View {
        Group {
            if let image = ImageLoader.characterThumbnail(edition: edition, name: name) {
                #if os(macOS)
                Image(nsImage: image).resizable().scaledToFill()
                #else
                Image(uiImage: image).resizable().scaledToFill()
                #endif
            } else {
                color.opacity(0.4)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay(Circle().stroke(color, lineWidth: 1.5))
        .accessibilityHidden(true)
    }

    // MARK: - Right

    private var log: some View {
        TownSection(title: "Campaign Log") {
            if game.campaignLog.isEmpty { note("Nothing yet. Scenarios, events and level ups are written here.") }
            ForEach(game.campaignLog.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: Self.logIcon(entry.type))
                        .font(.system(size: 12))
                        .foregroundStyle(BoardTheme.brass)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(BoardTheme.font(size: 13))
                            .foregroundStyle(BoardTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let details = entry.details {
                            Text(details)
                                .font(BoardTheme.font(size: 11))
                                .foregroundStyle(BoardTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(entry.timestamp, format: .dateTime.month(.abbreviated).day())
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(BoardTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func logIcon(_ type: CampaignLogType) -> String {
        switch type {
        case .scenarioCompleted: return "checkmark.seal"
        case .scenarioFailed: return "xmark.seal"
        case .characterAdded: return "person.badge.plus"
        case .characterRetired: return "figure.walk.departure"
        case .characterExhausted: return "bed.double"
        case .achievementGained: return "flag"
        case .prosperityGained: return "building.2"
        case .reputationChanged: return "person.2"
        case .treasureLooted: return "shippingbox"
        case .itemAcquired: return "bag"
        case .levelUp: return "arrow.up.circle"
        case .characterUnlocked: return "lock.open"
        case .questCompleted: return "scroll.fill"
        case .eventResolved: return "scroll"
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.font(size: 12))
            .foregroundStyle(BoardTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
