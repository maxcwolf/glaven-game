import SwiftUI

struct AddObjectiveSheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var health = 5
    @State private var isEscort = false
    @State private var initiative = 99

    var body: some View {
        NavigationStack {
            Form {
                Section("Objective Details") {
                    TextField("Name", text: $name)
                    Toggle("Escort", isOn: $isEscort)
                }

                Section("Stats") {
                    Stepper("Health: \(health)", value: $health, in: 1...99)
                    Stepper("Initiative: \(initiative)", value: $initiative, in: 1...99)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlavenTheme.background)
            .navigationTitle("Add Objective")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 320, minHeight: 280)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let objName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        gameManager.objectiveManager.addObjective(
                            name: objName.isEmpty ? "Objective" : objName,
                            health: health,
                            escort: isEscort,
                            initiative: initiative
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
