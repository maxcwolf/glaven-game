import Foundation
import SwiftData

/// One saved campaign: the game as it last stood (the start of the round, mid-scenario).
struct CampaignFile: Codable {
    var id: UUID
    /// The player's name for it; empty until renamed (the party's names stand in).
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var snapshot: GameSnapshot
}

/// Campaigns saved as files on the device, one JSON file each, so several parties can be played
/// side by side. On iPad they sit in the app's Documents folder, visible in the Files app.
final class CampaignStore {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// What the campaigns list and Continue show, without the whole snapshot.
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let name: String
        let updatedAt: Date
        /// Nil for a campaign with no party yet.
        let summary: AutosaveSummary?

        /// The name, or the party's names until it has one.
        var title: String {
            if !name.isEmpty { return name }
            if let summary { return GameText.list(summary.characterNames) }
            return "New Campaign"
        }
    }

    // MARK: - Where

    /// Documents/Campaigns on iPad; Application Support on the Mac. A store kept only in memory
    /// (tests, previews) gets a temporary folder of its own, shared by every manager on it.
    static func directory(for container: ModelContainer) -> URL {
        if container.configurations.contains(where: \.isStoredInMemoryOnly) {
            let key = ObjectIdentifier(container)
            if let known = temporaryDirectories[key], known.container === container { return known.url }
            temporaryDirectories = temporaryDirectories.filter { $0.value.container != nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GlavenGameCampaigns-\(UUID().uuidString)", isDirectory: true)
            temporaryDirectories[key] = TemporaryDirectory(container: container, url: url)
            return url
        }
        #if os(iOS)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlavenGame", isDirectory: true)
        #endif
        return base.appendingPathComponent("Campaigns", isDirectory: true)
    }

    /// By container identity, held weakly: a container that's gone can't claim a folder again
    /// even if a new one reuses its address.
    private struct TemporaryDirectory {
        weak var container: ModelContainer?
        let url: URL
    }
    private static var temporaryDirectories: [ObjectIdentifier: TemporaryDirectory] = [:]

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Reading

    /// Every campaign, most recently played first.
    func entries(labels: EditionDataStore?) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(CampaignFile.self, from: Data(contentsOf: $0)) }
            .map { Entry(id: $0.id, name: $0.name, updatedAt: $0.updatedAt,
                         summary: AutosaveSummary($0.snapshot, savedAt: $0.updatedAt, labels: labels)) }
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    func load(_ id: UUID) -> CampaignFile? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return try? Self.decoder.decode(CampaignFile.self, from: data)
    }

    func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    // MARK: - Writing

    /// Write a campaign to its file (atomically, so a failed write leaves the last save intact).
    func save(_ file: CampaignFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(file)
        try data.write(to: url(for: file.id), options: .atomic)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// A campaign file as exported, for sharing.
    func exportData(_ id: UUID) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    /// Read an exported campaign (or a bare game snapshot from an older export) as a new
    /// campaign; nil if it isn't one.
    func importCampaign(_ data: Data) -> CampaignFile? {
        let now = Date()
        var file: CampaignFile
        if let campaign = try? Self.decoder.decode(CampaignFile.self, from: data) {
            file = campaign
        } else if let snapshot = try? JSONDecoder().decode(GameSnapshot.self, from: data) {
            file = CampaignFile(id: UUID(), name: "", createdAt: now, updatedAt: now, snapshot: snapshot)
        } else {
            return nil
        }
        file.id = UUID()   // never replaces a campaign already here
        file.updatedAt = now
        // An import that can't be written isn't imported.
        guard (try? save(file)) != nil else { return nil }
        return file
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Seconds since 1970 with their fraction: saves a moment apart still sort in order.
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
