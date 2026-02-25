import SwiftUI

struct CharacterSheetView: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editionTheme) private var theme

    @State private var selectedTab = 0
    @State private var editingTitle: String = ""
    @State private var notesText: String = ""

    private var characterColor: Color {
        Color(hex: character.color) ?? .blue
    }

    private var className: String {
        character.name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                tabContent
            }
            .background(GlavenTheme.background)
            .navigationTitle("Character Sheet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitPendingChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editingTitle = character.title
                notesText = character.notes
            }
        }
    }

    // MARK: - Tab Picker

    @ViewBuilder
    private var picker: some View {
        Picker("Tab", selection: $selectedTab) {
            Text("Overview").tag(0)
            Text("Perks").tag(1)
            Text("Items").tag(2)
            Text("Quest").tag(3)
            Text("Notes").tag(4)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onChange(of: selectedTab) { _, _ in
            commitPendingChanges()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0: overviewTab
        case 1: perksTab
        case 2: itemsTab
        case 3: PersonalQuestView(character: character)
        case 4: notesTab
        default: overviewTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                characterHeader
                levelGrid
                statsSection
                goldSection
            }
            .padding()
        }
    }

    @ViewBuilder
    private var characterHeader: some View {
        HStack(spacing: 14) {
            ThumbnailImage(
                image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                size: 64,
                cornerRadius: 12,
                fallbackColor: characterColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(className)
                    .font(theme.titleFont(size: 20))
                    .foregroundStyle(GlavenTheme.primaryText)

                TextField("Character Name", text: $editingTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit {
                        gameManager.characterManager.setTitle(editingTitle, for: character)
                    }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var levelGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Level")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GlavenTheme.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                ForEach(1...9, id: \.self) { lvl in
                    Button {
                        gameManager.characterManager.setLevel(lvl, for: character)
                    } label: {
                        Text("\(lvl)")
                            .font(.system(size: 16, weight: lvl == character.level ? .bold : .regular))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(lvl == character.level ? characterColor : GlavenTheme.primaryText.opacity(0.08))
                            .foregroundStyle(lvl == character.level ? .white : GlavenTheme.secondaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            if character.level < 9 {
                let nextThreshold = GameCharacter.xpThresholds[character.level]
                Text("Next level at \(nextThreshold) XP")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stats")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GlavenTheme.secondaryText)

            HStack(spacing: 20) {
                statItem(icon: "heart.fill", color: .red, label: "Health", value: "\(character.maxHealth)")
                statItem(icon: "star.fill", color: .blue, label: "XP", value: "\(character.experience)")
                statItem(icon: "hand.raised.fill", color: .orange, label: "Hand", value: "\(character.handSize)")
            }
        }
    }

    @ViewBuilder
    private func statItem(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GlavenTheme.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(GlavenTheme.primaryText.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var goldSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gold")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GlavenTheme.secondaryText)

            HStack(spacing: 16) {
                Button {
                    gameManager.characterManager.addLoot(-1, to: character)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    GameIcon(image: ImageLoader.statusIcon("loot"), fallbackSystemName: "dollarsign.circle.fill", size: 20, color: .yellow)
                    Text("\(character.loot)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.yellow)
                }

                Button {
                    gameManager.characterManager.addLoot(1, to: character)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(GlavenTheme.primaryText.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Perks Tab

    private var perksTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                deckSummary
                if let perks = character.characterData?.perks {
                    ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                        PerkRow(
                            perk: perk,
                            selected: index < character.selectedPerks.count ? character.selectedPerks[index] : 0
                        ) {
                            gameManager.characterManager.togglePerk(at: index, for: character)
                        }
                    }
                }

                Divider().background(GlavenTheme.primaryText.opacity(0.2))

                battleGoalProgressSection
            }
            .padding()
        }
    }

    @ViewBuilder
    private var deckSummary: some View {
        let count = character.attackModifierDeck.attackModifiers.count
        HStack {
            Text("Deck: \(count) cards")
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.secondaryText)
            Spacer()
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var battleGoalProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Battle Goal Progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlavenTheme.secondaryText)
                Spacer()
                Text("\(character.battleGoalProgress) / 18")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9), spacing: 4) {
                ForEach(0..<18, id: \.self) { i in
                    Button {
                        let newValue = i < character.battleGoalProgress ? i : i + 1
                        gameManager.characterManager.setBattleGoalProgress(newValue, for: character)
                    } label: {
                        Image(systemName: i < character.battleGoalProgress ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundStyle(i < character.battleGoalProgress ? GlavenTheme.positive : GlavenTheme.secondaryText.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            let perksEarned = character.battleGoalProgress / 3
            if perksEarned > 0 {
                Text("\(perksEarned) perk\(perksEarned == 1 ? "" : "s") earned from battle goals")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.positive)
            }
        }
    }

    // MARK: - Items Tab

    private var itemsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !character.items.isEmpty {
                    CharacterItemsView(character: character)
                } else {
                    Text("No items equipped")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
            .padding()
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        VStack(spacing: 0) {
            TextEditor(text: $notesText)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundStyle(GlavenTheme.primaryText)
                .padding(8)
                .background(GlavenTheme.primaryText.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
        }
    }

    // MARK: - Helpers

    private func commitPendingChanges() {
        let trimmedTitle = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != character.title {
            gameManager.characterManager.setTitle(trimmedTitle, for: character)
        }
        if notesText != character.notes {
            gameManager.characterManager.setNotes(notesText, for: character)
        }
    }
}
