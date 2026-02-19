import Foundation

@Observable
final class ScenarioManager {
    private let game: GameState
    private let editionStore: EditionDataStore
    private let monsterManager: MonsterManager
    private let levelManager: LevelManager
    var onBeforeMutate: (() -> Void)?

    init(game: GameState, editionStore: EditionDataStore,
         monsterManager: MonsterManager, levelManager: LevelManager) {
        self.game = game
        self.editionStore = editionStore
        self.monsterManager = monsterManager
        self.levelManager = levelManager
    }

    // MARK: - Scenario Lifecycle

    func setScenario(_ scenarioData: ScenarioData) {
        onBeforeMutate?()
        let scenario = Scenario(data: scenarioData)
        game.scenario = scenario
        applyScenarioData(scenarioData)

        // Solo scenario: mark all other characters absent
        if let soloChar = scenarioData.solo, scenarioData.spotlight != true {
            for character in game.characters {
                if character.name == soloChar && character.edition == scenarioData.edition {
                    character.absent = false
                } else {
                    character.absent = true
                }
            }
        }
    }

    func cancelScenario() {
        onBeforeMutate?()
        // Remove all scenario-added monsters
        game.figures.removeAll { figure in
            if case .monster = figure { return true }
            if case .objective = figure { return true }
            return false
        }
        game.scenario = nil
    }

    func finishScenario(success: Bool) {
        onBeforeMutate?()
        guard let scenario = game.scenario else { return }
        let data = scenario.data

        if success {
            // Record completion
            game.completedScenarios.insert(data.id)

            // Apply rewards
            if let rewards = data.rewards {
                applyRewards(rewards, edition: data.edition)
            }

            // Campaign log
            game.campaignLog.append(CampaignLogEntry(
                type: .scenarioCompleted,
                message: "Completed Scenario #\(data.index): \(data.name)",
                details: "Round \(game.round)"
            ))
        } else {
            game.campaignLog.append(CampaignLogEntry(
                type: .scenarioFailed,
                message: "Failed Scenario #\(data.index): \(data.name)",
                details: "Round \(game.round)"
            ))
        }

        // Clear scenario state
        game.figures.removeAll { figure in
            if case .monster = figure { return true }
            if case .objective = figure { return true }
            return false
        }
        game.scenario = nil
    }

    // MARK: - Room Management

    func openRoom(_ room: RoomData) {
        onBeforeMutate?()
        guard let scenario = game.scenario else { return }
        guard !scenario.revealedRooms.contains(room.roomNumber) else { return }

        scenario.revealedRooms.append(room.roomNumber)

        let edition = scenario.data.edition
        let playerCount = max(2, game.activeCharacters.count)

        // Spawn monsters from room — elites first so they get lowest standee numbers
        if let standees = room.monster {
            let activeStandees = standees.compactMap { standee -> (MonsterStandeeData, MonsterType)? in
                guard let type = standee.monsterType(forPlayerCount: playerCount) else { return nil }
                return (standee, type)
            }
            let sorted = activeStandees.sorted { a, b in
                if a.1 == b.1 { return false }
                return a.1 == .elite
            }
            for (standee, monsterType) in sorted {
                spawnMonster(name: standee.name, type: monsterType, edition: edition,
                             number: standee.number, marker: standee.marker, health: standee.health)
            }
        }

        // Spawn objectives for this room
        if let objectiveIndices = room.objectives {
            for objRef in objectiveIndices {
                spawnObjectiveByReference(objRef, scenario: scenario)
            }
        }
    }

    func openInitialRooms() {
        guard let scenario = game.scenario else { return }
        guard let rooms = scenario.data.rooms else { return }

        for room in rooms where room.isInitial {
            openRoom(room)
        }
    }

    // MARK: - Section Management

    func addSection(_ index: String) {
        guard let scenario = game.scenario else { return }
        let edition = scenario.data.edition
        guard let sectionData = editionStore.sectionData(index: index, edition: edition) else { return }
        guard !scenario.additionalSections.contains(index) else { return }

        onBeforeMutate?()
        scenario.additionalSections.append(index)

        // For conclusion sections, apply their rewards separately
        if sectionData.isConclusion, let rewards = sectionData.rewards {
            applyRewards(rewards, edition: edition)
        }

        applyScenarioData(sectionData, isSection: true)
    }

