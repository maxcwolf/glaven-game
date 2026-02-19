import Foundation

@Observable
final class EditionDataStore {
    var editions: [EditionInfo] = []
    var charactersByEdition: [String: [CharacterData]] = [:]
    var monstersByEdition: [String: [MonsterData]] = [:]
    var decksByEdition: [String: [DeckData]] = [:]
    var scenariosByEdition: [String: [ScenarioData]] = [:]
    var sectionsByEdition: [String: [ScenarioData]] = [:]
    var battleGoalsByEdition: [String: [BattleGoalData]] = [:]
    var itemsByEdition: [String: [ItemData]] = [:]
    var personalQuestsByEdition: [String: [PersonalQuestData]] = [:]
    var treasuresByEdition: [String: [String]] = [:]  // Raw reward strings indexed by position
    var labelsByEdition: [String: [String: Any]] = [:]  // Label data from label/en.json

    // Indexed lookups for O(1) access by name/id
    private var characterIndex: [String: [String: CharacterData]] = [:]
    private var monsterIndex: [String: [String: MonsterData]] = [:]
    private var deckIndex: [String: [String: DeckData]] = [:]
    private var scenarioIndex: [String: [String: ScenarioData]] = [:]
    private var sectionIndex: [String: [String: ScenarioData]] = [:]
    private var itemIndex: [String: [Int: ItemData]] = [:]
    private var battleGoalIndex: [String: BattleGoalData] = [:]
    private var personalQuestIndex: [String: PersonalQuestData] = [:]

    private var loadErrors: [String] = []

    func loadAllEditions() {
        loadEdition("gh")
        if !loadErrors.isEmpty {
            let log = loadErrors.joined(separator: "\n")
            try? log.write(toFile: "/tmp/glaven_errors.log", atomically: true, encoding: .utf8)
        }
    }

    func loadEdition(_ editionName: String) {
        guard let editionURL = appResourceBundle.url(forResource: editionName, withExtension: nil, subdirectory: "EditionData") else {
            loadErrors.append("Edition directory not found: \(editionName)")
            return
        }

        // Load base.json
        let baseURL = editionURL.appendingPathComponent("base.json")
        if let data = try? Data(contentsOf: baseURL),
           var info = try? JSONDecoder().decode(EditionInfo.self, from: data) {
            info.edition = editionName
            editions.append(info)
        }

        // Load from directories
        charactersByEdition[editionName] = loadDirectoryFiles(
            "character", from: editionURL, edition: editionName,
            editionKeyPath: \CharacterData.edition,
            fileFilter: { !$0.lastPathComponent.starts(with: "deck") }
        )
        loadDecks(from: editionURL.appendingPathComponent("character/deck"), edition: editionName, isCharacter: true)

        monstersByEdition[editionName] = loadDirectoryFiles(
            "monster", from: editionURL, edition: editionName,
            editionKeyPath: \MonsterData.edition
        )
        loadDecks(from: editionURL.appendingPathComponent("monster/deck"), edition: editionName, isCharacter: false)

        scenariosByEdition[editionName] = loadDirectoryFiles(
            "scenarios", from: editionURL, edition: editionName,
            editionKeyPath: \ScenarioData.edition
        )
        sectionsByEdition[editionName] = loadDirectoryFiles(
            "sections", from: editionURL, edition: editionName,
            editionKeyPath: \ScenarioData.edition
        )

        // Load from single JSON files
        if let v = loadJSONFile("items.json", from: editionURL, edition: editionName, editionKeyPath: \ItemData.edition) { itemsByEdition[editionName] = v }
        if let v = loadJSONFile("battle-goals.json", from: editionURL, edition: editionName, editionKeyPath: \BattleGoalData.edition) { battleGoalsByEdition[editionName] = v }
        if let v: [String] = loadJSONFile("treasures.json", from: editionURL, edition: editionName) { treasuresByEdition[editionName] = v }
        if let v = loadJSONFile("personal-quests.json", from: editionURL, edition: editionName, editionKeyPath: \PersonalQuestData.edition) { personalQuestsByEdition[editionName] = v }

        // Load label data for custom ability text resolution
        let labelURL = editionURL.appendingPathComponent("label/en.json")
        if let data = try? Data(contentsOf: labelURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            labelsByEdition[editionName] = json
        }

        buildIndexes(for: editionName)
    }

