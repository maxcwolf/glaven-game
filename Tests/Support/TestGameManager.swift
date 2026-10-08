import SwiftData
@testable import GlavenGameLib

/// A GameManager on an in-memory store, set up for Gloomhaven.
@MainActor
enum SaveAndContinueTestsSupport {
    static func manager() throws -> GameManager {
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        return gm
    }
}
