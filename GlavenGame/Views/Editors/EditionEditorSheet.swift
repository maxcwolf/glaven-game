import SwiftUI

/// Editor for creating/editing complete game editions (custom content packages).
struct EditionEditorSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var editionName: String = ""
    @State private var extensions: [String] = []
    @State private var newExtension: String = ""
    @State private var selectedConditions: Set<ConditionName> = Set(ConditionName.allCases.prefix(10))
    @State private var characters: [CharacterData] = []
    @State private var monsters: [MonsterData] = []
    @State private var decks: [DeckData] = []
    @State private var jsonOutput: String = ""
    @State private var jsonInput: String = ""
    @State private var jsonError: String?

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    var body: some View {
        NavigationStack {
            mainContent
                .background(GlavenTheme.background)
                .navigationTitle("Edition Editor")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(editions, id: \.self) { ed in
                                Button(ed.uppercased()) { loadEdition(ed) }
                            }
                        } label: {
                            Label("Load", systemImage: "folder")
                        }
                    }
                }
                .onChange(of: editionName) { _, _ in updateJSON() }
                .onChange(of: extensions) { _, _ in updateJSON() }
                .onChange(of: selectedConditions) { _, _ in updateJSON() }
                .onChange(of: characters) { _, _ in updateJSON() }
                .onChange(of: monsters) { _, _ in updateJSON() }
                .onChange(of: decks) { _, _ in updateJSON() }
                .onAppear { updateJSON() }
        }
    }

    private var mainContent: some View {
        HSplitOrVStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    propertiesSection
                    conditionsSection
                    extensionsSection
                    dataArraysSection
                }
                .padding()
            }
            .frame(minWidth: 320)

            Divider()

            jsonOutputSection
        }
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edition Properties")
                .font(.headline)

            HStack {
                Text("Name")
                    .frame(width: 80, alignment: .leading)
                TextField("edition-id", text: $editionName)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Conditions

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Conditions")
                    .font(.headline)
                Spacer()
                Button("All") { selectedConditions = Set(ConditionName.allCases) }
                    .font(.caption)
                Button("None") { selectedConditions = [] }
                    .font(.caption)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(ConditionName.allCases, id: \.self) { condition in
                    Toggle(condition.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                           isOn: Binding(
                            get: { selectedConditions.contains(condition) },
                            set: { selected in
                                if selected { selectedConditions.insert(condition) }
                                else { selectedConditions.remove(condition) }
                            }
                           ))
                    .toggleStyle(.switch)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Extensions

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extends")
                .font(.headline)

            ForEach(extensions, id: \.self) { ext in
                HStack {
                    Text(ext)
                        .font(.subheadline)
                    Spacer()
                    Button(role: .destructive) {
                        extensions.removeAll { $0 == ext }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField("edition-name", text: $newExtension)
                    .textFieldStyle(.roundedBorder)
                Button {
                    guard !newExtension.isEmpty else { return }
                    extensions.append(newExtension)
                    newExtension = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newExtension.isEmpty)
            }
        }
    }

    // MARK: - Data Arrays

    private var dataArraysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Characters
            dataArrayHeader(title: "Characters", count: characters.count, onClear: { characters = [] })
            ForEach(Array(characters.enumerated()), id: \.offset) { index, char in
                HStack {
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(char.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption)
                    Spacer()
                    Button(role: .destructive) { characters.remove(at: index) } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Paste character JSON into the output panel to add characters.")
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)

            Divider()

            // Monsters
            dataArrayHeader(title: "Monsters", count: monsters.count, onClear: { monsters = [] })
            ForEach(Array(monsters.enumerated()), id: \.offset) { index, monster in
                HStack {
                    Image(systemName: "pawprint.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption)
                    if monster.isBoss {
                        Text("BOSS")
                            .font(.caption2.bold())
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Button(role: .destructive) { monsters.remove(at: index) } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Decks
            dataArrayHeader(title: "Decks", count: decks.count, onClear: { decks = [] })
            ForEach(Array(decks.enumerated()), id: \.offset) { index, deck in
                HStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(deck.name)
                        .font(.caption)
                    Text("(\(deck.abilities.count) cards)")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Spacer()
                    Button(role: .destructive) { decks.remove(at: index) } label: {
                        Image(systemName: "trash").font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dataArrayHeader(title: String, count: Int, onClear: @escaping () -> Void) -> some View {
        HStack {
            Text("\(title) (\(count))")
                .font(.headline)
            Spacer()
            if count > 0 {
                Button("Clear", role: .destructive) { onClear() }
                    .font(.caption)
            }
        }
    }

    // MARK: - JSON Output

    private var jsonOutputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("JSON Output")
                    .font(.headline)
                Spacer()
                Button {
                    copyToClipboard(jsonOutput)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
            }

            if let error = jsonError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $jsonInput)
                .font(.system(.caption, design: .monospaced))
                .frame(maxHeight: .infinity)
                .padding(4)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: jsonInput) { _, newValue in
                    parseJSON(newValue)
                }
        }
        .padding()
        .frame(minWidth: 280)
    }

    // MARK: - Logic

    private func loadEdition(_ ed: String) {
        editionName = ed
        let info = gameManager.editionStore.editions.first(where: { $0.edition == ed })
        selectedConditions = Set(info?.conditions ?? [])
        extensions = info?.extends ?? info?.extensions ?? []
        characters = gameManager.editionStore.characters(for: ed)
        monsters = gameManager.editionStore.monsters(for: ed)
        decks = gameManager.editionStore.decksByEdition[ed] ?? []
    }

    private func updateJSON() {
        let edition = EditionExportData(
            edition: editionName.isEmpty ? "custom" : editionName,
            extensions: extensions.isEmpty ? nil : extensions,
            conditions: selectedConditions.isEmpty ? nil : Array(selectedConditions),
            characters: characters.isEmpty ? nil : characters,
            monsters: monsters.isEmpty ? nil : monsters,
            decks: decks.isEmpty ? nil : decks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(edition),
           let str = String(data: data, encoding: .utf8) {
            jsonOutput = str
            jsonInput = str
            jsonError = nil
        }
    }

    private func parseJSON(_ jsonString: String) {
        guard jsonString != jsonOutput else { return }
        guard let data = jsonString.data(using: .utf8) else {
            jsonError = "Invalid text encoding"
            return
        }
        do {
            let edition = try JSONDecoder().decode(EditionExportData.self, from: data)
            editionName = edition.edition
            extensions = edition.extensions ?? []
            selectedConditions = Set(edition.conditions ?? [])
            characters = edition.characters ?? []
            monsters = edition.monsters ?? []
            decks = edition.decks ?? []
            jsonError = nil
        } catch {
            jsonError = "Parse error: \(error.localizedDescription)"
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// Lightweight export struct for edition JSON.
private struct EditionExportData: Codable {
    var edition: String
    var extensions: [String]?
    var conditions: [ConditionName]?
    var characters: [CharacterData]?
    var monsters: [MonsterData]?
    var decks: [DeckData]?
}
