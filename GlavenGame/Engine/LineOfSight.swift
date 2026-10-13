import Foundation

/// Line of sight on the hex board, following the Gloomhaven rulebook:
///
/// > You have line of sight if you can draw a line from any corner of the attacker's hex
/// > to any corner of the defender's hex without touching any part of a wall (the line
/// > edge of a map tile or the entire area of any partial hex along the edge of a map tile).
/// > Only walls block line of sight.
///
/// Board model:
/// - **Walls** = hexes that are not on a revealed map tile (void: gaps between tiles,
///   partial edge hexes, unrevealed rooms, outside the map), cells with a `.wall` overlay and
///   closed doors (FAQ: "Walls and closed doors are the only things that block line of sight").
/// - **Wall lines** = the sides between full hexes of two tiles that touch with no door or
///   corridor over them (`BoardState.wallEdges`): the tile's edge is still there as a
///   one-dimensional wall.
/// - Obstacles, traps, hazards, difficult terrain, open doors and figures do **not** block LOS
///   ("Obstacles do not hinder ranged attacks").
///
/// Geometry: the board is pointy-top hexes in odd-row offset coordinates (see `HexMath` /
/// `BoardScene.hexPath`). LOS is evaluated on an exact integer lattice — an affine image of a
/// regular pointy-top grid — so shared corners and edges between hexes coincide exactly and
/// there is no floating-point tolerance to tune:
///
/// - Hex `(col, row)` has its center at `X = 2·col + (row & 1)`, `Y = 3·row`.
/// - Its 6 corners are the center plus `(1,1) (0,2) (-1,1) (-1,-1) (0,-2) (1,-1)`.
///
/// A corner-to-corner line is blocked when it touches a wall anywhere — passing through it,
/// running along its edge or only grazing a corner (FAQ: "if the sight line touches any corner
/// or edge of a wall, or any corner or edge of a hex that is considered a wall"). The two ends
/// of the line are the exception for wall hexes: the corners of a hex beside a wall lie on it,
/// and a figure there still sees along and away from the wall. A wall line has no such
/// exception: a sight line that ends on it would be seeing across it.
/// Two adjacent hexes always have LOS, unless a wall line runs between them.
enum LineOfSight {

    /// Check if there is line of sight between two hexes.
    static func hasLOS(from source: HexCoord, to target: HexCoord, board: BoardState) -> Bool {
        if source == target { return true }
        if board.areAdjacent(source, target) { return true }

        let blockers = blockingHexes(between: source, and: target, board: board)
        let lines = blockingLines(between: source, and: target, board: board)
        if blockers.isEmpty && lines.isEmpty { return true }

        let sourceCorners = corners(of: source)
        let targetCorners = corners(of: target)

        for sc in sourceCorners {
            for tc in targetCorners {
                let segment = Segment(sc, tc)
                if !blockers.contains(where: { segment.touches($0) }) && !lines.contains(where: { segment.touches($0) }) {
                    return true
                }
            }
        }
        return false
    }

    /// Check if a target at a given range has LOS from source.
    static func hasLOS(
        from source: HexCoord,
        to target: HexCoord,
        range: Int,
        board: BoardState
    ) -> Bool {
        guard board.isWithin(range, from: source, to: target) else { return false }
        return hasLOS(from: source, to: target, board: board)
    }

    /// Whether a hex acts as a wall for line of sight: it is not part of the revealed map
    /// (void / gap between tiles / partial edge hex), it carries a `.wall` overlay, or it is a
    /// closed door. Obstacles and every other overlay are transparent, but for an obstacle the
    /// scenario makes `solid`.
    static func blocksLineOfSight(_ coord: HexCoord, board: BoardState) -> Bool {
        guard let cell = board.cells[coord] else { return true }
        return cell.overlay == .wall || cell.solid == true || board.isClosedDoor(coord)
    }

    // MARK: - Lattice Geometry

    /// A point on the integer LOS lattice.
    private struct LatticePoint {
        let x: Int
        let y: Int
    }

