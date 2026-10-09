import SwiftUI

struct ItemShopSheet: View {
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedSlot: ItemSlot?
    @State private var selectedItem: ItemData?
    /// An owned item the player tapped Sell on, waiting for them to confirm.
    @State private var pendingSale: ItemData?

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var prosperityLevel: Int { gameManager.game.prosperityLevel }

    /// The city's supply, plus anything the character owns so it can be sold back.
    private var availableItems: [ItemData] {
        var filtered = gameManager.itemManager.availableItems()
        let supply = Set(filtered.map(\.itemKey))
        filtered += gameManager.editionStore.items(for: edition).filter {
            isOwned($0) && !supply.contains($0.itemKey)
        }

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

    /// Whether the character can buy it now: affordable, in stock and not already theirs.
    private func canAfford(_ item: ItemData) -> Bool {
        gameManager.itemManager.purchaseProblem(item, for: character) == nil
    }

    /// Every copy of the item is owned by someone in the party.
    private func isSoldOut(_ item: ItemData) -> Bool {
        !gameManager.itemManager.inStock(item)
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
                    let modifier = ItemManager.reputationPriceModifier(gameManager.game.partyReputation)
                    if modifier != 0 {
                        Text("Reputation: prices \(modifier > 0 ? "+" : "\u{2212}")\(abs(modifier))")
                            .font(.caption)
                            .foregroundStyle(modifier < 0 ? GlavenTheme.positive : GlavenTheme.secondaryText)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // Item list
                List {
                    ForEach(availableItems) { item in
                        let owned = isOwned(item)
                        ItemRow(item: item, isOwned: owned, canAfford: canAfford(item), soldOut: isSoldOut(item),
                                price: owned ? gameManager.itemManager.salePrice(item) : gameManager.itemManager.price(item)) {
                            // Selling asks first: Buy and Sell share a spot, so a double tap
                            // would otherwise sell what was just bought at half price.
                            if owned {
                                pendingSale = item
                            } else if gameManager.itemManager.buy(item, for: character) {
                                BoardSoundPlayer.play(.loot)
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
            .confirmationDialog(pendingSale.map { "Sell \($0.name) for \(gameManager.itemManager.salePrice($0)) gold?" } ?? "",
                                isPresented: Binding(get: { pendingSale != nil }, set: { if !$0 { pendingSale = nil } }),
                                titleVisibility: .visible) {
                if let item = pendingSale {
                    Button("Sell for \(gameManager.itemManager.salePrice(item)) Gold", role: .destructive) {
                        if gameManager.itemManager.sell(item, for: character) { BoardSoundPlayer.play(.loot) }
                        pendingSale = nil
                    }
                }
                Button("Keep It", role: .cancel) { pendingSale = nil }
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
    let soldOut: Bool
    /// The price to buy it, or (owned) what selling it pays.
    let price: Int
    let action: () -> Void

    private var canBuy: Bool { canAfford && !soldOut }

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
                Text("\(price)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            }

            // Buy/Sell button
            Button(action: action) {
                Text(isOwned ? "Sell" : (soldOut ? "Sold Out" : "Buy"))
                    .accessibilityLabel(isOwned ? "Sell for \(price) gold" : (soldOut ? "Sold out" : "Buy for \(price) gold"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isOwned ? Color.orange.opacity(0.3) : (canBuy ? Color.green.opacity(0.3) : Color.gray.opacity(0.2)))
                    .foregroundStyle(isOwned ? .orange : (canBuy ? .green : Color.secondary))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isOwned && !canBuy)
        }
        .padding(.vertical, 4)
        .opacity(isOwned ? 1.0 : (canBuy ? 1.0 : 0.5))
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
