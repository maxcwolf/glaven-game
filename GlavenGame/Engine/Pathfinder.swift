import Foundation

/// How a figure moves across the board (Gloomhaven rulebook p.17-18).
enum MoveMode: String, Sendable, Codable, CaseIterable {
    /// Standard movement. Obstacles, walls and enemies block; allies may be passed
    /// through. Difficult terrain costs 2 to enter. Traps and hazardous terrain
    /// trigger on every hex entered.
    case normal
    /// Jump. Every hex except the last ignores figures and terrain: obstacles, enemies,
    /// allies, traps, hazards and difficult terrain may be passed over at 1 movement
    /// each. The last hex is entered normally: it must be passable and unoccupied,
    /// costs 2 if it is difficult terrain, and triggers a trap/hazard on it.
    case jump
    /// Flying. Figures and all terrain are ignored for the whole move, including the
    /// last hex: every hex costs 1, obstacles may be crossed (and ended on), and traps
    /// and hazards never trigger. The move must still end in an unoccupied hex.
    case fly

    /// Map the legacy `flying:` / `jumping:` flags to a mode (flying wins).
    init(flying: Bool, jumping: Bool) {
        self = flying ? .fly : (jumping ? .jump : .normal)
    }

    /// Resolve the effective mode from an explicit `mode` plus the legacy bool flags.
    /// The legacy flags win when set so existing call sites keep their meaning.
    static func resolve(_ mode: MoveMode, flying: Bool, jumping: Bool) -> MoveMode {
        if flying { return .fly }
        if jumping { return .jump }
        return mode
    }
}

/// Hex pathfinding on BoardState, implementing Gloomhaven movement rules.
///
/// ## Rules modelled
/// - **Normal move**: can't pass enemies, obstacles, walls or non-existent hexes; can
///   pass allies; can't END on any occupied hex. Difficult terrain costs 2.
/// - **Jump / Fly**: see `MoveMode`. Neither may cross a hex that doesn't exist (void)
///   or a `.wall` overlay.
/// - **Closed doors**: characters may enter a closed door hex (it opens the door).
///   Figures that can't open doors (`canOpenDoors: false` — monsters, summons, escorts)
///   treat a closed door as a wall in every mode.
/// - **Negative hexes** (traps + hazardous terrain): entering one costs a "negative
///   hex" (jump: only the landing hex counts; fly: never).
///
/// ## Path selection
/// Every search tracks the Pareto front of (movement cost, negative hexes entered), so
/// each query can pick the right lexicographic objective exactly:
/// - `maxCost` given: fewest negative hexes among paths within the budget, then
///   cheapest. (Characters prefer to avoid traps when an equally legal path exists.)
/// - `avoidTraps: true`, no budget — the monster AI rule: traps and hazards are
///   obstacles unless moving through them is the only way, in which case the path
///   through the fewest negative hexes is used (then cheapest).
/// - `avoidTraps: false`, no budget: cheapest path, fewest negative hexes as the
///   tie-break.
///
/// Note: `avoidTraps` covers traps AND hazardous terrain (the parameter keeps its
/// historical name for source compatibility).
enum Pathfinder {

    /// A chosen path plus its movement cost and the number of negative hexes
    /// (traps/hazards) it enters that would trigger for the given move mode.
    struct PathResult: Equatable {
        /// The destination hex (last element of `path`).
        let target: HexCoord
        /// The full path including both endpoints.
        let path: [HexCoord]
        /// Movement points spent along `path` for the move mode.
        let cost: Int
        /// Traps/hazards entered along `path` that would trigger (mode-aware).
        let negativeHexes: Int
    }

    // MARK: - Path to a single destination

