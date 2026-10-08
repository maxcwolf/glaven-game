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
                Section("Pacing") {
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
                        .accessibilityValue(animationSpeedLabel)
                        HStack {
                            Text("Fast").font(.caption).foregroundStyle(GlavenTheme.secondaryText)
                            Spacer()
                            Text("Slow").font(.caption).foregroundStyle(GlavenTheme.secondaryText)
                        }
                        Text("How quickly pieces move and monsters take their turns.")
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                Section("Sound") {
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.soundEffects },
                            set: { settingsManager.soundEffects = $0 }
                        ),
                        title: "Sound Effects",
                        description: "Card flips, coins and the title sting"
                    )
                    #if os(iOS)
                    settingsToggle(
                        binding: Binding(
                            get: { settingsManager.hapticFeedback },
                            set: { settingsManager.hapticFeedback = $0 }
                        ),
                        title: "Haptic Feedback",
                        description: "Vibration on taps, hits and card flips"
                    )
                    #endif
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Text Size")
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
        .frame(minWidth: 480, minHeight: 560)
        .onDisappear {
            settingsManager.saveSettings()
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
