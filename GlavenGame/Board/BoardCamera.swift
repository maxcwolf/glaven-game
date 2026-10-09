import CoreGraphics

/// The view the board is seen through: its size in points and the HUD panels over it.
struct BoardViewport: Equatable {
    var size: CGSize
    /// The panels over the board, in view points (y down).
    var obstacles: [CGRect] = []
    /// The board's size in scene units, so the clear area chosen is the one that shows it
    /// largest (a wide board prefers a wide gap). Without it, the largest gap by area.
    var contentSize: CGSize?

    /// The panels' frames (in any one coordinate space, y down) relative to the board's frame
    /// in that space, clipped to the board. Empty and off-board panels are dropped.
    static func obstacles(_ frames: [CGRect], over board: CGRect) -> [CGRect] {
        let bounds = CGRect(origin: .zero, size: board.size)
        return frames.compactMap { frame in
            let local = frame.offsetBy(dx: -board.minX, dy: -board.minY).intersection(bounds)
            return local.isNull || local.width < 1 || local.height < 1 ? nil : local
        }
    }

    /// The rectangle no panel covers that shows the board largest (y down); among ties, the
    /// biggest. When the panels leave too little room, the whole view rather than a sliver.
    var clearRect: CGRect {
        let whole = CGRect(origin: .zero, size: size)
        guard !obstacles.isEmpty else { return whole }
        // A largest empty rectangle has each edge on the view's edge or a panel's edge.
        let lefts = Set([0] + obstacles.map(\.maxX)).filter { $0 >= 0 && $0 < size.width }
        let rights = Set([size.width] + obstacles.map(\.minX)).filter { $0 > 0 && $0 <= size.width }
        let tops = Set([0] + obstacles.map(\.maxY)).filter { $0 >= 0 && $0 < size.height }
        let bottoms = Set([size.height] + obstacles.map(\.minY)).filter { $0 > 0 && $0 <= size.height }
        var best = CGRect.zero
        var bestScore = (fit: -CGFloat.infinity, area: -CGFloat.infinity)
        for left in lefts.sorted() {
            for right in rights.sorted() where right > left {
                for top in tops.sorted() {
                    for bottom in bottoms.sorted() where bottom > top {
                        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                        let score = (fit: fitFactor(of: rect), area: rect.width * rect.height)
                        guard score > bestScore else { continue }
                        let blocked = obstacles.contains { panel in
                            let overlap = panel.intersection(rect)
                            return !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5
                        }
                        if !blocked { best = rect; bestScore = score }
                    }
                }
            }
        }
        return best.width < 160 || best.height < 160 ? whole : best
    }

    /// How large the board would show in `rect` (view points per scene unit, at most 1:1).
    private func fitFactor(of rect: CGRect) -> CGFloat {
        guard let content = contentSize, content.width > 0, content.height > 0 else { return 0 }
        return min((rect.width - 48) / content.width, (rect.height - 48) / content.height, 1)
    }
}

/// Where the board camera looks and how far it's zoomed, in scene units. `scale` is SpriteKit's
/// camera scale: scene units per view point, so a larger scale shows more of the board.
struct BoardCamera: Equatable {
    var position: CGPoint
    var scale: CGFloat

    /// Zoomed in 2× at most (a hex is then about the size of a thumb-sized card), out to 1/0.3.
    static let scaleRange: ClosedRange<CGFloat> = 0.5...(1.0 / 0.3)

    /// How much of the board, in view points, always stays in the clear area however far the
    /// player pans.
    static let keepVisible: CGFloat = 120

    /// Where a scene point appears in the view (y down).
    func viewPoint(of point: CGPoint, in viewport: BoardViewport) -> CGPoint {
        CGPoint(x: (point.x - position.x) / scale + viewport.size.width / 2,
                y: viewport.size.height / 2 - (point.y - position.y) / scale)
    }

    /// The scene point under a view point (y down).
    func scenePoint(at viewPoint: CGPoint, in viewport: BoardViewport) -> CGPoint {
        CGPoint(x: position.x + (viewPoint.x - viewport.size.width / 2) * scale,
                y: position.y + (viewport.size.height / 2 - viewPoint.y) * scale)
    }