    /// Corner offsets from a hex center, in counter-clockwise order on the lattice.
    private static let cornerOffsets: [(Int, Int)] = [
        (1, 1), (0, 2), (-1, 1), (-1, -1), (0, -2), (1, -1),
    ]

    /// Center of a hex on the integer lattice (pointy-top, odd-row offset).
    private static func center(of coord: HexCoord) -> LatticePoint {
        LatticePoint(x: 2 * coord.col + (coord.row & 1), y: 3 * coord.row)
    }

    /// The 6 corners of a pointy-top hex on the integer lattice.
    private static func corners(of coord: HexCoord) -> [LatticePoint] {
        let c = center(of: coord)
        return cornerOffsets.map { LatticePoint(x: c.x + $0.0, y: c.y + $0.1) }
    }

    /// A wall hex, pre-computed for segment overlap tests.
    private struct Blocker {
        let corners: [LatticePoint]
        let minX: Int, maxX: Int, minY: Int, maxY: Int

        init(_ coord: HexCoord) {
            let c = LineOfSight.center(of: coord)
            corners = LineOfSight.corners(of: coord)
            minX = c.x - 1; maxX = c.x + 1
            minY = c.y - 2; maxY = c.y + 2
        }
    }

    /// A corner-to-corner sight line.
    private struct Segment {
        let p: LatticePoint
        let q: LatticePoint
        let minX: Int, maxX: Int, minY: Int, maxY: Int

        init(_ p: LatticePoint, _ q: LatticePoint) {
            self.p = p
            self.q = q
            minX = min(p.x, q.x); maxX = max(p.x, q.x)
            minY = min(p.y, q.y); maxY = max(p.y, q.y)
        }

        /// Whether this segment touches the closed hexagon anywhere but at its own two ends.
        /// Exact Liang–Barsky clipping against the hexagon's 6 half-planes using rational
        /// parameters (integer numerator / positive denominator).
        func touches(_ hex: Blocker) -> Bool {
            // Bounding-box rejection (closed, so edge-running lines are still tested).
            if maxX < hex.minX || minX > hex.maxX || maxY < hex.minY || minY > hex.maxY {
                return false
            }

            let dx = q.x - p.x
            let dy = q.y - p.y
            // A line of no length (a corner the two hexes share) is all end.
            if dx == 0 && dy == 0 { return false }
            // Feasible parameter interval [lowN/lowD, highN/highD] ⊆ [0, 1].
            var lowN = 0, lowD = 1
            var highN = 1, highD = 1

            for i in 0..<6 {
                let v = hex.corners[i]
                let w = hex.corners[(i + 1) % 6]
                let ex = w.x - v.x
                let ey = w.y - v.y
                // Inside (CCW polygon): cross(e, point - v) >= 0.
                // f(t) = cross(e, p - v) + t · cross(e, d) = a + t·b
                let a = ex * (p.y - v.y) - ey * (p.x - v.x)
                let b = ex * dy - ey * dx
                if b == 0 {
                    if a < 0 { return false } // parallel and entirely outside this edge
                } else if b > 0 {
                    // t >= -a / b
                    let n = -a, d = b
                    if n * lowD > lowN * d { lowN = n; lowD = d }
                } else {
                    // t <= a / (-b)
                    let n = a, d = -b
                    if n * highD < highN * d { highN = n; highD = d }
                }
            }
            // The line is in the hexagon for t in [low, high]: a touch when that is not empty
            // and reaches inside (0, 1) — low ≤ high, low < 1 and high > 0.
            return lowN * highD <= highN * lowD && lowN < lowD && highN > 0
        }