    /// Load all JSON files from a directory into an array of decoded objects.
    private func loadDirectoryFiles<T: Decodable>(
        _ subdirectory: String,
        from editionURL: URL,
        edition: String,
        editionKeyPath: WritableKeyPath<T, String>? = nil,
        fileFilter: ((URL) -> Bool)? = nil
    ) -> [T] {
        let dir = editionURL.appendingPathComponent(subdirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var results: [T] = []
        for file in files where file.pathExtension == "json" {
            if let fileFilter, !fileFilter(file) { continue }
            guard !isDirectory(file) else { continue }
            do {
                let data = try Data(contentsOf: file)
                var item = try JSONDecoder().decode(T.self, from: data)
                if let kp = editionKeyPath, item[keyPath: kp].isEmpty {
                    item[keyPath: kp] = edition
                }
                results.append(item)
            } catch {
                loadErrors.append("\(subdirectory)/\(file.lastPathComponent): \(error)")
            }
        }
        return results
    }

    /// Load and decode a single JSON file containing an array.
    private func loadJSONFile<T: Decodable>(
        _ filename: String,
        from editionURL: URL,
        edition: String,
        editionKeyPath: WritableKeyPath<T, String>? = nil
    ) -> [T]? {
        let url = editionURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            var items = try JSONDecoder().decode([T].self, from: data)
            if let kp = editionKeyPath {
                for i in items.indices where items[i][keyPath: kp].isEmpty {
                    items[i][keyPath: kp] = edition
                }
            }
            return items
        } catch {
            loadErrors.append("\(filename): \(error)")
            return nil
        }
    }

