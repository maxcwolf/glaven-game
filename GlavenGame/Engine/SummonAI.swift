import Foundation

/// Result of computing a summon's turn.
struct SummonTurnResult {
    let summonPieceID: PieceID
    /// The path the summon moves along (empty if no movement).
    let movementPath: [HexCoord]
    /// The attack target (nil if no attack).
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
}

/// Computes a summon's turn using monster-like AI with inverted friend/foe sets.
enum SummonAI {

    /// Compute a single summon's turn.
    /// Summons use monster AI but treat monsters as enemies and characters/other summons as allies.
    static func computeTurn(
        summon: GameSummon,
        ownerCharacterID: String,
        board: BoardState,
        gameState: GameState
    ) -> SummonTurnResult {
        let summonPieceID = PieceID.summon(id: summon.id)

        // Check if stunned
        if summon.entityConditions.contains(where: { $0.name == .stun && !$0.expired }) {
            return SummonTurnResult(
                summonPieceID: summonPieceID,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: true,
                attackValue: 0, attackRange: 0
            )
        }

        let isDisarmed = summon.entityConditions.contains(where: { $0.name == .disarm && !$0.expired })

        // Use summon's base stats (no ability card modifiers)
        let totalMove = summon.movement
        let totalAttack = summon.effectiveAttack
        let totalRange = max(summon.range, totalAttack > 0 ? 1 : 0)
        let isRanged = summon.range > 0

        guard let currentPos = board.piecePositions[summonPieceID] else {
            return SummonTurnResult(
                summonPieceID: summonPieceID,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        // Gather enemies = monsters on the board (excluding invisible)
        let enemies = gatherEnemies(board: board, gameState: gameState)
        let enemyPositions = Set(enemies.compactMap { board.piecePositions[$0] })
        // Allies = characters + other summons (excluding self)
        let allyPositions = gatherAllyPositions(board: board, excluding: summonPieceID)

        // Find focus (nearest monster to attack)
        guard let focus = MonsterAI.findFocus(
            from: currentPos,
            enemies: enemies,
            board: board,
            range: totalRange,
            isRanged: isRanged,
            enemyPositions: enemyPositions,
            gameState: gameState
        ) else {
            return SummonTurnResult(
                summonPieceID: summonPieceID,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        guard let focusPos = board.piecePositions[focus] else {
            return SummonTurnResult(
                summonPieceID: summonPieceID,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: focus, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        // Find best attack hex and path
        let (_, path) = MonsterAI.findBestAttackPosition(
            from: currentPos,
            focusPos: focusPos,
            range: totalRange,
            moveRange: totalMove,
            isRanged: isRanged,
            board: board,
            enemyPositions: enemyPositions,
            allyPositions: allyPositions
        )

        // Determine movement
        var movePath: [HexCoord] = []
        if let path = path, path.count > 1 {
            let maxSteps = min(totalMove, path.count - 1)
            movePath = Array(path.prefix(maxSteps + 1))
            while movePath.count > 1 && allyPositions.contains(movePath.last!) {
                movePath.removeLast()
            }
        }

        let finalPos = movePath.last ?? currentPos

        // Determine if we can attack the focus
        var attackTarget: PieceID? = nil
        if !isDisarmed && totalAttack > 0 {
            let canHitFocus = finalPos.distance(to: focusPos) <= totalRange &&
                              LineOfSight.hasLOS(from: finalPos, to: focusPos, board: board)
            if canHitFocus {
                attackTarget = focus
            }
        }

        return SummonTurnResult(
            summonPieceID: summonPieceID,
            movementPath: movePath,
            attackTarget: attackTarget,
            attackFromHex: attackTarget != nil ? finalPos : nil,
            focusTarget: focus,
            stunned: false,
            attackValue: totalAttack,
            attackRange: totalRange
        )
    }

    // MARK: - Helpers

    /// Gather all enemy piece IDs for a summon (= all monsters on the board), excluding invisible.
    private static func gatherEnemies(board: BoardState, gameState: GameState) -> [PieceID] {
        board.piecePositions.keys.filter { id in
            guard case .monster(let name, let standee) = id else { return false }
            // Exclude invisible monsters
            if let monster = gameState.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }),
               entity.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) {
                return false
            }
            return true
        }
    }

    /// Gather ally positions for a summon (= characters + other summons), excluding self.
    private static func gatherAllyPositions(board: BoardState, excluding: PieceID) -> Set<HexCoord> {
        var positions = Set<HexCoord>()
        for (id, coord) in board.piecePositions {
            guard id != excluding else { continue }
            switch id {
            case .character, .summon:
                positions.insert(coord)
            default:
                break
            }
        }
        return positions
    }
}