    // MARK: - Scenario Status Queries

    func isCompleted(_ scenario: ScenarioData) -> Bool {
        game.completedScenarios.contains(scenario.id)
    }

    func isAvailable(_ scenario: ScenarioData) -> Bool {
        let edition = scenario.edition
        if scenario.isInitial { return true }
        let unlocked = isScenarioUnlocked(scenario, edition: edition) || game.manualScenarios.contains(scenario.id)
        let meetsReqs = checkRequirements(scenario)
        let blocked = isScenarioBlocked(scenario, edition: edition)
        return unlocked && meetsReqs && !blocked
    }

    func isBlocked(_ scenario: ScenarioData) -> Bool {
        isScenarioBlocked(scenario, edition: scenario.edition)
    }

    func isLocked(_ scenario: ScenarioData) -> Bool {
        let edition = scenario.edition
        let unlocked = isScenarioUnlocked(scenario, edition: edition) || game.manualScenarios.contains(scenario.id)
        if !unlocked { return true }
        return !checkRequirements(scenario)
    }

    // MARK: - Available Scenarios

    func availableScenarios(for edition: String) -> [ScenarioData] {
        let allScenarios = editionStore.scenarios(for: edition)
        return allScenarios.filter { scenario in
            // Filter out sections (have parent)
            if scenario.parent != nil { return false }

            // Filter out solo scenarios, random dungeons, and random dungeon card sections
            if scenario.group == "solo" || scenario.group == "randomDungeon"
                || scenario.group == "randomMonsterCard" || scenario.group == "randomDungeonCard" { return false }

            // Initial scenarios are always available
            if scenario.isInitial { return true }

            // Already completed and not repeatable
            if game.completedScenarios.contains(scenario.id) && !scenario.isRepeatable {
                return false
            }

            // Check if unlocked via completed scenarios
            let isUnlocked = isScenarioUnlocked(scenario, edition: edition)

            // Check requirements (achievements, etc.)
            let meetsRequirements = checkRequirements(scenario)

            // Check if blocked
            let isBlocked = isScenarioBlocked(scenario, edition: edition)

            return isUnlocked && meetsRequirements && !isBlocked
        }.sorted { a, b in
            // Sort by index numerically if possible
            let aNum = Int(a.index) ?? Int.max
            let bNum = Int(b.index) ?? Int.max
            return aNum < bNum
        }
    }

    func availableSections(for edition: String) -> [ScenarioData] {
        guard let scenario = game.scenario else { return [] }
        let allSections = editionStore.sections(for: edition)
        return allSections.filter { section in
            // Must be for current scenario
            guard section.parent == scenario.data.index else { return false }

            // Not already applied
            guard !scenario.additionalSections.contains(section.index) else { return false }

            // Not blocked
            if let blocked = scenario.data.blockedSections, blocked.contains(section.index) {
                return false
            }

            return true
        }
    }

    // MARK: - Private: Apply Scenario Data

