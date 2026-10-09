import SwiftUI

/// The round's turn order in the top bar: a portrait, initiative and name for each figure, the
/// one acting ringed in brass, the ones that have acted dimmed with a check. While cards are
/// being chosen it shows who is ready and who is choosing instead.
struct TurnRailView: View {
    let entries: [BoardCoordinator.TurnRailEntry]

    var body: some View {
        // Hug the chips when they fit; scroll when a big round doesn't.
        ViewThatFits(in: .horizontal) {
            chips
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) { chips }
                    .onChange(of: entries.first { $0.state == .current }?.id) { _, current in
                        guard let current else { return }
                        withAnimation(.snappy) { proxy.scrollTo(current, anchor: .center) }
                    }
            }
        }
        .background(BoardTheme.sheet, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Turn order")
    }

    private var chips: some View {
        HStack(spacing: 4) {
            ForEach(entries) { entry in
                chip(entry).id(entry.id)
            }
        }
        .padding(4)
    }

    private func chip(_ entry: BoardCoordinator.TurnRailEntry) -> some View {
        let isCurrent = entry.state == .current
        return HStack(spacing: 8) {
            portrait(entry)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().stroke(isCurrent ? BoardTheme.brass : .clear, lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    if entry.state == .done {
                        Image(systemName: entry.isLongRest ? "bed.double.fill" : "checkmark")
                            .font(BoardTheme.font(size: 11, weight: .bold))
                            .foregroundStyle(BoardTheme.sheet)
                            .frame(width: 17, height: 17)
                            .background(BoardTheme.gain, in: Circle())
                            .offset(x: 3, y: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if entry.showsInitiative {
                        Text("\(entry.initiative)").monospacedDigit()
                    }
                    Text(entry.name).lineLimit(1)
                    if entry.isLongRest && entry.state != .done {
                        Image(systemName: "bed.double.fill").accessibilityLabel("Long rest")
                    }
                }
                .font(BoardTheme.font(size: 13, weight: .semibold))
                .foregroundStyle(entry.state == .upcoming ? BoardTheme.secondaryText : BoardTheme.text)
                if let detail = entry.detail {
                    Text(detail)
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(isCurrent ? BoardTheme.brass : BoardTheme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(isCurrent ? BoardTheme.raised : .clear, in: Capsule())
        .overlay(Capsule().stroke(isCurrent ? BoardTheme.brass.opacity(0.7) : .clear, lineWidth: 1))
        .opacity(entry.state == .done ? 0.75 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(entry))
    }

    @ViewBuilder
    private func portrait(_ entry: BoardCoordinator.TurnRailEntry) -> some View {
        let image: PlatformImage? = {
            switch entry.kind {
            case .character(let edition, let name): return ImageLoader.characterThumbnail(edition: edition, name: name)
            case .monster(let edition, let name): return ImageLoader.monsterThumbnail(edition: edition, name: name)
            case .objective: return nil
            }
        }()
        if let image {
            #if os(macOS)
            Image(nsImage: image).resizable().scaledToFill()
            #else
            Image(uiImage: image).resizable().scaledToFill()
            #endif
        } else {
            Circle().fill(.gray.opacity(0.5))
        }
    }

    private func accessibilityText(_ entry: BoardCoordinator.TurnRailEntry) -> String {
        let state: String
        switch entry.state {
        case .done: state = "has acted"
        case .current: state = "acting now"
        case .upcoming: state = "still to act"
        }
        guard entry.showsInitiative else { return "\(entry.name), \(entry.detail ?? state)" }
        return "\(entry.name), initiative \(entry.initiative), \(state)"
    }
}

/// What the board is waiting for, in words: the ability being resolved and what to tap.
struct InstructionBanner: View {
    let instruction: BoardCoordinator.Instruction
    var onSkip: (() -> Void)?
    var onCancel: (() -> Void)?
    /// What can be picked on the board, offered to VoiceOver as actions (swipe up or down).
    var choices: [BoardChoice] = []
    /// Pause and fast-forward, while the monsters (or summons) play their turns.
    var playback: BoardCoordinator?

    var body: some View {
        HStack(spacing: 14) {
            prompt
            // Apart from the prompt, so VoiceOver reaches each on its own.
            if let playback {
                PlaybackControls(coordinator: playback)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(BoardTheme.raised, in: RoundedRectangle(cornerRadius: BoardTheme.Radius.medium))
        .overlay(RoundedRectangle(cornerRadius: BoardTheme.Radius.medium).stroke(BoardTheme.border, lineWidth: 1))
    }

    private var prompt: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.title)
                    .font(.headline)
                    .foregroundStyle(BoardTheme.text)
                Text(instruction.detail)
                    .font(.subheadline)
                    .foregroundStyle(BoardTheme.brass)
                ForEach(instruction.previews, id: \.self) { line in
                    Text(line)
                        .font(BoardTheme.font(size: 12).monospacedDigit())
                        .foregroundStyle(BoardTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if instruction.canCancel, let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.boardQuiet)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Takes the ability back to be performed again")
            }
            if instruction.canSkip, let onSkip {
                Button("Skip This Action", action: onSkip)
                    .buttonStyle(.boardQuiet)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(choices.isEmpty ? "" : "\(choices.count) choice\(choices.count == 1 ? "" : "s"): swipe up or down to hear them, double-tap to choose")
        .accessibilityActions {
            ForEach(choices) { choice in
                Button(choice.label, action: choice.perform)
            }
        }
    }
}

/// Pause and fast-forward for the turns that play themselves. Space pauses and resumes,
/// F fast-forwards.
struct PlaybackControls: View {
    let coordinator: BoardCoordinator

    var body: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.setPaused(!coordinator.isPaused)
            } label: {
                Label(coordinator.isPaused ? "Resume" : "Pause",
                      systemImage: coordinator.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(coordinator.isPaused ? .boardPrimary : .boardQuiet)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityHint(coordinator.isPaused ? "Lets the turns go on" : "Stops the turns before their next step")

            Button {
                coordinator.setFastForward(!coordinator.isFastForward)
            } label: {
                Label(coordinator.isFastForward ? "Normal Speed" : "Fast-Forward",
                      systemImage: coordinator.isFastForward ? "forward.end.fill" : "forward.fill")
            }
            .buttonStyle(.boardQuiet)
            .keyboardShortcut("f", modifiers: [])
            .accessibilityHint(coordinator.isFastForward ? "Plays the turns at the usual pace"
                               : "Plays the turns faster until your next turn")
        }
    }
}
