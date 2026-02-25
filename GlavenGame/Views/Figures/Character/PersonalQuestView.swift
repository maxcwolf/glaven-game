import SwiftUI

struct PersonalQuestView: View {
    @Bindable var character: GameCharacter
    @Environment(GameManager.self) private var gameManager

    private var quest: PersonalQuestData? {
        guard let cardId = character.personalQuest else { return nil }
        return gameManager.editionStore.personalQuest(cardId: cardId)
    }

    private var availableQuests: [PersonalQuestData] {
        gameManager.editionStore.personalQuests(for: character.edition)
    }

    private var isQuestComplete: Bool {
        guard let quest = quest else { return false }
        for (i, req) in quest.requirements.enumerated() {
            let target = req.counter?.intValue ?? 1
            let progress = i < character.personalQuestProgress.count ? character.personalQuestProgress[i] : 0
            if progress < target { return false }
        }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let quest = quest {
                    assignedQuestView(quest)
                } else {
                    unassignedView
                }
            }
            .padding()
        }
    }

    // MARK: - Assigned Quest

    @ViewBuilder
    private func assignedQuestView(_ quest: PersonalQuestData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "scroll.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Quest #\(quest.cardId)")
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    if let altId = quest.altId {
                        Text("Alt: \(altId)")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }
                Spacer()
                if isQuestComplete {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(GlavenTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Requirements
            ForEach(Array(quest.requirements.enumerated()), id: \.offset) { index, req in
                requirementRow(index: index, requirement: req)
            }

            // Rewards section
            rewardsSection(quest)

            // Unassign button
            Button(role: .destructive) {
                character.personalQuest = nil
                character.personalQuestProgress = []
            } label: {
                Label("Remove Quest", systemImage: "xmark.circle")
                    .font(.subheadline)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func requirementRow(index: Int, requirement: PersonalQuestRequirement) -> some View {
        let target = requirement.counter?.intValue ?? 1
        let progress = index < character.personalQuestProgress.count ? character.personalQuestProgress[index] : 0
        let isComplete = progress >= target
        let hasPrereqs = requirement.requires != nil && !(requirement.requires!.isEmpty)
        let prereqsMet = !hasPrereqs || requirement.requires!.allSatisfy { prereqIdx in
            let prereqTarget = prereqIdx < quest!.requirements.count ? (quest!.requirements[prereqIdx].counter?.intValue ?? 1) : 1
            let prereqProgress = prereqIdx < character.personalQuestProgress.count ? character.personalQuestProgress[prereqIdx] : 0
            return prereqProgress >= prereqTarget
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isComplete ? .green : GlavenTheme.secondaryText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(cleanRequirementName(requirement.name))
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    if let autotrack = requirement.autotrack {
                        Text("Track: \(autotrack)")
                            .font(.caption2)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Spacer()

                Text("\(progress)/\(target)")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(isComplete ? .green : GlavenTheme.accentText)
            }

            // Progress controls
            if prereqsMet && !isComplete {
                HStack(spacing: 12) {
                    Button {
                        updateProgress(at: index, delta: -1, target: target)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(progress > 0 ? GlavenTheme.accentText : GlavenTheme.secondaryText.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(progress <= 0)

                    ProgressView(value: Double(progress), total: Double(target))
                        .tint(GlavenTheme.accentText)

                    Button {
                        updateProgress(at: index, delta: 1, target: target)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(GlavenTheme.accentText)
                    }
                    .buttonStyle(.plain)
                }
            } else if !prereqsMet {
                Text("Requires completing previous objectives")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if hasPrereqs {
                let reqIndices = requirement.requires!.map { "#\($0 + 1)" }.joined(separator: ", ")
                Text("Requires: \(reqIndices)")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .padding()
        .background(isComplete ? Color.green.opacity(0.08) : GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func rewardsSection(_ quest: PersonalQuestData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rewards")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GlavenTheme.secondaryText)

            if let unlock = quest.unlockCharacter {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(.purple)
                    Text("Unlocks: \(unlock.replacingOccurrences(of: "-", with: " ").capitalized)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }

            if let envelope = quest.openEnvelope {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(.orange)
                    Text("Open Envelope: \(envelope)")
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }
        }
        .padding()
        .background(GlavenTheme.primaryText.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Unassigned

    @ViewBuilder
    private var unassignedView: some View {
        if availableQuests.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "scroll")
                    .font(.system(size: 48))
                    .foregroundStyle(GlavenTheme.secondaryText)
                Text("No personal quests available for this edition")
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Assign Personal Quest")
                    .font(.headline)
                    .foregroundStyle(GlavenTheme.primaryText)

                Text("Select a quest card to assign to this character.")
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)

                ForEach(availableQuests) { quest in
                    Button {
                        character.personalQuest = quest.cardId
                        character.personalQuestProgress = Array(repeating: 0, count: quest.requirements.count)
                    } label: {
                        HStack {
                            Image(systemName: "scroll.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quest #\(quest.cardId)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(GlavenTheme.primaryText)
                                Text("\(quest.requirements.count) objective\(quest.requirements.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            Spacer()
                            if let unlock = quest.unlockCharacter {
                                Text(unlock.replacingOccurrences(of: "-", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }
                        .padding()
                        .background(GlavenTheme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateProgress(at index: Int, delta: Int, target: Int) {
        while character.personalQuestProgress.count <= index {
            character.personalQuestProgress.append(0)
        }
        character.personalQuestProgress[index] = max(0, min(target, character.personalQuestProgress[index] + delta))
    }

    private func cleanRequirementName(_ name: String) -> String {
        // Strip i18n markers like %data.personalQuest.gh.510.1%
        if name.hasPrefix("%") && name.hasSuffix("%") {
            let stripped = name.dropFirst().dropLast()
            let parts = stripped.split(separator: ".")
            if parts.count >= 2 {
                return "Objective \(parts.last ?? "?")"
            }
        }
        return name
    }
}
