import SwiftUI

struct ElementView: View {
    let element: ElementModel
    @Environment(GameManager.self) private var gameManager
    @State private var isHovered = false
    @State private var waningPulse = false

    private var isStrong: Bool {
        element.state == .new || element.state == .strong || element.state == .always
    }

    private var isWaning: Bool {
        element.state == .waning
    }

    var body: some View {
        ZStack {
            // Strong: large bright halo — most pronounced
            if isStrong {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 46, height: 46)

                Circle()
                    .strokeBorder(color, lineWidth: 3)
                    .frame(width: 46, height: 46)
            }

            // Waning: medium halo with pulsing ring
            if isWaning {
                Circle()
                    .fill(color.opacity(waningPulse ? 0.3 : 0.15))
                    .frame(width: 42, height: 42)

                Circle()
                    .strokeBorder(color.opacity(waningPulse ? 0.9 : 0.5), lineWidth: 2.5)
                    .frame(width: 42, height: 42)
            }

            BundledImage(
                ImageLoader.elementIcon(element.type.rawValue),
                size: 28,
                systemName: fallbackIconName
            )
            .foregroundStyle(color)
            .opacity(iconOpacity)
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        }
        .frame(width: 48, height: 48)
        .shadow(color: isStrong ? color.opacity(0.8) : .clear, radius: isStrong ? 8 : 0)
        .shadow(color: isWaning ? color.opacity(0.5) : .clear, radius: isWaning ? 5 : 0)
        .scaleEffect(isStrong ? 1.1 : (isHovered ? 1.08 : 1.0))
        .animation(.easeInOut(duration: 0.3), value: element.state)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onChange(of: element.state) { _, newState in
            if newState == .waning {
                waningPulse = false
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    waningPulse = true
                }
            } else {
                withAnimation(.linear(duration: 0.1)) {
                    waningPulse = false
                }
            }
        }
        .onAppear {
            if element.state == .waning {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    waningPulse = true
                }
            }
        }
        .onTapGesture {
            SoundPlayer.play(.tap)
            cycleState()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var fallbackIconName: String {
        switch element.type {
        case .fire: return "flame.fill"
        case .ice: return "snowflake"
        case .air: return "wind"
        case .earth: return "leaf.fill"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .wild: return "sparkles"
        }
    }

    private var color: Color {
        switch element.type {
        case .fire: return .red
        case .ice: return .cyan
        case .air: return .gray
        case .earth: return .green
        case .light: return .yellow
        case .dark: return .indigo
        case .wild: return .purple
        }
    }

    private var iconOpacity: Double {
        switch element.state {
        case .inert: return GlavenTheme.isLight ? 0.9 : 0.8
        case .new, .strong: return 1.0
        case .waning: return 0.9
        case .consumed, .partlyConsumed: return GlavenTheme.isLight ? 0.8 : 0.7
        case .always: return 1.0
        }
    }

    private func cycleState() {
        guard let idx = gameManager.game.elementBoard.firstIndex(where: { $0.type == element.type }) else { return }
        switch element.state {
        case .inert:
            gameManager.game.elementBoard[idx].state = .new
        case .new, .strong:
            gameManager.game.elementBoard[idx].state = .waning
        case .waning:
            gameManager.game.elementBoard[idx].state = .inert
        case .consumed, .partlyConsumed:
            gameManager.game.elementBoard[idx].state = .inert
        case .always:
            break
        }
    }
}
