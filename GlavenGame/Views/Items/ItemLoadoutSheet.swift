import SwiftUI

/// What a character brings to the next scenario (GH p.9): every item they own, each brought or
/// left at home, within one head, body and legs item, two hands and half their level (rounded up)
/// in small items.
struct ItemLoadoutSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    let character: GameCharacter
    /// Off for snapshots: ImageRenderer draws neither scroll views nor navigation stacks.
    var scrolls = true

    private var store: EditionDataStore { gameManager.editionStore }

    private var owned: [ItemData] {
        character.items.compactMap { store.itemData(key: $0) }
    }

    var body: some View {
        if scrolls {
            NavigationStack {
                ScrollView { content }
                    .background(BoardTheme.sheet)
                    .navigationTitle("Items — \(GameText.characterName(character, labels: store))")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
        } else {
            content.background(BoardTheme.sheet)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Self.limitsLine(for: character, store: store))
                .font(.subheadline)
                .foregroundStyle(BoardTheme.secondaryText)
            if owned.isEmpty {
                Text("No items yet. Buy some in the shop.")
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            ForEach(ItemSlot.allCases, id: \.self) { slot in
                let items = owned.filter { $0.slot == slot }
                if !items.isEmpty {
                    Text(slot.displayName.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BoardTheme.brass)
                    ForEach(items) { item in row(item) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: ItemData) -> some View {
        let bringing = !character.itemsLeftBehind.contains(item.itemKey)
        let problem = bringing ? nil : gameManager.itemManager.bringingProblem(item.itemKey, for: character)
        return HStack(spacing: 12) {
            Image(systemName: item.slot.icon)
                .foregroundStyle(bringing ? BoardTheme.brass : BoardTheme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(bringing ? BoardTheme.text : BoardTheme.secondaryText)
                Text(bringing ? "Brought" : problem.map { "At home · \($0.text)" } ?? "At home")
                    .font(.caption)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            Spacer()
            Toggle("Bring \(item.name)", isOn: Binding(
                get: { bringing },
                set: { gameManager.itemManager.setBringing(item.itemKey, $0, for: character) }))
                .labelsHidden()
                .tint(BoardTheme.brass)
                .disabled(problem != nil)
        }
        .padding(12)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
    }

    /// "Bringing 3 of 4 items · up to 1 small item at level 2".
    static func limitsLine(for character: GameCharacter, store: EditionDataStore) -> String {
        let small = ItemLoadout.smallItemLimit(level: character.level, carrying: character.carriedItems)
        let brought = character.carriedItems.count
        return "Bringing \(brought) of \(character.items.count) item\(character.items.count == 1 ? "" : "s")"
            + " · up to \(small) small item\(small == 1 ? "" : "s") at level \(character.level)"
    }
}
