import SwiftUI

struct EntityMenuView: View {
    let entity: any Entity
    let name: String
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Health adjustment
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 14, color: .red)
                            Text("Health")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }

                        HStack(spacing: 12) {
                            healthButton(-5, label: "-5")
                            healthButton(-1, label: "-1")

                            VStack(spacing: 2) {
                                Text("\(entity.health)")
                                    .font(.system(size: 28 * scale, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(GlavenTheme.primaryText)
                                Text("/ \(entity.maxHealth)")
                                    .font(.system(size: 12 * scale))
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            .frame(minWidth: 60 * scale)

                            healthButton(1, label: "+1")
                            healthButton(5, label: "+5")
                        }

                        // Health bar
                        let pct = entity.maxHealth > 0 ? Double(entity.health) / Double(entity.maxHealth) : 0
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(GlavenTheme.primaryText.opacity(0.1))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(pct <= 0.25 ? Color.red : pct <= 0.5 ? Color.orange : GlavenTheme.positive)
                                    .frame(width: geo.size.width * pct)
                            }
                        }
                        .frame(height: 8)
                    }
                    .padding()
                    .background(GlavenTheme.primaryText.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Conditions grid
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conditions")
                            .font(.system(size: 12 * scale))
                            .foregroundStyle(GlavenTheme.secondaryText)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(gameManager.game.conditions, id: \.self) { condition in
                                let isActive = entity.entityConditions.contains { $0.name == condition }
                                let isImmune = entity.immunities.contains(condition)

                                Button {
                                    if isActive {
                                        gameManager.entityManager.removeCondition(condition, from: entity)
                                    } else {
                                        gameManager.entityManager.addCondition(condition, to: entity)
                                    }
                                } label: {
                                    VStack(spacing: 2) {
                                        BundledImage(
                                            ImageLoader.conditionIcon(condition.rawValue),
                                            size: 24,
                                            systemName: "bolt.fill"
                                        )
                                        Text(condition.rawValue)
                                            .font(.system(size: 8 * scale))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(isActive ? Color.accentColor.opacity(0.3) : GlavenTheme.primaryText.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isActive ? Color.accentColor : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isImmune)
                                .opacity(isImmune ? 0.3 : 1.0)
                            }
                        }
                    }
                    .padding()
                    .background(GlavenTheme.primaryText.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Character-specific: XP and Loot
                    if let character = entity as? GameCharacter {
                        HStack(spacing: 16) {
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    GameIcon(image: ImageLoader.statusIcon("experience"), fallbackSystemName: "star.fill", size: 14, color: .blue)
                                    Text("XP")
                                        .font(.system(size: 12 * scale))
                                        .foregroundStyle(GlavenTheme.secondaryText)
                                }
                                HStack(spacing: 8) {
                                    Button { gameManager.characterManager.addXP(-1, to: character) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 20 * scale))
                                    }
                                    .buttonStyle(.plain)
                                    Text("\(character.experience)")
                                        .font(.system(size: 22 * scale, weight: .bold))
                                        .monospacedDigit()
                                    Button { gameManager.characterManager.addXP(1, to: character) } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20 * scale))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    GameIcon(image: ImageLoader.statusIcon("loot"), fallbackSystemName: "dollarsign.circle.fill", size: 14, color: .yellow)
                                    Text("Loot")
                                        .font(.system(size: 12 * scale))
                                        .foregroundStyle(GlavenTheme.secondaryText)
                                }
                                HStack(spacing: 8) {
                                    Button { gameManager.characterManager.addLoot(-1, to: character) } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 20 * scale))
                                            .foregroundStyle(.yellow)
                                    }
                                    .buttonStyle(.plain)
                                    Text("\(character.loot)")
                                        .font(.system(size: 22 * scale, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.yellow)
                                    Button { gameManager.characterManager.addLoot(1, to: character) } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20 * scale))
                                            .foregroundStyle(.yellow)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                        .background(GlavenTheme.primaryText.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // Action buttons
                    VStack(spacing: 8) {
                        if let character = entity as? GameCharacter {
                            Button {
                                gameManager.characterManager.toggleExhausted(character)
                                dismiss()
                            } label: {
                                Label(character.exhausted ? "Revive" : "Exhaust", systemImage: character.exhausted ? "heart.fill" : "heart.slash")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        if let monsterEntity = entity as? GameMonsterEntity {
                            Button(role: .destructive) {
                                monsterEntity.dead = true
                                monsterEntity.health = 0
                                dismiss()
                            } label: {
                                Label("Kill", systemImage: "xmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle(name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320 * scale, minHeight: 400 * scale)
    }

    private func healthButton(_ amount: Int, label: String) -> some View {
        Button {
            gameManager.entityManager.changeHealth(entity, amount: amount)
        } label: {
            Text(label)
                .font(.system(size: 16 * scale, weight: .bold))
                .frame(width: 44 * scale, height: 36 * scale)
                .background(amount < 0 ? Color.red.opacity(0.2) : GlavenTheme.positive.opacity(0.2))
                .foregroundStyle(amount < 0 ? Color.red : GlavenTheme.positive)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

}
