import Foundation

/// Resolves area-of-effect (AoE) attack patterns on the hex board.
///
/// Pattern strings come from the GHS monster ability data, e.g.
/// `"(0,1,target)|(1,0,target)|(1,1,active)|(1,2,target)"`. Each `(x,y,type)` hex is in
/// **odd-row offset** coordinates (x = column, y = row, odd rows shifted half a hex right) —
/// the same pointy-top convention as the board (`HexMath.oddRowToCube`). This is what makes
/// e.g. Deep Terror's 6-hex pattern a straight line and the 7-hex Spitting Drake / Flame
/// Demon pattern a "flower" (a center hex plus its 6 neighbors).
///
/// Hex types:
/// - `active` (grey) — the attacker's own hex. A pattern with an active hex is a **melee** area
///   attack: it is anchored on the attacker and may be rotated to any of the 6 orientations.
/// - `target` / `conditional` (red) — hexes that are attacked.
/// - Patterns with **no** active hex are **ranged** area attacks: the pattern may be placed
///   anywhere in any rotation as long as at least one red hex is within range of the attacker.
///
/// Every enemy hit must be in line of sight of the attacker. The monster places the pattern so
/// it covers its focus and as many other enemies as possible; if no legal placement covers the
/// focus, nothing is hit.
///
/// Targetability (e.g. invisible figures) is the caller's responsibility: pass only enemies
/// that may be targeted. Invisible figures cannot be targeted, even by area attacks.
enum AoEResolver {

    /// A parsed AoE hex with its type, in cube coordinates (same frame as `HexCoord.cube`)
    /// relative to the pattern origin.
    struct PatternHex: Equatable {
        let cubeX: Int
        let cubeY: Int
        let cubeZ: Int
        let isTarget: Bool  // true for target/conditional hexes that are attacked
        let isActive: Bool  // true for the attacker's position in the pattern
    }

    /// A concrete placement of a pattern on the board.
    struct Placement: Equatable {
        /// Board hexes covered by the pattern's red (target) hexes.
        let targetHexes: [HexCoord]
        /// Enemies hit by this placement (in LOS of the attacker); the focus target is first.
        let targets: [PieceID]
    }

    // MARK: - Parsing

    /// Parse an AoE pattern string into cube-coordinate hexes.
    ///
    /// Coordinates are relative to the active (attacker) hex when the pattern has one, which then
    /// sits at (0,0,0). Ranged patterns (no active hex) are made relative to their first red hex.
    /// Hex types that don't take part in targeting (blank, invisible, ally, enhance) are dropped.
    static func parsePattern(_ pattern: String) -> [PatternHex] {
        let hexes = ActionHex.parse(pattern).filter {
            $0.type == .active || $0.type == .target || $0.type == .conditional
        }
        guard let origin = hexes.first(where: { $0.type == .active })
            ?? hexes.first(where: { $0.type != .active }) else { return [] }

        let originCube = HexMath.oddRowToCube(origin.x, origin.y)
        return hexes.map { hex in
            let cube = HexMath.oddRowToCube(hex.x, hex.y)
            return PatternHex(
                cubeX: cube.x - originCube.x,
                cubeY: cube.y - originCube.y,
                cubeZ: cube.z - originCube.z,
                isTarget: hex.type == .target || hex.type == .conditional,
                isActive: hex.type == .active
            )
        }
    }

    /// Whether the pattern is a melee area attack (it contains the attacker's grey hex).
    /// Patterns without an active hex are ranged area attacks.
    static func isMeleePattern(_ pattern: String) -> Bool {
        parsePattern(pattern).contains { $0.isActive }
    }

    // MARK: - Targeting

    /// Find the enemies hit by the best placement of an AoE pattern.
    ///
    /// - Parameters:
    ///   - pattern: The AoE pattern string from the ability card.
    ///   - attackerPos: The hex the attack is made from.
    ///   - focusTarget: The attacker's focus; every returned placement covers it.
    ///   - enemies: Targetable enemies (exclude invisible figures).
    ///   - board: The board state (piece positions, walls for LOS).
    ///   - range: Attack range — only used for ranged patterns (no active hex), where at least
    ///     one red hex must be within this range. Ignored for melee patterns.
    /// - Returns: Enemies hit (focus first), or `[]` if no legal placement covers the focus.
    static func resolveTargets(
        pattern: String,
        attackerPos: HexCoord,
        focusTarget: PieceID,
        enemies: [PieceID],
        board: BoardState,
        range: Int = 1
    ) -> [PieceID] {
        bestPlacement(
            pattern: pattern,
            attackerPos: attackerPos,
            focusTarget: focusTarget,
            enemies: enemies,
            board: board,
            range: range
        )?.targets ?? []
    }

