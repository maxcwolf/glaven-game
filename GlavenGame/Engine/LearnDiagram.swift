import Foundation

/// A small hex map that shows a rule (Moving, Line of sight, How monsters choose): figures,
/// terrain, a path, lines of sight, numbers in hexes. Pointy-topped hexes in rows, odd rows
/// shifted half a hex right.
struct LearnDiagram: Equatable {
    struct Hex: Hashable, Comparable {
        let col: Int, row: Int
        init(_ col: Int, _ row: Int) { self.col = col; self.row = row }
        static func < (a: Hex, b: Hex) -> Bool { (a.row, a.col) < (b.row, b.col) }

        /// Hexes between two hexes (cube distance).
        func distance(to other: Hex) -> Int {
            func cube(_ h: Hex) -> (Int, Int, Int) {
                let x = h.col - (h.row - (h.row & 1)) / 2
                let z = h.row
                return (x, -x - z, z)
            }
            let a = cube(self), b = cube(other)
            return max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
        }
    }

    enum Terrain: Equatable { case obstacle, trap, hazard, difficult, wall, door, coin, treasure }

    enum Figure: Equatable {
        case hero(String)
        case enemy(String)
        case elite(String)
        case summon(String)
        /// Where a figure was before it moved (push, pull).
        case ghost(String)
    }

    struct Line: Equatable {
        enum Style: Equatable { case sight, blocked, arrow }
        let from: Hex, to: Hex
        var style: Style
    }

    var cols: Int
    var rows: Int
    var terrain: [Hex: Terrain] = [:]
    var figures: [Hex: Figure] = [:]
    /// Hexes tinted brass: reach, range, a revealed room.
    var lit: Set<Hex> = []
    /// A move, hex by hex, drawn as a dashed arrow.
    var path: [Hex] = []
    var lines: [Line] = []
    /// Small numbers or words in hexes.
    var labels: [Hex: String] = [:]
    /// A brass ring (a monster's focus).
    var ring: Hex?

    /// Every hex of the grid.
    var hexes: [Hex] {
        (0..<rows).flatMap { row in (0..<cols).map { Hex($0, row) } }
    }

    /// Hexes within `range` of `hex` on the grid.
    func within(_ range: Int, of hex: Hex) -> Set<Hex> {
        Set(hexes.filter { $0 != hex && $0.distance(to: hex) <= range })
    }
}

extension LearnDiagram {
    typealias H = Hex

    static let moving: LearnDiagram = {
        var d = LearnDiagram(cols: 7, rows: 3)
        d.figures = [H(0, 1): .hero("B"), H(5, 1): .enemy("1")]
        d.terrain = [H(1, 1): .obstacle, H(3, 1): .difficult, H(4, 0): .trap]
        d.path = [H(0, 1), H(1, 0), H(2, 0), H(2, 1), H(3, 1)]
        d.labels = [H(1, 0): "1", H(2, 0): "2", H(2, 1): "3", H(3, 1): "5"]
        return d
    }()

    static let doors: LearnDiagram = {
        var d = LearnDiagram(cols: 7, rows: 3)
        d.terrain = [H(3, 0): .wall, H(3, 2): .wall, H(3, 1): .door]
        d.figures = [H(2, 1): .hero("B"), H(5, 0): .enemy("1"), H(5, 2): .enemy("2"), H(6, 1): .elite("3")]
        d.path = [H(2, 1), H(3, 1)]
        d.lit = [H(4, 0), H(5, 0), H(6, 0), H(4, 1), H(5, 1), H(6, 1), H(4, 2), H(5, 2), H(6, 2)]
        return d
    }()

    static let loot: LearnDiagram = {
        var d = LearnDiagram(cols: 6, rows: 3)
        d.figures = [H(2, 1): .hero("B")]
        d.terrain = [H(3, 0): .coin, H(1, 1): .coin, H(5, 1): .coin, H(0, 0): .treasure]
        d.lit = d.within(1, of: H(2, 1))
        return d
    }()

    static let summons: LearnDiagram = {
        var d = LearnDiagram(cols: 7, rows: 3)
        d.figures = [H(1, 1): .hero("T"), H(2, 1): .summon("S"), H(5, 1): .enemy("1"), H(5, 0): .enemy("2")]
        d.path = [H(2, 1), H(3, 1), H(4, 1)]
        return d
    }()

    static let attacking: LearnDiagram = {
        var d = LearnDiagram(cols: 8, rows: 4)
        d.figures = [H(1, 1): .hero("S"), H(3, 2): .enemy("1"), H(4, 0): .enemy("2"), H(6, 2): .enemy("3")]
        d.lit = d.within(3, of: H(1, 1))
        d.lines = [Line(from: H(1, 1), to: H(3, 2), style: .sight), Line(from: H(1, 1), to: H(4, 0), style: .sight)]
        d.labels = [H(6, 2): "out"]
        return d
    }()

    static let lineOfSight: LearnDiagram = {
        var d = LearnDiagram(cols: 7, rows: 4)
        d.figures = [H(0, 1): .hero("S"), H(5, 0): .enemy("1"), H(5, 3): .enemy("2")]
        d.terrain = [H(2, 1): .obstacle, H(3, 2): .wall, H(3, 3): .wall]
        d.lines = [Line(from: H(0, 1), to: H(5, 0), style: .sight), Line(from: H(0, 1), to: H(5, 3), style: .blocked)]
        return d
    }()

    static let pushAndPull: LearnDiagram = {
        var d = LearnDiagram(cols: 6, rows: 3)
        d.figures = [H(0, 1): .hero("B"), H(1, 1): .ghost("1"), H(3, 1): .enemy("1")]
        d.terrain = [H(3, 1): .trap]
        d.path = [H(1, 1), H(2, 1), H(3, 1)]
        return d
    }()

    static let focus: LearnDiagram = {
        var d = LearnDiagram(cols: 7, rows: 4)
        d.figures = [H(0, 1): .enemy("1"), H(3, 1): .hero("B"), H(4, 3): .hero("S")]
        d.terrain = [H(2, 2): .obstacle]
        d.lines = [Line(from: H(0, 1), to: H(3, 1), style: .arrow)]
        d.labels = [H(2, 1): "2", H(3, 3): "4"]
        d.ring = H(3, 1)
        return d
    }()

    static let scenarioGoal: LearnDiagram = {
        var d = LearnDiagram(cols: 8, rows: 3)
        d.terrain = [H(4, 0): .wall, H(4, 2): .wall, H(4, 1): .door]
        d.figures = [H(1, 1): .hero("B"), H(2, 2): .hero("S"), H(6, 0): .enemy("2"), H(7, 1): .enemy("3")]
        d.lit = [H(5, 0), H(6, 0), H(7, 0), H(5, 1), H(6, 1), H(7, 1), H(5, 2), H(6, 2), H(7, 2)]
        return d
    }()
}
