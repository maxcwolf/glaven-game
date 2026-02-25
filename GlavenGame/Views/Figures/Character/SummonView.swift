import SwiftUI

struct SummonView: View {
    @Bindable var summon: GameSummon
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @State private var showEntityMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(summonColor)
                    .frame(width: 16, height: 16)

                Text(summon.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.caption)
                    .fontWeight(.medium)

                // State badge
                if summon.state == .new {
                    Text("NEW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(GlavenTheme.nextPhaseColor)
                        .clipShape(Capsule())
                }

                Spacer()

                // Stats
                if summon.effectiveAttack > 0 {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.actionIcon("attack"), fallbackSystemName: "burst.fill", size: 12)
                        Text("\(summon.effectiveAttack)")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
                if summon.movement > 0 {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.actionIcon(summon.flying ? "fly" : "move"), fallbackSystemName: "figure.walk", size: 12)
                        Text("\(summon.movement)")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }
                if summon.range > 0 {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.actionIcon("range"), fallbackSystemName: "scope", size: 12)
                        Text("\(summon.range)")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }

                // HP with +/- buttons
                HStack(spacing: 2) {
                    Button {
                        gameManager.entityManager.changeHealth(summon, amount: -1)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                    .buttonStyle(.plain)

                    GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 12, color: .red)
                    Text("\(summon.health)/\(summon.maxHealth)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(summon.health <= summon.maxHealth / 3 ? Color.red : GlavenTheme.primaryText)

                    Button {
                        gameManager.entityManager.changeHealth(summon, amount: 1)
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                // Remove button
                Button {
                    gameManager.characterManager.removeSummon(summon, from: character)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            // Condition badges
            if !summon.entityConditions.isEmpty {
                ConditionBadgesView(conditions: summon.entityConditions) { condition in
                    gameManager.entityManager.removeCondition(condition.name, from: summon)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(GlavenTheme.primaryText.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(summon.dead ? 0.4 : 1.0)
        .onTapGesture {
            showEntityMenu = true
        }
        .sheet(isPresented: $showEntityMenu) {
            EntityMenuView(entity: summon, name: summon.name.replacingOccurrences(of: "-", with: " ").capitalized)
        }
    }

    private var summonColor: Color {
        switch summon.color {
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .white: return .white
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        default: return .gray
        }
    }
}