    /// Find the best legal placement of an AoE pattern: one that hits the focus (in LOS) and the
    /// most other enemies. Returns `nil` if no legal placement hits the focus.
    /// Ties are broken deterministically (first placement found in rotation order).
    static func bestPlacement(
        pattern: String,
        attackerPos: HexCoord,
        focusTarget: PieceID,
        enemies: [PieceID],
        board: BoardState,
        range: Int = 1
    ) -> Placement? {
        guard let focusPos = board.piecePositions[focusTarget] else { return nil }

        let hexes = parsePattern(pattern)
        let targetOffsets = hexes.filter { $0.isTarget }.map { Cube($0.cubeX, $0.cubeY, $0.cubeZ) }
        guard !targetOffsets.isEmpty else { return nil }
        let isMelee = hexes.contains { $0.isActive }

        // Enemy lookup by hex (summons may share a hex).
        var enemiesAt: [HexCoord: [PieceID]] = [:]
        for enemy in enemies {
            if let pos = board.piecePositions[enemy] {
                enemiesAt[pos, default: []].append(enemy)
            }
        }
        guard enemiesAt[focusPos]?.contains(focusTarget) == true else { return nil }

        var losCache: [HexCoord: Bool] = [:]
        func inSight(_ hex: HexCoord) -> Bool {
            if let cached = losCache[hex] { return cached }
            let result = LineOfSight.hasLOS(from: attackerPos, to: hex, board: board)
            losCache[hex] = result
            return result
        }

        var best: Placement?
        func consider(_ placementHexes: [HexCoord]) {
            var hit: [PieceID] = []
            for hex in placementHexes {
                guard let here = enemiesAt[hex], inSight(hex) else { continue }
                for enemy in here where !hit.contains(enemy) {
                    hit.append(enemy)
                }
            }
            guard let focusIdx = hit.firstIndex(of: focusTarget) else { return }
            hit.remove(at: focusIdx)
            hit.insert(focusTarget, at: 0)
            if best == nil || hit.count > best!.targets.count {
                best = Placement(targetHexes: placementHexes, targets: hit)
            }
        }

        if isMelee {
            // Anchored on the attacker's hex; try all 6 rotations.
            let origin = Cube(attackerPos)
            for turns in 0..<6 {
                consider(targetOffsets.map { ($0.rotated(turns) + origin).hex })
            }
        } else {
            for placement in rangedPlacements(
                offsets: targetOffsets, covering: focusPos,
                attackerPos: attackerPos, range: range, board: board
            ) {
                consider(placement)
            }
        }
        return best
    }

    /// All legal placements of a ranged pattern's red hexes that cover `hex`: every rotation,
    /// with each red hex in turn placed on `hex`, keeping only placements where at least one red
    /// hex is on the map, not the attacker's own hex, and within `range` of the attacker.
    static func rangedPlacements(
        pattern: String,
        covering hex: HexCoord,
        attackerPos: HexCoord,
        range: Int,
        board: BoardState
    ) -> [[HexCoord]] {
        let offsets = parsePattern(pattern).filter { $0.isTarget }.map { Cube($0.cubeX, $0.cubeY, $0.cubeZ) }
        return rangedPlacements(offsets: offsets, covering: hex, attackerPos: attackerPos, range: range, board: board)
    }

    private static func rangedPlacements(
        offsets: [Cube],
        covering hex: HexCoord,
        attackerPos: HexCoord,
        range: Int,
        board: BoardState
    ) -> [[HexCoord]] {
        let effectiveRange = max(range, 1)
        let anchor = Cube(hex)
        var seen = Set<Set<HexCoord>>()
        var placements: [[HexCoord]] = []

        for turns in 0..<6 {
            let rotated = offsets.map { $0.rotated(turns) }
            for pivot in rotated {
                let placed = rotated.map { ($0 - pivot + anchor).hex }
                guard seen.insert(Set(placed)).inserted else { continue }
                let reachable = placed.contains { h in
                    h != attackerPos
                        && board.cells[h] != nil
                        && attackerPos.distance(to: h) <= effectiveRange
                }
                if reachable { placements.append(placed) }
            }
        }
        return placements
    }

    // MARK: - Cube Math

    /// Cube coordinate in the same frame as `HexCoord.cube` / `HexMath.oddRowToCube`.
    private struct Cube: Equatable {
        let x: Int, y: Int, z: Int

        init(_ x: Int, _ y: Int, _ z: Int) {
            self.x = x; self.y = y; self.z = z
        }

        init(_ coord: HexCoord) {
            let c = coord.cube
            self.init(c.x, c.y, c.z)
        }

        var hex: HexCoord { HexCoord.fromCube(x: x, y: y, z: z) }

        /// Rotate by `turns` × 60° around the origin.
        func rotated(_ turns: Int) -> Cube {
            var c = self
            for _ in 0..<(((turns % 6) + 6) % 6) {
                c = Cube(-c.z, -c.x, -c.y)
            }
            return c
        }

        static func + (a: Cube, b: Cube) -> Cube { Cube(a.x + b.x, a.y + b.y, a.z + b.z) }
        static func - (a: Cube, b: Cube) -> Cube { Cube(a.x - b.x, a.y - b.y, a.z - b.z) }
    }
}
