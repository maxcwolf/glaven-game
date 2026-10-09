import SwiftUI

struct PartySheetView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingName = false
    @State private var nameText = ""
    @State private var showStatistics = false

    private var game: GameState { gameManager.game }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Party Name
                    partyNameSection

                    // Reputation Track
                    trackSection(
                        title: "Reputation",
                        value: game.partyReputation,
                        range: -20...20,
                        icon: "person.2.circle",
                        color: reputationColor
                    )

                    // Prosperity Track
                    trackSection(
                        title: "Prosperity",
                        value: game.partyProsperity,
                        range: 0...64,
                        icon: "building.2.crop.circle",
                        color: .green
                    )

                    // Prosperity Level
                    prosperityLevelSection

                    // Achievements
                    if !game.globalAchievements.isEmpty {
                        achievementSection(title: "Global Achievements", achievements: game.globalAchievements, icon: "trophy.circle", color: .orange)
                    }

                    if !game.partyAchievements.isEmpty {
                        achievementSection(title: "Party Achievements", achievements: game.partyAchievements, icon: "flag.circle", color: .mint)
                    }

                    if !game.campaignStickers.isEmpty {
                        achievementSection(title: "Campaign Stickers", achievements: game.campaignStickers, icon: "seal", color: .purple)
                    }

                    // Campaign Progress
                    if game.edition != nil {
                        campaignProgressSection
                    }

                    // Completed Scenarios
                    if !game.completedScenarios.isEmpty {
                        completedScenariosSection
                    }

                    // Characters Summary
                    charactersSummarySection

                    // What happened, newest first
                    if !game.campaignLog.isEmpty {
                        campaignLogSection
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Campaign")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showStatistics = true } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                }
            }
            .sheet(isPresented: $showStatistics) {
                PartyStatisticsSheet()
            }
        }
    }

    // MARK: - Party Name

    @ViewBuilder
    private var partyNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Party Name")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)

            if editingName {
                HStack {
                    TextField("Enter party name", text: $nameText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        gameManager.game.partyName = nameText
                        editingName = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Text(game.partyName.isEmpty ? "Unnamed Party" : game.partyName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(game.partyName.isEmpty ? Color.secondary : .primary)
                    Spacer()
                    Button {
                        nameText = game.partyName
                        editingName = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(GlavenTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Track Section

    @ViewBuilder
    /// Reputation and prosperity are earned in scenarios and events, so they're shown, not edited.
    private func trackSection(title: String, value: Int, range: ClosedRange<Int>, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }

            // Visual track
            GeometryReader { geo in
                let fraction = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(GlavenTheme.primaryText.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.7))
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Prosperity Level

    private var prosperityLevel: Int { game.prosperityLevel }

    @ViewBuilder
    private var prosperityLevelSection: some View {
        HStack {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(.yellow)
            Text("Prosperity Level")
                .font(.subheadline)
            Spacer()
            Text("Level \(prosperityLevel)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.yellow)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Achievements

    @ViewBuilder
    private func achievementSection(title: String, achievements: Set<String>, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(achievements.count)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            FlowLayout(spacing: 6) {
                ForEach(achievements.sorted(), id: \.self) { achievement in
                    Text(achievement.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Campaign Progress

    @ViewBuilder
    private var campaignProgressSection: some View {
        if let edition = game.edition {
            let allScenarios = gameManager.editionStore.scenarios(for: edition)
                .filter { $0.parent == nil && $0.group != "randomMonsterCard" && $0.group != "randomDungeonCard" }
            let totalCount = allScenarios.count
            let completedCount = game.completedScenarios.count
            let availableScenarios = gameManager.scenarioManager.availableScenarios(for: edition)
                .filter { !game.completedScenarios.contains($0.id) }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(GlavenTheme.accentText)
                    Text("Campaign Progress")
                        .font(.headline)
                    Spacer()
                    Text("\(completedCount)/\(totalCount)")
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.accentText)
                }

                // Progress bar
                GeometryReader { geo in
                    let fraction = totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GlavenTheme.primaryText.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GlavenTheme.accentText.opacity(0.7))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 8)

                // Available scenarios
                if !availableScenarios.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available (\(availableScenarios.count))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        FlowLayout(spacing: 6) {
                            ForEach(availableScenarios.prefix(12)) { scenario in
                                Text("#\(scenario.index)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(GlavenTheme.accentText.opacity(0.15))
                                    .foregroundStyle(GlavenTheme.accentText)
                                    .clipShape(Capsule())
                            }
                            if availableScenarios.count > 12 {
                                Text("+\(availableScenarios.count - 12) more")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Completed Scenarios

    @ViewBuilder
    private var completedScenariosSection: some View {
        let sortedScenarios = completedScenarioDetails

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(.green)
                Text("Completed Scenarios")
                    .font(.headline)
                Spacer()
                Text("\(game.completedScenarios.count)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            FlowLayout(spacing: 6) {
                ForEach(sortedScenarios, id: \.id) { info in
                    Text("#\(info.index) \(info.name)")
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var completedScenarioDetails: [CompletedScenarioInfo] {
        guard let edition = game.edition else {
            return game.completedScenarios.sorted().map {
                CompletedScenarioInfo(id: $0, index: $0, name: "")
            }
        }
        let allScenarios = gameManager.editionStore.scenarios(for: edition)
        return game.completedScenarios.compactMap { completedID in
            let parts = completedID.split(separator: "-", maxSplits: 1)
            guard parts.count == 2 else { return CompletedScenarioInfo(id: completedID, index: completedID, name: "") }
            let index = String(parts[1])
            let name = allScenarios.first(where: { $0.index == index })?.name ?? ""
            return CompletedScenarioInfo(id: completedID, index: index, name: name)
        }.sorted { (Int($0.index) ?? 999) < (Int($1.index) ?? 999) }
    }

    // MARK: - Characters Summary

    // MARK: - Campaign Log

    private var campaignLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Campaign Log", systemImage: "book.closed")
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)
            ForEach(game.campaignLog.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: Self.logIcon(entry.type))
                        .foregroundStyle(GlavenTheme.accentText)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.primaryText)
                        if let details = entry.details {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(entry.timestamp, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    static func logIcon(_ type: CampaignLogType) -> String {
        switch type {
        case .scenarioCompleted: return "checkmark.seal"
        case .scenarioFailed: return "xmark.seal"
        case .characterAdded: return "person.badge.plus"
        case .characterRetired: return "figure.walk.departure"
        case .characterExhausted: return "bed.double"
        case .achievementGained: return "flag"
        case .prosperityGained: return "building.2"
        case .reputationChanged: return "person.2"
        case .treasureLooted: return "shippingbox"
        case .itemAcquired: return "bag"
        case .levelUp: return "arrow.up.circle"
        case .characterUnlocked: return "lock.open"
        case .questCompleted: return "scroll.fill"
        case .eventResolved: return "scroll"
        }
    }

    @ViewBuilder
    private var charactersSummarySection: some View {
        if !game.characters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.3")
                        .foregroundStyle(GlavenTheme.accentText)
                    Text("Characters")
                        .font(.headline)
                }

                ForEach(game.characters, id: \.id) { character in
                    HStack {
                        ThumbnailImage(
                            image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                            size: 32,
                            cornerRadius: 6,
                            fallbackColor: .gray
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameText.characterName(character, labels: gameManager.editionStore))
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Level \(character.level) | XP: \(character.experience) | Gold: \(character.loot)")
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        Spacer()
                        if character.exhausted {
                            Text("Exhausted")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Helpers

    private var reputationColor: Color {
        if game.partyReputation > 0 { return .blue }
        if game.partyReputation < 0 { return .red }
        return Color.secondary
    }
}

// FlowLayout is defined in ConditionsView.swift and shared

private struct CompletedScenarioInfo: Identifiable {
    let id: String
    let index: String
    let name: String
}
