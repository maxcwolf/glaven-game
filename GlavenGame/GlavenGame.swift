import SwiftUI
import SwiftData

/// Wrapper view that observes SettingsManager and injects uiScale into the environment.
/// This must be a View (not in App.body directly) so @Observable tracking works reliably.
private struct ScaledContentView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.scenePhase) private var scenePhase

    private var isLight: Bool { gameManager.settingsManager.lightMode }
    private var effectiveTheme: String {
        gameManager.settingsManager.effectiveTheme(edition: gameManager.game.edition)
    }

    var body: some View {
        // Sync the static flags before any child view reads them.
        let _ = GlavenTheme.isLight = isLight
        let _ = GlavenTheme.activeTheme = effectiveTheme

        ContentView()
            .environment(\.uiScale, gameManager.settingsManager.uiScale)
            .environment(\.editionTheme, EditionTheme.forEdition(gameManager.game.edition))
            .environment(\.isCompact, false)
            .dynamicTypeSize(dynamicTypeForScale(gameManager.settingsManager.uiScale))
            .preferredColorScheme(isLight ? .light : .dark)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background || newPhase == .inactive {
                    gameManager.settingsManager.saveSettings()
                    gameManager.saveGame()
                }
            }
            .onAppear {
                GlavenTheme.isLight = isLight
                GlavenTheme.activeTheme = effectiveTheme
                SoundPlayer.settingsManager = gameManager.settingsManager
                SoundPlayer.playGlayvin()
            }
    }
}

@main
struct GlavenGameApp: App {
    let modelContainer: ModelContainer
    let gameManager: GameManager

    init() {
        GlavenFont.registerFonts()
        let schema = Schema([
            SettingsModel.self,
            SavedGameModel.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container
        self.gameManager = GameManager(modelContainer: container)

        // Sync initial light mode before first render
        GlavenTheme.isLight = gameManager.settingsManager.lightMode
    }

    var body: some Scene {
        WindowGroup {
            ScaledContentView()
                .environment(gameManager)
                .modelContainer(modelContainer)
                .onAppear {
                    // Maximize the window to fill the screen on launch
                    if let window = NSApplication.shared.windows.first {
                        if let screen = window.screen ?? NSScreen.main {
                            window.setFrame(screen.visibleFrame, display: true)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Game") {
                    gameManager.newGame()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    gameManager.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!gameManager.canUndo)
                Button("Redo") {
                    gameManager.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!gameManager.canRedo)
            }
        }
    }
}
