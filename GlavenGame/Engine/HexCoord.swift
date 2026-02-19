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
