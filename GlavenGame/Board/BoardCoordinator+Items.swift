import Foundation

/// Items used on the board (GH p.26): on the character's own turn, when the item's moment comes
/// — during their move, during their attack, or any time in their turn. A spent item is
/// refreshed by a long rest; a consumed one is gone for the scenario.
///
/// Played so far: the effects that happen on the user's own turn. Items that react to an enemy's
/// attack (armour, shields, the Iron Helmet) and ones that need a card picker (Minor Stamina
/// Potion) are still marked by hand on the character sheet.
enum BoardItemEffect: Equatable {
    case extraMove(Int)
    case jump
    case invisible
    case advantage
    case ignoreShields
    case attackCondition(ConditionName)
    case attackBonus(Int)
    case heal(Int)

    enum Moment: Equatable { case turn, move, attack, meleeAttack, rangedAttack }

    var moment: Moment {
        switch self {
        case .extraMove, .jump: return .move
        case .advantage, .attackBonus: return .attack
        case .ignoreShields: return .rangedAttack
        case .attackCondition: return .meleeAttack
        case .invisible, .heal: return .turn
        }
    }

    /// The board's effects, by item key.
    static let byItem: [String: BoardItemEffect] = [
        "gh-1": .extraMove(2),               // Boots of Striding
        "gh-2": .jump,                       // Winged Shoes
        "gh-5": .invisible,                  // Cloak of Invisibility
        "gh-6": .advantage,                  // Eagle-Eye Goggles
        "gh-9": .ignoreShields,              // Piercing Bow
        "gh-10": .attackCondition(.stun),    // War Hammer
        "gh-11": .attackCondition(.poison),  // Poison Dagger
        "gh-12": .heal(3),                   // Minor Healing Potion
        "gh-14": .attackBonus(1),            // Minor Power Potion
    ]
}

extension BoardCoordinator {

    /// The acting character's items that can be used right now.
    func usableItems() -> [ItemData] {
        guard let turn = activePlayerTurn, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == turn.characterID }) else { return [] }
        return character.items.compactMap { key -> ItemData? in
            guard !character.spentItems.contains(key), !character.consumedItems.contains(key),
                  let effect = BoardItemEffect.byItem[key], isMoment(effect.moment, for: turn),
                  let item = itemData(key) else { return nil }
            return item
        }
    }

    private func isMoment(_ moment: BoardItemEffect.Moment, for turn: PlayerTurnController) -> Bool {
        let me = PieceID.character(turn.characterID)
        switch (moment, interactionMode) {
        case (.turn, .watchingMonsterTurn), (.turn, .placingCharacter):
            return false
        case (.turn, _):
            return turn.phase == .executeTopAction || turn.phase == .executeBottomAction
        case (.move, .selectingMove(let mover, _, _, let teleport, _)):
            return mover == me && !teleport
        case (.attack, .selectingAttackTarget(let attacker, _, _)),
             (.attack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me
        case (.meleeAttack, .selectingAttackTarget(let attacker, _, _)),
             (.meleeAttack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me && turn.currentAttackRange() <= 1
        case (.rangedAttack, .selectingAttackTarget(let attacker, _, _)),
             (.rangedAttack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me && turn.currentAttackRange() > 1
        default:
            return false
        }
    }

    /// Use an item: its effect now, then it's spent or consumed, and counted for battle goals.
    @discardableResult
    func useItem(_ item: ItemData) -> Bool {
        guard usableItems().contains(where: { $0.itemKey == item.itemKey }),
              let turn = activePlayerTurn, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == turn.characterID }),
              let effect = BoardItemEffect.byItem[item.itemKey] else { return false }
        let me = PieceID.character(character.id)
        gameManager.characterManager.onBeforeMutate?()
        if item.consumed { character.consumedItems.insert(item.itemKey) } else { character.spentItems.insert(item.itemKey) }
        gameManager.scenarioStatsManager.recordItemUse(by: character.name)
        log("\(name(me)) uses \(item.name)", category: .info)

        switch effect {
        case .extraMove(let extra):
            if case .selectingMove(_, let range, _, _, let mode) = interactionMode {
                beginMoveAction(pieceID: me, moveRange: range + extra, mode: mode)
            }
        case .jump:
            if case .selectingMove(_, let range, _, _, _) = interactionMode {
                beginMoveAction(pieceID: me, moveRange: range, mode: .jump)
            }
        case .invisible:
            applyCondition(.invisible, to: me)
        case .advantage:
            turn.pendingAdvantage = true
        case .ignoreShields:
            turn.pendingPierce += 99
        case .attackCondition(let condition):
            turn.pendingConditions.append(condition)
        case .attackBonus(let bonus):
            turn.addToAttack(bonus)
        case .heal(let amount):
            let healed = heal(me, amount: amount, source: me)
            log("\(name(me)) heals for \(healed)", category: .heal, trace: "Heal \(amount), self")
        }
        return true
    }

    private func itemData(_ key: String) -> ItemData? {
        let parts = key.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        return gameManager?.editionStore.itemData(id: id, edition: String(parts[0]))
    }
}
