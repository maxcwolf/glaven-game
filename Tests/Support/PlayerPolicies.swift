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
    /// Whose card, if any, is lost to spare what the party protects a source of damage.
    func spare(_ pending: BoardCoordinator.PendingSave, sim: ScenarioSimulator) -> (characterID: String, cardId: Int)?
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

    /// Only what would be destroyed is worth a card: from the fullest hand, its last card.
    func spare(_ pending: BoardCoordinator.PendingSave, sim: ScenarioSimulator) -> (characterID: String, cardId: Int)? {
        guard pending.destroys,
              let hand = pending.hands.max(by: { ($0.cards.count, $1.characterID) < ($1.cards.count, $0.characterID) }),
              let card = hand.cards.last else { return nil }
        return (hand.characterID, card)
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

/// Plays to win with the plainest means the rules give every character: each turn a move and
/// an attack, a card's lost half never played (its basic Attack 2 / Move 2 instead), a short
/// rest only when the hand has run out, every attack on the enemy it can kill or the weakest in
/// reach, doors opened only once the room is clear, and — when no enemy is left to fight — a walk
/// to what the scenario's goal names (its treasure, its exit, its lettered hex, its plates).
///
/// With a veteran party (`ScenarioSimulator.Options.veteranParty`) this wins most scenarios, so
/// late rooms, bosses and the scenarios' own goals are played to their end.
struct VeteranPolicy: PlayerPolicy {

    private let basics = TacticalPolicy()

    /// An attack as the policy reckons with it.
    private struct Strike: Hashable {
        var value: Int
        var range: Int
        var targets: Int
        /// Movement the same half gives before the attack ("Move 2, Attack 2").
        var ownMove = 0
        static let basic = Strike(value: 2, range: 1, targets: 1)
    }

    private struct Step: Hashable {
        var move: Int
        var jump: Bool
        static let basic = Step(move: 2, jump: false)
    }

    func startingHex(for character: GameCharacter, options: [HexCoord], sim: ScenarioSimulator) -> HexCoord {
        basics.startingHex(for: character, options: options, sim: sim)
    }

    // MARK: - Reading cards

    /// The attack a card's top half makes without being lost; nil if it has none.
    private func printedStrike(_ card: AbilityModel?) -> Strike? {
        guard let card, !TacticalPolicy.isLost(card, top: true) else { return nil }
        let actions = card.actions ?? []
        guard let index = actions.firstIndex(where: { $0.type == .attack }), let value = actions[index].value?.intValue,
              value > 0 else { return nil }
        let attack = actions[index]
        let subs = attack.subActions ?? []
        var range = TacticalPolicy.range(of: attack)
        var targets = subs.first { $0.type == .target }?.value?.intValue ?? 1
        if subs.contains(where: { $0.type == .area }) { targets = max(targets, 2); range = max(range, 1) }
        if subs.contains(where: { $0.type == .specialTarget && ($0.value?.stringValue.contains("enemies") ?? false) }) { targets = 6 }
        let ownMove = actions[..<index].first { $0.type == .move }?.value?.intValue ?? 0
        return Strike(value: value, range: max(1, range), targets: max(1, targets), ownMove: ownMove)
    }

    /// The move a card's bottom half makes without being lost; nil if it has none.
    private func printedStep(_ card: AbilityModel?) -> Step? {
        guard let card, !TacticalPolicy.isLost(card, top: false) else { return nil }
        guard let move = (card.bottomActions ?? []).first(where: { $0.type == .move }), let value = move.value?.intValue, value > 0
        else { return nil }
        return Step(move: value, jump: (move.subActions ?? []).contains { $0.type == .jump })
    }

    /// The attack a card's bottom half makes without being lost (Spare Dagger's Attack 2).
    private func bottomStrike(_ card: AbilityModel?) -> Strike? {
        guard let card, !TacticalPolicy.isLost(card, top: false),
              let attack = (card.bottomActions ?? []).first(where: { $0.type == .attack }), let value = attack.value?.intValue, value > 0
        else { return nil }
        return Strike(value: value, range: max(1, TacticalPolicy.range(of: attack)), targets: 1)
    }

    // MARK: - Reading the board

    private func foes(of piece: PieceID, _ sim: ScenarioSimulator) -> [(piece: PieceID, hex: HexCoord, health: Int)] {
        sim.enemies(of: piece).compactMap { id in sim.position(id).map { (id, $0, sim.health(id).current) } }
    }

    /// Hexes the character can end a move of `step` on (their own included), traps and hazardous
    /// terrain left out.
    private func reach(_ piece: PieceID, _ step: Step, _ sim: ScenarioSimulator) -> [HexCoord] {
        guard let here = sim.position(piece) else { return [] }
        guard step.move > 0, !sim.coord.isConditionActive(.immobilize, on: piece) else { return [here] }
        let board = sim.coord.boardState
        let (enemies, allies) = sim.coord.movementSets(for: piece)
        let reachable = Pathfinder.reachableHexes(board: board, from: here, range: step.move, mode: step.jump ? .jump : .normal,
                                                  avoidTraps: false, canOpenDoors: false,
                                                  occupiedByEnemy: enemies, occupiedByAlly: allies)
        return ([here] + reachable.keys.filter { hex in
            hex != here && !(board.cells[hex]?.isTrap ?? false) && !(board.cells[hex]?.isHazard ?? false) && !board.isClosedDoor(hex)
        }).sorted()
    }

    /// What `strike` is worth from `hex`: the hit points it takes off the enemies in reach
    /// (weakest first), and more for each it kills.
    private func worth(_ strike: Strike, from hex: HexCoord, _ foes: [(piece: PieceID, hex: HexCoord, health: Int)],
                       _ sim: ScenarioSimulator) -> Int {
        let board = sim.coord.boardState
        let inReach = foes.filter { $0.hex.distance(to: hex) <= strike.range && LineOfSight.hasLOS(from: hex, to: $0.hex, board: board) }
            .map(\.health).sorted()
        return inReach.prefix(strike.targets).reduce(0) { $0 + min(strike.value, $1) + (strike.value >= $1 ? 4 : 0) }
    }

    private func best(_ strike: Strike, among hexes: [HexCoord], _ foes: [(piece: PieceID, hex: HexCoord, health: Int)],
                      _ sim: ScenarioSimulator) -> (worth: Int, hex: HexCoord?) {
        var best: (worth: Int, hex: HexCoord?) = (0, nil)
        for hex in hexes {
            let value = worth(strike, from: hex, foes, sim)
            if value > best.worth { best = (value, hex) }
        }
        return best
    }

    /// Steps from every floor hex to the nearest of `targets`, walls and obstacles in the way
    /// (figures aren't: they move). Closed doors are walked through only when `throughDoors`.
    private func stepsTo(_ targets: [HexCoord], _ sim: ScenarioSimulator, throughDoors: Bool) -> [HexCoord: Int] {
        let board = sim.coord.boardState
        var steps: [HexCoord: Int] = [:]
        var frontier = targets.filter { board.cells[$0] != nil }
        frontier.forEach { steps[$0] = 0 }
        while !frontier.isEmpty {
            var next: [HexCoord] = []
            for hex in frontier {
                let cost = steps[hex]! + 1
                for neighbor in hex.neighbors where steps[neighbor] == nil {
                    guard let cell = board.cells[neighbor], cell.passable, cell.overlay != .wall, !board.isLockedDoor(neighbor) else { continue }
                    if board.isClosedDoor(neighbor) && !throughDoors { continue }
                    steps[neighbor] = cost
                    next.append(neighbor)
                }
            }
            frontier = next
        }
        return steps
    }

    /// Where the party is headed when there is no one to fight: what the goal names, else a door.
    private func destinations(for piece: PieceID, _ sim: ScenarioSimulator) -> (hexes: [HexCoord], adjacentIsEnough: Bool) {
        let board = sim.coord.boardState
        // Won already, with the round to play out: no door is opened on what lies beyond.
        if sim.coord.pendingResult == .victory { return ([], false) }
        let taken = Set(board.piecePositions.filter { $0.key != piece }.values)
        if let goal = sim.coord.scenarioGoal {
            var hexes: [HexCoord] = []
            if goal.loot != nil || goal.lootIDs != nil {
                let ids = Set(goal.lootIDs ?? [])
                var mayLootGoal = true
                if case .character(let id) = piece { mayLootGoal = sim.coord.mayLootGoalTreasure(id) }
                hexes += board.cells.values.filter { cell in
                    cell.overlay == .treasure && ((cell.treasureID == BoardCoordinator.goalTreasureID && mayLootGoal)
                                                  || ids.contains(cell.treasureID ?? ""))
                }.map(\.coord)
            }
            if !hexes.isEmpty { return (hexes.sorted(), false) }
            if let reach = goal.reach, let lettered = board.markerHexes[reach.marker], !lettered.isEmpty {
                return (lettered.sorted(), reach.adjacent == true)
            }
            if let plates = goal.occupy {
                let free = sim.coord.platesInPlay(plates).flatMap { board.markerHexes[$0] ?? [] }.filter { !taken.contains($0) }
                if !free.isEmpty { return (free.sorted(), false) }
            }
            // The exit, once nothing else is left to do on the way (doors still shut come first).
            if let exit = goal.escape, !board.doors.contains(where: { !$0.isOpen && !board.isLockedDoor($0.coord) }) {
                let free = sim.coord.exitHexes(exit).filter { !taken.contains($0) }
                if !free.isEmpty { return (free.sorted(), false) }
            }
        }
        let doors = board.doors.filter { !$0.isOpen && !board.isLockedDoor($0.coord) }.map(\.coord)
        if !doors.isEmpty { return (doors.sorted(), false) }
        // Nothing left to open: the money on the floor.
        let tokens = board.lootTokens.filter { $0.value > 0 }.map(\.key)
        return (tokens.sorted(), false)
    }

    // MARK: - Cards

    /// The two cards whose attack and move do the most this turn; nil (a long rest) only with
    /// fewer than two cards in hand.
    func chooseCards(for character: GameCharacter, hand: [AbilityModel],
                     sim: ScenarioSimulator) -> (leading: AbilityModel, other: AbilityModel)? {
        guard hand.count >= 2 else { return nil }
        let me = PieceID.character(character.id)
        let foes = foes(of: me, sim)
        var reaches: [Step: [HexCoord]] = [:]
        func hexes(_ step: Step) -> [HexCoord] {
            if let known = reaches[step] { return known }
            let found = reach(me, step, sim)
            reaches[step] = found
            return found
        }
        // With no one to attack: how far the move gets toward the enemies, or the goal.
        let (targets, _) = foes.isEmpty ? destinations(for: me, sim) : (foes.map(\.hex), true)
        let field = stepsTo(targets, sim, throughDoors: foes.isEmpty)
        func approach(_ step: Step) -> Int {
            // One more hex of reach than the search without doors gives: the door itself.
            let around = foes.isEmpty ? hexes(Step(move: step.move, jump: step.jump)).flatMap { [$0] + $0.neighbors } : hexes(step)
            return around.compactMap { field[$0] }.min() ?? 99
        }

        var bestPair: (score: Int, top: AbilityModel, bottom: AbilityModel)?
        for top in hand {
            let strike = printedStrike(top) ?? .basic
            for bottom in hand where bottom.cardId != top.cardId {
                let step = printedStep(bottom) ?? .basic
                let reachWithOwnMove = strike.ownMove > 0 ? Step(move: step.move + strike.ownMove, jump: step.jump) : step
                var value = best(strike, among: hexes(reachWithOwnMove), foes, sim).worth
                // A bottom half that attacks instead (when no move is needed to strike).
                if let second = bottomStrike(bottom), let here = sim.position(me) {
                    let standing = worth(strike, from: here, foes, sim) + worth(second, from: here, foes, sim)
                    value = max(value, standing)
                }
                var score = value * 100
                if value == 0 { score -= approach(step) * 10 }
                // Act early when there is something to hit; tie-break toward lower card ids.
                score -= (value > 0 ? min(top.initiative, bottom.initiative) : 99 - max(top.initiative, bottom.initiative)) / 10
                if bestPair == nil || score > bestPair!.score
                    || (score == bestPair!.score && (top.cardId ?? 0, bottom.cardId ?? 0) < (bestPair!.top.cardId ?? 0, bestPair!.bottom.cardId ?? 0)) {
                    bestPair = (score, top, bottom)
                }
            }
        }
        guard let pair = bestPair else { return nil }
        let attacking = pair.score > 0
        let topLeads = attacking ? pair.top.initiative <= pair.bottom.initiative : pair.top.initiative >= pair.bottom.initiative
        return topLeads ? (pair.top, pair.bottom) : (pair.bottom, pair.top)
    }

    /// What a turn with `top` above `bottom` is worth from where the character stands.
    private func turnWorth(top: AbilityModel?, bottom: AbilityModel?, _ me: PieceID, _ sim: ScenarioSimulator) -> Int {
        let foes = foes(of: me, sim)
        let strike = printedStrike(top) ?? .basic, step = printedStep(bottom) ?? .basic
        var value = best(strike, among: reach(me, Step(move: step.move + strike.ownMove, jump: step.jump), sim), foes, sim).worth * 100
        if let second = bottomStrike(bottom), let here = sim.position(me) {
            value = max(value, (worth(strike, from: here, foes, sim) + worth(second, from: here, foes, sim)) * 100)
        }
        return value + step.move
    }

    func prepareTurn(_ turn: PlayerTurnController, sim: ScenarioSimulator) {
        let me = PieceID.character(turn.characterID)
        if turnWorth(top: turn.bottomCard, bottom: turn.topCard, me, sim) > turnWorth(top: turn.topCard, bottom: turn.bottomCard, me, sim) {
            turn.swapCards()
        }
        // Move first unless the attack already does its best from here.
        guard let here = sim.position(me) else { return }
        let foes = foes(of: me, sim)
        let strike = printedStrike(turn.topCard) ?? .basic, step = printedStep(turn.bottomCard) ?? .basic
        let standing = worth(strike, from: here, foes, sim)
        let moving = best(strike, among: reach(me, step, sim), foes, sim).worth
        if moving > standing || (standing == 0 && bottomStrike(turn.bottomCard) == nil) { turn.setBottomFirst(true) }
    }

    /// The basic Attack 2 or Move 2 whenever the printed half would lose the card, and whenever
    /// it would do nothing where the basic action would.
    func useDefaultAction(_ turn: PlayerTurnController, sim: ScenarioSimulator) -> Bool {
        let me = PieceID.character(turn.characterID)
        guard turn.canUseDefaultAction, let here = sim.position(me) else { return false }
        let foes = foes(of: me, sim)
        let enemyBeside = foes.contains { $0.hex.distance(to: here) == 1 }
        if turn.phase == .executeTopAction {
            guard let card = turn.topCard else { return false }
            if TacticalPolicy.isLost(card, top: true) { return true }
            if let strike = printedStrike(card) {
                // A printed attack with no one in its reach, and someone beside for the basic one.
                return strike.ownMove == 0 && worth(strike, from: here, foes, sim) == 0 && enemyBeside
            }
            return enemyBeside
        }
        guard let card = turn.bottomCard else { return false }
        if TacticalPolicy.isLost(card, top: false) { return true }
        if printedStep(card) != nil { return false }
        if let second = bottomStrike(card), worth(second, from: here, foes, sim) > 0 { return false }
        // No move printed: walk the basic two hexes when there is somewhere to go.
        let attackStillToCome = turn.bottomFirst
        let strike = printedStrike(turn.topCard) ?? .basic
        if attackStillToCome { return worth(strike, from: here, foes, sim) == 0 }
        return !enemyBeside
    }

    // MARK: - Moves

    /// The attack still to come this turn, after the move being placed.
    private func strikeToCome(_ sim: ScenarioSimulator) -> Strike? {
        guard let turn = sim.coord.activePlayerTurn else { return nil }
        let inTop = turn.phase == .executeTopAction
        let current = inTop ? turn.topActions : turn.bottomActions
        if let later = current.dropFirst(turn.currentActionIndex + 1).first(where: { $0.type == .attack }), let value = later.value?.intValue {
            return Strike(value: max(1, value), range: max(1, TacticalPolicy.range(of: later)), targets: 1)
        }
        // The other half, if it is still to be played.
        let otherHalfPending = inTop != turn.bottomFirst
        guard otherHalfPending else { return nil }
        if inTop { return bottomStrike(turn.bottomCard) }
        return printedStrike(turn.topCard) ?? .basic
    }

    func moveDestination(for piece: PieceID, options: Set<HexCoord>, mode: MoveMode, sim: ScenarioSimulator) -> HexCoord? {
        guard case .character = piece, let here = sim.position(piece) else {
            return basics.moveDestination(for: piece, options: options, mode: mode, sim: sim)
        }
        let board = sim.coord.boardState
        let foes = foes(of: piece, sim)
        let safe = options.filter { !(board.cells[$0]?.isTrap ?? false) && !(board.cells[$0]?.isHazard ?? false) }
        // A door is opened only when no enemy is left on the board.
        let allowed = (safe.isEmpty ? options : safe).filter { foes.isEmpty || !board.isClosedDoor($0) }
        let pool = (allowed.isEmpty ? Set([here]).intersection(options) : allowed).sorted()
        guard !pool.isEmpty else { return options.contains(here) ? here : nil }
        func loot(_ hex: HexCoord) -> Int { (board.lootTokens[hex] ?? 0) > 0 ? 0 : 1 }

        if !foes.isEmpty {
            if let strike = strikeToCome(sim) {
                let ranked = pool.map { (hex: $0, worth: worth(strike, from: $0, foes, sim)) }
                if let top = ranked.map(\.worth).max(), top > 0 {
                    // The shortest move among the best; a ranged attacker keeps off its targets.
                    return ranked.filter { $0.worth == top }.map(\.hex).min { a, b in
                        let beside = { (hex: HexCoord) in strike.range > 1 ? foes.filter { $0.hex.distance(to: hex) == 1 }.count : 0 }
                        let ka = (beside(a), loot(a), here.distance(to: a)), kb = (beside(b), loot(b), here.distance(to: b))
                        return ka == kb ? a < b : ka < kb
                    }
                }
            }
            // No attack from anywhere in reach: close in on the nearest enemy.
            let field = stepsTo(foes.map(\.hex), sim, throughDoors: false)
            return pool.min { a, b in
                let ka = (field[a] ?? 99, loot(a)), kb = (field[b] ?? 99, loot(b))
                return ka == kb ? a < b : ka < kb
            }
        }

        // No one to fight: toward what the goal names, else the next door.
        let (targets, adjacentIsEnough) = destinations(for: piece, sim)
        guard !targets.isEmpty else { return options.contains(here) ? here : nil }
        let field = stepsTo(targets, sim, throughDoors: true)
        return pool.min { a, b in
            let da = max(adjacentIsEnough ? 1 : 0, field[a] ?? 99), db = max(adjacentIsEnough ? 1 : 0, field[b] ?? 99)
            let ka = (da, loot(a)), kb = (db, loot(b))
            return ka == kb ? a < b : ka < kb
        }
    }

    // MARK: - The rest as the tactical party plays it

    func attackTarget(for attacker: PieceID, options: Set<PieceID>, chosen: [PieceID], sim: ScenarioSimulator) -> PieceID? {
        basics.attackTarget(for: attacker, options: options, chosen: chosen, sim: sim)
    }

    func conditionTarget(for piece: PieceID, condition: ConditionName, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID? {
        basics.conditionTarget(for: piece, condition: condition, options: options, sim: sim)
    }

    func healTarget(for healer: PieceID, options: Set<PieceID>, sim: ScenarioSimulator) -> PieceID {
        basics.healTarget(for: healer, options: options, sim: sim)
    }

    func summonHex(for owner: String, options: Set<HexCoord>, sim: ScenarioSimulator) -> HexCoord? {
        basics.summonHex(for: owner, options: options, sim: sim)
    }

    func forcedMoveHex(for target: PieceID, from origin: HexCoord, options: Set<HexCoord>, isPush: Bool,
                       sim: ScenarioSimulator) -> HexCoord? {
        basics.forcedMoveHex(for: target, from: origin, options: options, isPush: isPush, sim: sim)
    }

    func negateDamage(_ damage: Int, character: GameCharacter, sim: ScenarioSimulator) -> BoardCoordinator.DamageMitigationChoice {
        basics.negateDamage(damage, character: character, sim: sim)
    }

    /// A short rest only when the hand can't cover the next round: resting late loses the fewest cards.
    func shortRest(character: GameCharacter, cardToLose: Int, sim: ScenarioSimulator) -> ShortRestDecision {
        character.handCards.count < 2 ? .rest : .skip
    }

    func longRestLoss(character: GameCharacter, sim: ScenarioSimulator) -> Int {
        basics.longRestLoss(character: character, sim: sim)
    }
}
