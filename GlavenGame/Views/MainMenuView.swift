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
                    if let summary = gameManager.autosaveSummary {
                        continueButton(summary)
                    }

                    menuButton(gameManager.hasAutosave ? "New Campaign" : "New Game", icon: "plus.circle.fill") {
                        if gameManager.hasAutosave {
                            gameManager.confirmingNewGame = true
                        } else {
                            gameManager.beginNewGame()
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
        .confirmationDialog("Start a new campaign?", isPresented: Bindable(gameManager).confirmingNewGame,
                            titleVisibility: .visible) {
            Button("Start New Campaign", role: .destructive) {
                gameManager.beginNewGame()
            }
            Button("Keep Current Campaign", role: .cancel) {}
        } message: {
            Text("Your saved party and its progress will be replaced.")
        }
    }

    /// Continue, with what it resumes: "Brute, Tinkerer" and "#1 Black Barrow · Round 2".
    private func continueButton(_ summary: AutosaveSummary) -> some View {
        Button {
            gameManager.continueGame()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continue")
                        .font(GlavenFont.title(size: 22))
                    Text(continueDetail(summary))
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(GlavenTheme.cardBackground)
            .foregroundStyle(GlavenTheme.primaryText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GlavenTheme.accentText.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityHint(continueDetail(summary))
    }

    private func continueDetail(_ summary: AutosaveSummary) -> String {
        let party = GameText.list(summary.characterNames)
        guard let scenario = summary.scenario, let round = summary.round else { return party }
        return "\(party)\n\(scenario) · Round \(round)"
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
