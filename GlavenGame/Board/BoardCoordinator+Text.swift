import Foundation
import SpriteKit

/// The board's headings, in the words the HUD shows. Kept out of the view so tests can check
/// them for every phase.
extension BoardCoordinator {

    /// The name of a figure in turn order: "Brute", "Bandit Guard".
    func figureName(_ figure: AnyFigure) -> String {
        switch figure {
        case .character(let character): return characterName(character.id)
        case .monster(let monster): return monsterTypeName(monster.name)
        case .objective(let objective): return objective.name.isEmpty ? "Objective" : objective.name
        }
    }

    /// The figure whose turn it is, during play.
    var currentTurnEntry: TurnOrderEntry? {
        guard boardPhase == .execution, turnOrder.indices.contains(currentTurnIndex) else { return nil }
        return turnOrder[currentTurnIndex]
    }

    /// The HUD's main heading: what is happening on the board right now.
    var phaseTitle: String {
        switch boardPhase {
        case .setup: return "Place Your Characters"
        case .cardSelection: return "Choose Cards"
        case .execution:
            guard let entry = currentTurnEntry else { return "Round in Progress" }
            return "\(figureName(entry.figure))\u{2019}s Turn \u{00B7} \(Int(entry.initiative.rounded(.up)))"
        case .roomReveal: return "New Room Revealed"
        case .scenarioEnd: return scenarioResult == .defeat ? "Scenario Failed" : "Scenario Complete"
        }
    }

    /// One figure in the turn-order rail.
    struct TurnRailEntry: Identifiable, Equatable {
        enum State: Equatable { case done, current, upcoming }
        enum Kind: Equatable { case character(edition: String, name: String), monster(edition: String, name: String), objective }
        let id: String
        let name: String
        let initiative: Int
        let state: State
        let kind: Kind
        /// A long-resting character acts at initiative 99.
        let isLongRest: Bool
        /// A line under the name: "Ready", "Choosing…", "2 of 3 acting".
        var detail: String? = nil
        /// Whether the initiative is known yet (not while cards are being chosen).
        var showsInitiative = true
    }

    /// The top bar's heading: the round, and what is happening in it.
    var hudHeading: (title: String, subtitle: String) {
        let round = displayedRound.map { "Round \($0)" }
        switch boardPhase {
        case .setup: return ("Setup", "Place your characters")
        case .cardSelection: return (round ?? "Round 1", "Choose cards")
        case .execution:
            let subtitle = currentTurnEntry.map { "\(figureName($0.figure))\u{2019}s turn" } ?? "Round in progress"
            return (round ?? "Round", subtitle)
        case .roomReveal: return (round ?? "Round", "New room revealed")
        case .scenarioEnd: return (round ?? "Round", scenarioResult == .defeat ? "Scenario failed" : "Scenario complete")
        }
    }

    /// The rail while cards are being chosen: who is ready, who is choosing, and the monsters,
    /// whose cards are drawn when everyone's are revealed. No initiatives yet.
    var selectionRail: [TurnRailEntry] {
        guard boardPhase == .cardSelection, let game = gameManager?.game else { return [] }
        let party = game.activeCharacters.filter { !$0.exhausted && !$0.absent }
        var entries = party.map { character -> TurnRailEntry in
            let done = cardSelectionsComplete.contains(character.id)
            let current = cardSelectingCharacterID == character.id
            return TurnRailEntry(id: character.id, name: characterName(character.id), initiative: 0,
                                 state: done ? .done : (current ? .current : .upcoming),
                                 kind: .character(edition: character.edition, name: character.name),
                                 isLongRest: done && character.longRest,
                                 detail: done ? (character.longRest ? "Long rest" : "Ready")
                                     : (current ? "Choosing\u{2026}" : "Waiting"),
                                 showsInitiative: false)
        }
        for monster in game.monsters where !monster.off && !monster.aliveEntities.isEmpty && !isPlayerSideMonster(monster) {
            entries.append(TurnRailEntry(id: "monster-\(monster.name)", name: monsterTypeName(monster.name) + "s",
                                         initiative: 0, state: .upcoming,
                                         kind: .monster(edition: monster.edition, name: monster.name),
                                         isLongRest: false, detail: "Draw at reveal", showsInitiative: false))
        }
        return entries
    }

