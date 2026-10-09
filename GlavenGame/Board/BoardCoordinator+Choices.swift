import Foundation

/// One thing the player can pick on the board right now, said in words: VoiceOver offers these
/// as actions on the board, so a hex or a target can be chosen without seeing the map.
struct BoardChoice: Identifiable {
    let id: String
    let label: String
    let perform: () -> Void
}

extension BoardCoordinator {

    /// The choices the current prompt allows, nearest first. Each does exactly what tapping it
    /// on the board does.
    func accessibleChoices() -> [BoardChoice] {
        switch interactionMode {
        case .placingCharacter:
            let free = boardState.startingLocations.filter { !boardState.isOccupied($0) }
            return hexChoices(free, from: nil) { "Start \($0)" }

        case .selectingMove(let mover, _, let hexes, let teleport, _):
            let verb = teleport ? "Teleport" : "Move"
            return hexChoices(hexes, from: boardState.piecePositions[mover]) { "\(verb) \($0)" }

        case .placingSummon(let summonID, let owner, let hexes):
            return hexChoices(hexes, from: boardState.piecePositions[.character(owner)]) { "Place \(self.name(.summon(id: summonID))) \($0)" }

        case .selectingPushPullHex(let target, _, let hexes, _, let isPush):
            let verb = isPush ? "Push" : "Pull"
            return hexChoices(hexes, from: boardState.piecePositions[target]) { "\(verb) \(self.name(target)) \($0)" }

        case .selectingAttackTarget(let attacker, _, let targets):
            return pieceChoices(targets, from: attacker) { "Attack \($0)" }

        case .selectingMultiAttackTargets(let attacker, _, let targets, let count, let selected):
            var choices = pieceChoices(targets.subtracting(selected), from: attacker) { "Target \($0)" }
            if !selected.isEmpty {
                let names = GameText.list(selected.map(name))
                choices.insert(BoardChoice(id: "confirm",
                                           label: "Attack \(names) (\(selected.count) of \(count))") { [weak self] in
                    self?.confirmMultiAttack()
                }, at: 0)
            }
            return choices

        case .selectingHealTarget(let healer, let value, let targets):
            return pieceChoices(targets, from: healer) { "Heal \(value): \($0)" }

        case .selectingConditionTarget(let source, let condition, let targets):
            return pieceChoices(targets, from: source) { "\(GameText.conditionName(condition)) \($0)" }

        case .selectingForcedMoveTarget(let source, let steps, let isPush, let targets):
            return pieceChoices(targets, from: source) { "\(isPush ? "Push" : "Pull") \(steps): \($0)" }

        case .idle, .watchingMonsterTurn:
            return []
        }
    }

    // MARK: - Figures

    private func pieceChoices(_ pieces: Set<PieceID>, from source: PieceID,
                              label: @escaping (String) -> String) -> [BoardChoice] {
        let origin = boardState.piecePositions[source]
        return pieces.sorted { a, b in
            let da = distance(origin, boardState.piecePositions[a]), db = distance(origin, boardState.piecePositions[b])
            return (da, a) < (db, b)
        }.map { piece in
            BoardChoice(id: "piece-\(piece)", label: label(spokenFigure(piece, from: origin))) { [weak self] in
                self?.handlePieceTap(piece)
            }
        }
    }

    /// "Bandit Guard 2, 5 of 5 health, 2 hexes away" ("you" for the acting figure itself).
    func spokenFigure(_ piece: PieceID, from origin: HexCoord?) -> String {
        var parts = [name(piece)]
        if let entity = entity(for: piece) { parts.append("\(entity.health) of \(entity.maxHealth) health") }
        if let origin, let hex = boardState.piecePositions[piece] {
            let steps = origin.distance(to: hex)
            parts.append(steps == 0 ? "yourself" : steps == 1 ? "next to you" : "\(steps) hexes away")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Hexes

    private func hexChoices(_ hexes: some Collection<HexCoord>, from origin: HexCoord?,
                            label: @escaping (String) -> String) -> [BoardChoice] {
        let sorted = hexes.sorted { a, b in (distance(origin, a), a) < (distance(origin, b), b) }
        var seen: [String: Int] = [:]
        return sorted.map { hex in
            var text = label(spokenHex(hex, from: origin))
            // Two hexes can read alike ("2 hexes east"); number the later ones.
            seen[text, default: 0] += 1
            if let n = seen[text], n > 1 { text += " (\(n))" }
            return BoardChoice(id: "hex-\(hex.col)-\(hex.row)", label: text) { [weak self] in
                self?.handleHexTap(hex)
            }
        }
    }

    /// Where a hex is and what's on or beside it: "3 hexes northeast, trap, next to Bandit Guard 1".
    func spokenHex(_ hex: HexCoord, from origin: HexCoord?) -> String {
        var parts: [String] = []
        if let origin {
            let steps = origin.distance(to: hex)
            parts.append(steps == 0 ? "where you stand" : "\(steps) hex\(steps == 1 ? "" : "es") \(Self.direction(from: origin, to: hex))")
        } else {
            parts.append("at column \(hex.col), row \(hex.row)")
        }
        if let cell = boardState.cells[hex] {
            switch cell.overlay {
            case .trap: parts.append("trap")
            case .hazard: parts.append("hazardous terrain")
            case .difficultTerrain: parts.append("difficult terrain")
            case .treasure: parts.append("treasure")
            case .door: parts.append("door")
            default: break
            }
        }
        if (boardState.lootTokens[hex] ?? 0) > 0 { parts.append("money token") }
        // Whoever stands at the origin (the mover, the one pushed) isn't news.
        let beside = hex.neighbors.filter { $0 != origin }.compactMap { boardState.piece(at: $0) }.sorted()
        if !beside.isEmpty { parts.append("next to \(GameText.list(beside.map(name)))") }
        return parts.joined(separator: ", ")
    }

    /// The compass direction from one hex to another, as the map is drawn (north is up).
    static func direction(from origin: HexCoord, to hex: HexCoord) -> String {
        let a = origin.pixelPosition, b = hex.pixelPosition
        let angle = atan2(-(b.y - a.y), b.x - a.x) * 180 / .pi   // screen y grows downward
        let names = ["east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"]
        let sector = Int(((angle + 360 + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return names[sector % 8]
    }

    private func distance(_ origin: HexCoord?, _ hex: HexCoord?) -> Int {
        guard let origin, let hex else { return 0 }
        return origin.distance(to: hex)
    }
}
