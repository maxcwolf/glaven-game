import SwiftUI

/// Standalone Initiative Tracker with large numeric keypad input.
struct InitiativeToolSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCharacterID: String?
    @State private var inputDigits: [Int] = []
    @State private var submittedInitiatives: [String: Int] = [:]

    private var characters: [GameCharacter] {
        gameManager.game.characters.filter { !$0.exhausted && !$0.absent }
    }

    private var selectedCharacter: GameCharacter? {
        characters.first(where: { $0.id == selectedCharacterID })
    }

    private var displayValue: String {
        if inputDigits.isEmpty { return "__" }
        if inputDigits.count == 1 { return "\(inputDigits[0])_" }
        return "\(inputDigits[0])\(inputDigits[1])"
    }

    private var numericValue: Int? {
        guard inputDigits.count == 2 else { return nil }
        return inputDigits[0] * 10 + inputDigits[1]
    }

    private var allSubmitted: Bool {
        characters.allSatisfy { submittedInitiatives[$0.id] != nil || $0.longRest }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Character selection
                characterGrid

                Divider()

                // Initiative display
                initiativeDisplay

                // Keypad
                keypad

                // Action buttons
                actionButtons
            }
            .background(GlavenTheme.background)
            .navigationTitle("Initiative Tracker")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset All") {
                        resetAll()
                    }
                }
            }
            .onAppear {
                // Select first character
                selectedCharacterID = characters.first?.id
                // Load existing initiatives
                for char in characters {
                    if char.initiative > 0 {
                        submittedInitiatives[char.id] = char.initiative
                    }
                }
            }
        }
    }

    // MARK: - Character Grid

    @ViewBuilder
    private var characterGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(characters, id: \.id) { character in
                    let isSelected = character.id == selectedCharacterID
                    let hasInit = submittedInitiatives[character.id] != nil
                    let charColor = Color(hex: character.color) ?? .blue

                    Button {
                        selectedCharacterID = character.id
                        inputDigits = []
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? charColor.opacity(0.3) : Color.clear)
                                    .frame(width: 44, height: 44)

                                Image(systemName: "person.fill")
                                    .font(.title3)
                                    .foregroundStyle(charColor)

                                if hasInit {
                                    Text("\(submittedInitiatives[character.id] ?? 0)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(charColor)
                                        .clipShape(Capsule())
                                        .offset(x: 14, y: -14)
                                }

                                if character.longRest {
                                    Image(systemName: "moon.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                        .offset(x: 14, y: 14)
                                }
                            }

                            Text(character.title.isEmpty
                                ? character.name.replacingOccurrences(of: "-", with: " ").capitalized
                                : character.title)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? GlavenTheme.primaryText : GlavenTheme.secondaryText)
                        }
                        .frame(width: 60)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(GlavenTheme.cardBackground)
    }

    // MARK: - Initiative Display

    @ViewBuilder
    private var initiativeDisplay: some View {
        VStack(spacing: 8) {
            if let char = selectedCharacter {
                Text(char.title.isEmpty
                    ? char.name.replacingOccurrences(of: "-", with: " ").capitalized
                    : char.title)
                    .font(.subheadline)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            Text(displayValue)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .foregroundStyle(GlavenTheme.primaryText)
                .frame(height: 80)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Keypad

    @ViewBuilder
    private var keypad: some View {
        VStack(spacing: 8) {
            // Row 1: 1 2 3
            HStack(spacing: 8) {
                keypadButton(1)
                keypadButton(2)
                keypadButton(3)
            }
            // Row 2: 4 5 6
            HStack(spacing: 8) {
                keypadButton(4)
                keypadButton(5)
                keypadButton(6)
            }
            // Row 3: 7 8 9
            HStack(spacing: 8) {
                keypadButton(7)
                keypadButton(8)
                keypadButton(9)
            }
            // Row 4: Clear 0 Submit
            HStack(spacing: 8) {
                Button {
                    inputDigits = []
                } label: {
                    Text("C")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                keypadButton(0)

                Button {
                    submitInitiative()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(numericValue == nil)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func keypadButton(_ digit: Int) -> some View {
        Button {
            addDigit(digit)
        } label: {
            Text("\(digit)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(GlavenTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(GlavenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(inputDigits.count >= 2)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                setLongRest()
            } label: {
                Label("Long Rest", systemImage: "moon.fill")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.yellow.opacity(0.15))
                    .foregroundStyle(.yellow)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            if allSubmitted {
                Text("All set!")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GlavenTheme.cardBackground)
    }

    // MARK: - Logic

    private func addDigit(_ digit: Int) {
        guard inputDigits.count < 2 else { return }
        inputDigits.append(digit)

        // Auto-submit on second digit
        if inputDigits.count == 2, let value = numericValue {
            submitValue(value)
        }
    }

    private func submitInitiative() {
        guard let value = numericValue else { return }
        submitValue(value)
    }

    private func submitValue(_ value: Int) {
        guard let charID = selectedCharacterID,
              let character = characters.first(where: { $0.id == charID }) else { return }

        gameManager.characterManager.onBeforeMutate?()
        character.initiative = value
        character.longRest = false
        submittedInitiatives[charID] = value

        // Advance to next character without initiative
        advanceToNext()
    }

    private func setLongRest() {
        guard let charID = selectedCharacterID,
              let character = characters.first(where: { $0.id == charID }) else { return }

        gameManager.characterManager.onBeforeMutate?()
        character.initiative = 99
        character.longRest = true
        submittedInitiatives[charID] = 99

        advanceToNext()
    }

    private func advanceToNext() {
        inputDigits = []
        // Find next character without initiative
        if let next = characters.first(where: {
            submittedInitiatives[$0.id] == nil && !$0.longRest
        }) {
            selectedCharacterID = next.id
        }
    }

    private func resetAll() {
        gameManager.characterManager.onBeforeMutate?()
        for character in characters {
            character.initiative = 0
            character.longRest = false
        }
        submittedInitiatives = [:]
        inputDigits = []
        selectedCharacterID = characters.first?.id
    }
}