    /// The camera that shows all of `content` in the clear area, with `margin` points to spare,
    /// zoomed in no further than 1:1 (a small board isn't blown up).
    static func fitting(_ content: CGRect, in viewport: BoardViewport, margin: CGFloat = 24) -> BoardCamera {
        let clear = viewport.clearRect
        let width = max(1, clear.width - margin * 2)
        let height = max(1, clear.height - margin * 2)
        let fit = max(content.width / width, content.height / height, 1)
        let scale = min(max(fit, scaleRange.lowerBound), scaleRange.upperBound)
        // Put the content's centre at the clear area's centre.
        let position = CGPoint(x: content.midX - (clear.midX - viewport.size.width / 2) * scale,
                               y: content.midY + (clear.midY - viewport.size.height / 2) * scale)
        return BoardCamera(position: position, scale: scale)
    }

    /// The same camera, panned back so at least `keepVisible` points of the board (or all of
    /// it, when it's smaller) stay in the clear area.
    func clamped(to content: CGRect, in viewport: BoardViewport) -> BoardCamera {
        guard !content.isNull, !content.isEmpty else { return self }
        let clear = viewport.clearRect
        let half = CGSize(width: viewport.size.width / 2, height: viewport.size.height / 2)
        let keepX = min(Self.keepVisible, content.width / scale, clear.width / 2)
        let keepY = min(Self.keepVisible, content.height / scale, clear.height / 2)
        // The board's right edge stays right of the clear area's left edge (plus keep), and so on.
        let minX = content.minX + (half.width - clear.maxX + keepX) * scale
        let maxX = content.maxX + (half.width - clear.minX - keepX) * scale
        let minY = content.minY + (clear.minY + keepY - half.height) * scale
        let maxY = content.maxY + (clear.maxY - keepY - half.height) * scale
        var camera = self
        camera.position.x = minX <= maxX ? min(max(position.x, minX), maxX) : (minX + maxX) / 2
        camera.position.y = minY <= maxY ? min(max(position.y, minY), maxY) : (minY + maxY) / 2
        return camera
    }

    /// Whether all of `content` is in the clear area.
    func shows(_ content: CGRect, in viewport: BoardViewport) -> Bool {
        let clear = viewport.clearRect.insetBy(dx: -1, dy: -1)
        return [CGPoint(x: content.minX, y: content.minY), CGPoint(x: content.maxX, y: content.maxY)]
            .allSatisfy { clear.contains(viewPoint(of: $0, in: viewport)) }
    }

    /// Clamped to the board's extent, and then, if no hex is left in the clear area (an
    /// L-shaped map's empty corner, or zoomed in on a sliver), panned to the nearest one.
    func clamped(to content: CGRect, hexes: [CGPoint], in viewport: BoardViewport) -> BoardCamera {
        let camera = clamped(to: content, in: viewport)
        let clear = viewport.clearRect
        guard !hexes.isEmpty, !hexes.contains(where: { clear.contains(camera.viewPoint(of: $0, in: viewport)) }) else {
            return camera
        }
        let middle = camera.scenePoint(at: CGPoint(x: clear.midX, y: clear.midY), in: viewport)
        let nearest = hexes.min { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }!
        return camera.showing(nearest, in: viewport, margin: 60)
    }

    /// Zoomed to `newScale` (within range) with the scene point under `anchor` (a view point)
    /// staying put — a pinch zooms where the fingers are.
    func zoomed(to newScale: CGFloat, around anchor: CGPoint, in viewport: BoardViewport) -> BoardCamera {
        let scale = min(max(newScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let pinned = scenePoint(at: anchor, in: viewport)
        let position = CGPoint(x: pinned.x - (pinned.x - self.position.x) * scale / self.scale,
                               y: pinned.y - (pinned.y - self.position.y) * scale / self.scale)
        return BoardCamera(position: position, scale: scale)
    }

    /// The smallest pan that brings `point` at least `margin` points inside the clear area; the
    /// same camera when it's already there.
    func showing(_ point: CGPoint, in viewport: BoardViewport, margin: CGFloat = 90) -> BoardCamera {
        let clear = viewport.clearRect
        let inner = clear.insetBy(dx: min(margin, clear.width / 2 - 1), dy: min(margin, clear.height / 2 - 1))
        let seen = viewPoint(of: point, in: viewport)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if seen.x < inner.minX { dx = seen.x - inner.minX } else if seen.x > inner.maxX { dx = seen.x - inner.maxX }
        if seen.y < inner.minY { dy = seen.y - inner.minY } else if seen.y > inner.maxY { dy = seen.y - inner.maxY }
        guard dx != 0 || dy != 0 else { return self }
        // View y runs down, scene y up.
        return BoardCamera(position: CGPoint(x: position.x + dx * scale, y: position.y - dy * scale), scale: scale)
    }
}
