import SwiftUI

struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    shortcutSection("Game Flow", shortcuts: [
                        ("Space", "Next Round / Draw"),
                    ])

                    shortcutSection("File", shortcuts: [
                        ("\u{2318}S", "Save Game"),
                        ("\u{2318}\u{21E7}N", "New Game"),
                    ])

                    shortcutSection("Edit", shortcuts: [
                        ("\u{2318}Z", "Undo"),
                        ("\u{2318}\u{21E7}Z", "Redo"),
                    ])

                    shortcutSection("Navigation", shortcuts: [
                        ("\u{2318},", "Settings"),
                    ])

                    shortcutSection("Gestures", shortcuts: [
                        ("Pinch", "Zoom in/out (scales UI)"),
                        ("Long Press", "Context menu on figures"),
                        ("Drag", "Reorder characters"),
                        ("Swipe XP/Gold", "Adjust values by dragging"),
                    ])

                    Text("Keyboard shortcuts are built into the app and cannot be customized. Use the Settings panel to adjust other behavior.")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .padding(.horizontal)
                }
                .padding()
            }
            .background(GlavenTheme.background)
            .navigationTitle("Keyboard Shortcuts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 320, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GlavenTheme.primaryText)

            ForEach(shortcuts, id: \.0) { key, description in
                HStack {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.primaryText)
                    Spacer()
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(GlavenTheme.accentText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(GlavenTheme.primaryText.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
