import Foundation

/// Result of computing a monster's turn.
struct MonsterTurnResult {
    let entityID: PieceID
    let monsterName: String
    let standeeNumber: Int
    /// The path the monster moves along (empty if no movement).
    let movementPath: [HexCoord]
    /// All pieces being attacked (ordered; first is focus target, rest are additional targets).
    let attackTargets: [PieceID]
    /// The hex to attack from (after movement).
    let attackFromHex: HexCoord?
    /// The focused enemy (may differ from attack targets if can't reach).
    let focusTarget: PieceID?
    /// Whether the monster is stunned and skipping its turn.
    let stunned: Bool
    /// Whether the monster is disarmed (moves toward focus but can't attack).
    let disarmed: Bool
    /// The ability card actions to apply after movement/attack.
    let abilityActions: [ActionModel]
    /// The initiative of the ability card drawn.
    let initiative: Int
}

/// Implements Gloomhaven's monster AI focus/movement algorithm.
enum MonsterAI {

    /// Compute a single monster entity's turn.
    /// - Parameters:
    ///   - pieceID: The piece ID of this entity on the board
    ///   - monster: The GameMonster group this entity belongs to
    ///   - entity: The specific GameMonsterEntity
    ///   - ability: The drawn ability card
    ///   - board: Current board state
    ///   - gameState: Current game state (for player count, initiative tiebreakers)
    static func computeTurn(
        pieceID: PieceID,
        monster: GameMonster,
        entity: GameMonsterEntity,
        ability: AbilityModel,
        board: BoardState,
        gameState: GameState
    ) -> MonsterTurnResult {
        let standee = entity.number

        // Check if stunned
        if entity.entityConditions.contains(where: { $0.name == .stun && !$0.expired }) {
            return MonsterTurnResult(
                entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
                movementPath: [], attackTargets: [], attackFromHex: nil,
                focusTarget: nil, stunned: true, disarmed: false,
                abilityActions: [], initiative: ability.initiative
            )
        }

        let isDisarmed = entity.entityConditions.contains(where: { $0.name == .disarm && !$0.expired })

        // Get stat card values
        let stat = monster.stat(for: entity.type)
        let baseMove = stat?.movement?.intValue ?? 0
        let baseAttack = stat?.attack?.intValue ?? 0
        let baseRange = stat?.range?.intValue ?? 0

        // Parse ability card modifiers
        let (moveModifier, attackModifier, rangeModifier, extraActions) = parseAbilityCard(ability)

        let totalMove = max(0, baseMove + moveModifier)
        let totalAttack = baseAttack + attackModifier
        let totalRange = max(baseRange + rangeModifier, totalAttack > 0 ? 1 : 0) // melee has range 1
        let isMelee = (baseRange + rangeModifier) <= 0
        let isRanged = !isMelee

        // Get current position
        guard let currentPos = board.piecePositions[pieceID] else {
            return MonsterTurnResult(
                entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
                movementPath: [], attackTargets: [], attackFromHex: nil,
                focusTarget: nil, stunned: false, disarmed: isDisarmed,
                abilityActions: extraActions, initiative: ability.initiative
            )
        }

        // Parse target count from ability card (Target sub-action on Attack)
        let targetCount = parseTargetCount(ability)

        // Gather enemy positions (characters + summons that aren't allies, excluding invisible)
        let enemies = gatherEnemies(board: board, monster: monster, gameState: gameState)
        let enemyPositions = Set(enemies.compactMap { board.piecePositions[$0] })
        let allyPositions = gatherAllyPositions(board: board, monster: monster, excluding: pieceID)

        // Find focus
        guard let focus = findFocus(
            from: currentPos,
            enemies: enemies,
            board: board,
            range: totalRange,
            isRanged: isRanged,
            enemyPositions: enemyPositions,
            gameState: gameState
        ) else {
            // No focus found — stay put
            return MonsterTurnResult(
                entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
                movementPath: [], attackTargets: [], attackFromHex: nil,
                focusTarget: nil, stunned: false, disarmed: isDisarmed,
                abilityActions: extraActions, initiative: ability.initiative
            )
        }

        guard let focusPos = board.piecePositions[focus] else {
            return MonsterTurnResult(
                entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
                movementPath: [], attackTargets: [], attackFromHex: nil,
                focusTarget: focus, stunned: false, disarmed: isDisarmed,
                abilityActions: extraActions, initiative: ability.initiative
            )
        }

        // Find best attack hex and path
        let (_, path) = findBestAttackPosition(
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
            // Move along the path, limited by movement points
            let maxSteps = min(totalMove, path.count - 1)
            movePath = Array(path.prefix(maxSteps + 1))
            // Can't stop on ally-occupied hex — step back until we find an empty hex
            while movePath.count > 1 && allyPositions.contains(movePath.last!) {
                movePath.removeLast()
            }
        }

        let finalPos = movePath.last ?? currentPos

        // Determine if we can attack the focus
        var attackTargets: [PieceID] = []

        if !isDisarmed && totalAttack > 0 {
            let canHitFocus = finalPos.distance(to: focusPos) <= totalRange &&
                              LineOfSight.hasLOS(from: finalPos, to: focusPos, board: board)
            if canHitFocus {
                attackTargets.append(focus)

                // Find additional targets if ability has Target > 1
                if targetCount > 1 {
                    let additionalTargets = findAdditionalTargets(
                        from: finalPos,
                        primaryTarget: focus,
                        enemies: enemies,
                        board: board,
                        range: totalRange,
                        count: targetCount - 1,
                        gameState: gameState
                    )
                    attackTargets.append(contentsOf: additionalTargets)
                }
            }
        }

        return MonsterTurnResult(
            entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
            movementPath: movePath, attackTargets: attackTargets,
            attackFromHex: !attackTargets.isEmpty ? finalPos : nil,
            focusTarget: focus, stunned: false, disarmed: isDisarmed,
            abilityActions: extraActions, initiative: ability.initiative
        )
    }

