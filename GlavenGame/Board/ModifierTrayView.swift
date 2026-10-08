import SwiftUI

/// The attack modifier deck beside the board, with the real card art. On the player's own attack
/// the face-down deck is the button that draws; every attack's cards (monsters' too) flip face up
/// here and stay, with the attack's sum, until the next attack. Nothing covers the board.
struct ModifierTrayView: View {
    @Bindable var coordinator: BoardCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardHeight: CGFloat = 62

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let pending = coordinator.pendingModifierDraw {
                drawPrompt(pending)
            } else if let reveal = coordinator.lastModifierReveal {
                revealView(reveal)
                    .id(reveal.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
            } else {
                Text("Attack modifier cards appear here.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(coordinator.pendingModifierDraw != nil ? Color(red: 0.89, green: 0.70, blue: 0.24) : .white.opacity(0.08),
                          lineWidth: coordinator.pendingModifierDraw != nil ? 2 : 1))
        .padding(.horizontal, 8)
        .animation(reduceMotion ? nil : .snappy, value: coordinator.lastModifierReveal?.id)
        .animation(reduceMotion ? nil : .snappy, value: coordinator.pendingModifierDraw?.id)
    }

    private var header: some View {
        HStack {
            Text(deckTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Spacer()
        }
    }

    private var deckTitle: String {
        if let pending = coordinator.pendingModifierDraw {
            return "\(coordinator.name(pending.attackerPiece))\u{2019}s modifier deck"
        }
        if let reveal = coordinator.lastModifierReveal {
            return reveal.drawnByPlayer ? "\(coordinator.name(reveal.attacker))\u{2019}s draw"
                : "Drawn for \(coordinator.name(reveal.attacker))"
        }
        return "Modifier deck"
    }

    private func drawPrompt(_ pending: BoardCoordinator.PendingModifierDraw) -> some View {
        Button {
            BoardSoundPlayer.play(.card)
            coordinator.drawPendingModifiers()
        } label: {
            HStack(spacing: 12) {
                cardBack
                VStack(alignment: .leading, spacing: 3) {
                    Text("Draw")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Attack \(pending.baseAttack) on \(coordinator.name(pending.defenderPiece))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                    if pending.advantage != pending.disadvantage {
                        Text(pending.advantage ? "With advantage: draw 2, keep the better" : "With disadvantage: draw 2, keep the worse")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.95, green: 0.84, blue: 0.62))
                            .lineLimit(2)
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("d", modifiers: [])
        .accessibilityLabel("Draw attack modifier for \(coordinator.name(pending.attackerPiece))")
    }

    private var cardBack: some View {
        Group {
            if let image = ImageLoader.amCardBack() {
                #if os(macOS)
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                #endif
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.25, green: 0.2, blue: 0.15))
                    .aspectRatio(1.5, contentMode: .fit)
            }
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
    }

    private func revealView(_ reveal: BoardCoordinator.ModifierReveal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(reveal.drawn.enumerated()), id: \.offset) { index, card in
                        let applies = reveal.applies(at: index)
                        VStack(spacing: 3) {
                            AttackModifierCardView(modifier: card, size: cardHeight)
                                .opacity(applies ? 1 : 0.35)
                                .overlay(alignment: .topTrailing) {
                                    if !applies {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                    }
                                }
                            ForEach(GameText.modifierEffects(card), id: \.self) { effect in
                                Text(effect)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color(red: 0.85, green: 0.81, blue: 0.97))
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityText(card, applies: applies))
                    }
                }
            }
            Text(reveal.sum.map { "\(coordinator.name(reveal.attacker)) \u{2192} \(coordinator.name(reveal.defender)): \($0)" }
                 ?? "\(coordinator.name(reveal.attacker)) \u{2192} \(coordinator.name(reveal.defender))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accessibilityText(_ card: AttackModifier, applies: Bool) -> String {
        let value: String
        switch card.type {
        case .null_, .curse: value = "Miss"
        case .double_, .bless: value = "Double"
        default: value = card.value >= 0 ? "Plus \(card.value)" : "Minus \(-card.value)"
        }
        let effects = GameText.modifierEffects(card)
        let base = effects.isEmpty ? value : "\(value), \(effects.joined(separator: ", "))"
        return applies ? base : "\(base), not used"
    }
}
