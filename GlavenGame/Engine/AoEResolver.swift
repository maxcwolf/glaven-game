import Foundation

/// Resolves AoE (area of effect) patterns on the hex board.
/// Transforms AoE patterns from ability card coordinate space to board coordinates,
/// tries all 6 rotations, and finds the orientation that hits the most enemies.
enum AoEResolver {

    /// A parsed AoE hex with its type.
    struct PatternHex {
        let cubeX: Int
        let cubeY: Int
        let cubeZ: Int
        let isTarget: Bool  // true for target/conditional hexes that deal damage
        let isActive: Bool  // true for the attacker's position in the pattern
    }

    /// Parse an AoE pattern string into cube-coordinate hexes relative to the active hex.
    /// The active hex becomes the origin (0,0,0).
    /// Pattern format: "(x,y,type)|(x,y,type)|..." where x,y are odd-column offset coords.
    static func parsePattern(_ pattern: String) -> [PatternHex] {
        let hexes = ActionHex.parse(pattern)
        guard !hexes.isEmpty else { return [] }

        // Find the active hex (attacker position)
        let activeHex = hexes.first(where: { $0.type == .active })
        let originX = activeHex?.x ?? 0
        let originY = activeHex?.y ?? 0

        // Convert origin to cube
        let originCube = oddColumnToCube(col: originX, row: originY)

        // Convert all hexes to cube coordinates relative to origin
        return hexes.compactMap { hex in
            let cube = oddColumnToCube(col: hex.x, row: hex.y)
            let relX = cube.x - originCube.x
            let relY = cube.y - originCube.y
            let relZ = cube.z - originCube.z

            let isTarget = hex.type == .target || hex.type == .conditional
            let isActive = hex.type == .active

            // Skip invisible/blank hexes — they don't affect targeting
            guard hex.type != .invisible && hex.type != .blank else { return nil }

            return PatternHex(cubeX: relX, cubeY: relY, cubeZ: relZ, isTarget: isTarget, isActive: isActive)
        }
    }

    /// Find the best AoE rotation and return all enemy piece IDs that would be hit.
    /// The result always includes the focus target if it can be hit by any rotation.
    /// - Parameters:
    ///   - pattern: The AoE pattern string from the ability card
    ///   - attackerPos: The attacker's position on the board
    ///   - focusTarget: The primary focus target
    ///   - enemies: All valid enemy piece IDs
    ///   - board: The board state
    /// - Returns: Array of enemy piece IDs hit by the best AoE orientation
    static func resolveTargets(
        pattern: String,
        attackerPos: HexCoord,
        focusTarget: PieceID,
        enemies: [PieceID],
        board: BoardState
    ) -> [PieceID] {
        let patternHexes = parsePattern(pattern)
        guard !patternHexes.isEmpty else { return [] }

        // Get target hexes only (not the active/attacker hex)
        let targetOffsets = patternHexes.filter { $0.isTarget }
        guard !targetOffsets.isEmpty else { return [] }

        let attackerCube = attackerPos.cube

        // Build enemy position lookup
        var positionToEnemies: [HexCoord: [PieceID]] = [:]
        for enemy in enemies {
            if let pos = board.piecePositions[enemy] {
                positionToEnemies[pos, default: []].append(enemy)
            }
        }

        // Try all 6 rotations and pick the one that hits the most enemies (preferring focus)
        var bestTargets: [PieceID] = []
        var bestScore = -1

        for rotation in 0..<6 {
            var hitTargets: [PieceID] = []
            var hitsFocus = false

            for offset in targetOffsets {
                // Rotate the offset
                let rotated = rotateCube(x: offset.cubeX, y: offset.cubeY, z: offset.cubeZ, turns: rotation)
                // Translate to board position
                let boardCube = (x: attackerCube.x + rotated.x, y: attackerCube.y + rotated.y, z: attackerCube.z + rotated.z)
                let boardHex = HexCoord.fromCube(x: boardCube.x, y: boardCube.y, z: boardCube.z)

                // Check if any enemies are on this hex
                if let enemiesHere = positionToEnemies[boardHex] {
                    for enemy in enemiesHere where !hitTargets.contains(enemy) {
                        hitTargets.append(enemy)
                        if enemy == focusTarget { hitsFocus = true }
                    }
                }
            }

            // Score: prioritize hitting focus, then maximize targets
            let score = (hitsFocus ? 1000 : 0) + hitTargets.count
            if score > bestScore {
                bestScore = score
                bestTargets = hitTargets
            }
        }

        // Ensure focus is first in the list if present
        if let focusIdx = bestTargets.firstIndex(of: focusTarget), focusIdx > 0 {
            bestTargets.remove(at: focusIdx)
            bestTargets.insert(focusTarget, at: 0)
        }

        return bestTargets
    }

    // MARK: - Coordinate Helpers

    /// Convert odd-column offset coordinates (used by AoE patterns) to cube coordinates.
    /// AoE patterns use flat-top hexes with odd columns shifted down.
    private static func oddColumnToCube(col: Int, row: Int) -> (x: Int, y: Int, z: Int) {
        let x = col
        let z = row - (col - (col & 1)) / 2
        let y = -x - z
        return (x, y, z)
    }

    /// Rotate cube coordinates by N × 60° clockwise around the origin.
    private static func rotateCube(x: Int, y: Int, z: Int, turns: Int) -> (x: Int, y: Int, z: Int) {
        var cx = x, cy = y, cz = z
        for _ in 0..<(turns % 6) {
            let newX = -cz
            let newY = -cx
            let newZ = -cy
            cx = newX
            cy = newY
            cz = newZ
        }
        return (cx, cy, cz)
    }
}
