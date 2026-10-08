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
///   partial edge hexes, unrevealed rooms, outside the map) plus cells with a `.wall` overlay.
/// - Obstacles, traps, hazards, difficult terrain, doors and figures do **not** block LOS
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
/// A corner-to-corner line is blocked when it overlaps a wall hex (closed hexagon) along a
/// segment of positive length — i.e. it passes through the wall's interior or runs along
/// one of its edges. A line that merely touches a single corner point of a wall hex (e.g. it
/// passes through the corner shared by two open hexes and a wall hex) is not blocked.
/// Two adjacent hexes always have LOS: the map data has no explicit edge walls between
/// touching cells.
enum LineOfSight {

    /// Check if there is line of sight between two hexes.
    static func hasLOS(from source: HexCoord, to target: HexCoord, board: BoardState) -> Bool {
        if source == target { return true }
        if source.isAdjacent(to: target) { return true }

        let blockers = blockingHexes(between: source, and: target, board: board)
        if blockers.isEmpty { return true }

        let sourceCorners = corners(of: source)
        let targetCorners = corners(of: target)

        for sc in sourceCorners {
            for tc in targetCorners {
                let segment = Segment(sc, tc)
                if !blockers.contains(where: { segment.overlaps($0) }) {
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
        guard source.distance(to: target) <= range else { return false }
        return hasLOS(from: source, to: target, board: board)
    }

    /// Whether a hex acts as a wall for line of sight: it is not part of the revealed map
    /// (void / gap between tiles / partial edge hex) or it carries a `.wall` overlay.
    /// Obstacles and every other overlay are transparent.
    static func blocksLineOfSight(_ coord: HexCoord, board: BoardState) -> Bool {
        guard let cell = board.cells[coord] else { return true }
        return cell.overlay == .wall
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

        /// Whether this segment overlaps the closed hexagon along a positive length.
        /// Exact Liang–Barsky clipping against the hexagon's 6 half-planes using rational
        /// parameters (integer numerator / positive denominator).
        func overlaps(_ hex: Blocker) -> Bool {
            // Bounding-box rejection (closed, so edge-running lines are still tested).
            if maxX < hex.minX || minX > hex.maxX || maxY < hex.minY || minY > hex.maxY {
                return false
            }

            let dx = q.x - p.x
            let dy = q.y - p.y
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
            // Positive-length overlap iff low < high (a single shared point is not a block).
            return lowN * highD < highN * lowD
        }
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
