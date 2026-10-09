import Foundation

/// A hex coordinate in odd-row offset format.
/// Row 0 is "even" row (no x-offset). Row 1 is "odd" row (half-cell x-offset).
struct HexCoord: Hashable, Codable, Sendable {
    let col: Int
    let row: Int

    init(_ col: Int, _ row: Int) {
        self.col = col
        self.row = row
    }

    // MARK: - Cube Coordinates

    /// Convert to cube coordinates for distance/rotation calculations.
    var cube: (x: Int, y: Int, z: Int) {
        HexMath.oddRowToCube(col, row)
    }

    /// Create from cube coordinates.
    static func fromCube(x: Int, y: Int, z: Int) -> HexCoord {
        let offset = HexMath.cubeToOddRow(x, y, z)
        return HexCoord(offset.col, offset.row)
    }

    /// The hexes on the straight line from this hex to `other`, both ends included (cube
    /// interpolation, nudged so a line along a hex edge picks one side consistently).
    func line(to other: HexCoord) -> [HexCoord] {
        let steps = distance(to: other)
        guard steps > 0 else { return [self] }
        let a = cube, b = other.cube
        return (0...steps).map { i in
            let t = Double(i) / Double(steps)
            let x = Double(a.x) + Double(b.x - a.x) * t + 1e-6
            let y = Double(a.y) + Double(b.y - a.y) * t + 2e-6
            let z = Double(a.z) + Double(b.z - a.z) * t - 3e-6
            var rx = x.rounded(), ry = y.rounded(), rz = z.rounded()
            let (dx, dy, dz) = (abs(rx - x), abs(ry - y), abs(rz - z))
            if dx > dy && dx > dz { rx = -ry - rz } else if dy > dz { ry = -rx - rz } else { rz = -rx - ry }
            return HexCoord.fromCube(x: Int(rx), y: Int(ry), z: Int(rz))
        }
    }

    // MARK: - Neighbors

    /// The 6 adjacent hexes in odd-row offset.
    var neighbors: [HexCoord] {
        let isOddRow = (row & 1) == 1
        if isOddRow {
            return [
                HexCoord(col + 1, row - 1), // NE
                HexCoord(col + 1, row),      // E
                HexCoord(col + 1, row + 1), // SE
                HexCoord(col,     row + 1), // SW
                HexCoord(col - 1, row),      // W
                HexCoord(col,     row - 1), // NW
            ]
        } else {
            return [
                HexCoord(col,     row - 1), // NE
                HexCoord(col + 1, row),      // E
                HexCoord(col,     row + 1), // SE
                HexCoord(col - 1, row + 1), // SW
                HexCoord(col - 1, row),      // W
                HexCoord(col - 1, row - 1), // NW
            ]
        }
    }

    /// Whether `other` is adjacent (distance == 1).
    func isAdjacent(to other: HexCoord) -> Bool {
        distance(to: other) == 1
    }

    // MARK: - Distance

    /// Hex distance (cube Manhattan / 2).
    func distance(to other: HexCoord) -> Int {
        let a = cube
        let b = other.cube
        return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2
    }

    // MARK: - Push / Pull Candidates

    /// Neighbors that are farther from `origin` than `self` (valid push destinations).
    func pushCandidates(awayFrom origin: HexCoord) -> [HexCoord] {
        let currentDist = distance(to: origin)
        return neighbors.filter { $0.distance(to: origin) > currentDist }
    }

    /// Neighbors that are closer to `origin` than `self` (valid pull destinations).
    func pullCandidates(toward origin: HexCoord) -> [HexCoord] {
        let currentDist = distance(to: origin)
        return neighbors.filter { $0.distance(to: origin) < currentDist }
    }

    // MARK: - Pixel Position

    /// Pixel position for rendering.
    var pixelPosition: CGPoint {
        HexMath.hexToPixel(col: col, row: row)
    }
}

extension HexCoord: CustomStringConvertible {
    var description: String { "(\(col),\(row))" }
}

/// Row-major order, used to break ties between equally good hexes deterministically.
extension HexCoord: Comparable {
    static func < (lhs: HexCoord, rhs: HexCoord) -> Bool {
        (lhs.row, lhs.col) < (rhs.row, rhs.col)
    }
}
