import SwiftUI
import UniformTypeIdentifiers

struct SaveSlotsSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [SaveSlotInfo] = []
    @State private var showNewSave = false
    @State private var newSaveName = ""
    @State private var slotToDelete: SaveSlotInfo?
    @State private var slotToLoad: SaveSlotInfo?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if slots.isEmpty {
                    emptyState
                } else {
                    slotList
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Save Slots")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showNewSave = true } label: {
                            Label("New Save", systemImage: "plus")
                        }
                        Divider()
                        Button { showExporter = true } label: {
                            Label("Export Game", systemImage: "square.and.arrow.up")
                        }
                        Button { showImporter = true } label: {
                            Label("Import Game", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Save Game", isPresented: $showNewSave) {
                TextField("Save name", text: $newSaveName)
                Button("Save") {
                    let name = newSaveName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    gameManager.saveToSlot(name: name)
                    newSaveName = ""
                    refreshSlots()
                }
                Button("Cancel", role: .cancel) { newSaveName = "" }
            } message: {
                Text("Enter a name for this save.")
            }
            .alert("Load Save?", isPresented: Binding(
                get: { slotToLoad != nil },
                set: { if !$0 { slotToLoad = nil } }
            )) {
                Button("Load", role: .destructive) {
                    if let slot = slotToLoad {
                        gameManager.loadFromSlot(name: slot.name)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { slotToLoad = nil }
            } message: {
                if let slot = slotToLoad {
                    Text("Load \"\(slot.name)\"? Your current unsaved progress will be lost.")
                }
            }
            .alert("Delete Save?", isPresented: Binding(
                get: { slotToDelete != nil },
                set: { if !$0 { slotToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let slot = slotToDelete {
                        gameManager.deleteSlot(name: slot.name)
                        refreshSlots()
                    }
                }
                Button("Cancel", role: .cancel) { slotToDelete = nil }
            } message: {
                if let slot = slotToDelete {
                    Text("Delete \"\(slot.name)\"? This cannot be undone.")
                }
            }
            .onAppear { refreshSlots() }
            .fileExporter(
                isPresented: $showExporter,
                document: GameExportDocument(gameManager: gameManager),
                contentType: .json,
                defaultFilename: "glaven-save.json"
            ) { _ in }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource() else {
                        importError = "Cannot access file."
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        let data = try Data(contentsOf: url)
                        if gameManager.importGameData(data) {
                            dismiss()
                        } else {
                            importError = "Invalid save file format."
                        }
                    } catch {
                        importError = "Failed to read file: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importError = "Import failed: \(error.localizedDescription)"
                }
            }
            .alert("Import Error", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(GlavenTheme.secondaryText)
            Text("No saved games")
                .font(.headline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Text("Tap + to save your current game.")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Slot List

    @ViewBuilder
    private var slotList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(slots) { slot in
                    slotRow(slot)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func slotRow(_ slot: SaveSlotInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.name)
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let edition = slot.edition {
                        Text(edition.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.accentText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GlavenTheme.accentText.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if slot.characterCount > 0 {
                        Label("\(slot.characterCount)", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                    if let scenario = slot.scenarioName {
                        Text(scenario)
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Text(slot.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText.opacity(0.7))
            }

            Spacer()

            // Overwrite button
            Button {
                gameManager.saveToSlot(name: slot.name)
                refreshSlots()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16))
                    .foregroundStyle(GlavenTheme.accentText)
                    .frame(width: 36, height: 36)
                    .background(GlavenTheme.accentText.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Load button
            Button {
                slotToLoad = slot
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(GlavenTheme.positive)
                    .frame(width: 36, height: 36)
                    .background(GlavenTheme.positive.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                slotToDelete = slot
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func refreshSlots() {
        let models = gameManager.allSaveSlots()
        slots = models.compactMap { model in
            // Skip autosave from the list
            guard model.name != "autosave" else { return nil }
            return SaveSlotInfo(from: model)
        }
    }
}

// MARK: - Save Slot Info

private struct SaveSlotInfo: Identifiable {
    let id: String
    let name: String
    let updatedAt: Date
    let edition: String?
    let characterCount: Int
    let scenarioName: String?

    init(from model: SavedGameModel) {
        self.id = model.name
        self.name = model.name
        self.updatedAt = model.updatedAt

        // Try to extract summary info from snapshot
        if let data = model.snapshotData,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.edition = json["edition"] as? String
            self.characterCount = (json["characters"] as? [[String: Any]])?.count ?? 0
            if let scenario = json["scenario"] as? [String: Any],
               let scenarioData = scenario["data"] as? [String: Any] {
                let index = scenarioData["index"] as? String ?? ""
                let sName = scenarioData["name"] as? String ?? ""
                self.scenarioName = index.isEmpty ? nil : "#\(index) \(sName)"
            } else {
                self.scenarioName = nil
            }
        } else {
            self.edition = nil
            self.characterCount = 0
            self.scenarioName = nil
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }
}

// MARK: - Export Document

struct GameExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(gameManager: GameManager) {
        self.data = gameManager.exportGameData() ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
