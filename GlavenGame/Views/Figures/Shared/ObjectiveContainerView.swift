import SwiftUI

struct ObjectiveContainerView: View {
    @Bindable var objective: GameObjectiveContainer
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var showDetail = false

    private var aliveEntities: [GameObjectiveEntity] {
        objective.entities.filter { !$0.dead }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: objective.escort ? "figure.walk" : "target")
                    .font(.system(size: 14 * scale))
                    .foregroundStyle(objective.escort ? .blue : GlavenTheme.accentText)

                Text(objective.title.isEmpty ? "Objective" : objective.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .lineLimit(1)

                if objective.escort {
                    Text("ESCORT")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                // Initiative
                if objective.initiative < 99 {
                    Text("\(objective.initiative)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .monospacedDigit()
                }

                // Add entity button
                Button {
                    gameManager.objectiveManager.addEntity(to: objective)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(GlavenTheme.accentText)
                }
                .buttonStyle(.plain)
            }

            // Entities
            ForEach(aliveEntities, id: \.uuid) { entity in
                ObjectiveEntityRow(entity: entity, container: objective)
            }
        }
        .padding(10)
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button {
                gameManager.objectiveManager.addEntity(to: objective)
            } label: {
                Label("Add Token", systemImage: "plus.circle")
            }
            Divider()
            Button(role: .destructive) {
                gameManager.objectiveManager.removeObjective(objective)
            } label: {
                Label("Remove Objective", systemImage: "trash")
            }
        }
    }
}

// MARK: - Entity Row

private struct ObjectiveEntityRow: View {
    @Bindable var entity: GameObjectiveEntity
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale

    let container: GameObjectiveContainer

    private var healthFraction: Double {
        guard entity.maxHealth > 0 else { return 0 }
        return Double(entity.health) / Double(entity.maxHealth)
    }

    private var healthColor: Color {
        if healthFraction > 0.5 { return GlavenTheme.positive }
        if healthFraction > 0.25 { return .yellow }
        return .red
    }

    var body: some View {
        HStack(spacing: 8) {
            // Number badge
            Text("#\(entity.number)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.primaryText)
                .frame(width: 24 * scale, height: 24 * scale)
                .background(GlavenTheme.primaryText.opacity(0.1))
                .clipShape(Circle())

            // Health bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(GlavenTheme.primaryText.opacity(0.1))

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(healthColor)
                        .frame(width: geo.size.width * healthFraction)
                }
            }
            .frame(height: 8 * scale)

            // Health text
            Text("\(entity.health)/\(entity.maxHealth)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(GlavenTheme.primaryText)
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .trailing)

            // Health controls
            HStack(spacing: 4) {
                Button {
                    gameManager.entityManager.changeHealth(entity, amount: -1)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button {
                    gameManager.entityManager.changeHealth(entity, amount: 1)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(GlavenTheme.positive.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(role: .destructive) {
                gameManager.objectiveManager.removeEntity(entity, from: container)
            } label: {
                Label("Remove Token #\(entity.number)", systemImage: "trash")
            }
        }
    }
}
