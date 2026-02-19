import Foundation

/// A positioned map tile in global hex space.
struct PositionedTile {
    let ref: String
    let col: Int
    let row: Int
    let turns: Int
}

/// A positioned overlay in global hex space.
struct PositionedOverlay {
    let imageName: String
    let col: Int
    let row: Int
    let direction: String
    let cells: [(Int, Int)]
}

/// Bounding box of all tiles in hex coordinates.
struct MapBounds: Codable {
    var minCol: Int
    var maxCol: Int
    var minRow: Int
    var maxRow: Int

    static let zero = MapBounds(minCol: 0, maxCol: 0, minRow: 0, maxRow: 0)

    mutating func expand(col: Int, row: Int) {
        minCol = min(minCol, col)
        maxCol = max(maxCol, col)
        minRow = min(minRow, row)
        maxRow = max(maxRow, row)
    }
}

/// Flattens VGB's recursive map tile data into positioned tiles and overlays.
/// Ported from VGB's Scenario.elm `mapTileDataToList` and `mapTileDataToOverlayList`.
enum ScenarioMapBuilder {

    struct Result {
        let tiles: [PositionedTile]
        let overlays: [PositionedOverlay]
        let bounds: MapBounds
    }

    static func build(from scenario: VGBScenario) -> Result {
        let (tiles, bounds) = mapTileDataToList(scenario.mapTileData, turnAxis: nil)
        let overlaysByRoom = mapTileDataToOverlayList(scenario.mapTileData)
        let positioned = positionOverlays(overlaysByRoom, mapTileData: scenario.mapTileData, turnAxis: nil)
        return Result(tiles: tiles, overlays: positioned, bounds: bounds)
    }

    // MARK: - Tile Flattening

    private static func mapTileDataToList(
        _ data: VGBMapTileData,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?
    ) -> ([PositionedTile], MapBounds) {
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        // Get cells from this tile's grid
        let grid = TileGrids.grid(for: data.ref)
        var mapTiles: [PositionedTile] = []
        for (y, row) in grid.enumerated() {
            for (x, passable) in row.enumerated() {
                if !passable { continue }
                let rotated = HexMath.normaliseAndRotatePoint(
                    turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: (x, y)
                )
                mapTiles.append(PositionedTile(ref: data.ref, col: rotated.0, row: rotated.1, turns: data.turns))
            }
        }

        // Also add cells from overlay positions (they may extend the tile footprint)
        for overlay in data.overlays {
            for cell in overlay.cells {
                guard cell.count >= 2 else { continue }
                let rotated = HexMath.normaliseAndRotatePoint(
                    turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: (cell[0], cell[1])
                )
                mapTiles.append(PositionedTile(ref: data.ref, col: rotated.0, row: rotated.1, turns: data.turns))
            }
        }

        // Process door connections recursively
        var doorTiles: [PositionedTile] = []
        for door in data.doors {
            let r = (door.room1X, door.room1Y)
            let doorRefPoint = HexMath.normaliseAndRotatePoint(
                turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: r
            )
            // The door tile itself belongs to the parent tile
            doorTiles.append(PositionedTile(ref: data.ref, col: doorRefPoint.0, row: doorRefPoint.1, turns: data.turns))

            let doorOrigin = (door.room2X, door.room2Y)
            let (childTiles, _) = mapTileDataToList(
                door.mapTileData,
                turnAxis: (refPoint: doorRefPoint, origin: doorOrigin)
            )
            doorTiles.append(contentsOf: childTiles)
        }

        let allTiles = mapTiles + doorTiles

        // Compute bounding box
        var bounds = MapBounds.zero
        for tile in allTiles {
            bounds.expand(col: tile.col, row: tile.row)
        }

        return (allTiles, bounds)
    }

    // MARK: - Overlay Collection

    /// Collect overlays keyed by tile ref, including door overlays.
    private static func mapTileDataToOverlayList(
        _ data: VGBMapTileData
    ) -> [(ref: String, overlays: [VGBOverlay], doors: [VGBDoor])] {
        var result: [(ref: String, overlays: [VGBOverlay], doors: [VGBDoor])] = []
        result.append((ref: data.ref, overlays: data.overlays, doors: data.doors))
        for door in data.doors {
            result.append(contentsOf: mapTileDataToOverlayList(door.mapTileData))
        }
        return result
    }

