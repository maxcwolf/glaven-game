import SwiftUI

/// A reusable number picker sheet with +/- buttons and optional range constraints.
/// Used for selecting damage amounts, healing, gold, quantity, etc.
struct NumberPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let icon: String?
    let iconColor: Color
    let min: Int
    let max: Int
    let initial: Int
    let onConfirm: (Int) -> Void

    @State private var value: Int

    init(title: String, subtitle: String? = nil, icon: String? = nil, iconColor: Color = GlavenTheme.accentText,
         min: Int = 0, max: Int = 99, initial: Int = 0, onConfirm: @escaping (Int) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.min = min
        self.max = max
        self.initial = initial
        self.onConfirm = onConfirm
        self._value = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundStyle(iconColor)
                }

                // Subtitle
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                // Number display with +/- buttons
                HStack(spacing: 24) {
                    // Decrement
                    Button {
                        if value > min { value -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(value > min ? GlavenTheme.accentText : GlavenTheme.secondaryText.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(value <= min)

                    // Value
                    Text("\(value)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(GlavenTheme.primaryText)
                        .frame(minWidth: 80)

                    // Increment
                    Button {
                        if value < max { value += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(value < max ? GlavenTheme.accentText : GlavenTheme.secondaryText.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(value >= max)
                }

                // Range label
                if min != 0 || max != 99 {
                    Text("\(min) – \(max)")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText.opacity(0.6))
                }

                Spacer()

                // Confirm button
                Button {
                    onConfirm(value)
                    dismiss()
                } label: {
                    Text("Confirm")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
            .padding()
            .background(GlavenTheme.background)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 280, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
