import SwiftUI

/// The round's turn order: a portrait and initiative for each figure, with the one acting lit,
/// the ones that have acted dimmed and the rest still to come.
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
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Turn order")
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(entries) { entry in
                chip(entry).id(entry.id)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    private func chip(_ entry: BoardCoordinator.TurnRailEntry) -> some View {
        let isCurrent = entry.state == .current
        return HStack(spacing: 6) {
            portrait(entry)
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            Text("\(entry.initiative)")
                .font(.subheadline.monospacedDigit().weight(.bold))
            Text(entry.name)
                .font(.subheadline)
                .lineLimit(1)
            if entry.isLongRest {
                Image(systemName: "bed.double.fill")
                    .font(.caption)
                    .accessibilityLabel("Long rest")
            }
            if entry.state == .done {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(isCurrent ? Color(red: 0.95, green: 0.84, blue: 0.62) : .white)
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(isCurrent ? Color(red: 0.23, green: 0.17, blue: 0.08) : .clear)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isCurrent ? Color(red: 0.89, green: 0.70, blue: 0.24) : .clear, lineWidth: 1.5))
        .opacity(entry.state == .done ? 0.45 : 1)
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
        return "\(entry.name), initiative \(entry.initiative), \(state)"
    }
}

/// What the board is waiting for, in words: the ability being resolved and what to tap.
struct InstructionBanner: View {
    let instruction: BoardCoordinator.Instruction
    var onSkip: (() -> Void)?
    /// What can be picked on the board, offered to VoiceOver as actions (swipe up or down).
    var choices: [BoardChoice] = []

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instruction.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(instruction.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.66))
            }
            if instruction.canSkip, let onSkip {
                Button("Skip This Action", action: onSkip)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(red: 0.11, green: 0.09, blue: 0.08).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.42, green: 0.33, blue: 0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityHint(choices.isEmpty ? "" : "\(choices.count) choice\(choices.count == 1 ? "" : "s"): swipe up or down to hear them, double-tap to choose")
        .accessibilityActions {
            ForEach(choices) { choice in
                Button(choice.label, action: choice.perform)
            }
        }
    }
}
