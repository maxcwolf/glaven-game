import SwiftUI

struct PreferencesSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var settingsManager: SettingsManager {
        gameManager.settingsManager
    }

    private var animationSpeedLabel: String {
        switch settingsManager.animationSpeed {
        case ..<0.6: return "Fast"
        case ..<0.8: return "Quick"
        case ..<1.1: return "Normal"
        case ..<1.6: return "Slow"
        default: return "Very Slow"
        }
    }

    private var scaleLabel: String {
        switch settingsManager.uiScale {
        case ..<0.9: return "Compact"
        case ..<1.05: return "Default"
        case ..<1.25: return "Large"
        case ..<1.45: return "Extra Large"
        default: return "Maximum"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gameplay") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.applyConditions },
                            set: { settingsManager.applyConditions = $0 }
                        ),
                        title: "Auto-apply Conditions",
                        description: "Automatically apply wound/regen at turn start"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.initiativeRequired },
                            set: { settingsManager.initiativeRequired = $0 }
                        ),
                        title: "Require Initiative",
                        description: "Must set initiative before drawing"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.lootDeckEnabled },
                            set: { settingsManager.lootDeckEnabled = $0 }
                        ),
                        title: "Enable Loot Deck",
                        description: "Show loot deck in footer"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.sortFigures },
                            set: { settingsManager.sortFigures = $0 }
                        ),
                        title: "Sort by Initiative",
                        description: "Auto-sort figures during play phase"
                    )
                }

                if settingsManager.applyConditions {
                    Section("Condition Exclusions") {
                        Text("Disable auto-application per condition:")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)

                        let applyConditions: [ConditionName] = [.wound, .regenerate, .poison, .bane, .infect, .rupture]
                        ForEach(applyConditions, id: \.self) { condition in
                            let isExcluded = Binding<Bool>(
                                get: { settingsManager.excludedConditions.contains(condition) },
                                set: { excluded in
                                    if excluded {
                                        settingsManager.excludedConditions.insert(condition)
                                    } else {
                                        settingsManager.excludedConditions.remove(condition)
                                    }
                                }
                            )
                            Toggle(isOn: isExcluded) {
                                Text(condition.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            .tint(.red)
                        }
                    }
                }

                Section("Monsters") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.abilities },
                            set: { settingsManager.abilities = $0 }
                        ),
                        title: "Show Abilities",
                        description: "Display monster ability cards"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.automaticStandees },
                            set: { settingsManager.automaticStandees = $0 }
                        ),
                        title: "Auto-add Standees",
                        description: "Add standees when spawning monsters"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.randomStandees },
                            set: { settingsManager.randomStandees = $0 }
                        ),
                        title: "Randomize Standee Numbers",
                        description: "Random vs sequential standee assignment"
                    )
                }

                Section("Frosthaven") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.fhPets },
                            set: { settingsManager.fhPets = $0 }
                        ),
                        title: "Pets (Stables)",
                        description: "Enable pet card management"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.fhGarden },
                            set: { settingsManager.fhGarden = $0 }
                        ),
                        title: "Garden",
                        description: "Enable herb garden management"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.fhTrials },
                            set: { settingsManager.fhTrials = $0 }
                        ),
                        title: "Trials",
                        description: "Enable trial card system"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.fhFavors },
                            set: { settingsManager.fhFavors = $0 }
                        ),
                        title: "Favors",
                        description: "Enable favor token system"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.fhAlchemist },
                            set: { settingsManager.fhAlchemist = $0 }
                        ),
                        title: "Alchemist",
                        description: "Enable alchemist/imbue mechanics"
                    )
                }

                Section("Theme") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.automaticTheme },
                            set: { settingsManager.automaticTheme = $0 }
                        ),
                        title: "Automatic Theme",
                        description: "Match theme to active edition"
                    )

                    if !settingsManager.automaticTheme {
                        Picker("Theme", selection: Binding(
                            get: { settingsManager.theme },
                            set: { settingsManager.theme = $0 }
                        )) {
                            ForEach(GlavenTheme.allThemes, id: \.self) { theme in
                                Text(GlavenTheme.themeName(theme)).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Display") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.lightMode },
                            set: { settingsManager.lightMode = $0 }
                        ),
                        title: "Light Mode",
                        description: "Warm parchment appearance"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.compact },
                            set: { settingsManager.compact = $0 }
                        ),
                        title: "Compact Mode",
                        description: "Reduce spacing and card sizes"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.animations },
                            set: { settingsManager.animations = $0 }
                        ),
                        title: "Animations",
                        description: "Enable transitions and animations"
                    )
                    if settingsManager.animations {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Animation Speed")
                                Spacer()
                                Text(animationSpeedLabel)
                                    .foregroundStyle(GlavenTheme.secondaryText)
                            }
                            Slider(
                                value: Binding(
                                    get: { settingsManager.animationSpeed },
                                    set: { settingsManager.animationSpeed = $0 }
                                ),
                                in: 0.5...2.0,
                                step: 0.25
                            )
                            HStack {
                                Text("Fast").font(.caption2).foregroundStyle(GlavenTheme.secondaryText)
                                Spacer()
                                Text("Slow").font(.caption2).foregroundStyle(GlavenTheme.secondaryText)
                            }
                        }
                    }
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.soundEffects },
                            set: { settingsManager.soundEffects = $0 }
                        ),
                        title: "Sound Effects",
                        description: "Play sound effects for game actions"
                    )
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.hapticFeedback },
                            set: { settingsManager.hapticFeedback = $0 }
                        ),
                        title: "Haptic Feedback",
                        description: "Vibration feedback on interactions"
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("UI Scale")
                            Spacer()
                            Text(scaleLabel)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }

                        Slider(
                            value: Binding(
                                get: { settingsManager.uiScale },
                                set: { settingsManager.uiScale = $0 }
                            ),
                            in: 0.85...1.5,
                            step: 0.05
                        )

                        HStack {
                            Text("Compact")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                            Spacer()
                            Text("Maximum")
                                .font(.caption2)
                                .foregroundStyle(GlavenTheme.secondaryText)
                        }

                        // Live preview
                        HStack(spacing: 8) {
                            Image(systemName: "textformat.size")
                                .font(.system(size: 14 * settingsManager.uiScale))
                            Text("Preview Text")
                                .font(.system(size: 16 * settingsManager.uiScale))
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.3))
                                .frame(width: 32 * settingsManager.uiScale, height: 28 * settingsManager.uiScale)
                                .overlay(
                                    Text("1")
                                        .font(.system(size: 14 * settingsManager.uiScale, weight: .bold, design: .monospaced))
                                )
                        }
                        .padding(.vertical, 4)

                        if settingsManager.uiScale != 1.0 {
                            Button("Reset to Default") {
                                settingsManager.uiScale = 1.0
                            }
                            .font(.caption)
                        }
                    }
                }

                Section("Language") {
                    Picker("Language", selection: Binding(
                        get: { settingsManager.locale },
                        set: { settingsManager.locale = $0 }
                    )) {
                        ForEach(SupportedLocale.allCases) { locale in
                            Text(locale.displayName).tag(locale.code)
                        }
                    }
                }

                Section("Edition Data") {
                    editionDataSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlavenTheme.background)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        settingsManager.saveSettings()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 300)
        .onDisappear {
            settingsManager.saveSettings()
        }
    }

    // MARK: - Edition Data Management

    @ViewBuilder
    private var editionDataSection: some View {
        // Loaded editions
        ForEach(gameManager.editionStore.editions, id: \.edition) { edition in
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(edition.displayName)
                    .font(.subheadline)
                Spacer()
                Text("\(gameManager.editionStore.characters(for: edition.edition).count) chars")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }

    }


    private func settingsToggle(binding: Binding<Bool>, title: String, description: String) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
        }
        .tint(GlavenTheme.accentText)
    }
}
