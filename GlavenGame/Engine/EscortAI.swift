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
    /// Every enemy the attack is made against, where it targets more than one.
    var attackTargets: [PieceID] = []
}

/// Computes an escort objective's turn with the player-side monster AI: escorts treat monsters
/// as enemies and characters, summons and allied monsters as allies.
enum EscortAI {

    /// `destination`: the hexes its move heads for when the scenario says where ("Move 2 towards
    /// the altar"); it then walks there instead of toward an enemy.
    static func computeTurn(
        escort: GameObjectiveContainer,
        entity: GameObjectiveEntity,
        board: BoardState,
        gameState: GameState,
        destination: Set<HexCoord> = [],
        home: HexCoord? = nil
    ) -> EscortTurnResult {
        let pieceID = PieceID.objective(id: entity.number)
        // One who holds his place: back onto it if he has been moved off, then an attack on
        // every enemy beside him.
        if let strike = escort.standingAttack, let position = board.piecePositions[pieceID] {
            let stunned = MonsterAI.isActive(.stun, on: entity)
            var path: [HexCoord] = []
            if !stunned, !MonsterAI.isActive(.immobilize, on: entity), let home, home != position, !board.isOccupied(home) {
                let enemies = Set(PlayerSideAI.hostileMonsters(board: board, gameState: gameState, includeInvisible: true)
                    .compactMap { board.piecePositions[$0] })
                path = Pathfinder.findPath(board: board, from: position, to: home, canOpenDoors: false,
                                           occupiedByEnemy: enemies) ?? []
            }
            let stands = path.last ?? position
            let attack = MonsterAI.isActive(.disarm, on: entity) ? nil
                : MonsterAbility.attack(ActionModel(type: .attack, value: .int(0), valueType: .plus),
                                        stat: nil, baseAttack: strike, baseRange: 0)
            let targets = stunned || attack == nil ? [] : PlayerSideAI.hostileMonsters(board: board, gameState: gameState, includeInvisible: false)
                .filter { board.piecePositions[$0]?.distance(to: stands) == 1 }
            return EscortTurnResult(escortPieceID: pieceID, entityNumber: entity.number, movementPath: path,
                                    attackTarget: nil, attackFromHex: targets.isEmpty ? nil : stands, focusTarget: targets.first,
                                    stunned: stunned, attackValue: strike, attackRange: 0, attack: attack, attackTargets: targets)
        }
        if !destination.isEmpty, escort.escortMove > 0, let position = board.piecePositions[pieceID] {
            return EscortTurnResult(escortPieceID: pieceID, entityNumber: entity.number,
                                    movementPath: walk(from: position, toward: destination, entity: entity,
                                                       move: escort.escortMove, board: board, gameState: gameState),
                                    attackTarget: nil, attackFromHex: nil, focusTarget: nil,
                                    stunned: MonsterAI.isActive(.stun, on: entity), attackValue: 0, attackRange: 0)
        }
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

    /// As far along the shortest way to `destination` as its move takes it: around enemies,
    /// through doors, past traps where it can, never ending on another figure. Empty when it is
    /// there already, can't move (stunned, immobilized) or has no way.
    private static func walk(from position: HexCoord, toward destination: Set<HexCoord>, entity: GameObjectiveEntity,
                             move: Int, board: BoardState, gameState: GameState) -> [HexCoord] {
        guard !destination.contains(position), !MonsterAI.isActive(.stun, on: entity),
              !MonsterAI.isActive(.immobilize, on: entity) else { return [] }
        let enemies = Set(PlayerSideAI.hostileMonsters(board: board, gameState: gameState, includeInvisible: true)
            .compactMap { board.piecePositions[$0] })
        let others = Set(board.piecePositions.values).subtracting(enemies).subtracting([position])
        // A lettered hex that can't be stood on (an altar, or someone is there) is reached by
        // standing next to it.
        let taken = Set(board.piecePositions.values)
        let standable: (HexCoord) -> Bool = { board.isPassable($0) && !taken.contains($0) }
        let open = destination.filter(standable)
        let targets = open.isEmpty ? Set(destination.flatMap(\.neighbors).filter(standable)) : open
        guard !targets.contains(position) else { return [] }
        // It opens the doors in its way, and springs a trap only where no way avoids one.
        let way: (Set<HexCoord>) -> [HexCoord]? = { blocking in
            Pathfinder.cheapestTargetPath(board: board, from: position, targets: targets, avoidTraps: true,
                                          canOpenDoors: true, occupiedByEnemy: blocking, occupiedByAlly: others)?.path
        }
        // With enemies barring every way, it comes as near as it can along the way it would take.
        var route = way(enemies)
        if route == nil, let through = way([]) {
            route = Array(through.prefix { !enemies.contains($0) })
        }
        guard let route, route.count > 1 else { return [] }
        return MonsterAI.truncate(route, toBudget: move, board: board)
    }
}
