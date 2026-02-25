import SwiftUI

struct RoomRevealSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var adjacentRooms: [RoomData] {
        gameManager.game.scenario?.adjacentUnrevealedRooms ?? []
    }

    private var playerCount: Int {
        max(2, gameManager.game.activeCharacters.count)
    }

    var body: some View {
        NavigationStack {
            List(adjacentRooms, id: \.roomNumber) { room in
                Button {
                    gameManager.scenarioManager.openRoom(room)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Room \(room.roomNumber)")
                                .font(.headline)
                            if let ref = room.ref {
                                Text("(\(ref))")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "door.left.hand.open")
                                .foregroundStyle(Color.accentColor)
                        }

                        // Monster preview
                        if let standees = room.monster {
                            let spawning = standeesForPlayerCount(standees, playerCount: playerCount)
                            if !spawning.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "figure.stand")
                                        .font(.caption2)
                                        .foregroundStyle(Color.secondary)
                                    Text(monsterSummary(spawning))
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }

                        // Treasures
                        if let treasures = room.treasures, !treasures.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "diamond.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.yellow)
                                Text(treasureSummary(treasures))
                                    .font(.caption)
                                    .foregroundStyle(Color.yellow.opacity(0.8))
                                    .lineLimit(2)
                            }
                            // Show looted status
                            let looted = lootedTreasuresInRoom(treasures)
                            if !looted.isEmpty {
                                Text("\(looted.count) already looted")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }

                        // Objectives
                        if let objectives = room.objectives, !objectives.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "target")
                                    .font(.caption2)
                                    .foregroundStyle(GlavenTheme.accentText)
                                Text("\(objectives.count) objective\(objectives.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Open Room")
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func standeesForPlayerCount(_ standees: [MonsterStandeeData], playerCount: Int) -> [(String, MonsterType)] {
        standees.compactMap { standee in
            guard let type = standee.monsterType(forPlayerCount: playerCount) else { return nil }
            return (standee.name, type)
        }
    }

    private func treasureSummary(_ treasures: [IntOrString]) -> String {
        let labels = treasures.map { t -> String in
            "Treasure #\(t.stringValue)"
        }
        return labels.joined(separator: ", ")
    }

    private func lootedTreasuresInRoom(_ treasures: [IntOrString]) -> [String] {
        guard let scenario = gameManager.game.scenario else { return [] }
        let edition = scenario.data.edition
        let index = scenario.data.index
        return treasures.compactMap { t in
            let key = "\(edition)-\(index)-\(t.stringValue)"
            return gameManager.game.lootedTreasures.contains(key) ? t.stringValue : nil
        }
    }

    private func monsterSummary(_ spawning: [(String, MonsterType)]) -> String {
        var counts: [String: (normal: Int, elite: Int, boss: Int)] = [:]
        for (name, type) in spawning {
            var entry = counts[name] ?? (0, 0, 0)
            switch type {
            case .normal: entry.normal += 1
            case .elite: entry.elite += 1
            case .boss: entry.boss += 1
            }
            counts[name] = entry
        }
        return counts.sorted(by: { $0.key < $1.key }).map { name, count in
            let displayName = name.replacingOccurrences(of: "-", with: " ").capitalized
            var parts: [String] = []
            if count.normal > 0 { parts.append("\(count.normal)N") }
            if count.elite > 0 { parts.append("\(count.elite)E") }
            if count.boss > 0 { parts.append("\(count.boss)B") }
            return "\(displayName) (\(parts.joined(separator: "/")))"
        }.joined(separator: ", ")
    }
}
