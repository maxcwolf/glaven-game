import SwiftUI

/// The choices a scenario's rewards need (GH p.47): who takes each item, how the collective gold
/// is split, which location opens. Used by the results screen on the board and the old sheet.
struct RewardChoicesView: View {
    @Environment(GameManager.self) private var gameManager
    let rewards: ScenarioRewards
    let edition: String
    @Binding var choices: ScenarioRewardChoices
    /// Colours, so the view sits on the board's panels as well as the menus'.
    var textColor: Color = GlavenTheme.primaryText
    var surface: Color = GlavenTheme.cardBackground

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
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Rewards")
                .font(.headline)
                .foregroundStyle(textColor)

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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func displayName(_ character: GameCharacter) -> String {
        GameText.characterName(character, labels: gameManager.editionStore)
    }

    @ViewBuilder
    private func itemPicker(id: Int, count: Int) -> some View {
        let key = "\(edition)-\(id)"
        let name = gameManager.editionStore.itemData(id: id, edition: edition)?.name ?? "Item \(id)"
        let eligible = manager.eligibleItemRecipients(key)
        VStack(alignment: .leading, spacing: 4) {
            Text(count > 1 ? "\(count)× \(name)" : name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(textColor)
            if eligible.isEmpty {
                Text("Everyone already owns one — it goes to the city's supply")
                    .font(.subheadline)
                    .foregroundStyle(textColor.opacity(0.7))
            }
            ForEach(0..<min(count, eligible.count), id: \.self) { copy in
                Picker(count > 1 ? "Copy \(copy + 1) goes to" : "Goes to", selection: recipient(key, copy: copy)) {
                    ForEach(eligible, id: \.id) { character in
                        Text(displayName(character)).tag(character.id)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(textColor)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Split \(total) collective gold")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(textColor)
            ForEach(manager.rewardParty, id: \.id) { character in
                let share = choices.collectiveGold[character.id] ?? 0
                Stepper(value: goldShare(character.id), in: 0...max(0, share + total - assigned)) {
                    Text("\(displayName(character)): \(share) gold")
                        .font(.subheadline)
                        .foregroundStyle(textColor)
                }
            }
            if assigned != total {
                Text("\(total - assigned) gold still to hand out")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
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
        Picker("Unlock one location", selection: Binding(
            get: { choices.location ?? locations[0] },
            set: { choices.location = $0 }
        )) {
            ForEach(locations, id: \.self) { index in
                let name = gameManager.editionStore.scenarioData(index: index, edition: edition)?.name
                Text(name.map { "#\(index) \($0)" } ?? "Scenario \(index)").tag(index)
            }
        }
        .font(.subheadline)
        .foregroundStyle(textColor)
    }
}
