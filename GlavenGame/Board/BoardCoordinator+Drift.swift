import Foundation

/// A board that moves the party as the round ends: the wind of the Windswept Highlands, the
/// current of the Plane of Water (`ScenarioPlacements.Drift`).
extension BoardCoordinator {

    /// The six sides of a hex by name, in the order `HexCoord.neighbors` lists them.
    static let hexSides = ["NE", "E", "SE", "SW", "W", "NW"]

    /// The hex beside `hex` on the side named.
    func neighbor(of hex: HexCoord, toward side: String) -> HexCoord? {
        Self.hexSides.firstIndex(of: side).map { hex.neighbors[$0] }
    }

    /// The hex beside `hex` on the side opposite the one named.
    private func neighbor(of hex: HexCoord, awayFrom side: String) -> HexCoord? {
        Self.hexSides.firstIndex(of: side).map { hex.neighbors[($0 + 3) % 6] }
    }

    /// What moves the party as this round ends: which way, and whom in what order.
    struct DriftToCome {
        let drift: ScenarioPlacements.Drift
        let sides: [String]
        let order: [PieceID]
    }

    /// The round's drift, decided while the round's cards still lie drawn (its direction can
    /// hang on a monster's initiative, and its order on the characters'). Nil when the
    /// scenario has none or no one stands where it reaches.
    func driftToCome() -> DriftToCome? {
        guard let drift = scenarioData?.placements?.drift, let gameManager else { return nil }
        let order = driftOrder(drift)
        guard !order.isEmpty else { return nil }
        var sides: [String] = []
        if let cycle = drift.directions, !cycle.isEmpty {
            sides = cycle[(max(1, gameManager.game.round) - 1) % cycle.count]
        } else if let by = drift.byInitiative, let initiative = driftInitiative(of: by.monster) {
            sides = initiative % 2 == 0 ? by.even : by.odd
        }
        guard !sides.isEmpty else { return nil }
        return DriftToCome(drift: drift, sides: sides, order: order)
    }

    /// The characters and their summons the drift reaches, in initiative order (a summon before
    /// its owner) or from the top of the map down.
    private func driftOrder(_ drift: ScenarioPlacements.Drift) -> [PieceID] {
        guard let gameManager else { return [] }
        var characters = gameManager.game.characters.filter { !$0.exhausted && !$0.absent }
        let turns = turnOrder.compactMap { entry -> String? in
            if case .character(let character) = entry.figure { return character.id }
            return nil
        }
        func place(_ character: GameCharacter) -> (Int, Double, String) {
            (turns.firstIndex(of: character.id) ?? turns.count, character.longRest ? 99 : character.effectiveInitiative, character.id)
        }
        characters.sort { place($0) < place($1) }
        var pieces: [PieceID] = characters.flatMap { character in
            character.summons.filter { !$0.dead }.map { PieceID.summon(id: $0.id) } + [.character(character.id)]
        }.filter { piece in
            guard let hex = boardState.piecePositions[piece] else { return false }
            guard let tiles = drift.tiles else { return true }
            return (boardState.cells[hex]?.tileRef.lowercased()).map(tiles.contains) ?? false
        }
        if drift.order == "top" {
            pieces.sort { (boardState.piecePositions[$0]?.row ?? 0, boardState.piecePositions[$0]?.col ?? 0)
                < (boardState.piecePositions[$1]?.row ?? 0, boardState.piecePositions[$1]?.col ?? 0) }
        }
        return pieces
    }

    /// This round's initiative of a monster type's ability card: the card it (or a type sharing
    /// its deck) acted on, else one drawn from its deck for this alone.
    private func driftInitiative(of name: String) -> Int? {
        guard let gameManager, let monster = gameManager.game.monsters.first(where: { $0.name == name }) else { return nil }
        if let drawn = gameManager.monsterManager.currentAbilityInitiative(for: monster) { return drawn }
        gameManager.monsterManager.drawAbility(for: monster)
        guard let drawn = gameManager.monsterManager.currentAbilityInitiative(for: monster) else { return nil }
        log("A \(GameText.monsterName(name)) card is drawn for the round: initiative \(drawn)", category: .info)
        return drawn
    }

    /// Whether a figure can be moved from `from` into `hex`: an empty hex that isn't a wall, an
    /// obstacle or a closed door, with no wall between the two.
    func canDrift(into hex: HexCoord, from: HexCoord) -> Bool {
        guard let cell = boardState.cells[hex], cell.passable, cell.overlay != .wall, !boardState.isClosedDoor(hex),
              !boardState.isWalled(from, hex) else { return false }
        return boardState.piece(at: hex) == nil
    }

