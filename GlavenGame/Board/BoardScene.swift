import SpriteKit
import Foundation

/// SpriteKit scene that renders the game board.
class BoardScene: SKScene {

    // MARK: - Layer Nodes

    private let tileLayer = SKNode()
    private let overlayLayer = SKNode()
    private let pieceLayer = SKNode()
    private let highlightLayer = SKNode()

    /// Callback when a hex is clicked.
    var onHexTap: ((HexCoord) -> Void)?
    /// Callback when a piece is clicked.
    var onPieceTap: ((PieceID) -> Void)?

    /// Camera node for pan/zoom.
    private let cameraNode = SKCameraNode()
    private var lastPanPoint: CGPoint?
    private var currentZoom: CGFloat = 1.0
    private let minZoom: CGFloat = 0.3
    private let maxZoom: CGFloat = 3.0

    /// Map from piece ID to its sprite node.
    private var pieceNodes: [PieceID: PieceSpriteNode] = [:]

    /// Map from hex coord to highlight node.
    private var highlightNodes: [HexCoord: SKShapeNode] = [:]

    /// Cached character appearances for piece creation.
    var storedAppearances: [String: CharacterAppearance] = [:]

    /// Board state reference for hit testing.
    weak var boardStateRef: BoardState?

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.12, green: 0.1, blue: 0.09, alpha: 1.0)

        addChild(tileLayer)
        addChild(overlayLayer)
        addChild(pieceLayer)
        addChild(highlightLayer)

        camera = cameraNode
        addChild(cameraNode)
    }

    // MARK: - Board Building

    /// Character appearance data for rendering.
    struct CharacterAppearance {
        let color: SKColor
        let thumbnail: PlatformImage?
    }

    /// Build the visual board from a BoardState.
    /// `offsetCol`/`offsetRow` must match the coordinator's values for consistent positioning.
    func buildBoard(from board: BoardState, scenario: VGBScenario, offsetCol: Int, offsetRow: Int,
                    characterAppearances: [String: CharacterAppearance] = [:]) {
        boardStateRef = board
        tileLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        pieceLayer.removeAllChildren()
        highlightLayer.removeAllChildren()
        pieceNodes.removeAll()
        highlightNodes.removeAll()

        // Collect all tile data from the scenario tree
        let uniqueTiles = collectUniqueTiles(from: scenario.mapTileData)

        // Place tile images — only for visible rooms
        for tile in uniqueTiles {
            guard board.visibleRooms.contains(tile.ref) else { continue }
            placeTileSprite(tile: tile, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        // Place overlay sprites — only for hexes that exist in the board state (visible rooms)
        let result = ScenarioMapBuilder.build(from: scenario)
        let visibleCoords = Set(board.cells.keys)
        for overlay in result.overlays {
            let overlayCoord = HexCoord(overlay.col, overlay.row)
            guard visibleCoords.contains(overlayCoord) else { continue }
            placeOverlaySprite(overlay: overlay, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        // Place pieces
        self.storedAppearances = characterAppearances
        for (pieceID, coord) in board.piecePositions {
            addPieceSprite(id: pieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
            // Apply elite styling
            if board.eliteStandees.contains(pieceID), let node = pieceNodes[pieceID] {
                node.setElite(true)
            }
        }

        // Center camera on the visible board cells
        let centerCol = (board.bounds.minCol + board.bounds.maxCol) / 2 - offsetCol
        let centerRow = (board.bounds.minRow + board.bounds.maxRow) / 2 - offsetRow
        cameraNode.position = hexCenterInScene(col: centerCol, row: centerRow)
    }

    // MARK: - Tile Sprites

    private func placeTileSprite(tile: UniqueTile, offsetCol: Int, offsetRow: Int) {
        let pos = HexMath.hexToPixel(col: tile.anchorCol - offsetCol, row: tile.anchorRow - offsetRow)
        let imgOffset = TileImageOffsets.offset(for: tile.ref)

        guard let image = MapImageCache.shared.image(named: "map-tiles/\(tile.ref)") else { return }
        let texture = SKTexture(cgImage: image)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(x: 0, y: 1) // top-left anchor like SwiftUI
        sprite.position = CGPoint(
            x: pos.x + CGFloat(imgOffset.left),
            y: -pos.y - CGFloat(imgOffset.top) // flip Y for SpriteKit
        )
        sprite.zRotation = -CGFloat(tile.turns) * .pi / 3.0 // negative for SpriteKit's CCW rotation
        sprite.zPosition = 0
        tileLayer.addChild(sprite)
    }

    // MARK: - Overlay Sprites

    private func placeOverlaySprite(overlay: PositionedOverlay, offsetCol: Int, offsetRow: Int) {
        guard let image = MapImageCache.shared.image(named: "overlays/\(overlay.imageName)") else { return }
        let texture = SKTexture(cgImage: image)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        // Scale to cell size
        let scale = HexMath.cellSize / max(texture.size().width, texture.size().height)
        sprite.setScale(scale)
        sprite.position = hexCenterInScene(col: overlay.col - offsetCol, row: overlay.row - offsetRow)
        sprite.zPosition = 1
        sprite.name = "overlay_\(overlay.col)_\(overlay.row)"
        overlayLayer.addChild(sprite)
    }

    /// Remove an overlay sprite at a given hex coordinate (e.g., after a trap triggers).
    func removeOverlaySprite(at coord: HexCoord, offsetCol: Int, offsetRow: Int) {
        let name = "overlay_\(coord.col)_\(coord.row)"
        overlayLayer.childNode(withName: name)?.removeFromParent()
    }

    // MARK: - Piece Sprites

    func addPieceSprite(id: PieceID, at coord: HexCoord, offsetCol: Int = 0, offsetRow: Int = 0) {
        var charColor: SKColor? = nil
        var thumbnail: PlatformImage? = nil
        if case .character(let charID) = id, let appearance = storedAppearances[charID] {
            charColor = appearance.color
            thumbnail = appearance.thumbnail
        }
        let pieceNode = PieceSpriteNode(pieceID: id, characterColor: charColor, thumbnailImage: thumbnail)
        pieceNode.position = hexCenterInScene(col: coord.col - offsetCol, row: coord.row - offsetRow)
        pieceNode.zPosition = 10
        pieceLayer.addChild(pieceNode)
        pieceNodes[id] = pieceNode
    }

    func removePieceSprite(id: PieceID) {
        if let node = pieceNodes[id] {
            node.animateDeath {
                node.removeFromParent()
            }
        }
        pieceNodes.removeValue(forKey: id)
    }

    /// Set a piece's alpha (e.g., for invisible condition translucency).
    func setPieceAlpha(id: PieceID, invisible: Bool) {
        guard let node = pieceNodes[id] else { return }
        node.setInvisible(invisible)
    }

    /// Show a damage number floating up from a piece.
    func pieceDamage(id: PieceID, amount: Int) {
        guard let node = pieceNodes[id] else { return }
        node.animateDamage(amount: amount)
    }

    /// Animate a piece moving along a path.
    func movePiece(id: PieceID, along path: [HexCoord], offsetCol: Int = 0, offsetRow: Int = 0, completion: @escaping () -> Void) {
        guard let node = pieceNodes[id], path.count > 1 else {
            completion()
            return
        }

        var actions: [SKAction] = []
        for hex in path.dropFirst() {
            let target = hexCenterInScene(col: hex.col - offsetCol, row: hex.row - offsetRow)
            actions.append(SKAction.move(to: target, duration: 0.2))
        }

        node.run(SKAction.sequence(actions)) {
            completion()
        }
    }

    // MARK: - Highlights

    /// Show colored highlights on hexes.
    func highlightHexes(_ hexes: Set<HexCoord>, color: SKColor, offsetCol: Int = 0, offsetRow: Int = 0) {
        clearHighlights()

        for hex in hexes {
            let center = hexCenterInScene(col: hex.col - offsetCol, row: hex.row - offsetRow)

            let path = hexPath(radius: HexMath.cellSize / 2.1)
            let shape = SKShapeNode(path: path)
            shape.fillColor = color.withAlphaComponent(0.3)
            shape.strokeColor = color.withAlphaComponent(0.6)
            shape.lineWidth = 2
            shape.position = center
            shape.zPosition = 5
            highlightLayer.addChild(shape)
            highlightNodes[hex] = shape
        }
    }

    /// Clear all hex highlights.
    func clearHighlights() {
        highlightLayer.removeAllChildren()
        highlightNodes.removeAll()
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        let location = event.location(in: self)

        // Check piece hit first
        let pieceHits = pieceLayer.nodes(at: location)
        if let pieceNode = pieceHits.first(where: { $0 is PieceSpriteNode }) as? PieceSpriteNode {
            onPieceTap?(pieceNode.pieceID)
            return
        }

        // Check highlight hit (for hex taps during move/attack selection)
        let highlightHits = highlightLayer.nodes(at: location)
        if !highlightHits.isEmpty {
            // Find which hex coordinate was tapped
            for (coord, node) in highlightNodes {
                if highlightHits.contains(where: { $0 === node }) {
                    onHexTap?(coord)
                    return
                }
            }
        }

        // Otherwise, start panning
        lastPanPoint = location
    }

    override func mouseDragged(with event: NSEvent) {
        let location = event.location(in: self)
        if let last = lastPanPoint {
            let delta = CGPoint(x: location.x - last.x, y: location.y - last.y)
            cameraNode.position = CGPoint(
                x: cameraNode.position.x - delta.x,
                y: cameraNode.position.y - delta.y
            )
        }
        lastPanPoint = location
    }

    override func mouseUp(with event: NSEvent) {
        lastPanPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let zoomDelta = event.deltaY * 0.05
        currentZoom = max(minZoom, min(maxZoom, currentZoom + zoomDelta))
        cameraNode.setScale(1.0 / currentZoom)
    }

    // MARK: - Geometry Helpers

    /// Convert a hex coordinate (with offset applied) to the pixel center in SpriteKit space.
    /// hexToPixel gives the top-left of the cell's bounding box; the center is at
    /// (cellStepX/2, cellSize/2) from there (cellSize/2, not cellStepY/2, because
    /// pointy-top hex rows interleave — the hex height (90) exceeds the row step (67)).
    private func hexCenterInScene(col: Int, row: Int) -> CGPoint {
        let pos = HexMath.hexToPixel(col: col, row: row)
        return CGPoint(
            x: pos.x + HexMath.cellStepX / 2,
            y: -(pos.y + HexMath.cellSize / 2)
        )
    }

    /// Create a pointy-top hexagon path.
    /// The coordinate system uses pointy-top hexes (odd-row offset, cellStepX=76, cellStepY=67).
    private func hexPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3.0 + .pi / 6.0 // +30° for pointy-top orientation
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Tile Collection (mirrors ScenarioMapSheet logic)

    private func collectUniqueTiles(from mapTileData: VGBMapTileData) -> [UniqueTile] {
        var tiles: [UniqueTile] = []
        collectUniqueTilesRecursive(mapTileData, turnAxis: nil, tiles: &tiles)
        return tiles
    }

    private func collectUniqueTilesRecursive(
        _ data: VGBMapTileData,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?,
        tiles: inout [UniqueTile]
    ) {
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        // This tile's anchor point (first passable cell)
        let grid = TileGrids.grid(for: data.ref)
        var anchorCol = 0
        var anchorRow = 0
        outer: for (y, row) in grid.enumerated() {
            for (x, passable) in row.enumerated() {
                if passable {
                    let rotated = HexMath.normaliseAndRotatePoint(
                        turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: (x, y)
                    )
                    anchorCol = rotated.0
                    anchorRow = rotated.1
                    break outer
                }
            }
        }

        let tileID = "\(data.ref)-\(anchorCol)-\(anchorRow)"
        tiles.append(UniqueTile(id: tileID, ref: data.ref, anchorCol: anchorCol, anchorRow: anchorRow, turns: data.turns))

        // Recurse through doors
        for door in data.doors {
            let r = (door.room1X, door.room1Y)
            let doorRefPoint = HexMath.normaliseAndRotatePoint(
                turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: r
            )
            let doorOrigin = (door.room2X, door.room2Y)
            collectUniqueTilesRecursive(
                door.mapTileData,
                turnAxis: (refPoint: doorRefPoint, origin: doorOrigin),
                tiles: &tiles
            )
        }
    }
}
