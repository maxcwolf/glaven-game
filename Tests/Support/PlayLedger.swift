import Foundation
@testable import GlavenGameLib

/// The rules `ScenarioSimulator` holds a playthrough to beyond the state of the board, as plain
/// functions of what it saw — kept apart from the simulator so that each check can be shown to
/// fire on a bad event (`PlayLedgerTests`).
///
/// What a check needs to know of the rules it reads from the cards and the stat cards, not from
/// the engine's own targeting or turn order: a violation the engine can't see must still be
/// seen here.
final class PlayLedger {

    // MARK: - Attacks: range (ATK-1, LOS-3)

    /// An attack reaches its target only within its range, counted in hexes.
    static func rangeProblem(attacker: PieceID, target: PieceID, from: HexCoord, to: HexCoord, reach: Int) -> String? {
        let distance = from.distance(to: to)
        guard distance > reach else { return nil }
        return "\(attacker) at \(from) attacks \(target) at \(to): \(distance) hexes away, with a reach of \(reach)"
    }

    /// How many hexes beyond its range an area attack can reach: for a melee area the furthest
    /// red hex from the attacker's grey one; for a ranged area the pattern's width (one of its
    /// hexes must be within range, the others lie around it).
    static func areaReach(_ pattern: String, range: Int) -> Int {
        let hexes = AoEResolver.parsePattern(pattern)
        func distance(_ a: AoEResolver.PatternHex, _ b: AoEResolver.PatternHex) -> Int {
            max(abs(a.cubeX - b.cubeX), abs(a.cubeY - b.cubeY), abs(a.cubeZ - b.cubeZ))
        }
        let targets = hexes.filter(\.isTarget)
        if let active = hexes.first(where: \.isActive) {
            return targets.map { distance(active, $0) }.max() ?? 1
        }
        let width = targets.flatMap { a in targets.map { distance(a, $0) } }.max() ?? 0
        return max(1, range) + width
    }

    /// The furthest any attack on a monster's card can reach, from the stat card's range and
    /// what the card prints: a range with no sign replaces the stat card's, "+X" adds to it, a
    /// melee attack reaches the adjacent hex, an area as far as its pattern. Nil when the card
    /// has no attack. (An upper bound: a range an element would add is counted as added.)
    static func monsterReach(statRange: Int, card actions: [ActionModel]) -> Int? {
        var best: Int?
        func attackReach(_ attack: ActionModel) -> Int {
            var range = statRange
            var pattern: String?
            func read(_ subs: [ActionModel]) {
                for sub in subs {
                    switch sub.type {
                    case .range:
                        let value = sub.value?.intValue ?? 0
                        if sub.valueType == .plus || sub.valueType == .add { range += value }
                        else if sub.valueType == .minus || sub.valueType == .subtract { break }   // "−X Range": at most what it was
                        else { range = max(range, value) }
                    case .area:
                        pattern = sub.value?.stringValue
                    default:
                        break
                    }
                    read(sub.subActions ?? [])
                }
            }
            read(attack.subActions ?? [])
            if let pattern { return areaReach(pattern, range: range) }
            return max(1, range)
        }
        func walk(_ actions: [ActionModel]) {
            for action in actions {
                if action.type == .attack {
                    best = max(best ?? 0, attackReach(action))
                } else {
                    walk(action.subActions ?? [])
                }
            }
        }
        walk(actions)
        return best
    }

    /// How many separate Attack abilities a monster's card prints (each may hit an enemy once).
    static func attackLines(_ actions: [ActionModel]) -> Int {
        actions.reduce(0) { total, action in
            total + (action.type == .attack ? 1 : attackLines(action.subActions ?? []))
        }
    }

    /// How often a monster's card lets it attack the same enemy in a turn: once for each Attack
    /// it prints — and, where the card says "target one enemy with all attacks" (Living Bones,
    /// Lurkers), as often as the stat card's Target gives it attacks.
    static func attacksOnOneEnemy(card actions: [ActionModel], statTargets: Int) -> Int {
        func allOnOne(_ actions: [ActionModel]) -> Bool {
            actions.contains { action in
                (action.type == .specialTarget && action.value?.stringValue == "enemyOneAll") || allOnOne(action.subActions ?? [])
            }
        }
        return max(1, attackLines(actions)) * (allOnOne(actions) ? max(1, statTargets) : 1)
    }

    // MARK: - Attacks: no enemy twice by one ability (ATK-9)

    private var attacksMade: [String: [PieceID: Int]] = [:]

    /// One more attack on `target` by the attack ability `ability` (a key that is the same for
    /// every attack the ability makes), which may attack each enemy `allowed` times.
    func noteAttack(ability: String, target: PieceID, allowed: Int = 1) -> String? {
        attacksMade[ability, default: [:]][target, default: 0] += 1
        let count = attacksMade[ability]![target]!
        guard count > allowed else { return nil }
        return "\(target) is attacked \(count) times by one attack ability (\(ability))"
    }

    // MARK: - The order of turns (RND-6, RND-7, RND-8, MON-9)

    private struct Act {
        let piece: PieceID
        /// Which figure it is: a standee number is used again after its monster has died.
        let identity: AnyHashable
        let initiative: Double
        let newcomer: Bool
    }