    private func isPlayerSideMonster(_ monster: GameMonster) -> Bool { monster.isAlly || monster.isAllied }

    /// "2 of 3 acting" for the monster type whose turn it is: standees act elites first, then by number.
    private func actingDetail(_ monster: GameMonster) -> String? {
        guard case .monster(let name, let standee)? = actingPiece, name == monster.name else { return nil }
        let order = monster.aliveEntities.sorted { ($0.type == .elite ? 0 : 1, $0.number) < ($1.type == .elite ? 0 : 1, $1.number) }
        guard order.count > 1, let index = order.firstIndex(where: { $0.number == standee }) else { return nil }
        return "\(index + 1) of \(order.count) acting"
    }

    /// The round's turn order for the HUD rail: who has acted, who is acting, who is next.
    var turnRail: [TurnRailEntry] {
        guard boardPhase == .execution || boardPhase == .roomReveal else { return [] }
        return turnOrder.enumerated().map { index, entry in
            let state: TurnRailEntry.State = index == currentTurnIndex ? .current
                : (entry.completed || index < currentTurnIndex ? .done : .upcoming)
            let kind: TurnRailEntry.Kind
            var longRest = false
            var detail: String?
            switch entry.figure {
            case .character(let c):
                kind = .character(edition: c.edition, name: c.name)
                longRest = c.longRest
            case .monster(let m):
                kind = .monster(edition: m.edition, name: m.name)
                if state == .current { detail = actingDetail(m) }
            case .objective: kind = .objective
            }
            return TurnRailEntry(id: entry.id.uuidString, name: figureName(entry.figure),
                                 initiative: Int(entry.initiative.rounded(.up)), state: state, kind: kind,
                                 isLongRest: longRest, detail: detail)
        }
    }

    /// What the player is being asked to do on the board, for the instruction banner.
    struct Instruction: Equatable {
        /// The ability being resolved: "Attack 3, Range 2", "Move 4".
        let title: String
        /// What to tap: "Tap a ringed enemy to attack".
        let detail: String
        /// Whether "Skip this action" applies (the player's own ability is waiting for a choice).
        let canSkip: Bool
        /// Whether the choice can be cancelled, putting the ability back to be performed again.
        var canCancel = false
        /// What the attack will do to each target, nearest first ("Bandit Guard 1: 2 − 1 shield = 1 + draw").
        var previews: [String] = []
    }

    /// The banner for the current interaction, with Cancel offered while the action can still
    /// be taken back.
    static let pausedDetail = "Paused \u{2014} Resume lets the turns go on"

    func instruction(for mode: InteractionMode) -> Instruction? {
        guard var instruction = baseInstruction(for: mode) else { return nil }
        // Not while a card is shown full size on top: Escape (Cancel's key) is for closing that.
        instruction.canCancel = (activePlayerTurn?.canCancelChoice ?? false) && previewCardId == nil
        if case .selectingAttackTarget(let attacker, _, let targets) = mode, activePlayerTurn?.pendingAreaPattern == nil {
            instruction.previews = Array(attackPreviewLines(attacker: attacker, targets: targets).prefix(4))
        }
        return instruction
    }

