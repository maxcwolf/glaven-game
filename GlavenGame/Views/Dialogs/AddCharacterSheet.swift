import SwiftUI

struct AddCharacterSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedLevel = 1
    @State private var showLocked = false
    @State private var confirmingUnlock: String? = nil

    private var existingNames: Set<String> {
        Set(gameManager.game.characters.map(\.name))
    }

    private var edition: String { gameManager.game.edition ?? "gh" }

    private var allCharacters: [CharacterData] {
        gameManager.editionStore.characters(for: edition)
    }

    private var unlockedCharacters: [CharacterData] {
        allCharacters.filter { isUnlocked($0) }
    }

    private var lockedCharacters: [CharacterData] {
        allCharacters.filter { !isUnlocked($0) }
    }

    private func isUnlocked(_ character: CharacterData) -> Bool {
        let isSpoiler = character.spoiler ?? false
        let isLocked = character.locked ?? false
        if !isSpoiler && !isLocked { return true }
        let key = "\(character.edition)-\(character.name)"
        return gameManager.game.unlockedCharacters.contains(key)
    }

    private func filtered(_ characters: [CharacterData]) -> [CharacterData] {
        guard !searchText.isEmpty else { return characters }
        let query = searchText.lowercased()
        return characters.filter {
            $0.name.replacingOccurrences(of: "-", with: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                levelSelector

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Unlocked characters
                        let unlocked = filtered(unlockedCharacters)
                        ForEach(unlocked) { character in
                            let isAdded = existingNames.contains(character.name)
                            characterRow(character, isAdded: isAdded)
                            if character.id != unlocked.last?.id || !lockedCharacters.isEmpty {
                                Divider().background(GlavenTheme.primaryText.opacity(0.1))
                            }
                        }

                        // Locked section
                        let locked = filtered(lockedCharacters)
                        if !locked.isEmpty {
                            lockedSectionHeader
                            if showLocked {
                                ForEach(locked) { character in
                                    lockedCharacterRow(character)
                                    if character.id != locked.last?.id {
                                        Divider().background(GlavenTheme.primaryText.opacity(0.1))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .background(GlavenTheme.background)
            .searchable(text: $searchText, prompt: "Search characters")
            .navigationTitle("Add Character")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 450)
    }

    // MARK: - Level Selector

    @ViewBuilder
    private var levelSelector: some View {
        VStack(spacing: 6) {
            Text("Character Level")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
            HStack(spacing: 4) {
                ForEach(1...9, id: \.self) { level in
                    Button {
                        selectedLevel = level
                    } label: {
                        Text("\(level)")
                            .font(.subheadline)
                            .fontWeight(selectedLevel == level ? .bold : .regular)
                            .frame(width: 34, height: 34)
                            .background(selectedLevel == level ? Color.accentColor : GlavenTheme.primaryText.opacity(0.1))
                            .foregroundStyle(selectedLevel == level ? .white : .secondary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal)
    }

    // MARK: - Character Row

    @ViewBuilder
    private func characterRow(_ character: CharacterData, isAdded: Bool) -> some View {
        let charColor = Color(hex: character.color ?? "#808080") ?? .gray

        Button {
            if !isAdded {
                gameManager.characterManager.addCharacter(name: character.name, edition: edition, level: selectedLevel)
            }
        } label: {
            HStack(spacing: 12) {
                ThumbnailImage(
                    image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                    size: 44,
                    cornerRadius: 8,
                    fallbackColor: charColor
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isAdded ? Color.secondary : GlavenTheme.primaryText)
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 12, color: .red)
                            Text("\(character.healthForLevel(selectedLevel))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Hand \(character.resolvedHandSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(GlavenTheme.positive)
                        .font(.title3)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .opacity(isAdded ? 0.5 : 1.0)
    }

    // MARK: - Locked Section

    @ViewBuilder
    private var lockedSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showLocked.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Locked Characters (\(lockedCharacters.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(GlavenTheme.secondaryText)
                Spacer()
                Image(systemName: showLocked ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GlavenTheme.cardBackground.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func lockedCharacterRow(_ character: CharacterData) -> some View {
        let isConfirming = confirmingUnlock == character.name

        HStack(spacing: 12) {
            // Spoiler icon instead of thumbnail
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.gray.opacity(0.4))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                if isConfirming {
                    Text(character.name.replacingOccurrences(of: "-", with: " ").capitalized)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.primaryText)
                } else {
                    Text("???")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.secondaryText)
                }
                Text("Locked")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()

            if isConfirming {
                Button {
                    unlockCharacter(character)
                } label: {
                    Text("Confirm")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    confirmingUnlock = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    confirmingUnlock = character.name
                } label: {
                    Label("Unlock", systemImage: "lock.open.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .opacity(0.7)
    }

    private func unlockCharacter(_ character: CharacterData) {
        gameManager.pushUndoState()
        let key = "\(character.edition)-\(character.name)"
        gameManager.game.unlockedCharacters.insert(key)
        confirmingUnlock = nil
    }
}
