import Foundation

/// Result of computing a monster's turn.
struct MonsterTurnResult {
    let entityID: PieceID
    let monsterName: String
    let standeeNumber: Int
    /// The path the monster moves along (empty if no movement).
    let movementPath: [HexCoord]
    /// All pieces being attacked by the card's first attack (ordered; first is the focus).
    let attackTargets: [PieceID]
    /// The hex to attack from (after movement).
    let attackFromHex: HexCoord?
    /// The focused enemy (may differ from attack targets if can't reach).
    let focusTarget: PieceID?
    /// Whether the monster is stunned and skipping its turn.
    let stunned: Bool
    /// Whether the monster is disarmed (moves toward focus but can't attack).
    let disarmed: Bool
    /// The ability card actions that are neither Move nor Attack (heal, conditions, elements…).
    let abilityActions: [ActionModel]
    /// The initiative of the ability card drawn.
    let initiative: Int
    /// Push steps from attack sub-actions (applied to each attack target after damage).
    let pendingPush: Int
    /// Pull steps from attack sub-actions (applied to each attack target after damage).
    let pendingPull: Int
    /// The card's first attack, resolved against the stat card (nil if the card has no attack).
    var attack: MonsterAttackSpec? = nil
    /// Whether the movement is a jump.
    var jumping: Bool = false
    /// Every enemy it could focus on, best first (the first is the focus), and why: for the
    /// learning mode's "Why?".
    var focusCandidates: [FocusCandidate] = []
}

/// An enemy a monster could focus on, and what decided it (p.30): first the fewest traps and
/// hazards on the way, then the least movement to attack it, then the nearest, then the one
/// acting first.
struct FocusCandidate: Equatable {
    let pieceID: PieceID
    let negativeHexes: Int
    let pathCost: Int
    let proximity: Int
    let initiative: Double

    /// What set the first of two candidates ahead of the second.
    enum Reason: Equatable { case traps, movement, proximity, initiative }

    static func reason(_ a: FocusCandidate, over b: FocusCandidate) -> Reason {
        if a.negativeHexes != b.negativeHexes { return .traps }
        if a.pathCost != b.pathCost { return .movement }
        if a.proximity != b.proximity { return .proximity }
        return .initiative
    }

    static func ordered(_ a: FocusCandidate, _ b: FocusCandidate) -> Bool {
        if a.negativeHexes != b.negativeHexes { return a.negativeHexes < b.negativeHexes }
        if a.pathCost != b.pathCost { return a.pathCost < b.pathCost }
        if a.proximity != b.proximity { return a.proximity < b.proximity }
        return a.initiative < b.initiative
    }
}

/// Implements Gloomhaven's monster AI focus/movement algorithm (GH p.29–31).
enum MonsterAI {