    /// Every mode has wording (the switch has no default), so a new kind of choice can't appear
    /// on the board without telling the player.
    private func baseInstruction(for mode: InteractionMode) -> Instruction? {
        let ownTurn = activePlayerTurn != nil
        switch mode {
        case .idle:
            return nil
        case .placingCharacter(let id):
            return Instruction(title: "Place \(characterName(id))", detail: "Tap a highlighted starting hex",
                               canSkip: false)
        case .selectingMove(_, let range, _, let teleport, let moveMode):
            let verb = teleport ? "Teleport" : (moveMode == .jump ? "Jump" : (moveMode == .fly ? "Fly" : "Move"))
            return Instruction(title: "\(verb) \(range)", detail: "Tap a highlighted hex to move there",
                               canSkip: ownTurn)
        case .selectingAttackTarget(_, let range, _):
            let value = activePlayerTurn?.currentAttackValue()
            let title = value.map { "Attack \($0), Range \(range)" } ?? "Attack, Range \(range)"
            return Instruction(title: title, detail: "Tap a highlighted enemy to attack", canSkip: ownTurn)
        case .selectingMultiAttackTargets(_, let range, _, let count, let selected):
            let value = activePlayerTurn?.currentAttackValue()
            let title = value.map { "Attack \($0), Range \(range)" } ?? "Attack, Range \(range)"
            return Instruction(title: title,
                               detail: "Tap up to \(count) enemies, then Confirm (\(selected.count) of \(count) chosen)",
                               canSkip: ownTurn)
        case .choosingPerformer(_, let action, let candidates):
            let enemies = candidates.contains { if case .monster = $0 { return true }; return false }
            return Instruction(title: GameText.actionTitle(action),
                               detail: enemies ? "Tap the enemy to control" : "Tap the ally who performs it", canSkip: ownTurn)
        case .placingToken(_, let token, let remaining, _):
            if token == .destroyObstacle {
                return Instruction(title: "Destroy an obstacle", detail: "Tap an obstacle next to you", canSkip: ownTurn)
            }
            return Instruction(title: "Place \(token.name)",
                               detail: remaining > 1 ? "Tap an empty hex next to you (\(remaining) to place)"
                                                     : "Tap an empty hex next to you", canSkip: false)
        case .placingSummon(let summonID, _, _):
            return Instruction(title: "Place \(name(.summon(id: summonID)))",
                               detail: "Tap a highlighted hex next to your character", canSkip: false)
        case .selectingPushPullHex(let target, _, _, let remaining, let isPush):
            return Instruction(title: "\(isPush ? "Push" : "Pull") \(name(target))",
                               detail: "Tap the hex to \(isPush ? "push" : "pull") them into (\(remaining) left)",
                               canSkip: false)
        case .selectingConditionTarget(_, let condition, _):
            return Instruction(title: GameText.conditionName(condition),
                               detail: "Tap a highlighted figure to apply it", canSkip: ownTurn)
        case .selectingHealTarget(_, let value, _):
            return Instruction(title: "Heal \(value)", detail: "Tap a highlighted ally to heal", canSkip: ownTurn)
        case .selectingForcedMoveTarget(_, let steps, let isPush, _):
            return Instruction(title: "\(isPush ? "Push" : "Pull") \(steps)",
                               detail: "Tap a highlighted enemy to \(isPush ? "push" : "pull")", canSkip: ownTurn)
        case .watchingMonsterTurn:
            // On a character's turn it's their summons acting (before them); a prompt of the
            // character's own (a rest) has its own panel.
            if case .character(let character) = currentTurnEntry?.figure {
                guard pendingLongRest == nil, pendingShortRest == nil else { return nil }
                return Instruction(title: "\(characterName(character.id))\u{2019}s summons are acting",
                                   detail: isPaused ? Self.pausedDetail : "Summons take their turns on their own",
                                   canSkip: false)
            }
            let actor = currentTurnEntry.map { figureName($0.figure) } ?? "The monsters"
            return Instruction(title: "\(actor) \(currentTurnEntry == nil ? "are" : "is") acting",
                               detail: isPaused ? Self.pausedDetail
                                   : "Monsters and summons take their turns on their own", canSkip: false)
        }
    }

