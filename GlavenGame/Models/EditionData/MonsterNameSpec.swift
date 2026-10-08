import Foundation

/// A monster reference as written in scenario data, optionally carrying a level modifier.
///
/// Gloomhaven Secretariat scenario data appends a level modifier to a monster name in the
/// scenario `monsters` list, room `monster[].name` standees and rule `spawns[].monster.name`:
/// - `"living-corpse:+2"` (GH 28), `"infiltrator:+1"` (GH 57), `"the-harvester:+1"` (GH 58),
///   `"stone-golem:+1"` (GH 67) — monster level = scenario level + N
/// - `"bandit-guard:-1"`, `"city-guard-sun-solo:-2"` (solo scenarios) — scenario level − N
///
/// No other suffix form occurs in the GH data. A bare number (`"name:3"`) is accepted as an
/// absolute level for robustness. Scenario statEffects / allies lists use the plain name, so
/// game state should always store `name` (the base name), never the raw string.
struct MonsterNameSpec: Hashable {
    /// Base monster name used for data lookup, ability decks, images and board pieces.
    let name: String
    /// Relative level modifier (`:+2` → 2, `:-1` → -1, plain name → 0).
    let levelOffset: Int
    /// Absolute level when the suffix is an unsigned number (`:3`), otherwise nil.
    let absoluteLevel: Int?

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.lastIndex(of: ":") else {
            self.init(name: trimmed, levelOffset: 0, absoluteLevel: nil)
            return
        }
        let base = String(trimmed[..<colon])
        let suffix = String(trimmed[trimmed.index(after: colon)...])
        guard !base.isEmpty, let number = Int(suffix) else {
            // Unknown suffix form — keep the whole string so a lookup failure stays visible.
            self.init(name: trimmed, levelOffset: 0, absoluteLevel: nil)
            return
        }
        if suffix.hasPrefix("+") || suffix.hasPrefix("-") {
            self.init(name: base, levelOffset: number, absoluteLevel: nil)
        } else {
            self.init(name: base, levelOffset: 0, absoluteLevel: number)
        }
    }

    init(name: String, levelOffset: Int = 0, absoluteLevel: Int? = nil) {
        self.name = name
        self.levelOffset = levelOffset
        self.absoluteLevel = absoluteLevel
    }

    /// Parses `"living-corpse:+2"` → `("living-corpse", 2)`, `"bandit-guard:-1"` →
    /// `("bandit-guard", -1)`, `"cultist"` → `("cultist", 0)`.
    static func parse(_ raw: String) -> (name: String, levelOffset: Int) {
        let spec = MonsterNameSpec(raw)
        return (spec.name, spec.levelOffset)
    }

    /// Strips any level suffix: `"living-corpse:+2"` → `"living-corpse"`.
    static func baseName(_ raw: String) -> String {
        MonsterNameSpec(raw).name
    }

    /// True when the raw name carried a level modifier.
    var hasLevelModifier: Bool { levelOffset != 0 || absoluteLevel != nil }

    /// Monster level for a scenario played at `scenarioLevel`, clamped to 0...7.
    func level(forScenarioLevel scenarioLevel: Int) -> Int {
        let raw = absoluteLevel ?? (scenarioLevel + levelOffset)
        return min(max(raw, MonsterData.levelRange.lowerBound), MonsterData.levelRange.upperBound)
    }
}
