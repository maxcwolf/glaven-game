import SwiftUI
import UniformTypeIdentifiers

/// Every saved campaign, most recently played first: play one, rename, duplicate, export or
/// delete it, or import one shared from another device.
struct CampaignsSheet: View {
    @Environment(GameManager.self) private var gameManager
    @State private var renaming: CampaignStore.Entry?
    @State private var newName = ""
    @State private var deleting: CampaignStore.Entry?
    @State private var exporting: ExportedCampaign?
    @State private var showImporter = false
    @State private var importError: String?
    /// Off for snapshots: ImageRenderer doesn't draw scroll views.
    var scrolls = true
    var onDone: () -> Void = {}

    var body: some View {
        TownDialog(title: "Campaigns", subtitle: Self.subtitle(count: gameManager.campaigns.count),
                   size: CGSize(width: 780, height: 600), onDone: onDone) {
            Button("Import", systemImage: "square.and.arrow.down") { showImporter = true }
                .buttonStyle(.boardQuietCompact)
                .accessibilityHint("Open a campaign file shared from another device")
        } content: {
            if scrolls { ScrollView { list } } else { list }
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
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .padding(.top, 40)
            }
            ForEach(gameManager.campaigns) { campaign in
                row(campaign)
            }
        }
        .padding(18)
    }

    private func row(_ campaign: CampaignStore.Entry) -> some View {
        let playing = campaign.id == gameManager.continueCampaign?.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(campaign.title)
                        .font(BoardTheme.display(21))
                        .foregroundStyle(BoardTheme.text)
                        .lineLimit(1)
                    if playing { TownSmallCaps(text: "Playing", lit: true) }
                }
                Text(Self.line(detail: Self.detail(campaign), played: campaign.updatedAt))
                    .font(BoardTheme.font(size: 12))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
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
                Image(systemName: "ellipsis")
                    .font(BoardTheme.font(size: 15, weight: .semibold))
                    .foregroundStyle(BoardTheme.text)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(BoardTheme.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More for \(campaign.title)")
            Button("Play", systemImage: "play.fill") {
                onDone()
                gameManager.continueCampaign(campaign.id)
            }
            .buttonStyle(playing ? .boardPrimaryCompact : .boardQuietCompact)
            .accessibilityLabel("Play \(campaign.title)")
        }
        .padding(14)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(playing ? BoardTheme.brass : BoardTheme.border.opacity(0.45), lineWidth: playing ? 1.5 : 1))
    }

    /// "Saved on this iPad · 2 campaigns".
    static func subtitle(count: Int) -> String {
        #if os(iOS)
        let place = "Saved on this iPad"
        #else
        let place = "Saved on this Mac"
        #endif
        return count == 0 ? place : "\(place) \u{00B7} \(count) campaign\(count == 1 ? "" : "s")"
    }

    /// "Brute, Tinkerer · played Oct 9, 1:15 PM".
    static func line(detail: String?, played: Date) -> String {
        let when = "played \(played.formatted(date: .abbreviated, time: .shortened))"
        return [detail, when].compactMap { $0 }.joined(separator: " \u{00B7} ")
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
