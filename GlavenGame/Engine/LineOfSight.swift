import Foundation

/// Line of sight checks using corner-to-corner ray casting on a hex grid.
/// Per Gloomhaven rules: LOS exists if ANY corner-to-corner line from source
/// to target hex is unblocked. Only walls/obstacles block LOS (figures do NOT).
enum LineOfSight {

    /// Check if there is line of sight between two hexes.
    static func hasLOS(from source: HexCoord, to target: HexCoord, board: BoardState) -> Bool {
        if source == target { return true }
        if source.isAdjacent(to: target) {
            // Adjacent hexes always have LOS unless there's a wall between them
            // (walls are marked as impassable cells, not as cells with wall overlays
            //  blocking adjacency — so adjacent always has LOS in standard GH)
            return true
        }

        let sourceCorners = hexCorners(source)
        let targetCorners = hexCorners(target)

        // Collect blocking cells: obstacles/walls that are impassable
        // Only check cells in the bounding region between source and target
        let blockingCells = gatherBlockingCells(from: source, to: target, board: board)

        // Check if any corner-to-corner line is clear
        for sc in sourceCorners {
            for tc in targetCorners {
                if isLineUnblocked(from: sc, to: tc, blockingCells: blockingCells) {
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

    // MARK: - Hex Geometry

    /// The 6 corners of a flat-top hex at a given coordinate.
    /// Uses the same coordinate system as HexMath.hexToPixel.
    private static func hexCorners(_ coord: HexCoord) -> [CGPoint] {
        let center = coord.pixelPosition
        let size = HexMath.cellSize / 2.0 // radius from center to corner
        return (0..<6).map { i in
            let angle = CGFloat(i) * .pi / 3.0  // flat-top: 0°, 60°, 120°, ...
            return CGPoint(
                x: center.x + size * cos(angle),
                y: center.y + size * sin(angle)
            )
        }
    }

    /// Gather all blocking cells (impassable) in the region between source and target.
    private static func gatherBlockingCells(
        from source: HexCoord,
        to target: HexCoord,
        board: BoardState
    ) -> [(center: CGPoint, radius: CGFloat)] {
        let halfSize = HexMath.cellSize / 2.0
        // Use a generous bounding box
        let minCol = min(source.col, target.col) - 1
        let maxCol = max(source.col, target.col) + 1
        let minRow = min(source.row, target.row) - 1
        let maxRow = max(source.row, target.row) + 1

        var blocking: [(center: CGPoint, radius: CGFloat)] = []
        for (coord, cell) in board.cells {
            guard coord != source && coord != target else { continue }
            guard !cell.passable else { continue }
            guard coord.col >= minCol && coord.col <= maxCol &&
                  coord.row >= minRow && coord.row <= maxRow else { continue }
            blocking.append((center: coord.pixelPosition, radius: halfSize))
        }
        return blocking
    }

    /// Check if a line segment from p1 to p2 is unblocked by any blocking hex.
    /// A hex blocks if the line passes through its interior.
    private static func isLineUnblocked(
        from p1: CGPoint,
        to p2: CGPoint,
        blockingCells: [(center: CGPoint, radius: CGFloat)]
    ) -> Bool {
        for cell in blockingCells {
            if lineIntersectsHex(from: p1, to: p2, hexCenter: cell.center, hexRadius: cell.radius) {
                return false
            }
        }
        return true
    }

    /// Check if a line segment intersects a hex.
    /// Uses a simplified approach: check if the line passes through the hex's bounding hexagon
    /// by testing against the 6 edges of the hex.
    private static func lineIntersectsHex(
        from p1: CGPoint,
        to p2: CGPoint,
        hexCenter: CGPoint,
        hexRadius: CGFloat
    ) -> Bool {
        // Compute the 6 corners of the blocking hex
        let corners = (0..<6).map { i -> CGPoint in
            let angle = CGFloat(i) * .pi / 3.0
            return CGPoint(
                x: hexCenter.x + hexRadius * cos(angle),
                y: hexCenter.y + hexRadius * sin(angle)
            )
        }

        // Check if the line intersects any edge of the hex
        for i in 0..<6 {
            let j = (i + 1) % 6
            if segmentsIntersect(p1, p2, corners[i], corners[j]) {
                return true
            }
        }

        // Check if either endpoint is inside the hex
        if pointInHex(p1, center: hexCenter, radius: hexRadius) { return true }
        if pointInHex(p2, center: hexCenter, radius: hexRadius) { return true }

        return false
    }

    /// Check if two line segments intersect.
    /// Uses the cross product method.
    private static func segmentsIntersect(
        _ a1: CGPoint, _ a2: CGPoint,
        _ b1: CGPoint, _ b2: CGPoint
    ) -> Bool {
        let d1 = cross(a1, a2, b1)
        let d2 = cross(a1, a2, b2)
        let d3 = cross(b1, b2, a1)
        let d4 = cross(b1, b2, a2)

        // Lines touching at exactly a corner doesn't block (per GH rules)
        // So we use strict inequality
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }

        return false
    }

    /// Cross product of vectors (b-a) and (c-a).
    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    /// Check if a point is inside a hex (approximate using distance check).
    private static func pointInHex(_ point: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
        // Use a slightly reduced radius to avoid edge cases at corners
        let innerRadius = radius * 0.866 // cos(30°) = sqrt(3)/2
        let dx = abs(point.x - center.x)
        let dy = abs(point.y - center.y)
        return dx < innerRadius && dy < radius * 0.95 && dx + dy * 0.577 < innerRadius
    }
}