    /// The round to show in the HUD, or nil before the first round. During card selection this is
    /// the round the cards are being chosen for (the game's round counter moves on when play starts).
    var displayedRound: Int? {
        guard let round = gameManager?.game.round else { return nil }
        switch boardPhase {
        case .setup: return nil
        case .cardSelection: return round + 1
        case .execution, .roomReveal, .scenarioEnd: return max(round, 1)
        }
    }
}

// MARK: - Tokens

extension BoardCoordinator {

    /// How a figure's token looks: portrait, rim colour for its side and rank, standee badge.
    func pieceAppearance(_ piece: PieceID) -> PieceAppearance {
        var appearance = PieceAppearance.fallback(for: piece)
        appearance.isPlayerSide = isPlayerSide(piece)
        appearance.name = name(piece)
        guard let game = gameManager?.game else { return appearance }
        switch piece {
        case .character(let id):
            guard let character = game.characters.first(where: { $0.id == id }) else { break }
            appearance.portrait = ImageLoader.characterThumbnail(edition: character.edition, name: character.name)
            appearance.portraitKey = "character \(character.edition) \(character.name)"
            appearance.rimColor = SKColor(hex: character.color) ?? appearance.rimColor
            appearance.initials = String(GameText.characterName(character).prefix(2)).uppercased()
        case .monster(let name, let standee):
            guard let monster = game.monsters.first(where: { $0.name == name }) else { break }
            appearance.portrait = ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name)
            appearance.portraitKey = "monster \(monster.edition) \(monster.name)"
            switch monsterEntity(name: name, standee: standee)?.type ?? .normal {
            case .normal: appearance.rank = .normal; appearance.rimColor = PieceAppearance.normalRim
            case .elite: appearance.rank = .elite; appearance.rimColor = PieceAppearance.eliteRim
            case .boss: appearance.rank = .boss; appearance.rimColor = PieceAppearance.bossRim
            }
        case .summon:
            if let owner = summonOwner(of: piece) {
                appearance.rimColor = SKColor(hex: owner.color) ?? appearance.rimColor
            }
            let words = name(piece).split(separator: " ")
            appearance.initials = words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        case .objective:
            break
        }
        return appearance
    }

    /// A figure's health and active conditions, for its token.
    func pieceStatus(_ piece: PieceID) -> PieceStatus? {
        guard let entity = entity(for: piece) else { return nil }
        let active = Set(entity.entityConditions.filter { !$0.expired }.map(\.name))
        let tokens = dooms(on: piece).compactMap { doom -> PieceStatus.CharacterToken? in
            guard let owner = gameManager?.game.characters.first(where: { $0.id == doom.characterID }) else { return nil }
            return PieceStatus.CharacterToken(edition: owner.edition, className: owner.name,
                                              name: GameText.characterName(owner, labels: gameManager?.editionStore), color: owner.color)
        }
        return PieceStatus(health: entity.health, maxHealth: entity.maxHealth,
                           conditions: ConditionName.allCases.filter(active.contains), tokens: tokens)
    }

    /// Mark whose turn it is: a ring on the board, and `actingPiece` for anything that asks.
    func setActing(_ piece: PieceID?) {
        actingPiece = piece
        boardScene?.setActingPiece(piece)
        if case .character = piece { boardScene?.play(.turn) }
    }

    /// Bring every token on the board up to date (health, conditions, invisibility).
    func syncPieceVisuals() {
        boardScene?.refreshAllStatuses()
        refreshInvisibility()
    }
}

// MARK: - Damage choice

extension BoardCoordinator {

    /// What taking the pending damage would do to the character.
    struct DamageOutcome: Equatable {
        let healthBefore: Int
        let healthAfter: Int
        /// Taking it drops the character to 0 hit points: they are exhausted.
        let exhausts: Bool
    }

    func damageOutcome(_ pending: PendingDamage) -> DamageOutcome? {
        guard let character = gameManager?.game.characters.first(where: { $0.id == pending.characterID }) else { return nil }
        let after = max(0, character.health - pending.damage)
        return DamageOutcome(healthBefore: character.health, healthAfter: after, exhausts: after == 0)
    }
}
