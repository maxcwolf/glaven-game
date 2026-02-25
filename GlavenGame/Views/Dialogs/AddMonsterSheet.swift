import SwiftUI

struct AddMonsterSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var existingNames: Set<String> {
        Set(gameManager.game.monsters.map(\.name))
    }

    private var allMonsters: [MonsterData] {
        guard let edition = gameManager.game.edition else { return [] }
        return gameManager.editionStore.monsters(for: edition)
            .filter { !($0.hidden ?? false) && !($0.spoiler ?? false) }
            .sorted { $0.name < $1.name }
    }

    private var filteredMonsters: [MonsterData] {
        guard !searchText.isEmpty else { return allMonsters }
        let query = searchText.lowercased()
        return allMonsters.filter {
            $0.name.replacingOccurrences(of: "-", with: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredMonsters) { monster in
                        let isAdded = existingNames.contains(monster.name)
                        monsterRow(monster, isAdded: isAdded)
                        if monster.id != filteredMonsters.last?.id {
                            Divider().background(GlavenTheme.primaryText.opacity(0.1))
                        }
                    }
                }
            }
            .background(GlavenTheme.background)
            .searchable(text: $searchText, prompt: "Search monsters")
            .navigationTitle("Add Monster")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 450)
    }

    @ViewBuilder
    private func monsterRow(_ monster: MonsterData, isAdded: Bool) -> some View {
        Button {
            if !isAdded, let edition = gameManager.game.edition {
                gameManager.monsterManager.addMonster(name: monster.name, edition: edition)
            }
        } label: {
            HStack(spacing: 12) {
                ThumbnailImage(
                    image: ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name),
                    size: 36,
                    cornerRadius: 6,
                    fallbackColor: monster.isBoss ? GlavenTheme.boss.opacity(0.5) : .gray
                )
                Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isAdded ? Color.secondary : GlavenTheme.primaryText)
                Spacer()
                Text(monster.isBoss ? "Boss" : "Count: \(monster.maxCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(GlavenTheme.positive)
                        .font(.title3)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .opacity(isAdded ? 0.5 : 1.0)
    }
}
