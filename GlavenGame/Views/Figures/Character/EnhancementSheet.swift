import SwiftUI

struct EnhancementSheet: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAbility: AbilityModel?
    @State private var enhancementTarget: EnhancementTarget?

    private var edition: String { character.edition }

    private var allAbilities: [AbilityModel] {
        guard let data = character.characterData else { return [] }
        let deckName = data.deck ?? character.name
        return gameManager.editionStore.abilities(forDeck: deckName, edition: edition)
            .filter {
                let lvl = $0.level?.intValue ?? 0
                let str = $0.level?.stringValue ?? ""
                return lvl <= character.level || str == "X"
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(allAbilities) { ability in
                        enhancementCardView(ability)
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Enhancements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $enhancementTarget) { target in
                EnhancementPickerSheet(
                    target: target,
                    character: character,
                    edition: edition
                )
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Card View

    @ViewBuilder
    private func enhancementCardView(_ ability: AbilityModel) -> some View {
        let cardId = ability.cardId ?? 0
        let enhCount = EnhancementsManager.enhancementCount(on: cardId, in: character.enhancements)

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("#\(cardId)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)
                Text(ability.name ?? "")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(GlavenTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                if enhCount > 0 {
                    Text("\(enhCount) enhanced")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }
                if let level = ability.level {
                    Text("Lv \(level.stringValue)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider().background(GlavenTheme.primaryText.opacity(0.1))

            // Top actions
            if let actions = ability.actions, !actions.isEmpty {
                actionsSection("Top", half: "top", actions: actions, ability: ability)
            }

            // Bottom actions
            if let actions = ability.bottomActions, !actions.isEmpty {
                Divider().background(GlavenTheme.primaryText.opacity(0.05)).padding(.horizontal, 10)
                actionsSection("Bottom", half: "bottom", actions: actions, ability: ability)
            }
        }
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(enhCount > 0 ? Color.green.opacity(0.3) : GlavenTheme.primaryText.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionsSection(_ label: String, half: String, actions: [ActionModel], ability: AbilityModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.secondaryText)

            ForEach(Array(actions.enumerated()), id: \.offset) { idx, action in
                actionWithSlots(action, cardId: ability.cardId ?? 0, half: half, actionIndex: idx, ability: ability)

                // Sub-actions
                if let subs = action.subActions {
                    ForEach(Array(subs.enumerated()), id: \.offset) { subIdx, sub in
                        HStack(spacing: 4) {
                            Spacer().frame(width: 16)
                            actionWithSlots(sub, cardId: ability.cardId ?? 0, half: half, actionIndex: idx * 100 + subIdx + 1, ability: ability)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionWithSlots(_ action: ActionModel, cardId: Int, half: String, actionIndex: Int, ability: AbilityModel) -> some View {
        HStack(spacing: 6) {
            // Action description
            Text(describeAction(action))
                .font(.caption)
                .foregroundStyle(GlavenTheme.primaryText)
                .lineLimit(1)

            Spacer()

            // Enhancement slots
            if let slots = action.enhancementTypes, !slots.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { slotIdx, slotType in
                        let existing = EnhancementsManager.enhancement(
                            on: cardId, half: half, actionIndex: actionIndex, slotIndex: slotIdx,
                            in: character.enhancements
                        )
                        enhancementSlotButton(
                            slotType: slotType,
                            existing: existing,
                            cardId: cardId,
                            half: half,
                            actionIndex: actionIndex,
                            slotIdx: slotIdx,
                            actionType: action.type,
                            ability: ability
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func enhancementSlotButton(slotType: EnhancementSlotType, existing: Enhancement?,
                                        cardId: Int, half: String, actionIndex: Int, slotIdx: Int,
                                        actionType: ActionType, ability: AbilityModel) -> some View {
        Button {
            if let existing, !existing.inherited {
                // Remove enhancement
                gameManager.enhancementsManager.removeEnhancement(existing, from: character)
            } else if existing == nil {
                // Open picker
                enhancementTarget = EnhancementTarget(
                    cardId: cardId,
                    actionHalf: half,
                    actionIndex: actionIndex,
                    slotIndex: slotIdx,
                    slotType: slotType,
                    actionType: actionType,
                    cardLevel: ability.level?.intValue ?? 1,
                    isLost: ability.lost == true,
                    isPersistent: ability.persistent == true,
                    isSummon: actionType == .summon || actionType == .spawn
                )
            }
        } label: {
            if let existing {
                Text(existing.action.displayName)
                    .font(.system(size: 9))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(existing.inherited ? Color.gray : Color.green)
                    .clipShape(Capsule())
            } else {
                slotIcon(slotType)
                    .font(.system(size: 12))
                    .foregroundStyle(slotColor(slotType).opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(slotColor(slotType).opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func slotIcon(_ type: EnhancementSlotType) -> Image {
        switch type {
        case .square: return Image(systemName: "square")
        case .circle: return Image(systemName: "circle")
        case .diamond: return Image(systemName: "diamond")
        case .diamond_plus: return Image(systemName: "diamond.fill")
        case .hex: return Image(systemName: "hexagon")
        case .any: return Image(systemName: "star")
        }
    }

    private func slotColor(_ type: EnhancementSlotType) -> Color {
        switch type {
        case .square: return .blue
        case .circle: return .green
        case .diamond: return .red
        case .diamond_plus: return .cyan
        case .hex: return .orange
        case .any: return .purple
        }
    }

    private func describeAction(_ action: ActionModel) -> String {
        let value = action.value?.stringValue ?? ""
        let prefix = action.valueType == .plus ? "+" : (action.valueType == .minus ? "-" : "")
        switch action.type {
        case .attack: return "\(prefix)\(value) Attack"
        case .move: return "\(prefix)\(value) Move"
        case .heal: return "Heal \(value)"
        case .shield: return "Shield \(value)"
        case .retaliate: return "Retaliate \(value)"
        case .range: return "\(prefix)\(value) Range"
        case .target: return "\(prefix)\(value) Target"
        case .condition: return value.replacingOccurrences(of: "-", with: " ").capitalized
        case .element: return "\(value.capitalized) Element"
        case .push: return "Push \(value)"
        case .pull: return "Pull \(value)"
        case .pierce: return "Pierce \(value)"
        case .loot: return "Loot \(value)"
        case .jump: return "Jump"
        case .summon, .spawn: return "Summon"
        case .area: return "Area"
        case .custom: return value
        default: return action.type.rawValue.capitalized
        }
    }
}

// MARK: - Enhancement Target

struct EnhancementTarget: Identifiable {
    let id = UUID()
    var cardId: Int
    var actionHalf: String
    var actionIndex: Int
    var slotIndex: Int
    var slotType: EnhancementSlotType
    var actionType: ActionType
    var cardLevel: Int
    var isLost: Bool
    var isPersistent: Bool
    var isSummon: Bool
}

// MARK: - Enhancement Picker

struct EnhancementPickerSheet: View {
    let target: EnhancementTarget
    @Bindable var character: GameCharacter
    let edition: String
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var availableActions: [EnhancementAction] {
        EnhancementsManager.availableActions(
            for: target.slotType,
            actionType: target.actionType,
            isSummon: target.isSummon,
            edition: edition
        )
    }

    private var previousEnhancementsOnCard: Int {
        EnhancementsManager.enhancementCount(on: target.cardId, in: character.enhancements)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Enhancement Slot") {
                    infoRow("Slot Type", value: target.slotType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    infoRow("Action", value: target.actionType.rawValue.capitalized)
                    infoRow("Card Level", value: "\(target.cardLevel)")
                    infoRow("Existing Enhancements", value: "\(previousEnhancementsOnCard)")
                }

                Section("Available Enhancements") {
                    ForEach(availableActions, id: \.self) { action in
                        let cost = EnhancementsManager.enhancementCost(
                            action: action,
                            slotType: target.slotType,
                            actionType: target.actionType,
                            cardLevel: target.cardLevel,
                            previousEnhancements: previousEnhancementsOnCard,
                            isMultiTarget: false,
                            isLost: target.isLost,
                            isPersistent: target.isPersistent,
                            isSummon: target.isSummon,
                            edition: edition
                        )
                        Button {
                            applyEnhancement(action)
                        } label: {
                            HStack {
                                enhancementIcon(action)
                                    .frame(width: 24)
                                Text(action.displayName)
                                    .foregroundStyle(GlavenTheme.primaryText)
                                Spacer()
                                Text("\(cost)g")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                                    .foregroundStyle(character.loot >= cost ? .green : .red)
                            }
                        }
                        .disabled(character.loot < cost)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlavenTheme.background)
            .navigationTitle("Choose Enhancement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 350, minHeight: 400)
    }

    private func applyEnhancement(_ action: EnhancementAction) {
        let cost = EnhancementsManager.enhancementCost(
            action: action,
            slotType: target.slotType,
            actionType: target.actionType,
            cardLevel: target.cardLevel,
            previousEnhancements: previousEnhancementsOnCard,
            isMultiTarget: false,
            isLost: target.isLost,
            isPersistent: target.isPersistent,
            isSummon: target.isSummon,
            edition: edition
        )
        guard character.loot >= cost else { return }

        let enhancement = Enhancement(
            cardId: target.cardId,
            actionHalf: target.actionHalf,
            actionIndex: target.actionIndex,
            slotIndex: target.slotIndex,
            action: action
        )

        gameManager.pushUndoState()
        character.loot -= cost
        character.enhancements.append(enhancement)
        dismiss()
    }

    @ViewBuilder
    private func enhancementIcon(_ action: EnhancementAction) -> some View {
        if action == .plus1 {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
        } else if action == .hex {
            Image(systemName: "hexagon.fill")
                .foregroundStyle(.orange)
        } else if action == .jump {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
        } else if action.isElement {
            Image(systemName: "flame.fill")
                .foregroundStyle(.purple)
        } else if action.isNegativeCondition {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if action.isPositiveCondition {
            Image(systemName: "heart.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "circle.fill")
                .foregroundStyle(.gray)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(GlavenTheme.primaryText)
        }
    }
}
