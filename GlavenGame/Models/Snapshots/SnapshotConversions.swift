import Foundation

// MARK: - GameState -> GameSnapshot

extension GameState {
    func toSnapshot(boardCoordinator: BoardCoordinator? = nil) -> GameSnapshot {
        GameSnapshot(
            edition: edition,
            conditions: conditions,
            figures: figures.map { $0.toSnapshot() },
            state: state,
            round: round,
            level: level,
            levelCalculation: levelCalculation,
            levelAdjustment: levelAdjustment,
            bonusAdjustment: bonusAdjustment,
            ge5Player: ge5Player,
            playerCount: playerCount,
            solo: solo,
            playSeconds: playSeconds,
            totalSeconds: totalSeconds,
            elementBoard: elementBoard,
            monsterAttackModifierDeck: monsterAttackModifierDeck,
            allyAttackModifierDeck: allyAttackModifierDeck,
            lootDeck: lootDeck,
            partyName: partyName,
            partyReputation: partyReputation,
            partyProsperity: partyProsperity,
            scenario: scenario?.toSnapshot(),
            completedScenarios: completedScenarios,
            manualScenarios: manualScenarios,
            globalAchievements: globalAchievements,
            partyAchievements: partyAchievements,
            campaignStickers: campaignStickers,
            lootedTreasures: lootedTreasures,
            retiredCharacters: retiredCharacters,
            campaignLog: campaignLog,
            unlockedCharacters: unlockedCharacters,
            unlockedItems: unlockedItems,
            boardSnapshot: boardCoordinator?.boardScene != nil ? boardCoordinator?.snapshot() : nil
        )
    }

    func restore(from snapshot: GameSnapshot, editionStore: EditionDataStore, boardCoordinator: BoardCoordinator? = nil) {
        edition = snapshot.edition
        conditions = snapshot.conditions
        state = snapshot.state
        round = snapshot.round
        level = snapshot.level
        levelCalculation = snapshot.levelCalculation
        levelAdjustment = snapshot.levelAdjustment
        bonusAdjustment = snapshot.bonusAdjustment
        ge5Player = snapshot.ge5Player
        playerCount = snapshot.playerCount
        solo = snapshot.solo
        playSeconds = snapshot.playSeconds
        totalSeconds = snapshot.totalSeconds
        elementBoard = snapshot.elementBoard
        monsterAttackModifierDeck = snapshot.monsterAttackModifierDeck
        allyAttackModifierDeck = snapshot.allyAttackModifierDeck
        lootDeck = snapshot.lootDeck
        partyName = snapshot.partyName
        partyReputation = snapshot.partyReputation
        partyProsperity = snapshot.partyProsperity
        completedScenarios = snapshot.completedScenarios
        manualScenarios = snapshot.manualScenarios
        globalAchievements = snapshot.globalAchievements
        partyAchievements = snapshot.partyAchievements
        campaignStickers = snapshot.campaignStickers
        lootedTreasures = snapshot.lootedTreasures
        retiredCharacters = snapshot.retiredCharacters
        campaignLog = snapshot.campaignLog
        unlockedCharacters = snapshot.unlockedCharacters
        unlockedItems = snapshot.unlockedItems

        // Restore figures
        figures = snapshot.figures.map { $0.toRuntime(editionStore: editionStore) }

        // Restore scenario
        if let scenarioSnap = snapshot.scenario {
            scenario = scenarioSnap.toRuntime(editionStore: editionStore)
        } else {
            scenario = nil
        }

        // Restore board state
        if let boardSnap = snapshot.boardSnapshot, let coordinator = boardCoordinator {
            coordinator.restore(from: boardSnap)
        }
    }
}

// MARK: - AnyFigure -> FigureSnapshot

extension AnyFigure {
    func toSnapshot() -> FigureSnapshot {
        switch self {
        case .character(let c): return .character(c.toSnapshot())
        case .monster(let m): return .monster(m.toSnapshot())
        case .objective(let o): return .objective(o.toSnapshot())
        }
    }
}

extension FigureSnapshot {
    func toRuntime(editionStore: EditionDataStore) -> AnyFigure {
        switch self {
        case .character(let s): return .character(s.toRuntime(editionStore: editionStore))
        case .monster(let s): return .monster(s.toRuntime(editionStore: editionStore))
        case .objective(let s): return .objective(s.toRuntime())
        }
    }
}

// MARK: - GameCharacter <-> CharacterSnapshot

