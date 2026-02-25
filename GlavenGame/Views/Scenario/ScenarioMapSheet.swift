import SwiftUI

struct ScenarioMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let scenario: VGBScenario

    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0

    // Pre-computed once during init — not recomputed on every body evaluation
    private let tiles: [UniqueTile]
    private let overlays: [PositionedOverlay]
    private let bounds: MapBounds

    init(scenario: VGBScenario) {
        self.scenario = scenario
        let result = ScenarioMapBuilder.build(from: scenario)
        self.overlays = result.overlays
        self.bounds = result.bounds
        self.tiles = Self.computeUniqueTiles(from: scenario.mapTileData)
    }

    var body: some View {
        NavigationStack {
            mapContent
                .navigationTitle("#\(scenario.id) \(scenario.title)")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation { zoom = 1.0; lastZoom = 1.0 }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        // Add padding around the bounds
        let padding = 2
        let minCol = bounds.minCol - padding
        let minRow = bounds.minRow - padding
        let maxCol = bounds.maxCol + padding
        let maxRow = bounds.maxRow + padding

        let totalWidth = CGFloat(maxCol - minCol + 1) * HexMath.cellStepX + HexMath.cellStepX
        let totalHeight = CGFloat(maxRow - minRow + 1) * HexMath.cellStepY + HexMath.cellSize

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Layer 1: Tile images
                ForEach(tiles, id: \.id) { tile in
                    tileImage(tile: tile, offsetCol: minCol, offsetRow: minRow)
                }

                // Layer 2: Overlay images
                ForEach(Array(overlays.enumerated()), id: \.offset) { _, overlay in
                    overlayImage(overlay: overlay, offsetCol: minCol, offsetRow: minRow)
                }
            }
            .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: totalWidth * zoom, height: totalHeight * zoom, alignment: .topLeading)
        }
        .defaultScrollAnchor(.center)
        .background(Color(red: 0.15, green: 0.13, blue: 0.12))
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    zoom = max(0.3, min(3.0, lastZoom * value.magnification))
                }
                .onEnded { value in
                    lastZoom = max(0.3, min(3.0, lastZoom * value.magnification))
                    zoom = lastZoom
                }
        )
    }

    // MARK: - Tile Rendering

    @ViewBuilder
    private func tileImage(tile: UniqueTile, offsetCol: Int, offsetRow: Int) -> some View {
        let pos = HexMath.hexToPixel(col: tile.anchorCol - offsetCol, row: tile.anchorRow - offsetRow)
        let imgOffset = TileImageOffsets.offset(for: tile.ref)

        if let image = MapImageCache.shared.image(named: "map-tiles/\(tile.ref)") {
            Image(decorative: image, scale: 1)
                .offset(x: CGFloat(imgOffset.left), y: CGFloat(imgOffset.top))
                .frame(width: 75, height: 90, alignment: .topLeading)
                .rotationEffect(.degrees(Double(tile.turns) * 60))
                .offset(x: pos.x, y: pos.y)
        }
    }

    @ViewBuilder
    private func overlayImage(overlay: PositionedOverlay, offsetCol: Int, offsetRow: Int) -> some View {
        let pos = HexMath.hexToPixel(col: overlay.col - offsetCol, row: overlay.row - offsetRow)

        if let image = MapImageCache.shared.image(named: "overlays/\(overlay.imageName)") {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: HexMath.cellSize)
                .offset(x: pos.x - 7, y: pos.y)
        }
    }

    // MARK: - Unique Tile Collection

    private static func computeUniqueTiles(from mapTileData: VGBMapTileData) -> [UniqueTile] {
        var seen = Set<String>()
        var result = [UniqueTile]()
        collectUniqueTiles(from: mapTileData, turnAxis: nil, into: &result, seen: &seen)
        return result
    }

    private static func collectUniqueTiles(
        from data: VGBMapTileData,
        turnAxis: (refPoint: (Int, Int), origin: (Int, Int))?,
        into result: inout [UniqueTile],
        seen: inout Set<String>
    ) {
        let refPoint = turnAxis?.refPoint ?? (0, 0)
        let origin = turnAxis?.origin ?? (0, 0)

        let anchor = HexMath.normaliseAndRotatePoint(
            turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: (0, 0)
        )

        let key = "\(data.ref)_\(anchor.0)_\(anchor.1)"
        if !seen.contains(key) {
            seen.insert(key)
            result.append(UniqueTile(
                id: key,
                ref: data.ref,
                anchorCol: anchor.0,
                anchorRow: anchor.1,
                turns: data.turns
            ))
        }

        for door in data.doors {
            let r = (door.room1X, door.room1Y)
            let doorRefPoint = HexMath.normaliseAndRotatePoint(
                turns: data.turns, refPoint: refPoint, origin: origin, tileCoord: r
            )
            let doorOrigin = (door.room2X, door.room2Y)
            collectUniqueTiles(
                from: door.mapTileData,
                turnAxis: (refPoint: doorRefPoint, origin: doorOrigin),
                into: &result,
                seen: &seen
            )
        }
    }
}

// MARK: - Supporting Types

struct UniqueTile: Identifiable {
    let id: String
    let ref: String
    let anchorCol: Int
    let anchorRow: Int
    let turns: Int
}

// MARK: - Image Cache

/// Caches loaded CGImages to avoid repeated disk I/O on every render pass.
final class MapImageCache {
    static let shared = MapImageCache()
    private var cache: [String: CGImage] = [:]

    private init() {}

    func image(named name: String) -> CGImage? {
        if let cached = cache[name] { return cached }

        guard let url = appResourceBundle.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Images"
        ) else { return nil }

        let loaded: CGImage?
        #if canImport(AppKit)
        if let nsImage = NSImage(contentsOf: url) {
            loaded = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        } else {
            loaded = nil
        }
        #else
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            loaded = uiImage.cgImage
        } else {
            loaded = nil
        }
        #endif

        if let img = loaded {
            cache[name] = img
        }
        return loaded
    }
}

// MARK: - Wrapper for GameBoardSheet

/// Loads the VGB scenario for the current game scenario and presents the map sheet.
struct ScenarioMapSheetWrapper: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    private let store = ScenarioMapStore.shared

    var body: some View {
        if let index = gameManager.game.scenario?.data.index,
           let vgbScenario = store.scenarioMap(for: index) {
            ScenarioMapSheet(scenario: vgbScenario)
        } else {
            ContentUnavailableView(
                "Map Not Available",
                systemImage: "map",
                description: Text("No map data found for this scenario.")
            )
        }
    }
}
