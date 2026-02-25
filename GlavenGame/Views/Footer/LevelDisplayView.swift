import SwiftUI

struct LevelDisplayView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text("Level")
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                Text("\(gameManager.game.level)")
                    .font(.system(size: 20 * scale, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 11 * scale))
                        Text("\(gameManager.levelManager.trap())")
                            .font(.system(size: 11 * scale))
                    }
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.statusIcon("experience"), fallbackSystemName: "star", size: 12)
                        Text("\(gameManager.levelManager.experience())")
                            .font(.system(size: 11 * scale))
                    }
                }
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.statusIcon("loot"), fallbackSystemName: "dollarsign.circle.fill", size: 12, color: .yellow)
                        Text("\(gameManager.levelManager.loot())")
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.yellow)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "mountain.2")
                            .font(.system(size: 11 * scale))
                        Text("\(gameManager.levelManager.terrain())")
                            .font(.system(size: 11 * scale))
                    }
                }
            }
        }
    }
}
