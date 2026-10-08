import SwiftUI

struct ContentView: View {
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        Group {
            switch gameManager.appPhase {
            case .mainMenu:
                MainMenuView()
            case .gameSetup:
                GameSetupView()
            case .board:
                BoardView(coordinator: gameManager.boardCoordinator)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}
