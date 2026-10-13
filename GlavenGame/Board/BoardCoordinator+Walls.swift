import Foundation

/// Walls broken down by damage (`ScenarioPlacements.walls`, Harrower Hive): every
/// `breakable-wall` connector of the map is shut to everyone, and the objective standing on it
/// is its hit points. Characters attack it like an enemy; destroyed, it becomes a corridor, the
/// rooms beside it are revealed and the enemies beside it gain the scenario's condition.
extension BoardCoordinator {

    var wallRule: ScenarioPlacements.Walls? { scenarioData?.placements?.walls }

    /// The hexes of the walls not yet broken down.
    var standingWalls: Set<HexCoord> {
        guard wallRule != nil else { return [] }
        return Set(boardState.doors.filter { !$0.isOpen && $0.subType == BoardBuilder.breakableWallSubType }.map(\.coord))
    }

    /// Give each wall the map has just shown its hit points — a place for the objective and one
    /// more of it — and shut it: no one opens a wall by walking into it.
    func raiseWalls() {
        guard let rule = wallRule, let gameManager else { return }
        let walls = standingWalls
        for hex in walls.sorted()
        where !boardState.openObjectiveSlots.contains(where: { $0.coord == hex })
            && !boardState.objectiveSites.values.contains(where: { $0.coord == hex }) {
            boardState.openObjectiveSlots.append(ObjectiveSlot(objective: rule.objective, coord: hex, cells: [hex], barsDoor: true))
        }
        // (The scenario sets one up by itself, as it does any objective no room lists.)
        let places = boardState.openObjectiveSlots.filter { $0.objective == rule.objective }.count
        let waiting = unplacedObjectiveEntities().filter { $0.0.objectiveIndex == rule.objective }.count
        for _ in 0..<max(0, places - waiting) { gameManager.scenarioManager.addObjective(rule.objective) }
        boardState.lockedDoors.formUnion(walls)
    }

    /// "When any wall is destroyed, the room or rooms on the other side are revealed …
    /// Additionally, when any wall is destroyed, all enemies adjacent to it gain STUN." The wall's
    /// own connector has opened; at the corner of three tiles the third is revealed too.
    func wallComesDown(at hex: HexCoord) {
        guard let rule = wallRule, let scenario = scenarioData else { return }
        for ref in BoardBuilder.tiles(touching: hex, in: scenario).sorted()
        where !boardState.visibleRooms.contains(where: { $0.lowercased() == ref }) {
            let ways = boardState.doors.filter { !$0.isOpen && $0.childTileRef.lowercased() == ref }
            guard let way = ways.min(by: { $0.coord < $1.coord }) else { continue }
            revealRoom(behind: way, opening: false)
        }
        guard let condition = rule.condition.flatMap(ConditionName.init(rawValue:)) else { return }
        for piece in boardState.neighbors(of: hex).sorted().compactMap({ boardState.piece(at: $0) }) {
            guard case .monster = piece, side(of: piece) != .party, !isInactive(piece) else { continue }
            applyCondition(condition, to: piece)
        }
    }

    /// "Reveal all rooms": every room of the scenario is on the map, whichever walls still stand.
    var everyRoomIsRevealed: Bool {
        guard let scenario = gameManager?.game.scenario else { return false }
        return (scenario.data.rooms ?? []).allSatisfy { scenario.revealedRooms.contains($0.roomNumber) }
    }

    /// A wall broken down, or one a rule opened, is a corridor from then on: drawn as one.
    func layCorridor(at hex: HexCoord) {
        boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.addOverlaySprite(imageName: BoardScene.corridorOverBrokenWall, at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
    }
}