    // MARK: - Focus Algorithm

    /// Find the monster's focus target.
    /// Focus = enemy with lowest path cost to attack → tiebreak by proximity → tiebreak by initiative.
    static func findFocus(
        from position: HexCoord,
        enemies: [PieceID],
        board: BoardState,
        range: Int,
        isRanged: Bool,
        enemyPositions: Set<HexCoord>,
        gameState: GameState
    ) -> PieceID? {
        struct FocusCandidate {
            let pieceID: PieceID
            let pathCost: Int
            let proximity: Int
            let initiative: Double
        }

        var candidates: [FocusCandidate] = []

        for enemy in enemies {
            guard let enemyPos = board.piecePositions[enemy] else { continue }

            // Find valid attack hexes for this enemy
            let attackHexes = findAttackHexes(
                target: enemyPos, range: range, board: board,
                enemyPositions: enemyPositions, sourcePosition: position
            )

            if attackHexes.isEmpty { continue }

            // Find path cost to cheapest attack hex
            guard let result = Pathfinder.cheapestTarget(
                board: board, from: position, targets: attackHexes,
                occupiedByEnemy: enemyPositions
            ) else { continue }

            let proximity = position.distance(to: enemyPos)
            let initiative = enemyInitiative(enemy, gameState: gameState)

            candidates.append(FocusCandidate(
                pieceID: enemy,
                pathCost: result.cost,
                proximity: proximity,
                initiative: initiative
            ))
        }

        // Sort: lowest path cost → lowest proximity → lowest initiative
        candidates.sort { a, b in
            if a.pathCost != b.pathCost { return a.pathCost < b.pathCost }
            if a.proximity != b.proximity { return a.proximity < b.proximity }
            return a.initiative < b.initiative
        }

        return candidates.first?.pieceID
    }

