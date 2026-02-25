import SwiftUI

struct RandomMonsterCardSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMonsterID: String = ""
    @State private var drawnAbility: AbilityModel?

    private var monsters: [GameMonster] {
        gameManager.game.monsters.filter { !$0.off && $0.aliveEntities.count > 0 }
    }

    private var selectedMonster: GameMonster? {
        monsters.first { $0.id == selectedMonsterID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Monster picker
                if monsters.count > 1 {
                    Section {
                        Picker("Monster", selection: $selectedMonsterID) {
                            Text("Select...").tag("")
                            ForEach(monsters, id: \.id) { monster in
                                Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                                    .tag(monster.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(.horizontal)
                } else if let only = monsters.first {
                    Text(only.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                        .onAppear { selectedMonsterID = only.id }
                }

                Spacer()

                // Drawn card
                if let ability = drawnAbility {
                    VStack(spacing: 12) {
                        Text(ability.name ?? "Ability")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(GlavenTheme.primaryText)

                        Text("Initiative \(ability.initiative)")
                            .font(.title3)
                            .monospacedDigit()
                            .foregroundStyle(GlavenTheme.accentText)

                        // Actions
                        if let actions = ability.actions, !actions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                                    HStack(spacing: 6) {
                                        Image(systemName: iconForAction(action.type))
                                            .font(.caption)
                                            .foregroundStyle(colorForAction(action.type))
                                        Text(describeAction(action))
                                            .font(.subheadline)
                                            .foregroundStyle(GlavenTheme.primaryText)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(GlavenTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        if ability.shuffle == true {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(GlavenTheme.primaryText.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            .font(.system(size: 48))
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text("Draw a random ability card")
                            .font(.subheadline)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Spacer()

                // Draw button
                Button {
                    drawRandom()
                } label: {
                    Label("Draw Card", systemImage: "hand.draw.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(selectedMonster != nil ? GlavenTheme.accentText.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                        .foregroundStyle(selectedMonster != nil ? GlavenTheme.accentText : GlavenTheme.secondaryText)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedMonsterID.isEmpty)
                .padding(.bottom)
            }
            .background(GlavenTheme.background)
            .navigationTitle("Random Monster Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func drawRandom() {
        guard let monster = selectedMonster else { return }
        let abilities = gameManager.monsterManager.abilities(for: monster)
        guard !abilities.isEmpty else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            drawnAbility = abilities.randomElement()
        }
    }

    private func iconForAction(_ type: ActionType) -> String {
        switch type {
        case .attack: return "burst.fill"
        case .move: return "figure.walk"
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .retaliate: return "arrow.uturn.left.circle"
        case .condition: return "exclamationmark.triangle"
        case .element: return "flame.fill"
        default: return "circle.fill"
        }
    }

    private func colorForAction(_ type: ActionType) -> Color {
        switch type {
        case .attack: return .red
        case .move: return .blue
        case .heal: return .green
        case .shield: return .cyan
        case .retaliate: return .orange
        case .condition: return .yellow
        case .element: return .purple
        default: return GlavenTheme.secondaryText
        }
    }

    private func describeAction(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        let prefix = action.valueType == .plus ? "+" : ""
        switch action.type {
        case .attack: return "\(prefix)\(value) Attack"
        case .move: return "\(prefix)\(value) Move"
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .condition: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case .element: return "\(value.capitalized) Element"
        default: return "\(action.type.rawValue.capitalized) \(value)"
        }
    }
}
