import Foundation

/// BFS-based hex pathfinding on BoardState.
enum Pathfinder {

    /// Find the shortest path from `from` to `to`.
    /// Returns nil if no path exists. The returned array includes both endpoints.
    static func findPath(
        board: BoardState,
        from: HexCoord,
        to: HexCoord,
        flying: Bool = false,
        jumping: Bool = false,
        avoidTraps: Bool = true,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> [HexCoord]? {
        if from == to { return [from] }

        var visited: [HexCoord: HexCoord] = [from: from] // child → parent
        var queue: [(coord: HexCoord, cost: Int)] = [(from, 0)]
        var head = 0

        while head < queue.count {
            let (current, _) = queue[head]
            head += 1

            if current == to {
                return reconstructPath(from: from, to: to, parents: visited)
            }

            for neighbor in current.neighbors {
                guard visited[neighbor] == nil else { continue }
                guard canTraverse(neighbor, board: board, flying: flying, jumping: jumping,
                                  avoidTraps: avoidTraps, occupiedByEnemy: occupiedByEnemy,
                                  destination: to) else { continue }

                visited[neighbor] = current
                queue.append((neighbor, 0))
            }
        }

        // If avoiding traps failed, try again allowing traps
        if avoidTraps {
            return findPath(board: board, from: from, to: to, flying: flying, jumping: jumping,
                          avoidTraps: false, occupiedByEnemy: occupiedByEnemy, occupiedByAlly: occupiedByAlly)
        }

        return nil
    }

    /// Find all hexes reachable within a given movement range.
    /// Returns a dictionary of coord → movement cost.
    static func reachableHexes(
        board: BoardState,
        from: HexCoord,
        range: Int,
        flying: Bool = false,
        jumping: Bool = false,
        avoidTraps: Bool = true,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> [HexCoord: Int] {
        var costs: [HexCoord: Int] = [from: 0]
        var queue: [(coord: HexCoord, cost: Int)] = [(from, 0)]
        var head = 0

        while head < queue.count {
            let (current, currentCost) = queue[head]
            head += 1

            for neighbor in current.neighbors {
                let moveCost = movementCost(neighbor, board: board, flying: flying)
                let newCost = currentCost + moveCost

                guard newCost <= range else { continue }
                guard let existingCost = costs[neighbor], newCost < existingCost else {
                    if costs[neighbor] != nil { continue }
                    // First time visiting
                    guard canTraverse(neighbor, board: board, flying: flying, jumping: jumping,
                                      avoidTraps: avoidTraps, occupiedByEnemy: occupiedByEnemy,
                                      destination: nil) else { continue }
                    // Can't stop on enemy-occupied hex
                    if occupiedByEnemy.contains(neighbor) { continue }
                    costs[neighbor] = newCost
                    queue.append((neighbor, newCost))
                    continue
                }
                // Found a cheaper path
                costs[neighbor] = newCost
                queue.append((neighbor, newCost))
            }
        }

        // Remove hexes that are occupied (can't stop on them, only pass through allies)
        var result = costs
        for coord in occupiedByAlly {
            if coord != from { result.removeValue(forKey: coord) }
        }
        for coord in occupiedByEnemy {
            result.removeValue(forKey: coord)
        }

        return result
    }

    /// Find the cheapest target to reach from a set of target hexes.
    /// Returns the target hex and cost, or nil if none reachable.
    static func cheapestTarget(
        board: BoardState,
        from: HexCoord,
        targets: Set<HexCoord>,
        flying: Bool = false,
        jumping: Bool = false,
        occupiedByEnemy: Set<HexCoord> = []
    ) -> (target: HexCoord, cost: Int)? {
        if targets.contains(from) { return (from, 0) }

        var costs: [HexCoord: Int] = [from: 0]
        var queue: [(coord: HexCoord, cost: Int)] = [(from, 0)]
        var head = 0
        var bestTarget: HexCoord?
        var bestCost = Int.max

        while head < queue.count {
            let (current, currentCost) = queue[head]
            head += 1

            if currentCost >= bestCost { continue }

            for neighbor in current.neighbors {
                let moveCost = movementCost(neighbor, board: board, flying: flying)
                let newCost = currentCost + moveCost

                guard newCost < bestCost else { continue }
                if let existing = costs[neighbor], existing <= newCost { continue }

                guard canTraverse(neighbor, board: board, flying: flying, jumping: jumping,
                                  avoidTraps: true, occupiedByEnemy: occupiedByEnemy,
                                  destination: nil) else { continue }

                costs[neighbor] = newCost
                queue.append((neighbor, newCost))

                if targets.contains(neighbor) && newCost < bestCost {
                    bestTarget = neighbor
                    bestCost = newCost
                }
            }
        }

        if let target = bestTarget {
            return (target, bestCost)
        }
        return nil
    }

    /// Find the shortest path cost from `from` to `to` (Dijkstra).
    /// Cheaper than findPath when you only need the cost.
    static func pathCost(
        board: BoardState,
        from: HexCoord,
        to: HexCoord,
        flying: Bool = false,
        jumping: Bool = false,
        occupiedByEnemy: Set<HexCoord> = []
    ) -> Int? {
        if from == to { return 0 }

        var costs: [HexCoord: Int] = [from: 0]
        var queue: [(coord: HexCoord, cost: Int)] = [(from, 0)]
        var head = 0

        while head < queue.count {
            let (current, currentCost) = queue[head]
            head += 1

            if current == to { return currentCost }

            if let known = costs[current], currentCost > known { continue }

            for neighbor in current.neighbors {
                let moveCost = movementCost(neighbor, board: board, flying: flying)
                let newCost = currentCost + moveCost

                if let existing = costs[neighbor], existing <= newCost { continue }

                guard canTraverse(neighbor, board: board, flying: flying, jumping: jumping,
                                  avoidTraps: true, occupiedByEnemy: occupiedByEnemy,
                                  destination: to) else { continue }

                costs[neighbor] = newCost
                queue.append((neighbor, newCost))
            }
        }

        return nil
    }

    // MARK: - Private

    /// Whether a figure can traverse through a hex.
    private static func canTraverse(
        _ coord: HexCoord,
        board: BoardState,
        flying: Bool,
        jumping: Bool,
        avoidTraps: Bool,
        occupiedByEnemy: Set<HexCoord>,
        destination: HexCoord?
    ) -> Bool {
        guard let cell = board.cells[coord] else { return false }

        // Flying ignores most obstacles
        if flying { return true }

        // Must be passable (obstacles/walls block)
        guard cell.passable else { return false }

        // Enemies block movement (can't pass through)
        if occupiedByEnemy.contains(coord) && coord != destination {
            return false
        }

        // Jumping ignores traps and difficult terrain (only for intermediate hexes)
        if jumping && coord != destination { return true }

        // Traps: treat as obstacles if avoiding
        if avoidTraps && cell.isTrap { return false }

        return true
    }

    /// Movement cost to enter a hex.
    private static func movementCost(_ coord: HexCoord, board: BoardState, flying: Bool) -> Int {
        if flying { return 1 }
        guard let cell = board.cells[coord] else { return 1 }
        return cell.isDifficultTerrain ? 2 : 1
    }

    /// Reconstruct path from BFS parent map.
    private static func reconstructPath(
        from: HexCoord,
        to: HexCoord,
        parents: [HexCoord: HexCoord]
    ) -> [HexCoord] {
        var path: [HexCoord] = [to]
        var current = to
        while current != from {
            guard let parent = parents[current] else { break }
            path.append(parent)
            current = parent
        }
        return path.reversed()
    }
}
