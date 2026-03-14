import SwiftUI

/// A positioned achievement marker on the world map.
/// Computed from scenario reward data — placed near the scenario that grants the achievement.
struct AchievementSticker: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let isGlobal: Bool  // global vs party achievement
    let x: CGFloat
    let y: CGFloat

    /// Build achievement stickers from earned achievements and scenario data.
    /// Places each sticker near the scenario that granted it, offset slightly
    /// below so it doesn't overlap the scenario tile.
    static func build(
        globalAchievements: Set<String>,
        partyAchievements: Set<String>,
        scenarios: [ScenarioData],
        completedScenarios: Set<String>,
        edition: String
    ) -> [AchievementSticker] {
        var stickers: [AchievementSticker] = []
        var placed: Set<String> = []

        for scenario in scenarios {
            guard let coords = scenario.coordinates else { continue }
            guard let rewards = scenario.rewards else { continue }

            let scenarioID = "\(edition)-\(scenario.index)"
            guard completedScenarios.contains(scenarioID) else { continue }

            let cx = (coords.x ?? 0) + (coords.width ?? 0) / 2
            let cy = (coords.y ?? 0) + (coords.height ?? 0) + 15  // Below the scenario tile

            for g in rewards.globalAchievements ?? [] {
                guard globalAchievements.contains(g), !placed.contains(g) else { continue }
                placed.insert(g)
                stickers.append(AchievementSticker(
                    id: "global-\(g)",
                    name: g,
                    displayName: formatName(g),
                    isGlobal: true,
                    x: cx, y: cy
                ))
            }

            for p in rewards.partyAchievements ?? [] {
                guard partyAchievements.contains(p), !placed.contains(p) else { continue }
                placed.insert(p)
                stickers.append(AchievementSticker(
                    id: "party-\(p)",
                    name: p,
                    displayName: formatName(p),
                    isGlobal: false,
                    x: cx, y: cy + CGFloat(stickers.filter { s in
                        abs(s.x - cx) < 20 && abs(s.y - cy) < 30
                    }.count) * CGFloat(18)  // Stack vertically if multiple at same location
                ))
            }
        }

        return stickers
    }

    private static func formatName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// Renders an achievement badge on the world map.
struct AchievementStickerView: View {
    let sticker: AchievementSticker
    let zoom: CGFloat

    var body: some View {
        label
            .position(x: sticker.x * zoom, y: sticker.y * zoom)
            .allowsHitTesting(false)
    }

    private var label: some View {
        HStack(spacing: 2 * zoom) {
            Image(systemName: sticker.isGlobal ? "globe" : "flag.fill")
                .font(.system(size: max(5, 7 * zoom)))
            Text(sticker.displayName)
                .font(.system(size: max(5, 7 * zoom), weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4 * zoom)
        .padding(.vertical, 2 * zoom)
        .background(
            Capsule()
                .fill(sticker.isGlobal
                      ? Color.orange.opacity(0.85)
                      : Color.teal.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: 2 * zoom, x: 0, y: 1 * zoom)
        )
    }
}
