import Foundation

/// What a player needs to know before a scenario: its goal, how it can be lost, and its special
/// rules, in plain words. The goal is the one the game actually checks (the scenario's own win
/// rule, or every enemy killed); the rules come from the scenario's printed rule text where the
/// data has it, and are otherwise described from the rule data.
struct ScenarioBrief: Equatable {
    var title: String
    var goal: String
    var defeat: [String]
    var rules: [String]
    /// The monster types the scenario uses, by key ("bandit-guard"), for their portraits.
    var monsters: [String] = []
    /// "3 rooms · start in L1a".
    var map: String? = nil
    /// What winning gives, in a few words each: "Party achievement: First Steps", "Unlocks #2 Barrow Lair".
    var rewards: [String] = []
    var edition: String = "gh"

    static func make(for scenario: ScenarioData, labels: EditionDataStore? = nil) -> ScenarioBrief {
        let rules = scenario.rules ?? []
        let name = labels?.resolveLabel(key: "scenario.title.\(scenario.edition).\(scenario.index)", edition: scenario.edition)
            ?? scenario.name
        // What the scenario book asks of the objectives, where the scenario data has no rule for it.
        let written = scenario.solo == nil
            ? ScenarioPlacementStore.shared.placements(for: scenario.index, edition: scenario.edition)?.goal : nil
        let losses = (written?.lostAt ?? [:]).sorted { $0.key < $1.key }.compactMap { key, limit -> String? in
            guard let index = Int(key), let objectives = scenario.objectives, objectives.indices.contains(index - 1),
                  let name = objectives[index - 1].name else { return nil }
            return lossLine(name: name, limit: limit)
        }
        let exhaustion: [String] = (written?.lostIfExhausted ?? []).compactMap { way in
            switch way {
            case "any": return "Any character is exhausted."
            case "offExit": return "A character is exhausted away from the exit."
            case "beforeLoot": return "A character is exhausted before the treasure is looted."
            default: return nil
            }
        }
        let killed = (written?.lostIfKilled ?? []).map { "A \(GameText.monsterName($0, edition: scenario.edition, labels: labels)) is killed." }
        return ScenarioBrief(
            title: "#\(scenario.index) \(name)",
            goal: written?.text ?? goal(rules.filter { $0.finish == "won" }, edition: scenario.edition, labels: labels),
            defeat: ["Every character is exhausted."] + losses + exhaustion + killed
                + rules.filter { $0.finish == "lost" }.map { lossText($0, labels: labels, edition: scenario.edition) },
            rules: specialRules(scenario, labels: labels),
            monsters: monsterKeys(scenario.monsters ?? []),
            map: mapLine(scenario.rooms ?? []),
            rewards: rewardLines(scenario, labels: labels),
            edition: scenario.edition)
    }

    // MARK: - Monsters, map and rewards

    /// Each monster type once, by key: "living-corpse:+2" (a level above the scenario's) is a Living Corpse.
    private static func monsterKeys(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        return raw.map { MonsterNameSpec($0).name }.filter { seen.insert($0).inserted }
    }

    private static func mapLine(_ rooms: [RoomData]) -> String? {
        guard !rooms.isEmpty else { return nil }
        let count = rooms.count == 1 ? "1 room" : "\(rooms.count) rooms"
        guard let start = rooms.first(where: \.isInitial)?.ref else { return count }
        return "\(count) · start in \(start)"
    }

    /// The rewards for winning that are known before playing (gold and XP written as formulas
    /// are left to the end screen).
    private static func rewardLines(_ scenario: ScenarioData, labels: EditionDataStore?) -> [String] {
        let edition = scenario.edition
        var lines: [String] = []
        let rewards = scenario.rewards
        func achievement(_ id: String, _ kind: String) -> String {
            labels?.resolveLabel(key: "\(kind).\(id)", edition: edition) ?? GameText.titleCased(id)
        }
        if case .int(let gold)? = rewards?.gold, gold != 0 { lines.append("\(gold) gold each") }
        if case .int(let xp)? = rewards?.experience, xp != 0 { lines.append("\(xp) experience each") }
        for id in rewards?.partyAchievements ?? [] { lines.append("Party achievement: \(achievement(id, "partyAchievements"))") }
        for id in rewards?.globalAchievements ?? [] { lines.append("Global achievement: \(achievement(id, "globalAchievements"))") }
        for entry in rewards?.items ?? [] {
            let id = entry.split(separator: ":").first.flatMap { Int($0) }
            if let id, let name = labels?.itemData(id: id, edition: edition)?.name { lines.append("Item: \(name)") }
        }
        if let name = rewards?.unlockCharacter {
            lines.append("New class: \(GameText.className(name, edition: edition, labels: labels))")
        }
        for index in scenario.unlocks ?? [] {
            guard let unlocked = labels?.scenarioData(index: index, edition: edition) else { continue }
            let name = labels?.resolveLabel(key: "scenario.title.\(edition).\(index)", edition: edition) ?? unlocked.name
            lines.append("Unlocks #\(index) \(name)")
        }
        return lines
    }

