import SwiftUI

struct RoundButtonView: View {
    @Environment(GameManager.self) private var gameManager
    @Environment(\.uiScale) private var scale
    @State private var showValidationWarning = false
    @State private var isPressed = false
    @State private var glowIntensity: Double = 0.3

    private var isDrawPhase: Bool {
        gameManager.game.state == .draw
    }

    private var canDraw: Bool {
        gameManager.roundManager.drawAvailable()
    }

    private var phaseColor: Color {
        isDrawPhase ? GlavenTheme.drawPhaseColor : GlavenTheme.nextPhaseColor
    }

    private var missingInitiativeNames: [String] {
        gameManager.game.characters
            .filter { !$0.exhausted && !$0.absent && !$0.longRest && $0.initiative <= 0 }
            .map { $0.title.isEmpty ? $0.name.replacingOccurrences(of: "-", with: " ").capitalized : $0.title }
    }

    var body: some View {
        Button {
            if isDrawPhase {
                if canDraw {
                    SoundPlayer.play(.phaseChange)
                    gameManager.roundManager.nextGameState()
                } else {
                    SoundPlayer.play(.error)
                    showValidationWarning = true
                }
            } else {
                SoundPlayer.play(.phaseChange)
                gameManager.roundManager.nextGameState()
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isDrawPhase ? "play.fill" : "forward.fill")
                    .font(.system(size: 22 * scale))
                    .foregroundStyle(.white)
                Text(isDrawPhase ? "Draw" : "Next")
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 80 * scale, height: 56 * scale)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [phaseColor.opacity(0.5), phaseColor.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(phaseColor.opacity(0.7), lineWidth: 1.5)
            )
            .shadow(color: phaseColor.opacity(glowIntensity), radius: 10)
            .scaleEffect(isPressed ? 0.93 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDrawPhase ? "Draw cards" : "Next round")
        .accessibilityHint(isDrawPhase && !canDraw ? "Set initiative for all characters first" : "Double tap to advance")
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
        .popover(isPresented: $showValidationWarning) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Missing Initiative")
                        .font(.headline)
                        .foregroundStyle(GlavenTheme.primaryText)
                }
                ForEach(missingInitiativeNames, id: \.self) { name in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text(name)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .frame(minWidth: 200)
        }
    }
}
