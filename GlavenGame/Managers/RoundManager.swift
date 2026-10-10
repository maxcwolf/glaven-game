import Foundation

@Observable
final class RoundManager {
    private let game: GameState
    private let entityManager: EntityManager
    private let monsterManager: MonsterManager
    private let attackModifierManager: AttackModifierManager
    var onBeforeMutate: (() -> Void)?

    /// Called when a round starts, before monster ability cards are drawn — used by
    /// ScenarioRulesManager to evaluate start-of-round rules (spawns there still draw a card).
    var onRoundAdvanced: (() -> Void)?
    /// Called at the end of a round, before elements wane — evaluates end-of-round rules.
    var onRoundEnding: (() -> Void)?
    /// On the board, each summon and each monster standee takes its own turn, and the turn
    /// controllers tick their conditions; in the companion tracker summons are processed with
    /// their summoner and monsters as a group.
    var figuresTakeOwnTurns = false

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

        // Evaluate start-of-round scenario rules (spawns, stat changes) before drawing cards.
        onRoundAdvanced?()

        // Draw monster abilities and apply stat effects
        // (Not for a type that sits this round out.)
        let inactive = MonsterAI.inactiveMonsters(game)
        for monster in game.monsters where !monster.off && monster.aliveEntities.count > 0 && !inactive.contains(monster.name) {
            monsterManager.drawAbility(for: monster)
            monsterManager.applyStatEffects(for: monster)
        }

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
        // End-of-round scenario rules see the round that is ending, before elements wane.
        onRoundEnding?()
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
                // Round bonus cards leave the active area at the end of the round (p.24).
                for cardId in c.roundBonusCards { c.removeFromActiveArea(cardId) }
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
                monsterManager.finishRound(for: m)
                for entity in m.entities {
                    entity.active = false
                    // Monsters summoned this round act from the next round on.
                    if entity.summonState == .new { entity.summonState = .active }
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
                if !figuresTakeOwnTurns {
                    for entity in m.aliveEntities { afterTurnEntity(entity) }
                }
                m.active = false
            } else {
                m.active = true
                if !figuresTakeOwnTurns {
                    for entity in m.aliveEntities { beforeTurnEntity(entity) }
                }
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
        entityManager.restoreConditions(character)
        entityManager.applyConditionsTurn(character)
        if !figuresTakeOwnTurns {
            for summon in character.summons where !summon.dead {
                entityManager.restoreConditions(summon)
                entityManager.applyConditionsTurn(summon)
            }
        }

        // Long rest: "Heal 2, Self" as part of the resting turn, after start-of-turn wound damage.
        // Healing follows the normal rules (poison blocks it; it removes poison and wound).
        if character.longRest && character.health > 0 {
            entityManager.heal(character, amount: 2)
            character.spentItems.removeAll()
            character.itemSlotsUsed.removeAll()
        }
    }

    private func afterTurn(character: GameCharacter) {
        entityManager.expireConditions(character)
        if !figuresTakeOwnTurns {
            for summon in character.summons where !summon.dead {
                entityManager.expireConditions(summon)
            }
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
