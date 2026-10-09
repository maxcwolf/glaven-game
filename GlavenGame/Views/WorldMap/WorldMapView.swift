import SwiftUI

/// The world map, in the board's look: the edition's map with a sticker for each scenario the
/// party has found (open in brass, won in green), as the board game's map gets its stickers.
/// Tapping one shows it beside the map, and in town it can be chosen for the party.
struct WorldMapView: View {
    @Environment(GameManager.self) private var gameManager
    /// In town, choosing a scenario on the map picks it for the party to start.
    var onChoose: ((ScenarioData) -> Void)? = nil
    var onDone: () -> Void = {}

    @State private var zoom: CGFloat?
    @State private var selected: ScenarioData?

    private var edition: String { gameManager.game.edition ?? "gh" }
    private var scenarioManager: ScenarioManager { gameManager.scenarioManager }

    private var editionInfo: EditionInfo? {
        gameManager.editionStore.editions.first { $0.edition == edition }
    }

    /// The scenarios with a sticker: those found (unlocked) and those won.
    private var found: [ScenarioData] { Self.found(gameManager.editionStore.scenarios(for: edition), scenarioManager) }

    /// A scenario gets its sticker once it's unlocked, and keeps it once won.
    static func found(_ all: [ScenarioData], _ manager: ScenarioManager) -> [ScenarioData] {
        all.filter { $0.coordinates != nil && $0.parent == nil && $0.group == nil }
            .filter { manager.isCompleted($0) || manager.isUnlocked($0) }
    }

    private var achievementStickers: [AchievementSticker] {
        AchievementSticker.build(
            globalAchievements: gameManager.game.globalAchievements,
            partyAchievements: gameManager.game.partyAchievements,
            scenarios: gameManager.editionStore.scenarios(for: edition),
            completedScenarios: gameManager.game.completedScenarios,
            edition: edition
        )
    }

    var body: some View {
        TownDialog(title: "World Map", subtitle: "\(editionInfo?.displayName ?? "Gloomhaven") and its surroundings \u{00B7} \(Self.foundLine(found.count))",
                   onDone: onDone) {
            zoomButton("minus.magnifyingglass", "Zoom out") { zoom = max(0.2, (zoom ?? 0.5) * 0.8) }
            zoomButton("plus.magnifyingglass", "Zoom in") { zoom = min(2, (zoom ?? 0.5) * 1.25) }
        } content: {
            HStack(alignment: .top, spacing: 0) {
                map
                ScrollView { detail }
                    .frame(width: 300)
                    .padding(14)
            }
        }
    }

    /// "2 scenarios found".
    static func foundLine(_ count: Int) -> String {
        "\(count) scenario\(count == 1 ? "" : "s") found"
    }

