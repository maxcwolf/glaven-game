import Foundation
import SwiftData

@Model
final class SavedGameModel {
    var name: String = "autosave"
    var snapshotData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(name: String = "autosave") {
        self.name = name
    }
}
