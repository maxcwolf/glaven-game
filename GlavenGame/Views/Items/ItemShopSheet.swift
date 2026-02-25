import SwiftUI

struct ItemShopSheet: View {
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedSlot: ItemSlot?
    @State private var selectedItem: ItemData?

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var prosperityLevel: Int {
        let thresholds = [0, 4, 9, 15, 22, 30, 39, 49, 64]
        for i in stride(from: thresholds.count - 1, through: 0, by: -1) {
            if gameManager.game.partyProsperity >= thresholds[i] { return i + 1 }
        }
        return 1
    }

    private var availableItems: [ItemData] {
        let allItems = gameManager.editionStore.availableItems(for: edition, prosperity: prosperityLevel)
        var filtered = allItems

        if let slot = selectedSlot {
            filtered = filtered.filter { $0.slot == slot }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered.sorted { $0.id < $1.id }
    }

    private func isOwned(_ item: ItemData) -> Bool {
        character.items.contains(item.itemKey)
    }

    private func canAfford(_ item: ItemData) -> Bool {
        character.loot >= item.cost
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Slot filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        slotFilterButton(nil, label: "All")
                        ForEach(ItemSlot.allCases, id: \.self) { slot in
                            slotFilterButton(slot, label: slot.displayName)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Gold display
                HStack {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(character.loot) Gold")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Spacer()
                    Text("Prosperity \(prosperityLevel)")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Item list
                List {
                    ForEach(availableItems) { item in
                        ItemRow(item: item, isOwned: isOwned(item), canAfford: canAfford(item)) {
                            if isOwned(item) {
                                // Sell
                                SoundPlayer.play(.coin)
                                gameManager.pushUndoState()
                                character.items.removeAll { $0 == item.itemKey }
                                character.loot += item.cost / 2
                            } else if canAfford(item) {
                                // Buy
                                SoundPlayer.play(.coin)
                                gameManager.pushUndoState()
                                character.items.append(item.itemKey)
                                character.loot -= item.cost
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search items...")
            .navigationTitle("Item Shop")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailSheet(item: item)
            }
        }
    }

    @ViewBuilder
    private func slotFilterButton(_ slot: ItemSlot?, label: String) -> some View {
        Button {
            selectedSlot = slot
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selectedSlot == slot ? GlavenTheme.accentText.opacity(0.3) : GlavenTheme.primaryText.opacity(0.08))
                .foregroundStyle(selectedSlot == slot ? GlavenTheme.accentText : GlavenTheme.primaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ItemRow: View {
    let item: ItemData
    let isOwned: Bool
    let canAfford: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Item card thumbnail with texture
            itemCardThumbnail

            // Item info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("#\(item.id)")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Text(item.name)
                        .font(GlavenFont.title(size: 15))
                }

                HStack(spacing: 8) {
                    Text(item.slot.displayName)
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)

                    if item.spent {
                        Text("Spent")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    if item.consumed {
                        Text("Consumed")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            // Cost
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("\(item.cost)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            }

            // Buy/Sell button
            Button(action: action) {
                Text(isOwned ? "Sell" : "Buy")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isOwned ? Color.orange.opacity(0.3) : (canAfford ? Color.green.opacity(0.3) : Color.gray.opacity(0.2)))
                    .foregroundStyle(isOwned ? .orange : (canAfford ? .green : Color.secondary))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isOwned && !canAfford)
        }
        .padding(.vertical, 4)
        .opacity(isOwned ? 1.0 : (canAfford ? 1.0 : 0.5))
    }

    @ViewBuilder
    private var itemCardThumbnail: some View {
        ZStack {
            if let img = ImageLoader.itemCardFront() {
                #if os(macOS)
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #else
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(slotColor.opacity(0.15))
            }

            // Slot icon overlay
            Image(systemName: item.slot.icon)
                .font(.system(size: 16))
                .foregroundStyle(slotColor)
        }
        .frame(width: 42, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isOwned ? Color.green.opacity(0.6) : GlavenTheme.primaryText.opacity(0.1), lineWidth: isOwned ? 2 : 1)
        )
    }

    private var slotColor: Color {
        switch item.slot {
        case .head: return .cyan
        case .body: return .blue
        case .legs: return .green
        case .onehand: return .orange
        case .twohand: return .red
        case .small: return .purple
        }
    }
}
