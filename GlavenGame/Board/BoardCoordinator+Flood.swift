import Foundation

/// Water that rises on a tile as rounds end and is bailed by the characters: the hold of the
/// Merchant Ship (`ScenarioPlacements.Flood`).
extension BoardCoordinator {

    var scenarioFlood: ScenarioPlacements.Flood? { scenarioData?.placements?.flood }

    static let waterArt = "difficult-terrain-water"

    /// The hexes of the tile that fills, in map order: the tile's own, not a doorway or a
    /// corridor hex on its edge (which touches another tile, as no hex of a tile's own does).
    func floodHexes() -> [HexCoord] {
        guard let flood = scenarioFlood else { return [] }
        func onTheTile(_ hex: HexCoord) -> Bool { boardState.cells[hex]?.tileRef.lowercased() == flood.tile }
        let doors = Set(boardState.doors.map(\.coord))
        return boardState.cells.values.filter { $0.overlay != .wall && $0.overlay != .door }.map(\.coord)
            .filter { onTheTile($0) && !doors.contains($0) && boardState.neighbors(of: $0).allSatisfy { boardState.cells[$0] == nil || onTheTile($0) } }.sorted()
    }

    private func isWaterTile(_ hex: HexCoord) -> Bool {
        guard let cell = boardState.cells[hex] else { return false }
        return cell.overlay == .difficultTerrain && cell.overlaySubType == "water"
    }

    /// Whether a water tile of the flood lies on `hex` (one a character can pick up).
    func isFloodWater(_ hex: HexCoord) -> Bool {
        guard scenarioFlood != nil, isWaterTile(hex) else { return false }
        return floodHexes().contains(hex)
    }

    private func setWater(_ hex: HexCoord, _ wet: Bool) {
        boardState.cells[hex]?.overlay = wet ? .difficultTerrain : nil
        boardState.cells[hex]?.overlaySubType = wet ? "water" : nil
        boardState.cells[hex]?.overlayImageName = nil
        boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        if wet { boardScene?.addOverlaySprite(imageName: Self.waterArt, at: hex, offsetCol: offsetCol, offsetRow: offsetRow) }
    }

    /// "Remove water tiles d for three characters", once, as the scenario is set up.
    func setUpTheFlood() {
        guard let flood = scenarioFlood, !boardState.floodSetUp, let gameManager else { return }
        boardState.floodSetUp = true
        guard let dry = flood.dry, gameManager.game.characterCount == dry.characters else { return }
        for hex in (boardState.markerHexes[dry.marker] ?? []).sorted() where isFloodWater(hex) { setWater(hex, false) }
    }

    /// Whether a water tile is to be added as this round ends.
    var waterRisesThisRound: Bool {
        guard let flood = scenarioFlood, let gameManager else { return false }
        let variables = ["R": gameManager.game.round, "C": gameManager.game.characterCount, "L": gameManager.game.level]
        return ScenarioExpression.condition(flood.every, variables: variables) ?? false
    }

    /// Where a water tile may be added: a dry hex of the tile beside a wet one (any dry hex
    /// when the tile has been bailed dry).
    func risingWaterHexes() -> [HexCoord] {
        let hexes = floodHexes()
        let dry = hexes.filter { !isWaterTile($0) && boardState.cells[$0]?.overlay == nil }
        let wet = Set(hexes.filter(isWaterTile))
        guard !wet.isEmpty else { return dry }
        return dry.filter { hex in boardState.neighbors(of: hex).contains(where: wet.contains) }
    }

    /// One water tile is added, where the players say; with the tile full the scenario is lost.
    @MainActor func waterRisesAsTheRoundEnds() async {
        guard let flood = scenarioFlood else { return }
        setUpTheFlood()
        let dry = floodHexes().filter { !isWaterTile($0) }
        guard !dry.isEmpty else {
            pendingResult = .defeat
            endReason = .ruleLost(flood.lost)
            log("The water has nowhere left to rise: the scenario is lost", category: .death)
            return
        }
        let open = risingWaterHexes()
        guard !open.isEmpty else { return }
        let generation = boardGeneration
        let chosen = await chooseHex(open, for: nil, title: "The water rises",
                                     detail: "Tap the hex the water tile is added to") ?? open[0]
        guard isCurrentBoard(generation) else { return }
        setWater(chosen, true)
        let left = floodHexes().filter { !isWaterTile($0) }.count
        log("The water rises [at \(chosen)]: \(left == 0 ? "the hold is full" : "\(left) dry hex\(left == 1 ? "" : "es") left")", category: .info)
    }

    /// A character looting `hex` picks up its water tile, if they hold none.
    func pickUpWater(at hex: HexCoord, by characterID: String) {
        guard isFloodWater(hex), !boardState.waterHeld.contains(characterID) else { return }
        gameManager?.characterManager.onBeforeMutate?()
        boardState.waterHeld.insert(characterID)
        setWater(hex, false)
        log("\(characterName(characterID)) picks up a water tile", category: .loot, trace: "at \(hex)")
    }

    /// A character ending their turn on a bailing hex gets rid of the water tile they hold.
    func bailWater(_ characterID: String) {
        guard let flood = scenarioFlood, boardState.waterHeld.contains(characterID),
              let hex = boardState.piecePositions[.character(characterID)],
              boardState.markerHexes[flood.bail]?.contains(hex) == true else { return }
        boardState.waterHeld.remove(characterID)
        log("\(characterName(characterID)) bails a water tile out of the ship", category: .info)
    }
}
