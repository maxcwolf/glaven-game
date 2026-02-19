import Foundation

@Observable
final class RoundManager {
    private let game: GameState
    private let entityManager: EntityManager
    private let monsterManager: MonsterManager
    private let attackModifierManager: AttackModifierManager
    var onBeforeMutate: (() -> Void)?

    /// Called after round advances — used by ScenarioRulesManager to evaluate rules
    var onRoundAdvanced: (() -> Void)?

    init(game: GameState, entityManager: EntityManager,
         monsterManager: MonsterManager, attackModifierManager: AttackModifierManager) {
        self.game = game
        self.entityManager = entityManager
        self.monsterManager = monsterManager
        self.attackModifierManager = attackModifierManager
    }

    func nextGameState() {
        onBeforeMutate?()
        switch game.state {
        case .draw:
            transitionToNext()
        case .next:
            transitionToDraw()
        }
    }

    private func transitionToNext() {
        game.state = .next
        game.round += 1

        // Advance new elements to strong
        for i in game.elementBoard.indices {
            if game.elementBoard[i].state == .new {
                game.elementBoard[i].state = .strong
            }
        }

        // Draw monster abilities and apply stat effects
        for monster in game.monsters where !monster.off && monster.aliveEntities.count > 0 {
            monsterManager.drawAbility(for: monster)
            monsterManager.applyStatEffects(for: monster)
        }

        // Evaluate scenario rules for this round
        onRoundAdvanced?()

        // Sort figures by initiative
        game.figures.sort { a, b in
            let initA = effectiveInitiative(for: a)
            let initB = effectiveInitiative(for: b)
            if initA != initB { return initA < initB }
            if a.figureType != b.figureType {
                return a.figureType == .character
            }
            return a.name < b.name
        }
    }

    private func transitionToDraw() {
        game.state = .draw
        game.totalSeconds += game.playSeconds
        game.playSeconds = 0

        // Advance element states: strong->waning, waning->inert
        for i in game.elementBoard.indices {
            let state = game.elementBoard[i].state
            if state == .strong || state == .new {
                game.elementBoard[i].state = .waning
            } else if state == .waning {
                game.elementBoard[i].state = .inert
            }
        }

        // Reset figure states
        for figure in game.figures {
            switch figure {
            case .character(let c):
                c.active = false
                c.initiative = 0
                c.longRest = false
                // Reset shield/retaliate
                c.shield = nil
                c.retaliate = []
                // Reset summon states
                for summon in c.summons {
                    summon.active = false
                    if summon.state == .new { summon.state = .active }
                }
            case .monster(let m):
                m.active = false
                m.ability = -1
                for entity in m.entities {
                    entity.active = false
                    // Reset shield/retaliate
                    entity.shield = nil
                    entity.retaliate = []
                }
            case .objective(let o):
                o.active = false
            }
        }

        // Shuffle AM decks if needed
        if game.monsterAttackModifierDeck.needsShuffle {
            attackModifierManager.shuffleDeck(&game.monsterAttackModifierDeck)
        }
        if game.allyAttackModifierDeck.needsShuffle {
            attackModifierManager.shuffleDeck(&game.allyAttackModifierDeck)
        }
        for character in game.characters {
            if character.attackModifierDeck.needsShuffle {
                attackModifierManager.shuffleDeck(&character.attackModifierDeck)
            }
        }
    }

    func toggleFigure(_ figure: AnyFigure) {
        onBeforeMutate?()
        switch figure {
        case .character(let c):
            if c.active {
                afterTurn(character: c)
                c.active = false
            } else {
                c.active = true
                beforeTurn(character: c)
            }
        case .monster(let m):
            if m.active {
                for entity in m.aliveEntities { afterTurnEntity(entity) }
                m.active = false
            } else {
                m.active = true
                for entity in m.aliveEntities { beforeTurnEntity(entity) }
            }
        case .objective(let o):
            o.active.toggle()
        }

        // Advance consumed elements to inert after any turn
        for i in game.elementBoard.indices {
            if game.elementBoard[i].state == .consumed || game.elementBoard[i].state == .partlyConsumed {
                game.elementBoard[i].state = .inert
            }
            if game.elementBoard[i].state == .new {
                game.elementBoard[i].state = .strong
            }
        }
    }

    private func beforeTurn(character: GameCharacter) {
        // Long rest: heal 2, remove wound and poison
        if character.longRest {
            entityManager.changeHealth(character, amount: 2)
            entityManager.removeCondition(.wound, from: character)
            entityManager.removeCondition(.poison, from: character)
        }

        entityManager.restoreConditions(character)
        entityManager.applyConditionsTurn(character)
        for summon in character.summons where !summon.dead {
            entityManager.restoreConditions(summon)
            entityManager.applyConditionsTurn(summon)
        }
    }

    private func afterTurn(character: GameCharacter) {
        entityManager.expireConditions(character)
        for summon in character.summons where !summon.dead {
            entityManager.expireConditions(summon)
            if summon.state == .new { summon.state = .active }
        }
    }

    private func beforeTurnEntity(_ entity: GameMonsterEntity) {
        entityManager.restoreConditions(entity)
        entityManager.applyConditionsTurn(entity)
    }

    private func afterTurnEntity(_ entity: GameMonsterEntity) {
        entityManager.expireConditions(entity)
    }

    func drawAvailable() -> Bool {
        game.characters.allSatisfy { c in
            c.exhausted || c.absent || c.initiative > 0 || c.longRest
        }
    }

    func resetScenario() {
        onBeforeMutate?()
        game.figures.removeAll()
        game.round = 0
        game.state = .draw
        game.elementBoard = ElementModel.defaultBoard()
        game.monsterAttackModifierDeck = .defaultDeck()
        game.allyAttackModifierDeck = .defaultDeck()
        game.lootDeck = LootDeck()
    }

    private func effectiveInitiative(for figure: AnyFigure) -> Double {
        switch figure {
        case .character(let c):
            return c.effectiveInitiative
        case .monster(let m):
            if let init_ = monsterManager.currentAbilityInitiative(for: m) {
                return Double(init_)
            }
            return 100
        case .objective(let o):
            return Double(o.initiative) - 0.5
        }
    }
}
