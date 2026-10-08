import SwiftUI

struct MainMenuView: View {
    @Environment(GameManager.self) private var gameManager
    @State private var showSettings = false
    @State private var showLoad = false
    @State private var showCredits = false

    var body: some View {
        ZStack {
            MenuKeyArt()

            VStack(spacing: 24) {
                Spacer()

                Text("Glaven")
                    .font(GlavenFont.title(size: 96))
                    .foregroundStyle(BoardTheme.text)
                    .shadow(color: .black.opacity(0.8), radius: 12, y: 4)
                    .accessibilityAddTraits(.isHeader)

                Text("A Gloomhaven Board Game")
                    .font(.title3)
                    .foregroundStyle(BoardTheme.text.opacity(0.85))
                    .shadow(color: .black, radius: 6)
                    .padding(.top, -18)

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

                    if hasSaveSlots {
                        menuButton("Load Game", icon: "folder.fill") {
                            showLoad = true
                        }
                    }

                    menuButton("Settings", icon: "gearshape.fill") {
                        showSettings = true
                    }

                    menuButton("Credits", icon: "scroll.fill") {
                        showCredits = true
                    }
                }
                .frame(width: 300)
                .padding(.top, 8)

                Spacer()
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            PreferencesSheet()
        }
        .sheet(isPresented: $showLoad) {
            SaveSlotsSheet()
        }
        .sheet(isPresented: $showCredits) {
            CreditsSheet()
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

    /// Named saves to load (the autosave is Continue).
    private var hasSaveSlots: Bool {
        gameManager.allSaveSlots().contains { $0.name != "autosave" }
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
                        .foregroundStyle(BoardTheme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.brass, lineWidth: 1.5))
            .foregroundStyle(BoardTheme.text)
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
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border, lineWidth: 1))
            .foregroundStyle(BoardTheme.text)
        }
        .buttonStyle(.plain)
    }
}
