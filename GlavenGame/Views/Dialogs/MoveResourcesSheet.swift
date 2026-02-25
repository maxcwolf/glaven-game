import SwiftUI

struct MoveResourcesSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var sourceIndex = 0
    @State private var targetIndex = 1
    @State private var goldAmount = 0
    @State private var xpAmount = 0

    private var characters: [GameCharacter] {
        gameManager.game.characters
    }

    private var source: GameCharacter? {
        guard sourceIndex < characters.count else { return nil }
        return characters[sourceIndex]
    }

    private var target: GameCharacter? {
        guard targetIndex < characters.count else { return nil }
        return characters[targetIndex]
    }

    var body: some View {
        NavigationStack {
            Form {
                // Source character
                Section("From") {
                    Picker("Source", selection: $sourceIndex) {
                        ForEach(Array(characters.enumerated()), id: \.offset) { index, char in
                            Text(characterDisplayName(char))
                                .tag(index)
                        }
                    }
                    if let src = source {
                        HStack {
                            Text("Gold: \(src.loot)")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("XP: \(src.experience)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Target character
                Section("To") {
                    Picker("Target", selection: $targetIndex) {
                        ForEach(Array(characters.enumerated()), id: \.offset) { index, char in
                            Text(characterDisplayName(char))
                                .tag(index)
                        }
                    }
                    if let tgt = target {
                        HStack {
                            Text("Gold: \(tgt.loot)")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("XP: \(tgt.experience)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Amounts
                Section("Transfer") {
                    Stepper("Gold: \(goldAmount)", value: $goldAmount, in: 0...(source?.loot ?? 0))
                    Stepper("XP: \(xpAmount)", value: $xpAmount, in: 0...(source?.experience ?? 0))
                }

                // Transfer button
                Section {
                    Button {
                        transfer()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Transfer", systemImage: "arrow.right.circle.fill")
                                .fontWeight(.bold)
                            Spacer()
                        }
                    }
                    .disabled(sourceIndex == targetIndex || (goldAmount == 0 && xpAmount == 0))
                }
            }
            .navigationTitle("Move Resources")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func characterDisplayName(_ char: GameCharacter) -> String {
        let name = char.title.isEmpty
            ? char.name.replacingOccurrences(of: "-", with: " ").capitalized
            : char.title
        return "\(name) (\(char.loot)g)"
    }

    private func transfer() {
        guard let src = source, let tgt = target, sourceIndex != targetIndex else { return }
        gameManager.pushUndoState()
        if goldAmount > 0 {
            src.loot -= goldAmount
            tgt.loot += goldAmount
        }
        if xpAmount > 0 {
            src.experience -= xpAmount
            tgt.experience += xpAmount
        }
        goldAmount = 0
        xpAmount = 0
    }
}
