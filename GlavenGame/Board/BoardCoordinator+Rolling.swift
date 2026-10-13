import Foundation

/// Obstacles that roll along their rows as each round ends: the boulders of Rockslide Ridge
/// (`ScenarioPlacements.Rolling`).
extension BoardCoordinator {

    var scenarioRolling: ScenarioPlacements.Rolling? { scenarioData?.placements?.rolling }

    /// The rows the boulders roll along, the top of the map first: each from the hex a boulder
    /// comes back in at to the last hex of the map on the side they roll toward.
    func rollerRows() -> [[HexCoord]] {
        guard let rolling = scenarioRolling else { return [] }
        let starts = (boardState.markerHexes[rolling.reenter] ?? []).sorted { ($0.row, $0.col) < ($1.row, $1.col) }
        return starts.map { start in
            var row = [start]
            while row.count < 60, let next = row[row.count - 1].neighbor(toward: rolling.side),
                  let cell = boardState.cells[next], cell.overlay != .wall, !boardState.isClosedDoor(next) {
                row.append(next)
            }
            return row
        }
    }

    /// Where the rolling obstacles lie, found on the map the first time they are asked for.
    func rollers() -> [HexCoord] {
        if boardState.rollers.isEmpty, let rolling = scenarioRolling {
            boardState.rollers = boardState.cells.values
                .filter { $0.overlay == .obstacle && $0.overlaySubType == rolling.subType }.map(\.coord).sorted()
        }
        return boardState.rollers
    }

    /// The ways the rows can roll: each row a different number of hexes.
    func rollChoices(rows: Int) -> [[Int]] {
        func arrange(_ left: [Int], _ count: Int) -> [[Int]] {
            guard count > 0 else { return [[]] }
            return left.indices.flatMap { index -> [[Int]] in
                var rest = left
                let first = rest.remove(at: index)
                return arrange(rest, count - 1).map { [first] + $0 }
            }
        }
        return arrange((scenarioRolling?.steps ?? []).sorted(), rows)
    }

    /// The hexes a boulder at `from` enters rolling `steps` along `row`, in order: the last hex
    /// of the row is entered and left for the first in the same step.
    func rollPath(from: HexCoord, along row: [HexCoord], steps: Int) -> [[HexCoord]] {
        guard var index = row.firstIndex(of: from), row.count > 2 else { return [] }
        var path: [[HexCoord]] = []
        for _ in 0..<max(0, steps) {
            index += 1
            var entered = [row[min(index, row.count - 1)]]
            if index >= row.count - 1 {
                index = 0
                entered.append(row[0])
            }
            path.append(entered)
        }
        return path
    }

    /// The choice that rolls over the fewest of the party, then over the most of its enemies.
    func gentlestRoll(_ choices: [[Int]], rows: [[HexCoord]]) -> Int {
        let boulders = rollers()
        func harm(_ choice: [Int]) -> (Int, Int) {
            var party = 0, enemies = 0
            for (row, steps) in zip(rows, choice) {
                for boulder in boulders where row.contains(boulder) {
                    for hex in rollPath(from: boulder, along: row, steps: steps).flatMap({ $0 }) {
                        guard let piece = boardState.piece(at: hex) else { continue }
                        if case .objective = piece { continue }
                        if isPlayerSide(piece) { party += 1 } else { enemies += 1 }
                    }
                }
            }
            return (party, -enemies)
        }
        return choices.indices.min { harm(choices[$0]) < harm(choices[$1]) } ?? 0
    }

    /// "Top 1 · Middle 3 · Bottom 2".
    static func rollWords(_ choice: [Int]) -> String {
        let names = choice.count == 3 ? ["Top", "Middle", "Bottom"] : choice.indices.map { "Row \($0 + 1)" }
        return zip(names, choice).map { "\($0) \($1)" }.joined(separator: " \u{B7} ")
    }

    /// The round is over: the players say how far each row rolls, and the boulders roll.
    @MainActor func rollAsTheRoundEnds() async {
        let rows = rollerRows()
        guard !rows.isEmpty, !rollers().isEmpty else { return }
        let choices = rollChoices(rows: rows.count)
        guard !choices.isEmpty else { return }
        let suggested = gentlestRoll(choices, rows: rows)
        let generation = boardGeneration
        var chosen = suggested
        if choices.count > 1 {
            chosen = await chooseOption(choices.map(Self.rollWords), title: "The boulders roll",
                                        question: "How many hexes does each row roll? Each row a different number.",
                                        suggested: suggested) ?? suggested
            guard isCurrentBoard(generation) else { return }
        }
        await rollBoulders(by: choices[chosen])
    }

    /// Roll each row's boulders `steps[row]` hexes, the top row first and in a row the boulder
    /// further along first.
    @MainActor func rollBoulders(by steps: [Int]) async {
        let rows = rollerRows()
        let generation = boardGeneration
        log("The boulders roll: \(Self.rollWords(steps))", category: .move)
        for (row, count) in zip(rows, steps) {
            let inRow = rollers().filter(row.contains).sorted { (row.firstIndex(of: $0) ?? 0) > (row.firstIndex(of: $1) ?? 0) }
            for boulder in inRow {
                await roll(boulder, along: row, steps: count)
                guard isCurrentBoard(generation), scenarioResult == nil else { return }
            }
        }
    }

