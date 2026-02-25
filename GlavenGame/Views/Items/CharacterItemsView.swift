import SwiftUI

struct CharacterItemsView: View {
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var equippedItems: [ItemData] {
        character.items.compactMap { key in
            let parts = key.split(separator: "-", maxSplits: 1)
            guard parts.count == 2,
                  let id = Int(parts[1]) else { return nil }
            return gameManager.editionStore.itemData(id: id, edition: String(parts[0]))
        }
    }

    private var slotGroups: [(ItemSlot, [ItemData])] {
        let grouped = Dictionary(grouping: equippedItems, by: \.slot)
        return ItemSlot.allCases.compactMap { slot in
            guard let items = grouped[slot], !items.isEmpty else { return nil }
            return (slot, items)
        }
    }

    var body: some View {
        if equippedItems.isEmpty {
            Text("No items equipped")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(slotGroups, id: \.0) { slot, items in
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            // Mini card thumbnail
                            ZStack {
                                if let img = ImageLoader.itemCardFront() {
                                    #if os(macOS)
                                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                    #else
                                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                                    #endif
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(slotColor(slot).opacity(0.15))
                                }
                                Image(systemName: slot.icon)
                                    .font(.system(size: 8))
                                    .foregroundStyle(slotColor(slot))
                            }
                            .frame(width: 18, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                            Text(item.name)
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.primaryText)
                                .lineLimit(1)
                            if item.spent {
                                Image(systemName: "arrow.clockwise.circle")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                            }
                            if item.consumed {
                                Image(systemName: "flame.circle")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
        }
    }

    private func slotColor(_ slot: ItemSlot) -> Color {
        switch slot {
        case .head: return .cyan
        case .body: return .blue
        case .legs: return .green
        case .onehand: return .orange
        case .twohand: return .red
        case .small: return .purple
        }
    }
}
