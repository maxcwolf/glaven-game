import Foundation

/// Loads and caches VGB scenario map data from bundled JSON files.
final class ScenarioMapStore {
    static let shared = ScenarioMapStore()

    private var cache: [String: VGBScenario] = [:]
    private var availableIndices: Set<String>?

    private init() {}

    /// Load a scenario map by its index string (e.g. "1", "72", "solo-3").
    func scenarioMap(for index: String) -> VGBScenario? {
        if let cached = cache[index] { return cached }

        guard let url = appResourceBundle.url(
            forResource: index,
            withExtension: "json",
            subdirectory: "ScenarioMaps"
        ) else { return nil }

        guard let data = try? Data(contentsOf: url),
              let scenario = try? JSONDecoder().decode(VGBScenario.self, from: data)
        else { return nil }

        cache[index] = scenario
        return scenario
    }

    /// Check if a map exists for the given scenario index.
    func hasMap(for index: String) -> Bool {
        if let indices = availableIndices {
            return indices.contains(index)
        }
        // Build the set once from bundled resources
        var indices = Set<String>()
        if let urls = appResourceBundle.urls(
            forResourcesWithExtension: "json",
            subdirectory: "ScenarioMaps"
        ) {
            for url in urls {
                indices.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        availableIndices = indices
        return indices.contains(index)
    }
}
