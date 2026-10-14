import SwiftUI

/// Settings, in the board's look: sections as panels, choices as named stops in brass.
struct PreferencesSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    private var settingsManager: SettingsManager {
        gameManager.settingsManager
    }

    /// A named setting on a scale: the value it stores, and what it's called.
    struct Stop: Equatable {
        let value: Double
        let name: String
    }

    static let speedStops = [Stop(value: 0.5, name: "Fast"), Stop(value: 0.75, name: "Quick"), Stop(value: 1, name: "Normal"),
                             Stop(value: 1.5, name: "Slow"), Stop(value: 2, name: "Very Slow")]
    static let sizeStops = [Stop(value: 0.85, name: "Compact"), Stop(value: 1, name: "Default"), Stop(value: 1.15, name: "Large"),
                            Stop(value: 1.3, name: "Extra Large"), Stop(value: 1.5, name: "Maximum")]

    static let cardStyleStops = CardStyle.allCases.enumerated().map { Stop(value: Double($0.offset), name: $0.element.label) }

    /// The stop nearest a stored value (older saves may hold values between stops).
    static func nearest(_ value: Double, in stops: [Stop]) -> Stop {
        stops.min { abs($0.value - value) < abs($1.value - value) } ?? stops[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(BoardTheme.display(30))
                    .foregroundStyle(BoardTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") {
                    settingsManager.saveSettings()
                    dismiss()
                }
                .buttonStyle(.boardPrimary)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(BoardTheme.border.opacity(0.4)).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Pacing") {
                        stopsRow(title: "Animation speed",
                                 detail: "How quickly pieces move and monsters take their turns.",
                                 stops: Self.speedStops,
                                 value: Binding(get: { settingsManager.animationSpeed },
                                                set: { settingsManager.animationSpeed = $0 }))
                        divider
                        toggleRow(title: "Draw modifier cards for monsters",
                                  detail: "Tap the deck for every attack, not only your own.",
                                  isOn: Binding(get: { settingsManager.drawAllModifiers },
                                                set: { settingsManager.drawAllModifiers = $0 }))
                    }

                    section("Sound") {
                        toggleRow(title: "Sound effects", detail: "Card flips, coins and the title sting.",
                                  isOn: Binding(get: { settingsManager.soundEffects },
                                                set: { settingsManager.soundEffects = $0 }))
                        #if os(iOS)
                        divider
                        toggleRow(title: "Haptic feedback", detail: "Vibration on taps, hits and card flips.",
                                  isOn: Binding(get: { settingsManager.hapticFeedback },
                                                set: { settingsManager.hapticFeedback = $0 }))
                        #endif
                    }

                    section("Look") {
                        toggleRow(title: "Automatic theme", detail: "Match the theme to the edition being played.",
                                  isOn: Binding(get: { settingsManager.automaticTheme },
                                                set: { settingsManager.automaticTheme = $0 }))
                        if !settingsManager.automaticTheme {
                            segmented(GlavenTheme.allThemes.map { Stop(value: 0, name: GlavenTheme.themeName($0)) },
                                      selected: GlavenTheme.themeName(settingsManager.theme)) { name in
                                if let theme = GlavenTheme.allThemes.first(where: { GlavenTheme.themeName($0) == name }) {
                                    settingsManager.theme = theme
                                }
                            }
                        }
                        divider
                        toggleRow(title: "Light mode", detail: "A warm parchment look for menus and town.",
                                  isOn: Binding(get: { settingsManager.lightMode },
                                                set: { settingsManager.lightMode = $0 }))
                        divider
                        stopsRow(title: "Text size", detail: "Larger text everywhere, for reading at a distance.",
                                 stops: Self.sizeStops,
                                 value: Binding(get: { Double(settingsManager.uiScale) },
                                                set: { settingsManager.uiScale = CGFloat($0) }))
                        Text("The Brute attacks for 3")
                            .font(BoardTheme.font(size: 16 * settingsManager.uiScale))
                            .foregroundStyle(BoardTheme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.small))
                            .accessibilityLabel("Preview of the text size")
                    }

                    section("Cards") {
                        stopsRow(title: "Card style",
                                 detail: "Your ability cards as the printed cards, or drawn by the app: plainer and easier to read at a glance.",
                                 stops: Self.cardStyleStops,
                                 value: Binding(get: { Self.cardStyleStops[CardStyle.allCases.firstIndex(of: settingsManager.cardStyle) ?? 0].value },
                                                set: { settingsManager.cardStyle = CardStyle.allCases[Int($0)] }))
                        divider
                        cardSizeRow
                    }
                }
                .padding(22)
            }
        }
        .background(BoardTheme.sheet.ignoresSafeArea())
        .frame(minWidth: 520, minHeight: 600)
        .onDisappear {
            settingsManager.saveSettings()
        }
    }

    // MARK: - Cards

    /// "150%".
    static func percent(_ scale: CGFloat) -> String { "\(Int((scale * 100).rounded()))%" }

    /// The card size: a slider, and a card of the party's (or the Brute's) as it is in the hand.
    private var cardSizeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                label("Card size", "How large your ability cards are in your hand, as you play them, and when you choose one to lose.")
                Spacer(minLength: 12)
                Text(Self.percent(settingsManager.cardScale))
                    .font(BoardTheme.font(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(BoardTheme.brass)
            }
            HStack(spacing: 12) {
                Slider(value: Binding(get: { Double(settingsManager.cardScale) },
                                      set: { settingsManager.cardScale = CGFloat($0) }),
                       in: Double(SettingsManager.cardScaleRange.lowerBound)...Double(SettingsManager.cardScaleRange.upperBound),
                       step: 0.05) {
                    Text("Card size")
                } minimumValueLabel: {
                    Image(systemName: "rectangle.portrait").font(.caption)
                } maximumValueLabel: {
                    Image(systemName: "rectangle.portrait").font(.title2)
                }
                .tint(BoardTheme.brass)
                .accessibilityValue(Self.percent(settingsManager.cardScale))
                Button("Reset") { settingsManager.cardScale = 1 }
                    .buttonStyle(.boardQuietCompact)
                    .disabled(settingsManager.cardScale == 1)
            }
            if let sample = sampleCard {
                AbilityCardFace(card: sample.card, edition: sample.edition, color: sample.color,
                                height: CardSelectionPanel.cardHeight,
                                labelResolver: { gameManager.editionStore.resolveCustomText($0, edition: sample.edition) })
                    .environment(\.cardStyle, settingsManager.cardStyle)
                    .environment(\.cardScale, settingsManager.cardScale)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity)
                    .animation(.snappy, value: settingsManager.cardScale)
                    .accessibilityLabel("Preview of the card size")
            }
        }
    }

    /// A card to show the style and size on: the first party member's first card, else the Brute's.
    private var sampleCard: (card: AbilityModel, edition: String, color: Color)? {
        let store = gameManager.editionStore
        if let character = gameManager.game.characters.first,
           let card = store.deckData(name: character.characterData?.deck ?? character.name, edition: character.edition)?.abilities.first {
            return (card, character.edition, Color(hex: character.color) ?? BoardTheme.brass)
        }
        guard let card = store.deckData(name: "brute", edition: "gh")?.abilities.first else { return nil }
        return (card, "gh", BoardTheme.brass)
    }

    // MARK: - Pieces

    private var divider: some View {
        Rectangle().fill(BoardTheme.border.opacity(0.3)).frame(height: 1)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(BoardTheme.font(size: 12, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(BoardTheme.brass)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BoardTheme.panel, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
                .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.border.opacity(0.45), lineWidth: 1))
        }
    }

    private func label(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BoardTheme.font(size: 16, weight: .semibold))
                .foregroundStyle(BoardTheme.text)
            Text(detail)
                .font(BoardTheme.font(size: 13))
                .foregroundStyle(BoardTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { label(title, detail) }
            .toggleStyle(.switch)
            .tint(BoardTheme.brass)
    }

    private func stopsRow(title: String, detail: String, stops: [Stop], value: Binding<Double>) -> some View {
        let current = Self.nearest(value.wrappedValue, in: stops)
        return VStack(alignment: .leading, spacing: 10) {
            label(title, detail)
            segmented(stops, selected: current.name) { name in
                if let stop = stops.first(where: { $0.name == name }) { value.wrappedValue = stop.value }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityValue(current.name)
        }
    }

    /// Named choices in a capsule, the chosen one in brass.
    private func segmented(_ stops: [Stop], selected: String, choose: @escaping (String) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(stops, id: \.name) { stop in
                let isSelected = stop.name == selected
                Button { choose(stop.name) } label: {
                    Text(stop.name)
                        .font(BoardTheme.font(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? BoardTheme.sheet : BoardTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(isSelected ? BoardTheme.brass : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stop.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(BoardTheme.raised, in: Capsule())
    }
}
