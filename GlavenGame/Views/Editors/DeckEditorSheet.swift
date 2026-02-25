import SwiftUI

/// Editor for creating/editing ability card decks (character or monster).
struct DeckEditorSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var deckName: String = ""
    @State private var deckEdition: String = "gh"
    @State private var isCharacterDeck: Bool = false
    @State private var abilities: [AbilityModel] = []
    @State private var jsonOutput: String = ""
    @State private var jsonInput: String = ""
    @State private var jsonError: String?
    @State private var expandedAbility: Int?

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var existingDecks: [DeckData] {
        gameManager.editionStore.decksByEdition[deckEdition] ?? []
    }

    var body: some View {
        NavigationStack {
            HSplitOrVStack {
                // Input side
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        inputSection
                        abilitiesSection
                    }
                    .padding()
                }
                .frame(minWidth: 300)

                Divider()

                // JSON output side
                jsonOutputSection
            }
            .background(GlavenTheme.background)
            .navigationTitle("Deck Editor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(existingDecks) { deck in
                            Button(deck.name) { loadDeck(deck) }
                        }
                    } label: {
                        Label("Load", systemImage: "folder")
                    }
                    .disabled(existingDecks.isEmpty)
                }
            }
            .onChange(of: deckName) { _, _ in updateJSON() }
            .onChange(of: deckEdition) { _, _ in updateJSON() }
            .onChange(of: isCharacterDeck) { _, _ in updateJSON() }
            .onChange(of: abilities) { _, _ in updateJSON() }
            .onAppear { updateJSON() }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Deck Properties")
                .font(.headline)

            HStack {
                Text("Edition")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $deckEdition) {
                    ForEach(editions, id: \.self) { ed in
                        Text(ed.uppercased()).tag(ed)
                    }
                }
                .labelsHidden()
            }

            HStack {
                Text("Name")
                    .frame(width: 80, alignment: .leading)
                TextField("deck-name", text: $deckName)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Character Deck", isOn: $isCharacterDeck)
        }
    }

    // MARK: - Abilities Section

    private var abilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ability Cards (\(abilities.count))")
                    .font(.headline)
                Spacer()
                Button { addAbility() } label: {
                    Label("Add Card", systemImage: "plus.circle")
                        .font(.caption)
                }
            }

            ForEach(Array(abilities.enumerated()), id: \.offset) { index, ability in
                abilityRow(index: index, ability: ability)
            }
        }
    }

    private func abilityRow(index: Int, ability: AbilityModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedAbility = expandedAbility == index ? nil : index
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expandedAbility == index ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                        Text("#\(ability.cardId ?? index)")
                            .font(.caption.monospaced())
                        if let name = ability.name, !name.isEmpty {
                            Text(name)
                                .font(.caption.bold())
                        }
                        Text("Init: \(ability.initiative)")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                        if let level = ability.level {
                            Text("Lv\(level.intValue)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive) {
                    abilities.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // Expanded detail
            if expandedAbility == index {
                abilityDetail(index: index)
            }
        }
        .padding(8)
        .background(GlavenTheme.cardBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func abilityDetail(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Card ID").font(.caption2)
                    TextField("000", value: Binding(
                        get: { abilities[index].cardId ?? 0 },
                        set: { abilities[index].cardId = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Initiative").font(.caption2)
                    TextField("00", value: $abilities[index].initiative, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Level").font(.caption2)
                    TextField("1", text: Binding(
                        get: {
                            if let lv = abilities[index].level { return "\(lv.intValue)" }
                            return ""
                        },
                        set: {
                            if let v = Int($0) { abilities[index].level = .int(v) }
                            else if $0.isEmpty { abilities[index].level = nil }
                            else { abilities[index].level = .string($0) }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }

            HStack {
                Text("Name").font(.caption2)
                TextField("Ability Name", text: Binding(
                    get: { abilities[index].name ?? "" },
                    set: { abilities[index].name = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 16) {
                Toggle("Shuffle", isOn: Binding(
                    get: { abilities[index].shuffle ?? false },
                    set: { abilities[index].shuffle = $0 ? true : nil }
                )).toggleStyle(.switch).font(.caption)

                Toggle("Lost", isOn: Binding(
                    get: { abilities[index].lost ?? false },
                    set: { abilities[index].lost = $0 ? true : nil }
                )).toggleStyle(.switch).font(.caption)

                Toggle("Persistent", isOn: Binding(
                    get: { abilities[index].persistent ?? false },
                    set: { abilities[index].persistent = $0 ? true : nil }
                )).toggleStyle(.switch).font(.caption)

                Toggle("Round", isOn: Binding(
                    get: { abilities[index].round ?? false },
                    set: { abilities[index].round = $0 ? true : nil }
                )).toggleStyle(.switch).font(.caption)
            }

            if let xp = abilities[index].xp {
                HStack {
                    Text("XP").font(.caption2)
                    Text("\(xp)")
                        .font(.caption)
                }
            }

            // Top actions
            actionsEditor(label: "Actions", actions: Binding(
                get: { abilities[index].actions ?? [] },
                set: { abilities[index].actions = $0.isEmpty ? nil : $0 }
            ))

            // Bottom actions (character decks)
            if isCharacterDeck {
                actionsEditor(label: "Bottom Actions", actions: Binding(
                    get: { abilities[index].bottomActions ?? [] },
                    set: { abilities[index].bottomActions = $0.isEmpty ? nil : $0 }
                ))
            }
        }
        .padding(.leading, 8)
    }

    private func actionsEditor(label: String, actions: Binding<[ActionModel]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption.bold())
                Spacer()
                Button {
                    actions.wrappedValue.append(ActionModel(type: .attack))
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }

            ForEach(Array(actions.wrappedValue.enumerated()), id: \.offset) { idx, _ in
                ActionEditorView(
                    action: Binding(
                        get: { actions.wrappedValue[idx] },
                        set: { actions.wrappedValue[idx] = $0 }
                    ),
                    onDelete: {
                        actions.wrappedValue.remove(at: idx)
                    }
                )
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
                Button {
                    exportJSON()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
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

    private func addAbility() {
        let nextId = (abilities.map { $0.cardId ?? 0 }.max() ?? 0) + 1
        abilities.append(AbilityModel(cardId: nextId, initiative: 0))
        expandedAbility = abilities.count - 1
    }

    private func loadDeck(_ deck: DeckData) {
        deckName = deck.name
        deckEdition = deck.edition
        isCharacterDeck = deck.character ?? false
        abilities = deck.abilities
        expandedAbility = nil
    }

    private func updateJSON() {
        let deck = DeckData(
            name: deckName.isEmpty ? "unnamed" : deckName,
            edition: deckEdition,
            character: isCharacterDeck ? true : nil,
            abilities: abilities
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(deck),
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
            let deck = try JSONDecoder().decode(DeckData.self, from: data)
            deckName = deck.name
            isCharacterDeck = deck.character ?? false
            abilities = deck.abilities
            jsonError = nil
        } catch {
            jsonError = "Parse error: \(error.localizedDescription)"
        }
    }

    private func exportJSON() {
        copyToClipboard(jsonOutput)
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
