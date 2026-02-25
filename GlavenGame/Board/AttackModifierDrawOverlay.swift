import SwiftUI
import Foundation

/// Interactive overlay that lets the player physically draw attack modifier card(s) before combat resolves.
/// Handles normal draws, advantage (draw 2, use better), and disadvantage (draw 2, use worse).
/// Rolling modifier chains are drawn automatically until a terminal card is reached.
struct AttackModifierDrawOverlay: View {

    let pending: BoardCoordinator.PendingModifierDraw
    let coordinator: BoardCoordinator

    @Environment(\.uiScale) private var scale

    // MARK: - Draw Phase State

    private enum DrawPhase {
        case readyForFirst
        case drawnFirst(chain1: [AttackModifier])   // adv/disadv: waiting for second draw
        case done(chain1: [AttackModifier], chain2: [AttackModifier]?)
    }

    @State private var phase: DrawPhase = .readyForFirst
    @State private var revealCount1: Int = 0
    @State private var revealCount2: Int = 0

    private var needsTwo: Bool { pending.advantage || pending.disadvantage }

    // MARK: - View

    var body: some View {
        Color.black.opacity(0.72)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    headerSection
                    cardSection
                    Divider().overlay(Color.white.opacity(0.15))
                    buttonSection
                }
                .padding(24)
                .frame(maxWidth: 400 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
            }
    }

    // MARK: - Header

    @ViewBuilder private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Attack Modifier")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                pieceView(pending.attackerPiece)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
                pieceView(pending.defenderPiece)
            }

            Text("Base Attack \(pending.baseAttack)")
                .font(.system(size: 12 * scale))
                .foregroundStyle(.secondary)

            if pending.advantage && !pending.disadvantage {
                badge("ADVANTAGE — draw 2, use better", color: .green)
            } else if pending.disadvantage && !pending.advantage {
                badge("DISADVANTAGE — draw 2, use worse", color: .red)
            } else if pending.advantage && pending.disadvantage {
                badge("NORMAL — adv & disadv cancel (1 card)", color: .orange)
            } else {
                badge("NORMAL — 1 card draw", color: .gray)
            }
        }
    }

    /// Renders a rich piece label: thumbnail + name for characters, name + standee circle for monsters.
    @ViewBuilder private func pieceView(_ piece: PieceID) -> some View {
        switch piece {
        case .character(let charID):
            let char = coordinator.gameManager?.game.characters.first(where: { $0.id == charID })
            let displayName = char.map { $0.title.isEmpty ? $0.name.capitalized : $0.title } ?? charID
            let thumb: PlatformImage? = char.flatMap { ImageLoader.characterThumbnail(edition: $0.edition, name: $0.name) }
            HStack(spacing: 5) {
                if let img = thumb {
                    pieceImage(img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28 * scale, height: 28 * scale)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24 * scale))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text(displayName)
                    .font(.system(size: 17 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

        case .monster(let name, let standee):
            let formattedName = name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
            HStack(spacing: 5) {
                Text(formattedName)
                    .font(.system(size: 17 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                standeeCircle(standee)
            }

        case .summon(let summonID):
            let summonName = coordinator.gameManager?.game.characters
                .compactMap { $0.summons.first(where: { $0.id == summonID })?.name }
                .first ?? "Summon"
            Text(summonName)
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

        case .objective(let id):
            Text("Objective \(id)")
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Circled standee number badge.
    @ViewBuilder private func standeeCircle(_ number: Int) -> some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.15))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            Text("\(number)")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22 * scale, height: 22 * scale)
    }

    @ViewBuilder private func pieceImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }

    @ViewBuilder private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Cards

    @ViewBuilder private var cardSection: some View {
        switch phase {
        case .readyForFirst:
            if needsTwo {
                HStack(spacing: 20) {
                    cardSlot(nil, revealed: false, label: "Card 1")
                    cardSlot(nil, revealed: false, label: "Card 2")
                }
            } else {
                cardSlot(nil, revealed: false, label: nil)
            }

        case .drawnFirst(let chain1):
            HStack(spacing: 20) {
                chainColumn(chain1, revealCount: revealCount1, label: "Card 1", highlight: .none)
                cardSlot(nil, revealed: false, label: "Card 2")
            }

        case .done(let chain1, let chain2):
            if let chain2 = chain2 {
                let selected = resolveSelectedCards(chain1: chain1, chain2: chain2)
                let chain1Wins = chainWins(chain1, over: chain2, selected: selected)
                let chain2Wins = chainWins(chain2, over: chain1, selected: selected)
                let bothApplied = selected.count > 1 && selected == chain1 + chain2

                HStack(alignment: .top, spacing: 20) {
                    chainColumn(chain1, revealCount: revealCount1, label: "Card 1",
                                highlight: bothApplied ? .rolling : (chain1Wins ? .winner : .loser))
                    chainColumn(chain2, revealCount: revealCount2, label: "Card 2",
                                highlight: bothApplied ? .rolling : (chain2Wins ? .winner : .loser))
                }

                if bothApplied {
                    Text("Rolling — both cards applied")
                        .font(.system(size: 11 * scale, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            } else {
                // Normal draw
                chainColumn(chain1, revealCount: revealCount1, label: nil, highlight: .none)
            }
        }
    }

    private enum Highlight { case none, winner, loser, rolling }

    @ViewBuilder
    private func chainColumn(_ chain: [AttackModifier], revealCount: Int, label: String?, highlight: Highlight) -> some View {
        VStack(spacing: 4) {
            if let label = label {
                Text(label)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.secondary)
            }

            // Cards in chain (rolling cards + terminal)
            if chain.isEmpty {
                cardSlot(nil, revealed: false, label: nil)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(chain.enumerated()), id: \.offset) { index, card in
                        let isRevealed = index < revealCount
                        if index < chain.count - 1 {
                            // Rolling card
                            VStack(spacing: 2) {
                                cardSlot(card, revealed: isRevealed, label: nil)
                                if isRevealed {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8 * scale))
                                        .foregroundStyle(.yellow)
                                }
                            }
                        } else {
                            // Terminal card — apply highlight border
                            cardSlot(card, revealed: isRevealed, label: nil)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(highlightColor(highlight), lineWidth: isRevealed && highlight != .none ? 3 : 0)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isRevealed {
                                        highlightBadge(highlight)
                                            .offset(x: 4, y: -4)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func highlightColor(_ h: Highlight) -> Color {
        switch h {
        case .winner: return .yellow
        case .loser: return .red.opacity(0.6)
        case .rolling: return .yellow
        case .none: return .clear
        }
    }

    @ViewBuilder private func highlightBadge(_ h: Highlight) -> some View {
        switch h {
        case .winner:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12 * scale))
                .foregroundStyle(.yellow)
                .background(Circle().fill(.black))
        case .loser:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12 * scale))
                .foregroundStyle(.red.opacity(0.7))
                .background(Circle().fill(.black))
        case .rolling:
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 11 * scale))
                .foregroundStyle(.yellow)
                .background(Circle().fill(.black))
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func cardSlot(_ card: AttackModifier?, revealed: Bool, label: String?) -> some View {
        VStack(spacing: 2) {
            ZStack {
                AttackModifierCardBack(size: 100)
                    .opacity(revealed ? 0 : 1)
                    .rotation3DEffect(.degrees(revealed ? 90 : 0), axis: (x: 0, y: 1, z: 0))

                if let card = card {
                    AttackModifierCardView(modifier: card, size: 100)
                        .opacity(revealed ? 1 : 0)
                        .rotation3DEffect(.degrees(revealed ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                }
            }
            .frame(height: 100 * scale)

            if let label = label {
                Text(label)
                    .font(.system(size: 9 * scale))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Buttons

    @ViewBuilder private var buttonSection: some View {
        VStack(spacing: 10) {
            switch phase {
            case .readyForFirst:
                Button(action: drawFirst) {
                    Label(needsTwo ? "Draw Card 1" : "Draw", systemImage: "rectangle.stack.badge.plus")
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

            case .drawnFirst:
                Button(action: drawSecond) {
                    Label("Draw Card 2", systemImage: "rectangle.stack.badge.plus")
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

            case .done(let chain1, let chain2):
                let selected = chain2.map { resolveSelectedCards(chain1: chain1, chain2: $0) } ?? chain1
                let label = applyLabel(for: selected)
                Button(action: { applyResult(chain1: chain1, chain2: chain2) }) {
                    Label(label, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    // MARK: - Draw Logic

    /// Draws cards from the deck until a non-rolling card is reached, returning the full chain.
    private func drawChain() -> [AttackModifier] {
        var chain: [AttackModifier] = []
        repeat {
            guard let card = pending.drawCard() else { break }
            chain.append(card)
        } while chain.last?.rolling == true
        return chain.isEmpty ? [] : chain
    }

    private func drawFirst() {
        SoundPlayer.play(.cardFlip)
        let chain1 = drawChain()
        guard !chain1.isEmpty else { return }
        revealCount1 = 0
        if needsTwo {
            phase = .drawnFirst(chain1: chain1)
        } else {
            phase = .done(chain1: chain1, chain2: nil)
        }
        animateReveal(count: chain1.count, into: $revealCount1)
    }

    private func drawSecond() {
        guard case .drawnFirst(let chain1) = phase else { return }
        SoundPlayer.play(.cardFlip)
        let chain2 = drawChain()
        guard !chain2.isEmpty else { return }
        revealCount2 = 0
        phase = .done(chain1: chain1, chain2: chain2)
        animateReveal(count: chain2.count, into: $revealCount2)
    }

    private func animateReveal(count: Int, into binding: Binding<Int>) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.25) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    binding.wrappedValue = i + 1
                }
                if i > 0 { SoundPlayer.play(.cardFlip) }
            }
        }
    }

    private func applyResult(chain1: [AttackModifier], chain2: [AttackModifier]?) {
        let selected: [AttackModifier]
        if let chain2 = chain2 {
            selected = resolveSelectedCards(chain1: chain1, chain2: chain2)
        } else {
            selected = chain1
        }
        coordinator.completeModifierDraw(selectedCards: selected)
    }

    // MARK: - Rule Logic

    /// Selects the final cards to apply per official Gloomhaven v1 rules.
    private func resolveSelectedCards(chain1: [AttackModifier], chain2: [AttackModifier]) -> [AttackModifier] {
        let term1 = chain1.last
        let term2 = chain2.last

        if pending.advantage && !pending.disadvantage {
            let c1Rolling = chain1.count > 1
            let c2Rolling = chain2.count > 1
            if !c1Rolling && !c2Rolling {
                // Simple: pick the better terminal card
                if let t1 = term1, let t2 = term2 {
                    return CombatResolver.cardScore(t1) >= CombatResolver.cardScore(t2) ? [t1] : [t2]
                }
                return term1.map { [$0] } ?? term2.map { [$0] } ?? []
            } else {
                // At least one chain has rolling: apply all cards from both chains (v1 rule)
                return chain1 + chain2
            }
        } else if pending.disadvantage && !pending.advantage {
            // Disadvantage: ignore rolling, use the worse terminal card only
            if let t1 = term1, let t2 = term2 {
                return CombatResolver.cardScore(t1) <= CombatResolver.cardScore(t2) ? [t1] : [t2]
            }
            return term1.map { [$0] } ?? term2.map { [$0] } ?? []
        } else {
            // Both cancel out — use chain1's terminal only
            return term1.map { [$0] } ?? []
        }
    }

    /// Returns true if `thisChain`'s terminal is the "winning" selection (i.e., it appears in selected).
    private func chainWins(_ thisChain: [AttackModifier], over other: [AttackModifier], selected: [AttackModifier]) -> Bool {
        guard let terminal = thisChain.last else { return false }
        // If both chains are fully in selected (rolling case), neither individually "wins"
        if selected == thisChain + other || selected == other + thisChain { return false }
        return selected.contains(terminal)
    }

    private func applyLabel(for cards: [AttackModifier]) -> String {
        if cards.isEmpty { return "Apply" }
        if cards.count == 1, let card = cards.first {
            return "Apply \(card.displayText)"
        }
        // Multiple cards: show combined value
        var total = 0
        var hasMiss = false
        var hasDouble = false
        for card in cards {
            if card.valueType == .multiply {
                if card.value == 0 { hasMiss = true }
                else { hasDouble = true }
            } else {
                total += card.value
            }
        }
        if hasMiss { return "Apply MISS" }
        if hasDouble { return "Apply ×2 (+\(total))" }
        let sign = total >= 0 ? "+" : ""
        return "Apply \(sign)\(total) (rolling)"
    }
}
