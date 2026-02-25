import SwiftUI

struct HealthBarView: View {
    let current: Int
    let max: Int
    let color: Color
    var onHealthChange: ((Int) -> Void)?

    @State private var criticalPulse = false

    private var percentage: Double {
        guard max > 0 else { return 0 }
        return Double(current) / Double(max)
    }

    private var isCritical: Bool {
        max > 0 && percentage <= 0.35 && current > 0
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(GlavenTheme.primaryText.opacity(0.1))

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * percentage)
                        .animation(.easeInOut(duration: 0.25), value: percentage)
                }
                .shadow(color: isCritical ? Color.red.opacity(criticalPulse ? 0.7 : 0.2) : .clear, radius: 6)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let pct = value.location.x / geo.size.width
                            let newHealth = Int(round(pct * Double(max)))
                            onHealthChange?(Swift.max(0, Swift.min(max, newHealth)))
                        }
                )
            }
            .frame(height: 12)

            // HP text
            HStack(spacing: 3) {
                GameIcon(image: ImageLoader.statusIcon("health"), fallbackSystemName: "heart.fill", size: 10, color: isCritical ? .red : .red)
                Text("\(current)/\(max)")
                    .font(.caption2)
                    .fontWeight(isCritical ? .bold : .regular)
                    .foregroundStyle(isCritical ? Color.red : Color.secondary)
                Spacer()
            }
        }
        .onChange(of: isCritical) { _, critical in
            if critical {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    criticalPulse = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    criticalPulse = false
                }
            }
        }
        .onAppear {
            if isCritical {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    criticalPulse = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health \(current) of \(max)")
        .accessibilityValue("\(Int(percentage * 100)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onHealthChange?(Swift.min(max, current + 1))
            case .decrement: onHealthChange?(Swift.max(0, current - 1))
            @unknown default: break
            }
        }
    }

    private var barColor: Color {
        if percentage <= 0.25 { return .red }
        if percentage <= 0.5 { return .orange }
        return color
    }
}
