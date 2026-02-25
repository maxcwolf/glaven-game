import SwiftUI

struct ItemBrowserSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedSlot: ItemSlot?
    @State private var selectedItem: ItemData?
    @State private var showAllItems = false

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var allItems: [ItemData] {
        if showAllItems {
            return gameManager.editionStore.items(for: edition).filter { !$0.random }
        }
        return gameManager.itemManager.availableItems()
    }

    private var filteredItems: [ItemData] {
        var items = allItems

        if let slot = selectedSlot {
            items = items.filter { $0.slot == slot }
        }

        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        return items.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                countBar
                itemList
            }
            .searchable(text: $searchText, prompt: "Search items...")
            .navigationTitle("Item Browser")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(showAllItems ? "Available" : "Show All") {
                        showAllItems.toggle()
                    }
                    .font(.caption)
                }
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailSheet(item: item)
            }
        }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                slotButton(nil, label: "All")
                ForEach(ItemSlot.allCases, id: \.self) { slot in
                    slotButton(slot, label: slot.displayName)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var countBar: some View {
        HStack {
            Text("Prosperity \(gameManager.game.partyProsperity)")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
            Text("\(filteredItems.count) items")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    // MARK: - Item List

    @ViewBuilder
    private var itemList: some View {
        List(filteredItems) { item in
            Button {
                selectedItem = item
            } label: {
                itemRow(item)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func itemRow(_ item: ItemData) -> some View {
        let owned = gameManager.itemManager.ownedCount(item)
        let inStock = owned < item.count

        HStack(spacing: 10) {
            Image(systemName: item.slot.icon)
                .font(.system(size: 16))
                .foregroundStyle(slotColor(item.slot))
                .frame(width: 28, height: 28)
                .background(slotColor(item.slot).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("#\(item.id)")
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
                HStack(spacing: 6) {
                    Text(item.slot.displayName)
                        .font(.caption2)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    if item.spent {
                        Text("Spent")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if item.consumed {
                        Text("Consumed")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if owned > 0 {
                        Text("\(owned)/\(item.count) owned")
                            .font(.caption2)
                            .foregroundStyle(inStock ? .green : .red)
                    }
                }
            }

            Spacer()

            HStack(spacing: 2) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("\(item.cost)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func slotButton(_ slot: ItemSlot?, label: String) -> some View {
        Button {
            selectedSlot = slot
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedSlot == slot ? GlavenTheme.accentText.opacity(0.3) : GlavenTheme.primaryText.opacity(0.08))
                .foregroundStyle(selectedSlot == slot ? GlavenTheme.accentText : GlavenTheme.primaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func slotColor(_ slot: ItemSlot) -> Color {
        switch slot {
        case .head: return .purple
        case .body: return .blue
        case .legs: return .green
        case .onehand: return .orange
        case .twohand: return .red
        case .small: return .cyan
        }
    }
}