    @MainActor private func roll(_ boulder: HexCoord, along row: [HexCoord], steps: Int) async {
        guard let rolling = scenarioRolling, let gameManager else { return }
        let generation = boardGeneration
        var here = boulder
        for entered in rollPath(from: boulder, along: row, steps: steps) {
            for hex in entered {
                // "The boulders destroy any obstacle in their way, but do not affect traps."
                if let cell = boardState.cells[hex], cell.overlay == .obstacle, !boardState.rollers.contains(hex) {
                    boardState.removeObstacle(at: hex)
                    boardState.cells[hex]?.overlayImageName = nil
                    boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
                    log("A boulder destroys the obstacle in its way", category: .info, trace: "at \(hex)")
                }
                // "If any boulder moves onto a hex occupied by any figure, that figure takes trap damage."
                if let figure = boardState.piece(at: hex), isRolledOver(figure) {
                    let damage = gameManager.levelManager.trap()
                    log("A boulder rolls over \(name(figure)): \(damage) damage", category: .damage)
                    await sufferDamageWithMitigation(damage, to: figure, source: "A boulder")
                    guard isCurrentBoard(generation), scenarioResult == nil else { return }
                }
            }
            guard let last = entered.last else { continue }
            moveRoller(rolling, from: here, to: last)
            here = last
        }
        // "If the boulder stops in any figure's hex, that figure is forced to move one hex to the left."
        guard let figure = boardState.piece(at: here), isRolledOver(figure), isOnBoard(figure) else { return }
        if let beside = here.neighbor(toward: rolling.side), canDrift(into: beside, from: here) {
            log("The boulder pushes \(name(figure)) aside [to \(beside)]", category: .move)
            await moveAlong(figure, path: [here, beside], style: .forced)
        } else if let free = nearestEmptyHex(to: here) {
            // (Nowhere to go that way: the nearest empty hex, as for any figure without a place.)
            log("The boulder pushes \(name(figure)) aside [to \(free)]", category: .move)
            await animateMove(figure, along: [here, free], as: .teleport)
            guard isCurrentBoard(generation), isOnBoard(figure) else { return }
            boardState.movePiece(figure, to: free)
            syncPieceVisuals()
        }
    }

    /// Figures a boulder harms and pushes: any but an objective.
    private func isRolledOver(_ piece: PieceID) -> Bool {
        if case .objective = piece { return false }
        return true
    }

    /// The art an overlay of the map is drawn with: "obstacle-boulder-1", "trap-spike",
    /// "difficult-terrain-rubble".
    private func overlayArt(_ cell: HexCell) -> String? {
        if let name = cell.overlayImageName { return name }
        guard let overlay = cell.overlay, let subType = cell.overlaySubType else { return nil }
        let kind: String
        switch overlay {
        case .obstacle: kind = "obstacle"
        case .trap: kind = "trap"
        case .difficultTerrain: kind = "difficult-terrain"
        case .hazard: kind = "hazard"
        default: return nil
        }
        return "\(kind)-\(subType)"
    }

    /// Lift the boulder off `from` (what it lay on is there again) and lay it on `to`.
    private func moveRoller(_ rolling: ScenarioPlacements.Rolling, from: HexCoord, to: HexCoord) {
        guard from != to, let lifted = boardState.cells[from] else { return }
        let art = overlayArt(lifted) ?? "obstacle-\(rolling.subType)"
        if let under = boardState.underRollers.removeValue(forKey: from) {
            boardState.cells[from] = under
        } else {
            boardState.removeObstacle(at: from)
            boardState.cells[from]?.overlayImageName = nil
        }
        boardScene?.removeOverlaySprite(at: from, offsetCol: offsetCol, offsetRow: offsetRow)
        if let cell = boardState.cells[from], cell.overlay != nil, let beneath = overlayArt(cell) {
            boardScene?.addOverlaySprite(imageName: beneath, at: from, offsetCol: offsetCol, offsetRow: offsetRow)
        }
        if let cell = boardState.cells[to], cell.overlay != nil { boardState.underRollers[to] = cell }
        boardState.cells[to]?.overlay = .obstacle
        boardState.cells[to]?.overlaySubType = rolling.subType
        boardState.cells[to]?.overlayImageName = lifted.overlayImageName
        boardState.cells[to]?.passable = false
        boardScene?.removeOverlaySprite(at: to, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.addOverlaySprite(imageName: art, at: to, offsetCol: offsetCol, offsetRow: offsetRow)
        boardState.rollers = (boardState.rollers.filter { $0 != from } + [to]).sorted()
    }

    // MARK: - An answer in words

    struct PendingOptionChoice: Identifiable {
        let id = UUID()
        let title: String
        let question: String
        let options: [String]
        /// The answer headless play gives, and the one a player in doubt might take.
        let suggested: Int
        var continuation: CheckedContinuation<Int?, Never>?
    }

    /// Ask the players which of `options`; headless play takes the one suggested. Nil if the
    /// board was left meanwhile.
    @MainActor func chooseOption(_ options: [String], title: String, question: String, suggested: Int = 0) async -> Int? {
        guard !autoResolvePrompts, options.count > 1 else { return suggested }
        return await withCheckedContinuation { continuation in
            pendingOptionChoice = PendingOptionChoice(title: title, question: question, options: options,
                                                      suggested: suggested, continuation: continuation)
        }
    }

    func resolveOptionChoice(_ index: Int) {
        guard let pending = pendingOptionChoice, pending.options.indices.contains(index) else { return }
        pendingOptionChoice = nil
        pending.continuation?.resume(returning: index)
    }
}
