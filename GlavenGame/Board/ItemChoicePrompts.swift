import SwiftUI

/// Which elements an item infuses (Mana Potions, Staff of Elements, Circlet of Elements).
struct ElementChoicePrompt: View {
    let pending: BoardCoordinator.PendingElementChoice
    let coordinator: BoardCoordinator
    @State private var chosen: [ElementType] = []

    var body: some View {
        ItemChoicePanel(title: pending.itemName,
                        detail: pending.count == 1 ? "Infuse one element." : "Infuse \(pending.count) different elements.") {
            HStack(spacing: 10) {
                ForEach(ElementType.gameElements, id: \.self) { element in
                    let on = chosen.contains(element)
                    Button {
                        if let index = chosen.firstIndex(of: element) { chosen.remove(at: index) }
                        else if chosen.count < pending.count { chosen.append(element) }
                    } label: {
                        VStack(spacing: 4) {
                            BundledImage(ImageLoader.elementIcon(element.rawValue), size: 36, systemName: "circle.fill")
                            Text(GameText.elementName(element))
                                .font(.caption)
                                .foregroundStyle(BoardTheme.text)
                        }
                        .padding(8)
                        .background(on ? BoardTheme.brass.opacity(0.35) : BoardTheme.raised,
                                    in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                        .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium)
                            .stroke(on ? BoardTheme.brass : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GameText.elementName(element))
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        } actions: {
            Button(chosen.isEmpty ? "Infuse Nothing" : "Infuse \(GameText.list(chosen.map(GameText.elementName)))") {
                coordinator.resolveElementChoice(chosen)
            }
            .buttonStyle(.borderedProminent)
            .tint(BoardTheme.brass)
        }
    }
}

/// Which negative condition an item removes (Minor Cure Potion).
struct ConditionRemovalPrompt: View {
    let pending: BoardCoordinator.PendingConditionRemoval
    let coordinator: BoardCoordinator

    var body: some View {
        ItemChoicePanel(title: pending.itemName, detail: "Remove one negative condition.") {
            HStack(spacing: 10) {
                ForEach(pending.options, id: \.self) { condition in
                    Button {
                        coordinator.resolveConditionRemoval(condition)
                    } label: {
                        VStack(spacing: 4) {
                            BundledImage(ImageLoader.conditionIcon(condition.rawValue), size: 36, systemName: "bolt.fill")
                            Text(GameText.conditionName(condition))
                                .font(.caption)
                                .foregroundStyle(BoardTheme.text)
                        }
                        .padding(8)
                        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(GameText.conditionName(condition))")
                }
            }
        } actions: {
            Button("Keep Them All") { coordinator.resolveConditionRemoval(nil) }
                .buttonStyle(.bordered)
                .tint(.gray)
        }
    }
}

/// The panel both pickers share: the item's name, what to do, the choices and a button row.
private struct ItemChoicePanel<Choices: View, Actions: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let choices: Choices
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
            Text(detail)
                .font(.body)
                .foregroundStyle(BoardTheme.secondaryText)
            choices
            HStack {
                Spacer()
                actions
            }
            .controlSize(.large)
        }
        .padding(20)
        .boardPanel()
        .padding()
    }
}

/// Boots of Speed / Quickness, once every card is revealed: go earlier, keep, or go later.
struct InitiativeChangePrompt: View {
    let pending: BoardCoordinator.PendingInitiativeChange
    let coordinator: BoardCoordinator

    var body: some View {
        let earlier = max(1, pending.initiative - pending.amount)
        let later = min(99, pending.initiative + pending.amount)
        ItemChoicePanel(title: pending.itemName,
                        detail: "\(coordinator.characterName(pending.characterID)) leads with initiative \(pending.initiative). Every card is revealed: change it by \(pending.amount)?") {
            EmptyView()
        } actions: {
            Button("Earlier (\(earlier))") { coordinator.resolveInitiativeChange(-pending.amount) }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.brass)
            Button("Keep \(pending.initiative)") { coordinator.resolveInitiativeChange(0) }
                .buttonStyle(.bordered)
                .tint(.gray)
            Button("Later (\(later))") { coordinator.resolveInitiativeChange(pending.amount) }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.brass)
        }
        .frame(maxWidth: 560)
    }
}