extension GameCharacter {
    func toSnapshot() -> CharacterSnapshot {
        CharacterSnapshot(
            name: name, edition: edition, level: level, off: off, active: active,
            number: number, health: health, maxHealth: maxHealth,
            entityConditions: entityConditions, immunities: immunities,
            markers: markers, tags: tags,
            shield: shield, shieldPersistent: shieldPersistent,
            retaliate: retaliate, retaliatePersistent: retaliatePersistent,
            title: title, initiative: initiative, experience: experience,
            loot: loot, lootCards: lootCards,
            exhausted: exhausted, absent: absent, longRest: longRest,
            identity: identity, token: token, tokenValues: tokenValues,
            attackModifierDeck: attackModifierDeck,
            summons: summons.map { $0.toSnapshot() },
            selectedPerks: selectedPerks,
            battleGoalCardIds: battleGoalCardIds,
            selectedBattleGoal: selectedBattleGoal,
            items: items,
            notes: notes,
            battleGoalProgress: battleGoalProgress,
            personalQuest: personalQuest,
            personalQuestProgress: personalQuestProgress,
            retired: retired,
            handCards: handCards,
            discardedCards: discardedCards,
            lostCards: lostCards,
            resources: resources,
            enhancements: enhancements
        )
    }
}

extension CharacterSnapshot {
    func toRuntime(editionStore: EditionDataStore) -> GameCharacter {
        let charData = editionStore.characterData(name: name, edition: edition)
        let c = GameCharacter(name: name, edition: edition, level: level, characterData: charData)
        c.off = off
        c.active = active
        c.number = number
        c.health = health
        c.maxHealth = maxHealth
        c.entityConditions = entityConditions
        c.immunities = immunities
        c.markers = markers
        c.tags = tags
        c.shield = shield
        c.shieldPersistent = shieldPersistent
        c.retaliate = retaliate
        c.retaliatePersistent = retaliatePersistent
        c.title = title
        c.initiative = initiative
        c.experience = experience
        c.loot = loot
        c.lootCards = lootCards
        c.exhausted = exhausted
        c.absent = absent
        c.longRest = longRest
        c.identity = identity
        c.token = token
        c.tokenValues = tokenValues
        c.attackModifierDeck = attackModifierDeck
        c.summons = summons.map { $0.toRuntime() }
        c.selectedPerks = selectedPerks
        c.battleGoalCardIds = battleGoalCardIds
        c.selectedBattleGoal = selectedBattleGoal
        c.items = items
        c.notes = notes
        c.battleGoalProgress = battleGoalProgress
        c.personalQuest = personalQuest
        c.personalQuestProgress = personalQuestProgress
        c.retired = retired
        c.handCards = handCards
        c.discardedCards = discardedCards
        c.lostCards = lostCards
        c.resources = resources
        c.enhancements = enhancements
        return c
    }
}

// MARK: - GameMonster <-> MonsterSnapshot

extension GameMonster {
    func toSnapshot() -> MonsterSnapshot {
        MonsterSnapshot(
            name: name, edition: edition, level: level, off: off, active: active,
            ability: ability, abilities: abilities,
            entities: entities.map { $0.toSnapshot() },
            isAlly: isAlly, isAllied: isAllied, tags: tags, drawExtra: drawExtra
        )
    }
}

extension MonsterSnapshot {
    func toRuntime(editionStore: EditionDataStore) -> GameMonster {
        let monData = editionStore.monsterData(name: name, edition: edition)
        let m = GameMonster(name: name, edition: edition, level: level, monsterData: monData)
        m.off = off
        m.active = active
        m.ability = ability
        m.abilities = abilities
        m.entities = entities.map { $0.toRuntime() }
        m.isAlly = isAlly
        m.isAllied = isAllied
        m.tags = tags
        m.drawExtra = drawExtra
        return m
    }
}

// MARK: - GameMonsterEntity <-> MonsterEntitySnapshot

extension GameMonsterEntity {
    func toSnapshot() -> MonsterEntitySnapshot {
        MonsterEntitySnapshot(
            number: number, type: type, health: health, maxHealth: maxHealth,
            level: level, dead: dead, dormant: dormant, revealed: revealed,
            active: active, off: off, summonState: summonState,
            entityConditions: entityConditions, immunities: immunities,
            markers: markers, tags: tags,
            shield: shield, shieldPersistent: shieldPersistent,
            retaliate: retaliate, retaliatePersistent: retaliatePersistent
        )
    }
}