    /// Find all valid attack hexes to hit a target from.
    static func findAttackHexes(
        target: HexCoord,
        range: Int,
        board: BoardState,
        enemyPositions: Set<HexCoord>,
        sourcePosition: HexCoord
    ) -> Set<HexCoord> {
        var hexes = Set<HexCoord>()

        // For range 1 (melee), check all neighbors of the target
        if range <= 1 {
            for neighbor in target.neighbors {
                guard board.isPassable(neighbor) else { continue }
                // Can be source position or unoccupied (can't stop on any occupied hex)
                guard neighbor == sourcePosition || !board.isOccupied(neighbor) else { continue }
                hexes.insert(neighbor)
            }
        } else {
            // For ranged attacks, find all hexes within range with LOS
            // Use a BFS to find all hexes within range
            for (coord, cell) in board.cells {
                guard cell.passable else { continue }
                guard coord.distance(to: target) <= range else { continue }
                guard coord == sourcePosition || !board.isOccupied(coord) else { continue }
                guard LineOfSight.hasLOS(from: coord, to: target, board: board) else { continue }
                hexes.insert(coord)
            }
        }

        return hexes
    }

    /// Find the best attack position and path to it.
    static func findBestAttackPosition(
        from position: HexCoord,
        focusPos: HexCoord,
        range: Int,
        moveRange: Int,
        isRanged: Bool,
        board: BoardState,
        enemyPositions: Set<HexCoord>,
        allyPositions: Set<HexCoord>
    ) -> (attackHex: HexCoord?, path: [HexCoord]?) {
        // Find all valid attack hexes
        let attackHexes = findAttackHexes(
            target: focusPos, range: range, board: board,
            enemyPositions: enemyPositions, sourcePosition: position
        )

        if attackHexes.isEmpty { return (nil, nil) }

        // Already in an attack hex?
        if attackHexes.contains(position) {
            // For ranged monsters adjacent to target, try to move away to avoid disadvantage
            if isRanged && position.isAdjacent(to: focusPos) && moveRange > 0 {
                // Find a non-adjacent attack hex within movement range
                let reachable = Pathfinder.reachableHexes(
                    board: board, from: position, range: moveRange,
                    occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions
                )
                let nonAdjacentAttackHexes = attackHexes.filter {
                    !$0.isAdjacent(to: focusPos) && reachable[$0] != nil
                }
                if let best = nonAdjacentAttackHexes.min(by: { reachable[$0]! < reachable[$1]! }) {
                    let path = Pathfinder.findPath(
                        board: board, from: position, to: best,
                        occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions
                    )
                    return (best, path)
                }
            }
            return (position, nil) // Already in position
        }

        // Find cheapest attack hex to reach
        guard let result = Pathfinder.cheapestTarget(
            board: board, from: position, targets: attackHexes,
            occupiedByEnemy: enemyPositions
        ) else {
            // Can't reach any attack hex — move toward closest one
            let closest = attackHexes.min(by: { position.distance(to: $0) < position.distance(to: $1) })
            if let target = closest {
                let path = Pathfinder.findPath(
                    board: board, from: position, to: target,
                    occupiedByEnemy: enemyPositions
                )
                return (target, path)
            }
            return (nil, nil)
        }

        let path = Pathfinder.findPath(
            board: board, from: position, to: result.target,
            occupiedByEnemy: enemyPositions
        )
        return (result.target, path)
    }

    // MARK: - Multi-Target

    /// Parse the target count from an ability card. Defaults to 1.
    /// Looks for a `.target` sub-action on any `.attack` action.
    private static func parseTargetCount(_ ability: AbilityModel) -> Int {
        for action in ability.actions ?? [] {
            if action.type == .attack {
                for sub in action.subActions ?? [] {
                    if sub.type == .target, let val = sub.value?.intValue, val > 1 {
                        return val
                    }
                }
            }
        }
        return 1
    }

