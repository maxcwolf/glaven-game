import SwiftUI
import SpriteKit

/// SwiftUI wrapper for the SpriteKit game board with HUD overlays.
struct BoardView: View {
    @Environment(GameManager.self) private var gameManager
    @Bindable var coordinator: BoardCoordinator

    var body: some View {
        ZStack {
            // SpriteKit board
            if let scene = coordinator.boardScene {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
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
                HStack(alignment: .top, spacing: 0) {
                    // Left: character info cards
                    characterInfoPanel
                    Spacer()
                    // Right: monster info + battle log
                    VStack(spacing: 4) {
                        monsterInfoPanel
                        turnLogPanel
                    }
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
                damageMitigationOverlay(pending: pending, character: character)
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

            // Modifier card popup
            if coordinator.showModifierCard, let mod = coordinator.lastDrawnModifier {
                modifierCardPopup(mod)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: coordinator.showModifierCard)
            }

            // Full-size card image preview overlay
            if let cardId = coordinator.previewCardId {
                cardImagePreviewOverlay(cardId: cardId)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: coordinator.previewCardId)
            }

            // Scenario end overlay
            if let result = coordinator.scenarioResult {
                scenarioEndOverlay(result: result)
            }
        }
    }

    // MARK: - Top HUD

    @ViewBuilder
    private var boardHUD: some View {
        HStack(spacing: 16) {
            // Phase indicator
            Text(phaseLabel)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())

            // Current figure info
            if coordinator.boardPhase == .execution,
               coordinator.currentTurnIndex >= 0,
               coordinator.currentTurnIndex < coordinator.turnOrder.count {
                let entry = coordinator.turnOrder[coordinator.currentTurnIndex]
                Text("Turn: \(figureName(entry.figure)) (\(Int(entry.initiative)))")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())
            }

            Spacer()

