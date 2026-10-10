import Foundation

/// Result of computing a summon's turn.
struct SummonTurnResult {
    let summonPieceID: PieceID
    /// The path the summon moves along (empty if no movement).
    let movementPath: [HexCoord]
    /// The first attack target (nil if no attack).
    let attackTarget: PieceID?
    /// The hex to attack from (after movement).
    let attackFromHex: HexCoord?
    /// The focused enemy.
    let focusTarget: PieceID?
    /// Whether the summon is stunned and skipping its turn.
    let stunned: Bool
    /// The base attack value.
    let attackValue: Int
    /// The attack range.
    let attackRange: Int
    /// Every target of the attack (several for "Target N" summons).
    var attackTargets: [PieceID] = []
    /// The resolved attack (nil when the summon has no attack or is disarmed).
    var attack: MonsterAttackSpec? = nil
    var flying: Bool = false
    /// Every enemy it could focus on, best first, for "Why?".
    var focusCandidates: [FocusCandidate] = []
}

/// Monster-style AI for figures fighting on the players' side (summons, escorts): they follow
/// the monster focus and movement rules with friend and foe inverted (GH p.26).
enum PlayerSideAI {

    struct Plan {
        var focus: PieceID?
        var path: [HexCoord] = []
        var targets: [PieceID] = []
        var stunned = false
        /// Every enemy it could focus on, best first, for "Why?".
        var candidates: [FocusCandidate] = []
    }

    /// Compute focus, movement and targets for a player-side figure with fixed Move/Attack values.
    static func plan(pieceID: PieceID, entity: any Entity, move: Int, attack: MonsterAttackSpec?,
                     flying: Bool, board: BoardState, gameState: GameState) -> Plan {
        guard !MonsterAI.isActive(.stun, on: entity) else { return Plan(stunned: true) }
        guard let position = board.piecePositions[pieceID] else { return Plan() }

        let immobilized = MonsterAI.isActive(.immobilize, on: entity)
        let chill = entity.entityConditions.filter { $0.name == .chill && !$0.expired }
            .reduce(0) { $0 + max(1, $1.value) }
        let totalMove = immobilized ? 0 : max(0, move - chill)

        let enemies = hostileMonsters(board: board, gameState: gameState, includeInvisible: false)
        let blockers = Set(hostileMonsters(board: board, gameState: gameState, includeInvisible: true)
            .compactMap { board.piecePositions[$0] })
        let allies = Set(board.piecePositions.compactMap { id, coord in
            id != pieceID && !blockers.contains(coord) ? coord : nil
        })

        let range = attack?.range ?? 1
        let isRanged = attack?.isRanged ?? false
        let mode: MoveMode = flying ? .fly : .normal
        let candidates = MonsterAI.focusCandidates(from: position, enemies: enemies, board: board, range: range,
                                                   isRanged: isRanged, enemyPositions: blockers, gameState: gameState,
                                                   mode: mode)
        guard let focus = candidates.first?.pieceID,
              let focusPos = board.piecePositions[focus] else { return Plan() }

        var path: [HexCoord] = []
        if totalMove > 0 {
            let route = MonsterAI.findBestAttackPosition(
                from: position, focusPos: focusPos, focus: focus, range: range, moveRange: totalMove,
                isRanged: isRanged, attack: attack, enemies: enemies, board: board,
                enemyPositions: blockers, allyPositions: allies, gameState: gameState, mode: mode
            ).path ?? []
            path = MonsterAI.truncate(route, toBudget: totalMove, board: board, mode: mode)
        }

        var targets: [PieceID] = []
        if let attack, !MonsterAI.isActive(.disarm, on: entity) {
            targets = MonsterAI.targets(for: attack, from: path.last ?? position, focus: focus, focusPos: focusPos,
                                        enemies: enemies, board: board, gameState: gameState)
        }
        return Plan(focus: focus, path: path, targets: targets, candidates: candidates)
    }

    /// The players' side's enemies on the board: hostile (non-allied) monsters — invisible ones
    /// only when asked (they can't be focused or targeted, but still block movement) — and
    /// objectives to destroy (an altar, a barred door), which are enemies like any other.
    static func hostileMonsters(board: BoardState, gameState: GameState, includeInvisible: Bool) -> [PieceID] {
        board.piecePositions.keys.sorted().filter { id in
            if let (container, entity) = MonsterAI.objectiveEntity(id, gameState: gameState) {
                return !container.escort && !container.isProtected && entity.maxHealth > 0
            }
            guard let (group, entity) = MonsterAI.monsterEntity(id, gameState: gameState),
                  !MonsterAI.isAllyFaction(group) else { return false }
            return includeInvisible || !MonsterAI.isActive(.invisible, on: entity)
        }
    }
}

/// Computes a summon's turn: summons permanently follow "Move +0, Attack +0" with their own
/// stats, using their summoner's attack modifier deck (GH p.26).
enum SummonAI {

    static func computeTurn(
        summon: GameSummon,
        ownerCharacterID: String,
        board: BoardState,
        gameState: GameState
    ) -> SummonTurnResult {
        let pieceID = PieceID.summon(id: summon.id)
        let attack = attackSpec(for: summon)
        let plan = PlayerSideAI.plan(pieceID: pieceID, entity: summon, move: summon.movement, attack: attack,
                                     flying: summon.flying, board: board, gameState: gameState)
        return SummonTurnResult(
            summonPieceID: pieceID,
            movementPath: plan.path,
            attackTarget: plan.targets.first,
            attackFromHex: plan.targets.isEmpty ? nil : (plan.path.last ?? board.piecePositions[pieceID]),
            focusTarget: plan.focus,
            stunned: plan.stunned,
            attackValue: attack?.value ?? 0,
            attackRange: attack?.range ?? 0,
            attackTargets: plan.targets,
            attack: attack,
            flying: summon.flying,
            focusCandidates: plan.candidates
        )
    }

    /// The summon's attack, or nil for summons without one (e.g. Decoy, Monolith).
    static func attackSpec(for summon: GameSummon) -> MonsterAttackSpec? {
        if case .int(0) = summon.attack, summon.attackEffects.isEmpty { return nil }
        let attackAction = ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                       subActions: summon.attackEffects.filter { $0.type != .specialTarget })
        return MonsterAbility.attack(attackAction, stat: nil, baseAttack: summon.effectiveAttack,
                                     baseRange: summon.range)
    }
}
