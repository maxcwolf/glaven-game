import SwiftUI

/// Editor for creating/editing character class data.
struct CharacterEditorSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var charName: String = ""
    @State private var charEdition: String = "gh"
    @State private var charColor: Color = .blue
    @State private var charColorHex: String = "#0000FF"
    @State private var isSpoiler: Bool = false
    @State private var deckName: String = ""
    @State private var characterClass: String = ""
    @State private var stats: [CharacterStatModel] = (1...9).map { CharacterStatModel(level: $0, health: 6 + $0 * 2) }
    @State private var jsonOutput: String = ""
    @State private var jsonInput: String = ""
    @State private var jsonError: String?
    @State private var hpPreset: Int = -1

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var existingCharacters: [CharacterData] {
        gameManager.editionStore.characters(for: charEdition)
    }

    private let classOptions = [
        "human", "inox", "quatryl", "orchid", "savvas",
        "vermling", "valrath", "harrower", "aesther", "lurker",
        "algox", "unfettered", "spell-weaver"
    ]

    var body: some View {
        NavigationStack {
            HSplitOrVStack {
                // Input side
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        propertiesSection
                        statsSection
                    }
                    .padding()
                }
                .frame(minWidth: 300)

                Divider()

                // JSON output
                jsonOutputSection
            }
            .background(GlavenTheme.background)
            .navigationTitle("Character Editor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(existingCharacters) { char in
                            Button(char.name.replacingOccurrences(of: "-", with: " ").capitalized) {
                                loadCharacter(char)
                            }
                        }
                    } label: {
                        Label("Load", systemImage: "folder")
                    }
                    .disabled(existingCharacters.isEmpty)
                }
            }
            .onChange(of: charName) { _, _ in updateJSON() }
            .onChange(of: charEdition) { _, _ in updateJSON() }
            .onChange(of: charColorHex) { _, _ in updateJSON() }
            .onChange(of: isSpoiler) { _, _ in updateJSON() }
            .onChange(of: deckName) { _, _ in updateJSON() }
            .onChange(of: characterClass) { _, _ in updateJSON() }
            .onChange(of: stats) { _, _ in updateJSON() }
            .onAppear { updateJSON() }
        }
    }

    // MARK: - Properties Section

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Character Properties")
                .font(.headline)

            editionRow
            nameRow
            classRow
            colorRow
            deckRow

            Toggle("Spoiler", isOn: $isSpoiler)
                .font(.subheadline)
        }
    }

    private var editionRow: some View {
        HStack {
            Text("Edition")
                .frame(width: 80, alignment: .leading)
            Picker("", selection: $charEdition) {
                ForEach(editions, id: \.self) { ed in
                    Text(ed.uppercased()).tag(ed)
                }
            }
            .labelsHidden()
        }
    }

    private var nameRow: some View {
        HStack {
            Text("Name")
                .frame(width: 80, alignment: .leading)
            TextField("character-name", text: $charName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var classRow: some View {
        HStack {
            Text("Class")
                .frame(width: 80, alignment: .leading)
            Picker("", selection: $characterClass) {
                Text("(none)").tag("")
                ForEach(classOptions, id: \.self) { cls in
                    Text(cls.capitalized).tag(cls)
                }
            }
            .labelsHidden()
        }
    }

    private var colorRow: some View {
        HStack {
            Text("Color")
                .frame(width: 80, alignment: .leading)
            TextField("#RRGGBB", text: $charColorHex)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
            ColorPicker("", selection: $charColor)
                .labelsHidden()
                .onChange(of: charColor) { _, newColor in
                    charColorHex = newColor.toHex()
                }
        }
    }

    private var deckRow: some View {
        HStack {
            Text("Deck")
                .frame(width: 80, alignment: .leading)
            TextField("deck-name", text: $deckName)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Health per Level")
                    .font(.headline)
                Spacer()
                Picker("Preset", selection: $hpPreset) {
                    Text("Custom").tag(-1)
                    Text("Low (6→14)").tag(0)
                    Text("Mid (8→20)").tag(1)
                    Text("High (10→26)").tag(2)
                }
                .onChange(of: hpPreset) { _, preset in
                    applyHPPreset(preset)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    HStack(spacing: 4) {
                        Text("Lv\(stat.level)")
                            .font(.caption.bold())
                            .frame(width: 32, alignment: .leading)
                        TextField("HP", value: $stats[index].health, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
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

    private func loadCharacter(_ char: CharacterData) {
        charName = char.name
        charEdition = char.edition
        characterClass = char.characterClass ?? ""
        isSpoiler = char.spoiler ?? false
        deckName = char.deck ?? char.name
        charColorHex = char.color ?? "#0000FF"
        stats = char.stats
        if stats.count < 9 {
            for level in (stats.count + 1)...9 {
                stats.append(CharacterStatModel(level: level, health: 10))
            }
        }
        hpPreset = -1
    }

    private func applyHPPreset(_ preset: Int) {
        guard preset >= 0 else { return }
        let bases: [[Int]] = [
            [6, 7, 8, 9, 10, 11, 12, 13, 14],      // Low
            [8, 9, 11, 12, 14, 15, 17, 18, 20],     // Mid
            [10, 12, 14, 16, 18, 20, 22, 24, 26],   // High
        ]
        guard preset < bases.count else { return }
        for i in 0..<min(9, stats.count) {
            stats[i].health = bases[preset][i]
        }
    }

    private func updateJSON() {
        var charData = CharacterData(
            name: charName.isEmpty ? "unnamed" : charName,
            edition: charEdition,
            stats: stats
        )
        if !characterClass.isEmpty { charData.characterClass = characterClass }
        if !charColorHex.isEmpty { charData.color = charColorHex }
        if isSpoiler { charData.spoiler = true }
        if !deckName.isEmpty { charData.deck = deckName }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(charData),
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
            let char = try JSONDecoder().decode(CharacterData.self, from: data)
            charName = char.name
            characterClass = char.characterClass ?? ""
            isSpoiler = char.spoiler ?? false
            deckName = char.deck ?? ""
            charColorHex = char.color ?? ""
            stats = char.stats
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

// MARK: - Color Hex Helper

private extension Color {
    func toHex() -> String {
        #if os(macOS)
        let nsColor = NSColor(self)
        guard let converted = nsColor.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(converted.redComponent * 255)
        let g = Int(converted.greenComponent * 255)
        let b = Int(converted.blueComponent * 255)
        #else
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