    /// Compute a single monster entity's turn: focus, movement, and the targets of its first attack.
    /// - Parameters:
    ///   - pieceID: The piece ID of this entity on the board
    ///   - monster: The GameMonster group this entity belongs to
    ///   - entity: The specific GameMonsterEntity
    ///   - ability: The drawn ability card
    ///   - board: Current board state
    ///   - gameState: Current game state (for player count, initiative tiebreakers)
    ///   - consumed: Element-consume actions this monster type paid for this turn
    static func computeTurn(
        pieceID: PieceID,
        monster: GameMonster,
        entity: GameMonsterEntity,
        ability: AbilityModel,
        board: BoardState,
        gameState: GameState,
        consumed: Set<UUID> = []
    ) -> MonsterTurnResult {
        let standee = entity.number
        let actions = ability.actions ?? []

        var candidates: [FocusCandidate] = []
        func result(path: [HexCoord] = [], targets: [PieceID] = [], from: HexCoord? = nil,
                    focus: PieceID? = nil, stunned: Bool = false, disarmed: Bool = false,
                    attack: MonsterAttackSpec? = nil, jumping: Bool = false) -> MonsterTurnResult {
            MonsterTurnResult(
                entityID: pieceID, monsterName: monster.name, standeeNumber: standee,
                movementPath: path, attackTargets: targets, attackFromHex: from,
                focusTarget: focus, stunned: stunned, disarmed: disarmed,
                abilityActions: actions.filter { $0.type != .move && $0.type != .attack },
                initiative: ability.initiative,
                pendingPush: attack?.push ?? 0, pendingPull: attack?.pull ?? 0,
                attack: attack, jumping: jumping, focusCandidates: candidates
            )
        }

        if isActive(.stun, on: entity) {
            return result(stunned: true)
        }

        let isDisarmed = isActive(.disarm, on: entity)
        let isImmobilized = isActive(.immobilize, on: entity)

        // Stat card values (expressions such as "1+C" are evaluated).
        let stat = monster.attackStat(for: entity.type)
        let characterCount = max(2, gameState.characters.filter { !$0.absent }.count)
        func statValue(_ value: IntOrString?) -> Int {
            guard let value else { return 0 }
            return evaluateEntityValue(value, level: monster.level, characterCount: characterCount)
        }
        let baseMove = statValue(stat?.movement)
        let baseAttack = stat?.attackValue(characterCount: characterCount, level: monster.level,
                                           variables: attackVariables(for: monster, gameState: gameState)) ?? 0
        let baseRange = statValue(stat?.range)

        // Move: only if the card has a Move action. Chill (FH) reduces it; Immobilize prevents it.
        let moveSpec = MonsterAbility.move(in: actions, baseMove: baseMove)
        let chillReduction = entity.entityConditions
            .filter { $0.name == .chill && !$0.expired }
            .reduce(0) { $0 + max(1, $1.value) }
        let totalMove = (isImmobilized || moveSpec == nil) ? 0 : max(0, (moveSpec?.value ?? 0) - chillReduction)

        // Attack: the card's first Attack action. A card without an attack still finds a focus
        // as if it had a melee attack (p.30).
        let attackSpec = actions.first(where: { $0.type == .attack }).map {
            MonsterAbility.attack($0, stat: stat, baseAttack: baseAttack, baseRange: baseRange, consumed: consumed)
        }
        let focusRange = attackSpec?.range ?? 1
        let isRanged = attackSpec?.isRanged ?? false
        let mode: MoveMode = monster.monsterData?.flying == true ? .fly : (moveSpec?.jump == true ? .jump : .normal)

        guard let currentPos = board.piecePositions[pieceID] else {
            return result(disarmed: isDisarmed, attack: attackSpec)
        }

        // Focus candidates exclude invisible figures, but every enemy figure blocks movement.
        let enemies = gatherEnemies(board: board, monster: monster, gameState: gameState)
        let blockingPositions = movementBlockers(board: board, monster: monster, gameState: gameState)
        let allyPositions = gatherAllyPositions(board: board, monster: monster, excluding: pieceID)

        candidates = focusCandidates(
            from: currentPos,
            enemies: enemies,
            board: board,
            range: focusRange,
            isRanged: isRanged,
            enemyPositions: blockingPositions,
            gameState: gameState,
            mode: mode,
            attack: attackSpec
        )
        guard let focus = findFocus(
            from: currentPos,
            enemies: enemies,
            board: board,
            range: focusRange,
            isRanged: isRanged,
            enemyPositions: blockingPositions,
            gameState: gameState,
            mode: mode,
            attack: attackSpec
        ), let focusPos = board.piecePositions[focus] else {
            // No focus: the monster neither moves nor attacks (p.30).
            return result(disarmed: isDisarmed, attack: attackSpec)
        }

        // Movement toward the best attack position.
        var movePath: [HexCoord] = []
        if totalMove > 0 {
            let path = findBestAttackPosition(
                from: currentPos,
                focusPos: focusPos,
                focus: focus,
                range: focusRange,
                moveRange: totalMove,
                isRanged: isRanged,
                attack: attackSpec,
                enemies: enemies,
                board: board,
                enemyPositions: blockingPositions,
                allyPositions: allyPositions,
                gameState: gameState,
                mode: mode
            ).path
            movePath = truncate(path ?? [], toBudget: totalMove, board: board, mode: mode)
        }

        let finalPos = movePath.last ?? currentPos

        // Targets of the first attack.
        var attackTargets: [PieceID] = []
        if let spec = attackSpec, !isDisarmed {
            attackTargets = targets(for: spec, from: finalPos, focus: focus, focusPos: focusPos,
                                    enemies: enemies, board: board, gameState: gameState)
        }

        return result(path: movePath, targets: attackTargets,
                      from: attackTargets.isEmpty ? nil : finalPos,
                      focus: focus, disarmed: isDisarmed, attack: attackSpec,
                      jumping: moveSpec?.jump ?? false)
    }

