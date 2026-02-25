import SwiftUI

/// Editor for creating/editing monster data with per-level stats.
struct MonsterEditorSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var monsterName: String = ""
    @State private var monsterEdition: String = "gh"
    @State private var monsterDeck: String = ""
    @State private var isBoss: Bool = false
    @State private var isFlying: Bool = false
    @State private var isHidden: Bool = false
    @State private var standeeCount: Int = 6
    @State private var selectedLevel: Int = 0
    @State private var editAllLevels: Bool = false
    @State private var stats: [MonsterStatModel] = []
    @State private var jsonOutput: String = ""
    @State private var jsonInput: String = ""
    @State private var jsonError: String?

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var existingMonsters: [MonsterData] {
        gameManager.editionStore.monsters(for: monsterEdition)
    }

    var body: some View {
        NavigationStack {
            HSplitOrVStack {
                // Input side
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        propertiesSection
                        levelSelector
                        statsSection
                    }
                    .padding()
                }
                .frame(minWidth: 340)

                Divider()

                // JSON output
                jsonOutputSection
            }
            .background(GlavenTheme.background)
            .navigationTitle("Monster Editor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(existingMonsters) { monster in
                            Button(monster.name.replacingOccurrences(of: "-", with: " ").capitalized) {
                                loadMonster(monster)
                            }
                        }
                    } label: {
                        Label("Load", systemImage: "folder")
                    }
                    .disabled(existingMonsters.isEmpty)
                }
            }
            .onAppear { initializeStats(); updateJSON() }
        }
    }

    // MARK: - Properties

    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monster Properties")
                .font(.headline)

            HStack {
                Text("Edition")
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $monsterEdition) {
                    ForEach(editions, id: \.self) { ed in
                        Text(ed.uppercased()).tag(ed)
                    }
                }
                .labelsHidden()
                .onChange(of: monsterEdition) { _, _ in updateJSON() }
            }

            HStack {
                Text("Name")
                    .frame(width: 80, alignment: .leading)
                TextField("monster-name", text: $monsterName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: monsterName) { _, _ in updateJSON() }
            }

            HStack {
                Text("Deck")
                    .frame(width: 80, alignment: .leading)
                TextField("deck-name", text: $monsterDeck)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: monsterDeck) { _, _ in updateJSON() }
            }

            HStack(spacing: 16) {
                Toggle("Boss", isOn: $isBoss)
                    .onChange(of: isBoss) { _, _ in initializeStats(); updateJSON() }
                Toggle("Flying", isOn: $isFlying)
                    .onChange(of: isFlying) { _, _ in updateJSON() }
                Toggle("Hidden", isOn: $isHidden)
                    .onChange(of: isHidden) { _, _ in updateJSON() }
            }
            .font(.subheadline)

            if !isBoss {
                Stepper("Standees: \(standeeCount)", value: $standeeCount, in: 1...10)
                    .font(.subheadline)
                    .onChange(of: standeeCount) { _, _ in updateJSON() }
            }
        }
    }

    // MARK: - Level Selector

    private var levelSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level")
                    .font(.headline)
                Spacer()
                Toggle("Edit All Levels", isOn: $editAllLevels)
                    .font(.caption)
            }

            if !editAllLevels {
                Picker("Level", selection: $selectedLevel) {
                    ForEach(0...7, id: \.self) { lv in
                        Text("Lv \(lv)").tag(lv)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editAllLevels {
                ForEach(0...7, id: \.self) { level in
                    statsForLevel(level)
                }
            } else {
                statsForLevel(selectedLevel)
            }
        }
    }

    private func statsForLevel(_ level: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if editAllLevels {
                Text("Level \(level)")
                    .font(.subheadline.bold())
            }

            if isBoss {
                statFields(for: .boss, level: level)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Normal")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                        statFields(for: .normal, level: level)
                    }
                    VStack(alignment: .leading) {
                        Text("Elite")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                        statFields(for: .elite, level: level)
                    }
                }
            }

            if editAllLevels && level < 7 {
                Divider()
            }
        }
    }

    private func statFields(for type: MonsterType, level: Int) -> some View {
        let index = statIndex(type: type, level: level)
        return VStack(alignment: .leading, spacing: 6) {
            statRow(label: "HP", binding: intOrStringBinding(index: index, keyPath: \.health))
            statRow(label: "Move", binding: intOrStringBinding(index: index, keyPath: \.movement))
            statRow(label: "Attack", binding: intOrStringBinding(index: index, keyPath: \.attack))
            statRow(label: "Range", binding: intOrStringBinding(index: index, keyPath: \.range))

            // Immunities
            if let immunities = stats[safe: index]?.immunities, !immunities.isEmpty {
                HStack {
                    Text("Immune:")
                        .font(.caption2)
                    Text(immunities.map(\.rawValue).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            // Actions
            if let actions = stats[safe: index]?.actions, !actions.isEmpty {
                Text("Actions: \(actions.count)")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
    }

    private func statRow(label: String, binding: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .frame(width: 48, alignment: .leading)
            TextField("0", text: binding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .onChange(of: binding.wrappedValue) { _, _ in updateJSON() }
        }
    }

    private func intOrStringBinding(index: Int, keyPath: WritableKeyPath<MonsterStatModel, IntOrString?>) -> Binding<String> {
        Binding(
            get: {
                guard let stat = stats[safe: index] else { return "0" }
                if let val = stat[keyPath: keyPath] {
                    return val.stringValue ?? "\(val.intValue ?? 0)"
                }
                return "0"
            },
            set: { newValue in
                guard index < stats.count else { return }
                if let intVal = Int(newValue) {
                    stats[index][keyPath: keyPath] = .int(intVal)
                } else if !newValue.isEmpty {
                    stats[index][keyPath: keyPath] = .string(newValue)
                } else {
                    stats[index][keyPath: keyPath] = .int(0)
                }
            }
        )
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

    private func initializeStats() {
        if stats.isEmpty {
            stats = []
            for level in 0...7 {
                if isBoss {
                    stats.append(MonsterStatModel(type: .boss, level: level, health: .int(10 + level * 5),
                                                   movement: .int(2), attack: .int(3 + level), range: .int(0)))
                } else {
                    stats.append(MonsterStatModel(type: .normal, level: level, health: .int(4 + level * 2),
                                                   movement: .int(2), attack: .int(2 + level), range: .int(0)))
                    stats.append(MonsterStatModel(type: .elite, level: level, health: .int(6 + level * 3),
                                                   movement: .int(2), attack: .int(3 + level), range: .int(0)))
                }
            }
        }
    }

    private func statIndex(type: MonsterType, level: Int) -> Int {
        stats.firstIndex(where: { ($0.type ?? .normal) == type && ($0.level ?? 0) == level }) ?? 0
    }

    private func loadMonster(_ monster: MonsterData) {
        monsterName = monster.name
        monsterEdition = monster.edition
        monsterDeck = monster.deck ?? monster.name
        isBoss = monster.isBoss
        isFlying = monster.flying ?? false
        isHidden = monster.hidden ?? false
        standeeCount = monster.maxCount
        stats = monster.stats
        selectedLevel = 0
    }

    private func updateJSON() {
        var monsterData = MonsterData(
            name: monsterName.isEmpty ? "unnamed" : monsterName,
            edition: monsterEdition,
            stats: stats
        )
        if !monsterDeck.isEmpty { monsterData.deck = monsterDeck }
        if isBoss { monsterData.boss = true }
        if isFlying { monsterData.flying = true }
        if isHidden { monsterData.hidden = true }
        if !isBoss { monsterData.count = .int(standeeCount) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(monsterData),
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
            let monster = try JSONDecoder().decode(MonsterData.self, from: data)
            monsterName = monster.name
            monsterDeck = monster.deck ?? ""
            isBoss = monster.isBoss
            isFlying = monster.flying ?? false
            isHidden = monster.hidden ?? false
            standeeCount = monster.maxCount
            stats = monster.stats
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

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