    private func buildIndexes(for edition: String) {
        characterIndex[edition] = Dictionary(
            (charactersByEdition[edition] ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { _, last in last }
        )
        monsterIndex[edition] = Dictionary(
            (monstersByEdition[edition] ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { _, last in last }
        )
        deckIndex[edition] = Dictionary(
            (decksByEdition[edition] ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { _, last in last }
        )
        scenarioIndex[edition] = Dictionary(
            (scenariosByEdition[edition] ?? []).map { ($0.index, $0) },
            uniquingKeysWith: { _, last in last }
        )
        sectionIndex[edition] = Dictionary(
            (sectionsByEdition[edition] ?? []).map { ($0.index, $0) },
            uniquingKeysWith: { _, last in last }
        )
        itemIndex[edition] = Dictionary(
            (itemsByEdition[edition] ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { _, last in last }
        )
        for goal in battleGoalsByEdition[edition] ?? [] {
            battleGoalIndex[goal.cardId] = goal
        }
        for quest in personalQuestsByEdition[edition] ?? [] {
            personalQuestIndex[quest.cardId] = quest
        }
    }

    private func loadDecks(from directory: URL, edition: String, isCharacter: Bool) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var decks = decksByEdition[edition] ?? []
        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                var deck = try JSONDecoder().decode(DeckData.self, from: data)
                if deck.edition.isEmpty { deck.edition = edition }
                if isCharacter { deck.character = true }
                decks.append(deck)
            } catch {
                loadErrors.append("deck/\(file.lastPathComponent): \(error)")
            }
        }
        decksByEdition[edition] = decks
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    // MARK: - Lookup Methods

    func characters(for edition: String) -> [CharacterData] {
        charactersByEdition[edition] ?? []
    }

    func monsters(for edition: String) -> [MonsterData] {
        monstersByEdition[edition] ?? []
    }

    func characterData(name: String, edition: String) -> CharacterData? {
        characterIndex[edition]?[name]
    }

    func monsterData(name: String, edition: String) -> MonsterData? {
        monsterIndex[edition]?[name]
    }

    func deckData(name: String, edition: String) -> DeckData? {
        deckIndex[edition]?[name]
    }

    func abilities(forDeck deckName: String, edition: String) -> [AbilityModel] {
        deckData(name: deckName, edition: edition)?.abilities ?? []
    }

    func scenarios(for edition: String) -> [ScenarioData] {
        scenariosByEdition[edition] ?? []
    }

    func sections(for edition: String) -> [ScenarioData] {
        sectionsByEdition[edition] ?? []
    }

    func scenarioData(index: String, edition: String) -> ScenarioData? {
        scenarioIndex[edition]?[index]
    }

    func sectionData(index: String, edition: String) -> ScenarioData? {
        sectionIndex[edition]?[index]
    }

    func items(for edition: String) -> [ItemData] {
        itemsByEdition[edition] ?? []
    }

    func itemData(id: Int, edition: String) -> ItemData? {
        itemIndex[edition]?[id]
    }

    func availableItems(for edition: String, prosperity: Int) -> [ItemData] {
        items(for: edition).filter { $0.availableAtProsperity(prosperity) }
    }

    func battleGoals(for edition: String) -> [BattleGoalData] {
        battleGoalsByEdition[edition] ?? []
    }

    func battleGoal(cardId: String) -> BattleGoalData? {
        battleGoalIndex[cardId]
    }

    func personalQuests(for edition: String) -> [PersonalQuestData] {
        personalQuestsByEdition[edition] ?? []
    }

    func personalQuest(cardId: String, edition: String) -> PersonalQuestData? {
        personalQuestIndex[cardId]
    }

    func personalQuest(cardId: String) -> PersonalQuestData? {
        personalQuestIndex[cardId]
    }

    // MARK: - Treasures

    func treasures(for edition: String) -> [String] {
        treasuresByEdition[edition] ?? []
    }

    /// Get treasure reward string by 1-based treasure index
    func treasureReward(index: Int, edition: String) -> String? {
        let treasures = treasuresByEdition[edition] ?? []
        let arrayIndex = index - 1  // treasure indices are 1-based
        guard arrayIndex >= 0, arrayIndex < treasures.count else { return nil }
        return treasures[arrayIndex]
    }

    /// Parse a treasure reward string into a human-readable label
    func treasureLabel(rewardString: String, edition: String) -> String {
        TreasureRewardParser.parse(rewardString, edition: edition, store: self)
    }

    // MARK: - Label Resolution

    /// Walk a dot-separated key path through the label dictionary for an edition.
    /// e.g. "custom.gh.mindthief.abilities.146.1" → the text at that nested path.
    func resolveLabel(key: String, edition: String) -> String? {
        guard let labels = labelsByEdition[edition] else { return nil }
        let components = key.split(separator: ".").map(String.init)
        var current: Any = labels
        for component in components {
            if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else {
                return nil
            }
        }
        return current as? String
    }

    /// Resolve a `%data.X.Y.Z%` placeholder to human-readable text.
    /// Strips the `data.` prefix, looks up the label, then resolves inner `%game.*%` patterns.
    func resolveCustomText(_ placeholder: String, edition: String) -> String? {
        // Strip surrounding % markers
        var key = placeholder
        if key.hasPrefix("%") && key.hasSuffix("%") {
            key = String(key.dropFirst().dropLast())
        }
        // Strip "data." prefix
        if key.hasPrefix("data.") {
            key = String(key.dropFirst(5))
        }
        guard let rawText = resolveLabel(key: key, edition: edition) else { return nil }
        return resolveInnerPlaceholders(rawText)
    }

    /// Replace remaining `%game.*%` patterns in resolved label text.
    private func resolveInnerPlaceholders(_ text: String) -> String {
        var result = text

        // Replace %game.action.X:N% → "X N" (must come before the no-value variant)
        result = replacePattern(in: result, pattern: #"%game\.action\.([^:%]+):(\d+)%"#) { match in
            let name = match[1].replacingOccurrences(of: "-", with: " ").capitalized
            return "\(name) \(match[2])"
        }
        // Replace %game.action.X% → "X"
        result = replacePattern(in: result, pattern: #"%game\.action\.([^:%]+)%"#) { match in
            match[1].replacingOccurrences(of: "-", with: " ").capitalized
        }

        // Replace %game.condition.X% → "X"
        result = replacePattern(in: result, pattern: #"%game\.condition\.([^%]+)%"#) { match in
            match[1].replacingOccurrences(of: "-", with: " ").capitalized
        }

        // Replace %game.element.X% → "X"
        result = replacePattern(in: result, pattern: #"%game\.element\.([^%]+)%"#) { match in
            match[1].capitalized
        }

        // Replace %game.card.experience:N% → "XP +N"
        result = replacePattern(in: result, pattern: #"%game\.card\.experience:(\d+)%"#) { match in
            "XP +\(match[1])"
        }

        // Replace %game.damage:N% → "N damage"
        result = replacePattern(in: result, pattern: #"%game\.damage:(\d+)%"#) { match in
            "\(match[1]) damage"
        }

        // Replace %game.damage% → "damage"
        result = result.replacingOccurrences(of: "%game.damage%", with: "damage")

        // Resolve recursive %data.custom...% references
        result = replacePattern(in: result, pattern: #"%data\.([^%]+)%"#) { match in
            resolveLabel(key: match[1], edition: "gh") ?? match[0]
        }

        // Strip any remaining %...% patterns
        result = replacePattern(in: result, pattern: #"%[^%]+%"#) { _ in "" }

        // Clean up HTML line breaks
        result = result.replacingOccurrences(of: "<br>", with: "\n")

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Helper to replace regex matches using a closure.
    private func replacePattern(in text: String, pattern: String, replacement: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        // Process in reverse to maintain valid ranges
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let range = Range(match.range(at: i), in: result) {
                    groups.append(String(result[range]))
                } else {
                    groups.append("")
                }
            }
            let replaced = replacement(groups)
            result.replaceSubrange(fullRange, with: replaced)
        }
        return result
    }
}