    /// Targets of an attack made from `position` with the given focus.
    static func targets(for spec: MonsterAttackSpec, from position: HexCoord, focus: PieceID, focusPos: HexCoord,
                        enemies: [PieceID], board: BoardState, gameState: GameState) -> [PieceID] {
        if let reach = spec.allEnemiesWithin {
            // "Target all enemies within N": every enemy in reach and line of sight.
            let hits = enemies.filter { enemy in
                guard let pos = board.piecePositions[enemy] else { return false }
                return canAttack(from: position, to: pos, range: reach, board: board)
            }
            guard !hits.isEmpty else { return [] }
            return hits.contains(focus) ? [focus] + hits.filter { $0 != focus } : hits
        }
        if let area = spec.area {
            // The pattern decides reach; invisible figures are never in `enemies`.
            let hits = AoEResolver.resolveTargets(pattern: area, attackerPos: position, focusTarget: focus,
                                                  enemies: enemies, board: board, range: spec.range)
            guard hits.contains(focus) else { return [] }
            return hits
        }
        guard canAttack(from: position, to: focusPos, range: spec.range, board: board) else { return [] }
        if spec.allAttacksOnFocus {
            return Array(repeating: focus, count: max(1, spec.targetCount))
        }
        var result = [focus]
        if spec.targetCount > 1 {
            result += findAdditionalTargets(from: position, primaryTarget: focus, enemies: enemies, board: board,
                                            range: spec.range, count: spec.targetCount - 1, gameState: gameState)
        }
        return result
    }

    /// Whether a figure at `from` can attack a figure at `to` within `range` (LOS required).
    static func canAttack(from: HexCoord, to: HexCoord, range: Int, board: BoardState) -> Bool {
        from.distance(to: to) <= range && LineOfSight.hasLOS(from: from, to: to, board: board)
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
        gameState: GameState,
        mode: MoveMode = .normal,
        attack: MonsterAttackSpec? = nil
    ) -> PieceID? {
        focusCandidates(from: position, enemies: enemies, board: board, range: range, isRanged: isRanged,
                        enemyPositions: enemyPositions, gameState: gameState, mode: mode, attack: attack).first?.pieceID
    }

    /// Every enemy the monster could attack this turn or later, best focus first.
    static func focusCandidates(
        from position: HexCoord,
        enemies: [PieceID],
        board: BoardState,
        range: Int,
        isRanged: Bool,
        enemyPositions: Set<HexCoord>,
        gameState: GameState,
        mode: MoveMode = .normal,
        attack: MonsterAttackSpec? = nil
    ) -> [FocusCandidate] {
        var candidates: [FocusCandidate] = []

        for enemy in enemies {
            guard let enemyPos = board.piecePositions[enemy] else { continue }

            var attackHexes = findAttackHexes(
                target: enemyPos, range: range, board: board,
                enemyPositions: enemyPositions, sourcePosition: position, mode: mode
            )
            // A melee area reaching further than 1 hex attacks the enemy only from hexes where a
            // turn of the pattern covers it, not from every hex within its reach.
            if let attack, let area = attack.area, AoEResolver.isMeleePattern(area) {
                attackHexes = attackHexes.filter {
                    !targets(for: attack, from: $0, focus: enemy, focusPos: enemyPos,
                             enemies: enemies, board: board, gameState: gameState).isEmpty
                }
            }
            if attackHexes.isEmpty { continue }

            // Traps and hazards count as obstacles unless every route needs one; then the
            // route through the fewest of them is used (p.30).
            guard let result = Pathfinder.cheapestTargetPath(
                board: board, from: position, targets: attackHexes, mode: mode,
                avoidTraps: true, canOpenDoors: false, occupiedByEnemy: enemyPositions
            ) else { continue }

            candidates.append(FocusCandidate(
                pieceID: enemy,
                negativeHexes: result.negativeHexes,
                pathCost: result.cost,
                proximity: position.distance(to: enemyPos),
                initiative: enemyInitiative(enemy, gameState: gameState)
            ))
        }

        return candidates.sorted(by: FocusCandidate.ordered)
    }

