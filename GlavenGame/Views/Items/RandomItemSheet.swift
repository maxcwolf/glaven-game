import SwiftUI

struct RandomItemSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var drawnItem: ItemData?
    @State private var selectedSlot: ItemSlot?

    private var edition: String {
        gameManager.game.edition ?? "gh"
    }

    private var randomPool: [ItemData] {
        var items = gameManager.editionStore.items(for: edition).filter { $0.random }
        if let slot = selectedSlot {
            items = items.filter { $0.slot == slot }
        }
        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Slot filter
                slotFilter

                Spacer()

                // Drawn item
                if let item = drawnItem {
                    drawnItemView(item)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "gift")
                            .font(.system(size: 48))
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("Draw a random item")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("\(randomPool.count) items in pool")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Spacer()

                // Draw button
                Button {
                    drawRandomItem()
                } label: {
                    Label("Draw Item", systemImage: "dice.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(!randomPool.isEmpty ? GlavenTheme.accentText.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                        .foregroundStyle(!randomPool.isEmpty ? GlavenTheme.accentText : GlavenTheme.secondaryText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(randomPool.isEmpty)
                .padding(.bottom)
            }
            .background(GlavenTheme.background)
            .navigationTitle("Random Item")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 420)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var slotFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                slotChip(nil, label: "All")
                ForEach(ItemSlot.allCases, id: \.self) { slot in
                    slotChip(slot, label: slot.displayName)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func slotChip(_ slot: ItemSlot?, label: String) -> some View {
        let isSelected = selectedSlot == slot
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSlot = slot
                drawnItem = nil
            }
        } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? GlavenTheme.accentText.opacity(0.2) : GlavenTheme.primaryText.opacity(0.08))
                .foregroundStyle(isSelected ? GlavenTheme.accentText : GlavenTheme.secondaryText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func drawnItemView(_ item: ItemData) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: item.slot.icon)
                    .foregroundStyle(GlavenTheme.accentText)
                Text("#\(item.id)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            Text(item.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.primaryText)

            HStack(spacing: 16) {
                Label("\(item.cost)g", systemImage: "dollarsign.circle")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
                Label(item.slot.displayName, systemImage: item.slot.icon)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            if item.spent {
                Label("Spent on use", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if item.consumed {
                Label("Consumed on use", systemImage: "flame")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func drawRandomItem() {
        guard !randomPool.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            drawnItem = randomPool.randomElement()
        }
    }
}
