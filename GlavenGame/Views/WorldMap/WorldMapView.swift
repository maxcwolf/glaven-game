import SwiftUI

struct WorldMapView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1.0
    @State private var selectedScenario: ScenarioData?
    @State private var initialZoomApplied = false

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var editionInfo: EditionInfo? {
        gameManager.editionStore.editions.first { $0.edition == edition }
    }

    private var mapDimensions: WorldMapDimensions? {
        editionInfo?.worldMap
    }

    private var scenarios: [ScenarioData] {
        gameManager.editionStore.scenarios(for: edition)
            .filter { $0.coordinates != nil && $0.parent == nil }
    }

    private var baseMapImage: PlatformImage? {
        ImageLoader.worldMapBase(edition: edition)
    }

    private var hasActiveScenario: Bool {
        gameManager.game.scenario != nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                mapContent(in: geo)
                    .onAppear {
                        if !initialZoomApplied, let dims = mapDimensions {
                            zoom = min(geo.size.width / dims.width, geo.size.height / dims.height)
                            initialZoomApplied = true
                        }
                    }
            }
            .background(GlavenTheme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(editionInfo?.displayName ?? "World Map")
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { withAnimation { zoom *= 1.25 } } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button { withAnimation { zoom *= 0.8 } } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                }
            }
            .sheet(item: $selectedScenario) { scenario in
                ScenarioMapDetailView(
                    scenario: scenario,
                    isCompleted: gameManager.scenarioManager.isCompleted(scenario),
                    isAvailable: gameManager.scenarioManager.isAvailable(scenario),
                    isBlocked: gameManager.scenarioManager.isBlocked(scenario),
                    isLocked: gameManager.scenarioManager.isLocked(scenario),
                    canStartScenario: !hasActiveScenario,
                    onStart: {
                        gameManager.scenarioManager.setScenario(scenario)
                        dismiss()
                    }
                )
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(GlavenTheme.headerFooterBackground, for: .navigationBar)
            #endif
        }
    }

    @ViewBuilder
    private func mapContent(in geo: GeometryProxy) -> some View {
        if let dims = mapDimensions {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    baseMap(dims: dims)

                    ForEach(scenarios) { scenario in
                        ScenarioMarkerView(
                            scenario: scenario,
                            zoom: zoom,
                            isCompleted: gameManager.scenarioManager.isCompleted(scenario),
                            isAvailable: gameManager.scenarioManager.isAvailable(scenario),
                            isBlocked: gameManager.scenarioManager.isBlocked(scenario),
                            isLocked: gameManager.scenarioManager.isLocked(scenario),
                            onTap: { selectedScenario = scenario }
                        )
                    }
                }
                .frame(width: dims.width * zoom, height: dims.height * zoom)
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newZoom = zoom * value.magnification
                        zoom = min(max(newZoom, 0.1), 5.0)
                    }
            )
        } else {
            ContentUnavailableView(
                "No World Map",
                systemImage: "map",
                description: Text("No world map data available for this edition.")
            )
        }
    }

    @ViewBuilder
    private func baseMap(dims: WorldMapDimensions) -> some View {
        if let img = baseMapImage {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .frame(width: dims.width * zoom, height: dims.height * zoom)
            #else
            Image(uiImage: img)
                .resizable()
                .frame(width: dims.width * zoom, height: dims.height * zoom)
            #endif
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: dims.width * zoom, height: dims.height * zoom)
                .overlay {
                    Text("Map image not found")
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
        }
    }
}
