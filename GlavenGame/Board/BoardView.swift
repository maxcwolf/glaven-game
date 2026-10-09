import SwiftUI
import SpriteKit

/// SwiftUI wrapper for the SpriteKit game board with HUD overlays.
struct BoardView: View {
    @Environment(GameManager.self) private var gameManager
    @Bindable var coordinator: BoardCoordinator
    @State private var previewMonsterAbility: (GameMonster, AbilityModel)?
    @State private var confirmingAbandon = false
    /// The side columns (party, monsters, battle log) can be hidden to see the whole board.
    @State private var showSidePanels = true
    @State private var logExpanded = true
    /// Where the board and the HUD's panels sit, so the board is framed in the clear part.
    @State private var hudFrames = HUDFrames()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // SpriteKit board
            if let scene = coordinator.boardScene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
                    .reportFrame { hudFrames.board = $0 }
                    .onAppear {
                        scene.reduceMotion = reduceMotion
                        scene.setHUDObstacles(hudObstacles)
                    }
                    .onChange(of: reduceMotion) { _, value in scene.reduceMotion = value }
                    .onChange(of: hudObstacles) { _, obstacles in scene.setHUDObstacles(obstacles) }
            } else {
                Color.black
                    .overlay {
                        Text("No board loaded")
                            .foregroundStyle(.white)
                    }
            }

            // HUD overlays
            VStack(spacing: 0) {
                boardHUD
                    .reportFrame { hudFrames.hud = $0 }
                let rail = coordinator.turnRail
                if !rail.isEmpty {
                    TurnRailView(entries: rail)
                        .reportFrame { hudFrames.rail = $0 }
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }
                if showSidePanels {
                    HStack(alignment: .top, spacing: 0) {
                        // Left: the party, and the modifier tray under it
                        VStack(alignment: .leading, spacing: 0) {
                            characterInfoPanel
                            if coordinator.boardPhase == .execution || coordinator.pendingModifierDraw != nil {
                                ModifierTrayView(coordinator: coordinator)
                            }
                        }
                        .reportFrame { hudFrames.left = $0 }
                        Spacer(minLength: 0)
                        // Right: monster info + battle log, each capped so the board stays visible
                        VStack(spacing: 4) {
                            monsterInfoPanel
                                .layoutPriority(1)   // the log shrinks before the monsters do
                            turnLogPanel
                        }
                        .reportFrame { hudFrames.right = $0 }
                    }
                    .transition(.opacity)
                }
                Spacer()
                bottomBar
            }

            // Card selection overlay
            if coordinator.boardPhase == .cardSelection,
               let charID = coordinator.cardSelectingCharacterID,
               let character = gameManager.game.characters.first(where: { $0.id == charID }) {
                VStack {
                    Spacer()
                    CardSelectionPanel(
                        coordinator: coordinator,
                        character: character
                    )
                    .id(charID) // Force recreate @State when character changes
                    .padding()
                }
                .transition(.move(edge: .bottom))
            }

            // Damage mitigation prompt
            if let pending = coordinator.pendingDamage,
               let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) {
                DamageChoiceSheet(pending: pending, character: character, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // A defence item offered while an enemy attacks
            if let pending = coordinator.pendingItemUse {
                ItemUsePrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Recovering discarded cards (Minor Stamina Potion)
            if let pending = coordinator.pendingRecovery,
               let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) {
                RecoveryPicker(pending: pending, character: character, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }

            // Elements to infuse, a condition to remove (Mana Potions, Minor Cure Potion)
            if let pending = coordinator.pendingElementChoice {
                ElementChoicePrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }
            if let pending = coordinator.pendingInitiativeChange {
                InitiativeChangePrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }
            if let pending = coordinator.pendingSufferChoice {
                SufferChoicePrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }
            if let pending = coordinator.pendingAllyChoice {
                AllyChoicePrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }
            if let pending = coordinator.pendingItemRefresh {
                ItemRefreshPrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }
            if let pending = coordinator.pendingConditionRemoval {
                ConditionRemovalPrompt(pending: pending, coordinator: coordinator)
                    .id(pending.id)
                    .transition(.opacity)
            }

            // Long rest card choice prompt
            if let pending = coordinator.pendingLongRest,
               let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) {
                longRestOverlay(character: character)
            }

            // Short rest prompt
            if let pending = coordinator.pendingShortRest,
               let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) {
                shortRestOverlay(pending: pending, character: character)
            }

            // Monster ability card preview (tap on monster group in info panel)
            if let (monster, ability) = previewMonsterAbility {
                monsterAbilityPreviewOverlay(monster: monster, ability: ability)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .animation(.easeInOut(duration: 0.15), value: previewMonsterAbility != nil)
                    .zIndex(8)
            }

            // Full-size card image preview overlay
            if let cardId = coordinator.previewCardId {
                cardImagePreviewOverlay(cardId: cardId)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: coordinator.previewCardId)
            }

            // The scenario's intro, or its goal and rules reopened from the HUD
            if let presentation = coordinator.briefPresentation, let brief = coordinator.scenarioBrief {
                ScenarioBriefCard(brief: brief, buttonTitle: presentation == .intro ? "Begin" : "Close",
                                  onDismiss: { withAnimation(.snappy) { coordinator.briefPresentation = nil } },
                                  battleGoals: gameManager.game.characters.filter { !$0.absent }.compactMap { character in
                                      gameManager.scenarioManager.chosenBattleGoal(of: character).map {
                                          (GameText.characterName(character, labels: gameManager.editionStore), $0)
                                      }
                                  },
                                  tableRules: gameManager.game.tableRules.inPlay)
                .transition(.opacity)
                .zIndex(9)
                .onAppear { if presentation == .intro { BoardSoundPlayer.play(.start) } }
            }

            // Results
            if let outcome = coordinator.scenarioOutcome() {
                ScenarioResultsView(outcome: outcome) { choices in coordinator.confirmScenarioEnd(choices: choices) }
                    .transition(.opacity)
                    .zIndex(10)
                    .onAppear { BoardSoundPlayer.play(outcome.victory ? .victory : .defeat) }
            }
        }
    }

    // MARK: - Board framing

    /// Frames (global, y down) of the board and the panels over it.
    struct HUDFrames: Equatable {
        var board: CGRect = .zero
        var hud: CGRect = .zero
        var rail: CGRect = .zero
        var left: CGRect = .zero
        var right: CGRect = .zero
        /// The largest the bottom-left bar has been this scenario: the board keeps clear of all of
        /// it, so it doesn't jump each time the bar changes (actions, End Turn, a monster's turn).
        private(set) var bottomLeading: CGRect = .zero
        var bottomTrailing: CGRect = .zero

        mutating func reportBottomLeading(_ frame: CGRect) {
            guard !frame.isEmpty else { return }
            bottomLeading = bottomLeading.isEmpty ? frame : bottomLeading.union(frame)
        }

        /// The panels over the board, in board view points. The side panels count as whole
        /// columns: they grow and shrink as the turn goes on, and the board shouldn't chase them.
        func obstacles(showingSidePanels: Bool) -> [CGRect] {
            func column(_ frame: CGRect) -> CGRect {
                guard showingSidePanels, !frame.isEmpty else { return .zero }
                return CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                              height: max(frame.height, board.maxY - frame.minY))
            }
            return BoardViewport.obstacles([hud, rail, column(left), column(right), bottomLeading, bottomTrailing],
                                           over: board)
        }
    }

    private var hudObstacles: [CGRect] { hudFrames.obstacles(showingSidePanels: showSidePanels) }

    // MARK: - Top HUD

    @ViewBuilder
    private var boardHUD: some View {
        HStack(spacing: 16) {
            // What is happening: "Place Your Characters", "Brute’s Turn · 20"
            Text(coordinator.phaseTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())

            // The scenario's goal and special rules, any time.
            if coordinator.scenarioBrief != nil {
                Button {
                    withAnimation(.snappy) { coordinator.briefPresentation = .reminder }
                } label: {
                    Label("Goal", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BoardTheme.text)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(BoardTheme.brass.opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scenario goal and rules")
            }

            Spacer()

            // Element board
            ElementBoardView()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Round counter (hidden while placing characters, before round 1)
            if let round = coordinator.displayedRound {
                Text("Round \(round)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
            }

            // Frame the whole board again after panning and zooming.
            Button {
                coordinator.boardScene?.fitCamera(animated: true)
            } label: {
                Image(systemName: "viewfinder")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show the whole board")

            // Show or hide the side columns to see the whole board.
            Button {
                coordinator.boardScene?.refitWhenHUDChanges()
                withAnimation(.snappy) { showSidePanels.toggle() }
            } label: {
                Image(systemName: showSidePanels ? "sidebar.squares.leading" : "rectangle.split.3x1")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSidePanels ? "Hide side panels" : "Show side panels")

            // Game menu: leaving the scenario never happens on a single stray tap.
            Menu {
                Button {
                    gameManager.saveAndQuitScenario()
                } label: {
                    Label("Save & Quit to Menu", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    confirmingAbandon = true
                } label: {
                    Label("Abandon Scenario…", systemImage: "flag.slash")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Game menu")
        }
        .padding()
        .confirmationDialog("Abandon this scenario?", isPresented: $confirmingAbandon, titleVisibility: .visible) {
            Button("Abandon Scenario", role: .destructive) {
                gameManager.completeScenario(success: false)
            }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("It counts as a loss. Your characters keep the experience and gold they've collected.")
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(alignment: .top, spacing: 0) {
            // Main execution/setup content — takes all remaining space
            HStack(spacing: 12) {
                if coordinator.boardPhase == .setup {
                    setupBottomBar
                        .padding(10)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                        .reportFrame { hudFrames.reportBottomLeading($0) }
                } else if coordinator.boardPhase == .execution {
                    executionBottomBar
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()

            // Monster ability cards — natural content width, pinned to the right
            if coordinator.boardPhase == .execution {
                MonsterAbilityStripView(coordinator: coordinator, cardWidth: 140)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    .reportFrame { hudFrames.bottomTrailing = $0 }
                    .padding(.trailing, 8)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var setupBottomBar: some View {
        let allPlaced = gameManager.game.characters.allSatisfy { char in
            coordinator.boardState.piecePositions.keys.contains(.character(char.id))
        }

        VStack(spacing: 10) {
            // Instruction
            if !allPlaced {
                Label("Tap a lit starting hex to place the chosen character, or pick another first", systemImage: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else if case .placingCharacter = coordinator.interactionMode {
                Label("Tap a lit starting hex to move there", systemImage: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(spacing: 12) {
                // Character placement cards
                ForEach(gameManager.game.characters, id: \.id) { character in
                    let charColor = Color(hex: character.color) ?? .blue
                    let placed = coordinator.boardState.piecePositions.keys.contains(.character(character.id))
                    let isSelecting: Bool = {
                        if case .placingCharacter(let id) = coordinator.interactionMode {
                            return id == character.id
                        }
                        return false
                    }()

                    Button {
                        coordinator.beginPlaceCharacter(characterID: character.id)
                    } label: {
                        HStack(spacing: 8) {
                            BundledImage(ImageLoader.characterIcon(edition: character.edition, name: character.name), size: 20, systemName: "person.fill")
                                .foregroundStyle(placed ? .white.opacity(0.4) : charColor)

                            Text(GameText.characterName(character, labels: gameManager.editionStore))
                                .font(BoardTheme.font(size: 13, weight: .bold))
                                .foregroundStyle(placed ? .white.opacity(0.4) : .white)

                            if placed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(BoardTheme.font(size: 14))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(placed ? .white.opacity(0.05) : charColor.opacity(0.2))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelecting ? charColor : charColor.opacity(placed ? 0.1 : 0.4), lineWidth: isSelecting ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(placed ? "Move to another starting hex" : "Choose a starting hex")
                }

                Spacer()

                // Begin scenario button
                if allPlaced && !gameManager.game.characters.isEmpty {
                    Button {
                        coordinator.finishSetup()
                    } label: {
                        Label("Begin Scenario", systemImage: "play.fill")
                            .font(BoardTheme.font(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Character color for the active player turn.
    private var activeCharacterColor: Color {
        if let ptc = coordinator.activePlayerTurn,
           let char = gameManager.game.characters.first(where: { $0.id == ptc.characterID }) {
            return Color(hex: char.color) ?? .blue
        }
        return .blue
    }

    @ViewBuilder
    private var executionBottomBar: some View {
        if let playerTurn = coordinator.activePlayerTurn {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Active card display
                    activeCardDisplay(playerTurn: playerTurn)

                    // Action buttons
                    VStack(alignment: .leading, spacing: 8) {
                        if playerTurn.phase == .executeTopAction || playerTurn.phase == .executeBottomAction {
                            let actions = playerTurn.phase == .executeTopAction ? playerTurn.topActions : playerTurn.bottomActions
                            let idx = playerTurn.currentActionIndex

                            // While a step waits for a hex or a target, the banner has its Skip and
                            // Cancel; the step's own button would do nothing.
                            if playerTurn.isWaiting {
                                EmptyView()
                            } else if idx < actions.count {
                                let action = actions[idx]
                                let noTarget = playerTurn.attackHasNoTarget(action)
                                Button {
                                    playerTurn.executeCurrentAction()
                                } label: {
                                    Label(GameText.actionTitle(action), systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(noTarget ? .gray : BoardTheme.brass)
                                if noTarget {
                                    // Performing it now does nothing: a move first, or Skip, may be better.
                                    Label("No enemy in range", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(BoardTheme.secondaryText)
                                }
                            } else {
                                Button {
                                    playerTurn.executeCurrentAction()
                                } label: {
                                    Label(playerTurn.phase == .executeTopAction && !playerTurn.bottomFirst
                                          ? "Continue to Bottom Half" : "Continue", systemImage: "forward.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.gray)
                            }

                            if !playerTurn.hasActed {
                                // Either card may provide the top half, and either half may go first.
                                HStack(spacing: 8) {
                                    Button("Swap Cards") {
                                        playerTurn.swapCards()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Use the other card's top half and this card's bottom half")

                                    Toggle("Bottom first", isOn: Binding(
                                        get: { playerTurn.bottomFirst },
                                        set: { playerTurn.setBottomFirst($0) }
                                    ))
                                    .toggleStyle(.button)
                                    .controlSize(.small)
                                }
                            }

                            if !playerTurn.isWaiting {
                            HStack(spacing: 8) {
                                if playerTurn.canUseDefaultAction {
                                    Button(playerTurn.defaultActionTitle) {
                                        playerTurn.useDefaultAction()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.cyan)
                                    .controlSize(.small)
                                }

                                Button("Skip Rest of Half") {
                                    playerTurn.skipRemainingActions()
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                                .controlSize(.small)
                            }
                            }

                            // Items whose moment has come: during this move, this attack, or the turn.
                            let items = coordinator.usableItems()
                            if !items.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(items, id: \.itemKey) { item in
                                        Button {
                                            coordinator.useItem(item)
                                        } label: {
                                            Label("Use \(item.name)", systemImage: item.consumed ? "flask.fill" : "shield.lefthalf.filled")
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(BoardTheme.brass)
                                        .controlSize(.small)
                                        .accessibilityHint(item.consumed ? "Used up for the scenario" : "Spent until a long rest")
                                    }
                                }
                            }
                        }

                        if playerTurn.phase == .turnComplete {
                            Button {
                                coordinator.finishPlayerTurn()
                            } label: {
                                Label("End Turn", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Multi-target confirmation
                    if case .selectingMultiAttackTargets(_, _, _, let targetCount, let selected) = coordinator.interactionMode {
                        VStack(spacing: 4) {
                            if !selected.isEmpty {
                                Button("Confirm \(selected.count) Target\(selected.count == 1 ? "" : "s")") {
                                    coordinator.confirmMultiAttack()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    instructionBanner
                }
                .padding(.trailing, 8)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                .reportFrame { hudFrames.reportBottomLeading($0) }
                Spacer()
            }
        } else {
            instructionBanner
                .reportFrame { hudFrames.reportBottomLeading($0) }
            Spacer()
        }
    }

    /// What the board is waiting for, beside the action buttons so it never covers the board.
    @ViewBuilder
    private var instructionBanner: some View {
        if let instruction = coordinator.instruction(for: coordinator.interactionMode) {
            InstructionBanner(instruction: instruction, onSkip: coordinator.activePlayerTurn.map { turn in
                { turn.skipCurrentAction() }
            }, onCancel: coordinator.activePlayerTurn.map { turn in
                { turn.cancelChoice() }
            }, choices: coordinator.accessibleChoices())
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: instruction)
        }
    }

    /// Shows the active card (top or bottom) with the relevant half highlighted.
    @ViewBuilder
    private func activeCardDisplay(playerTurn: PlayerTurnController) -> some View {
        let isTop = playerTurn.phase == .executeTopAction
        let isBtm = playerTurn.phase == .executeBottomAction
        let card = isTop ? playerTurn.topCard : (isBtm ? playerTurn.bottomCard : nil)
        let edition = gameManager.game.characters.first(where: { $0.id == playerTurn.characterID })?.edition ?? "gh"
        let resolver = labelResolver(for: edition)

        if let card {
            ActiveCardHalf(card: card, isTop: isTop, characterColor: activeCharacterColor,
                           labelResolver: resolver, onPreview: previewAction(card: card))
                .padding(.leading, 8)
                .padding(.vertical, 6)
        } else if playerTurn.phase == .turnComplete {
            // Show both cards side by side, dimmed
            HStack(spacing: 6) {
                if let top = playerTurn.topCard {
                    BoardAbilityCardView(
                        card: top,
                        characterColor: activeCharacterColor,
                        highlight: .none,
                        width: 90,
                        height: 150,
                        labelResolver: resolver,
                        onPreview: previewAction(card: top)
                    )
                    .opacity(0.5)
                }
                if let btm = playerTurn.bottomCard {
                    BoardAbilityCardView(
                        card: btm,
                        characterColor: activeCharacterColor,
                        highlight: .none,
                        width: 90,
                        height: 150,
                        labelResolver: resolver,
                        onPreview: previewAction(card: btm)
                    )
                    .opacity(0.5)
                }
            }
            .padding(.leading, 8)
        }
    }

    // MARK: - Character Info Panel

    @ViewBuilder
    private var characterInfoPanel: some View {
        let characters = gameManager.game.characters.filter { !$0.absent }

        if !characters.isEmpty {
            let cards = VStack(spacing: 6) {
                ForEach(characters, id: \.id) { character in
                    characterCard(character)
                }
            }
            .padding(6)
            // Sized to the party; scrolls only when the screen is too short for it.
            ViewThatFits(in: .vertical) {
                cards
                ScrollView { cards }
            }
            .frame(width: 260)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(8)
        }
    }

    @ViewBuilder
    private func characterCard(_ character: GameCharacter) -> some View {
        let charColor = Color(hex: character.color) ?? .blue
        let isExhausted = character.exhausted || character.health <= 0

        VStack(alignment: .leading, spacing: 4) {
            // Name row
            HStack(spacing: 6) {
                BundledImage(ImageLoader.characterIcon(edition: character.edition, name: character.name), size: 14, systemName: "person.fill")
                    .foregroundStyle(charColor)
                    .opacity(isExhausted ? 0.4 : 1.0)
                Text(GameText.characterName(character, labels: gameManager.editionStore))
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .foregroundStyle(isExhausted ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                Spacer()
                if isExhausted {
                    Text("OUT")
                        .font(BoardTheme.font(size: 11, weight: .heavy))
                        .foregroundStyle(.red)
                }
            }

            if !isExhausted {
                // HP bar
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.red)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(hpColor(current: character.health, max: character.maxHealth))
                                .frame(width: geo.size.width * CGFloat(max(0, character.health)) / CGFloat(max(1, character.maxHealth)))
                        }
                    }
                    .frame(height: 6)

                    Text("\(character.health)/\(character.maxHealth)")
                        .font(BoardTheme.font(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Stats row: XP, Hand, Discard
                HStack(spacing: 8) {
                    Label("\(character.experience)", systemImage: "star.fill")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.yellow.opacity(0.8))
                    Label("\(character.handCards.count)", systemImage: "hand.raised.fill")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.cyan.opacity(0.8))
                    Label("\(character.discardedCards.count)", systemImage: "arrow.counterclockwise")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.orange.opacity(0.7))
                    Label("\(character.lostCards.count)", systemImage: "xmark.circle")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.red.opacity(0.6))
                    Spacer()
                }

                // Active conditions
                let conditions = character.entityConditions.filter { !$0.expired }
                if !conditions.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(conditions, id: \.name) { cond in
                            BundledImage(ImageLoader.conditionIcon(cond.name.rawValue), size: 12, systemName: "bolt.fill")
                                .help(GameText.conditionName(cond.name))
                        }
                    }
                }

                // Summons
                let livingSummons = character.summons.filter { !$0.dead && $0.health > 0 }
                ForEach(livingSummons, id: \.id) { summon in
                    summonMiniCard(summon)
                }
            }
        }
        .padding(8)
        .background(charColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(charColor.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func summonMiniCard(_ summon: GameSummon) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Name row
            HStack(spacing: 4) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(coordinator.name(.summon(id: summon.id)))
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                if summon.state == .new {
                    Text("NEW")
                        .font(BoardTheme.font(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.6))
                        .clipShape(Capsule())
                }
            }

            // Stats row
            HStack(spacing: 6) {
                Label("\(summon.effectiveAttack)", systemImage: "burst.fill")
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                Label("\(summon.movement)", systemImage: "arrow.right")
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(.cyan.opacity(0.8))
                if summon.range > 0 {
                    Label("\(summon.range)", systemImage: "scope")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                Spacer()
                Text("\(summon.health)/\(summon.maxHealth)")
                    .font(BoardTheme.font(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.8))
            }

            // Compact HP bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hpColor(current: summon.health, max: summon.maxHealth))
                        .frame(width: geo.size.width * CGFloat(max(0, summon.health)) / CGFloat(max(1, summon.maxHealth)))
                }
            }
            .frame(height: 4)

            // Conditions
            let summonConditions = summon.entityConditions.filter { !$0.expired }
            if !summonConditions.isEmpty {
                HStack(spacing: 3) {
                    ForEach(summonConditions, id: \.name) { cond in
                        BundledImage(ImageLoader.conditionIcon(cond.name.rawValue), size: 10, systemName: "bolt.fill")
                            .help(GameText.conditionName(cond.name))
                    }
                }
            }
        }
        .padding(5)
        .background(.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.green.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Monster Info Panel

    @ViewBuilder
    private var monsterInfoPanel: some View {
        let aliveMonsters = gameManager.game.monsters.filter { !$0.off && !$0.aliveEntities.isEmpty }

        if !aliveMonsters.isEmpty {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(aliveMonsters, id: \.id) { monster in
                        monsterGroupCard(monster)
                    }
                }
                .padding(6)
            }
            .frame(width: 260)
            .frame(maxHeight: 200)
            .background(.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func monsterGroupCard(_ monster: GameMonster) -> some View {
        let monsterColor: Color = monster.isBoss ? .purple : .red
        let ability = gameManager.monsterManager.currentAbility(for: monster)

        VStack(alignment: .leading, spacing: 3) {
            // Monster name
            HStack(spacing: 4) {
                Image(systemName: monster.isBoss ? "crown.fill" : "pawprint.fill")
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(monsterColor)
                Text(coordinator.monsterTypeName(monster.name))
                    .font(BoardTheme.font(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("Lv\(monster.level)")
                    .font(BoardTheme.font(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                if ability != nil {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill")
                        .font(BoardTheme.font(size: 11))
                        .foregroundStyle(monsterColor.opacity(0.7))
                }
            }

            // Standee rows — elites first, then normals
            let sorted = monster.aliveEntities.sorted { a, b in
                if a.type != b.type { return a.type == .elite }
                return a.number < b.number
            }

            ForEach(sorted, id: \.id) { entity in
                monsterEntityRow(entity, monster: monster)
            }
        }
        .padding(6)
        .background(monsterColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(monsterColor.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            if let ability {
                previewMonsterAbility = (monster, ability)
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows this round's ability card")
    }

    @ViewBuilder
    private func monsterEntityRow(_ entity: GameMonsterEntity, monster: GameMonster) -> some View {
        let isElite = entity.type == .elite
        let typeColor: Color = isElite ? .yellow : .white

        HStack(spacing: 4) {
            // Standee number badge
            Text("\(entity.number)")
                .font(BoardTheme.font(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(isElite ? .black : .white)
                .frame(width: 14, height: 14)
                .background(isElite ? .yellow : .white.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 2))

            // HP bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hpColor(current: entity.health, max: entity.maxHealth))
                        .frame(width: geo.size.width * CGFloat(max(0, entity.health)) / CGFloat(max(1, entity.maxHealth)))
                }
            }
            .frame(height: 5)

            Text("\(entity.health)/\(entity.maxHealth)")
                .font(BoardTheme.font(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(typeColor.opacity(0.8))

            // Conditions
            let conditions = entity.entityConditions.filter { !$0.expired }
            ForEach(conditions, id: \.name) { cond in
                BundledImage(ImageLoader.conditionIcon(cond.name.rawValue), size: 10, systemName: "bolt.fill")
                    .help(GameText.conditionName(cond.name))
            }
        }
        .frame(height: 16)
    }

    // MARK: - Shared Helpers

    private func hpColor(current: Int, max: Int) -> Color {
        let ratio = Double(current) / Double(Swift.max(1, max))
        if ratio > 0.6 { return .green }
        if ratio > 0.3 { return .yellow }
        return .red
    }

    // MARK: - Battle Log

    @ViewBuilder
    private var turnLogPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "scroll.fill")
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text("Battle Log")
                    .font(BoardTheme.font(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: logExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { logExpanded.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(logExpanded ? "Collapse the battle log" : "Expand the battle log")

            if logExpanded {
            Divider().overlay(.white.opacity(0.15))

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(coordinator.turnLog.suffix(100)) { entry in
                            logEntryRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: coordinator.turnLog.count) { _, _ in
                    if let last = coordinator.turnLog.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if let last = coordinator.turnLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(minHeight: 80, maxHeight: 220)
            }
        }
        .frame(width: 260)
        .background(.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(8)
    }

    @ViewBuilder
    private func logEntryRow(_ entry: TurnLogEntry) -> some View {
        if entry.isRoundHeader {
            // Round separator
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.yellow.opacity(0.3))
                    .frame(height: 1)
                Text(entry.message)
                    .font(BoardTheme.font(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(.yellow.opacity(0.8))
                    .padding(.horizontal, 8)
                Rectangle()
                    .fill(.yellow.opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: entry.category.icon)
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(entry.category.color.opacity(0.7))
                    .frame(width: 12, alignment: .center)
                    .padding(.top, 2)

                Text(entry.message)
                    .font(BoardTheme.font(size: 11, design: .default))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Damage Mitigation Overlay

    // MARK: - Long Rest Overlay

    @ViewBuilder
    private func longRestOverlay(character: GameCharacter) -> some View {
        let charColor = Color(hex: character.color) ?? .blue
        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(
            name: deckName, edition: character.edition
        )
        let resolver = labelResolver(for: character.edition)

        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "bed.double.fill")
                            .font(BoardTheme.font(size: 36))
                            .foregroundStyle(.orange)

                        Text(Self.restTitle("Long Rest", for: character, labels: gameManager.editionStore))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(charColor)

                        Text("Heal 2 HP, recover all other discard cards to hand.\nChoose one discard card to lose permanently.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    Divider().overlay(.white.opacity(0.2))

                    // Discard cards to choose from: as wide as they are, scrolling only when they
                    // don't fit, so the panel isn't the width of the screen for two cards.
                    ViewThatFits(in: .horizontal) {
                        longRestCards(character: character, deckData: deckData, color: charColor, resolver: resolver)
                        ScrollView(.horizontal, showsIndicators: false) {
                            longRestCards(character: character, deckData: deckData, color: charColor, resolver: resolver)
                        }
                    }
                }
                .padding(24)
                .frame(width: Self.longRestWidth(cards: character.discardedCards.count))
                .fixedSize(horizontal: false, vertical: true)   // as tall as its contents
                .boardPanel()
                .padding(40)
            }
    }

    private func longRestCards(character: GameCharacter, deckData: DeckData?, color charColor: Color,
                               resolver: @escaping (String) -> String?) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(character.discardedCards.enumerated()), id: \.offset) { index, cardId in
                if let card = deckData?.abilities.first(where: { $0.cardId == cardId }) {
                    BoardAbilityCardView(
                        card: card,
                        characterColor: charColor,
                        highlight: .none,
                        width: 140,
                        height: 240,
                        labelResolver: resolver,
                        onPreview: previewAction(card: card)
                    )
                    .overlay(alignment: .bottom) {
                        Text("LOSE THIS CARD")
                            .font(BoardTheme.font(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.8))
                            .clipShape(Capsule())
                            .padding(.bottom, 8)
                    }
                    .onTapGesture {
                        coordinator.resolveLongRest(characterID: character.id, discardIndex: index)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Lose \(card.name ?? "this card")")
                }
            }
        }
        .padding(.horizontal)
    }

    /// The long rest panel's width: its cards side by side (140 pt each), at least room for the
    /// heading, at most 760 pt (more cards scroll).
    static func longRestWidth(cards: Int) -> CGFloat {
        min(760, max(440, CGFloat(cards) * 150 + 48))
    }

    /// "Spellweaver — Short Rest": the character's name as the board shows it, not their class id.
    static func restTitle(_ rest: String, for character: GameCharacter, labels: EditionDataStore) -> String {
        "\(GameText.characterName(character, labels: labels)) — \(rest)"
    }

    // MARK: - Short Rest Overlay

    @ViewBuilder
    private func shortRestOverlay(pending: BoardCoordinator.PendingShortRest, character: GameCharacter) -> some View {
        let charColor = Color(hex: character.color) ?? .blue
        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(
            name: deckName, edition: character.edition
        )
        let resolver = labelResolver(for: character.edition)

        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                            .font(BoardTheme.font(size: 36))
                            .foregroundStyle(BoardTheme.brass)

                        Text(Self.restTitle("Short Rest", for: character, labels: gameManager.editionStore))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(charColor)

                        Text("Recover all discarded cards to hand.\nRandomly lose one card.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    Divider().overlay(.white.opacity(0.2))

                    // The random card is only revealed once the player has decided to rest (p.25).
                    if pending.committed, let card = deckData?.abilities.first(where: { $0.cardId == pending.randomCardId }) {
                        VStack(spacing: 8) {
                            Text("This card will be lost:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.6))

                            BoardAbilityCardView(
                                card: card,
                                characterColor: charColor,
                                highlight: .none,
                                width: 140,
                                height: 240,
                                labelResolver: resolver,
                                onPreview: previewAction(card: card)
                            )
                            .overlay(alignment: .bottom) {
                                Text("WILL BE LOST")
                                    .font(BoardTheme.font(size: 11, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.red.opacity(0.8))
                                    .clipShape(Capsule())
                                    .padding(.bottom, 8)
                            }
                        }
                        Divider().overlay(.white.opacity(0.2))
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        if pending.committed {
                            Button {
                                coordinator.resolveShortRest()
                            } label: {
                                Label("Accept", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BoardTheme.brass)

                            Button {
                                coordinator.rerollShortRest()
                            } label: {
                                Label("Take 1 Damage to Re-pick", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(pending.rerollUsed)
                        } else {
                            Button {
                                coordinator.commitShortRest()
                            } label: {
                                Label("Short Rest", systemImage: "moon.zzz.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BoardTheme.brass)

                            Button {
                                coordinator.skipShortRest()
                            } label: {
                                Label("Skip Rest", systemImage: "forward.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }
                    }
                }
                .padding(24)
                .fixedSize()   // the size of its contents: a card and two buttons, not the screen
                .boardPanel()
                .padding(40)
            }
    }

    // MARK: - Modifier Card Popup

    @ViewBuilder
    private func modifierCardPopup(_ modifier: AttackModifier) -> some View {
        VStack(spacing: 6) {
            AttackModifierCardView(modifier: modifier, size: 80)

            Text(modifierLabel(modifier))
                .font(BoardTheme.font(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(modifierLabelColor(modifier))
        }
        .padding(12)
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(modifierLabelColor(modifier).opacity(0.5), lineWidth: 1.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 80)
    }

    private func modifierLabel(_ modifier: AttackModifier) -> String {
        if modifier.valueType == .multiply {
            return modifier.value == 0 ? "MISS" : "x\(modifier.value)"
        }
        let v = modifier.value
        if v > 0 { return "+\(v)" }
        if v < 0 { return "\(v)" }
        return "+0"
    }

    private func modifierLabelColor(_ modifier: AttackModifier) -> Color {
        if modifier.valueType == .multiply {
            return modifier.value == 0 ? .red : .yellow
        }
        if modifier.value > 0 { return .green }
        if modifier.value < 0 { return .red }
        return .white
    }

    // MARK: - Monster Ability Preview

    @ViewBuilder
    private func monsterAbilityPreviewOverlay(monster: GameMonster, ability: AbilityModel) -> some View {
        let color = monsterAbilityColor(monster)
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .onTapGesture { previewMonsterAbility = nil }
            .accessibilityLabel("Close the ability card")
            .accessibilityAddTraits(.isButton)
            .overlay {
                VStack(spacing: 14) {
                    // Header
                    HStack(spacing: 8) {
                        monsterAbilityThumb(monster)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coordinator.monsterTypeName(monster.name))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Ability Card — Round \(gameManager.game.round)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Button {
                            previewMonsterAbility = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(BoardTheme.font(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 28, height: 28)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Close")
                        .buttonStyle(.plain)
                    }

                    let deckName = monster.monsterData?.deck ?? monster.name
                    let cardIndex = gameManager.monsterManager.currentAbilityCardIndex(for: monster)
                    let imageURL = cardIndex.flatMap { ImageLoader.monsterAbilityCardURL(deckName: deckName, cardIndex: $0) }

                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                fallbackCard(ability: ability, color: color)
                            case .empty:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.06))
                                    .overlay { ProgressView().tint(.white.opacity(0.5)) }
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(maxWidth: 440, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        fallbackCard(ability: ability, color: color)
                    }
                }
                .padding(24)
                .background(.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.5), lineWidth: 1.5)
                )
                .padding(40)
            }
    }

    @ViewBuilder
    private func fallbackCard(ability: AbilityModel, color: Color) -> some View {
        BoardAbilityCardView(
            card: ability,
            characterColor: color,
            highlight: .none,
            width: 180,
            height: 290
        )
    }

    @ViewBuilder
    private func monsterAbilityThumb(_ monster: GameMonster) -> some View {
        if let img = ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name) {
            #if os(macOS)
            Image(nsImage: img)
                .resizable().scaledToFill()
                .frame(width: 36, height: 36).clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            #else
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 36, height: 36).clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            #endif
        } else {
            Image(systemName: monster.isBoss ? "crown.fill" : "pawprint.fill")
                .font(BoardTheme.font(size: 18))
                .foregroundStyle(monsterAbilityColor(monster))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.08)))
        }
    }

    private func monsterAbilityColor(_ monster: GameMonster) -> Color {
        if monster.isBoss { return .purple }
        let hue = Double(abs(monster.name.hashValue) % 60) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.65)
    }

    // MARK: - Card Image Preview

    /// Returns a closure that shows the card image preview for the given card, or nil if no cardId.
    private func previewAction(card: AbilityModel) -> (() -> Void)? {
        guard let cardId = card.cardId else { return nil }
        return { coordinator.showCardPreview(cardId: cardId) }
    }

    @ViewBuilder
    private func cardImagePreviewOverlay(cardId: Int) -> some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .onTapGesture {
                coordinator.dismissCardPreview()
            }
            .accessibilityLabel("Close the card")
            .accessibilityAddTraits(.isButton)
            .overlay {
                if let url = appResourceBundle.url(forResource: "\(cardId)", withExtension: "jpeg", subdirectory: "CardImages/gh"),
                   let data = try? Data(contentsOf: url),
                   let uiImage = crossPlatformImage(from: data) {
                    Image(decorative: uiImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 363, maxHeight: 504)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.black.opacity(0.6))
                        )
                        .shadow(color: .black.opacity(0.5), radius: 20)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                coordinator.dismissCardPreview()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(BoardTheme.font(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 26, height: 26)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Close")
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .padding(4)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(BoardTheme.font(size: 48))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Card image not available")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
    }

    /// Create a CGImage from data, cross-platform (macOS + iOS).
    private func crossPlatformImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #elseif canImport(AppKit)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    // MARK: - Helpers

    private func labelResolver(for edition: String) -> (String) -> String? {
        { gameManager.editionStore.resolveCustomText($0, edition: edition) }
    }

    private func playerTurnPhaseLabel(_ phase: PlayerTurnPhase) -> String {
        switch phase {
        case .selectTopCard: return "Select Top"
        case .executeTopAction: return "Top Action"
        case .executeBottomAction: return "Bottom Action"
        case .turnComplete: return "Done"
        }
    }
}

// MARK: - Discard Card Picker

/// Lets the player pick exactly 2 discard cards to lose for damage mitigation.
struct DiscardCardPicker: View {
    let character: GameCharacter
    let deckData: DeckData?
    let characterColor: Color
    let onConfirm: ([Int]) -> Void
    var labelResolver: ((String) -> String?)? = nil
    var onPreviewCard: ((AbilityModel) -> (() -> Void)?)? = nil

    @State private var selectedIndices: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(BoardTheme.font(size: 11))
                    .foregroundStyle(.cyan)
                Text("Lose 2 discard cards to negate all damage (\(selectedIndices.count)/2 selected)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)

                if selectedIndices.count == 2 {
                    Button("Confirm") {
                        onConfirm(Array(selectedIndices))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(character.discardedCards.enumerated()), id: \.offset) { index, cardId in
                        let isSelected = selectedIndices.contains(index)

                        if let card = deckData?.abilities.first(where: { $0.cardId == cardId }) {
                            BoardAbilityCardView(
                                card: card,
                                characterColor: characterColor,
                                highlight: .none,
                                width: 120,
                                height: 200,
                                labelResolver: labelResolver,
                                onPreview: onPreviewCard?(card)
                            )
                            .overlay(alignment: .bottom) {
                                if isSelected {
                                    Text("SELECTED")
                                        .font(BoardTheme.font(size: 11, weight: .heavy))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(.cyan.opacity(0.8))
                                        .clipShape(Capsule())
                                        .padding(.bottom, 6)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? .cyan : .clear, lineWidth: 2.5)
                            )
                            .opacity(isSelected ? 1.0 : 0.7)
                            .onTapGesture {
                                if isSelected {
                                    selectedIndices.remove(index)
                                } else if selectedIndices.count < 2 {
                                    selectedIndices.insert(index)
                                }
                            }
                            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityLabel(card.name ?? "Card")
                        }
                    }
                }
            }
        }
    }
}

private extension View {
    /// Report this view's frame (global, y down) as it changes, and an empty frame once it's gone.
    func reportFrame(_ report: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report($0) }
            .onDisappear { report(.zero) }
    }
}
