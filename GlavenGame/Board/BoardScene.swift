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
    /// Floating numbers, attack lines and other short-lived effects, above every piece. Effects
    /// live here rather than on the piece, so a killing blow's number outlives the piece.
    private let effectsLayer = SKNode()
    /// The ring under the figure whose turn it is.
    private let actingRing = SKShapeNode(circleOfRadius: HexMath.cellStepX * 0.48)

    /// Callback when a hex is clicked.
    var onHexTap: ((HexCoord) -> Void)?
    /// Callback when a piece is clicked.
    var onPieceTap: ((PieceID) -> Void)?

    /// Camera node for pan/zoom.
    private let cameraNode = SKCameraNode()
    private var lastPanPoint: CGPoint?
    /// The board's extent in scene units (every revealed hex), which the camera frames and
    /// keeps in view.
    private(set) var boardContentRect: CGRect = .null
    /// The centre of every revealed hex, so the camera never ends up over empty floor.
    private var hexCenters: [CGPoint] = []
    /// The HUD's panels over the board (view points, y down); the board is framed around them.
    private(set) var hudObstacles: [CGRect] = []
    private var hudReported = false
    /// The board still needs framing once the view and the HUD's insets are known.
    private var framingPending = true
    /// The player has panned or zoomed since the board was last framed.
    private(set) var userMovedCamera = false

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

    override init(size: CGSize) {
        super.init(size: size)
        setUpLayers()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setUpLayers()
    }

    /// Build the layer tree once, when the scene is created. (Doing it in `didMove(to:)` added
    /// everything again each time the scene was shown, and SpriteKit throws on that.)
    private func setUpLayers() {
        backgroundColor = SKColor(red: 0.12, green: 0.1, blue: 0.09, alpha: 1.0)
        for layer in [tileLayer, overlayLayer, lootLayer, pieceLayer, highlightLayer, effectsLayer] {
            addChild(layer)
        }
        effectsLayer.zPosition = 30
        // Gold on a dark band, so the ring reads on warm floors as well as dark ones.
        actingRing.strokeColor = SKColor(red: 0.98, green: 0.80, blue: 0.30, alpha: 1)
        actingRing.lineWidth = 4
        actingRing.glowWidth = 2
        actingRing.fillColor = .clear
        actingRing.zPosition = 9
        let band = SKShapeNode(circleOfRadius: HexMath.cellStepX * 0.48)
        band.strokeColor = SKColor(white: 0, alpha: 0.75)
        band.lineWidth = 10
        band.fillColor = .clear
        band.zPosition = -0.1
        actingRing.addChild(band)
        actingRing.isHidden = true
        pieceLayer.addChild(actingRing)
        camera = cameraNode
        addChild(cameraNode)
    }

    #if os(iOS)
    private var pinchRecognizer: UIPinchGestureRecognizer?
    #endif

    override func didMove(to view: SKView) {
        #if os(iOS)
        if pinchRecognizer == nil {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinch)
            pinchRecognizer = pinch
        }
        #endif
        if framingPending { fitCamera() }
        frameIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard !boardContentRect.isNull, size != oldSize else { return }
        // A rotation or resize reframes the board unless the player has set their own view.
        if userMovedCamera { cameraState = clamped(cameraState) }
        else { fitCamera() }
    }

    override func willMove(from view: SKView) {
        #if os(iOS)
        if let pinch = pinchRecognizer {
            view.removeGestureRecognizer(pinch)
            pinchRecognizer = nil
        }
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
        if actingRing.parent == nil { pieceLayer.addChild(actingRing) }
        highlightLayer.removeAllChildren()
        effectsLayer.removeAllChildren()
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

        // Frame a new board; a rebuilt one (undo, a revealed room) keeps the player's view.
        let isFirstBuild = boardContentRect.isNull
        boardContentRect = contentRect(of: board)
        hexCenters = board.cells.keys.sorted().map { sceneCenter(of: $0) }
        if isFirstBuild { fitCamera() } else { cameraState = clamped(cameraState) }
    }

    /// Every revealed hex, edge to edge, in scene units.
    private func contentRect(of board: BoardState) -> CGRect {
        var rect = CGRect.null
        for hex in board.cells.keys {
            let center = sceneCenter(of: hex)
            rect = rect.union(CGRect(x: center.x - HexMath.cellStepX / 2, y: center.y - HexMath.cellSize / 2,
                                     width: HexMath.cellStepX, height: HexMath.cellSize))
        }
        return rect
    }

    // MARK: - Camera

    /// The view the board is seen through: the scene's size (it fills the view) and the HUD.
    var viewport: BoardViewport {
        BoardViewport(size: size, obstacles: hudObstacles,
                      contentSize: boardContentRect.isNull ? nil : boardContentRect.size)
    }

    /// Where the camera looks and how far it's zoomed.
    var cameraState: BoardCamera {
        get { BoardCamera(position: cameraNode.position, scale: cameraNode.xScale) }
        set {
            cameraNode.removeAction(forKey: "camera")
            cameraNode.position = newValue.position
            cameraNode.setScale(newValue.scale)
        }
    }

    /// Move the camera, gliding there when the board is on screen and motion is allowed.
    private func moveCamera(to camera: BoardCamera, animated: Bool) {
        guard camera != cameraState else { return }
        guard animated, !reduceMotion, view != nil else {
            cameraState = camera
            return
        }
        cameraNode.removeAction(forKey: "camera")
        let move = SKAction.move(to: camera.position, duration: 0.35)
        let zoom = SKAction.scale(to: camera.scale, duration: 0.35)
        move.timingMode = .easeInEaseOut
        zoom.timingMode = .easeInEaseOut
        cameraNode.run(.group([move, zoom]), withKey: "camera")
    }

    /// Show the whole board in the part of the view the HUD leaves clear.
    func fitCamera(animated: Bool = false) {
        guard !boardContentRect.isNull else { return }
        userMovedCamera = false
        moveCamera(to: BoardCamera.fitting(boardContentRect, in: viewport), animated: animated)
    }

    /// The HUD's panels moved or resized. The first report frames the board. After that, a
    /// panel that grows over the board reframes it, unless the player has set their own view;
    /// a panel that shrinks doesn't, so the board doesn't zoom in and out every round.
    func setHUDObstacles(_ obstacles: [CGRect]) {
        let changed = obstacles != hudObstacles
        hudObstacles = obstacles
        if !hudReported { hudReported = true; framingPending = true }
        if changed, !framingPending, !userMovedCamera, !boardContentRect.isNull,
           !cameraState.shows(boardContentRect, in: viewport) {
            framingPending = true
        }
        if changed || framingPending { frameIfNeeded() }
    }

    /// Reframe the board when the HUD next changes (after the side panels are shown or hidden).
    func refitWhenHUDChanges() { framingPending = true }

    private func frameIfNeeded() {
        guard framingPending, view != nil, hudReported, !boardContentRect.isNull else { return }
        framingPending = false
        fitCamera(animated: true)
    }

    /// Pan, if needed, so a point (a figure about to act or move) is well inside the clear area.
    /// Leaves the camera alone while the player's finger is on the board.
    func keepInView(_ point: CGPoint) {
        guard lastPanPoint == nil, !boardContentRect.isNull else { return }
        moveCamera(to: cameraState.showing(point, in: viewport), animated: true)
    }

    /// Zoom by `factor` (2 = twice as close) keeping the scene point under `anchor` (a view
    /// point, y down) where it is.
    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        guard factor > 0 else { return }
        userMovedCamera = true
        cameraState = clamped(cameraState.zoomed(to: cameraState.scale / factor, around: anchor, in: viewport))
    }

    /// Pan by a drag of `translation` view points (y down): the board follows the finger.
    func pan(by translation: CGVector) {
        userMovedCamera = true
        var camera = cameraState
        camera.position.x -= translation.dx * camera.scale
        camera.position.y += translation.dy * camera.scale
        cameraState = clamped(camera)
    }

    /// A camera kept on the board: some of it, and at least one hex, in the clear area.
    private func clamped(_ camera: BoardCamera) -> BoardCamera {
        guard !boardContentRect.isNull else { return camera }
        return camera.clamped(to: boardContentRect, hexes: hexCenters, in: viewport)
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

    /// The hexes currently highlighted (for tests).
    var highlightedHexes: Set<HexCoord> { Set(highlightNodes.keys) }

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

    // MARK: - Effects

    enum FloatStyle {
        case damage, heal, gold, info

        var color: SKColor {
            switch self {
            case .damage: return SKColor(red: 1.0, green: 0.36, blue: 0.30, alpha: 1)
            case .heal: return SKColor(red: 0.45, green: 0.86, blue: 0.45, alpha: 1)
            case .gold: return SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
            case .info: return SKColor(white: 0.95, alpha: 1)
            }
        }
    }

    /// A short label rising from a piece: "−3", "+2", "Miss", "Blocked". Outlined so it reads over
    /// any art, and drawn on the effects layer so it stays even if the piece dies.
    func floatText(_ text: String, over id: PieceID, style: FloatStyle) {
        guard let node = pieceNodes[id] else { return }
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: PlatformFont.boldSystemFont(ofSize: style == .damage ? 30 : 22),
            .foregroundColor: style.color,
            .strokeColor: SKColor.black,
            .strokeWidth: -4.0,
        ])
        label.verticalAlignmentMode = .center
        // Several labels at once (an attack and a retaliate) stack instead of overlapping.
        let stacked = effectsLayer.children.filter { ($0.userData?["piece"] as? String) == "\(id)" }.count
        label.position = CGPoint(x: node.position.x, y: node.position.y + HexMath.cellStepX * 0.45 + CGFloat(stacked) * 26)
        label.userData = ["piece": "\(id)"]
        label.setScale(0.6)
        effectsLayer.addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.12), .moveBy(x: 0, y: 8, duration: 0.12)]),
            .moveBy(x: 0, y: 26, duration: 0.7),
            .group([.moveBy(x: 0, y: 10, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent(),
        ]))
    }

    /// Show a damage number floating up from a piece.
    func pieceDamage(id: PieceID, amount: Int) {
        floatText("\u{2212}\(amount)", over: id, style: .damage)
        guard let node = pieceNodes[id] else { return }
        // A short shake so the hit registers even out of the corner of the eye.
        node.run(.sequence([.moveBy(x: 4, y: 0, duration: 0.04), .moveBy(x: -8, y: 0, duration: 0.06),
                            .moveBy(x: 4, y: 0, duration: 0.04)]), withKey: "shake")
    }

    /// Show a gold/loot pickup floating up from a piece.
    func pieceLoot(id: PieceID, text: String) {
        floatText(text, over: id, style: .gold)
    }

    /// Show healing floating up from a piece.
    func pieceHeal(id: PieceID, amount: Int) {
        floatText("+\(amount)", over: id, style: .heal)
    }

    /// Show an attack from one piece to another: a line between them for a moment, and a lunge
    /// toward the target for a melee attack.
    func showAttack(from attacker: PieceID, to target: PieceID, ranged: Bool) {
        guard let from = pieceNodes[attacker], let to = pieceNodes[target] else { return }
        let path = CGMutablePath()
        path.move(to: from.position)
        path.addLine(to: to.position)
        let line = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: ranged ? [10, 7] : [16, 4]))
        line.strokeColor = SKColor(red: 0.89, green: 0.33, blue: 0.29, alpha: 0.9)
        line.lineWidth = 4
        line.lineCap = .round
        line.zPosition = -1
        effectsLayer.addChild(line)
        line.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.25), .removeFromParent()]))

        if !ranged {
            let dx = (to.position.x - from.position.x) * 0.3
            let dy = (to.position.y - from.position.y) * 0.3
            let lunge = SKAction.moveBy(x: dx, y: dy, duration: 0.12)
            lunge.timingMode = .easeOut
            let back = SKAction.moveBy(x: -dx, y: -dy, duration: 0.16)
            back.timingMode = .easeIn
            from.run(.sequence([lunge, back]), withKey: "lunge")
        }
    }

    /// Ring the figure whose turn it is (nil hides the ring).
    func setActingPiece(_ id: PieceID?) {
        actingRing.removeAllActions()
        guard let id, let node = pieceNodes[id] else {
            actingRing.isHidden = true
            return
        }
        actingRing.isHidden = false
        actingRing.position = node.position
        keepInView(node.position)
        actingRing.setScale(1)
        actingRing.alpha = 1
        if !reduceMotion {
            actingRing.run(.repeatForever(.sequence([
                .group([.scale(to: 1.08, duration: 0.7), .fadeAlpha(to: 0.65, duration: 0.7)]),
                .group([.scale(to: 1.0, duration: 0.7), .fadeAlpha(to: 1.0, duration: 0.7)]),
            ])))
        }
        actingPieceID = id
    }

    /// The figure the ring is on (for tests and to follow it as it moves).
    private(set) var actingPieceID: PieceID?

    /// Number of effects currently showing (for tests).
    var activeEffectCount: Int { effectsLayer.children.count }

    /// The floating texts currently showing over a piece, oldest first (for tests).
    func floatingTexts(over id: PieceID) -> [String] {
        effectsLayer.children.compactMap { node in
            guard let label = node as? SKLabelNode, (label.userData?["piece"] as? String) == "\(id)" else { return nil }
            return label.attributedText?.string
        }
    }

    /// Animate a piece moving along a path.
    func movePiece(id: PieceID, along path: [HexCoord], offsetCol: Int = 0, offsetRow: Int = 0, completion: @escaping () -> Void) {
        guard let node = pieceNodes[id], path.count > 1 else {
            completion()
            return
        }

        var actions: [SKAction] = []
        let steps = Array(path.dropFirst())
        for (index, hex) in steps.enumerated() {
            let target = hexCenterInScene(col: hex.col - offsetCol, row: hex.row - offsetRow)
            let step = SKAction.move(to: target, duration: 0.2)
            // Ease into the first step and out of the last, so a move starts and stops naturally.
            if steps.count == 1 { step.timingMode = .easeInEaseOut }
            else if index == 0 { step.timingMode = .easeIn }
            else if index == steps.count - 1 { step.timingMode = .easeOut }
            actions.append(step)
        }

        if actingPieceID == id {
            actingRing.run(SKAction.sequence(actions.map { $0.copy() as! SKAction }), withKey: "follow")
        }
        // Keep the destination on screen as the figure walks there.
        if let last = steps.last {
            keepInView(hexCenterInScene(col: last.col - offsetCol, row: last.row - offsetRow))
        }
        node.run(SKAction.sequence(actions)) {
            completion()
        }
    }

    // MARK: - Highlights

    /// The style of the highlights currently shown (nil when there are none).
    private(set) var highlightStyle: HighlightStyle?

    /// Show highlighted hexes for one kind of choice.
    func highlightHexes(_ hexes: Set<HexCoord>, style: HighlightStyle, offsetCol: Int = 0, offsetRow: Int = 0) {
        clearHighlights()
        highlightStyle = style
        let radius = HexMath.cellSize / 2.1
        let outline = hexPath(radius: radius)
        let color = style.color

        for hex in hexes.sorted() {
            let shape = SKShapeNode(path: outline)
            shape.fillColor = color.withAlphaComponent(0.28)
            shape.strokeColor = color.withAlphaComponent(0.95)
            shape.lineWidth = 3
            shape.position = hexCenterInScene(col: hex.col - offsetCol, row: hex.row - offsetRow)
            shape.zPosition = 5
            shape.name = "highlight-\(style)"

            switch style.cue {
            case .outline:
                break
            case .dashed:
                shape.path = outline.copy(dashingWithPhase: 0, lengths: [9, 6])
                shape.fillColor = .clear
                let fill = SKShapeNode(path: outline)
                fill.fillColor = color.withAlphaComponent(0.22)
                fill.strokeColor = .clear
                shape.addChild(fill)
            case .doubleRing:
                let inner = SKShapeNode(path: hexPath(radius: radius * 0.72))
                inner.strokeColor = color.withAlphaComponent(0.9)
                inner.lineWidth = 2
                inner.fillColor = .clear
                shape.addChild(inner)
            case .reticle:
                let ring = SKShapeNode(circleOfRadius: radius * 0.78)
                ring.strokeColor = color
                ring.lineWidth = 2.5
                ring.fillColor = .clear
                let ticks = CGMutablePath()
                for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 2) {
                    let a = CGFloat(angle)
                    ticks.move(to: CGPoint(x: cos(a) * radius * 0.6, y: sin(a) * radius * 0.6))
                    ticks.addLine(to: CGPoint(x: cos(a) * radius * 0.95, y: sin(a) * radius * 0.95))
                }
                let tickNode = SKShapeNode(path: ticks)
                tickNode.strokeColor = color
                tickNode.lineWidth = 3
                ring.addChild(tickNode)
                ring.zPosition = 15   // above the token so the target is unmistakable
                shape.addChild(ring)
            case .plus:
                let plus = CGMutablePath()
                let arm = radius * 0.32
                plus.move(to: CGPoint(x: -arm, y: radius * 0.55)); plus.addLine(to: CGPoint(x: arm, y: radius * 0.55))
                plus.move(to: CGPoint(x: 0, y: radius * 0.55 - arm)); plus.addLine(to: CGPoint(x: 0, y: radius * 0.55 + arm))
                let plusNode = SKShapeNode(path: plus)
                plusNode.strokeColor = color
                plusNode.lineWidth = 4
                plusNode.zPosition = 15
                shape.addChild(plusNode)
            case .chevron:
                let chevron = CGMutablePath()
                chevron.move(to: CGPoint(x: -radius * 0.25, y: radius * 0.3))
                chevron.addLine(to: CGPoint(x: radius * 0.15, y: 0))
                chevron.addLine(to: CGPoint(x: -radius * 0.25, y: -radius * 0.3))
                let chevronNode = SKShapeNode(path: chevron)
                chevronNode.strokeColor = color
                chevronNode.lineWidth = 4
                shape.addChild(chevronNode)
            case .dot:
                let dot = SKShapeNode(circleOfRadius: 6)
                dot.fillColor = color
                dot.strokeColor = .clear
                shape.addChild(dot)
            }

            // A slow pulse so highlights read over busy map art.
            if !reduceMotion {
                shape.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.8),
                                                    .fadeAlpha(to: 1.0, duration: 0.8)])))
            }
            highlightLayer.addChild(shape)
            highlightNodes[hex] = shape
        }
    }

    /// Set from the accessibility setting; turns off the highlight pulse.
    var reduceMotion = false

    /// Clear all hex highlights.
    func clearHighlights() {
        highlightLayer.removeAllChildren()
        highlightNodes.removeAll()
        highlightStyle = nil
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

    /// Pan from the last drag point to `location` (both in scene space).
    private func pan(to location: CGPoint) {
        guard let last = lastPanPoint else { return }
        let scale = cameraState.scale
        pan(by: CGVector(dx: (location.x - last.x) / scale, dy: -(location.y - last.y) / scale))
    }

    /// The view point (y down) over a scene point.
    private func viewAnchor(of scenePoint: CGPoint) -> CGPoint {
        cameraState.viewPoint(of: scenePoint, in: viewport)
    }

    #if os(macOS)
    /// Where the click started (in view points) and whether it has turned into a drag, so a
    /// pan that starts on a highlighted hex doesn't also move the character there.
    private var clickStart: CGPoint?
    private var clickDragged = false

    override func mouseDown(with event: NSEvent) {
        cameraNode.removeAction(forKey: "camera")
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

    /// A trackpad's two-finger scroll pans; a mouse wheel zooms where the pointer is.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            pan(by: CGVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY))
        } else {
            zoom(by: 1 + event.scrollingDeltaY * 0.05, around: viewAnchor(of: event.location(in: self)))
        }
    }

    /// A trackpad pinch zooms where the pointer is.
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: viewAnchor(of: event.location(in: self)))
    }
    #else
    /// Where the current touch started, to tell a tap from a pan. The threshold is measured in
    /// screen points, so it doesn't change with zoom.
    private var touchStart: CGPoint?
    private var touchStartInView: CGPoint?
    private var touchMoved = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        cameraNode.removeAction(forKey: "camera")
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

    /// Pinch zooms where the fingers are.
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let view else { return }
        let anchor = viewAnchor(of: convertPoint(fromView: recognizer.location(in: view)))
        zoom(by: recognizer.scale, around: anchor)
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