    /// Find the best path from `from` to `to` (see type docs for the selection rule).
    /// Returns nil if no legal path exists (or none within `maxCost`).
    /// The returned array includes both endpoints.
    static func findPath(
        board: BoardState,
        from: HexCoord,
        to: HexCoord,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = true,
        canOpenDoors: Bool = true,
        maxCost: Int? = nil,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> [HexCoord]? {
        findPathDetailed(
            board: board, from: from, to: to,
            mode: MoveMode.resolve(mode, flying: flying, jumping: jumping),
            avoidTraps: avoidTraps, canOpenDoors: canOpenDoors, maxCost: maxCost,
            occupiedByEnemy: occupiedByEnemy, occupiedByAlly: occupiedByAlly
        )?.path
    }

    /// Like `findPath`, but also reports the path's movement cost and negative-hex count.
    static func findPathDetailed(
        board: BoardState,
        from: HexCoord,
        to: HexCoord,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = true,
        canOpenDoors: Bool = true,
        maxCost: Int? = nil,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> PathResult? {
        let context = MoveContext(
            board: board, start: from,
            mode: MoveMode.resolve(mode, flying: flying, jumping: jumping),
            canOpenDoors: canOpenDoors,
            enemies: occupiedByEnemy, allies: occupiedByAlly
        )
        let search = LabelSearch(context: context, maxCost: maxCost)
        let negativesFirst = avoidTraps || maxCost != nil
        guard let best = search.bestEnding(at: to, negativesFirst: negativesFirst) else { return nil }
        return search.result(for: best, at: to)
    }

    /// Movement cost of the best path from `from` to `to` (same selection as `findPath`).
    static func pathCost(
        board: BoardState,
        from: HexCoord,
        to: HexCoord,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = true,
        canOpenDoors: Bool = true,
        maxCost: Int? = nil,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> Int? {
        findPathDetailed(
            board: board, from: from, to: to, flying: flying, jumping: jumping, mode: mode,
            avoidTraps: avoidTraps, canOpenDoors: canOpenDoors, maxCost: maxCost,
            occupiedByEnemy: occupiedByEnemy, occupiedByAlly: occupiedByAlly
        )?.cost
    }

    // MARK: - Reachable hexes

    /// All hexes a figure can END its move on within `range` movement points.
    /// Returns coord → cheapest movement cost. The start hex is always included (cost 0).
    ///
    /// - `avoidTraps: false` (default — characters): traps and hazards may be entered
    ///   and passed through; the cost is the cheapest legal path.
    /// - `avoidTraps: true` (monster AI): only hexes reachable without entering any
    ///   trap/hazard are returned (strict; no fallback).
    static func reachableHexes(
        board: BoardState,
        from: HexCoord,
        range: Int,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = false,
        canOpenDoors: Bool = true,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> [HexCoord: Int] {
        let context = MoveContext(
            board: board, start: from,
            mode: MoveMode.resolve(mode, flying: flying, jumping: jumping),
            canOpenDoors: canOpenDoors,
            enemies: occupiedByEnemy, allies: occupiedByAlly
        )
        let search = LabelSearch(context: context, maxCost: max(0, range))

        var candidates: Set<HexCoord> = [from]
        for hex in search.settledHexes {
            candidates.insert(hex)
            candidates.formUnion(hex.neighbors)
        }

        var result: [HexCoord: Int] = [:]
        for hex in candidates {
            let costs = search.endings(at: hex)
                .filter { !avoidTraps || $0.negatives == 0 }
                .map(\.cost)
            if let cheapest = costs.min() { result[hex] = cheapest }
        }
        return result
    }

    // MARK: - Cheapest of several targets

    /// Find the best target to reach from a set of target hexes (e.g. a monster's
    /// candidate attack hexes). Returns the target hex and the movement cost, or nil
    /// if none is reachable. Selection matches `findPath`: with the default
    /// `avoidTraps: true` a trap/hazard-free route always wins, falling back to the
    /// route through the fewest negative hexes when every route needs one.
    static func cheapestTarget(
        board: BoardState,
        from: HexCoord,
        targets: Set<HexCoord>,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = true,
        canOpenDoors: Bool = true,
        maxCost: Int? = nil,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> (target: HexCoord, cost: Int)? {
        guard let best = cheapestTargetPath(
            board: board, from: from, targets: targets, flying: flying, jumping: jumping,
            mode: mode, avoidTraps: avoidTraps, canOpenDoors: canOpenDoors, maxCost: maxCost,
            occupiedByEnemy: occupiedByEnemy, occupiedByAlly: occupiedByAlly
        ) else { return nil }
        return (best.target, best.cost)
    }

    /// Like `cheapestTarget`, but returns the full path, its cost and its negative-hex
    /// count. Monster focus should compare candidates by `(negativeHexes, cost)`.
    /// Ties between equally good targets break by (row, col) for determinism.
    static func cheapestTargetPath(
        board: BoardState,
        from: HexCoord,
        targets: Set<HexCoord>,
        flying: Bool = false,
        jumping: Bool = false,
        mode: MoveMode = .normal,
        avoidTraps: Bool = true,
        canOpenDoors: Bool = true,
        maxCost: Int? = nil,
        occupiedByEnemy: Set<HexCoord> = [],
        occupiedByAlly: Set<HexCoord> = []
    ) -> PathResult? {
        if targets.contains(from) {
            return PathResult(target: from, path: [from], cost: 0, negativeHexes: 0)
        }
        let context = MoveContext(
            board: board, start: from,
            mode: MoveMode.resolve(mode, flying: flying, jumping: jumping),
            canOpenDoors: canOpenDoors,
            enemies: occupiedByEnemy, allies: occupiedByAlly
        )
        let search = LabelSearch(context: context, maxCost: maxCost)
        let negativesFirst = avoidTraps || maxCost != nil

        var best: (target: HexCoord, ending: Ending)?
        for target in targets {
            guard let ending = search.bestEnding(at: target, negativesFirst: negativesFirst) else { continue }
            if let current = best {
                let a = rank(ending, target, negativesFirst: negativesFirst)
                let b = rank(current.ending, current.target, negativesFirst: negativesFirst)
                if a < b { best = (target, ending) }
            } else {
                best = (target, ending)
            }
        }
        guard let chosen = best else { return nil }
        return search.result(for: chosen.ending, at: chosen.target)
    }

    // MARK: - Path helpers for callers

    /// Movement points needed to traverse `path` (start included) in the given mode.
    /// Normal: difficult terrain costs 2 per entered hex. Jump: intermediate hexes cost
    /// 1, the landing hex costs 2 if difficult. Fly: every hex costs 1.
    static func movementCost(of path: [HexCoord], board: BoardState, mode: MoveMode = .normal) -> Int {
        guard path.count > 1 else { return 0 }
        switch mode {
        case .fly:
            return path.count - 1
        case .jump:
            return (path.count - 2) + terrainCost(board.cells[path[path.count - 1]])
        case .normal:
            return path.dropFirst().reduce(0) { $0 + terrainCost(board.cells[$1]) }
        }
    }

    /// Truncate a (possibly multi-turn) path to what the figure can actually move this
    /// turn: the longest prefix whose movement cost (per `movementCost(of:)`) fits in
    /// `budget` and which ENDS on a legal hex — existing, not occupied by any figure on
    /// the board or in `occupied` (the mover at `path[0]` excepted), and passable unless
    /// flying. Returns `[path[0]]` when no step is possible.
    static func truncatePath(
        _ path: [HexCoord],
        budget: Int,
        board: BoardState,
        mode: MoveMode = .normal,
        occupied: Set<HexCoord> = []
    ) -> [HexCoord] {
        guard let start = path.first else { return [] }
        var blocked = Set(board.piecePositions.values)
        blocked.formUnion(occupied)
        blocked.remove(start)

        var bestEnd = 0
        var normalCost = 0
        for k in 1..<max(1, path.count) {
            let hex = path[k]
            let cell = board.cells[hex]
            let cost: Int
            switch mode {
            case .fly: cost = k
            case .jump: cost = (k - 1) + terrainCost(cell)
            case .normal:
                normalCost += terrainCost(cell)
                cost = normalCost
            }
            guard cost <= budget else {
                if mode == .normal { break } else { continue }
            }
            guard let cell, !blocked.contains(hex) else { continue }
            if mode != .fly && !cell.passable { continue }
            bestEnd = k
        }
        return Array(path[0...bestEnd])
    }

    /// The traps/hazardous-terrain hexes along `path` whose effects trigger, in order.
    /// Normal: every entered negative hex. Jump: only the landing hex. Fly: none.
    /// The start hex is never included (it was not entered by this move).
    static func negativeHexesEntered(
        along path: [HexCoord],
        board: BoardState,
        mode: MoveMode = .normal
    ) -> [HexCoord] {
        guard path.count > 1 else { return [] }
        switch mode {
        case .fly:
            return []
        case .jump:
            let last = path[path.count - 1]
            return isNegative(board.cells[last]) ? [last] : []
        case .normal:
            return path.dropFirst().filter { isNegative(board.cells[$0]) }
        }
    }

    // MARK: - Private: rules

    private static func terrainCost(_ cell: HexCell?) -> Int {
        (cell?.isDifficultTerrain ?? false) ? 2 : 1
    }

    private static func isNegative(_ cell: HexCell?) -> Bool {
        guard let cell else { return false }
        return cell.isTrap || cell.isHazard
    }

    /// Cost and negative-hex count of entering one hex.
    private struct Step {
        let cost: Int
        let negatives: Int
    }

    /// Movement rules for a single search, snapshotting the board once.
    private struct MoveContext {
        let cells: [HexCoord: HexCell]
        let start: HexCoord
        let mode: MoveMode
        /// Hexes that block passage in a normal move.
        let enemies: Set<HexCoord>
        /// Hexes a move can't END on (every figure except the mover).
        let occupied: Set<HexCoord>
        /// Closed doors, for figures that can't open them (treated as walls).
        let closedDoors: Set<HexCoord>

        init(board: BoardState, start: HexCoord, mode: MoveMode, canOpenDoors: Bool,
             enemies: Set<HexCoord>, allies: Set<HexCoord>) {
            self.cells = board.cells
            self.start = start
            self.mode = mode
            self.enemies = enemies
            var occupied = Set(board.piecePositions.values)
            occupied.formUnion(enemies)
            occupied.formUnion(allies)
            occupied.remove(start)
            self.occupied = occupied
            self.closedDoors = canOpenDoors
                ? []
                : Set(board.doors.lazy.filter { !$0.isOpen }.map(\.coord))
        }

        /// The cell at `hex` if it can be moved through at all in any mode:
        /// it exists, isn't a wall, and isn't a closed door the figure can't open.
        func space(_ hex: HexCoord) -> HexCell? {
            guard let cell = cells[hex], cell.overlay != .wall,
                  !closedDoors.contains(hex) else { return nil }
            return cell
        }

        /// Entering `hex` and continuing the move from it.
        func passStep(_ hex: HexCoord) -> Step? {
            guard let cell = space(hex) else { return nil }
            switch mode {
            case .fly, .jump:
                return Step(cost: 1, negatives: 0)
            case .normal:
                guard cell.passable, !enemies.contains(hex) else { return nil }
                return Step(cost: terrainCost(cell), negatives: isNegative(cell) ? 1 : 0)
            }
        }

        /// Entering `hex` as the final hex of the move.
        func endStep(_ hex: HexCoord) -> Step? {
            guard let cell = space(hex), !occupied.contains(hex) else { return nil }
            switch mode {
            case .fly:
                return Step(cost: 1, negatives: 0)
            case .jump, .normal:
                guard cell.passable else { return nil }
                return Step(cost: terrainCost(cell), negatives: isNegative(cell) ? 1 : 0)
            }
        }
    }

    // MARK: - Private: bi-criteria label-setting search

    /// A search state: standing on `hex` mid-move after spending `cost` movement and
    /// entering `negatives` traps/hazards. `parent` indexes the previous label (-1 = root).
    private struct Label {
        let hex: HexCoord
        let cost: Int
        let negatives: Int
        let parent: Int
    }

    /// A way to end the move on a hex: arriving from pass-through label `parent`
    /// (-1 means "stay on the start hex").
    private struct Ending {
        let cost: Int
        let negatives: Int
        let parent: Int
    }

    private static func rank(_ e: Ending, _ hex: HexCoord, negativesFirst: Bool) -> (Int, Int, Int, Int) {
        negativesFirst
            ? (e.negatives, e.cost, hex.row, hex.col)
            : (e.cost, e.negatives, hex.row, hex.col)
    }

    /// Computes, for every hex, the Pareto-optimal (cost, negatives) labels of standing
    /// on it mid-move. Labels are settled in lexicographic (cost, negatives) order using a
    /// bucket queue (every step costs >= 1), so a label is Pareto-optimal exactly when its
    /// negative count is below every label already settled on that hex.
    private struct LabelSearch {
        let context: MoveContext
        let maxCost: Int?
        private(set) var labels: [Label] = []
        /// Settled label indices per hex, in increasing cost / decreasing negatives.
        private(set) var settled: [HexCoord: [Int]] = [:]

        var settledHexes: Dictionary<HexCoord, [Int]>.Keys { settled.keys }

        init(context: MoveContext, maxCost: Int?) {
            self.context = context
            self.maxCost = maxCost
            run()
        }

        private mutating func run() {
            labels = [Label(hex: context.start, cost: 0, negatives: 0, parent: -1)]
            var fewestNegatives: [HexCoord: Int] = [:]
            var buckets: [[Int]] = [[0]]
            var cost = 0
            while cost < buckets.count {
                let bucket = buckets[cost].sorted { labels[$0].negatives < labels[$1].negatives }
                buckets[cost] = []
                for index in bucket {
                    let label = labels[index]
                    if let best = fewestNegatives[label.hex], label.negatives >= best { continue }
                    fewestNegatives[label.hex] = label.negatives
                    settled[label.hex, default: []].append(index)

                    for neighbor in label.hex.neighbors {
                        guard let step = context.passStep(neighbor) else { continue }
                        let newCost = label.cost + step.cost
                        if let maxCost, newCost > maxCost { continue }
                        let newNegatives = label.negatives + step.negatives
                        if let best = fewestNegatives[neighbor], newNegatives >= best { continue }
                        labels.append(Label(hex: neighbor, cost: newCost,
                                            negatives: newNegatives, parent: index))
                        while buckets.count <= newCost { buckets.append([]) }
                        buckets[newCost].append(labels.count - 1)
                    }
                }
                cost += 1
            }
        }

        /// Every way (within budget) to END the move on `hex`.
        func endings(at hex: HexCoord) -> [Ending] {
            if hex == context.start { return [Ending(cost: 0, negatives: 0, parent: -1)] }
            guard let step = context.endStep(hex) else { return [] }
            var result: [Ending] = []
            for neighbor in hex.neighbors {
                guard let indices = settled[neighbor] else { continue }
                for index in indices {
                    let label = labels[index]
                    let cost = label.cost + step.cost
                    if let maxCost, cost > maxCost { continue }
                    result.append(Ending(cost: cost, negatives: label.negatives + step.negatives,
                                         parent: index))
                }
            }
            return result
        }

        func bestEnding(at hex: HexCoord, negativesFirst: Bool) -> Ending? {
            endings(at: hex).min { a, b in
                negativesFirst
                    ? (a.negatives, a.cost) < (b.negatives, b.cost)
                    : (a.cost, a.negatives) < (b.cost, b.negatives)
            }
        }

        func result(for ending: Ending, at hex: HexCoord) -> PathResult {
            var path: [HexCoord] = [hex]
            var index = ending.parent
            while index >= 0 {
                path.append(labels[index].hex)
                index = labels[index].parent
            }
            path.reverse()
            return PathResult(target: hex, path: path, cost: ending.cost,
                              negativeHexes: ending.negatives)
        }
    }
}