        /// Whether this segment touches a wall line anywhere, its own ends included.
        func touches(_ line: WallLine) -> Bool {
            if maxX < line.minX || minX > line.maxX || maxY < line.minY || minY > line.maxY {
                return false
            }
            func side(_ a: LatticePoint, _ b: LatticePoint, _ c: LatticePoint) -> Int {
                ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).signum()
            }
            let d1 = side(p, q, line.a), d2 = side(p, q, line.b)
            let d3 = side(line.a, line.b, p), d4 = side(line.a, line.b, q)
            // Properly crossing, or one end of either lying on the other: the bounding boxes
            // overlap (checked above), so collinear ends do touch.
            if d1 != d2 && d3 != d4 { return true }
            if d1 == 0 && within(line.a) { return true }
            if d2 == 0 && within(line.b) { return true }
            if d3 == 0 && line.contains(p) { return true }
            if d4 == 0 && line.contains(q) { return true }
            return false
        }

        /// Whether a point known to be on this segment's line lies between its ends.
        private func within(_ point: LatticePoint) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    /// A wall line: the side two hexes share.
    private struct WallLine {
        let a: LatticePoint
        let b: LatticePoint
        let minX: Int, maxX: Int, minY: Int, maxY: Int

        init?(_ edge: HexEdge) {
            let mine = LineOfSight.corners(of: edge.a), theirs = LineOfSight.corners(of: edge.b)
            let shared = mine.filter { corner in theirs.contains { $0.x == corner.x && $0.y == corner.y } }
            guard shared.count == 2 else { return nil }
            a = shared[0]; b = shared[1]
            minX = min(a.x, b.x); maxX = max(a.x, b.x)
            minY = min(a.y, b.y); maxY = max(a.y, b.y)
        }

        /// Whether a point known to be on this line's line lies between its ends.
        func contains(_ point: LatticePoint) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    /// Wall lines near enough to the two hexes to meet a sight line between them.
    private static func blockingLines(between source: HexCoord, and target: HexCoord, board: BoardState) -> [WallLine] {
        guard !board.wallEdges.isEmpty else { return [] }
        let cols = (min(source.col, target.col) - 2)...(max(source.col, target.col) + 2)
        let rows = (min(source.row, target.row) - 2)...(max(source.row, target.row) + 2)
        return board.wallEdges.filter {
            cols.contains($0.a.col) && rows.contains($0.a.row) && cols.contains($0.b.col) && rows.contains($0.b.row)
        }.compactMap(WallLine.init)
    }

    /// Wall hexes that could intersect any corner-to-corner line between the two hexes.
    private static func blockingHexes(
        between source: HexCoord,
        and target: HexCoord,
        board: BoardState
    ) -> [Blocker] {
        // Every corner-to-corner line lies within the convex hull of the two hexes, which only
        // reaches one row/column beyond their bounding box; use a margin of 2 to be safe.
        let minCol = min(source.col, target.col) - 2
        let maxCol = max(source.col, target.col) + 2
        let minRow = min(source.row, target.row) - 2
        let maxRow = max(source.row, target.row) + 2

        // Each sight line stays within one hex radius of the center-to-center segment, so a
        // wall hex can only matter if its center is within two radii of that segment.
        let sc = euclidean(center(of: source))
        let tc = euclidean(center(of: target))
        let reach = 2.0 + 1e-6

        var blockers: [Blocker] = []
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                let coord = HexCoord(col, row)
                guard coord != source && coord != target else { continue }
                guard blocksLineOfSight(coord, board: board) else { continue }
                let bc = euclidean(center(of: coord))
                guard distance(from: bc, toSegment: sc, tc) <= reach else { continue }
                blockers.append(Blocker(coord))
            }
        }
        return blockers
    }

    /// Map a lattice point back to regular-hex Euclidean space (hex circumradius = 1).
    private static func euclidean(_ p: LatticePoint) -> (x: Double, y: Double) {
        (Double(p.x) * 3.0.squareRoot() / 2.0, Double(p.y) / 2.0)
    }

    /// Shortest Euclidean distance from a point to a segment.
    private static func distance(
        from p: (x: Double, y: Double),
        toSegment a: (x: Double, y: Double),
        _ b: (x: Double, y: Double)
    ) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
