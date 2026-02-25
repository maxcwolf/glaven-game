import SwiftUI

struct RetirementSheet: View {
    let character: GameCharacter
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false

    private var quest: PersonalQuestData? {
        guard let cardId = character.personalQuest else { return nil }
        return gameManager.editionStore.personalQuest(cardId: cardId)
    }

    private var isQuestComplete: Bool {
        guard let quest = quest else { return true } // No quest = can retire freely
        for (i, req) in quest.requirements.enumerated() {
            let target = req.counter?.intValue ?? 1
            let progress = i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0
            if progress < target { return false }
        }
        return true
    }

    private var className: String {
        character.name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Character summary
                    characterSummary

                    // Quest status
                    questStatus

                    // Rewards
                    if let quest = quest {
                        rewardsPreview(quest)
                    }

                    // Prosperity bonus
                    prosperityNote

                    // Stats summary
                    statsSummary

                    // Confirm
                    if isQuestComplete {
                        confirmSection
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text("Personal quest is not yet complete.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            Text("You can still force retire without completing the quest.")
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)

                            Button(role: .destructive) {
                                performRetirement()
                            } label: {
                                Label("Force Retire", systemImage: "exclamationmark.triangle")
                                    .font(.subheadline)
                            }
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Retire Character")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Character Summary

    @ViewBuilder
    private var characterSummary: some View {
        HStack(spacing: 14) {
            ThumbnailImage(
                image: ImageLoader.characterThumbnail(edition: character.edition, name: character.name),
                size: 56,
                cornerRadius: 10,
                fallbackColor: Color(hex: character.color) ?? .blue
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(character.title.isEmpty ? className : character.title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(GlavenTheme.primaryText)
                Text(className)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
                Text("Level \(character.level) | XP: \(character.experience) | Gold: \(character.loot)")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            Spacer()
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Quest Status

    @ViewBuilder
    private var questStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "scroll.fill")
                    .foregroundStyle(.orange)
                Text("Personal Quest")
                    .font(.headline)
                Spacer()
                if isQuestComplete {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                } else {
                    Text("Incomplete")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let quest = quest {
                Text("Quest #\(quest.cardId)")
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)

                ForEach(Array(quest.requirements.enumerated()), id: \.offset) { i, req in
                    let target = req.counter?.intValue ?? 1
                    let progress = i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0
                    HStack {
                        Image(systemName: progress >= target ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(progress >= target ? .green : GlavenTheme.secondaryText)
                        Text("\(progress)/\(target)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
            } else {
                Text("No quest assigned")
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Rewards Preview

    @ViewBuilder
    private func rewardsPreview(_ quest: PersonalQuestData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.purple)
                Text("Retirement Rewards")
                    .font(.headline)
            }

            if let unlock = quest.unlockCharacter {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(.purple)
                    Text("Unlock: \(unlock.replacingOccurrences(of: "-", with: " ").capitalized)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }

            if let envelope = quest.openEnvelope {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                        .foregroundStyle(.orange)
                    Text("Open Envelope: \(envelope)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "building.2.crop.circle")
                    .foregroundStyle(.green)
                Text("+1 Prosperity (retirement bonus)")
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.primaryText)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Prosperity Note

    @ViewBuilder
    private var prosperityNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(GlavenTheme.accentText)
            Text("Retiring grants +1 prosperity to the party. The character will be archived.")
                .font(.caption)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .padding()
        .background(GlavenTheme.accentText.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Stats Summary

    @ViewBuilder
    private var statsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Final Stats")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GlavenTheme.secondaryText)

            HStack(spacing: 20) {
                VStack {
                    Text("\(character.level)")
                        .font(.title3.weight(.bold))
                    Text("Level")
                        .font(.caption2)
                }
                VStack {
                    Text("\(character.experience)")
                        .font(.title3.weight(.bold))
                    Text("XP")
                        .font(.caption2)
                }
                VStack {
                    Text("\(character.loot)")
                        .font(.title3.weight(.bold))
                    Text("Gold")
                        .font(.caption2)
                }
                VStack {
                    Text("\(character.items.count)")
                        .font(.title3.weight(.bold))
                    Text("Items")
                        .font(.caption2)
                }
            }
            .foregroundStyle(GlavenTheme.primaryText)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Confirm

    @ViewBuilder
    private var confirmSection: some View {
        VStack(spacing: 12) {
            Toggle("I confirm the retirement of this character", isOn: $confirmed)
                .font(.subheadline)
                .foregroundStyle(GlavenTheme.primaryText)

            Button {
                performRetirement()
            } label: {
                Label("Retire Character", systemImage: "flag.checkered")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(confirmed ? Color.purple.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                    .foregroundStyle(confirmed ? .purple : GlavenTheme.secondaryText)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!confirmed)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func performRetirement() {
        gameManager.characterManager.retireCharacter(character)
        dismiss()
    }
}
