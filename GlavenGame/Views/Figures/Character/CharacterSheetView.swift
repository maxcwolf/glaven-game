import SwiftUI

/// A character's sheet, one page in the board's look: their level and progress, health, hand and
/// gold, personal quest, battle-goal checkmarks and notes on the left; their perks, in the
/// rulebook's words, and the items they own on the right.
struct CharacterSheetView: View {
    @Bindable var character: GameCharacter
    var onShop: (() -> Void)? = nil
    let onDone: () -> Void
    @Environment(GameManager.self) private var gameManager

    @State private var editingTitle = ""
    @State private var notesText = ""

    private var manager: CharacterManager { gameManager.characterManager }
    private var className: String { GameText.className(character.name, edition: character.edition, labels: gameManager.editionStore) }
    private var classColor: Color { Color(hex: character.color) ?? BoardTheme.border }

    var body: some View {
        TownDialog(title: character.title.isEmpty ? className : character.title,
                   subtitle: Self.subtitle(className: className, named: !character.title.isEmpty, level: character.level,
                                           won: character.record.scenariosCompleted.count),
                   portrait: (ImageLoader.characterThumbnail(edition: character.edition, name: character.name), classColor),
                   onDone: close) {
            nameField
        } content: {
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 14) {
                        progress
                        quest
                        battleGoals
                        notes
                    }
                }
                .frame(width: 400)
                ScrollView {
                    VStack(spacing: 14) {
                        perks
                        items
                    }
                }
            }
            .padding(18)
        }
        .onAppear {
            editingTitle = character.title
            notesText = character.notes
        }
    }

    // MARK: - Words

    /// "Level 3 · 6 scenarios won", with the class first once the character has a name.
    static func subtitle(className: String, named: Bool, level: Int, won: Int) -> String {
        let scenarios = won == 0 ? "no scenarios won yet" : "\(won) scenario\(won == 1 ? "" : "s") won"
        return (named ? "\(className) \u{00B7} " : "") + "Level \(level) \u{00B7} \(scenarios)"
    }

    /// The level's progress: how far through the level's experience band, what's left, and the
    /// next level's threshold ("30 XP to level 4", "Level 4 at 150").
    static func levelProgress(level: Int, experience: Int) -> (fraction: Double, toNext: String, next: String) {
        let thresholds = GameCharacter.xpThresholds
        guard level < thresholds.count else { return (1, "Highest level", "") }
        let start = thresholds[level - 1], end = thresholds[level]
        let fraction = Double(experience - start) / Double(max(1, end - start))
        let left = max(0, end - experience)
        return (max(0, min(1, fraction)),
                left == 0 ? "Ready to level up" : "\(left) XP to level \(level + 1)",
                "Level \(level + 1) at \(end)")
    }

    /// "Every three checkmarks earn a perk. One earned."
    static func battleGoalNote(checkmarks: Int) -> String {
        let earned = checkmarks / 3
        let numbers = ["None", "One", "Two", "Three", "Four", "Five", "Six"]
        return "Every three checkmarks earn a perk. \(earned < numbers.count ? numbers[earned] : "\(earned)") earned."
    }

    // MARK: - Header

    private var nameField: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
                .accessibilityHidden(true)
            TextField("Name your \(className)", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.text)
                .onSubmit(commit)
                .accessibilityLabel("Character name")
        }
        .padding(.horizontal, 14)
        .frame(width: 220, height: 36)
        .background(BoardTheme.raised, in: Capsule())
        .overlay(Capsule().stroke(BoardTheme.border.opacity(0.6), lineWidth: 1))
    }

    // MARK: - Left

    private var progress: some View {
        let level = Self.levelProgress(level: character.level, experience: character.experience)
        return TownSection(title: "Level \(character.level)", detail: level.toNext) {
            XPBar(progress: level.fraction, track: BoardTheme.raised)
            HStack {
                Text("\(character.experience) XP")
                    .font(BoardTheme.font(size: 13, weight: .semibold))
                    .foregroundStyle(BoardTheme.text)
                Spacer()
                Text(level.next)
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
            HStack(spacing: 8) {
                tile("heart.fill", "\(character.maxHealth)", "Health", BoardTheme.defeat)
                tile("rectangle.portrait.on.rectangle.portrait.fill", "\(character.handSize)", "Cards", BoardTheme.brass)
                tile("circle.fill", "\(character.loot)", "Gold", BoardTheme.victory)
            }
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(color)
                Text(value)
                    .font(BoardTheme.font(size: 20, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(BoardTheme.text)
            }
            Text(label)
                .font(BoardTheme.font(size: 11, weight: .medium))
                .foregroundStyle(BoardTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    @ViewBuilder
    private var quest: some View {
        if let id = character.personalQuest, let quest = manager.personalQuest(id, edition: character.edition) {
            TownSection(title: quest.name, detail: manager.questComplete(character) ? "Complete" : "Personal quest") {
                ForEach(Array(quest.requirements.enumerated()), id: \.offset) { index, requirement in
                    requirementRow(requirement, index: index, quest: quest)
                }
                Text(quest.reward.map { "Fulfil it to retire. Retiring \($0.prefix(1).lowercased() + $0.dropFirst())." } ?? "Fulfil it to retire.")
                    .font(BoardTheme.font(size: 12))
                    .foregroundStyle(BoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            TownSection(title: "Personal Quest") {
                Text("No quest yet. Choose one in town.")
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(BoardTheme.secondaryText)
            }
        }
    }

    private func requirementRow(_ requirement: PersonalQuest.Requirement, index: Int, quest: PersonalQuest) -> some View {
        let done = { (i: Int) in i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0 }
        let progress = done(index)
        let waiting = requirement.after.contains { done($0) < quest.requirements[$0].target }
        let manual = requirement.tracking == .manual && !waiting
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(requirement.text)
                    .font(BoardTheme.font(size: 14))
                    .foregroundStyle(BoardTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(progress) of \(requirement.target)")
                    .font(BoardTheme.font(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(progress >= requirement.target ? BoardTheme.gain : BoardTheme.brass)
            }
            HStack(spacing: 10) {
                if manual {
                    stepper("minus", "One less", disabled: progress <= 0) { manager.adjustQuest(index, by: -1, for: character) }
                }
                XPBar(progress: Double(progress) / Double(max(1, requirement.target)), track: BoardTheme.raised)
                if manual {
                    stepper("plus", "One more", disabled: progress >= requirement.target) { manager.adjustQuest(index, by: 1, for: character) }
                }
            }
            Text(waiting ? "After the one above." : (requirement.tracking == .manual ? "Counted by hand." : "Counted by the game."))
                .font(BoardTheme.font(size: 11))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }

    private func stepper(_ icon: String, _ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BoardTheme.text)
                .frame(width: 28, height: 28)
                .background(BoardTheme.raised, in: Circle())
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label)
    }

    private var battleGoals: some View {
        let checks = character.battleGoalProgress
        return TownSection(title: "Battle Goals", detail: "\(checks) of \(GameCharacter.maxBattleGoalChecks)") {
            HStack(spacing: 3) {
                ForEach(0..<(GameCharacter.maxBattleGoalChecks / 3), id: \.self) { group in
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            let n = group * 3 + i
                            Button {
                                manager.setBattleGoalProgress(n < checks ? n : n + 1, for: character)
                            } label: {
                                TownCheckBox(ticked: n < checks)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Checkmark \(n + 1)")
                            .accessibilityAddTraits(n < checks ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 3)
                    .background(checks >= group * 3 + 3 ? BoardTheme.brass.opacity(0.15) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text(Self.battleGoalNote(checkmarks: checks))
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }

    private var notes: some View {
        TownSection(title: "Notes") {
            TextEditor(text: $notesText)
                .scrollContentBackground(.hidden)
                .font(BoardTheme.font(size: 14))
                .foregroundStyle(BoardTheme.text)
                .frame(minHeight: 70)
                .padding(6)
                .background(BoardTheme.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                .accessibilityLabel("Notes")
        }
    }

    // MARK: - Right

    private var perks: some View {
        let available = manager.perksAvailable(for: character)
        let deck = character.attackModifierDeck.attackModifiers.count
        return TownSection(title: "Perks", detail: available > 0 ? "\(available) to take" : nil) {
            Text(available > 0 ? "Tap a perk to take it. Your attack modifier deck: \(deck) cards."
                               : "Perks come with each level and every three battle-goal checkmarks. Your attack modifier deck: \(deck) cards.")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                ForEach(Array((character.characterData?.perks ?? []).enumerated()), id: \.offset) { index, perk in
                    perkRow(perk, taken: index < character.selectedPerks.count ? character.selectedPerks[index] : 0) {
                        manager.togglePerk(at: index, for: character)
                    }
                }
            }
        }
    }

    private func perkRow(_ perk: PerkModel, taken: Int, toggle: @escaping () -> Void) -> some View {
        let text = GameText.perkText(perk)
        return Button(action: toggle) {
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    ForEach(0..<perk.count, id: \.self) { i in TownCheckBox(ticked: i < taken) }
                }
                .frame(width: 42, alignment: .leading)
                Text(text)
                    .font(BoardTheme.font(size: 14, weight: taken > 0 ? .semibold : .regular))
                    .foregroundStyle(taken > 0 ? BoardTheme.text : BoardTheme.text.opacity(0.82))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if taken >= perk.count { TownSmallCaps(text: "Taken", lit: true) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 32)
            .background(taken > 0 ? BoardTheme.brass.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: BoardTheme.Radius.small + 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityValue(perk.count > 1 ? "\(taken) of \(perk.count) taken" : (taken > 0 ? "Taken" : "Not taken"))
    }

    private var items: some View {
        let owned = character.items.compactMap { gameManager.editionStore.itemData(key: $0) }
        return TownSection(title: "Items", detail: owned.isEmpty ? nil : "Brings \(character.carriedItems.count) of \(owned.count)") {
            HStack(alignment: .top, spacing: 8) {
                if owned.isEmpty {
                    Text("No items yet.")
                        .font(BoardTheme.font(size: 14))
                        .foregroundStyle(BoardTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(owned) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.slot.displayName.uppercased(), systemImage: item.slot.icon)
                                    .font(BoardTheme.font(size: 11, weight: .bold))
                                    .kerning(1.1)
                                    .foregroundStyle(BoardTheme.secondaryText)
                                    .lineLimit(1)
                                Text(item.name)
                                    .font(BoardTheme.display(16))
                                    .foregroundStyle(BoardTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
                            .opacity(character.itemsLeftBehind.contains(item.itemKey) ? 0.55 : 1)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let onShop {
                    Button("Shop", systemImage: "bag") {
                        close()
                        onShop()
                    }
                    .buttonStyle(.boardQuietCompact)
                }
            }
        }
    }

    // MARK: - Saving

    private func commit() {
        let title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title != character.title { manager.setTitle(title, for: character) }
        if notesText != character.notes { manager.setNotes(notesText, for: character) }
    }

    private func close() {
        commit()
        onDone()
    }
}
