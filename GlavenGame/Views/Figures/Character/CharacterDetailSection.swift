import SwiftUI

/// Expanded detail panel shown when a character card is tapped.
struct CharacterDetailSection: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.editionTheme) private var theme

    @Binding var showCharacterSheet: Bool
    @Binding var showPerks: Bool
    @Binding var showBattleGoal: Bool
    @Binding var showConditions: Bool
    @Binding var showAbilityCards: Bool
    @Binding var showHandManagement: Bool

    @State private var showItemShop = false
    @State private var showAddSummon = false

    private var characterColor: Color {
        Color(hex: character.color) ?? .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(characterColor.opacity(0.3))

            // Health bar
            HealthBarView(current: character.health, max: character.maxHealth, color: characterColor) { newHealth in
                gameManager.entityManager.changeHealth(character, amount: newHealth - character.health)
            }

            // Stats row
            statsRow

            // Action buttons
            actionButtons

            // Battle goal
            battleGoalRow

            // Items
            if !character.items.isEmpty {
                CharacterItemsView(character: character)
            }

            // Conditions
            if !character.entityConditions.isEmpty {
                ConditionBadgesView(conditions: character.entityConditions) { condition in
                    gameManager.entityManager.removeCondition(condition.name, from: character)
                }
            }

            // Summons
            if !character.summons.isEmpty || character.characterData?.availableSummons?.isEmpty == false {
                summonsSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .sheet(isPresented: $showItemShop) {
            ItemShopSheet(character: character)
        }
        .sheet(isPresented: $showAddSummon) {
            AddSummonSheet(character: character)
        }
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 16) {
            Text("Lv \(character.level)")
                .font(.system(size: 12 * scale))
                .foregroundStyle(GlavenTheme.secondaryText)
            Text("Hand \(character.handSize)")
                .font(.system(size: 12 * scale))
                .foregroundStyle(GlavenTheme.secondaryText)

            Spacer()

            // XP +/-
            HStack(spacing: 4) {
                Button { gameManager.characterManager.addXP(-1, to: character) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)
                HStack(spacing: 2) {
                    GameIcon(image: ImageLoader.statusIcon("experience"), fallbackSystemName: "star.fill", size: 12, color: .blue)
                    Text("\(character.experience) XP")
                        .font(.system(size: 12 * scale))
                }
                Button { gameManager.characterManager.addXP(1, to: character) } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            // Gold +/-
            HStack(spacing: 4) {
                Button { gameManager.characterManager.addLoot(-1, to: character) } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)
                HStack(spacing: 2) {
                    GameIcon(image: ImageLoader.statusIcon("loot"), fallbackSystemName: "dollarsign.circle.fill", size: 12, color: .yellow)
                    Text("\(character.loot) Gold")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.yellow)
                }
                Button { gameManager.characterManager.addLoot(1, to: character) } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                detailButton("Sheet", icon: "person.text.rectangle", badge: 0) {
                    showCharacterSheet = true
                }
                if character.characterData?.perks?.isEmpty == false {
                    detailButton("Perks", icon: "list.bullet.rectangle", badge: selectedPerkCount) {
                        showPerks = true
                    }
                }
                detailButton(
                    character.battleGoalCardIds.isEmpty ? "Battle Goal" : "Goal",
                    icon: "flag",
                    badge: character.selectedBattleGoal != nil ? 1 : 0
                ) {
                    showBattleGoal = true
                }
                detailButton("Conditions", icon: "cross.circle", badge: character.entityConditions.count) {
                    showConditions = true
                }
                detailButton("Cards", icon: "rectangle.portrait.on.rectangle.portrait", badge: 0) {
                    showAbilityCards = true
                }
                detailButton("Hand", icon: "hand.raised", badge: character.handCards.count) {
                    showHandManagement = true
                }
                detailButton("Items", icon: "bag", badge: character.items.count) {
                    showItemShop = true
                }
                if character.characterData?.availableSummons?.isEmpty == false {
                    detailButton("Summon", icon: "person.badge.plus", badge: character.summons.count) {
                        showAddSummon = true
                    }
                }
            }
        }
    }

    private var selectedPerkCount: Int {
        character.selectedPerks.reduce(0, +)
    }

    @ViewBuilder
    private func detailButton(_ label: String, icon: String, badge: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11 * scale))
                Text(label)
                    .font(.system(size: 11 * scale, weight: .medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(characterColor.opacity(0.6))
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(GlavenTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(GlavenTheme.primaryText.opacity(GlavenTheme.isLight ? 0.12 : 0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(GlavenTheme.primaryText.opacity(GlavenTheme.isLight ? 0.2 : 0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Battle Goal Row

    @ViewBuilder
    private var battleGoalRow: some View {
        if let goalIdx = character.selectedBattleGoal,
           goalIdx < character.battleGoalCardIds.count,
           let goal = gameManager.editionStore.battleGoal(cardId: character.battleGoalCardIds[goalIdx]) {
            HStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GlavenTheme.positive)
                Text(goal.name)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(GlavenTheme.primaryText)
                HStack(spacing: 2) {
                    ForEach(0..<goal.checks, id: \.self) { _ in
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Summons Section

    @ViewBuilder
    private var summonsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Summons")
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(GlavenTheme.secondaryText)
                Spacer()
                if character.characterData?.availableSummons?.isEmpty == false {
                    Button { showAddSummon = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(character.summons, id: \.uuid) { summon in
                SummonView(summon: summon, character: character)
            }
        }
    }
}