            // Element board
            ElementBoardView()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Round counter
            Text("Round \(gameManager.game.round)")
                .font(.subheadline.monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6))
                .clipShape(Capsule())

            // Exit button
            Button {
                coordinator.exitBoard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Exit")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.red.opacity(0.6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var phaseLabel: String {
        switch coordinator.boardPhase {
        case .setup: return "Place Characters"
        case .cardSelection: return "Select Cards"
        case .execution: return "Turn in Progress"
        case .roomReveal: return "Room Revealed"
        case .scenarioEnd: return "Scenario Complete"
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if coordinator.boardPhase == .setup {
                setupBottomBar
            } else if coordinator.boardPhase == .execution {
                executionBottomBar
            } else {
                Spacer()
            }
        }
        .padding()
        .background(.black.opacity(0.4))
    }

    @ViewBuilder
    private var setupBottomBar: some View {
        let allPlaced = gameManager.game.characters.allSatisfy { char in
            coordinator.boardState.piecePositions.keys.contains(.character(char.id))
        }

        VStack(spacing: 10) {
            // Instruction
            if !allPlaced {
                Label("Tap a character, then tap a starting hex to place them", systemImage: "hand.tap.fill")
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

                            Text(character.title.isEmpty ? character.name.replacingOccurrences(of: "-", with: " ").capitalized : character.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(placed ? .white.opacity(0.4) : .white)

                            if placed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
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
                    .disabled(placed)
                }

                Spacer()

                // Begin scenario button
                if allPlaced && !gameManager.game.characters.isEmpty {
                    Button {
                        coordinator.finishSetup()
                    } label: {
                        Label("Begin Scenario", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold))
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
                // Active card display
                activeCardDisplay(playerTurn: playerTurn)

                // Action buttons
                VStack(alignment: .leading, spacing: 8) {
                    if playerTurn.phase == .executeTopAction || playerTurn.phase == .executeBottomAction {
                        let actions = playerTurn.phase == .executeTopAction ? playerTurn.topActions : playerTurn.bottomActions
                        let idx = playerTurn.currentActionIndex

                        if idx < actions.count {
                            let action = actions[idx]
                            Button {
                                playerTurn.executeCurrentAction()
                            } label: {
                                Label("Execute: \(action.type.rawValue.capitalized)", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        } else {
                            Button {
                                playerTurn.executeCurrentAction()
                            } label: {
                                Label("Next Phase", systemImage: "forward.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.gray)
                        }

                        HStack(spacing: 8) {
                            let defaultLabel = playerTurn.phase == .executeTopAction ? "Default: Attack 2" : "Default: Move 2"
                            Button(defaultLabel) {
                                playerTurn.useDefaultAction()
                            }
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                            .controlSize(.small)

                            Button("Skip Half") {
                                playerTurn.skipRemainingActions()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .controlSize(.small)
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
                        Text("Selecting targets: \(selected.count)/\(targetCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
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

                Spacer()
            }
        } else if case .placingSummon(_, _, _) = coordinator.interactionMode,
                  let pending = coordinator.pendingSummonPlacement {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Place \(pending.summonName)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.green)
                    Text("Tap a green hex")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
        } else if case .watchingMonsterTurn = coordinator.interactionMode {
            Text("Monsters acting...")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        } else {
            Spacer()
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
            let highlight: CardHighlight = isTop ? .top : .bottom
            let badge = isTop ? "TOP — Init \(card.initiative)" : "BOTTOM"
            let badgeColor: Color = isTop ? .yellow : .cyan

            BoardAbilityCardView(
                card: card,
                characterColor: activeCharacterColor,
                highlight: highlight,
                width: 140,
                height: 240,
                roleBadge: badge,
                roleBadgeColor: badgeColor,
                labelResolver: resolver,
                onPreview: previewAction(card: card)
            )
            .padding(.leading, 8)
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
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(characters, id: \.id) { character in
                        characterCard(character)
                    }
                }
                .padding(6)
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
                Text(character.title.isEmpty ? character.name.replacingOccurrences(of: "-", with: " ").capitalized : character.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isExhausted ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                Spacer()
                if isExhausted {
                    Text("OUT")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.red)
                }
            }

            if !isExhausted {
                // HP bar
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
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
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Stats row: XP, Hand, Discard
                HStack(spacing: 8) {
                    Label("\(character.experience)", systemImage: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow.opacity(0.8))
                    Label("\(character.handCards.count)", systemImage: "hand.raised.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.cyan.opacity(0.8))
                    Label("\(character.discardedCards.count)", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange.opacity(0.7))
                    Label("\(character.lostCards.count)", systemImage: "xmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.6))
                    Spacer()
                }

                // Active conditions
                let conditions = character.entityConditions.filter { !$0.expired }
                if !conditions.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(conditions, id: \.name) { cond in
                            BundledImage(ImageLoader.conditionIcon(cond.name.rawValue), size: 12, systemName: "bolt.fill")
                                .help(cond.name.rawValue.capitalized)
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
                Text(summon.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                Spacer()
                if summon.state == .new {
                    Text("NEW")
                        .font(.system(size: 7, weight: .heavy))
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
                    .font(.system(size: 8))
                    .foregroundStyle(.red.opacity(0.8))
                Label("\(summon.movement)", systemImage: "arrow.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.cyan.opacity(0.8))
                if summon.range > 0 {
                    Label("\(summon.range)", systemImage: "scope")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.8))
                }
                Spacer()
                Text("\(summon.health)/\(summon.maxHealth)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
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
                            .help(cond.name.rawValue.capitalized)
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

        VStack(alignment: .leading, spacing: 3) {
            // Monster name
            HStack(spacing: 4) {
                Image(systemName: monster.isBoss ? "crown.fill" : "pawprint.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(monsterColor)
                Text(monster.name.replacingOccurrences(of: "-", with: " ").capitalized)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("Lv\(monster.level)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
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
    }

    @ViewBuilder
    private func monsterEntityRow(_ entity: GameMonsterEntity, monster: GameMonster) -> some View {
        let isElite = entity.type == .elite
        let typeColor: Color = isElite ? .yellow : .white

        HStack(spacing: 4) {
            // Standee number badge
            Text("\(entity.number)")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
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
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(typeColor.opacity(0.8))

            // Conditions
            let conditions = entity.entityConditions.filter { !$0.expired }
            ForEach(conditions, id: \.name) { cond in
                BundledImage(ImageLoader.conditionIcon(cond.name.rawValue), size: 10, systemName: "bolt.fill")
                    .help(cond.name.rawValue.capitalized)
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
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow.opacity(0.8))
                Text("Battle Log")
                    .font(.system(size: 12, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(coordinator.turnLog.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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
                    .font(.system(size: 10, weight: .bold, design: .serif))
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
                    .font(.system(size: 8))
                    .foregroundStyle(entry.category.color.opacity(0.7))
                    .frame(width: 12, alignment: .center)
                    .padding(.top, 2)

                Text(entry.message)
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Scenario End Overlay

    @ViewBuilder
    private func scenarioEndOverlay(result: BoardCoordinator.ScenarioResult) -> some View {
        Color.black.opacity(0.6)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: result == .victory ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(result == .victory ? .yellow : .red)

                    Text(result == .victory ? "Victory!" : "Defeat")
                        .font(.system(size: 36, weight: .bold, design: .serif))
                        .foregroundStyle(.white)

                    Text("Round \(gameManager.game.round)")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))

                    Button(result == .victory ? "Complete Scenario" : "Return to Menu") {
                        coordinator.confirmScenarioEnd()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(result == .victory ? .green : .orange)
                    .controlSize(.large)
                }
                .padding(40)
                .background(.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
    }

    // MARK: - Damage Mitigation Overlay

    @ViewBuilder
    private func damageMitigationOverlay(pending: BoardCoordinator.PendingDamage, character: GameCharacter) -> some View {
        let charColor = Color(hex: character.color) ?? .blue
        let deckName = character.characterData?.deck ?? character.name
        let deckData = gameManager.editionStore.deckData(
            name: deckName, edition: character.edition
        )
        let resolver = labelResolver(for: character.edition)

        Color.black.opacity(0.5)
            .ignoresSafeArea()
            .overlay {
                HStack(spacing: 0) {
                    // Left side: damage info + take damage button
                    VStack(spacing: 16) {
                        // Header
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.red)

                            Text("\(character.title.isEmpty ? character.name : character.title)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(charColor)

                            Text("takes \(pending.damage) damage from \(pending.sourceDescription)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Divider().overlay(.white.opacity(0.2))

                        // Take damage button
                        Button {
                            coordinator.resolvePendingDamage(choice: .takeDamage)
                        } label: {
                            HStack {
                                Image(systemName: "heart.slash.fill")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading) {
                                    Text("Take \(pending.damage) Damage")
                                        .fontWeight(.medium)
                                    Text("HP: \(character.health) → \(max(0, character.health - pending.damage))")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.red.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .frame(width: 260)
                    .padding(20)

                    Divider().overlay(.white.opacity(0.15))

                    // Right side: card choices with full card previews
                    VStack(alignment: .leading, spacing: 12) {
                        // Lose 1 hand card
                        if !character.handCards.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.yellow)
                                    Text("Lose 1 hand card to negate all damage")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.yellow)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(character.handCards.enumerated()), id: \.offset) { index, cardId in
                                            if let card = deckData?.abilities.first(where: { $0.cardId == cardId }) {
                                                BoardAbilityCardView(
                                                    card: card,
                                                    characterColor: charColor,
                                                    highlight: .none,
                                                    width: 120,
                                                    height: 200,
                                                    labelResolver: resolver,
                                                    onPreview: previewAction(card: card)
                                                )
                                                .overlay(alignment: .bottom) {
                                                    Text("LOSE")
                                                        .font(.system(size: 10, weight: .heavy))
                                                        .foregroundStyle(.white)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 4)
                                                        .background(.red.opacity(0.8))
                                                        .clipShape(Capsule())
                                                        .padding(.bottom, 6)
                                                }
                                                .onTapGesture {
                                                    coordinator.resolvePendingDamage(choice: .loseHandCard(cardIndex: index))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Lose 2 discard cards
                        if character.discardedCards.count >= 2 {
                            DiscardCardPicker(
                                character: character,
                                deckData: deckData,
                                characterColor: charColor,
                                onConfirm: { indices in
                                    coordinator.resolvePendingDamage(choice: .loseDiscardCards(indices: indices))
                                },
                                labelResolver: resolver,
                                onPreviewCard: { card in self.previewAction(card: card) }
                            )
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 420)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.red.opacity(0.4), lineWidth: 1)
                )
                .padding(40)
            }
    }

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
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)

                        Text("\(character.title.isEmpty ? character.name : character.title) — Long Rest")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(charColor)

                        Text("Heal 2 HP, recover all other discard cards to hand.\nChoose one discard card to lose permanently.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    Divider().overlay(.white.opacity(0.2))

                    // Discard cards to choose from
                    ScrollView(.horizontal, showsIndicators: false) {
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
                                            .font(.system(size: 9, weight: .heavy))
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
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(24)
                .frame(maxHeight: 420)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.orange.opacity(0.4), lineWidth: 1)
                )
                .padding(40)
            }
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
                            .font(.system(size: 36))
                            .foregroundStyle(.cyan)

                        Text("\(character.title.isEmpty ? character.name : character.title) — Short Rest")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(charColor)

                        Text("Recover all discarded cards to hand.\nRandomly lose one card.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    Divider().overlay(.white.opacity(0.2))

                    // Show the randomly selected card
                    if let card = deckData?.abilities.first(where: { $0.cardId == pending.randomCardId }) {
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
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.red.opacity(0.8))
                                    .clipShape(Capsule())
                                    .padding(.bottom, 8)
                            }
                        }
                    }

                    Divider().overlay(.white.opacity(0.2))

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            coordinator.resolveShortRest()
                        } label: {
                            Label("Accept", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            coordinator.rerollShortRest()
                        } label: {
                            Label("Take 1 Damage to Re-pick", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(pending.rerollUsed)

                        Button {
                            coordinator.skipShortRest()
                        } label: {
                            Label("Skip Rest", systemImage: "forward.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.gray)
                    }
                }
                .padding(24)
                .frame(maxHeight: 500)
                .background(.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.cyan.opacity(0.4), lineWidth: 1)
                )
                .padding(40)
            }
    }

    // MARK: - Modifier Card Popup

    @ViewBuilder
    private func modifierCardPopup(_ modifier: AttackModifier) -> some View {
        VStack(spacing: 6) {
            AttackModifierCardView(modifier: modifier, size: 80)

            Text(modifierLabel(modifier))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
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
            .overlay {
                if let url = appResourceBundle.url(forResource: "\(cardId)", withExtension: "jpeg", subdirectory: "CardImages/gh"),
                   let data = try? Data(contentsOf: url),
                   let uiImage = crossPlatformImage(from: data) {
                    Image(decorative: uiImage, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 363, maxHeight: 504)
                        .shadow(color: .black.opacity(0.5), radius: 20)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                coordinator.dismissCardPreview()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 26, height: 26)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.3), radius: 4)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 13, y: -13)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 48))
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

    private func figureName(_ figure: AnyFigure) -> String {
        switch figure {
        case .character(let c):
            return c.title.isEmpty ? c.name : c.title
        case .monster(let m):
            return m.name.replacingOccurrences(of: "-", with: " ").capitalized
        case .objective(let o):
            return o.name
        }
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
private struct DiscardCardPicker: View {
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
                    .font(.system(size: 10))
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
                                        .font(.system(size: 9, weight: .heavy))
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
                        }
                    }
                }
            }
        }
    }
}
