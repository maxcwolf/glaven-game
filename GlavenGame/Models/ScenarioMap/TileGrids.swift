import Foundation

/// Defines hex cell grids for each GH map tile ref.
/// Ported from VGB's BoardMapTile.elm `getGridByRef`.
/// Each grid is rows of booleans — true means a hex cell exists at that position.
enum TileGrids {
    // Row format: each inner array is a row of columns (x). Outer array is rows (y).
    // Grid[y][x] = true means cell at (x, y) exists.

    private static let configA: [[Bool]] = [
        [false, false, false, false, false],
        [true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true],
        [false, false, false, false, false],
    ]

    private static let configB: [[Bool]] = [
        [true,  true,  true,  true],
        [true,  true,  true,  false],
        [true,  true,  true,  true],
        [true,  true,  true,  false],
    ]

    private static let configC: [[Bool]] = [
        [false, true,  true,  false],
        [true,  true,  true,  false],
        [true,  true,  true,  true],
        [true,  true,  true,  false],
    ]

    private static let configD: [[Bool]] = [
        [false, true,  true,  true,  false],
        [true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true],
        [true,  true,  true,  true,  false],
        [false, true,  true,  true,  false],
    ]

    private static let configE: [[Bool]] = [
        [false, true,  true,  true,  true],
        [true,  true,  true,  true,  true],
        [false, true,  true,  true,  true],
        [true,  true,  true,  true,  true],
        [false, true,  true,  true,  true],
    ]

    private static let configF: [[Bool]] = [
        [true,  true,  true],
        [true,  true,  false],
        [true,  true,  true],
        [true,  true,  false],
        [true,  true,  true],
        [true,  true,  false],
        [true,  true,  true],
        [true,  true,  false],
        [true,  true,  true],
    ]

    private static let configG: [[Bool]] = [
        [true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  true],
    ]

    private static let configH: [[Bool]] = [
        [false, true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true],
        [false, false, false, true,  true,  false, false],
        [false, false, true,  true,  true,  false, false],
        [false, false, false, true,  true,  false, false],
        [false, false, true,  true,  true,  false, false],
        [false, false, false, true,  true,  false, false],
    ]

    private static let configI: [[Bool]] = [
        [true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true],
    ]

    private static let configJ: [[Bool]] = [
        [false, false, false, false, false, false, true,  false],
        [false, false, false, false, false, true,  true,  true],
        [false, false, false, false, false, true,  true,  true],
        [false, false, false, false, true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  false, false],
        [true,  true,  true,  true,  true,  false, false, false],
    ]

    private static let configJ1ba: [[Bool]] = [
        [false, false, false, false, false, false, false, false],
        [false, false, false, false, true,  true,  false, false],
        [false, false, false, false, true,  true,  true,  false],
        [false, false, false, false, true,  true,  true,  false],
        [false, false, false, false, false, true,  true,  true],
        [false, false, false, false, false, true,  false, false],
        [false, false, false, false, false, false, false, false],
    ]

    private static let configJ1bb: [[Bool]] = [
        [true,  true,  true,  true,  true,  false, false, false],
        [true,  true,  true,  true,  false, false, false, false],
        [true,  true,  true,  true,  false, false, false, false],
        [false, false, false, false, false, false, false, false],
        [false, false, false, false, false, false, false, false],
        [false, false, false, false, false, false, false, false],
        [false, false, false, false, false, false, false, false],
    ]

    private static let configK: [[Bool]] = [
        [false, false, true,  true,  true,  true,  false, false],
        [false, true,  true,  true,  true,  true,  false, false],
        [false, true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  false, true,  true,  true,  false],
        [true,  true,  true,  false, false, true,  true,  true],
        [true,  true,  false, false, false, true,  true,  false],
    ]

    private static let configL: [[Bool]] = [
        [true,  true,  true,  true,  true],
        [true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true],
        [true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true],
        [true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true],
    ]

    private static let configM: [[Bool]] = [
        [false, true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  false],
        [false, true,  true,  true,  true,  false],
    ]

    private static let configN: [[Bool]] = [
        [true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  true],
        [true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  true,  true,  true,  true,  true,  true],
    ]

    /// Returns the hex cell grid for a tile ref string.
    /// Grid is `[row][col]` where `true` means a hex cell exists.
    static func grid(for ref: String) -> [[Bool]] {
        let r = ref.lowercased()
        // J1b is special: reversed configJ
        if r == "j1b" || r == "j2b" { return configJ.reversed() }
        if r == "j1ba" { return configJ1ba }
        if r == "j1bb" { return configJ1bb }

        // Map letter prefix to config
        guard let first = r.first else { return [[true]] }
        switch first {
        case "a": return configA
        case "b": return configB
        case "c": return configC
        case "d": return configD
        case "e": return configE
        case "f": return configF
        case "g": return configG
        case "h": return configH
        case "i": return configI
        case "j": return configJ
        case "k": return configK
        case "l": return configL
        case "m": return configM
        case "n": return configN
        default:  return [[true]]
        }
    }
}

// MARK: - Per-Tile Image Offsets

/// Per-tile image offsets ported from VGB's `_board.scss`.
/// Each tile image is positioned within a 75×90 container using these (left, top) pixel offsets.
enum TileImageOffsets {
    private static let offsets: [String: (left: Int, top: Int)] = [
        "a1a": (-2,  41),  "a1b": (-19, 39),
        "a2a": (-20, 20),  "a2b": (-20, 20),
        "a3a": (-20, 20),  "a3b": (-20, 20),
        "a4a": (-20, 20),  "a4b": (-20, 20),
        "b1a": (-27, -51), "b1b": (-27, -51),
        "b2a": (-27, -51), "b2b": (-27, -51),
        "b3a": (-27, -51), "b3b": (-27, -51),
        "b4a": (-27, -51), "b4b": (-27, -51),
        "c1a": (-61, -45), "c1b": (-61, -45),
        "c2a": (-61, -45), "c2b": (-61, -45),
        "d1a": (-59, -50), "d1b": (-59, -50),
        "d2a": (-59, -50), "d2b": (-59, -50),
        "e1a": (12,  -44), "e1b": (12,  -44),
        "f1a": (-24, -45), "f1b": (-24, -45),
        "g1a": (-22, -48), "g1b": (-22, -48),
        "g2a": (-22, -48), "g2b": (-22, -48),
        "h1a": (15,  -40), "h1b": (15,  -40),
        "h2a": (15,  -40), "h2b": (15,  -40),
        "h3a": (15,  -40), "h3b": (15,  -40),
        "i1a": (-25, -47), "i1b": (-25, -47),
        "i2a": (-25, -47), "i2b": (-25, -47),
        "j1a": (-25, -51), "j1b": (-24, -49),
        "j1ba": (-24, -49), "j1bb": (-24, -49),
        "j2a": (-25, -52), "j2b": (-24, -49),
        "k1a": (-56, -47), "k1b": (-71, -47),
        "k2a": (-73, -45), "k2b": (-56, -47),
        "l1a": (-25, -47), "l1b": (-25, -47),
        "l2a": (-25, -47), "l2b": (-25, -47),
        "l3a": (-25, -47), "l3b": (-25, -47),
        "m1a": (-20, -45), "m1b": (-22, -46),
        "n1a": (-19, -48), "n1b": (-19, -48),
    ]

    /// Returns the (left, top) pixel offset for a tile ref, defaulting to (0, 0).
    static func offset(for ref: String) -> (left: Int, top: Int) {
        offsets[ref.lowercased()] ?? (0, 0)
    }
}