    /// Find all valid attack hexes to hit a target from.
    static func findAttackHexes(
        target: HexCoord,
        range: Int,
        board: BoardState,
        enemyPositions: Set<HexCoord>,
        sourcePosition: HexCoord,
        mode: MoveMode = .normal
    ) -> Set<HexCoord> {
        var hexes = Set<HexCoord>()
        // Where the monster may end its move: a flying monster may hover over obstacles.
        func standable(_ hex: HexCoord) -> Bool {
            guard mode == .fly else { return board.isPassable(hex) }
            guard let cell = board.cells[hex] else { return false }
            return cell.overlay != .wall && !board.isClosedDoor(hex)
        }

        if range <= 1 {
            for neighbor in target.neighbors {
                guard standable(neighbor) else { continue }
                // Can be the source position or unoccupied (can't stop on any occupied hex)
                guard neighbor == sourcePosition || !board.isOccupied(neighbor) else { continue }
                guard LineOfSight.hasLOS(from: neighbor, to: target, board: board) else { continue }
                hexes.insert(neighbor)
            }
        } else {
            for coord in board.cells.keys {
                guard coord.distance(to: target) <= range, standable(coord) else { continue }
                guard coord == sourcePosition || !board.isOccupied(coord) else { continue }
                guard LineOfSight.hasLOS(from: coord, to: target, board: board) else { continue }
                hexes.insert(coord)
            }
        }

        return hexes
    }

    /// Find the best attack position and the path to it.
    ///
    /// The monster moves the fewest hexes needed to attack its focus with maximum effect (p.30):
    /// a ranged monster first avoids disadvantage on its focus, then maximizes additional targets,
    /// then minimizes movement. If no attack position is reachable this turn it moves toward the
    /// closest one.
    static func findBestAttackPosition(
        from position: HexCoord,
        focusPos: HexCoord,
        focus: PieceID? = nil,
        range: Int,
        moveRange: Int,
        isRanged: Bool,
        attack: MonsterAttackSpec? = nil,
        enemies: [PieceID] = [],
        board: BoardState,
        enemyPositions: Set<HexCoord>,
        allyPositions: Set<HexCoord>,
        gameState: GameState? = nil,
        mode: MoveMode = .normal
    ) -> (attackHex: HexCoord?, path: [HexCoord]?) {
        var attackHexes = findAttackHexes(
            target: focusPos, range: range, board: board,
            enemyPositions: enemyPositions, sourcePosition: position, mode: mode
        )
        // A melee area attacks the focus only from where a turn of its pattern covers it.
        if let attack, let area = attack.area, AoEResolver.isMeleePattern(area), let focus, let gameState {
            attackHexes = attackHexes.filter {
                !targets(for: attack, from: $0, focus: focus, focusPos: focusPos,
                         enemies: enemies, board: board, gameState: gameState).isEmpty
            }
        }

        // Attack hexes reachable this turn (cost within the movement budget). Hexes holding
        // another figure are excluded by findAttackHexes, except the monster's own hex.
        let reachable = Pathfinder.reachableHexes(
            board: board, from: position, range: moveRange, mode: mode,
            avoidTraps: true, canOpenDoors: false,
            occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions
        )
        // Area attacks: any hex from which the pattern can cover the focus is an attack hex.
        if let attack, attack.area != nil, let focus, let gameState {
            for hex in Set(reachable.keys).union([position]) where !attackHexes.contains(hex) {
                guard hex == position || !board.isOccupied(hex) else { continue }
                if !targets(for: attack, from: hex, focus: focus, focusPos: focusPos,
                            enemies: enemies, board: board, gameState: gameState).isEmpty {
                    attackHexes.insert(hex)
                }
            }
        }
        if attackHexes.isEmpty { return (nil, nil) }
        let reachableAttackHexes = attackHexes.filter { reachable[$0] != nil || $0 == position }

        if !reachableAttackHexes.isEmpty {
            func score(_ hex: HexCoord) -> (disadvantage: Int, targets: Int, cost: Int) {
                let disadvantage = isRanged && hex.isAdjacent(to: focusPos) ? 1 : 0
                var targetCount = 1
                if let attack, let focus, let gameState, attack.targetCount > 1 || attack.area != nil {
                    targetCount = targets(for: attack, from: hex, focus: focus, focusPos: focusPos,
                                          enemies: enemies, board: board, gameState: gameState).count
                }
                return (disadvantage, targetCount, hex == position ? 0 : (reachable[hex] ?? 0))
            }
            let best = reachableAttackHexes.min { a, b in
                let sa = score(a), sb = score(b)
                if sa.disadvantage != sb.disadvantage { return sa.disadvantage < sb.disadvantage }
                if sa.targets != sb.targets { return sa.targets > sb.targets }
                if sa.cost != sb.cost { return sa.cost < sb.cost }
                return (a.col, a.row) < (b.col, b.row)
            }!
            if best == position { return (position, nil) }
            let path = Pathfinder.findPath(
                board: board, from: position, to: best, mode: mode,
                canOpenDoors: false, maxCost: moveRange,
                occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions
            )
            return (best, path)
        }

        // Can't attack this turn: move toward the cheapest attack hex.
        func remaining(from hex: HexCoord) -> Pathfinder.PathResult? {
            Pathfinder.cheapestTargetPath(
                board: board, from: hex, targets: attackHexes, mode: mode,
                avoidTraps: true, canOpenDoors: false,
                occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions)
        }
        guard let result = remaining(from: position) else { return (nil, nil) }
        // The route's hex where the movement runs out may hold an ally: the monster can't stop
        // there, but another hex it can reach may bring it just as close (p.30) rather than
        // backing up along the route.
        let stop = Pathfinder.truncatePath(result.path, budget: moveRange, board: board, mode: mode).last ?? position
        // Only when a figure pushed the stop back (the next hex was affordable but taken): the
        // search below is a full route search from every reachable hex.
        let next = (result.path.firstIndex(of: stop) ?? 0) + 1
        let pushedBack = next < result.path.count && board.isOccupied(result.path[next])
            && Pathfinder.movementCost(of: Array(result.path.prefix(next + 1)), board: board, mode: mode) <= moveRange
        let ideal = max(0, result.cost - moveRange)
        if pushedBack, let left = remaining(from: stop), left.cost > ideal {
            var best = (negatives: left.negativeHexes, cost: left.cost, move: reachable[stop] ?? 0, hex: stop)
            for (hex, move) in reachable where hex != stop && !board.isOccupied(hex) {
                guard let there = remaining(from: hex) else { continue }
                let candidate = (negatives: there.negativeHexes, cost: there.cost, move: move, hex: hex)
                if (candidate.negatives, candidate.cost, candidate.move, candidate.hex)
                    < (best.negatives, best.cost, best.move, best.hex) {
                    best = candidate
                }
            }
            if best.hex != stop, let path = Pathfinder.findPath(
                board: board, from: position, to: best.hex, mode: mode, canOpenDoors: false, maxCost: moveRange,
                occupiedByEnemy: enemyPositions, occupiedByAlly: allyPositions) {
                return (result.target, path)
            }
        }
        return (result.target, result.path)
    }

