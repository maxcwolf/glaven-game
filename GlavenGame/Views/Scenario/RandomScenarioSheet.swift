import SwiftUI

struct RandomScenarioSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var randomScenario: ScenarioData?
    @State private var showOnlyAvailable = true

    private var scenarios: [ScenarioData] {
        guard let edition = gameManager.game.edition else { return [] }
        if showOnlyAvailable {
            return gameManager.scenarioManager.availableScenarios(for: edition)
        }
        return gameManager.editionStore.scenarios(for: edition)
            .filter { !$0.isConclusion && $0.solo == nil }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // Random scenario display
                if let scenario = randomScenario {
                    VStack(spacing: 12) {
                        Text("#\(scenario.index)")
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(GlavenTheme.accentText)

                        Text(scenario.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.primaryText)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            if let monsters = scenario.monsters {
                                Label("\(monsters.count) monsters", systemImage: "pawprint.fill")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            if let rooms = scenario.rooms {
                                Label("\(rooms.count) rooms", systemImage: "door.left.hand.open")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                        }

                        Button {
                            gameManager.scenarioManager.setScenario(scenario)
                            dismiss()
                        } label: {
                            Label("Start This Scenario", systemImage: "play.fill")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(GlavenTheme.accentText)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(GlavenTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "dice.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("Tap Roll to pick a random scenario")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Spacer()

                // Controls
                VStack(spacing: 12) {
                    Toggle("Available scenarios only", isOn: $showOnlyAvailable)
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Text("\(scenarios.count) scenarios in pool")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                randomScenario = scenarios.randomElement()
                            }
                        } label: {
                            Label("Roll", systemImage: "dice.fill")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(GlavenTheme.accentText.opacity(0.2))
                                .foregroundStyle(GlavenTheme.accentText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(scenarios.isEmpty)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .background(GlavenTheme.background)
            .navigationTitle("Random Scenario")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
