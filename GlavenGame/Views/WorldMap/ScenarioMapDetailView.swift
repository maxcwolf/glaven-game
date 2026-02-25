import SwiftUI

struct ScenarioMapDetailView: View {
    let scenario: ScenarioData
    let isCompleted: Bool
    let isAvailable: Bool
    let isBlocked: Bool
    let isLocked: Bool
    let canStartScenario: Bool
    var onStart: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Scenario header
                VStack(spacing: 4) {
                    Text("#\(scenario.index)")
                        .font(.caption)
                        .foregroundStyle(GlavenTheme.secondaryText)
                    Text(scenario.name)
                        .font(.title2.bold())
                        .foregroundStyle(GlavenTheme.primaryText)
                        .multilineTextAlignment(.center)
                    if let grid = scenario.coordinates?.gridLocation {
                        Text(grid)
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.secondaryText)
                    }
                }

                // Status badge
                statusBadge

                // Unlocks info
                if let unlocks = scenario.unlocks, !unlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unlocks")
                            .font(.caption.bold())
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text(unlocks.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.primaryText.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                // Links info
                if let links = scenario.links, !links.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Links")
                            .font(.caption.bold())
                            .foregroundStyle(GlavenTheme.secondaryText)
                        Text(links.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(GlavenTheme.primaryText.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                Spacer()

                // Start Scenario button
                if isAvailable && canStartScenario && !isCompleted {
                    Button {
                        onStart?()
                        dismiss()
                    } label: {
                        Text("Start Scenario")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(GlavenTheme.positive)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(GlavenTheme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(GlavenTheme.headerFooterBackground, for: .navigationBar)
            #endif
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(statusText)
                .font(.subheadline.bold())
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusText: String {
        if isCompleted { return "Completed" }
        if isBlocked { return "Blocked" }
        if isLocked { return "Locked" }
        if isAvailable { return "Available" }
        return "Unknown"
    }

    private var statusIcon: String {
        if isCompleted { return "checkmark.seal.fill" }
        if isBlocked { return "xmark.octagon.fill" }
        if isLocked { return "lock.fill" }
        if isAvailable { return "play.circle.fill" }
        return "questionmark.circle"
    }

    private var statusColor: Color {
        if isCompleted { return GlavenTheme.isLight ? Color(red: 0.72, green: 0.58, blue: 0.10) : .yellow }
        if isBlocked { return GlavenTheme.isLight ? Color(red: 0.75, green: 0.22, blue: 0.17) : .red }
        if isLocked { return .gray }
        if isAvailable { return GlavenTheme.positive }
        return GlavenTheme.secondaryText
    }
}
