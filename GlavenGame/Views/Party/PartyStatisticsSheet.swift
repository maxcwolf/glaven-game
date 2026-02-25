import SwiftUI

struct PartyStatisticsSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var game: GameState { gameManager.game }

    private var totalGold: Int {
        game.characters.reduce(0) { $0 + $1.loot }
    }

    private var totalXP: Int {
        game.characters.reduce(0) { $0 + $1.experience }
    }

    private var totalItems: Int {
        game.characters.reduce(0) { $0 + $1.items.count }
    }

    private var totalPerks: Int {
        game.characters.reduce(0) { $0 + $1.selectedPerks.reduce(0, +) }
    }

    private var averageLevel: Double {
        guard !game.characters.isEmpty else { return 0 }
        return Double(game.characters.reduce(0) { $0 + $1.level }) / Double(game.characters.count)
    }

    private var completedCount: Int {
        game.completedScenarios.count
    }

    private var achievementCount: Int {
        game.globalAchievements.count + game.partyAchievements.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Party overview
                    overviewGrid

                    // Character breakdown
                    if !game.characters.isEmpty {
                        characterBreakdown
                    }

                    // Campaign stats
                    campaignStats
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Party Statistics")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var overviewGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            statCard("Characters", value: "\(game.characters.count)", icon: "person.fill", color: .blue)
            statCard("Avg Level", value: String(format: "%.1f", averageLevel), icon: "arrow.up.circle", color: .green)
            statCard("Total Gold", value: "\(totalGold)", icon: "dollarsign.circle.fill", color: .yellow)
            statCard("Total XP", value: "\(totalXP)", icon: "star.fill", color: .blue)
            statCard("Total Items", value: "\(totalItems)", icon: "bag.fill", color: .orange)
            statCard("Total Perks", value: "\(totalPerks)", icon: "checkmark.circle.fill", color: .purple)
        }
    }

    @ViewBuilder
    private func statCard(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(GlavenTheme.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var characterBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Character Breakdown")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            ForEach(game.characters, id: \.id) { char in
                HStack(spacing: 10) {
                    ThumbnailImage(
                        image: ImageLoader.characterThumbnail(edition: char.edition, name: char.name),
                        size: 32,
                        cornerRadius: 6,
                        fallbackColor: Color(hex: char.color) ?? .blue
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(char.title.isEmpty ? char.name.replacingOccurrences(of: "-", with: " ").capitalized : char.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(GlavenTheme.primaryText)
                        Text("Lv \(char.level)")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        miniStat(value: "\(char.loot)", color: .yellow)
                        miniStat(value: "\(char.experience)", color: .blue)
                        miniStat(value: "\(char.items.count)", color: .orange)
                    }
                }
                .padding(10)
                .background(GlavenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func miniStat(value: String, color: Color) -> some View {
        Text(value)
            .font(.caption)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(color)
    }

    @ViewBuilder
    private var campaignStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Campaign")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            HStack(spacing: 12) {
                campaignRow(icon: "map.fill", label: "Scenarios Completed", value: "\(completedCount)", color: GlavenTheme.accentText)
            }
            campaignRow(icon: "trophy.circle", label: "Achievements", value: "\(achievementCount)", color: .orange)
            campaignRow(icon: "building.2.crop.circle", label: "Prosperity", value: "\(game.partyProsperity)", color: .green)
            campaignRow(icon: "person.2.circle", label: "Reputation", value: "\(game.partyReputation)", color: reputationColor)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func campaignRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.primaryText)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var reputationColor: Color {
        game.partyReputation >= 0 ? .blue : .red
    }
}
