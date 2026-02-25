import SwiftUI

struct MainMenuView: View {
    @Environment(GameManager.self) private var gameManager
    @State private var showSettings = false

    var body: some View {
        ZStack {
            GlavenTheme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                LogoView(size: 180)

                Text("GLAVEN")
                    .font(GlavenFont.title(size: 72))
                    .foregroundStyle(GlavenTheme.primaryText)
                    .padding(.top, -8)

                Text("A Gloomhaven Board Game")
                    .font(.title3)
                    .foregroundStyle(GlavenTheme.secondaryText)

                VStack(spacing: 12) {
                    menuButton("New Game", icon: "plus.circle.fill") {
                        gameManager.newGame()
                        gameManager.setEdition("gh")
                        gameManager.appPhase = .gameSetup
                    }

                    if gameManager.hasAutosave {
                        menuButton("Continue", icon: "play.circle.fill") {
                            gameManager.restoreGame()
                            if gameManager.boardCoordinator.boardScene != nil {
                                gameManager.appPhase = .board
                            } else if !gameManager.game.figures.isEmpty {
                                gameManager.appPhase = .gameSetup
                            }
                        }
                    }

                    menuButton("Settings", icon: "gearshape.fill") {
                        showSettings = true
                    }
                }
                .frame(width: 280)
                .padding(.top, 8)

                Spacer()
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            PreferencesSheet()
        }
    }

    @ViewBuilder
    private func menuButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(GlavenFont.title(size: 22))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(GlavenTheme.cardBackground)
            .foregroundStyle(GlavenTheme.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
