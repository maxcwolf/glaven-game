import SwiftUI

/// The choices a scenario's rewards need (GH p.47): who takes each item, how the collective gold
/// is split, which location opens, on the results screen in the board's look: names as chips,
/// gold handed out with − and +.
struct RewardChoicesView: View {
    @Environment(GameManager.self) private var gameManager
    let rewards: ScenarioRewards
    let edition: String
    @Binding var choices: ScenarioRewardChoices

    /// The defaults the choices start from: the first eligible characters take the items, the
    /// gold is split evenly, the first location opens.
    static func defaultChoices(for rewards: ScenarioRewards, edition: String,
                               manager: ScenarioManager) -> ScenarioRewardChoices {
        var choices = ScenarioRewardChoices()
        for grant in ScenarioManager.rewardItemGrants(rewards) {
            let key = "\(edition)-\(grant.id)"
            choices.itemRecipients[key] = manager.eligibleItemRecipients(key).prefix(grant.count).map(\.id)
        }
        if let gold = rewards.collectiveGold {
            choices.collectiveGold = manager.collectiveGoldShares(total: manager.resolveRewardInt(gold))
        }
        choices.location = rewards.chooseLocation?.first
        return choices
    }

    /// Whether every coin of the collective gold has been handed out.
    static func goldAssigned(_ choices: ScenarioRewardChoices, rewards: ScenarioRewards?, manager: ScenarioManager) -> Bool {
        guard let gold = rewards?.collectiveGold else { return true }
        return choices.collectiveGold.values.reduce(0, +) == manager.resolveRewardInt(gold)
    }

    static func needsChoices(_ rewards: ScenarioRewards) -> Bool {
        !(rewards.items ?? []).isEmpty || rewards.collectiveGold != nil
            || !(rewards.chooseLocation ?? []).isEmpty
    }

    private var manager: ScenarioManager { gameManager.scenarioManager }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TownSmallCaps(text: "Rewards to hand out", lit: true)
            ForEach(ScenarioManager.rewardItemGrants(rewards), id: \.id) { grant in
                itemPicker(id: grant.id, count: grant.count)
            }
            if let gold = rewards.collectiveGold {
                collectiveGoldSplit(total: manager.resolveRewardInt(gold))
            }
            if let locations = rewards.chooseLocation, !locations.isEmpty {
                locationPicker(locations)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
    }

    private func displayName(_ character: GameCharacter) -> String {
        GameText.characterName(character, labels: gameManager.editionStore)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(BoardTheme.font(size: 15, weight: .semibold))
            .foregroundStyle(BoardTheme.text)
    }

    private func note(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(BoardTheme.font(size: 13, weight: warning ? .semibold : .regular))
            .foregroundStyle(warning ? BoardTheme.brass : BoardTheme.secondaryText)
    }

    /// A choice among names, as chips: the chosen one lit.
    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(on ? .boardPrimaryCompact : .boardQuietCompact)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder
    private func itemPicker(id: Int, count: Int) -> some View {
        let key = "\(edition)-\(id)"
        let name = gameManager.editionStore.itemData(id: id, edition: edition)?.name ?? "Item \(id)"
        let eligible = manager.eligibleItemRecipients(key)
        VStack(alignment: .leading, spacing: 6) {
            heading(count > 1 ? "\(count)\u{00D7} \(name)" : name)
            if eligible.isEmpty {
                note("Everyone already owns one \u{2014} it goes to the city\u{2019}s supply")
            }
            ForEach(0..<min(count, eligible.count), id: \.self) { copy in
                let binding = recipient(key, copy: copy)
                HStack(spacing: 8) {
                    note(count > 1 ? "Copy \(copy + 1) to" : "Goes to")
                    FlowLayout(spacing: 6) {
                        ForEach(eligible, id: \.id) { character in
                            chip(displayName(character), on: binding.wrappedValue == character.id) {
                                binding.wrappedValue = character.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func recipient(_ key: String, copy: Int) -> Binding<String> {
        Binding(
            get: {
                let ids = choices.itemRecipients[key] ?? []
                return copy < ids.count ? ids[copy] : ""
            },
            set: { id in
                var ids = choices.itemRecipients[key] ?? []
                while ids.count <= copy { ids.append("") }
                // A character can only take one copy: swap with the copy they held.
                if let other = ids.firstIndex(of: id), other != copy { ids[other] = ids[copy] }
                ids[copy] = id
                choices.itemRecipients[key] = ids
            }
        )
    }

    @ViewBuilder
    private func collectiveGoldSplit(total: Int) -> some View {
        let assigned = choices.collectiveGold.values.reduce(0, +)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                heading("Share the party\u{2019}s gold")
                TownGold(amount: total, size: 13)
            }
            ForEach(manager.rewardParty, id: \.id) { character in
                let share = choices.collectiveGold[character.id] ?? 0
                let most = share + total - assigned
                HStack(spacing: 10) {
                    Text(displayName(character))
                        .font(BoardTheme.font(size: 14, weight: .semibold))
                        .foregroundStyle(BoardTheme.text)
                        .frame(width: 140, alignment: .leading)
                    Button { goldShare(character.id).wrappedValue = max(0, share - 1) } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.boardQuietCompact)
                    .disabled(share == 0)
                    .accessibilityLabel("One gold less for \(displayName(character))")
                    TownGold(amount: share, size: 13)
                        .frame(minWidth: 44)
                    Button { goldShare(character.id).wrappedValue = min(most, share + 1) } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.boardQuietCompact)
                    .disabled(share >= most)
                    .accessibilityLabel("One gold more for \(displayName(character))")
                }
                .accessibilityElement(children: .contain)
            }
            if assigned != total {
                note("\(total - assigned) gold still to hand out", warning: true)
            }
        }
    }

    private func goldShare(_ id: String) -> Binding<Int> {
        Binding(
            get: { choices.collectiveGold[id] ?? 0 },
            set: { choices.collectiveGold[id] = $0 }
        )
    }

    @ViewBuilder
    private func locationPicker(_ locations: [String]) -> some View {
        let chosen = choices.location ?? locations[0]
        VStack(alignment: .leading, spacing: 6) {
            heading("Unlock one location")
            FlowLayout(spacing: 6) {
                ForEach(locations, id: \.self) { index in
                    let name = gameManager.editionStore.scenarioData(index: index, edition: edition)?.name
                    chip(name.map { "#\(index) \($0)" } ?? "Scenario \(index)", on: chosen == index) {
                        choices.location = index
                    }
                }
            }
        }
    }
}
