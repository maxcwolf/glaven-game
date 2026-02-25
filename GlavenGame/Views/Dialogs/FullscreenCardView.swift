import SwiftUI

/// Fullscreen overlay for displaying an attack modifier card or ability card prominently.
struct FullscreenCardView: View {
    @Environment(\.dismiss) private var dismiss

    enum CardContent {
        case attackModifier(AttackModifier)
        case ability(AbilityModel, monsterName: String)
    }

    let content: CardContent

    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                switch content {
                case .attackModifier(let modifier):
                    attackModifierFullscreen(modifier)
                case .ability(let ability, let monsterName):
                    abilityFullscreen(ability, monsterName: monsterName)
                }

                Spacer()

                Text("Tap to dismiss")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 24)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    // MARK: - Attack Modifier Fullscreen

    @ViewBuilder
    private func attackModifierFullscreen(_ modifier: AttackModifier) -> some View {
        VStack(spacing: 16) {
            AttackModifierCardView(modifier: modifier, size: 300)
                .shadow(color: cardGlow(modifier).opacity(0.6), radius: 20)

            // Card info
            VStack(spacing: 6) {
                Text(modifier.displayText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(cardTextColor(modifier))

                if !modifier.effects.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(modifier.effects.enumerated()), id: \.offset) { _, effect in
                            Text(effect.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }

                Text(typeLabel(modifier))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Ability Fullscreen

    @ViewBuilder
    private func abilityFullscreen(_ ability: AbilityModel, monsterName: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(monsterName.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))

                Text("Initiative \(ability.initiative)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                if let name = ability.name, !name.isEmpty {
                    Text(name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            // Actions summary
            VStack(alignment: .leading, spacing: 6) {
                if let actions = ability.actions {
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        actionLabel(action)
                    }
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: ActionModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: actionIcon(action.type))
                .foregroundStyle(actionColor(action.type))
                .frame(width: 20)
            Text(actionText(action))
                .font(.body)
                .foregroundStyle(.white)
        }
    }

    private func actionText(_ action: ActionModel) -> String {
        let type = action.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        if let value = action.value {
            return "\(type) \(value.stringValue)"
        }
        return type
    }

    private func actionIcon(_ type: ActionType) -> String {
        switch type {
        case .attack: return "burst.fill"
        case .move: return "figure.walk"
        case .heal: return "heart.fill"
        case .shield: return "shield.fill"
        case .range: return "scope"
        case .target: return "target"
        case .push: return "arrow.right.to.line"
        case .pull: return "arrow.left.to.line"
        case .pierce: return "arrow.right"
        case .retaliate: return "bolt.fill"
        default: return "circle.fill"
        }
    }

    private func actionColor(_ type: ActionType) -> Color {
        switch type {
        case .attack: return .red
        case .move: return .blue
        case .heal: return .green
        case .shield: return .yellow
        default: return .white.opacity(0.7)
        }
    }

    // MARK: - Helpers

    private func cardGlow(_ modifier: AttackModifier) -> Color {
        switch modifier.type {
        case .null_, .curse: return .red
        case .double_, .bless: return .green
        case .plus1, .plus2, .plus3, .plus4: return .blue
        case .minus1, .minus2, .minus1extra: return .orange
        default: return .gray
        }
    }

    private func cardTextColor(_ modifier: AttackModifier) -> Color {
        switch modifier.type {
        case .null_, .curse: return .red
        case .double_, .bless: return .green
        default: return .white
        }
    }

    private func typeLabel(_ modifier: AttackModifier) -> String {
        switch modifier.type {
        case .null_: return "Null (Miss)"
        case .double_: return "Double Damage"
        case .bless: return "Bless"
        case .curse: return "Curse"
        default: return "Attack Modifier"
        }
    }
}
