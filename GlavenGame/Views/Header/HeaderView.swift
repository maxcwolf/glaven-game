import SwiftUI

struct HeaderView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @Environment(\.editionTheme) private var theme
    @Environment(\.isCompact) private var isCompact

    private var isDrawPhase: Bool {
        gameManager.game.state == .draw
    }

    var body: some View {
        if isCompact {
            compactHeader
        } else {
            wideHeader
        }
    }

    // MARK: - Wide Layout (iPad / Mac)

    @ViewBuilder
    private var wideHeader: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                LogoView(size: 36)
                if let edition = gameManager.game.edition {
                    Text(edition.uppercased())
                        .font(theme.titleFont(size: 20 * scale))
                        .foregroundStyle(GlavenTheme.primaryText)
                }
            }

            phaseBadge
            scenarioLabel

            HStack(spacing: 8) {
                undoButton
                redoButton
            }

            Spacer()
            ElementBoardView()
            Spacer()
            roundCounter
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(GlavenTheme.headerFooterBackground)
        .overlay(alignment: .bottom) { headerDivider }
    }

    // MARK: - Compact Layout (iPhone)

    @ViewBuilder
    private var compactHeader: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                LogoView(size: 28)
                phaseBadge
                if let scenario = gameManager.game.scenario {
                    Text("#\(scenario.data.index)")
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(GlavenTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 6) {
                    undoButton
                    redoButton
                }
                roundCounter
            }

            ElementBoardView()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(GlavenTheme.headerFooterBackground)
        .overlay(alignment: .bottom) { headerDivider }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var phaseBadge: some View {
        Text(isDrawPhase ? "DRAW" : "PLAY")
            .font(.system(size: 12 * scale, weight: .bold))
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 4 * scale)
            .background(isDrawPhase ? GlavenTheme.drawPhaseColor : GlavenTheme.nextPhaseColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .animateIf(gameManager.settingsManager.animations, .easeInOut(duration: 0.3), value: isDrawPhase)
            .accessibilityLabel(isDrawPhase ? "Draw phase" : "Play phase")
    }

    @ViewBuilder
    private var scenarioLabel: some View {
        if let scenario = gameManager.game.scenario {
            Text("#\(scenario.data.index) \(scenario.data.name)")
                .font(.system(size: 12 * scale))
                .foregroundStyle(GlavenTheme.secondaryText)
                .lineLimit(1)
        }
    }

    private var undoButton: some View {
        Button { gameManager.undo() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 14 * scale))
                .foregroundStyle(gameManager.canUndo ? GlavenTheme.primaryText : GlavenTheme.primaryText.opacity(0.2))
        }
        .buttonStyle(.plain)
        .disabled(!gameManager.canUndo)
        .accessibilityLabel("Undo")
        .accessibilityHint("Undo the last action")
    }

    private var redoButton: some View {
        Button { gameManager.redo() } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 14 * scale))
                .foregroundStyle(gameManager.canRedo ? GlavenTheme.primaryText : GlavenTheme.primaryText.opacity(0.2))
        }
        .buttonStyle(.plain)
        .disabled(!gameManager.canRedo)
        .accessibilityLabel("Redo")
        .accessibilityHint("Redo the last undone action")
    }

    @ViewBuilder
    private var roundCounter: some View {
        VStack(spacing: 2) {
            Text("Round")
                .font(.system(size: isCompact ? 10 : 12 * scale))
                .foregroundStyle(GlavenTheme.secondaryText)
            Text("\(gameManager.game.round)")
                .font(theme.titleFont(size: (isCompact ? 20 : 26) * scale))
                .foregroundStyle(GlavenTheme.primaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Round \(gameManager.game.round)")
    }

    @ViewBuilder
    private var headerDivider: some View {
        if GlavenTheme.isLight {
            Rectangle()
                .fill(GlavenTheme.primaryText.opacity(0.1))
                .frame(height: 1)
        }
    }
}
