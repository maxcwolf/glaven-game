import SwiftUI

/// Standalone Random Monster Cards tool for viewing random monster card sections by edition.
struct RandomMonsterCardsToolSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEdition: String = "gh"

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var randomMonsterSections: [ScenarioData] {
        gameManager.editionStore.sections(for: selectedEdition)
            .filter { $0.group == "randomMonsterCard" }
            .sorted { $0.index < $1.index }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Edition", selection: $selectedEdition) {
                        ForEach(editions, id: \.self) { edition in
                            Text(edition.uppercased()).tag(edition)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Text("\(randomMonsterSections.count) cards")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(GlavenTheme.cardBackground)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if randomMonsterSections.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                    .font(.largeTitle)
                                    .foregroundStyle(GlavenTheme.secondaryText.opacity(0.3))
                                Text("No random monster cards for this edition")
                                    .font(.subheadline)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }

                        ForEach(randomMonsterSections) { section in
                            sectionRow(section)
                        }
                    }
                    .padding()
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Random Monster Cards")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionRow(_ section: ScenarioData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(section.index)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                if !section.name.isEmpty {
                    Text(section.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GlavenTheme.primaryText)
                }

                Spacer()
            }

            // Show monsters that would be spawned
            if let rooms = section.rooms {
                ForEach(rooms.indices, id: \.self) { roomIdx in
                    let room = rooms[roomIdx]
                    if let monsters = room.monster, !monsters.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(monsters.indices, id: \.self) { mIdx in
                                let monster = monsters[mIdx]
                                HStack(spacing: 6) {
                                    Image(systemName: "pawprint.fill")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                    Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundStyle(GlavenTheme.primaryText)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
