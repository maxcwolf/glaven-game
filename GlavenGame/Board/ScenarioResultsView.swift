import SwiftUI

/// The end of a scenario: won or lost, why, and what each character takes away — experience
/// gained in the scenario plus the success bonus, gold, and any level they can now reach — then
/// the scenario's rewards. Finish applies them.
struct ScenarioResultsView: View {
    @Environment(GameManager.self) private var gameManager
    let outcome: ScenarioOutcome
    let onFinish: (ScenarioRewardChoices) -> Void
    @State private var choices = ScenarioRewardChoices()

    /// The scenario's rewards when it was won and they need the players to choose.
    private var rewardsToChoose: (ScenarioRewards, String)? {
        guard outcome.victory, let data = gameManager.game.scenario?.data, let rewards = data.rewards,
              RewardChoicesView.needsChoices(rewards) else { return nil }
        return (rewards, data.edition)
    }

    private var canFinish: Bool {
        RewardChoicesView.goldAssigned(choices, rewards: rewardsToChoose?.0, manager: gameManager.scenarioManager)
    }

    private var tint: Color { outcome.victory ? BoardTheme.victory : BoardTheme.defeat }

    var body: some View {
        ZStack {
            BoardTheme.scrim.ignoresSafeArea()
            VStack(spacing: 20) {
                header
                HStack(alignment: .top, spacing: 12) {
                    ForEach(outcome.heroes) { hero in
                        heroCard(hero)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)   // cards share the tallest card's height
                if !outcome.rewards.isEmpty { rewards }
                if let (rewards, edition) = rewardsToChoose {
                    RewardChoicesView(rewards: rewards, edition: edition, choices: $choices,
                                      textColor: BoardTheme.text, surface: BoardTheme.raised)
                }
                Text(outcome.note)
                    .font(.footnote)
                    .foregroundStyle(BoardTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Button { onFinish(choices) } label: {
                    Label(outcome.victory ? "Finish Scenario" : "Back to Town",
                          systemImage: outcome.victory ? "checkmark.circle.fill" : "arrow.uturn.left.circle.fill")
                        .font(.headline)
                        .frame(minWidth: 200, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(outcome.victory ? BoardTheme.brass : BoardTheme.defeat)
                .keyboardShortcut(.defaultAction)
                .disabled(!canFinish)
            }
            .padding(28)
            .frame(maxWidth: 760)
            .fixedSize(horizontal: false, vertical: true)
            .boardPanel()
            .padding(24)
        }
        .onAppear {
            if let (rewards, edition) = rewardsToChoose {
                choices = RewardChoicesView.defaultChoices(for: rewards, edition: edition,
                                                           manager: gameManager.scenarioManager)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(outcome.victory ? "Victory" : "Defeat")
                .font(BoardTheme.display(52))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            Text(outcome.title)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
            Text(outcome.reason)
                .font(.title3)
                .foregroundStyle(BoardTheme.text)
                .multilineTextAlignment(.center)
            Text(outcome.rounds == 1 ? "1 round" : "\(outcome.rounds) rounds")
                .font(.subheadline)
                .foregroundStyle(BoardTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private func heroCard(_ hero: ScenarioOutcome.Hero) -> some View {
        VStack(spacing: 10) {
            portrait(hero)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().stroke(tint.opacity(0.8), lineWidth: 2))
                .saturation(hero.exhausted ? 0.2 : 1)
            Text(hero.name)
                .font(.headline)
                .foregroundStyle(BoardTheme.text)
                .lineLimit(1)
            if hero.exhausted {
                Text("Exhausted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoardTheme.defeat)
            }
            VStack(alignment: .leading, spacing: 4) {
                stat("Experience", "+\(hero.xpGained)")
                if hero.bonusXP > 0 { stat("Success bonus", "+\(hero.bonusXP)") }
                stat("Gold", "+\(hero.goldGained)")
            }
            if let goal = hero.battleGoal {
                Label(goal.met ? "\(goal.name): +\(goal.checks) \(goal.checks == 1 ? "checkmark" : "checkmarks")" : "\(goal.name): not met",
                      systemImage: goal.met ? "checkmark.square.fill" : "square")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(goal.met ? BoardTheme.brass : BoardTheme.secondaryText)
            }
            if let level = hero.levelUpTo {
                Label("Can reach level \(level)", systemImage: "arrow.up.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoardTheme.gain)
            }
        }
        .padding(14)
        .frame(minWidth: 170, maxHeight: .infinity, alignment: .top)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(BoardTheme.secondaryText)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().foregroundStyle(BoardTheme.text)
        }
        .font(.subheadline)
    }

    private var rewards: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("REWARDS", systemImage: "gift")
                .font(.caption.weight(.bold))
                .foregroundStyle(BoardTheme.brass)
            ForEach(outcome.rewards, id: \.self) { line in
                Text(line)
                    .font(.body)
                    .foregroundStyle(BoardTheme.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func portrait(_ hero: ScenarioOutcome.Hero) -> some View {
        if let image = ImageLoader.characterThumbnail(edition: hero.edition, name: hero.className) {
            #if os(macOS)
            Image(nsImage: image).resizable().scaledToFill()
            #else
            Image(uiImage: image).resizable().scaledToFill()
            #endif
        } else {
            Circle().fill(BoardTheme.raised)
        }
    }
}
