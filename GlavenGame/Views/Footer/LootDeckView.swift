import SwiftUI

struct LootDeckView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var lastDrawn: Loot?
    @State private var showApplySheet = false
    @State private var showDeckSheet = false

    private var playerCount: Int {
        max(2, gameManager.game.activeCharacters.count)
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("Loot")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)

            Button {
                lastDrawn = gameManager.lootManager.drawCard()
                if lastDrawn != nil {
                    showApplySheet = true
                }
            } label: {
                VStack(spacing: 2) {
                    if let card = lastDrawn ?? gameManager.game.lootDeck.currentCard {
                        LootCardView(loot: card, playerCount: playerCount)
                    } else {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 20 * scale))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(gameManager.game.lootDeck.remainingCount) left")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 60 * scale, height: 56 * scale)
                .background(GlavenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .contextMenu {
            Button { showDeckSheet = true } label: {
                Label("View Deck", systemImage: "rectangle.stack")
            }
            Button {
                gameManager.lootManager.shuffleDeck()
            } label: {
                Label("Shuffle Deck", systemImage: "shuffle")
            }
        }
        .sheet(isPresented: $showApplySheet) {
            if let loot = lastDrawn {
                LootApplySheet(loot: loot, playerCount: playerCount)
            }
        }
        .sheet(isPresented: $showDeckSheet) {
            LootDeckSheet()
        }
    }
}
