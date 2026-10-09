import SwiftUI
import UniformTypeIdentifiers

/// Every saved campaign, most recently played first: play one, rename, duplicate, export or
/// delete it, or import one shared from another device.
struct CampaignsSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: CampaignStore.Entry?
    @State private var newName = ""
    @State private var deleting: CampaignStore.Entry?
    @State private var exporting: ExportedCampaign?
    @State private var showImporter = false
    @State private var importError: String?
    /// Off for snapshots: ImageRenderer draws neither scroll views nor navigation stacks.
    var scrolls = true

    var body: some View {
        if scrolls {
            NavigationStack { sheet }
        } else {
            list.background(BoardTheme.sheet)
        }
    }

    private var sheet: some View {
        ScrollView { list }
            .background(BoardTheme.sheet)
            .navigationTitle("Campaigns")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .alert("Rename Campaign", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let renaming { gameManager.renameCampaign(renaming.id, to: newName) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            } message: {
                Text("Leave it empty to name it after the party.")
            }
            .confirmationDialog(deleting.map { "Delete \u{201C}\($0.title)\u{201D}?" } ?? "",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Campaign", role: .destructive) {
                    if let deleting { gameManager.deleteCampaign(deleting.id) }
                    deleting = nil
                }
                Button("Keep It", role: .cancel) { deleting = nil }
            } message: {
                Text("The party and all its progress are gone for good.")
            }
            .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
                          document: exporting?.document, contentType: .json,
                          defaultFilename: exporting?.filename ?? "campaign.json") { _ in exporting = nil }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importError = Self.importCampaign(result, into: gameManager)
            }
            .alert("Couldn\u{2019}t Import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
    }

    private var list: some View {
        VStack(spacing: 10) {
            if gameManager.campaigns.isEmpty {
                Text("No campaigns yet. Start one from the main menu.")
                    .foregroundStyle(BoardTheme.secondaryText)
                    .padding(.top, 40)
            }
            ForEach(gameManager.campaigns) { campaign in
                row(campaign)
            }
        }
        .padding(20)
    }

    private func row(_ campaign: CampaignStore.Entry) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.title)
                    .font(GlavenFont.title(size: 22))
                    .foregroundStyle(BoardTheme.text)
                    .lineLimit(1)
                if let detail = Self.detail(campaign) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(BoardTheme.secondaryText)
                        .lineLimit(2)
                }
                Text("Played \(campaign.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            Spacer()
            Menu {
                Button { newName = campaign.name; renaming = campaign } label: { Label("Rename", systemImage: "pencil") }
                Button { gameManager.duplicateCampaign(campaign.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button {
                    if let data = gameManager.campaignStore.exportData(campaign.id) {
                        exporting = ExportedCampaign(document: CampaignDocument(data: data), title: campaign.title)
                    }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { deleting = campaign } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(BoardTheme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More for \(campaign.title)")
            Button {
                dismiss()
                gameManager.continueCampaign(campaign.id)
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(BoardTheme.panel, in: Capsule())
                    .overlay(Capsule().stroke(BoardTheme.brass, lineWidth: 1.5))
                    .foregroundStyle(BoardTheme.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(campaign.title)")
        }
        .padding(14)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
        .overlay {
            if campaign.id == gameManager.continueCampaign?.id {
                RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.brass.opacity(0.6), lineWidth: 1)
            }
        }
    }

    /// "Brute, Tinkerer · #1 Black Barrow, round 2" (the party, when the campaign is named).
    static func detail(_ campaign: CampaignStore.Entry) -> String? {
        guard let summary = campaign.summary else { return "No party yet" }
        var parts: [String] = []
        if !campaign.name.isEmpty { parts.append(GameText.list(summary.characterNames)) }
        if let scenario = summary.scenario, let round = summary.round {
            parts.append("\(scenario), round \(round)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Nil on success, or why the file couldn't be imported.
    private static func importCampaign(_ result: Result<URL, Error>, into gameManager: GameManager) -> String? {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return "The file couldn\u{2019}t be read." }
            return gameManager.importGameData(data) ? nil : "That file isn\u{2019}t a Glaven campaign."
        case .failure(let error):
            return error.localizedDescription
        }
    }
}

private struct ExportedCampaign {
    let document: CampaignDocument
    let title: String
    var filename: String { "\(title).json" }
}

/// A campaign file for the system's export panel.
struct CampaignDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
