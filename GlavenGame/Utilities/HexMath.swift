import Foundation

/// Hex coordinate math ported from VGB's Hexagon.elm and Scenario.elm.
/// Uses odd-row offset coordinate system with cube coordinate conversions for rotation.
enum HexMath {
    /// Pixel dimensions for hex cell positioning.
    static let cellStepX: CGFloat = 76
    static let cellStepY: CGFloat = 67
    static let cellSize: CGFloat = 90

    // MARK: - Coordinate Conversions

    /// Convert odd-row offset coordinates to cube coordinates.
    static func oddRowToCube(_ col: Int, _ row: Int) -> (x: Int, y: Int, z: Int) {
        let newX = col - (row - (row & 1)) / 2
        return (newX, -newX - row, row)
    }

    /// Convert cube coordinates to odd-row offset coordinates.
    static func cubeToOddRow(_ x: Int, _ y: Int, _ z: Int) -> (col: Int, row: Int) {
        (x + (z - (z & 1)) / 2, z)
    }

    // MARK: - Rotation

    /// Rotate a hex coordinate 60° clockwise around a rotation point (single step).
    static func singleRotate(origin: (Int, Int), around rotationPoint: (Int, Int)) -> (Int, Int) {
        let (ox, oy, oz) = oddRowToCube(origin.0, origin.1)
        let (rx, ry, rz) = oddRowToCube(rotationPoint.0, rotationPoint.1)

        let (newX, newY, newZ) = (-(oz - rz), -(ox - rx), -(oy - ry))
        return cubeToOddRow(newX + rx, newY + ry, newZ + rz)
    }

    /// Rotate a hex coordinate by `numTurns` × 60° around a rotation point.
    static func rotate(origin: (Int, Int), around rotationPoint: (Int, Int), turns numTurns: Int) -> (Int, Int) {
        if numTurns == 0 { return origin }
        let rotated = singleRotate(origin: origin, around: rotationPoint)
        if numTurns < 0 {
            return rotate(origin: rotated, around: rotationPoint, turns: numTurns + 1)
        } else {
            return rotate(origin: rotated, around: rotationPoint, turns: numTurns - 1)
        }
    }

    // MARK: - Map Tile Positioning

    /// Translate + rotate a tile coordinate into global space.
    /// Ported from VGB's `normaliseAndRotatePoint`.
    static func normaliseAndRotatePoint(
        turns: Int,
        refPoint: (Int, Int),
        origin: (Int, Int),
        tileCoord: (Int, Int)
    ) -> (Int, Int) {
        let (rpX, rpY, rpZ) = oddRowToCube(refPoint.0, refPoint.1)
        let (oX, oY, oZ) = oddRowToCube(origin.0, origin.1)
        let (tX, tY, tZ) = oddRowToCube(tileCoord.0, tileCoord.1)

        let initCoords = cubeToOddRow(tX - oX + rpX, tY - oY + rpY, tZ - oZ + rpZ)
        return rotate(origin: initCoords, around: refPoint, turns: turns)
    }

    // MARK: - Pixel Positioning

    /// Convert hex grid coordinate to pixel position.
    static func hexToPixel(col: Int, row: Int) -> CGPoint {
        let x = CGFloat(col) * cellStepX + (row & 1 == 1 ? cellStepX / 2 : 0)
        let y = CGFloat(row) * cellStepY
        return CGPoint(x: x, y: y)
    }
}
