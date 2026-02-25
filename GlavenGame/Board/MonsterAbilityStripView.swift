import SwiftUI

/// Compact horizontal strip of monster ability card images shown in the bottom bar during execution.
/// Each card cell shows the actual scanned card art from gloomhaven-card-browser.
struct MonsterAbilityStripView: View {

    @Environment(GameManager.self) private var gameManager
    let coordinator: BoardCoordinator
    /// Width of each individual card image. Height is derived from the landscape aspect ratio (~1.4:1).
    var cardWidth: CGFloat = 120

    private var cardHeight: CGFloat { cardWidth / 1.4 }

    var body: some View {
        let active = gameManager.game.monsters.filter { !$0.off && !$0.aliveEntities.isEmpty }
        if !active.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                ForEach(active) { monster in
                    if let cardIndex = gameManager.monsterManager.currentAbilityCardIndex(for: monster) {
                        let deckName = monster.monsterData?.deck ?? monster.name
                        if let url = ImageLoader.monsterAbilityCardURL(deckName: deckName, cardIndex: cardIndex) {
                            monsterCardCell(monster: monster, url: url)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Per-monster card cell

    @ViewBuilder
    private func monsterCardCell(monster: GameMonster, url: URL) -> some View {
        let active = isActive(monster)

        VStack(spacing: 3) {
            // Monster name + thumbnail header
            HStack(spacing: 4) {
                monsterThumb(monster)
                Text(formatName(monster.name))
                    .font(.system(size: 8, weight: active ? .heavy : .semibold))
                    .foregroundStyle(active ? .yellow : .white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: cardWidth, alignment: .leading)

            // Actual card image
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.06))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white.opacity(0.4))
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .topTrailing) {
                if active {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(2)
                        .background(Circle().fill(.yellow))
                        .offset(x: 3, y: -3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(active ? .yellow : .white.opacity(0.15), lineWidth: active ? 2 : 0.5)
            )
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func monsterThumb(_ monster: GameMonster) -> some View {
        if let img = ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name) {
            #if os(macOS)
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 14, height: 14)
                .clipShape(Circle())
            #else
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 14, height: 14)
                .clipShape(Circle())
            #endif
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 14, height: 14)
        }
    }

    private func isActive(_ monster: GameMonster) -> Bool {
        guard coordinator.boardPhase == .execution,
              coordinator.currentTurnIndex >= 0,
              coordinator.currentTurnIndex < coordinator.turnOrder.count else { return false }
        guard case .monster(let m) = coordinator.turnOrder[coordinator.currentTurnIndex].figure else { return false }
        return m.id == monster.id
    }

    private func formatName(_ name: String) -> String {
        name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}