    /// Find additional attack targets beyond the primary focus.
    /// Per Gloomhaven rules: closest enemies within range + LOS, tiebreaking by proximity then initiative.
    private static func findAdditionalTargets(
        from position: HexCoord,
        primaryTarget: PieceID,
        enemies: [PieceID],
        board: BoardState,
        range: Int,
        count: Int,
        gameState: GameState
    ) -> [PieceID] {
        struct Candidate {
            let pieceID: PieceID
            let distance: Int
            let initiative: Double
        }

        var candidates: [Candidate] = []
        for enemy in enemies {
            guard enemy != primaryTarget else { continue }
            guard let enemyPos = board.piecePositions[enemy] else { continue }
            let dist = position.distance(to: enemyPos)
            guard dist <= range else { continue }
            guard LineOfSight.hasLOS(from: position, to: enemyPos, board: board) else { continue }
            candidates.append(Candidate(
                pieceID: enemy,
                distance: dist,
                initiative: enemyInitiative(enemy, gameState: gameState)
            ))
        }

        // Sort: closest first, then lowest initiative
        candidates.sort { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            return a.initiative < b.initiative
        }

        return Array(candidates.prefix(count).map(\.pieceID))
    }

    // MARK: - Helpers

    /// Gather all enemy piece IDs (characters and their summons), excluding invisible figures.
    static func gatherEnemies(board: BoardState, monster: GameMonster, gameState: GameState) -> [PieceID] {
        board.piecePositions.keys.filter { id in
            switch id {
            case .character(let charID):
                guard !monster.isAlly && !monster.isAllied else { return false }
                // Exclude invisible characters
                if let char = gameState.characters.first(where: { $0.id == charID }),
                   char.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) {
                    return false
                }
                return true
            case .summon(let summonID):
                guard !monster.isAlly && !monster.isAllied else { return false }
                // Exclude invisible summons
                for char in gameState.characters {
                    if let summon = char.summons.first(where: { $0.id == summonID }),
                       summon.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) {
                        return false
                    }
                }
                return true
            case .monster: return false
            case .objective: return false
            }
        }
    }

    /// Gather ally positions (other monsters), excluding self.
    static func gatherAllyPositions(board: BoardState, monster: GameMonster, excluding: PieceID) -> Set<HexCoord> {
        var positions = Set<HexCoord>()
        for (id, coord) in board.piecePositions {
            guard id != excluding else { continue }
            if case .monster = id { positions.insert(coord) }
        }
        return positions
    }

    /// Get effective initiative for an enemy (for focus tiebreaking).
    static func enemyInitiative(_ pieceID: PieceID, gameState: GameState) -> Double {
        switch pieceID {
        case .character(let charID):
            if let char = gameState.characters.first(where: { $0.id == charID }) {
                return Double(char.initiative)
            }
            return 100
        case .summon(let summonID):
            // Find the character that owns this summon
            for char in gameState.characters {
                if char.summons.contains(where: { $0.id == summonID }) {
                    return Double(char.initiative) + 0.5 // Summons act after owner
                }
            }
            return 100.5
        default:
            return 100
        }
    }

    /// Parse an ability card for move/attack/range modifiers and extra actions.
    private static func parseAbilityCard(_ ability: AbilityModel) -> (move: Int, attack: Int, range: Int, extra: [ActionModel]) {
        var moveModifier = 0
        var attackModifier = 0
        var rangeModifier = 0
        var extraActions: [ActionModel] = []

        for action in ability.actions ?? [] {
            switch action.type {
            case .move:
                if let val = action.value?.intValue {
                    moveModifier += applyValueType(val, action.valueType)
                }
            case .attack:
                if let val = action.value?.intValue {
                    attackModifier += applyValueType(val, action.valueType)
                }
                // Check subActions for range modifier
                for sub in action.subActions ?? [] {
                    if sub.type == .range, let val = sub.value?.intValue {
                        rangeModifier += applyValueType(val, sub.valueType)
                    }
                }
            case .range:
                if let val = action.value?.intValue {
                    rangeModifier += applyValueType(val, action.valueType)
                }
            default:
                extraActions.append(action)
            }
        }

        return (moveModifier, attackModifier, rangeModifier, extraActions)
    }

    /// Apply a value type modifier.
    private static func applyValueType(_ value: Int, _ type: ActionValueType?) -> Int {
        switch type {
        case .plus, .add, .addition: return value
        case .minus, .subtract: return -value
        case .fixed, nil: return value
        }
    }
}
