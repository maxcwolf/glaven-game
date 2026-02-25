import SwiftUI

struct LootApplySheet: View {
    let loot: Loot
    let playerCount: Int
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var activeCharacters: [GameCharacter] {
        gameManager.game.characters.filter { !$0.exhausted && !$0.absent }
    }

    private var lootValue: Int {
        gameManager.lootManager.getValue(for: loot)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                drawnCard
                characterList
            }
            .padding()
            .navigationTitle("Apply Loot")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var drawnCard: some View {
        HStack(spacing: 12) {
            LootCardView(loot: loot, playerCount: playerCount)
                .frame(width: 80, height: 72)
                .background(GlavenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(lootTypeName)
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)
                Text("Value: \(lootValue)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(GlavenTheme.primaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var characterList: some View {
        if activeCharacters.isEmpty {
            Text("No active characters")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(activeCharacters, id: \.name) { character in
                        characterRow(character)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func characterRow(_ character: GameCharacter) -> some View {
        HStack(spacing: 12) {
            ThumbnailImage(
                image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                size: 36
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(GlavenTheme.primaryText)
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("\(character.loot)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Apply") {
                gameManager.lootManager.applyLoot(loot, to: character)
                gameManager.scenarioStatsManager.recordCoinsLooted(
                    by: character.name, amount: lootValue
                )
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var lootTypeName: String {
        switch loot.type {
        case .money: return "Gold"
        case .random_item: return "Random Item"
        case .special1, .special2: return "Special"
        default: return loot.type.rawValue.capitalized
        }
    }
}