    // MARK: - Goal

    /// "Hail is killed." / "5 Villagers are killed."
    static func lossLine(name: String, limit: Int) -> String {
        limit == 1 ? "\(name) is killed." : "\(limit) \(plural(name, limit)) are killed."
    }

    private static func goal(_ winRules: [ScenarioRule], edition: String, labels: EditionDataStore?) -> String {
        guard let rule = winRules.first else { return "Kill every enemy." }
        if let round = rule.round, let n = roundNumber(round) {
            return "Survive until the end of round \(n)."
        }
        if let killed = rule.figures?.first(where: { $0.type == "killed" }), let monster = killed.identifier?.name {
            let name = GameText.monsterName(monster, edition: edition, labels: labels)
            switch killed.value {
            case .int(let n): return "Kill \(n) \(plural(name, n))."
            case .string(let s) where Int(s) != nil: return "Kill \(s) \(plural(name, Int(s)!))."
            default: return "Kill every \(name)."
            }
        }
        if let note = text(rule.note, labels: labels, edition: edition) { return note }
        return "Complete the scenario's goal."
    }

    private static func lossText(_ rule: ScenarioRule, labels: EditionDataStore?, edition: String) -> String {
        if let note = text(rule.note, labels: labels, edition: edition) { return note }
        if let figure = rule.figures?.first, let who = figure.identifier, who.type == "objective",
           let name = who.name, figure.type == "dead" {
            return "\(name) is destroyed."
        }
        if let round = rule.round, let n = roundNumber(round) {
            return "Round \(n) ends before the goal is met."
        }
        return "A special rule is triggered."
    }

    // MARK: - Special rules

    private static func specialRules(_ scenario: ScenarioData, labels: EditionDataStore?) -> [String] {
        let edition = scenario.edition
        var lines: [String] = []
        func add(_ line: String?) {
            guard let line, !line.isEmpty, !lines.contains(line) else { return }
            lines.append(line)
        }

        // The scenario's own rule text, where the data ships it.
        if let printed = labels?.labelsByEdition[edition]
            .flatMap({ ($0["scenario"] as? [String: Any])?["rules"] as? [String: Any] })
            .flatMap({ ($0[edition] as? [String: Any])?[scenario.index] as? [String: Any] }) {
            // Some printed texts are an escort's move instruction ("towards the altar") or a
            // trigger's short note ("Move left"): only whole rules, not part of an objective's action.
            let objectiveText = (try? JSONEncoder().encode(scenario.objectives ?? []))
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            for key in printed.keys.sorted(by: { (Int($0) ?? 0) < (Int($1) ?? 0) }) {
                let reference = "%data.scenario.rules.\(edition).\(scenario.index).\(key)%"
                guard !objectiveText.contains(reference),
                      let rule = text(reference, labels: labels, edition: edition),
                      rule.split(separator: " ").count >= 5 else { continue }
                add(rule)
            }
        }

        var spawns: [String: Set<String>] = [:]   // monster name -> when it appears
        for rule in scenario.rules ?? [] where rule.finish == nil {
            for figure in rule.figures ?? [] {
                add(describe(figure, edition: edition, labels: labels))
            }
            for spawn in rule.spawns ?? [] {
                // Some names carry a data suffix ("infiltrator:+1").
                let base = String(spawn.monster.name.split(separator: ":").first ?? "")
                let name = GameText.monsterName(base, edition: edition, labels: labels)
                spawns[name, default: []].insert(when(rule))
            }
        }
        for name in spawns.keys.sorted() {
            var times = spawns[name]!
            if times.isSuperset(of: ["every odd round", "every even round"]) {
                times.subtract(["every odd round", "every even round"])
                times.insert("every round")
            }
            if times.count > 1 { times.remove("during the scenario") }
            let ordered = times.sorted { (Int($0.filter(\.isNumber)) ?? 0, $0) < (Int($1.filter(\.isNumber)) ?? 0, $1) }
            add("More \(plural(name, 2)) arrive \(GameText.list(ordered)).")
        }
        for objective in scenario.objectives ?? [] where objective.escort == true {
            if let name = objective.name { add("\(name) fights on your side; keep them alive.") }
        }
        return lines
    }

