import SwiftUI

struct TimerView: View {
    @Environment(GameManager.self) private var gameManager
    @State private var timer: Timer?

    private var isPlaying: Bool {
        gameManager.game.state == .next
    }

    private var displayTime: String {
        let seconds = gameManager.game.playSeconds
        if seconds >= 3600 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h)h \(m)m"
        } else {
            let m = seconds / 60
            let s = seconds % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                .font(.system(size: 10))
                .foregroundStyle(isPlaying ? GlavenTheme.positive : GlavenTheme.secondaryText)
            Text(displayTime)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(GlavenTheme.secondaryText)
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
        .onChange(of: isPlaying) { _, playing in
            if playing { startTimer() } else { stopTimer() }
        }
    }

    private func startTimer() {
        stopTimer()
        guard isPlaying else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            gameManager.game.playSeconds += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
