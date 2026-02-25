import SwiftUI

/// Shows an "Apply" bar when a monster is active, letting users toggle
/// optional self-targeting actions (heal, conditions, elements) and
/// batch-apply them to all alive entities.
struct InteractiveActionsView: View {
    let ability: AbilityModel
    @Bindable var monster: GameMonster
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var selectedIndices: Set<Int> = []
    @State private var pulseScale: CGFloat = 0.92

    /// Actions from the ability that are "interactive" (optional self-targeting).
    private var interactiveActions: [(Int, ActionModel)] {
        guard let actions = ability.actions else { return [] }
        return actions.enumerated().compactMap { idx, action in
            isInteractive(action) ? (idx, action) : nil
        }
    }

    var body: some View {
        if monster.active && !interactiveActions.isEmpty {
            VStack(spacing: 6) {
                Divider().background(Color.white.opacity(0.15))

                // Toggleable action chips
                FlowLayout(spacing: 6) {
                    ForEach(interactiveActions, id: \.0) { idx, action in
                        actionChip(idx: idx, action: action)
                    }
                }

                // Apply / Skip button
                HStack(spacing: 8) {
                    if !selectedIndices.isEmpty {
                        Button {
                            applySelected()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11 * scale))
                                Text("Apply (\(selectedIndices.count))")
                                    .font(.system(size: 11 * scale, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(GlavenTheme.positive.opacity(0.6))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        skipAll()
                    } label: {
                        Text(selectedIndices.isEmpty ? "Skip" : "Skip Rest")
                            .font(.system(size: 10 * scale))
                            .foregroundStyle(GlavenTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Action Chip

    @ViewBuilder
    private func actionChip(idx: Int, action: ActionModel) -> some View {
        let selected = selectedIndices.contains(idx)
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if selected {
                    selectedIndices.remove(idx)
                } else {
                    selectedIndices.insert(idx)
                }
            }
        } label: {
            HStack(spacing: 4) {
                BundledImage(ImageLoader.actionIcon(action.type.rawValue), size: 12, systemName: MonsterActionRow.actionFallback(action.type))
                Text(actionLabel(action))
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? GlavenTheme.positive.opacity(0.4) : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(selected ? GlavenTheme.positive : Color.clear, lineWidth: 1)
            )
            .scaleEffect(selected ? pulseScale : 1.0)
        }
        .buttonStyle(.plain)
        .onChange(of: selectedIndices) { _, newVal in
            if newVal.contains(idx) {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.0
                }
            }
        }
    }

    // MARK: - Logic

    private func isInteractive(_ action: ActionModel) -> Bool {
        let hasSelfTarget = action.subActions?.contains(where: {
            $0.type == .specialTarget && ($0.value?.stringValue ?? "").hasPrefix("self")
        }) ?? false

        switch action.type {
        case .heal:
            return hasSelfTarget
        case .condition:
            return hasSelfTarget
        case .element:
            return true  // Element creation/consumption is always interactive
        case .sufferDamage:
            return true
        default:
            return false
        }
    }

    private func actionLabel(_ action: ActionModel) -> String {
        switch action.type {
        case .heal:
            let val = action.value?.intValue ?? 0
            return "Heal \(val)"
        case .condition:
            let name = action.value?.stringValue ?? ""
            return name.replacingOccurrences(of: "-", with: " ").capitalized
        case .element:
            let name = action.value?.stringValue ?? ""
            let verb = action.valueType == .minus ? "Use" : "Create"
            return "\(verb) \(name.capitalized)"
        case .sufferDamage:
            let val = action.value?.intValue ?? 0
            return "Suffer \(val)"
        default:
            return action.type.rawValue.capitalized
        }
    }

    // MARK: - Apply / Skip

    private func applySelected() {
        gameManager.pushUndoState()

        for idx in selectedIndices.sorted() {
            guard let actions = ability.actions, idx < actions.count else { continue }
            let action = actions[idx]
            applyAction(action)
        }

        // Tag entities so actions aren't applied again
        for entity in monster.aliveEntities {
            for idx in selectedIndices {
                let tag = "roundAction-\(idx)-\(ability.initiative)"
                if !entity.tags.contains(tag) {
                    entity.tags.append(tag)
                }
            }
        }

        selectedIndices.removeAll()
    }

    private func skipAll() {
        // Tag all interactive actions as used without applying
        gameManager.pushUndoState()
        for entity in monster.aliveEntities {
            for (idx, _) in interactiveActions {
                let tag = "roundAction-\(idx)-\(ability.initiative)"
                if !entity.tags.contains(tag) {
                    entity.tags.append(tag)
                }
            }
        }
        selectedIndices.removeAll()
    }

    private func applyAction(_ action: ActionModel) {
        switch action.type {
        case .heal:
            let healVal = action.value?.intValue ?? 0
            for entity in monster.aliveEntities {
                let newHP = min(entity.maxHealth, entity.health + healVal)
                entity.health = newHP
            }

        case .condition:
            let condName = action.value?.stringValue ?? ""
            if let conditionName = ConditionName(rawValue: condName) {
                for entity in monster.aliveEntities {
                    gameManager.entityManager.addCondition(conditionName, to: entity)
                }
            }

        case .element:
            let elemName = action.value?.stringValue ?? ""
            if let elemType = ElementType(rawValue: elemName) {
                if action.valueType == .minus {
                    // Consume element
                    if let idx = gameManager.game.elementBoard.firstIndex(where: { $0.type == elemType && ($0.state == .strong || $0.state == .waning) }) {
                        gameManager.game.elementBoard[idx].state = .consumed
                    }
                } else {
                    // Create element
                    if let idx = gameManager.game.elementBoard.firstIndex(where: { $0.type == elemType }) {
                        if gameManager.game.elementBoard[idx].state != .always {
                            gameManager.game.elementBoard[idx].state = .new
                        }
                    }
                }
            }

        case .sufferDamage:
            let dmg = action.value?.intValue ?? 0
            for entity in monster.aliveEntities {
                entity.health = max(0, entity.health - dmg)
                if entity.health <= 0 {
                    entity.dead = true
                }
            }

        default:
            break
        }
    }
}
