import Foundation

/// Result of computing an escort objective's turn.
struct EscortTurnResult {
    let escortPieceID: PieceID
    let entityNumber: Int
    /// The path the escort moves along (empty if no movement).
    let movementPath: [HexCoord]
    /// The attack target (nil if no attack).
    let attackTarget: PieceID?
    /// The hex to attack from (after movement).
    let attackFromHex: HexCoord?
    /// The focused enemy.
    let focusTarget: PieceID?
    /// Whether the escort is stunned and skipping its turn.
    let stunned: Bool
    /// The base attack value.
    let attackValue: Int
    /// The attack range (0 = melee).
    let attackRange: Int
}

/// Computes an escort objective's turn using summon-like AI.
/// Escorts treat monsters as enemies and characters/summons as allies.
enum EscortAI {

    /// Compute a single escort entity's turn.
    static func computeTurn(
        escort: GameObjectiveContainer,
        entity: GameObjectiveEntity,
        board: BoardState,
        gameState: GameState
    ) -> EscortTurnResult {
        let pieceID = PieceID.objective(id: entity.number)

        // Check if stunned
        if entity.entityConditions.contains(where: { $0.name == .stun && !$0.expired }) {
            return EscortTurnResult(
                escortPieceID: pieceID, entityNumber: entity.number,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: true,
                attackValue: 0, attackRange: 0
            )
        }

        let isDisarmed = entity.entityConditions.contains(where: { $0.name == .disarm && !$0.expired })

        // Get stats from escort's defined actions
        let totalMove = escort.escortMove
        let totalAttack = escort.escortAttack
        let totalRange = max(escort.escortRange, totalAttack > 0 ? 1 : 0)
        let isRanged = escort.escortRange > 0

        guard let currentPos = board.piecePositions[pieceID] else {
            return EscortTurnResult(
                escortPieceID: pieceID, entityNumber: entity.number,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        // Gather enemies = monsters on the board (excluding invisible)
        let enemies = gatherEnemies(board: board, gameState: gameState)
        let enemyPositions = Set(enemies.compactMap { board.piecePositions[$0] })
        // Allies = characters + summons + other escorts (excluding self)
        let allyPositions = gatherAllyPositions(board: board, excluding: pieceID)

        // No movement or attack — passive escort, skip
        if totalMove == 0 && totalAttack == 0 {
            return EscortTurnResult(
                escortPieceID: pieceID, entityNumber: entity.number,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: false,
                attackValue: 0, attackRange: 0
            )
        }

        // Find focus (nearest monster to attack)
        let effectiveRange = totalAttack > 0 ? totalRange : 1
        guard let focus = MonsterAI.findFocus(
            from: currentPos,
            enemies: enemies,
            board: board,
            range: effectiveRange,
            isRanged: isRanged,
            enemyPositions: enemyPositions,
            gameState: gameState
        ) else {
            return EscortTurnResult(
                escortPieceID: pieceID, entityNumber: entity.number,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: nil, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        guard let focusPos = board.piecePositions[focus] else {
            return EscortTurnResult(
                escortPieceID: pieceID, entityNumber: entity.number,
                movementPath: [], attackTarget: nil, attackFromHex: nil,
                focusTarget: focus, stunned: false,
                attackValue: totalAttack, attackRange: totalRange
            )
        }

        // Find best attack hex and path
        let (_, path) = MonsterAI.findBestAttackPosition(
            from: currentPos,
            focusPos: focusPos,
            range: effectiveRange,
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
            // Can't stop on an ally-occupied hex
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

        return EscortTurnResult(
            escortPieceID: pieceID, entityNumber: entity.number,
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

    /// Gather all enemy piece IDs for an escort (= all monsters on the board), excluding invisible.
    private static func gatherEnemies(board: BoardState, gameState: GameState) -> [PieceID] {
        board.piecePositions.keys.filter { id in
            guard case .monster(let name, let standee) = id else { return false }
            if let monster = gameState.monsters.first(where: { $0.name == name }),
               let entity = monster.entities.first(where: { $0.number == standee }),
               entity.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) {
                return false
            }
            return true
        }
    }

    /// Gather ally positions for an escort (= characters + summons + other objectives), excluding self.
    private static func gatherAllyPositions(board: BoardState, excluding: PieceID) -> Set<HexCoord> {
        var positions = Set<HexCoord>()
        for (id, coord) in board.piecePositions {
            guard id != excluding else { continue }
            switch id {
            case .character, .summon, .objective:
                positions.insert(coord)
            default:
                break
            }
        }
        return positions
    }
}