extension MonsterEntitySnapshot {
    func toRuntime() -> GameMonsterEntity {
        let e = GameMonsterEntity(number: number, type: type, health: health, maxHealth: maxHealth, level: level)
        e.dead = dead
        e.dormant = dormant
        e.revealed = revealed
        e.active = active
        e.off = off
        e.summonState = summonState
        e.entityConditions = entityConditions
        e.immunities = immunities
        e.markers = markers
        e.tags = tags
        e.shield = shield
        e.shieldPersistent = shieldPersistent
        e.retaliate = retaliate
        e.retaliatePersistent = retaliatePersistent
        return e
    }
}

// MARK: - GameObjectiveContainer <-> ObjectiveContainerSnapshot

extension GameObjectiveContainer {
    func toSnapshot() -> ObjectiveContainerSnapshot {
        ObjectiveContainerSnapshot(
            uuid: uuid, name: name, edition: edition, title: title,
            escort: escort, level: level, off: off, active: active,
            initiative: initiative,
            entities: entities.map { $0.toSnapshot() }
        )
    }
}

extension ObjectiveContainerSnapshot {
    func toRuntime() -> GameObjectiveContainer {
        let o = GameObjectiveContainer(name: name, edition: edition, title: title, escort: escort, level: level)
        o.off = off
        o.active = active
        o.initiative = initiative
        o.entities = entities.map { $0.toRuntime() }
        return o
    }
}

// MARK: - GameObjectiveEntity <-> ObjectiveEntitySnapshot

extension GameObjectiveEntity {
    func toSnapshot() -> ObjectiveEntitySnapshot {
        ObjectiveEntitySnapshot(
            uuid: uuid, number: number, health: health, maxHealth: maxHealth,
            level: level, dead: dead, dormant: dormant, active: active, off: off,
            marker: marker,
            entityConditions: entityConditions, immunities: immunities,
            markers: markers, tags: tags,
            shield: shield, shieldPersistent: shieldPersistent,
            retaliate: retaliate, retaliatePersistent: retaliatePersistent
        )
    }
}

extension ObjectiveEntitySnapshot {
    func toRuntime() -> GameObjectiveEntity {
        let e = GameObjectiveEntity(number: number, health: health, maxHealth: maxHealth)
        e.level = level
        e.dead = dead
        e.dormant = dormant
        e.active = active
        e.off = off
        e.marker = marker
        e.entityConditions = entityConditions
        e.immunities = immunities
        e.markers = markers
        e.tags = tags
        e.shield = shield
        e.shieldPersistent = shieldPersistent
        e.retaliate = retaliate
        e.retaliatePersistent = retaliatePersistent
        return e
    }
}

// MARK: - GameSummon <-> SummonSnapshot

extension GameSummon {
    func toSnapshot() -> SummonSnapshot {
        SummonSnapshot(
            uuid: uuid, name: name, cardId: cardId, number: number, color: color,
            health: health, maxHealth: maxHealth, level: level,
            attack: attack, movement: movement, range: range, flying: flying,
            dead: dead, state: state, active: active, dormant: dormant, off: off,
            entityConditions: entityConditions, immunities: immunities,
            markers: markers, tags: tags,
            shield: shield, shieldPersistent: shieldPersistent,
            retaliate: retaliate, retaliatePersistent: retaliatePersistent
        )
    }
}

extension SummonSnapshot {
    func toRuntime() -> GameSummon {
        let s = GameSummon(
            name: name, cardId: cardId, number: number, color: color,
            health: health, maxHealth: maxHealth, level: level,
            attack: attack, movement: movement, range: range, flying: flying
        )
        s.dead = dead
        s.state = state
        s.active = active
        s.dormant = dormant
        s.off = off
        s.entityConditions = entityConditions
        s.immunities = immunities
        s.markers = markers
        s.tags = tags
        s.shield = shield
        s.shieldPersistent = shieldPersistent
        s.retaliate = retaliate
        s.retaliatePersistent = retaliatePersistent
        return s
    }
}

// MARK: - Scenario <-> ScenarioSnapshot

extension Scenario {
    func toSnapshot() -> ScenarioSnapshot {
        ScenarioSnapshot(
            edition: data.edition,
            index: data.index,
            isCustom: isCustom,
            revealedRooms: revealedRooms,
            additionalSections: additionalSections,
            appliedRules: appliedRules,
            disabledRules: disabledRules
        )
    }
}

extension ScenarioSnapshot {
    func toRuntime(editionStore: EditionDataStore) -> Scenario? {
        guard let scenarioData = editionStore.scenarioData(index: index, edition: edition) else {
            return nil
        }
        let scenario = Scenario(data: scenarioData, isCustom: isCustom)
        scenario.revealedRooms = revealedRooms
        scenario.additionalSections = additionalSections
        scenario.appliedRules = appliedRules
        scenario.disabledRules = disabledRules
        return scenario
    }
}
