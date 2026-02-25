import SwiftUI

struct FooterView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.isCompact) private var isCompact
    @State private var showScenarioSheet = false

    private var hasAlly: Bool {
        gameManager.game.monsters.contains { $0.isAlly || $0.isAllied }
    }

    private var activeCharacter: GameCharacter? {
        gameManager.game.characters.first { $0.active }
    }

    private var hasScenario: Bool {
        gameManager.game.scenario != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scenario bar
            if hasScenario {
                ScenarioHeaderView()
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(GlavenTheme.headerFooterBackground.opacity(0.8))

                ScenarioRulesView()
                    .padding(.horizontal)
            } else if gameManager.game.edition != nil {
                Button {
                    showScenarioSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map")
                        Text("Select Scenario")
                            .font(.system(size: 12 * scale))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.vertical, 4)
            }

            // Main footer
            if isCompact {
                compactFooter
            } else {
                wideFooter
            }
        }
        .sheet(isPresented: $showScenarioSheet) {
            ScenarioSelectionSheet()
        }
    }

    // MARK: - Wide Footer (iPad / Mac)

    @ViewBuilder
    private var wideFooter: some View {
        HStack(spacing: 16) {
            RoundButtonView()
            TimerView()
            Spacer()
            LevelDisplayView()
            Spacer()
            amDecks
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(GlavenTheme.headerFooterBackground)
    }

    // MARK: - Compact Footer (iPhone)

    @ViewBuilder
    private var compactFooter: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                RoundButtonView()
                TimerView()
                Spacer()
                LevelDisplayView()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                amDecks
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GlavenTheme.headerFooterBackground)
    }

    // MARK: - AM Decks (shared)

    @ViewBuilder
    private var amDecks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                AttackModifierDeckView(
                    label: "Monster",
                    deck: Binding(
                        get: { gameManager.game.monsterAttackModifierDeck },
                        set: { gameManager.game.monsterAttackModifierDeck = $0 }
                    ),
                    onDraw: { gameManager.attackModifierManager.drawMonsterCard() },
                    onShuffle: { gameManager.attackModifierManager.shuffleDeck(&gameManager.game.monsterAttackModifierDeck) }
                )
                if hasAlly {
                    AttackModifierDeckView(
                        label: "Ally",
                        deck: Binding(
                            get: { gameManager.game.allyAttackModifierDeck },
                            set: { gameManager.game.allyAttackModifierDeck = $0 }
                        ),
                        onDraw: { gameManager.attackModifierManager.drawAllyCard() },
                        onShuffle: { gameManager.attackModifierManager.shuffleDeck(&gameManager.game.allyAttackModifierDeck) }
                    )
                }
                if gameManager.game.lootDeck.active {
                    LootDeckView()
                }
                if let character = activeCharacter {
                    AttackModifierDeckView(
                        label: character.name.replacingOccurrences(of: "-", with: " ").capitalized,
                        deck: Binding(
                            get: { character.attackModifierDeck },
                            set: { character.attackModifierDeck = $0 }
                        ),
                        onDraw: { gameManager.attackModifierManager.drawCharacterCard(for: character) },
                        onShuffle: { gameManager.attackModifierManager.shuffleDeck(&character.attackModifierDeck) }
                    )
                }
            }
        }
    }
}
