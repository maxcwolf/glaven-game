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

// MARK: - Sidebar Environment Key (used by GameBoardView)

private struct ShowSidebarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var showSidebar: Binding<Bool>? {
        get { self[ShowSidebarKey.self] }
        set { self[ShowSidebarKey.self] = newValue }
    }
}
