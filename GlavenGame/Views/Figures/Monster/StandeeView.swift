import SwiftUI

struct StandeeView: View {
    @Bindable var entity: GameMonsterEntity
    let monster: GameMonster
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var showConditions = false
    @State private var showEntityMenu = false

    private var healthPercentage: Double {
        guard entity.maxHealth > 0 else { return 0 }
        return Double(entity.health) / Double(entity.maxHealth)
    }

    private var isCritical: Bool {
        entity.maxHealth > 0 && healthPercentage <= 0.35 && entity.health > 0
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored type stripe
            typeColor
                .frame(width: 4 * scale)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))

            HStack(spacing: 8 * scale) {
                // Number badge
                ZStack {
                    Circle()
                        .fill(typeColor)
                        .frame(width: 30 * scale, height: 30 * scale)
                    Circle()
                        .stroke(GlavenTheme.primaryText.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 30 * scale, height: 30 * scale)
                    Text("\(entity.number)")
                        .font(.system(size: 15 * scale, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                }

                // Shield + Retaliate
                if let shield = entity.shield ?? entity.shieldPersistent, shield.value?.intValue ?? 0 > 0 {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.actionIcon("shield"), fallbackSystemName: "shield.fill", size: 13, color: GlavenTheme.nextPhaseColor)
                        Text("\(shield.value?.intValue ?? 0)")
                            .font(.system(size: 11 * scale, weight: .bold))
                            .foregroundStyle(GlavenTheme.nextPhaseColor)
                    }
                }

                if let ret = entity.retaliate.first ?? entity.retaliatePersistent.first, ret.value?.intValue ?? 0 > 0 {
                    HStack(spacing: 2) {
                        GameIcon(image: ImageLoader.actionIcon("retaliate"), fallbackSystemName: "arrow.uturn.backward", size: 13, color: .orange)
                        Text("\(ret.value?.intValue ?? 0)")
                            .font(.system(size: 11 * scale, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                // Conditions
                if !entity.entityConditions.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(entity.entityConditions) { condition in
                            ZStack(alignment: .topTrailing) {
                                BundledImage(
                                    ImageLoader.conditionIcon(condition.name.rawValue),
                                    size: 14,
                                    systemName: "bolt.fill"
                                )
                                if condition.value > 1 {
                                    Text("\(condition.value)")
                                        .font(.system(size: 7 * scale, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 2)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .offset(x: 4 * scale, y: -3 * scale)
                                }
                            }
                        }
                    }
                }

                Button {
                    showConditions.toggle()
                } label: {
                    Image(systemName: "cross.circle")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(entity.entityConditions.isEmpty ? Color.secondary : Color.red)
                }
                .buttonStyle(.plain)

                // Health display
                VStack(spacing: 1) {
                    HStack(spacing: 2) {
                        Button {
                            SoundPlayer.play(.healthDown)
                            gameManager.entityManager.changeHealth(entity, amount: -1)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)

                        Text("\(entity.health)")
                            .font(.system(size: 16 * scale, weight: .bold, design: .monospaced))
                            .foregroundStyle(isCritical ? Color.red : GlavenTheme.primaryText)
                        Text("/\(entity.maxHealth)")
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(GlavenTheme.secondaryText)

                        Button {
                            SoundPlayer.play(.healthUp)
                            gameManager.entityManager.changeHealth(entity, amount: 1)
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12 * scale))
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }

                    // Mini health bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(GlavenTheme.primaryText.opacity(0.1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(miniBarColor)
                                .frame(width: geo.size.width * healthPercentage)
                                .animation(.easeInOut(duration: 0.25), value: healthPercentage)
                        }
                    }
                    .frame(width: 44 * scale, height: 3 * scale)
                }

                // Kill button
                Button {
                    SoundPlayer.play(.death)
                    entity.dead = true
                    entity.health = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red.opacity(0.7))
                        .font(.system(size: 14 * scale))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 6 * scale)
        }
        .background(entity.active ? typeColor.opacity(0.12) : GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(entity.active ? typeColor.opacity(0.4) : GlavenTheme.primaryText.opacity(0.06), lineWidth: 1)
        )
        .onTapGesture {
            showEntityMenu = true
        }
        .popover(isPresented: $showConditions) {
            ConditionsView(entity: entity, availableConditions: gameManager.game.conditions)
        }
        .sheet(isPresented: $showEntityMenu) {
            EntityMenuView(entity: entity, name: "\(entity.type.rawValue.capitalized) \(entity.number)")
        }
    }

    private var typeColor: Color {
        switch entity.type {
        case .normal: return GlavenTheme.normalType
        case .elite: return GlavenTheme.elite
        case .boss: return GlavenTheme.boss
        }
    }

    private var miniBarColor: Color {
        if healthPercentage <= 0.25 { return .red }
        if healthPercentage <= 0.5 { return .orange }
        return typeColor
    }
}
