import SwiftUI

/// The campaign in numbers, in the board's look: scenarios won and lost, monsters killed and
/// exhaustions, then each character's share, from the records the game keeps as it's played.
struct PartyStatisticsSheet: View {
    @Environment(GameManager.self) private var gameManager
    var onDone: () -> Void = {}

    private var game: GameState { gameManager.game }
    private var party: [GameCharacter] { game.characters.filter { !$0.retired } }

    /// The campaign's totals.
    struct Totals: Equatable {
        var won = 0, lost = 0, kills = 0, exhaustions = 0
        /// The monster killed most, and how many ("bandit-guard", 21).
        var mostKilled: (name: String, count: Int)?

        static func == (a: Totals, b: Totals) -> Bool {
            (a.won, a.lost, a.kills, a.exhaustions) == (b.won, b.lost, b.kills, b.exhaustions)
                && a.mostKilled?.name == b.mostKilled?.name && a.mostKilled?.count == b.mostKilled?.count
        }
    }

    static func totals(_ game: GameState) -> Totals {
        var kills: [String: Int] = [:]
        for character in game.characters { kills.merge(character.record.kills, uniquingKeysWith: +) }
        let most = kills.max { ($0.value, $1.key) < ($1.value, $0.key) }
        return Totals(won: game.completedScenarios.count,
                      lost: game.campaignLog.filter { $0.type == .scenarioFailed }.count,
                      kills: kills.values.reduce(0, +),
                      exhaustions: game.characters.reduce(0) { $0 + $1.record.timesExhausted },
                      mostKilled: most.map { ($0.key, $0.value) })
    }

    var body: some View {
        let totals = Self.totals(game)
        TownDialog(title: "Statistics", subtitle: subtitle, size: CGSize(width: 900, height: 600), onDone: onDone) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        tile("\(totals.won)", "Scenarios won")
                        tile("\(totals.lost)", "Lost")
                        tile("\(totals.kills)", "Monsters killed")
                        tile("\(totals.exhaustions)", "Exhaustions")
                    }
                    TownSection(title: "By Character") {
                        HStack {
                            Color.clear.frame(width: 170, height: 1)
                            ForEach(Self.columns, id: \.self) { TownSmallCaps(text: $0).frame(maxWidth: .infinity) }
                        }
                        .accessibilityHidden(true)
                        ForEach(party, id: \.id) { row($0) }
                        Rectangle().fill(BoardTheme.border.opacity(0.3)).frame(height: 1)
                        Text(footnote(totals))
                            .font(BoardTheme.font(size: 13))
                            .foregroundStyle(BoardTheme.secondaryText)
                    }
                }
                .padding(18)
            }
        }
    }

    static let columns = ["Won", "Kills", "Elites", "Exhausted", "XP", "Gold"]

    /// A character's numbers, in the order of `columns`.
    static func numbers(_ character: GameCharacter) -> [Int] {
        let record = character.record
        return [record.scenariosCompleted.count, record.kills.values.reduce(0, +), record.eliteKills,
                record.timesExhausted, character.experience, character.loot]
    }

    private var subtitle: String {
        let name = game.partyName.isEmpty ? "This campaign" : game.partyName
        guard let first = game.campaignLog.first?.timestamp else { return name }
        return "\(name) \u{00B7} since \(first.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func footnote(_ totals: Totals) -> String {
        var parts: [String] = []
        if let most = totals.mostKilled {
            let name = GameText.monsterName(most.name, edition: game.edition ?? "gh", labels: gameManager.editionStore)
            parts.append("Most kills: \(name) (\(most.count)).")
        }
        parts.append("Gold given at the sanctuary: \(game.events.sanctuaryGold).")
        return parts.joined(separator: " ")
    }

    private func row(_ character: GameCharacter) -> some View {
        let name = GameText.characterName(character, labels: gameManager.editionStore)
        let numbers = Self.numbers(character)
        return HStack {
            HStack(spacing: 8) {
                Group {
                    if let image = ImageLoader.characterThumbnail(edition: character.edition, name: character.name) {
                        #if os(macOS)
                        Image(nsImage: image).resizable().scaledToFill()
                        #else
                        Image(uiImage: image).resizable().scaledToFill()
                        #endif
                    } else {
                        BoardTheme.raised
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                Text(name)
                    .font(BoardTheme.font(size: 14, weight: .semibold))
                    .foregroundStyle(BoardTheme.text)
                    .lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)
            ForEach(Array(numbers.enumerated()), id: \.offset) { _, value in
                Text("\(value)")
                    .font(BoardTheme.font(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(BoardTheme.text)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name + ": " + zip(Self.columns, numbers).map { "\($0) \($1)" }.joined(separator: ", "))
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(BoardTheme.display(30))
                .foregroundStyle(BoardTheme.text)
            Text(label)
                .font(BoardTheme.font(size: 12, weight: .medium))
                .foregroundStyle(BoardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
