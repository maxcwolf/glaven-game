import SwiftUI

struct ScenarioStatsView: View {
    @Environment(GameManager.self) private var gameManager

    private var characters: [GameCharacter] {
        gameManager.game.characters
    }

    var body: some View {
        if !characters.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Character Stats")
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .padding(.bottom, 2)

                ForEach(characters, id: \.name) { character in
                    let stats = gameManager.scenarioStatsManager.stats(for: character.name)
                    CharacterStatRow(character: character, stats: stats)
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct CharacterStatRow: View {
    let character: GameCharacter
    let stats: ScenarioCharacterStats

    private var displayName: String {
        character.name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(GlavenTheme.primaryText)
                Spacer()
                if stats.exhausted {
                    Text("Exhausted")
                        .font(.caption2)
                        .foregroundStyle(Color.red)
                }
            }

            HStack(spacing: 12) {
                statItem(icon: "bolt.circle", value: stats.damageDealt, label: "Dmg")
                statItem(icon: "heart.circle", value: stats.healsGiven, label: "Heal")
                statItem(icon: "xmark.circle", value: stats.kills, label: "Kills")
                statItem(icon: "dollarsign.circle", value: stats.coinsLooted, label: "Coins")
                statItem(icon: "clock.circle", value: stats.roundsSurvived, label: "Rnds")
            }
            .font(.caption2)
            .foregroundStyle(GlavenTheme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    private func statItem(icon: String, value: Int, label: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text("\(value)")
                .monospacedDigit()
        }
    }
}