    /// Whether the hex the drift comes from, beside `here`, is an obstacle or a wall.
    private func givesShelter(_ hex: HexCoord, to here: HexCoord) -> Bool {
        guard let cell = boardState.cells[hex] else { return true }
        return cell.overlay == .wall || cell.overlay == .obstacle || boardState.isClosedDoor(hex) || boardState.isWalled(here, hex)
    }

    /// Move everyone the drift reaches one hex, one figure at a time.
    @MainActor func driftAsTheRoundEnds(_ coming: DriftToCome) async {
        let drift = coming.drift
        let generation = boardGeneration
        log("The \(drift.name) moves the party \(Self.driftWords(coming.sides))", category: .move)
        for piece in coming.order {
            guard isCurrentBoard(generation), scenarioResult == nil, isOnBoard(piece),
                  let here = boardState.piecePositions[piece] else { continue }
            if drift.sheltered == true, coming.sides.count == 1, let behind = neighbor(of: here, awayFrom: coming.sides[0]),
               givesShelter(behind, to: here) {
                log("\(name(piece)) is sheltered from the \(drift.name)", category: .move)
                continue
            }
            let open = coming.sides.compactMap { neighbor(of: here, toward: $0) }.filter { canDrift(into: $0, from: here) }.sorted()
            guard !open.isEmpty else {
                if let damage = drift.blocked {
                    log("\(name(piece)) can't be moved by the \(drift.name) and suffers \(damage) damage", category: .damage)
                    await sufferDamageWithMitigation(damage, to: piece, source: "The \(drift.name)")
                } else {
                    log("\(name(piece)) can't be moved by the \(drift.name)", category: .move)
                }
                continue
            }
            // Of two ways with one shut, the players may have the figure stopped instead (FAQ, #71).
            let mayStay = coming.sides.count > 1 && open.count < coming.sides.count
            var destination = open[0]
            if open.count > 1 || mayStay {
                destination = await chooseHex(open + (mayStay ? [here] : []), for: piece, title: "The \(drift.name)",
                                              detail: "Tap the hex \(name(piece)) is moved into"
                                                  + (mayStay ? ", or \(name(piece)) to stay" : "")) ?? open[0]
                guard isCurrentBoard(generation) else { return }
            }
            guard destination != here else {
                log("\(name(piece)) stands against the \(drift.name)", category: .move)
                continue
            }
            log("The \(drift.name) moves \(name(piece)) [to \(destination)]", category: .move)
            await moveAlong(piece, path: [here, destination], style: .forced)
        }
    }

    /// "up and to the left", "to the right": the sides as the players see them.
    static func driftWords(_ sides: [String]) -> String {
        let words = ["NE": "up and to the right", "E": "to the right", "SE": "down and to the right",
                     "SW": "down and to the left", "W": "to the left", "NW": "up and to the left"]
        if Set(sides) == ["NW", "NE"] { return "up" }
        if Set(sides) == ["SW", "SE"] { return "down" }
        return sides.compactMap { words[$0] }.joined(separator: " or ")
    }

    // MARK: - A hex to choose

    struct PendingHexChoice {
        let options: [HexCoord]
        var continuation: CheckedContinuation<HexCoord?, Never>?
    }

    /// Ask the players which of `options` (the hex `piece` stands on may be one: tap the
    /// figure); headless play takes the first. Nil if the board was left meanwhile.
    @MainActor func chooseHex(_ options: [HexCoord], for piece: PieceID, title: String, detail: String) async -> HexCoord? {
        guard !autoResolvePrompts, options.count > 1 else { return options.first }
        return await withCheckedContinuation { continuation in
            pendingHexChoice = PendingHexChoice(options: options, continuation: continuation)
            interactionMode = .choosingHex(piece: piece, title: title, detail: detail, validHexes: Set(options))
            boardScene?.highlightHexes(Set(options), style: .forcedMove, offsetCol: offsetCol, offsetRow: offsetRow)
        }
    }

    /// The hex tapped, if it is one of those offered.
    func resolveHexChoice(_ hex: HexCoord) {
        guard let pending = pendingHexChoice, pending.options.contains(hex) else { return }
        pendingHexChoice = nil
        interactionMode = .idle
        boardScene?.clearHighlights()
        pending.continuation?.resume(returning: hex)
    }
}
