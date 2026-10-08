import Foundation

struct MonsterData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(name)" }
    var name: String
    var edition: String
    var count: IntOrString?
    var baseStat: MonsterStatModel?
    var stats: [MonsterStatModel]
    var deck: String?
    var boss: Bool?
    var flying: Bool?
    var immortal: Bool?
    var hidden: Bool?
    var spoiler: Bool?
    var standeeCount: IntOrString?
    var standeeShare: String?
    var pet: String?

    var isBoss: Bool { boss ?? false }

    /// Lowest / highest monster level present in the data (GH: 0...7).
    static let levelRange = 0...7

    /// The stat block for a monster type at a level, with every field the level entry does not
    /// specify inherited from `baseStat` (see `MonsterStatModel.inheriting(from:)`).
    ///
    /// - Bosses always resolve to the `.boss` stat block regardless of `type`.
    /// - A stat entry without `type` takes `baseStat.type` (default `.normal`).
    /// - Levels outside 0...7 (e.g. scenario level 7 with a `:+2` name offset) are clamped.
    func stat(for type: MonsterType, at level: Int) -> MonsterStatModel? {
        let resolvedType = isBoss ? .boss : type
        let baseType = baseStat?.type ?? .normal
        let clampedLevel = min(max(level, Self.levelRange.lowerBound), Self.levelRange.upperBound)
        guard let entry = stats.first(where: {
            ($0.type ?? baseType) == resolvedType && ($0.level ?? 0) == clampedLevel
        }) else { return nil }
        var merged = entry.inheriting(from: baseStat)
        merged.type = resolvedType
        merged.level = clampedLevel
        return merged
    }

    /// Number of physical standees for this monster (Gloomhaven Secretariat:
    /// `standeeCount ?? count`, evaluated as an expression). GH data always provides `count`
    /// (6 for most monsters, 10 for e.g. Living Bones / Black Imp / Vermling Scout / Ooze,
    /// 4 for Cave Bear / Inox Shaman, 2 for Inox Bodyguard, 1 for most bosses).
    /// Falls back to 1 for bosses and 6 otherwise when the data has neither field.
    var maxCount: Int { maxCount(characterCount: 2) }

    /// `maxCount` for data whose count is a formula (e.g. `"C"`); `characterCount` is `C`.
    func maxCount(characterCount: Int) -> Int {
        guard let raw = standeeCount ?? count else { return isBoss ? 1 : 6 }
        let value = evaluateEntityValue(raw, characterCount: characterCount)
        return value > 0 ? value : (isBoss ? 1 : 6)
    }

    /// Name of the physical standee set this monster draws from (one hop). Variant monsters
    /// (`bandit-guard-music-note-solo`, `cave-bear-scenario-54`) and some bosses
    /// (`ghost-wolf` → `hound`, `deep-earth` → `earth-demon`) share standees with another
    /// monster via `standeeShare`; standee numbers in use by either must not be reused, and
    /// the combined number on the board is capped by the pool root's `maxCount`.
    /// Shares can chain (`lieutenant` → `city-guard-saw-solo` → `city-guard`); use
    /// `standeePoolRoot(lookup:)` to resolve the whole chain.
    var standeePoolName: String { standeeShare ?? name }

    /// Follows the `standeeShare` chain to the monster that owns the physical standees.
    /// `lookup` resolves a monster name in this monster's edition (e.g.
    /// `{ store.monsterData(name: $0, edition: data.edition) }`). Returns `self` when the
    /// monster does not share, and stops at a missing link or a cycle.
    func standeePoolRoot(lookup: (String) -> MonsterData?) -> MonsterData {
        var current = self
        var visited: Set<String> = [name]
        while let share = current.standeeShare, !visited.contains(share),
              let next = lookup(share) {
            visited.insert(share)
            current = next
        }
        return current
    }

    /// True when both monsters draw standees from the same physical set (same edition),
    /// resolving `standeeShare` chains through `lookup`.
    func sharesStandees(with other: MonsterData, lookup: (String) -> MonsterData?) -> Bool {
        guard edition == other.edition else { return false }
        return standeePoolRoot(lookup: lookup).name == other.standeePoolRoot(lookup: lookup).name
    }
}