    private func zoomButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(BoardTheme.font(size: 14, weight: .semibold))
                .foregroundStyle(BoardTheme.text)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(BoardTheme.border, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Map

    @ViewBuilder
    private var map: some View {
        if let dims = editionInfo?.worldMap {
            let mapWidth = CGFloat(dims.width), mapHeight = CGFloat(dims.height)
            GeometryReader { geo in
                // At first the map is a little taller than the view, centred on the stickers.
                let scale: CGFloat = zoom ?? max(geo.size.width / mapWidth, geo.size.height / mapHeight * 1.4)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        mapImage
                            .frame(width: mapWidth * scale, height: mapHeight * scale)
                        ForEach(gameManager.game.mapOverlays, id: \.name) { overlay in
                            OverlayStickerView(overlay: overlay, edition: edition, zoom: scale)
                        }
                        ForEach(achievementStickers) { sticker in
                            AchievementStickerView(sticker: sticker, zoom: scale)
                        }
                        ForEach(found) { scenario in sticker(scenario, scale: scale) }
                    }
                    .frame(width: mapWidth * scale, height: mapHeight * scale)
                }
                .defaultScrollAnchor(anchor(width: mapWidth, height: mapHeight))
                .gesture(MagnifyGesture().onChanged { value in
                    zoom = min(max(scale * value.magnification, 0.2), 2)
                })
            }
            .clipped()
            .overlay(alignment: .bottomLeading) { legend }
        } else {
            Text("No world map for this edition.")
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var mapImage: some View {
        if let image = ImageLoader.worldMapBase(edition: edition) {
            #if os(macOS)
            Image(nsImage: image).resizable()
            #else
            Image(uiImage: image).resizable()
            #endif
        } else {
            BoardTheme.raised
        }
    }

    /// The middle of the found stickers, as a point on the map (0–1).
    private func anchor(width: CGFloat, height: CGFloat) -> UnitPoint {
        let points = found.compactMap(\.coordinates).compactMap { c -> CGPoint? in
            guard let x = c.x, let y = c.y else { return nil }
            return CGPoint(x: x + (c.width ?? 0) / 2, y: y + (c.height ?? 0) / 2)
        }
        guard !points.isEmpty else { return .center }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return UnitPoint(x: x / width, y: y / height)
    }

    private func sticker(_ scenario: ScenarioData, scale: CGFloat) -> some View {
        let c = scenario.coordinates!
        let won = scenarioManager.isCompleted(scenario)
        let blocked = !won && !scenarioManager.isAvailable(scenario)
        let color = won ? BoardTheme.gain : (blocked ? BoardTheme.secondaryText : BoardTheme.brass)
        let isSelected = selected?.id == scenario.id
        return Button { selected = scenario } label: {
            Group {
                if let image = ImageLoader.worldMapScenario(edition: scenario.edition, index: scenario.index, customImage: c.image) {
                    #if os(macOS)
                    Image(nsImage: image).resizable().scaledToFit()
                    #else
                    Image(uiImage: image).resizable().scaledToFit()
                    #endif
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(BoardTheme.raised)
                }
            }
            .saturation(won || blocked ? 0.4 : 1)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: isSelected ? 4 : 2.5))
            .overlay(alignment: .bottomTrailing) {
                Text("#\(scenario.index)")
                    .font(BoardTheme.font(size: 12, weight: .bold))
                    .foregroundStyle(BoardTheme.sheet)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color, in: Capsule())
                    .offset(x: 6, y: 6)
            }
            .shadow(color: isSelected ? BoardTheme.brass.opacity(0.9) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
        .frame(width: (c.width ?? 0) * scale, height: (c.height ?? 0) * scale)
        .offset(x: (c.x ?? 0) * scale, y: (c.y ?? 0) * scale)
        .accessibilityLabel("#\(scenario.index) \(scenario.name), \(won ? "won" : (blocked ? "not yet playable" : "open"))")
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(BoardTheme.brass, "Open")
            legendItem(BoardTheme.gain, "Won")
            legendItem(BoardTheme.secondaryText, "Not yet")
            Text("Pinch or use the buttons to zoom")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(BoardTheme.sheet.opacity(0.85), in: Capsule())
        .padding(14)
        .accessibilityHidden(true)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 2).frame(width: 14, height: 11)
            Text(text).font(BoardTheme.font(size: 12, weight: .semibold)).foregroundStyle(BoardTheme.text)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let scenario = selected {
            let won = scenarioManager.isCompleted(scenario)
            let available = scenarioManager.isAvailable(scenario)
            let brief = ScenarioBrief.make(for: scenario, labels: gameManager.editionStore)
            TownSection(title: brief.title, detail: won ? "Won" : (available ? "Open" : (scenarioManager.isBlocked(scenario) ? "Blocked" : "Not yet"))) {
                Text(brief.goal)
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(BoardTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                TownSmallCaps(text: "Getting there")
                note(gameManager.eventCardManager.needsRoadEvent(for: scenario) ? "By road: a road event comes first." : "No road event.")
                let from = Self.unlockedBy(scenario, among: gameManager.editionStore.scenarios(for: edition),
                                          won: gameManager.game.completedScenarios)
                if !from.isEmpty {
                    TownSmallCaps(text: "Unlocked by")
                    note(GameText.list(from.map { "#\($0.index) \($0.name)" }))
                }
                let needs = Self.needs(scenario, labels: gameManager.editionStore)
                if !available, !won, !needs.isEmpty {
                    TownSmallCaps(text: "Needs")
                    note(needs)
                }
                if let onChoose, available, !won || scenario.isRepeatable {
                    Button("Choose for the Party") {
                        onChoose(scenario)
                        onDone()
                    }
                    .buttonStyle(.boardPrimary)
                }
            }
        } else {
            TownSection(title: "The Map") {
                note("Tap a sticker to see its scenario. Stickers appear as the party finds scenarios, just like the board game's map.")
            }
        }
    }

    /// What a scenario's requirements ask, in words: "Party achievement First Steps; global
    /// achievement The Rift Neutralized not yet gained".
    static func needs(_ scenario: ScenarioData, labels: EditionDataStore) -> String {
        let options = (scenario.requirements ?? []).map { req -> String in
            func named(_ ids: [String]?, kind: String, key: String) -> [String] {
                (ids ?? []).map { raw in
                    let negated = raw.hasPrefix("!")
                    let id = String((negated ? raw.dropFirst() : Substring(raw)).split(separator: ":").first ?? "")
                    let name = labels.resolveLabel(key: "\(key).\(id)", edition: scenario.edition) ?? GameText.titleCased(id)
                    return negated ? "\(kind) \(name) not yet gained" : "\(kind) \(name)"
                }
            }
            return (named(req.party, kind: "party achievement", key: "partyAchievements")
                    + named(req.global, kind: "global achievement", key: "globalAchievements")).joined(separator: "; ")
        }.filter { !$0.isEmpty }
        guard let first = options.first else { return "" }
        let text = options.count == 1 ? first : options.joined(separator: ", or ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// The won scenarios that unlock this one.
    static func unlockedBy(_ scenario: ScenarioData, among all: [ScenarioData], won: Set<String>) -> [ScenarioData] {
        all.filter { won.contains($0.id) && $0.group == nil && ($0.unlocks ?? []).contains(scenario.index) }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.font(size: 12))
            .foregroundStyle(BoardTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