    /// Cut a path to the hexes the monster can afford this turn, never ending on an occupied hex.
    static func truncate(_ path: [HexCoord], toBudget budget: Int, board: BoardState,
                         mode: MoveMode = .normal) -> [HexCoord] {
        guard path.count > 1 else { return [] }
        let result = Pathfinder.truncatePath(path, budget: budget, board: board, mode: mode)
        return result.count > 1 ? result : []
    }

    // MARK: - Multi-Target

    /// Find additional attack targets beyond the primary focus: the closest other enemies in
    /// range and LOS, tie-broken by initiative (p.31).
    static func findAdditionalTargets(
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
            guard canAttack(from: position, to: enemyPos, range: range, board: board) else { continue }
            candidates.append(Candidate(
                pieceID: enemy,
                distance: position.distance(to: enemyPos),
                initiative: enemyInitiative(enemy, gameState: gameState)
            ))
        }

        candidates.sort { a, b in
            if a.distance != b.distance { return a.distance < b.distance }
            return a.initiative < b.initiative
        }

        return Array(candidates.prefix(count).map(\.pieceID))
    }

    // MARK: - Factions

    /// Whether a monster fights on the players' side (scenario allies).
    static func isAllyFaction(_ monster: GameMonster) -> Bool {
        monster.isAlly || monster.isAllied
    }

    /// Look up the monster group and entity for a monster piece.
    static func monsterEntity(_ id: PieceID, gameState: GameState) -> (GameMonster, GameMonsterEntity)? {
        guard case .monster(let name, let standee) = id,
              let group = gameState.monsters.first(where: { $0.name == name }),
              let entity = group.entities.first(where: { $0.number == standee && !$0.dead }) else { return nil }
        return (group, entity)
    }

    /// Gather the enemies a monster can focus on and target.
    /// Hostile monsters fight characters, their summons and allied monsters; allied monsters fight
    /// hostile monsters. Invisible figures are excluded unless `includeInvisible` is set (they
    /// cannot be focused on or targeted, but they still block movement).
    static func gatherEnemies(board: BoardState, monster: GameMonster, gameState: GameState, includeInvisible: Bool = false) -> [PieceID] {
        let allyFaction = isAllyFaction(monster)
        return board.piecePositions.keys.sorted().filter { id in
            switch id {
            case .character(let charID):
                guard !allyFaction,
                      let char = gameState.characters.first(where: { $0.id == charID }),
                      !char.exhausted else { return false }
                return includeInvisible || !isActive(.invisible, on: char)
            case .summon(let summonID):
                guard !allyFaction else { return false }
                for char in gameState.characters {
                    if let summon = char.summons.first(where: { $0.id == summonID }) {
                        guard !summon.dead else { return false }
                        return includeInvisible || !isActive(.invisible, on: summon)
                    }
                }
                return false
            case .monster:
                guard let (group, entity) = monsterEntity(id, gameState: gameState),
                      isAllyFaction(group) != allyFaction else { return false }
                return includeInvisible || !isActive(.invisible, on: entity)
            case .objective:
                return false
            }
        }
    }

    /// Hexes the monster cannot move through: every enemy figure (visible or not) and objectives.
    static func movementBlockers(board: BoardState, monster: GameMonster, gameState: GameState) -> Set<HexCoord> {
        var blocked = Set(gatherEnemies(board: board, monster: monster, gameState: gameState, includeInvisible: true)
            .compactMap { board.piecePositions[$0] })
        for (id, coord) in board.piecePositions {
            if case .objective = id { blocked.insert(coord) }
        }
        return blocked
    }

    /// Positions of the monster's allies (same-faction monsters), excluding itself.
    static func gatherAllyPositions(board: BoardState, monster: GameMonster, excluding: PieceID,
                                    gameState: GameState? = nil) -> Set<HexCoord> {
        var positions = Set<HexCoord>()
        for (id, coord) in board.piecePositions {
            guard id != excluding, case .monster = id else { continue }
            if let gameState, let (group, _) = monsterEntity(id, gameState: gameState),
               isAllyFaction(group) != isAllyFaction(monster) {
                continue
            }
            positions.insert(coord)
        }
        return positions
    }

    /// Effective initiative of an enemy for focus tie-breaks. Summons act (and are focused)
    /// directly before their summoner (p.30); a long-resting character has initiative 99.
    static func enemyInitiative(_ pieceID: PieceID, gameState: GameState) -> Double {
        switch pieceID {
        case .character(let charID):
            if let char = gameState.characters.first(where: { $0.id == charID }) {
                // Flea-Bitten Shawl: the wearer counts as initiative 99 for focus.
                return char.longRest || char.carriedItems.contains("gh-105") ? 99 : Double(char.initiative)
            }
            return 100
        case .summon(let summonID):
            for char in gameState.characters {
                if let index = char.summons.firstIndex(where: { $0.id == summonID }) {
                    let ownerInitiative = char.longRest ? 99.0 : Double(char.initiative)
                    // Summons act before their owner, in the order they were summoned.
                    return ownerInitiative - 0.5 + Double(index) * 0.01
                }
            }
            return 100
        case .monster:
            // Monsters act at their type's initiative, elites before normals, then by standee.
            guard let (group, entity) = monsterEntity(pieceID, gameState: gameState) else { return 100 }
            let base = Double(group.drawnInitiative ?? 99)
            let order = (entity.type == .normal ? 0.5 : 0) + Double(entity.number) * 0.01
            return base + order
        case .objective:
            return 99.5
        }
    }

    // MARK: - Helpers

    /// Values for letters in a monster's stat expressions: V = Vermling Scouts on the board
    /// (Merciless Overseer), X = hexes moved this turn (Dark Rider).
    static func attackVariables(for monster: GameMonster, gameState: GameState, hexesMoved: Int = 0) -> [String: Int] {
        let scouts = gameState.monsters.first { $0.name == "vermling-scout" }?.aliveEntities.count ?? 0
        return ["V": scouts, "X": hexesMoved]
    }

    static func isActive(_ condition: ConditionName, on entity: any Entity) -> Bool {
        entity.entityConditions.contains { $0.name == condition && !$0.expired }
    }
}
