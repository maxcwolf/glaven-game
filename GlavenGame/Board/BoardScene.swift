import SpriteKit
import Foundation

/// SpriteKit scene that renders the game board.
class BoardScene: SKScene {

    // MARK: - Layer Nodes

    private let tileLayer = SKNode()
    private let overlayLayer = SKNode()
    private let lootLayer = SKNode()
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

    /// How each figure's token looks (portrait, rim, badge). Set by the coordinator; without it
    /// tokens fall back to `storedAppearances` for characters and plain tokens for the rest.
    var appearanceProvider: ((PieceID) -> PieceAppearance)?
    /// Each figure's current health and conditions, shown on its token.
    var statusProvider: ((PieceID) -> PieceStatus?)?

    /// Board state reference for hit testing.
    weak var boardStateRef: BoardState?
    /// The grid offset the board was drawn with, to turn a tap back into a board hex.
    private(set) var offsetCol = 0
    private(set) var offsetRow = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.12, green: 0.1, blue: 0.09, alpha: 1.0)

        addChild(tileLayer)
        addChild(overlayLayer)
        addChild(lootLayer)
        addChild(pieceLayer)
        addChild(highlightLayer)

        camera = cameraNode
        addChild(cameraNode)

        #if os(iOS)
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))
        #endif
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
        self.offsetCol = offsetCol
        self.offsetRow = offsetRow
        tileLayer.removeAllChildren()
        overlayLayer.removeAllChildren()
        lootLayer.removeAllChildren()
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
            // Traps that have sprung and treasure that has been looted are gone from the board.
            let name = overlay.imageName.lowercased()
            if name.contains("trap") && board.cells[overlayCoord]?.isTrap != true { continue }
            if (name.contains("treasure") || name.contains("coin") || name.contains("chest"))
                && board.cells[overlayCoord]?.overlay != .treasure { continue }
            placeOverlaySprite(overlay: overlay, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        // Place pieces
        self.storedAppearances = characterAppearances
        for (pieceID, coord) in board.piecePositions {
            addPieceSprite(id: pieceID, at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        // Restore loot tokens
        for (coord, _) in board.lootTokens {
            addLootSprite(at: coord, offsetCol: offsetCol, offsetRow: offsetRow)
        }

        // Center camera on the visible board cells
        let centerCol = (board.bounds.minCol + board.bounds.maxCol) / 2 - offsetCol
        let centerRow = (board.bounds.minRow + board.bounds.maxRow) / 2 - offsetRow
        cameraNode.position = hexCenterInScene(col: centerCol, row: centerRow)
    }

    // MARK: - Tile Sprites

    private func placeTileSprite(tile: UniqueTile, offsetCol: Int, offsetRow: Int) {
        let imgOffset = TileImageOffsets.offset(for: tile.ref)

        guard let image = MapImageCache.shared.image(named: "map-tiles/\(tile.ref)") else { return }
        let texture = SKTexture(cgImage: image)
        let imgW = texture.size().width
        let imgH = texture.size().height

        // Cell(0,0)'s center relative to the image's top-left corner (y-down pixel space).
        // imgOffset.left/top are negative: they describe how far the image extends past cell(0,0).
        // e.g. left=-22 means image starts 22px to the LEFT of cell(0,0)'s left edge.
        let cellCenterXFromImageLeft = CGFloat(-imgOffset.left) + HexMath.cellStepX / 2
        let cellCenterYFromImageTop  = CGFloat(-imgOffset.top)  + HexMath.cellSize  / 2

        // SpriteKit anchor is a fraction of sprite size measured from bottom-left (y-up).
        let anchorX = cellCenterXFromImageLeft / imgW
        let anchorY = (imgH - cellCenterYFromImageTop) / imgH

        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(x: anchorX, y: anchorY)
        // Place the anchor point (= cell(0,0)'s center) at cell(0,0)'s center in scene space.
        // Rotation then matches SwiftUI's rotationEffect which also rotates around cell(0,0)'s center.
        sprite.position = hexCenterInScene(col: tile.anchorCol - offsetCol, row: tile.anchorRow - offsetRow)
        sprite.zRotation = -CGFloat(tile.turns) * .pi / 3.0 // negative for SpriteKit's CCW convention
        sprite.zPosition = 0
        tileLayer.addChild(sprite)
    }

    // MARK: - Overlay Sprites

    /// Draw an overlay on every hex it covers. Multi-hex overlays (boulders, tables, logs, wall
    /// sections) ship one image per hex — `obstacle-boulder-3`, `-3-2`, `-3-3` — drawn with the
    /// second piece to the right of the first, so each piece is turned by the direction from the
    /// overlay's first hex to its second.
    private func placeOverlaySprite(overlay: PositionedOverlay, offsetCol: Int, offsetRow: Int) {
        let centers = overlay.cells.map { hexCenterInScene(col: $0.0 - offsetCol, row: $0.1 - offsetRow) }
        guard let first = centers.first else { return }
        var rotation: CGFloat = 0
        if centers.count > 1 {
            rotation = atan2(centers[1].y - first.y, centers[1].x - first.x)
        }
        for (index, cell) in overlay.cells.enumerated() {
            let name = Self.overlayPieceName(overlay.imageName, index: index)
            guard let image = MapImageCache.shared.image(named: "overlays/\(name)") else { continue }
            let texture = Self.overlayTexture(name, image: image)
            let sprite = SKSpriteNode(texture: texture)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            // Scale to cell size
            sprite.setScale(HexMath.cellSize / max(texture.size().width, texture.size().height))
            sprite.position = centers[index]
            sprite.zRotation = rotation
            sprite.zPosition = 1
            sprite.name = "overlay_\(cell.0)_\(cell.1)"
            overlayLayer.addChild(sprite)
        }
    }

    /// The image for one hex of a multi-hex overlay: the base image for the first hex, then the
    /// `-2`, `-3` pieces when the art has them.
    static func overlayPieceName(_ base: String, index: Int) -> String {
        guard index > 0 else { return base }
        let piece = "\(base)-\(index + 1)"
        return MapImageCache.shared.image(named: "overlays/\(piece)") != nil ? piece : base
    }

    private static var overlayTextures: [String: SKTexture] = [:]

    private static func overlayTexture(_ name: String, image: CGImage) -> SKTexture {
        if let cached = overlayTextures[name] { return cached }
        let texture = SKTexture(cgImage: image)
        overlayTextures[name] = texture
        return texture
    }

    /// Names of the overlay sprites drawn on the board (for tests).
    var overlaySpriteNames: [String] {
        overlayLayer.children.compactMap(\.name)
    }

    /// Remove an overlay sprite at a given hex coordinate (e.g., after a trap triggers).
    func removeOverlaySprite(at coord: HexCoord, offsetCol: Int, offsetRow: Int) {
        let name = "overlay_\(coord.col)_\(coord.row)"
        overlayLayer.childNode(withName: name)?.removeFromParent()
    }

    // MARK: - Loot Sprites

    /// Add a loot token sprite at a hex coordinate.
    func addLootSprite(at coord: HexCoord, offsetCol: Int, offsetRow: Int) {
        let center = hexCenterInScene(col: coord.col - offsetCol, row: coord.row - offsetRow)
        let radius: CGFloat = 14

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = SKColor(red: 0.9, green: 0.75, blue: 0.1, alpha: 0.95)
        circle.strokeColor = SKColor(red: 0.6, green: 0.45, blue: 0.0, alpha: 1.0)
        circle.lineWidth = 2
        circle.position = center
        circle.zPosition = 8
        circle.name = "loot_\(coord.col)_\(coord.row)"

        let label = SKLabelNode(text: "g")
        label.fontName = "GermaniaOne-Regular"
        label.fontSize = 14
        label.fontColor = SKColor(red: 0.4, green: 0.25, blue: 0.0, alpha: 1.0)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        circle.addChild(label)

        lootLayer.addChild(circle)
    }

    /// Remove the loot token sprite at a hex coordinate.
    func removeLootSprite(at coord: HexCoord, offsetCol: Int, offsetRow: Int) {
        let name = "loot_\(coord.col)_\(coord.row)"
        lootLayer.childNode(withName: name)?.removeFromParent()
    }

    // MARK: - Piece Sprites

    func addPieceSprite(id: PieceID, at coord: HexCoord, offsetCol: Int = 0, offsetRow: Int = 0) {
        var appearance = appearanceProvider?(id) ?? PieceAppearance.fallback(for: id)
        if appearanceProvider == nil, case .character(let charID) = id, let stored = storedAppearances[charID] {
            appearance.rimColor = stored.color
            appearance.portrait = stored.thumbnail
        }
        if appearanceProvider == nil, boardStateRef?.eliteStandees.contains(id) == true {
            appearance.rank = .elite
            appearance.rimColor = PieceAppearance.eliteRim
        }
        pieceNodes[id]?.removeFromParent()
        let pieceNode = PieceSpriteNode(pieceID: id, appearance: appearance)
        pieceNode.position = hexCenterInScene(col: coord.col - offsetCol, row: coord.row - offsetRow)
        pieceNode.zPosition = 10
        pieceLayer.addChild(pieceNode)
        pieceNodes[id] = pieceNode
        refreshStatus(of: id)
    }

    /// The token for a piece on the board.
    func pieceNode(for id: PieceID) -> PieceSpriteNode? {
        pieceNodes[id]
    }

    /// Show a piece's health and conditions on its token.
    func updatePieceStatus(id: PieceID, status: PieceStatus) {
        pieceNodes[id]?.apply(status: status)
    }

    /// Bring one token up to date from `statusProvider`.
    func refreshStatus(of id: PieceID) {
        guard let node = pieceNodes[id], let status = statusProvider?(id) else { return }
        node.apply(status: status)
    }

    /// Bring every token up to date from `statusProvider`.
    func refreshAllStatuses() {
        for id in pieceNodes.keys.sorted() { refreshStatus(of: id) }
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

    /// Show a gold/loot pickup floating up from a piece.
    func pieceLoot(id: PieceID, text: String) {
        guard let node = pieceNodes[id] else { return }
        node.animateLoot(text: text)
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

    /// Handle a tap/click. The tap is resolved to the hex it falls in (nearest hex centre, so a
    /// tap near an edge can't pick the neighbour): the figure standing there if there is one,
    /// otherwise the hex if it is highlighted. Returns true if handled.
    @discardableResult
    func handleTap(at location: CGPoint) -> Bool {
        let hex = Self.hex(at: location, offsetCol: offsetCol, offsetRow: offsetRow)
        if let piece = boardStateRef?.piecePositions.first(where: { $0.value == hex })?.key {
            onPieceTap?(piece)
            return true
        }
        if highlightNodes[hex] != nil {
            onHexTap?(hex)
            return true
        }
        return false
    }

    /// The board hex whose centre is nearest to a point in scene space.
    static func hex(at point: CGPoint, offsetCol: Int, offsetRow: Int) -> HexCoord {
        // Local (offset-free) grid: centre of (c, r) is hexToPixel + half a cell, with y flipped.
        let localY = -point.y - HexMath.cellSize / 2
        let approxRow = Int((localY / HexMath.cellStepY).rounded())
        var best = HexCoord(0, 0)
        var bestDistance = CGFloat.infinity
        for row in (approxRow - 1)...(approxRow + 1) {
            let shift: CGFloat = row & 1 == 1 ? HexMath.cellStepX / 2 : 0
            let approxCol = Int(((point.x - HexMath.cellStepX / 2 - shift) / HexMath.cellStepX).rounded())
            for col in (approxCol - 1)...(approxCol + 1) {
                let p = HexMath.hexToPixel(col: col, row: row)
                let center = CGPoint(x: p.x + HexMath.cellStepX / 2, y: -(p.y + HexMath.cellSize / 2))
                let distance = hypot(point.x - center.x, point.y - center.y)
                if distance < bestDistance {
                    bestDistance = distance
                    best = HexCoord(col + offsetCol, row + offsetRow)
                }
            }
        }
        return best
    }

    /// The centre of a board hex in scene space.
    func sceneCenter(of hex: HexCoord) -> CGPoint {
        hexCenterInScene(col: hex.col - offsetCol, row: hex.row - offsetRow)
    }

    private func pan(to location: CGPoint) {
        if let last = lastPanPoint {
            cameraNode.position = CGPoint(
                x: cameraNode.position.x - (location.x - last.x),
                y: cameraNode.position.y - (location.y - last.y)
            )
        }
    }

    private func zoom(by delta: CGFloat) {
        currentZoom = max(minZoom, min(maxZoom, currentZoom + delta))
        cameraNode.setScale(1.0 / currentZoom)
    }

    #if os(macOS)
    /// Where the click started (in view points) and whether it has turned into a drag, so a
    /// pan that starts on a highlighted hex doesn't also move the character there.
    private var clickStart: CGPoint?
    private var clickDragged = false

    override func mouseDown(with event: NSEvent) {
        clickStart = event.locationInWindow
        clickDragged = false
        lastPanPoint = event.location(in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        if let start = clickStart, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 6 {
            clickDragged = true
        }
        guard clickDragged else { return }
        pan(to: event.location(in: self))
        lastPanPoint = event.location(in: self)
    }

    override func mouseUp(with event: NSEvent) {
        if clickStart != nil, !clickDragged {
            handleTap(at: event.location(in: self))
        }
        clickStart = nil
        lastPanPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        zoom(by: event.deltaY * 0.05)
    }
    #else
    /// Where the current touch started, to tell a tap from a pan. The threshold is measured in
    /// screen points, so it doesn't change with zoom.
    private var touchStart: CGPoint?
    private var touchStartInView: CGPoint?
    private var touchMoved = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        touchStart = location
        touchStartInView = touch.location(in: view)
        lastPanPoint = location
        touchMoved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        // A second finger means a pinch: don't pan or tap.
        if (event?.allTouches?.count ?? 1) > 1 { touchMoved = true; return }
        let location = touch.location(in: self)
        let inView = touch.location(in: view)
        if let start = touchStartInView, hypot(inView.x - start.x, inView.y - start.y) > 8 {
            touchMoved = true
        }
        if touchMoved {
            pan(to: location)
            lastPanPoint = touch.location(in: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !touchMoved, let start = touchStart {
            handleTap(at: start)
        }
        touchStart = nil
        lastPanPoint = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
        lastPanPoint = nil
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        zoom(by: (recognizer.scale - 1) * 0.5)
        recognizer.scale = 1
    }
    #endif

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

        // This tile's anchor point is cell(0,0) of the tile's local grid — matches ScenarioMapSheet.
        let rotated = HexMath.normaliseAndRotatePoint(
            turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: (0, 0)
        )
        let anchorCol = rotated.0
        let anchorRow = rotated.1

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
