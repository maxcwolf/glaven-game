import Foundation

struct MonsterStatModel: Codable, Hashable {
    var type: MonsterType?
    var level: Int?
    var health: IntOrString?
    var movement: IntOrString?
    var attack: IntOrString?
    var range: IntOrString?
    var actions: [ActionModel]?
    var immunities: [ConditionName]?
    var special: [[ActionModel]]?
    var note: String?

    init(type: MonsterType? = nil, level: Int? = 0, health: IntOrString? = .int(0),
         movement: IntOrString? = nil, attack: IntOrString? = nil,
         range: IntOrString? = nil, actions: [ActionModel]? = nil,
         immunities: [ConditionName]? = nil) {
        self.type = type
        self.level = level
        self.health = health
        self.movement = movement
        self.attack = attack
        self.range = range
        self.actions = actions
        self.immunities = immunities
    }

    var resolvedType: MonsterType {
        type ?? .normal
    }

    // MARK: - baseStat inheritance

    /// Returns this (per-level / per-type) stat block with every field it does not specify
    /// inherited from the monster's `baseStat`, following Gloomhaven Secretariat semantics.
    ///
    /// - Scalar fields (`type`, `level`, `health`, `movement`, `attack`, `range`, `note`):
    ///   the level entry wins; `baseStat` only fills fields the entry leaves out
    ///   (e.g. Black Imp `baseStat.movement = 1`, Sightless Eye `baseStat.range = 3`,
    ///   Merciless Overseer `baseStat.attack = "V"`).
    /// - `actions` (stat-card attack effects / shield / retaliate / pierce / target):
    ///   **combined** — base actions first, then the level's own. A semantically identical
    ///   action present in both is kept once. The only GH monster with actions in both is
    ///   `cave-bear-scenario-54` (scenario rule "all Cave Bears add Poison" in `baseStat`
    ///   alongside the printed Wound at level 5+), which requires combining.
    /// - `immunities`: union (base first, order preserved, no duplicates). All 14 GH bosses
    ///   with immunities define them only in `baseStat`.
    /// - `special` (boss Special 1 / Special 2): positional, so it is **not** combined —
    ///   the level's list replaces the base list when present, otherwise base is inherited.
    func inheriting(from base: MonsterStatModel?) -> MonsterStatModel {
        guard let base else { return self }
        var merged = self
        merged.type = type ?? base.type
        merged.level = level ?? base.level
        merged.health = health ?? base.health
        merged.movement = movement ?? base.movement
        merged.attack = attack ?? base.attack
        merged.range = range ?? base.range
        merged.note = note ?? base.note
        merged.special = special ?? base.special
        merged.actions = Self.combineActions(base.actions, actions)
        merged.immunities = Self.combineImmunities(base.immunities, immunities)
        return merged
    }

    private static func combineActions(_ base: [ActionModel]?, _ own: [ActionModel]?) -> [ActionModel]? {
        guard let base, !base.isEmpty else { return own }
        guard let own, !own.isEmpty else { return base }
        var result = base
        for action in own where !result.contains(where: { isSameStatAction($0, action) }) {
            result.append(action)
        }
        return result
    }

    /// Value-equality for stat actions ignoring the per-instance `id`. Only leaf actions are
    /// treated as duplicates; actions with sub-actions are always kept.
    private static func isSameStatAction(_ a: ActionModel, _ b: ActionModel) -> Bool {
        guard (a.subActions ?? []).isEmpty, (b.subActions ?? []).isEmpty else { return false }
        return a.type == b.type && a.value == b.value && a.valueType == b.valueType
    }

    private static func combineImmunities(_ base: [ConditionName]?, _ own: [ConditionName]?) -> [ConditionName]? {
        guard let base, !base.isEmpty else { return own }
        guard let own, !own.isEmpty else { return base }
        var result = base
        for immunity in own where !result.contains(immunity) {
            result.append(immunity)
        }
        return result
    }

    // MARK: - Evaluated values

    /// Evaluates a stat value that may be an expression (`"8xC"`, `"1+C"`, `"(10xC)/2"`,
    /// `"3+X"`...). `level` defaults to this stat block's own level (`L`).
    /// `variables` supplies card-specific letters (Dark Rider `X` = hexes moved this turn,
    /// Merciless Overseer `V` = Vermling Scouts present); unknown letters count as 0.
    private func evaluate(_ value: IntOrString?, characterCount: Int, level: Int?,
                          variables: [String: Int]) -> Int {
        guard let value else { return 0 }
        return evaluateEntityValue(value, level: level ?? self.level ?? 0,
                                   characterCount: characterCount, variables: variables)
    }

    /// Max health, e.g. boss `"8xC"` → 8 × max(2, characterCount).
    func healthValue(characterCount: Int, level: Int? = nil, variables: [String: Int] = [:]) -> Int {
        evaluate(health, characterCount: characterCount, level: level, variables: variables)
    }

    /// Base movement (0 when the stat card has none).
    func movementValue(characterCount: Int, level: Int? = nil, variables: [String: Int] = [:]) -> Int {
        evaluate(movement, characterCount: characterCount, level: level, variables: variables)
    }

    /// Base attack, e.g. Inox Bodyguard `"1+C"`, Dark Rider `"3+X"` (pass `["X": hexesMoved]`).
    func attackValue(characterCount: Int, level: Int? = nil, variables: [String: Int] = [:]) -> Int {
        evaluate(attack, characterCount: characterCount, level: level, variables: variables)
    }

    /// Base range (0 = melee).
    func rangeValue(characterCount: Int, level: Int? = nil, variables: [String: Int] = [:]) -> Int {
        evaluate(range, characterCount: characterCount, level: level, variables: variables)
    }

    /// Card-specific variables (other than C/L/P/R) the attack value depends on,
    /// e.g. `["X"]` for Dark Rider, `["V"]` for Merciless Overseer.
    var attackVariables: Set<String> {
        guard let attack else { return [] }
        return entityValueVariables(attack).subtracting(["C", "L", "P", "R"])
    }

    // MARK: - Stat-card attack effects

    /// Conditions every attack by this monster applies (stat-card `condition` actions,
    /// e.g. Giant Viper Poison, Black Imp Poison at level 1+).
    var attackConditions: [ConditionName] {
        (actions ?? []).compactMap { action in
            guard action.type == .condition, case .string(let name)? = action.value else { return nil }
            return ConditionName(rawValue: name)
        }
    }

    /// Stat-card Pierce value (0 if none).
    var pierceValue: Int {
        (actions ?? []).filter { $0.type == .pierce }.reduce(0) { $0 + ($1.value?.intValue ?? 0) }
    }

    /// Stat-card Target count (nil if the card has no Target bonus).
    var targetCount: Int? {
        (actions ?? []).first(where: { $0.type == .target })?.value?.intValue
    }

    /// Stat-card "Advantage" (`%game.custom.advantage%`, e.g. Sun Demon): this monster's
    /// attacks gain Advantage.
    var hasAttackAdvantage: Bool {
        (actions ?? []).contains { $0.type == .custom && $0.value?.stringValue == "%game.custom.advantage%" }
    }

    /// Stat-card "Disadvantage" (`%game.custom.disadvantage%`, e.g. Night Demon in `baseStat`):
    /// printed on the GH card as "Attackers gain Disadvantage", i.e. attacks *targeting* this
    /// monster gain Disadvantage.
    var attackersGainDisadvantage: Bool {
        (actions ?? []).contains { $0.type == .custom && $0.value?.stringValue == "%game.custom.disadvantage%" }
    }
}
