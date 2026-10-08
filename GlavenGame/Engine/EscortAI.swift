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
    /// The resolved attack (nil when the escort has no attack or is disarmed).
    var attack: MonsterAttackSpec? = nil
}

/// Computes an escort objective's turn with the player-side monster AI: escorts treat monsters
/// as enemies and characters, summons and allied monsters as allies.
enum EscortAI {

    static func computeTurn(
        escort: GameObjectiveContainer,
        entity: GameObjectiveEntity,
        board: BoardState,
        gameState: GameState
    ) -> EscortTurnResult {
        let pieceID = PieceID.objective(id: entity.number)
        let attackAction = escort.escortActions.first { $0.type == .attack }
        let attack = attackAction.map {
            MonsterAbility.attack(ActionModel(type: .attack, value: .int(0), valueType: .plus,
                                              subActions: $0.subActions),
                                  stat: nil, baseAttack: escort.escortAttack, baseRange: escort.escortRange)
        }

        // Passive escorts (no move or attack) don't act.
        guard escort.escortMove > 0 || attack != nil else {
            return EscortTurnResult(escortPieceID: pieceID, entityNumber: entity.number, movementPath: [],
                                    attackTarget: nil, attackFromHex: nil, focusTarget: nil,
                                    stunned: MonsterAI.isActive(.stun, on: entity), attackValue: 0, attackRange: 0)
        }

        let plan = PlayerSideAI.plan(pieceID: pieceID, entity: entity, move: escort.escortMove, attack: attack,
                                     flying: false, board: board, gameState: gameState)
        return EscortTurnResult(
            escortPieceID: pieceID,
            entityNumber: entity.number,
            movementPath: plan.path,
            attackTarget: plan.targets.first,
            attackFromHex: plan.targets.isEmpty ? nil : (plan.path.last ?? board.piecePositions[pieceID]),
            focusTarget: plan.focus,
            stunned: plan.stunned,
            attackValue: attack?.value ?? 0,
            attackRange: attack?.range ?? 0,
            attack: attack
        )
    }
}
