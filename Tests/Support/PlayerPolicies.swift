import Foundation
@testable import GlavenGameLib

/// The players' decisions in a simulated scenario. Every method has a simple default (the
/// scripted behaviour: first cards, first options, never negate damage, always rest);
/// `TacticalPolicy` plays to win.
@MainActor
protocol PlayerPolicy {
    /// Where a character starts, among the free starting hexes (in map order).
    func startingHex(for character: GameCharacter, options: [HexCoord], sim: ScenarioSimulator) -> HexCoord
    /// Two cards to play, the leading card (whose initiative counts) first; nil to long rest.
    func chooseCards(for character: GameCharacter, hand: [AbilityModel],
                     sim: ScenarioSimulator) -> (leading: AbilityModel, other: AbilityModel)?
    /// Before the first action: swap which card gives the top half, or play the bottom half first.
    func prepareTurn(_ turn: PlayerTurnController, sim: ScenarioSimulator)
    /// At the start of each half: play the default Attack 2 / Move 2 instead of the printed half.
    func useDefaultAction(_ turn: PlayerTurnController, sim: ScenarioSimulator) -> Bool
    /// Destination of a move (nil skips the rest of the half).
    func moveDestination(for piece: PieceID, options: Set<HexCoord>, mode: MoveMode, sim: ScenarioSimulator) -> HexCoord?
    /// Next attack target (nil: no more targets).
    func attackTarget(for attacker: PieceID, options: Set<PieceID>, chosen: [PieceID], sim: ScenarioSimulator) -> PieceID?
    func conditionTarget(for piece: PieceID, condition: ConditionName, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID?
    func healTarget(for healer: PieceID, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID
    func summonHex(for owner: String, options: Set<HexCoord>, sim: ScenarioSimulator) -> HexCoord?
    /// Where a pushed or pulled figure goes next.
    func forcedMoveHex(for target: PieceID, from origin: HexCoord, options: Set<HexCoord>, isPush: Bool,
                       sim: ScenarioSimulator) -> HexCoord?
    func forcedMoveTarget(for piece: PieceID, options: Set<PieceID>, isPush: Bool, sim: ScenarioSimulator) -> PieceID?
    /// Lose cards to negate incoming damage (GH p.22)?
    func negateDamage(_ damage: Int, character: GameCharacter, sim: ScenarioSimulator) -> BoardCoordinator.DamageMitigationChoice
    func shortRest(character: GameCharacter, cardToLose: Int, sim: ScenarioSimulator) -> ShortRestDecision
    /// Index in the discard pile of the card lost to a long rest.
    func longRestLoss(character: GameCharacter, sim: ScenarioSimulator) -> Int
}

extension PlayerPolicy {
    func startingHex(for character: GameCharacter, options: [HexCoord], sim: ScenarioSimulator) -> HexCoord {
        options[0]
    }

    func chooseCards(for character: GameCharacter, hand: [AbilityModel],
                     sim: ScenarioSimulator) -> (leading: AbilityModel, other: AbilityModel)? {
        hand.count >= 2 ? (hand[0], hand[1]) : nil
    }

    func prepareTurn(_ turn: PlayerTurnController, sim: ScenarioSimulator) {}

    func useDefaultAction(_ turn: PlayerTurnController, sim: ScenarioSimulator) -> Bool { false }

    /// Head for the nearest enemy, or a closed door once the room is clear.
    func moveDestination(for piece: PieceID, options: Set<HexCoord>, mode: MoveMode, sim: ScenarioSimulator) -> HexCoord? {
        var goals = sim.enemies(of: piece).compactMap { sim.position($0) }
        if goals.isEmpty {
            goals = sim.coord.boardState.doors.filter { !$0.isOpen }.map(\.coord)
        }
        return options.min { a, b in
            let da = goals.map { a.distance(to: $0) }.min() ?? 0
            let db = goals.map { b.distance(to: $0) }.min() ?? 0
            return da == db ? a < b : da < db
        }
    }

    func attackTarget(for attacker: PieceID, options: Set<PieceID>, chosen: [PieceID], sim: ScenarioSimulator) -> PieceID? {
        options.sorted().first
    }

    func conditionTarget(for piece: PieceID, condition: ConditionName, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID? {
        options.sorted().first
    }

    func healTarget(for healer: PieceID, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID {
        healer
    }

    func summonHex(for owner: String, options: Set<HexCoord>, sim: ScenarioSimulator) -> HexCoord? {
        options.min()
    }

    func forcedMoveHex(for target: PieceID, from origin: HexCoord, options: Set<HexCoord>, isPush: Bool,
                       sim: ScenarioSimulator) -> HexCoord? {
        options.min()
    }

    func forcedMoveTarget(for piece: PieceID, options: Set<PieceID>, isPush: Bool, sim: ScenarioSimulator) -> PieceID? {
        options.sorted().first
    }

    func negateDamage(_ damage: Int, character: GameCharacter, sim: ScenarioSimulator) -> BoardCoordinator.DamageMitigationChoice {
        .takeDamage
    }

    func shortRest(character: GameCharacter, cardToLose: Int, sim: ScenarioSimulator) -> ShortRestDecision {
        .rest
    }

    func longRestLoss(character: GameCharacter, sim: ScenarioSimulator) -> Int { 0 }
}

/// The original scripted party: first two cards, first options, always rest.
struct ScriptedPolicy: PlayerPolicy {}

/// Plays reasonably well, so scenarios end in a real victory or a real defeat, and uses most of
/// the player-side rules along the way: card choice by situation, either card on top and either
/// half first, default actions to save lost cards, short rests with re-picks, long rests when
/// hurt, damage negation when a hit would be fatal, kill-first targeting, pushes into traps, and
/// looting on the way.
struct TacticalPolicy: PlayerPolicy {

    /// Sturdy characters take the starting hexes nearest the monsters; fragile ones stay back.
    func startingHex(for character: GameCharacter, options: [HexCoord], sim: ScenarioSimulator) -> HexCoord {
        let monsters = sim.coord.boardState.piecePositions.compactMap { id, hex -> HexCoord? in
            if case .monster = id, !sim.coord.isPlayerSide(id) { return hex }
            return nil
        }
        guard !monsters.isEmpty else { return options[0] }
        func distance(_ hex: HexCoord) -> Int { monsters.map { hex.distance(to: $0) }.min()! }
        let sturdy = character.maxHealth >= 8
        return options.min { a, b in
            let da = sturdy ? distance(a) : -distance(a), db = sturdy ? distance(b) : -distance(b)
            return da == db ? a < b : da < db
        }!
    }

    // MARK: Card choice

    func chooseCards(for character: GameCharacter, hand: [AbilityModel],
                     sim: ScenarioSimulator) -> (leading: AbilityModel, other: AbilityModel)? {
        guard hand.count >= 2 else { return nil }
        // Long rest when hurt and the hand is running low (heal 2, recover the discards).
        let hurt = character.maxHealth - character.health
        if character.discardedCards.count >= 2
            && ((hand.count <= 3 && hurt >= 3) || character.health * 10 <= character.maxHealth * 3) {
            return nil
        }
        // Lost cards are rationed: about one per three rounds, so the party lasts the scenario.
        let lostAllowance = 1 + sim.gm.game.round / 3
        let me = PieceID.character(character.id)
        let distance = nearestEnemyDistance(from: me, sim: sim)
        let spareCards = hand.count + character.discardedCards.count

        var best: (score: Double, top: AbilityModel, bottom: AbilityModel)?
        for top in hand {
            for bottom in hand where bottom.cardId != top.cardId {
                let move = Self.moveValue(bottom.bottomActions ?? [])
                let lostHalves = (Self.isLost(top, top: true) ? 1 : 0) + (Self.isLost(bottom, top: false) ? 1 : 0)
                let overBudget = character.lostCards.count + lostHalves > lostAllowance || spareCards <= 4
                let score = halfScore(top.actions ?? [], isTop: true, extraMove: move,
                                      distance: distance, hurt: hurt, sim: sim)
                    + halfScore(bottom.bottomActions ?? [], isTop: false,
                                extraMove: 0, distance: distance, hurt: hurt, sim: sim)
                    - Double(lostHalves) * (overBudget ? 12 : 2)
                    // Act before the monsters when they are close (strongly when hurt); break ties
                    // toward lower card ids.
                    - (distance.map { $0 <= 4 } == true
                        ? Double(min(top.initiative, bottom.initiative)) / (hurt * 2 >= character.maxHealth ? 8 : 100) : 0)
                    - Double(top.cardId ?? 0) / 100_000 - Double(bottom.cardId ?? 0) / 1_000_000
                if best == nil || score > best!.score {
                    best = (score, top, bottom)
                }
            }
        }
        guard let best else { return nil }
        // The faster card leads; the turn then swaps halves if needed (see prepareTurn).
        return best.top.initiative <= best.bottom.initiative ? (best.top, best.bottom) : (best.bottom, best.top)
    }

    /// How useful one half is right now.
    private func halfScore(_ actions: [ActionModel], isTop: Bool, extraMove: Int, distance: Int?,
                           hurt: Int, sim: ScenarioSimulator) -> Double {
        var score = 0.0
        for action in actions {
            let value = Double(action.value?.intValue ?? 0)
            switch action.type {
            case .attack:
                let range = Self.range(of: action)
                if let distance, distance <= range + extraMove + Self.moveValue(actions) {
                    score += 3 * value + 2
                } else if distance != nil {
                    score += value * 0.5
                }
            case .move, .jump, .fly:
                if let distance { score += min(value, Double(max(0, distance - 1))) * 1.2 } else { score += value * 1.5 }
            case .heal:
                score += min(value, Double(hurt)) * 1.5
            case .shield, .retaliate:
                score += (distance ?? 9) <= 2 ? value * 1.5 : 0.3
            case .loot:
                score += sim.coord.boardState.lootTokens.isEmpty ? 0.2 : 2
            case .summon:
                score += distance == nil ? 0 : 10
            case .condition, .element:
                score += 0.5
            default:
                break
            }
        }
        return score
    }

    /// Whether playing this half sends the card to the lost pile.
    static func isLost(_ card: AbilityModel, top: Bool) -> Bool {
        let flag = top ? card.lost : card.bottomLost
        return flag == true || PlayerTurnController.markers(in: (top ? card.actions : card.bottomActions) ?? []).contains("lost")
    }

    func prepareTurn(_ turn: PlayerTurnController, sim: ScenarioSimulator) {
        guard let top = turn.topCard, let bottom = turn.bottomCard else { return }
        let me = PieceID.character(turn.characterID)
        let distance = nearestEnemyDistance(from: me, sim: sim)
        // Use the half pairing chosen in chooseCards: swap if the other card has the better top.
        let current = Self.quickValue(top.actions ?? []) + Self.quickValue(bottom.bottomActions ?? [])
        let swapped = Self.quickValue(bottom.actions ?? []) + Self.quickValue(top.bottomActions ?? [])
        if swapped > current { turn.swapCards() }
        // Move first when the attack can't reach yet.
        let attackRange = (turn.topActions.first { $0.type == .attack }).map(Self.range(of:))
        if let attackRange, let distance, distance > attackRange, Self.moveValue(turn.bottomActions) > 0 {
            turn.setBottomFirst(true)
        }
    }

    /// Play Attack 2 / Move 2 instead of a half with the lost icon when cards are short.
    func useDefaultAction(_ turn: PlayerTurnController, sim: ScenarioSimulator) -> Bool {
        guard let character = sim.character(turn.characterID),
              character.handCards.count + character.discardedCards.count <= 6 else { return false }
        let isTop = turn.phase == .executeTopAction
        let card = isTop ? turn.topCard : turn.bottomCard
        let actions = isTop ? turn.topActions : turn.bottomActions
        let lost = (isTop ? card?.lost : card?.bottomLost) == true || PlayerTurnController.markers(in: actions).contains("lost")
        guard lost, !actions.contains(where: { $0.type == .summon }) else { return false }
        if isTop {
            // Default Attack 2 needs an adjacent enemy.
            let me = PieceID.character(turn.characterID)
            return nearestEnemyDistance(from: me, sim: sim) == 1
        }
        return true
    }

    // MARK: Movement and targets

    func moveDestination(for piece: PieceID, options: Set<HexCoord>, mode: MoveMode, sim: ScenarioSimulator) -> HexCoord? {
        guard let start = sim.position(piece) else { return nil }
        let board = sim.coord.boardState
        let enemies = sim.enemies(of: piece).compactMap { id in sim.position(id).map { (id, $0) } }
        let range = upcomingAttackRange(sim: sim)
        let candidates = options.filter { hex in
            // Never end on a trap or hazardous terrain by choice.
            !(board.cells[hex]?.isTrap ?? false) && !(board.cells[hex]?.isHazard ?? false)
        }
        let pool = candidates.isEmpty ? options : candidates

        func lootBonus(_ hex: HexCoord) -> Int {
            (board.lootTokens[hex] ?? 0) > 0 || board.cells[hex]?.overlay == .treasure ? 1 : 0
        }
        let health = sim.health(piece)
        let hurt = health.current * 2 <= health.max
        /// Enemies that could hit this hex in melee beyond the one being attacked.
        func danger(_ hex: HexCoord) -> Int {
            max(0, adjacentEnemies(hex, enemies) - ((range ?? 1) > 1 ? 0 : 1))
        }

        if !enemies.isEmpty && health.current * 10 <= health.max * 4 {
            let value = sim.coord.activePlayerTurn?.currentAttackValue() ?? 2
            let killable = enemies.contains { sim.health($0.0).current <= value }
            if !(killable && range != nil) {
                // Badly hurt: get as far from the enemies as possible.
                return pool.min { a, b in
                    let da = enemies.map { a.distance(to: $0.1) }.min()!, db = enemies.map { b.distance(to: $0.1) }.min()!
                    return da == db ? a < b : da > db
                }
            }
        }
        if !enemies.isEmpty {
            if let range {
                // Hexes from which the coming attack reaches an enemy; ranged attackers avoid
                // standing next to one (disadvantage); prefer loot, then the shortest move.
                let attackHexes = pool.filter { hex in
                    enemies.contains { $0.1.distance(to: hex) <= range && LineOfSight.hasLOS(from: hex, to: $0.1, board: board) }
                }
                if !attackHexes.isEmpty {
                    return attackHexes.min { a, b in
                        let ka = (hurt ? danger(a) : 0, danger(a), -lootBonus(a), start.distance(to: a))
                        let kb = (hurt ? danger(b) : 0, danger(b), -lootBonus(b), start.distance(to: b))
                        return ka == kb ? a < b : ka < kb
                    }
                }
            }
            // No attack this turn: approach to just outside melee reach (or to attack range).
            let want = max(2, range ?? 2)
            return pool.min { a, b in
                let da = abs((enemies.map { a.distance(to: $0.1) }.min() ?? 0) - want) * 2 - lootBonus(a)
                let db = abs((enemies.map { b.distance(to: $0.1) }.min() ?? 0) - want) * 2 - lootBonus(b)
                return da == db ? a < b : da < db
            }
        }

        // Room clear: pick up loot within reach, else head for a closed door (entering it opens it).
        let loot = pool.filter { lootBonus($0) > 0 }
        if let hex = loot.min(by: { start.distance(to: $0) == start.distance(to: $1) ? $0 < $1 : start.distance(to: $0) < start.distance(to: $1) }) {
            return hex
        }
        let doors = board.doors.filter { !$0.isOpen }.map(\.coord)
        guard !doors.isEmpty else {
            let tokens = board.lootTokens.filter { $0.value > 0 }.map(\.key)
                + board.cells.values.filter { $0.overlay == .treasure }.map(\.coord)
            guard !tokens.isEmpty else { return nil }
            return pool.min { a, b in
                let da = tokens.map { a.distance(to: $0) }.min()!, db = tokens.map { b.distance(to: $0) }.min()!
                return da == db ? a < b : da < db
            }
        }
        return pool.min { a, b in
            let da = doors.map { a.distance(to: $0) }.min()!, db = doors.map { b.distance(to: $0) }.min()!
            return da == db ? a < b : da < db
        }
    }

    /// Kill what can be killed (the toughest such enemy first), else the weakest enemy.
    func attackTarget(for attacker: PieceID, options: Set<PieceID>, chosen: [PieceID], sim: ScenarioSimulator) -> PieceID? {
        let value = sim.coord.activePlayerTurn?.currentAttackValue() ?? 2
        return options.sorted().min { a, b in
            let ha = sim.health(a), hb = sim.health(b)
            let ka = ha.current <= value, kb = hb.current <= value
            if ka != kb { return ka }
            if ka { return ha.max == hb.max ? a < b : ha.max > hb.max }
            return ha.current == hb.current ? a < b : ha.current < hb.current
        }
    }

    /// Negative conditions go on the healthiest enemy (the longest-lived threat).
    func conditionTarget(for piece: PieceID, condition: ConditionName, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID? {
        options.sorted().max { a, b in
            let ha = sim.health(a).current, hb = sim.health(b).current
            return ha == hb ? a > b : ha < hb
        }
    }

    /// The most injured figure in range.
    func healTarget(for healer: PieceID, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID {
        options.sorted().max { a, b in
            let la = sim.health(a).max - sim.health(a).current, lb = sim.health(b).max - sim.health(b).current
            return la == lb ? a > b : la < lb
        } ?? healer
    }

    func summonHex(for owner: String, options: Set<HexCoord>, sim: ScenarioSimulator) -> HexCoord? {
        let enemies = sim.enemies(of: .character(owner)).compactMap { sim.position($0) }
        return options.min { a, b in
            let da = enemies.map { a.distance(to: $0) }.min() ?? 0, db = enemies.map { b.distance(to: $0) }.min() ?? 0
            return da == db ? a < b : da < db
        }
    }

    /// Push enemies into traps when possible, otherwise as far away as possible; pull them close.
    func forcedMoveHex(for target: PieceID, from origin: HexCoord, options: Set<HexCoord>, isPush: Bool,
                       sim: ScenarioSimulator) -> HexCoord? {
        let board = sim.coord.boardState
        let hostile = sim.coord.isPlayerSide(target) == false
        return options.min { a, b in
            let trapA = hostile && (board.cells[a]?.isTrap == true || board.cells[a]?.isHazard == true) ? 0 : 1
            let trapB = hostile && (board.cells[b]?.isTrap == true || board.cells[b]?.isHazard == true) ? 0 : 1
            if trapA != trapB { return trapA < trapB }
            let da = isPush ? -origin.distance(to: a) : origin.distance(to: a)
            let db = isPush ? -origin.distance(to: b) : origin.distance(to: b)
            return da == db ? a < b : da < db
        }
    }

    // MARK: Cards under pressure

    /// Negate a hit that would exhaust the character, with two discards if possible.
    func negateDamage(_ damage: Int, character: GameCharacter, sim: ScenarioSimulator) -> BoardCoordinator.DamageMitigationChoice {
        // Only worth it with cards to spare: otherwise the character exhausts from cards soon after.
        guard damage >= character.health, character.handCards.count + character.discardedCards.count >= 6 else {
            return .takeDamage
        }
        let ranked = { (ids: [Int]) -> [Int] in
            ids.indices.sorted { cardValue(ids[$0], character, sim) < cardValue(ids[$1], character, sim) }
        }
        if character.discardedCards.count >= 2 {
            return .loseDiscardCards(indices: Array(ranked(character.discardedCards).prefix(2)))
        }
        let losable = sim.coord.losableHandCards(of: character)
        if losable.count > 2, let index = ranked(losable).first {
            return .loseHandCard(cardId: losable[index])
        }
        return .takeDamage
    }

    /// Short rest only when the hand can't cover the next round (each rest costs a card, so
    /// resting late recovers the most); re-pick (1 damage) to keep a valuable card while healthy.
    func shortRest(character: GameCharacter, cardToLose: Int, sim: ScenarioSimulator) -> ShortRestDecision {
        guard character.handCards.count < 2 else { return .skip }
        let values = character.discardedCards.map { cardValue($0, character, sim) }
        let mine = cardValue(cardToLose, character, sim)
        if character.health > 4, let top = values.max(), mine == top, values.filter({ $0 == top }).count == 1 {
            return .restAndRepick
        }
        return .rest
    }

    /// Lose the least useful discarded card.
    func longRestLoss(character: GameCharacter, sim: ScenarioSimulator) -> Int {
        character.discardedCards.indices.min { a, b in
            let va = cardValue(character.discardedCards[a], character, sim)
            let vb = cardValue(character.discardedCards[b], character, sim)
            return va == vb ? a < b : va < vb
        } ?? 0
    }

    // MARK: Helpers

    private func nearestEnemyDistance(from piece: PieceID, sim: ScenarioSimulator) -> Int? {
        guard let pos = sim.position(piece) else { return nil }
        return sim.enemies(of: piece).compactMap { sim.position($0)?.distance(to: pos) }.min()
    }

    private func adjacentEnemies(_ hex: HexCoord, _ enemies: [(PieceID, HexCoord)]) -> Int {
        enemies.filter { $0.1.distance(to: hex) == 1 }.count
    }

    /// Range of the next attack this turn after the current action (the move being placed).
    private func upcomingAttackRange(sim: ScenarioSimulator) -> Int? {
        guard let turn = sim.coord.activePlayerTurn else { return nil }
        let current = turn.phase == .executeTopAction ? turn.topActions : turn.bottomActions
        var upcoming = Array(current.dropFirst(turn.currentActionIndex + 1))
        // Top then bottom, or bottom then top: is the other half still to come?
        let otherHalfPending = (turn.phase == .executeTopAction) != turn.bottomFirst
        if otherHalfPending {
            upcoming += turn.phase == .executeTopAction ? turn.bottomActions : turn.topActions
        }
        return upcoming.first { $0.type == .attack }.map(Self.range(of:))
    }

    private func cardValue(_ id: Int, _ character: GameCharacter, _ sim: ScenarioSimulator) -> Double {
        guard let card = sim.card(id, of: character) else { return 0 }
        return Self.quickValue(card.actions ?? []) + Self.quickValue(card.bottomActions ?? [])
            + (card.lost == true || card.bottomLost == true ? 2 : 0)
    }

    static func quickValue(_ actions: [ActionModel]) -> Double {
        actions.reduce(0) { total, action in
            let value = Double(action.value?.intValue ?? 0)
            switch action.type {
            case .attack: return total + value * 2 + (range(of: action) > 1 ? 1 : 0)
            case .move, .jump, .fly: return total + value
            case .heal, .shield, .retaliate: return total + value
            case .summon: return total + 5
            default: return total + 0.25
            }
        }
    }

    static func range(of action: ActionModel) -> Int {
        action.subActions?.first { $0.type == .range }?.value?.intValue ?? 1
    }

    static func moveValue(_ actions: [ActionModel]) -> Int {
        actions.first { $0.type == .move || $0.type == .jump || $0.type == .fly }?.value?.intValue ?? 0
    }
}
