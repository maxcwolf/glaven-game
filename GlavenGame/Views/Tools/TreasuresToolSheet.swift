import SwiftUI

/// Standalone Treasures browser for viewing treasure rewards by edition.
struct TreasuresToolSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEdition: String = "gh"

    private var editions: [String] {
        gameManager.editionStore.editions.map(\.edition)
    }

    private var treasures: [(index: Int, reward: String)] {
        let rewards = gameManager.editionStore.treasures(for: selectedEdition)
        return rewards.enumerated().map { (index: $0.offset + 1, reward: $0.element) }
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

                    Text("\(treasures.count) treasures")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(GlavenTheme.cardBackground)

                List {
                    ForEach(treasures, id: \.index) { treasure in
                        HStack(alignment: .top, spacing: 12) {
                            Text("#\(treasure.index)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(.yellow)
                                .frame(width: 40, alignment: .trailing)

                            Text(treasure.reward)
                                .font(.subheadline)
                                .foregroundStyle(GlavenTheme.primaryText)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .background(GlavenTheme.background)
            .navigationTitle("Treasures")
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
}