    /// Position overlays in global hex space by walking the same tree as tile flattening.
    private static func positionOverlays(
        _ overlaysByRoom: [(ref: String, overlays: [VGBOverlay], doors: [VGBDoor])],
        mapTileData: VGBMapTileData,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?
    ) -> [PositionedOverlay] {
        var result: [PositionedOverlay] = []
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        // Position this room's overlays
        for overlay in mapTileData.overlays {
            let imageName = overlayImageName(for: overlay)
            guard !imageName.isEmpty else { continue }
            var positionedCells: [(Int, Int)] = []
            for cell in overlay.cells {
                guard cell.count >= 2 else { continue }
                let rotated = HexMath.normaliseAndRotatePoint(
                    turns: mapTileData.turns, refPoint: refPoint, origin: origin, tileCoord: (cell[0], cell[1])
                )
                positionedCells.append(rotated)
            }
            if let first = positionedCells.first {
                result.append(PositionedOverlay(
                    imageName: imageName,
                    col: first.0,
                    row: first.1,
                    direction: overlay.direction,
                    cells: positionedCells
                ))
            }
        }

        // Position door overlays and recurse
        for door in mapTileData.doors {
            let r = (door.room1X, door.room1Y)
            let doorRefPoint = HexMath.normaliseAndRotatePoint(
                turns: mapTileData.turns, refPoint: refPoint, origin: origin, tileCoord: r
            )

            // The door itself is an overlay
            let doorImageName = doorOverlayImageName(subType: door.subType, direction: door.direction)
            if !doorImageName.isEmpty {
                result.append(PositionedOverlay(
                    imageName: doorImageName,
                    col: doorRefPoint.0,
                    row: doorRefPoint.1,
                    direction: door.direction,
                    cells: [doorRefPoint]
                ))
            }

            let doorOrigin = (door.room2X, door.room2Y)
            result.append(contentsOf: positionOverlays(
                overlaysByRoom,
                mapTileData: door.mapTileData,
                turnAxis: (refPoint: doorRefPoint, origin: doorOrigin)
            ))
        }

        return result
    }

    // MARK: - Overlay Image Names

    /// Build the overlay image filename from the overlay ref data.
    private static func overlayImageName(for overlay: VGBOverlay) -> String {
        let ref = overlay.ref
        switch ref.type {
        case "starting-location":
            return "" // Don't render starting locations
        case "door":
            return doorOverlayImageName(subType: ref.subType ?? "stone", direction: overlay.direction)
        case "obstacle":
            return "obstacle-\(ref.subType ?? "")"
        case "trap":
            return "trap-\(ref.subType ?? "")"
        case "hazard":
            return "hazard-\(ref.subType ?? "")"
        case "difficult-terrain":
            let base = "difficult-terrain-\(ref.subType ?? "")"
            if ref.subType == "stairs" && (overlay.direction == "vertical" || overlay.direction == "vertical-reverse") {
                return "difficult-terrain-stairs-vert"
            }
            return base
        case "treasure":
            if ref.subType == "coin" { return "treasure-coin" }
            return "treasure-chest"
        case "token":
            return "" // Skip tokens for V1
        case "wall":
            return "wall-\(ref.subType ?? "")"
        case "rift":
            return "rift"
        default:
            return ""
        }
    }

    private static func doorOverlayImageName(subType: String, direction: String) -> String {
        let baseName: String
        switch subType {
        case "stone": baseName = "door-stone"
        case "wooden": baseName = "door-wooden"
        case "dark-fog", "darkFog": baseName = "door-dark-fog"
        case "light-fog", "lightFog": baseName = "door-light-fog"
        case "breakable-wall", "breakableWall": baseName = "door-breakable-wall"
        case "altar", "altarDoor": baseName = "door-altar"
        default:
            // Corridor types
            if subType.hasPrefix("corridor") { return subType }
            return "door-stone"
        }

        if direction == "vertical" || direction == "vertical-reverse" {
            switch baseName {
            case "door-stone", "door-wooden", "door-breakable-wall":
                return baseName + "-vert"
            default:
                return baseName
            }
        }
        return baseName
    }
}