    /// One rule effect in words, or nil for effects that only steer the game behind the scenes.
    private static func describe(_ figure: ScenarioFigureRule, edition: String, labels: EditionDataStore?) -> String? {
        let who = figure.identifier
        let everyone = who?.type == "character" && (who?.name == ".*" || who?.name == nil)
        let monsterName = who?.type == "monster" && who?.name != ".*"
            ? who?.name.map { plural(GameText.monsterName($0, edition: edition, labels: labels), 2) } : nil
        switch figure.type {
        case "amAdd":
            guard everyone, case .string(let value) = figure.value else { return nil }
            let parts = value.split(separator: ":")
            let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            let cards: String
            switch parts[0] {
            case "minus1": cards = count == 1 ? "a \u{2212}1 card" : "\(count) \u{2212}1 cards"
            case "plus1": cards = count == 1 ? "a +1 card" : "\(count) +1 cards"
            default:
                let card = GameText.titleCased(String(parts[0]))
                cards = count == 1 ? "a \(card)" : "\(count) \(plural(card, count))"
            }
            return "Each character adds \(cards) to their attack modifier deck."
        case "gainCondition":
            guard everyone, case .string(let value) = figure.value else { return nil }
            return "Each character starts the scenario with \(GameText.titleCased(value))."
        case "permanentCondition":
            guard let monsterName, case .string(let value) = figure.value else { return nil }
            return "\(monsterName) are always \(conditionAdjective(value))."
        default:
            return nil
        }
    }

    // MARK: - Helpers

    /// "in round 3", "every odd round", "every 4 rounds" — or "during the scenario".
    private static func when(_ rule: ScenarioRule) -> String {
        let round = (rule.round ?? "true").replacingOccurrences(of: " ", with: "")
        if let n = roundNumber(round) { return "in round \(n)" }
        if round == "R%2==1" { return "every odd round" }
        if round == "R%2==0" { return "every even round" }
        if let match = round.wholeMatch(of: #/R%(\d+)==\d+/#) { return "every \(match.1) rounds" }
        if rule.requiredRooms != nil || rule.rooms != nil { return "as rooms open" }
        return "during the scenario"
    }

    /// The round in an "R == 10" expression.
    private static func roundNumber(_ expression: String) -> Int? {
        let compact = expression.replacingOccurrences(of: " ", with: "")
        guard let match = compact.wholeMatch(of: #/R==(\d+)/#) else { return nil }
        return Int(match.1)
    }

    private static func text(_ raw: String?, labels: EditionDataStore?, edition: String) -> String? {
        guard var text = raw, !text.isEmpty else { return nil }
        // Map markers read as letters, the way they're printed on the map.
        text = text.replacing(#/%game\.mapMarker\.([a-z0-9]+)%/#) { "(\($0.1))" }
        if text.contains("%data."), let labels {
            if text.hasPrefix("%"), text.hasSuffix("%"), !text.dropFirst().dropLast().contains("%") {
                text = labels.resolveCustomText(text, edition: edition) ?? ""
            } else {
                text = text.replacing(#/%data\.([^%]+)%/#) { labels.resolveCustomText("%data.\($0.1)%", edition: edition) ?? "" }
            }
            text = text.replacing(#/%game\.mapMarker\.([a-z0-9]+)%/#) { "(\($0.1))" }
        }
        text = text.replacing(#/%[^%]+%/#) { _ in "" }
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let first = text.prefix(1).uppercased() + text.dropFirst()
        return first.hasSuffix(".") || first.hasSuffix("!") || first.hasSuffix("?") ? first : first + "."
    }

    private static func plural(_ word: String, _ count: Int) -> String {
        guard count != 1 else { return word }
        if word.hasSuffix("s") { return word }
        if word.hasSuffix("y"), !"aeiou".contains(word.dropLast().last ?? "a") { return word.dropLast() + "ies" }
        return word + "s"
    }

    private static func conditionAdjective(_ condition: String) -> String {
        switch condition {
        case "invisible": return "invisible"
        case "strengthen": return "strengthened"
        default: return GameText.titleCased(condition).lowercased()
        }
    }
}
