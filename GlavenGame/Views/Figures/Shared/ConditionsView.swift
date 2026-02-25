import SwiftUI

struct ConditionsView: View {
    let entity: any Entity
    let availableConditions: [ConditionName]
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(availableConditions, id: \.self) { condition in
                    let isActive = entity.entityConditions.contains { $0.name == condition }
                    let isImmune = entity.immunities.contains(condition)
                    let activeCondition = entity.entityConditions.first { $0.name == condition }
                    let isStackable = Condition.conditionTypes(for: condition).contains(.stack) || Condition.conditionTypes(for: condition).contains(.stackable)

                    Button {
                        if isActive {
                            gameManager.entityManager.removeCondition(condition, from: entity)
                        } else {
                            gameManager.entityManager.addCondition(condition, to: entity)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            ZStack(alignment: .topTrailing) {
                                BundledImage(
                                    ImageLoader.conditionIcon(conditionFilename(condition)),
                                    size: 24,
                                    systemName: "bolt.fill"
                                )

                                // Stack value badge
                                if isActive, let ac = activeCondition, ac.value > 0 {
                                    Text("\(ac.value)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .background(Color.red)
                                        .clipShape(Capsule())
                                        .offset(x: 6, y: -4)
                                }
                            }

                            HStack(spacing: 2) {
                                // Permanent pin icon
                                if isActive, let ac = activeCondition, ac.permanent {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 7))
                                        .foregroundStyle(.orange)
                                }
                                Text(condition.rawValue)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isActive ? Color.accentColor.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isActive ? Color.accentColor : Color.gray.opacity(0.3))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isImmune)
                    .opacity(isImmune ? 0.3 : 1.0)
                    .contextMenu {
                        if isActive {
                            if isStackable {
                                Button { gameManager.entityManager.addCondition(condition, to: entity, value: 1) } label: {
                                    Label("+1 Stack", systemImage: "plus.circle")
                                }
                                if let ac = activeCondition, ac.value > 1 {
                                    Button {
                                        if let idx = entity.entityConditions.firstIndex(where: { $0.name == condition }) {
                                            entity.entityConditions[idx].value -= 1
                                        }
                                    } label: {
                                        Label("-1 Stack", systemImage: "minus.circle")
                                    }
                                }
                            }
                            Button {
                                if let idx = entity.entityConditions.firstIndex(where: { $0.name == condition }) {
                                    entity.entityConditions[idx].permanent.toggle()
                                }
                            } label: {
                                if let ac = activeCondition {
                                    Label(ac.permanent ? "Remove Permanent" : "Make Permanent", systemImage: ac.permanent ? "pin.slash" : "pin")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 250)
    }

    private func conditionFilename(_ name: ConditionName) -> String {
        name.rawValue
    }
}

struct ConditionBadgesView: View {
    let conditions: [EntityCondition]
    let onRemove: (EntityCondition) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(conditions) { condition in
                HStack(spacing: 2) {
                    if condition.permanent {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.orange)
                    }
                    BundledImage(
                        ImageLoader.conditionIcon(condition.name.rawValue),
                        size: 12,
                        systemName: "bolt.fill"
                    )
                    Text(condition.name.rawValue)
                        .font(.caption2)
                    if condition.value > 0 {
                        Text("(\(condition.value))")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(condition.isPositive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .clipShape(Capsule())
                .onTapGesture(count: 2) {
                    onRemove(condition)
                }
            }
        }
    }

}

// Simple flow layout for condition badges
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = Swift.max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
