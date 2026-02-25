import SwiftUI

struct InitiativeInputView: View {
    let initiative: Int
    let onSet: (Int) -> Void

    @State private var text: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Initiative")
                .font(.headline)

            // Display current input
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(text.isEmpty ? GlavenTheme.secondaryText : GlavenTheme.primaryText)
                .frame(width: 120, height: 60)
                .background(GlavenTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(GlavenTheme.primaryText.opacity(0.2), lineWidth: 1)
                )

            // Number pad grid
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    numButton("1")
                    numButton("2")
                    numButton("3")
                }
                GridRow {
                    numButton("4")
                    numButton("5")
                    numButton("6")
                }
                GridRow {
                    numButton("7")
                    numButton("8")
                    numButton("9")
                }
                GridRow {
                    // Clear
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "delete.backward")
                            .font(.title3)
                            .frame(width: 56, height: 44)
                            .background(GlavenTheme.primaryText.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    numButton("0")

                    // Confirm
                    Button {
                        confirm()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 44)
                            .background(isValid ? GlavenTheme.accentText : GlavenTheme.primaryText.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }
            }

            // Long rest shortcut
            Button("Long Rest (99)") {
                onSet(99)
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 240, minHeight: 320)
        .onAppear {
            text = initiative > 0 ? "\(initiative)" : ""
        }
    }

    private var isValid: Bool {
        guard let value = Int(text) else { return false }
        return value > 0 && value <= 99
    }

    private func numButton(_ digit: String) -> some View {
        Button {
            if text.count < 2 {
                text += digit
            }
        } label: {
            Text(digit)
                .font(.title2.weight(.medium))
                .frame(width: 56, height: 44)
                .background(GlavenTheme.primaryText.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(text.count >= 2)
    }

    private func confirm() {
        let value = Int(text) ?? 0
        if value > 0 && value <= 99 {
            onSet(value)
        }
        dismiss()
    }
}
