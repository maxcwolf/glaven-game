import SwiftUI

// MARK: - Marking what can be explained

/// Where each explainable thing sits on the screen, for a tip's spotlight and the "?" outlines.
struct LearnAnchorKey: PreferenceKey {
    static let defaultValue: [LearnSubject: Anchor<CGRect>] = [:]
    static func reduce(value: inout [LearnSubject: Anchor<CGRect>], nextValue: () -> [LearnSubject: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Something on the screen that explains itself: a long-press (or a tap after the "?") says
/// what it is, and a tip can point at it.
private struct Learnable: ViewModifier {
    @Environment(GameManager.self) private var gameManager
    let subject: LearnSubject

    func body(content: Content) -> some View {
        let coordinator = gameManager.boardCoordinator
        content
            .anchorPreference(key: LearnAnchorKey.self, value: .bounds) { [subject: $0] }
            .simultaneousGesture(LongPressGesture(minimumDuration: BoardScene.holdDuration).onEnded { _ in
                coordinator.explain(subject)
            })
            .overlay {
                // After the "?", a tap explains instead of acting.
                if coordinator.explainMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { coordinator.explain(subject) }
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAction(named: "Explain") { coordinator.explain(subject) }
    }
}

extension View {
    func learnable(_ subject: LearnSubject) -> some View { modifier(Learnable(subject: subject)) }
}

// MARK: - The card a tip or an explanation is shown on

struct LearnCard<Content: View>: View {
    /// Where a "topic:" link in the text opens How to Play.
    var coordinator: BoardCoordinator?
    var badge: String?
    let title: String
    var width: CGFloat = 400
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let badge {
                Label(badge, systemImage: "lightbulb.fill")
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .foregroundStyle(BoardTheme.brass)
                    .textCase(.uppercase)
            }
            Text(title)
                .font(BoardTheme.display(26))
                .foregroundStyle(BoardTheme.text)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(18)
        .frame(width: width, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard let id = LearnText.topic(of: url) else { return .systemAction }
            coordinator?.openHowToPlay(id)
            return .handled
        })
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.large).stroke(BoardTheme.brass.opacity(0.8), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
    }
}

private func learnParagraph(_ text: String) -> some View {
    Text(LearnText.attributed(text))
        .font(BoardTheme.font(size: 15))
        .foregroundStyle(BoardTheme.text)
        .fixedSize(horizontal: false, vertical: true)
}

/// A rule taught the first time it comes up.
struct TipCard: View {
    let tip: LearnTip
    let coordinator: BoardCoordinator

    var body: some View {
        let topic = LearnTopic.topic(tip.topic)
        LearnCard(coordinator: coordinator, badge: "First time \u{00B7} \(topic.chapter.rawValue)", title: topic.title) {
            if let lead = tip.lead {
                Text(lead)
                    .font(BoardTheme.font(size: 15, weight: .semibold))
                    .foregroundStyle(BoardTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(topic.paragraphs, id: \.self) { learnParagraph($0) }
            HStack(spacing: 10) {
                Button("More in How to Play") { coordinator.openHowToPlay(tip.topic) }
                    .buttonStyle(.boardQuietCompact)
                Spacer()
                Button("Got it") { coordinator.dismissTip() }
                    .buttonStyle(.boardPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
            Text("Learning mode \u{00B7} each tip shows once \u{00B7} turn it off in the game menu")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }
}

/// What a long-press (or the "?") says about something, or a monster's "Why?".
struct ExplanationCard: View {
    let explanation: Explanation
    let coordinator: BoardCoordinator

    var body: some View {
        LearnCard(coordinator: coordinator, title: explanation.title, width: 420) {
            if explanation.subtitle != nil || explanation.health != nil {
                HStack(spacing: 12) {
                    if let piece = explanation.portrait {
                        BundledImage(portrait(piece), size: 48, systemName: "person.circle")
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(BoardTheme.brass, lineWidth: 2))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let subtitle = explanation.subtitle {
                            Text(subtitle).font(BoardTheme.font(size: 14, weight: .semibold)).foregroundStyle(BoardTheme.brass)
                        }
                        if let detail = explanation.detail {
                            Text(detail).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
                        }
                    }
                    Spacer()
                    if let health = explanation.health {
                        Text(health).font(BoardTheme.font(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(BoardTheme.gain)
                    }
                }
            } else if let detail = explanation.detail {
                Text(detail).font(BoardTheme.font(size: 15, weight: .semibold)).foregroundStyle(BoardTheme.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(explanation.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label).font(BoardTheme.font(size: 12, weight: .semibold)).foregroundStyle(BoardTheme.secondaryText)
                            .frame(width: 92, alignment: .leading)
                        Text(row.value).font(BoardTheme.font(size: 15, weight: .semibold)).foregroundStyle(BoardTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = row.note {
                        Text(note).font(BoardTheme.font(size: 13)).foregroundStyle(BoardTheme.secondaryText)
                            .padding(.leading, 92)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(Array(explanation.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 10) {
                    Text(step.label)
                        .font(BoardTheme.font(size: 13, weight: .bold))
                        .foregroundStyle(BoardTheme.sheet)
                        .frame(width: 24, height: 24)
                        .background(BoardTheme.brass, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.value).font(BoardTheme.font(size: 15, weight: .semibold)).foregroundStyle(BoardTheme.text)
                        if let note = step.note {
                            Text(note).font(BoardTheme.font(size: 14)).foregroundStyle(BoardTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(explanation.paragraphs, id: \.self) { learnParagraph($0) }
            if let footnote = explanation.footnote {
                Text(footnote).font(BoardTheme.font(size: 12)).foregroundStyle(BoardTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let topic = explanation.topic {
                    Button(LearnTopic.topic(topic).title) { coordinator.openHowToPlay(topic) }
                        .buttonStyle(.boardQuietCompact)
                }
                Spacer()
                Button("Close") { coordinator.closeExplanation() }
                    .buttonStyle(.boardPrimary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 2)
            Text("Long-press anything to learn what it is")
                .font(BoardTheme.font(size: 12))
                .foregroundStyle(BoardTheme.secondaryText)
        }
    }

    private func portrait(_ piece: PieceID) -> PlatformImage? {
        switch piece {
        case .monster(let name, _):
            return ImageLoader.monsterThumbnail(edition: coordinator.gameManager?.game.monsters.first { $0.name == name }?.edition ?? "gh",
                                                name: name)
        case .character(let id):
            return coordinator.gameManager?.game.characters.first { $0.id == id }
                .flatMap { ImageLoader.characterThumbnail(edition: $0.edition, name: $0.name) }
        default:
            return nil
        }
    }
}

// MARK: - The overlay: spotlight, card, "?" outlines

/// Over the whole board: a tip with its spotlight, an explanation beside what it explains, or
/// the "?" outlines on everything that can be explained.
struct LearningOverlay: View {
    let coordinator: BoardCoordinator
    /// Where each explainable thing is, in this overlay's space.
    let anchors: [LearnSubject: CGRect]
    /// Where a figure or hex on the board is, in this overlay's space.
    let boardRect: (LearnSubject) -> CGRect?
    let size: CGSize
    @State private var cardHeight: CGFloat = 320

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tip = coordinator.pendingTip {
                let target = tip.anchor.flatMap(rect(for:))
                spotlight(target)
                    .allowsHitTesting(true)
                    .onTapGesture {}   // the board waits for the tip
                    .accessibilityHidden(true)
                card(width: 400, near: target) { TipCard(tip: tip, coordinator: coordinator) }
                    .id(tip.id)
            } else if let explanation = coordinator.explanation {
                Color.black.opacity(0.25)
                    .contentShape(Rectangle())
                    .onTapGesture { coordinator.closeExplanation() }
                    .accessibilityHidden(true)   // the card's Close does it
                card(width: 420, near: rect(for: explanation.anchor ?? explanation.subject)) {
                    ExplanationCard(explanation: explanation, coordinator: coordinator)
                }
                .id(explanation.id)
            } else if coordinator.explainMode {
                outlines
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func rect(for subject: LearnSubject) -> CGRect? {
        anchors[subject] ?? boardRect(subject)
    }

    /// Everything darkened but `hole` (if any), which gets a brass ring.
    private func spotlight(_ hole: CGRect?) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.55))
            if let hole {
                RoundedRectangle(cornerRadius: 12)
                    .frame(width: hole.width + 8, height: hole.height + 8)
                    .offset(x: hole.minX - 4, y: hole.minY - 4)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .overlay(alignment: .topLeading) {
            if let hole {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(BoardTheme.brass, lineWidth: 2)
                    .frame(width: hole.width + 8, height: hole.height + 8)
                    .offset(x: hole.minX - 4, y: hole.minY - 4)
            }
        }
    }

    /// The card beside `target` where it fits (right, left, below, above), or in the middle.
    private func card<Card: View>(width: CGFloat, near target: CGRect?, @ViewBuilder content: () -> Card) -> some View {
        let origin = Self.cardOrigin(width: width, height: cardHeight, near: target, in: size)
        return content()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .offset(x: origin.x, y: origin.y)
            .transition(.opacity)
    }

    /// Where a card of this size goes beside `target` without covering it or leaving the screen.
    static func cardOrigin(width: CGFloat, height: CGFloat, near target: CGRect?, in size: CGSize) -> CGPoint {
        let margin: CGFloat = 24, gap: CGFloat = 18
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, margin), max(margin, size.height - height - margin)) }
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, margin), max(margin, size.width - width - margin)) }
        guard let target else {
            return CGPoint(x: (size.width - width) / 2, y: clampY((size.height - height) / 2))
        }
        if target.maxX + gap + width + margin <= size.width {
            return CGPoint(x: target.maxX + gap, y: clampY(target.midY - height / 2))
        }
        if target.minX - gap - width >= margin {
            return CGPoint(x: target.minX - gap - width, y: clampY(target.midY - height / 2))
        }
        if target.maxY + gap + height + margin <= size.height {
            return CGPoint(x: clampX(target.midX - width / 2), y: target.maxY + gap)
        }
        return CGPoint(x: clampX(target.midX - width / 2), y: clampY(target.minY - gap - height))
    }

    /// The "?": every explainable thing outlined, and how to leave.
    private var outlines: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.black.opacity(0.3)).allowsHitTesting(false)
            ForEach(Array(anchors.values.enumerated()), id: \.offset) { _, rect in
                RoundedRectangle(cornerRadius: 10)
                    .stroke(BoardTheme.brass, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: rect.width + 6, height: rect.height + 6)
                    .offset(x: rect.minX - 3, y: rect.minY - 3)
                    .allowsHitTesting(false)
            }
            // The figures on the board.
            ForEach(Array(coordinator.boardState.piecePositions.keys.sorted().compactMap { boardRect(.piece($0)) }.enumerated()),
                    id: \.offset) { _, rect in
                Circle()
                    .stroke(BoardTheme.brass, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .frame(width: rect.width + 6, height: rect.height + 6)
                    .offset(x: rect.minX - 3, y: rect.minY - 3)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 14) {
                Label("Tap anything to learn what it is", systemImage: "hand.tap")
                    .font(BoardTheme.font(size: 15, weight: .medium))
                    .foregroundStyle(BoardTheme.text)
                Text("or long-press it any time")
                    .font(BoardTheme.font(size: 13))
                    .foregroundStyle(BoardTheme.secondaryText)
                Button("Done") { coordinator.toggleExplainMode() }
                    .buttonStyle(.boardPrimary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(BoardTheme.raised, in: Capsule())
            .overlay(Capsule().stroke(BoardTheme.brass, lineWidth: 1))
            .fixedSize()
            .frame(width: size.width)
            .offset(y: (anchors[.turnRail]?.maxY ?? 64) + 14)   // just under the top bar
        }
    }
}
