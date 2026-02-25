import SwiftUI

struct CharacterItemsView: View {
    @Bindable var character: GameCharacter
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
                        itemRow(item: item, slot: slot)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(item: ItemData, slot: ItemSlot) -> some View {
        let key = item.itemKey
        let isSpent = character.spentItems.contains(key)
        let isConsumed = character.consumedItems.contains(key)
        let isUsable = item.spent || item.consumed
        let dim = isConsumed ? 0.3 : (isSpent ? 0.55 : 1.0)

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
            .opacity(dim)

            Text(item.name)
                .font(.caption)
                .foregroundStyle(GlavenTheme.primaryText)
                .lineLimit(1)
                .opacity(dim)

            Spacer(minLength: 0)

            // State badges
            if isConsumed {
                Image(systemName: "flame.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if isSpent {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isUsable else { return }
            gameManager.pushUndoState()
            if item.spent && !item.consumed {
                // Pure spent item: toggle spent
                if isSpent { character.spentItems.remove(key) }
                else { character.spentItems.insert(key) }
            } else if item.consumed && !item.spent {
                // Pure consumed item: toggle consumed
                if isConsumed { character.consumedItems.remove(key) }
                else { character.consumedItems.insert(key) }
            } else if item.spent {
                // Both flags: tap cycles active → spent → consumed → active
                if isConsumed {
                    character.consumedItems.remove(key)
                } else if isSpent {
                    character.spentItems.remove(key)
                    character.consumedItems.insert(key)
                } else {
                    character.spentItems.insert(key)
                }
            }
        }
        .contextMenu {
            if item.spent {
                Button {
                    gameManager.pushUndoState()
                    if isSpent { character.spentItems.remove(key) }
                    else { character.spentItems.insert(key) }
                } label: {
                    Label(isSpent ? "Refresh Item" : "Spend Item",
                          systemImage: isSpent ? "arrow.clockwise" : "arrow.clockwise.circle")
                }
            }
            if item.consumed {
                Button {
                    gameManager.pushUndoState()
                    if isConsumed { character.consumedItems.remove(key) }
                    else { character.consumedItems.insert(key) }
                } label: {
                    Label(isConsumed ? "Restore Item" : "Consume Item",
                          systemImage: isConsumed ? "flame.slash" : "flame.circle")
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
