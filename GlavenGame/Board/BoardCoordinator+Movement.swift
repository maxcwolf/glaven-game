import Foundation

/// How a figure travels along a path, which decides which hexes' terrain affects it.
enum MovementStyle {
    /// Normal movement: every hex entered triggers traps and hazardous terrain.
    case normal
    /// Jump: only the last hex counts as entered (GH p.17).
    case jump
    /// Flying: unaffected by traps and terrain for the whole move.
    case fly
    /// Push/pull: every hex entered triggers traps and hazards (difficult terrain doesn't apply).
    case forced
}

extension BoardCoordinator {

    /// Move a piece along `path` (first element = current hex), resolving traps, hazardous
    /// terrain and — for characters — closed doors on every hex actually entered.
    /// Returns false if the figure died (or became exhausted) along the way.
    @discardableResult
    @MainActor func moveAlong(_ pieceID: PieceID, path: [HexCoord], style: MovementStyle) async -> Bool {
        guard path.count > 1 else { return isOnBoard(pieceID) }
        moveObserver?(pieceID, path, style)
        let opensDoors: Bool = { if case .character = pieceID { return true }; return false }()

        var segmentStart = 0
        for index in 1..<path.count {
            let hex = path[index]
            let isLast = index == path.count - 1
            let entered = style == .normal || style == .forced || (style == .jump && isLast)
            let cell = boardState.cells[hex]
            let hitsTrap = entered && cell?.isTrap == true
            let hitsHazard = entered && cell?.isHazard == true
            let opensDoor = opensDoors && boardState.doors.contains { $0.coord == hex && !$0.isOpen }

            guard hitsTrap || hitsHazard || opensDoor || isLast else { continue }

            await animateMove(pieceID, along: Array(path[segmentStart...index]), as: MoveAnimation(style))
            segmentStart = index
            if !boardState.isOccupied(hex) || boardState.piecePositions[pieceID] == hex {
                boardState.movePiece(pieceID, to: hex)
            }

            if hitsTrap {
                guard await springTrap(at: hex, on: pieceID) else { return false }
                // Immobilize takes effect at once (e.g. a bear trap): the rest of the move is lost.
                if style != .forced && isConditionActive(.immobilize, on: pieceID) {
                    log("\(name(pieceID)) is immobilized and stops", category: .condition)
                    return isOnBoard(pieceID)
                }
            }
            if hitsHazard {
                guard await enterHazard(at: hex, on: pieceID) else { return false }
            }
            if opensDoor {
                openDoor(at: hex)
            }
        }
        return isOnBoard(pieceID)
    }

    func isOnBoard(_ pieceID: PieceID) -> Bool {
        boardState.piecePositions[pieceID] != nil
    }

    /// Animate a piece along a path (skipped when no scene is attached, e.g. in tests).
    @MainActor func animateMove(_ pieceID: PieceID, along path: [HexCoord], as animation: MoveAnimation = .walk) async {
        guard path.count > 1, let scene = boardScene else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            scene.movePiece(id: pieceID, along: path, animation: animation, offsetCol: offsetCol, offsetRow: offsetRow) {
                continuation.resume()
            }
        }
    }

    /// Spring the trap on `hex` (GH p.13): damage traps inflict 2 + L, sub-types add their
    /// conditions, and the trap is removed. Returns false if the figure died.
    @MainActor func springTrap(at hex: HexCoord, on pieceID: PieceID) async -> Bool {
        guard let gameManager, let cell = boardState.cells[hex], cell.isTrap else { return true }
        // Neutralizer: a trap sprung on a character's (or their summon's) turn is theirs.
        if let character = creditedCharacter(for: actingPiece) {
            gameManager.scenarioStatsManager.recordTrap(by: character.name)
        }
        let damage = cell.trapDamage ?? gameManager.levelManager.trap()
        let subType = cell.overlaySubType

        boardState.removeTrap(at: hex)
        boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.play(.trap)
        log("\(name(pieceID)) springs a trap and suffers \(damage) damage", category: .damage, trace: subType)

        if await sufferDamageWithMitigation(damage, to: pieceID, source: "a trap") {
            return false
        }
        for condition in Self.trapConditions(for: subType) {
            applyCondition(condition, to: pieceID)
        }
        return isOnBoard(pieceID)
    }

    /// Enter hazardous terrain: damage on entering, the terrain stays. Returns false if the figure died.
    @MainActor func enterHazard(at hex: HexCoord, on pieceID: PieceID) async -> Bool {
        guard let gameManager else { return true }
        let damage = gameManager.levelManager.terrain()
        log("\(name(pieceID)) suffers \(damage) damage from hazardous terrain", category: .damage)
        if await sufferDamageWithMitigation(damage, to: pieceID, source: "hazardous terrain") {
            return false
        }
        return isOnBoard(pieceID)
    }

    /// Conditions a trap applies in addition to its damage, by overlay sub-type.
    static func trapConditions(for subType: String?) -> [ConditionName] {
        switch subType {
        case "poison": return [.poison]
        case "bear": return [.immobilize]
        case "thorns": return [.wound]
        default: return []
        }
    }
}
