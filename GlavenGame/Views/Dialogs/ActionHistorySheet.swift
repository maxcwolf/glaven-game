import SwiftUI

struct ActionHistorySheet: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusCards
                if gameManager.undoCount > 0 || gameManager.redoCount > 0 {
                    interactiveTimeline
                }
                gameStateSummary
                Spacer()
                actionButtons
            }
            .padding()
            .background(GlavenTheme.background)
            .navigationTitle("Action History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(minWidth: 350, minHeight: 400)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Status Cards

    @ViewBuilder
    private var statusCards: some View {
        HStack(spacing: 24) {
            VStack {
                Text("\(gameManager.undoCount)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(GlavenTheme.accentText)
                Text("Undo Steps")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)

            VStack {
                Text("\(gameManager.redoCount)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                Text("Redo Steps")
                    .font(.caption)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Interactive Timeline

    @ViewBuilder
    private var interactiveTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(GlavenTheme.secondaryText)
                Spacer()
                Text("Step \(gameManager.historyIndex) of \(gameManager.historyCount - 1)")
                    .font(.caption2)
                    .foregroundStyle(GlavenTheme.secondaryText)
            }

            GeometryReader { geo in
                let total = gameManager.historyCount
                let stepWidth = geo.size.width / CGFloat(max(total - 1, 1))
                let currentPos = CGFloat(gameManager.historyIndex)

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(GlavenTheme.primaryText.opacity(0.1))
                        .frame(height: 6)

                    // Undo portion
                    if gameManager.undoCount > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(GlavenTheme.accentText.opacity(0.5))
                            .frame(width: stepWidth * currentPos, height: 6)
                    }

                    // Step dots
                    if total <= 30 {
                        ForEach(0..<total, id: \.self) { i in
                            Circle()
                                .fill(i == gameManager.historyIndex
                                      ? GlavenTheme.accentText
                                      : i < gameManager.historyIndex
                                      ? GlavenTheme.accentText.opacity(0.4)
                                      : Color.orange.opacity(0.4))
                                .frame(width: i == gameManager.historyIndex ? 14 : 8,
                                       height: i == gameManager.historyIndex ? 14 : 8)
                                .position(x: stepWidth * CGFloat(i), y: 7)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        gameManager.jumpToHistory(index: i)
                                    }
                                }
                        }
                    } else {
                        // Too many steps for dots — just show current marker
                        Circle()
                            .fill(GlavenTheme.accentText)
                            .frame(width: 14, height: 14)
                            .position(x: stepWidth * currentPos, y: 7)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if total > 30 {
                        let fraction = location.x / geo.size.width
                        let targetIndex = Int(round(fraction * CGFloat(total - 1)))
                        let clamped = max(0, min(total - 1, targetIndex))
                        withAnimation(.easeInOut(duration: 0.2)) {
                            gameManager.jumpToHistory(index: clamped)
                        }
                    }
                }
            }
            .frame(height: 20)

            // Step buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        gameManager.jumpToHistory(index: 0)
                    }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(gameManager.historyIndex == 0)
                .foregroundStyle(gameManager.historyIndex == 0 ? GlavenTheme.secondaryText.opacity(0.3) : GlavenTheme.accentText)

                Button {
                    gameManager.undo()
                } label: {
                    Image(systemName: "backward.frame.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!gameManager.canUndo)
                .foregroundStyle(!gameManager.canUndo ? GlavenTheme.secondaryText.opacity(0.3) : GlavenTheme.accentText)

                Spacer()

                Text("Step \(gameManager.historyIndex)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(GlavenTheme.accentText)

                Spacer()

                Button {
                    gameManager.redo()
                } label: {
                    Image(systemName: "forward.frame.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(!gameManager.canRedo)
                .foregroundStyle(!gameManager.canRedo ? GlavenTheme.secondaryText.opacity(0.3) : .orange)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        gameManager.jumpToHistory(index: gameManager.historyCount - 1)
                    }
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(gameManager.historyIndex == gameManager.historyCount - 1)
                .foregroundStyle(gameManager.historyIndex == gameManager.historyCount - 1 ? GlavenTheme.secondaryText.opacity(0.3) : .orange)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Game State Summary

    @ViewBuilder
    private var gameStateSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current State")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(GlavenTheme.secondaryText)

            HStack(spacing: 16) {
                statBadge("Round", value: "\(gameManager.game.round)", icon: "clock", color: GlavenTheme.accentText)
                statBadge("Phase", value: gameManager.game.state == .draw ? "Draw" : "Play", icon: "play", color: .green)
                statBadge("Chars", value: "\(gameManager.game.characters.count)", icon: "person.fill", color: .blue)
            }
        }
        .padding()
        .background(GlavenTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                gameManager.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(gameManager.canUndo ? GlavenTheme.accentText.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                    .foregroundStyle(gameManager.canUndo ? GlavenTheme.accentText : GlavenTheme.secondaryText)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!gameManager.canUndo)

            Button {
                gameManager.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(gameManager.canRedo ? Color.orange.opacity(0.2) : GlavenTheme.primaryText.opacity(0.05))
                    .foregroundStyle(gameManager.canRedo ? .orange : GlavenTheme.secondaryText)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!gameManager.canRedo)
        }
        .padding(.bottom)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statBadge(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(GlavenTheme.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