    private func applyScenarioData(_ data: ScenarioData, isSection: Bool = false) {
        guard let scenario = game.scenario else { return }
        let edition = data.edition

        // Add monsters to game (creates the figure slots, not entities yet)
        if let monsterNames = data.monsters {
            for name in monsterNames {
                // Don't add duplicate monsters
                if game.monsters.contains(where: { $0.name == name && $0.edition == edition }) { continue }

                // Check if this is an ally
                let isAlly = data.allies?.contains(name) ?? false
                let isAllied = data.allied?.contains(name) ?? false

                monsterManager.addMonster(name: name, edition: edition)
                if let monster = game.monsters.last(where: { $0.name == name && $0.edition == edition }) {
                    monster.isAlly = isAlly
                    monster.isAllied = isAllied
                    if let drawExtra = data.drawExtra, drawExtra.contains(name) {
                        monster.drawExtra = true
                    }
                }
            }
        }

        // Add objectives
        if let objectives = data.objectives {
            for (idx, objData) in objectives.enumerated() {
                addObjective(objData, index: idx + 1, edition: edition)
            }
        }

        // Open initial rooms (only for primary scenario, not sections)
        if !isSection {
            openInitialRooms()
        } else {
            // For sections, open all initial rooms
            if let rooms = data.rooms {
                for room in rooms where room.isInitial {
                    let playerCount = max(2, game.activeCharacters.count)
                    scenario.revealedRooms.append(room.roomNumber)
                    if let standees = room.monster {
                        let activeStandees = standees.compactMap { standee -> (MonsterStandeeData, MonsterType)? in
                            guard let type = standee.monsterType(forPlayerCount: playerCount) else { return nil }
                            return (standee, type)
                        }
                        let sorted = activeStandees.sorted { a, b in
                            if a.1 == b.1 { return false }
                            return a.1 == .elite
                        }
                        for (standee, monsterType) in sorted {
                            spawnMonster(name: standee.name, type: monsterType, edition: edition,
                                         number: standee.number, marker: standee.marker, health: standee.health)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private: Monster Spawning

    private func spawnMonster(name: String, type: MonsterType, edition: String,
                              number: Int? = nil, marker: String? = nil, health: String? = nil) {
        // Ensure the monster figure exists
        var monster = game.monsters.first(where: { $0.name == name && $0.edition == edition })
        if monster == nil {
            monsterManager.addMonster(name: name, edition: edition)
            monster = game.monsters.last(where: { $0.name == name && $0.edition == edition })
        }
        guard let monster = monster else { return }

        // Turn on the monster if it was off
        monster.off = false

        // Add entity
        monsterManager.addEntity(type: type, to: monster)

        // Apply marker to newly created entity
        if let marker = marker, let entity = monster.entities.last {
            entity.markers.append(marker)
        }

        // Override health if specified
        if let healthExpr = health, let entity = monster.entities.last {
            let hp = evaluateEntityValue(.string(healthExpr), level: game.level,
                                          characterCount: game.activeCharacters.count)
            entity.health = hp
            entity.maxHealth = hp
        }
    }

    // MARK: - Private: Objective Spawning

    private func addObjective(_ objData: ObjectiveData, index: Int, edition: String) {
        let container = GameObjectiveContainer(
            name: objData.name ?? "Objective \(index)",
            edition: edition,
            title: objData.name ?? "",
            escort: objData.isEscort,
            level: game.level
        )
        container.initiative = objData.resolvedInitiative

        // Calculate health
        if let healthValue = objData.health {
            let hp = evaluateEntityValue(healthValue, level: game.level,
                                          characterCount: game.activeCharacters.count)
            let entity = GameObjectiveEntity(number: index, health: hp, maxHealth: hp)
            if let marker = objData.marker {
                entity.marker = marker
            }
            container.entities.append(entity)
        }

        game.figures.append(.objective(container))
    }

    private func spawnObjectiveByReference(_ ref: IntOrString, scenario: Scenario) {
        guard let objectives = scenario.data.objectives else { return }
        let index = ref.intValue
        guard index > 0, index <= objectives.count else { return }
        let objData = objectives[index - 1]

        // Check if already spawned
        let name = objData.name ?? "Objective \(index)"
        if game.figures.contains(where: {
            if case .objective(let o) = $0 { return o.name == name }
            return false
        }) { return }

        addObjective(objData, index: index, edition: scenario.data.edition)
    }

    // MARK: - Private: Requirements Checking

    private func isScenarioUnlocked(_ scenario: ScenarioData, edition: String) -> Bool {
        let allScenarios = editionStore.scenarios(for: edition)

        // Check if any completed scenario unlocks this one
        for completed in game.completedScenarios {
            let parts = completed.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == edition else { continue }
            let completedIndex = String(parts[1])
            if let completedScenario = allScenarios.first(where: { $0.index == completedIndex }) {
                if let unlocks = completedScenario.unlocks, unlocks.contains(scenario.index) {
                    return true
                }
            }
        }

        // Check requires chains (legacy format)
        if let requires = scenario.requires {
            // requires is [[String]] — any inner array must have all scenarios completed
            return requires.contains { group in
                group.allSatisfy { reqIndex in
                    game.completedScenarios.contains("\(edition)-\(reqIndex)")
                }
            }
        }

        return false
    }

    private func isScenarioBlocked(_ scenario: ScenarioData, edition: String) -> Bool {
        let allScenarios = editionStore.scenarios(for: edition)

        // Check if any completed scenario blocks this one
        for completed in game.completedScenarios {
            let parts = completed.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, String(parts[0]) == edition else { continue }
            let completedIndex = String(parts[1])
            if let completedScenario = allScenarios.first(where: { $0.index == completedIndex }) {
                if let blocks = completedScenario.blocks, blocks.contains(scenario.index) {
                    return true
                }
            }
        }

        return false
    }

    private func checkRequirements(_ scenario: ScenarioData) -> Bool {
        guard let requirements = scenario.requirements else { return true }

        // Any requirement set must be fully met (OR between sets, AND within)
        return requirements.contains { req in
            checkSingleRequirement(req)
        }
    }

    private func checkSingleRequirement(_ req: ScenarioRequirement) -> Bool {
        // Global achievements (supports ! prefix for negation)
        if let globals = req.global {
            for g in globals {
                if g.hasPrefix("!") {
                    let name = String(g.dropFirst())
                    if game.globalAchievements.contains(name) { return false }
                } else {
                    if !game.globalAchievements.contains(g) { return false }
                }
            }
        }

        // Party achievements
        if let party = req.party {
            for p in party {
                if p.hasPrefix("!") {
                    let name = String(p.dropFirst())
                    if game.partyAchievements.contains(name) { return false }
                } else {
                    if !game.partyAchievements.contains(p) { return false }
                }
            }
        }

        // Campaign stickers
        if let stickers = req.campaignSticker {
            for s in stickers {
                if s.hasPrefix("!") {
                    let name = String(s.dropFirst())
                    if game.campaignStickers.contains(name) { return false }
                } else {
                    if !game.campaignStickers.contains(s) { return false }
                }
            }
        }

        // Characters — at least one active character must match
        if let characters = req.characters {
            let activeNames = Set(game.activeCharacters.map(\.name))
            if !characters.contains(where: { activeNames.contains($0) }) {
                return false
            }
        }

        // Completed scenario requirements
        if let scenarios = req.scenarios {
            let edition = game.edition ?? ""
            for group in scenarios {
                if !group.allSatisfy({ game.completedScenarios.contains("\(edition)-\($0)") }) {
                    return false
                }
            }
        }

        return true
    }

    // MARK: - Private: Rewards

    private func applyRewards(_ rewards: ScenarioRewards, edition: String) {
        if let globals = rewards.globalAchievements {
            for g in globals { game.globalAchievements.insert(g) }
        }
        if let party = rewards.partyAchievements {
            for p in party { game.partyAchievements.insert(p) }
        }
        if let lostParty = rewards.lostPartyAchievements {
            for p in lostParty { game.partyAchievements.remove(p) }
        }
        if let stickers = rewards.campaignSticker {
            for s in stickers { game.campaignStickers.insert(s) }
        }
        if let rep = rewards.reputation {
            game.partyReputation += resolveRewardInt(rep)
        }
        if let pros = rewards.prosperity {
            game.partyProsperity += resolveRewardInt(pros)
        }
        if let gold = rewards.gold {
            let amount = resolveRewardInt(gold)
            for character in game.activeCharacters {
                character.loot += amount
            }
        }
        if let xp = rewards.experience {
            let amount = resolveRewardInt(xp)
            for character in game.activeCharacters {
                character.experience += amount
            }
        }
    }

    private func resolveRewardInt(_ value: IntOrString) -> Int {
        switch value {
        case .int(let v): return v
        case .string(let s): return evaluateEntityValue(.string(s), level: game.level,
                                                          characterCount: game.activeCharacters.count)
        }
    }

    // MARK: - Random Scenario Draw

    /// Draw a random scenario from the pool of random-flagged, not-yet-completed scenarios.
    func drawRandomScenario() -> ScenarioData? {
        guard let edition = game.edition else { return nil }
        let allScenarios = editionStore.scenarios(for: edition)

        let candidates = allScenarios.filter { scenario in
            guard scenario.random == true else { return false }
            guard !scenario.isConclusion else { return false }
            guard !isCompleted(scenario) else { return false }
            guard !game.manualScenarios.contains(scenario.id) else { return false }
            return true
        }

        return candidates.randomElement()
    }

    /// Unlock a randomly drawn scenario and add it to manual scenarios.
    func drawAndUnlockRandomScenario() -> ScenarioData? {
        guard let drawn = drawRandomScenario() else { return nil }
        onBeforeMutate?()
        game.manualScenarios.insert(drawn.id)
        return drawn
    }
}
