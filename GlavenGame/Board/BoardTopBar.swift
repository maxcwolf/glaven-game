import SwiftUI

/// The board's one top bar: the game menu, the round and what is happening in it, the goal,
/// the turn order (or who is choosing cards), and the elements.
struct BoardTopBar: View {
    @Environment(GameManager.self) private var gameManager
    let coordinator: BoardCoordinator
    @Binding var showSidePanels: Bool
    var onAbandon: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            menu
            heading
            if let brief = coordinator.scenarioBrief {
                goalChip(brief.goal)
            }
            Spacer(minLength: 4)
            let rail = coordinator.turnRail.isEmpty ? coordinator.selectionRail : coordinator.turnRail
            if !rail.isEmpty {
                TurnRailView(entries: rail)
                    .layoutPriority(1)
            }
            Spacer(minLength: 4)
            CompactElementBoard()
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(BoardTheme.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BoardTheme.border.opacity(0.5)).frame(height: 1)
        }
    }

    // MARK: - Menu

    /// The game menu: the view controls, and leaving the scenario (never a single stray tap).
    private var menu: some View {
        Menu {
            Button {
                coordinator.boardScene?.fitCamera(animated: true)
            } label: {
                Label("Show the Whole Board", systemImage: "viewfinder")
            }
            Button {
                coordinator.boardScene?.refitWhenHUDChanges()
                withAnimation(.snappy) { showSidePanels.toggle() }
            } label: {
                Label(showSidePanels ? "Hide Side Panels" : "Show Side Panels",
                      systemImage: showSidePanels ? "sidebar.squares.leading" : "rectangle.split.3x1")
            }
            Divider()
            Button {
                gameManager.saveAndQuitScenario()
            } label: {
                Label("Save & Quit to Menu", systemImage: "square.and.arrow.down")
            }
            Button(role: .destructive, action: onAbandon) {
                Label("Abandon Scenario…", systemImage: "flag.slash")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(BoardTheme.font(size: 18, weight: .medium))
                .foregroundStyle(BoardTheme.text)
                .frame(width: 44, height: 44)
                .background(BoardTheme.raised, in: Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Game menu")
    }

    // MARK: - Heading and goal

    private var heading: some View {
        let heading = coordinator.hudHeading
        return VStack(alignment: .leading, spacing: 0) {
            Text(heading.title)
                .font(BoardTheme.display(22))
                .foregroundStyle(BoardTheme.text)
            Text(heading.subtitle)
                .font(BoardTheme.font(size: 12, weight: .medium))
                .foregroundStyle(BoardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The goal in a few words; it opens the scenario's goal and rules.
    private func goalChip(_ goal: String) -> some View {
        Button {
            withAnimation(.snappy) { coordinator.briefPresentation = .reminder }
        } label: {
            Label(goal.hasSuffix(".") ? String(goal.dropLast()) : goal, systemImage: "scope")
                .font(BoardTheme.font(size: 13, weight: .medium))
                .foregroundStyle(BoardTheme.brass)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .overlay(Capsule().stroke(BoardTheme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()   // the goal is short; the rail scrolls before it's cut
        .accessibilityLabel("Goal: \(goal)")
        .accessibilityHint("Shows the scenario's goal and rules")
    }
}

/// The six elements, small: inert ones dim and grey, waning ones half-lit with a half ring,
/// strong ones bright with a full ring, infused-this-turn ones with a dashed ring.
struct CompactElementBoard: View {
    @Environment(GameManager.self) private var gameManager

    var body: some View {
        HStack(spacing: 4) {
            ForEach(gameManager.game.elementBoard) { element in
                CompactElement(element: element)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Elements")
    }
}

struct CompactElement: View {
    let element: ElementModel

    /// How lit the element is: 0 inert, 1 waning, 2 strong (or infused this turn).
    static func level(_ state: ElementState) -> Int {
        switch state {
        case .strong, .always, .new: return 2
        case .waning: return 1
        case .inert, .consumed, .partlyConsumed: return 0
        }
    }

    var body: some View {
        let level = Self.level(element.state)
        BundledImage(ImageLoader.elementIcon(element.type.rawValue), size: 24, systemName: "circle")
            .frame(width: 24, height: 24)
            .saturation(level == 0 ? 0 : 1)
            .opacity(level == 0 ? 0.32 : (level == 1 ? 0.75 : 1))
            .padding(3)
            .overlay {
                if element.state == .new {
                    Circle().stroke(BoardTheme.brass, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                } else if level > 0 {
                    Circle().trim(from: 0, to: level == 2 ? 1 : 0.5)
                        .stroke(BoardTheme.brass, lineWidth: 2)
                        .rotationEffect(.degrees(90))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: element.state)
            .help(GameText.elementStateDescription(element.type, element.state))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameText.elementStateDescription(element.type, element.state))
    }
}