    private var round = -1
    private var acts: [Act] = []

    /// The figure whose turn it is has done something (moved, attacked) in `round`.
    ///
    /// - `initiative`: where the rules put its turn — a character's leading card (99 for a long
    ///   rest), a monster type's ability card, a summon just before its owner; on a tie a
    ///   character before a monster, so a character's is given a little lower.
    /// - `newcomer`: it was not on the board when the round's turns began (revealed or spawned
    ///   since): it acts when the rules for that say, not at its initiative.
    /// - `owner`: for a summon, its owner's piece.
    /// - `summonedThisRound`: a summon or summoned monster that arrived this round.
    /// - `identity`: the figure itself where a piece's name can pass to another (a standee
    ///   number reused in the same round); the piece otherwise.
    func noteAct(round: Int, piece: PieceID, initiative: Double, newcomer: Bool = false, owner: PieceID? = nil,
                 summonedThisRound: Bool = false, identity: AnyHashable? = nil) -> [String] {
        let identity = identity ?? AnyHashable(piece)
        if round != self.round {
            self.round = round
            acts = []
            attacksMade = [:]
        }
        if acts.last?.identity == identity { return [] }
        var problems: [String] = []
        if summonedThisRound {
            problems.append("\(piece) acts in the round it was summoned (round \(round))")
        }
        if acts.contains(where: { $0.identity == identity }) {
            problems.append("\(piece) takes a second turn in round \(round), after \(acts.last!.piece)")
        }
        if let owner, acts.contains(where: { $0.piece == owner }) {
            problems.append("\(piece) acts after its owner \(owner) in round \(round), not before")
        }
        if !newcomer, let earlier = acts.last(where: { !$0.newcomer }), initiative < earlier.initiative {
            problems.append("\(piece) (initiative \(Self.shown(initiative))) acts after \(earlier.piece) (\(Self.shown(earlier.initiative))) in round \(round)")
        }
        acts.append(Act(piece: piece, identity: identity, initiative: initiative, newcomer: newcomer))
        return problems
    }

    /// The figure is given another turn this round by a rule that says so (the Merciless
    /// Overseer's "All Scouts act again", MON-11): what it did on its first is set aside.
    func anotherTurn(for piece: PieceID, identity: AnyHashable? = nil) {
        let identity = identity ?? AnyHashable(piece)
        acts.removeAll { $0.identity == identity }
        attacksMade = attacksMade.filter { !$0.key.hasPrefix("\(piece)") }
    }

    private static func shown(_ initiative: Double) -> String { String(Int(initiative.rounded(.up))) }

    /// A character's place in the order: their initiative, a little before a monster type on
    /// the same number; a long rest is 99, after a character whose card says 99.
    static func characterInitiative(_ initiative: Int, longRest: Bool) -> Double {
        longRest ? 98.75 : Double(initiative) - 0.5
    }

    /// A summon's place: directly before its owner.
    static func summonInitiative(ownerInitiative: Double) -> Double { ownerInitiative - 0.1 }

    // MARK: - Rests and cards (RND-1 … RND-4, ATK-15)

    /// A rest, short or long, needs two cards in the discard pile.
    static func restProblem(_ name: String, rest: String, discards: Int) -> String? {
        discards >= 2 ? nil : "\(name) takes a \(rest) rest with \(discards) card\(discards == 1 ? "" : "s") in the discard pile"
    }

    /// Cards are neither made nor destroyed: hand, discard pile, lost pile and active area hold
    /// the character's hand size between them — and all of them are in the lost pile once the
    /// character is exhausted.
    static func cardProblem(_ name: String, exhausted: Bool, hand: Int, discard: Int, lost: Int, active: Int, handSize: Int) -> String? {
        let total = hand + discard + lost + active
        if total != handSize { return "\(name) has \(total) of \(handSize) cards" }
        if exhausted, hand + discard + active > 0 {
            return "exhausted \(name) still holds \(hand) cards in hand, \(discard) discarded and \(active) in play"
        }
        return nil
    }

    // MARK: - Money (TRN-5, MOV-10, SET-4)

    /// The gold the characters gained in one step against the money tokens that left the board
    /// in it: every token looted pays the level's rate, and nothing else pays (but the gold of a
    /// numbered treasure looted in the same step). While monsters act, tokens may also leave
    /// with a monster's Loot — unpaid — so then no more than the tokens gone can have been paid.
    static func goldProblem(gained: Int, tokensGone: Int, treasureGold: Int, rate: Int, monstersActing: Bool) -> String? {
        let fromTokens = gained - treasureGold
        guard fromTokens >= 0, rate > 0, fromTokens % rate == 0 else {
            return "\(gained) gold gained for \(tokensGone) money token\(tokensGone == 1 ? "" : "s") at \(rate) each"
                + (treasureGold > 0 ? " and \(treasureGold) from a treasure" : "")
        }
        let paid = fromTokens / rate
        if paid > tokensGone || (!monstersActing && paid != tokensGone) {
            return "\(gained) gold gained (\(paid) token\(paid == 1 ? "" : "s") at \(rate)) but \(tokensGone) left the board"
        }
        return nil
    }
}
