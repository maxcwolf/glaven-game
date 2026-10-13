import Foundation

/// Persistent bonuses with charges (GH p.24): "on the next six sources of damage…", "on your
/// next four ranged attack actions…". The card stays in the active area and a charge is marked
/// each time the bonus applies (some slots give experience); when every charge is marked the
/// card leaves the active area, to the lost pile if it has the lost icon.
///
/// Played so far: the charged cards whose effect needs no extra choice.
enum ChargedBonus: Equatable {
    /// Shield N against each attack that would damage the character.
    case shieldAgainstAttacks(Int)
    /// Suffer no damage, from any source.
    case negateDamage
    /// Suffer no damage from an attack, and retaliate against the attacker within range.
    case negateAttackAndRetaliate(Int, range: Int)
    /// Retaliate N against each melee attack targeting the character.
    case retaliateAgainstMelee(Int)
    /// One more target on each of the character's ranged attack actions.
    case extraTargetOnRanged
    /// On each of the character's attack actions: +N, added conditions, advantage.
    case attackPackage(bonus: Int, conditions: [ConditionName], advantage: Bool)
    /// +N on each attack action, or +M by consuming the element (Crackling Air: +1, Air: +2).
    case attackBonusOrElement(Int, ElementType, Int)
    /// A condition added to each attack made while invisible.
    case conditionWhileInvisible(ConditionName)
    /// +N each time the character is healed.
    case healedBonus(Int)
    /// The character's heals first remove the healed figure's negative conditions.
    case healCleanses
    /// Suffer no damage that would bring the character below 1 hit point.
    case negateLethal
    /// At the end of the character's turn, infuse the element unless it is already strong.
    case endOfTurnInfuse(ElementType)
    /// At the end of the character's turn, heal every adjacent ally.
    case endOfTurnHealAdjacent(Int)

    // Round bonuses (no charges: they last until the card leaves at the end of the round).
    enum Reach: Equatable { case any, melee, ranged }
    /// +N on every attack of that reach this round (Wall of Doom, Heaving Swing, Forceful Storm).
    case roundAttackBonus(Int, Reach)
    /// +N on every attack this round, for the character and allies beside them (Enhancement Field).
    case roundAttackBonusWithAdjacentAllies(Int)
    /// 1 experience each time the character retaliates this round (Eye for an Eye).
    case experiencePerRetaliate
    /// The next damage this round is negated (Trickster's Reversal: a single use).
    case negateNextDamage
    /// Enemies attacking an ally beside the character attack the character instead (Provoking Roar).
    case drawAttacksFromAdjacentAllies
    /// On each attack action (ranged only, if so) while the element is there: consume it for +N
    /// Range (Nature's Lift) or +N Attack (Foul Wind). A charge is marked only when it's consumed.
    case consumeForRange(ElementType, Int)
    case consumeForAttack(ElementType, Int)
    /// The character's summons suffer no damage instead (Intervening Apparitions).
    case summonsNegateDamage
    /// Each Curse the character gives is given twice (Unending Chant).
    case doubleCurses
    /// The character's summon heals itself after each of its attacks (Blood Hunger: Heal 2).
    case summonHealsAfterAttack(Int)
    /// An action the character performs at the start of each turn (Lumbering Bash: Heal 2, Range 2).
    case turnStartAction(ActionModel)
    /// An action the character performs at the end of each turn (Auto Turret: Attack 2, Range 5).
    case turnEndAction(ActionModel)

    // The Doomstalker's cards about doomed enemies.
    /// The next times a doomed enemy dies, the character performs an attack (Rain of Arrows).
    case attackOnDoomedDeath(value: Int, range: Int)
    /// The next times a doomed enemy dies near another enemy, a doom moves to it (Frightening Curse).
    case transferDoomOnDeath(range: Int)
    /// Advantage on one attack each turn against a doomed enemy; enemies can't be invisible (Expose).
    case advantageOncePerTurnVsDoomed
    /// Two dooms may be on the same enemy (Inescapable Fate).
    case twoDooms
    /// +N on attacks against doomed enemies this round (Relentless Offensive, Impending End).
    case roundAttackBonusVsDoomed(Int)

    /// Each time the character suffers damage, they perform an attack (Vengeful Barrage: Attack 3).
    case attackOnDamage(Int)
    /// On each attack action the character may Curse an ally within range for extra targets (Grim Bargain).
    case curseAllyForTargets(range: Int, targets: Int)
    /// The character's next attack action this round is doubled (Grim Bargain's bottom).
    case doubleNextAttack
    /// Before each attack action, a Move (Wings of the Night: Move 2).
    case moveBeforeAttack(Int)
    /// After each attack action made while invisible, an attack (Black Knives: Attack 2, Range 3).
    case attackAfterAttackWhileInvisible(value: Int, range: Int)
    /// After each move action made while invisible, an attack on every adjacent enemy (Claws of the Night).
    case attackAdjacentAfterMoveWhileInvisible(Int)
    /// Advantage on every attack, and invisible enemies can be targeted (Eyes of the Night).
    case advantageAndSeeInvisible
    /// Every attack targeting the character has disadvantage this round (Dancing Shadows, Terror Blade).
    case attackersGainDisadvantage

    /// Round bonuses and charge-less persistent cards leave every use in place.
    var isUnlimited: Bool {
        switch self {
        case .roundAttackBonus, .roundAttackBonusWithAdjacentAllies, .experiencePerRetaliate,
             .drawAttacksFromAdjacentAllies, .advantageOncePerTurnVsDoomed, .twoDooms, .roundAttackBonusVsDoomed,
             .advantageAndSeeInvisible, .attackersGainDisadvantage:
            return true
        default: return false
        }
    }
    /// +N on each of the character's heal actions.
    case healBonus(Int)
    /// +N on an attack against an enemy adjacent to none of its allies.
    case bonusAgainstIsolated(Int)
    /// +N on an attack against an enemy that is disarmed, immobilized or stunned.
    case bonusAgainstDisabled(Int)
    /// Double the attack while the character is invisible.
    case doubleWhileInvisible
    /// Double the attack against an enemy adjacent to none of its allies but to one of the character's.
    case doubleAgainstFlanked
    /// On a melee attack, when possible: destroy an adjacent obstacle for +N (Stone Pummel).
    case destroyObstacleForAttack(Int)

    /// By edition and card id.
    static let byCard: [String: ChargedBonus] = [
        "gh-137": .destroyObstacleForAttack(3),                                   // Stone Pummel
        "gh-7": .shieldAgainstAttacks(1),                       // Warding Strength
        "gh-15": .negateDamage,                                 // Juggernaut
        "gh-116": .retaliateAgainstMelee(2),                    // Opposing Strike
        "gh-121": .extraTargetOnRanged,                         // Backup Ammunition
        "gh-88": .bonusAgainstIsolated(2),                      // Single Out
        "gh-90": .doubleWhileInvisible,                         // Smoke Bomb
        "gh-106": .bonusAgainstDisabled(2),                     // Cull the Weak
        "gh-111": .doubleAgainstFlanked,                        // Spring the Trap
        "gh-66": .negateDamage,                                 // Frost Armor
        "gh-69": .attackBonusOrElement(1, .air, 2),            // Crackling Air
        "gh-79": .retaliateAgainstMelee(3),                     // Engulfed in Flames
        "gh-85": .negateAttackAndRetaliate(3, range: 3),        // Cold Front
        "gh-44": .healBonus(2),                                 // Potent Potables
        "gh-346": .negateDamage,                                // Immortality
        "gh-175": .retaliateAgainstMelee(2),                    // Purifying Aura
        "gh-203": .attackPackage(bonus: 3, conditions: [.wound], advantage: true), // Angelic Ascension
        "gh-288": .conditionWhileInvisible(.stun),              // Voice of the Night
        "gh-325": .healedBonus(2),                              // Cauterize
        "gh-441": .healCleanses,                                // Master Physician
        "gh-322": .negateLethal,                                // Defiance of Death
        "gh-277": .endOfTurnInfuse(.dark),                      // Nightfall
        "gh-187": .endOfTurnInfuse(.light),                     // Beacon of Light
        "gh-230": .endOfTurnHealAdjacent(2),                    // Fortified Position
        "gh-13": .roundAttackBonus(1, .any),                    // Wall of Doom
        "gh-127": .roundAttackBonus(1, .ranged),                // Heaving Swing
        "gh-128": .roundAttackBonus(2, .melee),                 // Forceful Storm
        "gh-40": .roundAttackBonusWithAdjacentAllies(1),        // Enhancement Field
        "gh-2": .experiencePerRetaliate,                        // Eye for an Eye
        "gh-98": .negateNextDamage,                             // Trickster's Reversal
        "gh-4": .drawAttacksFromAdjacentAllies,                 // Provoking Roar
        "gh-257": .summonsNegateDamage,                         // Intervening Apparitions
        "gh-358": .doubleCurses,                                // Unending Chant
        "gh-499": .summonHealsAfterAttack(2),                   // Blood Hunger
        "gh-129": .consumeForRange(.air, 2),                    // Nature's Lift
        "gh-298": .consumeForAttack(.air, 1),                   // Foul Wind
        "gh-143": .turnStartAction(ActionModel(type: .heal, value: .int(2),        // Lumbering Bash
                                               subActions: [ActionModel(type: .range, value: .int(2))])),
        "gh-415": .turnStartAction(ActionModel(type: .heal, value: .int(2),        // Triage
                                               subActions: [ActionModel(type: .range, value: .int(1))])),
        "gh-54": .turnEndAction(ActionModel(type: .attack, value: .int(2),         // Auto Turret
                                            subActions: [ActionModel(type: .range, value: .int(5))])),
        "gh-376": .attackOnDoomedDeath(value: 2, range: 5),             // Rain of Arrows
        "gh-383": .transferDoomOnDeath(range: 2),                       // Frightening Curse
        "gh-391": .advantageOncePerTurnVsDoomed,                        // Expose
        "gh-397": .twoDooms,                                            // Inescapable Fate
        "gh-392": .roundAttackBonusVsDoomed(2),                         // Relentless Offensive
        "gh-401": .roundAttackBonusVsDoomed(3),                         // Impending End
        "gh-345": .attackOnDamage(3),                                   // Vengeful Barrage
        "gh-316": .curseAllyForTargets(range: 2, targets: 2),           // Grim Bargain
        "gh-270": .moveBeforeAttack(2),                                 // Wings of the Night
        "gh-261": .attackAfterAttackWhileInvisible(value: 2, range: 3), // Black Knives
        "gh-279": .attackAdjacentAfterMoveWhileInvisible(2),            // Claws of the Night
        "gh-283": .advantageAndSeeInvisible,                            // Eyes of the Night
        "gh-267": .attackersGainDisadvantage,                           // Dancing Shadows
        "gh-275": .attackersGainDisadvantage,                           // Terror Blade
        "gh-53": .turnEndAction(ActionModel(type: .custom,                         // Gas Canister
                                            value: .string("One ally within Range 3 may Recover one of their discarded cards."))),
    ]

    /// The round halves of cards whose other half has its own bonus in `byCard`.
    static let byRoundHalf: [String: ChargedBonus] = [
        "gh-345": .roundAttackBonus(1, .any),                           // Vengeful Barrage: +1 this round
        "gh-316": .doubleNextAttack,                                    // Grim Bargain: double the next attack
    ]

    /// Cards both of whose halves are round bonuses, where `byCard` is the top half's (the other
    /// half is played as printed actions).
    static let topRoundHalves: Set<String> = []
    /// Likewise, where `byCard` is the bottom half's.
    static let bottomRoundHalves: Set<String> = ["gh-13"]            // Wall of Doom: "+1 Attack this round"

    /// The bonus of a card in play — only that of the half it was played for (GH p.25: the two
    /// halves of a card are separate actions). `byCard` holds a card's persistent half, or its
    /// round half when it has no persistent one; `byRoundHalf` the round half of a card that
    /// has both.
    static func bonus(edition: String, card: AbilityModel, top: Bool) -> ChargedBonus? {
        guard let cardId = card.cardId else { return nil }
        let key = "\(edition)-\(cardId)"
        let mine = PlayerTurnController.markers(in: (top ? card.actions : card.bottomActions) ?? [])
        let other = PlayerTurnController.markers(in: (top ? card.bottomActions : card.actions) ?? [])
        if mine.contains("persistent") {
            // Both halves persistent (the Doomstalker's dooms): the table holds the top's.
            return other.contains("persistent") && !top ? nil : byCard[key]
        }
        guard mine.contains("round") else { return nil }
        if let own = byRoundHalf[key] { return own }
        if other.contains("persistent") { return nil }
        if other.contains("round") {
            return (top ? topRoundHalves : bottomRoundHalves).contains(key) ? byCard[key] : nil
        }
        return byCard[key]
    }

    /// The experience each charge slot gives, in order (0 for a plain slot).
    static func slots(of card: AbilityModel) -> [Int] {
        var result: [Int] = []
        func walk(_ actions: [ActionModel]) {
            for action in actions {
                if action.type == .card, let value = action.value?.stringValue {
                    if value == "slot" { result.append(0) }
                    else if value.hasPrefix("slotXp:") { result.append(Int(value.dropFirst("slotXp:".count)) ?? 0) }
                }
                walk(action.subActions ?? [])
            }
        }
        walk((card.actions ?? []) + (card.bottomActions ?? []))
        return result
    }
}

extension BoardCoordinator {

    /// The character's charged bonuses in effect: cards in the active area, and a card whose
    /// persistent half was performed this turn (before it is put away).
    func chargedBonuses(of character: GameCharacter) -> [(cardId: Int, bonus: ChargedBonus)] {
        var cards = character.activeCards
        if let turn = activePlayerTurn, turn.characterID == character.id {
            cards += turn.persistentCardsThisTurn.filter { !cards.contains($0) }
            cards.removeAll { turn.usedUpThisTurn.contains($0) }
        }
        // A doom card in play is its doom (bottom half), not its top half's bonus.
        let dooming = Set(activeDooms.filter { $0.doom.characterID == character.id }.map(\.doom.cardId))
        return cards.filter { !dooming.contains($0) }.compactMap { id in
            bonusInPlay(id, of: character).map { (id, $0) }
        }
    }

    /// The bonus a card in play gives: that of the half it is in play for.
    func bonusInPlay(_ cardId: Int, of character: GameCharacter) -> ChargedBonus? {
        guard let card = gameManager?.characterManager.abilities(for: character).first(where: { $0.cardId == cardId }) else { return nil }
        return ChargedBonus.bonus(edition: character.edition, card: card, top: isTopHalfInPlay(cardId, of: character))
    }

    /// Whether a card in play (in the active area, or played this turn) is there for its top half.
    /// Read from the card where only one half can be in play, or the two differ in kind
    /// (persistent or round); where both are the same kind, from what was recorded as it was played.
    func isTopHalfInPlay(_ cardId: Int, of character: GameCharacter) -> Bool {
        let turn = activePlayerTurn?.characterID == character.id ? activePlayerTurn : nil
        if let turn, !character.activeCards.contains(cardId), let top = turn.halfInPlayThisTurn[cardId] {
            return top
        }
        let recorded = !character.bottomHalvesInPlay.contains(cardId)
        guard let card = gameManager?.characterManager.abilities(for: character).first(where: { $0.cardId == cardId }) else { return recorded }
        let kinds: Set<String> = ["persistent", "round"]
        let top = PlayerTurnController.markers(in: card.actions ?? []).intersection(kinds)
        let bottom = PlayerTurnController.markers(in: card.bottomActions ?? []).intersection(kinds)
        if top.isEmpty != bottom.isEmpty { return bottom.isEmpty }
        let round = character.roundBonusCards.contains(cardId) || turn?.roundCardsThisTurn.contains(cardId) == true
        let kind = round ? "round" : "persistent"
        if top.contains(kind) != bottom.contains(kind) { return top.contains(kind) }
        return recorded
    }

    func chargedBonuses(of piece: PieceID) -> [(cardId: Int, bonus: ChargedBonus)] {
        guard case .character(let id) = piece,
              let character = gameManager?.game.characters.first(where: { $0.id == id }) else { return [] }
        return chargedBonuses(of: character)
    }

    /// Mark one charge of a bonus: experience for an XP slot, and the card leaves the active
    /// area once every charge is marked.
    func useCharge(_ cardId: Int, of character: GameCharacter) {
        let roundHalf = character.roundBonusCards.contains(cardId) || activePlayerTurn?.roundCardsThisTurn.contains(cardId) == true
        if bonusInPlay(cardId, of: character)?.isUnlimited == true { return }
        guard let card = gameManager?.characterManager.abilities(for: character).first(where: { $0.cardId == cardId }) else { return }
        // A round half's single use (Grim Bargain's doubled attack): the other half's slots aren't its.
        let slots = roundHalf && ChargedBonus.byRoundHalf["\(character.edition)-\(cardId)"] != nil ? [] : ChargedBonus.slots(of: card)
        let used = character.bonusChargesUsed[cardId, default: 0]
        if used < slots.count, slots[used] > 0 {
            character.experience += slots[used]
            log("\(name(.character(character.id))) gains \(slots[used]) XP", category: .info)
        }
        let nowUsed = used + 1
        guard nowUsed >= slots.count else {
            character.bonusChargesUsed[cardId] = nowUsed
            return
        }
        character.bonusChargesUsed[cardId] = nil
        log("\(card.name ?? "The card")\u{2019}s bonus is used up", category: .info)
        if character.activeCards.contains(cardId) {
            character.removeFromActiveArea(cardId)
        } else if let turn = activePlayerTurn, turn.characterID == character.id {
            turn.usedUpThisTurn.insert(cardId)
        }
    }

    /// The first bonus matching `matches`, with its card — for a bonus on "your next N Attack
    /// (Heal) actions", which is counted in at the start of the action and whose charge is marked
    /// only once the action is performed (`useCharge`): an action with no target marks none.
    func firstCharge(of piece: PieceID, where matches: (ChargedBonus) -> Bool) -> (cardId: Int, bonus: ChargedBonus)? {
        guard case .character(let id) = piece,
              let character = gameManager?.game.characters.first(where: { $0.id == id }) else { return nil }
        return chargedBonuses(of: character).first(where: { matches($0.bonus) })
    }

    /// Mark a charge of the first bonus matching `matches`, returning it.
    @discardableResult
    func useFirstCharge(of piece: PieceID, where matches: (ChargedBonus) -> Bool) -> ChargedBonus? {
        guard case .character(let id) = piece,
              let character = gameManager?.game.characters.first(where: { $0.id == id }),
              let found = chargedBonuses(of: character).first(where: { matches($0.bonus) }) else { return nil }
        useCharge(found.cardId, of: character)
        return found.bonus
    }

    /// Whether the character would suffer no damage from `amount` (Juggernaut, Frost Armor,
    /// Trickster's Reversal; Defiance of Death when it would be lethal), without using a charge.
    func negatesDamage(_ piece: PieceID, amount: Int) -> Bool {
        let health = entity(for: piece)?.health ?? 0
        return chargedBonuses(of: piece).contains {
            $0.bonus == .negateDamage || $0.bonus == .negateNextDamage || ($0.bonus == .negateLethal && amount >= health)
        }
    }

    /// Conditions the attacker's bonuses add to the one attack about to be made, marking a charge
    /// of each: Voice of the Night's Stun "on your next five attacks while invisible" — a charge
    /// for every enemy attacked, not one for a whole Target 3 or area attack.
    func conditionsFromBonuses(attacker: PieceID) -> [ConditionName] {
        guard isConditionActive(.invisible, on: attacker),
              case .conditionWhileInvisible(let condition)? = useFirstCharge(of: attacker, where: {
                  if case .conditionWhileInvisible = $0 { return true }; return false }) else { return [] }
        log("\(name(attacker))\u{2019}s bonus: \(GameText.conditionName(condition))", category: .attack)
        return [condition]
    }

    /// Master Physician: "Before your next six Heal actions, remove all negative conditions on
    /// the healed figure(s)" — a charge for each Heal action, however many figures it heals.
    /// A heal made outside a card's Heal step (an item's, a rest's) is an action of its own.
    func healCleanses(by source: PieceID) -> Bool {
        let spend = { self.useFirstCharge(of: source, where: { $0 == .healCleanses }) != nil }
        guard let turn = activePlayerTurn, PieceID.character(turn.characterID) == source, turn.performingHeal else { return spend() }
        if let decided = turn.healActionCleanses { return decided }
        let cleanses = spend()
        turn.healActionCleanses = cleanses
        return cleanses
    }

    /// The card whose charge would take `amount` damage for the character, by name.
    func negatingBonusName(_ piece: PieceID, amount: Int) -> String? {
        guard case .character(let id) = piece, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == id }) else { return nil }
        let found = chargedBonuses(of: character).first {
            $0.bonus == .negateDamage || $0.bonus == .negateNextDamage || ($0.bonus == .negateLethal && amount >= character.health)
        }
        guard let found else { return nil }
        return gameManager.characterManager.abilities(for: character).first { $0.cardId == found.cardId }?.name ?? "A bonus in play"
    }

    /// Provoking Roar: an enemy attacking an ally beside a provoking character attacks that
    /// character instead, whatever the range. Returns who is really attacked.
    func provokedTarget(of attacker: PieceID, aimingAt target: PieceID) -> PieceID {
        guard let game = gameManager?.game, let position = boardState.piecePositions[target] else { return target }
        for character in game.characters {
            let provoker = PieceID.character(character.id)
            guard provoker != target, areEnemies(attacker, provoker), areAllies(provoker, target),
                  let theirs = boardState.piecePositions[provoker], boardState.areAdjacent(theirs, position),
                  chargedBonuses(of: character).contains(where: { $0.bonus == .drawAttacksFromAdjacentAllies }) else { continue }
            log("\(name(provoker)) draws the attack meant for \(name(target))", category: .attack)
            return provoker
        }
        return target
    }

    /// This round's attack bonuses for an attack by `attacker` (its own, and Enhancement Field
    /// from an ally beside it).
    func roundAttackBonus(for attacker: PieceID, ranged: Bool) -> Int {
        guard let game = gameManager?.game else { return 0 }
        var total = 0
        for (_, bonus) in chargedBonuses(of: attacker) {
            switch bonus {
            case .roundAttackBonus(let n, let reach) where reach == .any || (reach == .ranged) == ranged:
                total += n
            case .roundAttackBonusWithAdjacentAllies(let n):
                total += n
            default: break
            }
        }
        guard let position = boardState.piecePositions[attacker] else { return total }
        for character in game.characters where PieceID.character(character.id) != attacker {
            guard let theirs = boardState.piecePositions[.character(character.id)],
                  boardState.areAdjacent(theirs, position), areAllies(attacker, .character(character.id)) else { continue }
            for (_, bonus) in chargedBonuses(of: character) {
                if case .roundAttackBonusWithAdjacentAllies(let n) = bonus { total += n }
            }
        }
        return total
    }

    /// Bonuses printed in the text of the attack being made, judged per target: "+2 when the
    /// target is adjacent to any of your allies", "+1 for each negative condition on the target",
    /// "XP +1 for each enemy targeted" (Backstab, Submissive Affliction, Net Shooter…).
    func attackTextBonus(_ texts: [String], attacker: PieceID, target: PieceID) -> (attack: Int, experience: Int) {
        guard let targetPos = boardState.piecePositions[target], let defender = entity(for: target) else { return (0, 0) }
        let neighbours = boardState.neighbors(of: targetPos).compactMap { boardState.piece(at: $0) }
        let attackersAllies = neighbours.filter { $0 != attacker && areAllies($0, attacker) }.count
        let isolated = !neighbours.contains { $0 != target && areAllies($0, target) }
        let negatives = defender.entityConditions.filter { $0.name.isNegative && !$0.expired }.count
        func number(_ pattern: String, in text: String) -> Int {
            guard let match = text.firstMatch(of: try! Regex(pattern)), let value = match.output[1].substring else { return 0 }
            return Int(value) ?? 0
        }
        var attack = 0, experience = 0
        for text in texts {
            let bonus = number(#"\+(\d+) attack"#, in: text), xp = number(#"xp \+(\d+)"#, in: text)
            if text.contains("if the target is doomed") {
                // Swift Trickery, Press the Attack.
                if isDoomed(target) { attack += bonus; experience += xp }
            } else if text.contains("if the target is undamaged") {
                // Fresh Kill.
                if defender.health >= defender.maxHealth { attack += bonus; experience += xp }
            } else if text.contains("adjacent to any of your allies") {
                if attackersAllies > 0 { attack += bonus; experience += xp }
            } else if text.contains("adjacent to none of its allies") {
                if isolated { attack += bonus; experience += xp }
            } else if text.contains("for each of your allies adjacent to the target") {
                attack += bonus * attackersAllies
            } else if text.contains("double the shield value of the target") {
                attack += 2 * shield(of: target)
            } else if text.contains("for each negative condition on the target") {
                attack += bonus * negatives
                experience += xp * negatives
            } else if text.contains("for each enemy targeted") {
                experience += max(1, xp)
            }
        }
        return (attack, experience)
    }

    /// End-of-turn bonuses: Nightfall and Beacon of Light infuse, Fortified Position heals.
    func applyEndOfTurnBonuses(_ turn: PlayerTurnController) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == turn.characterID }),
              let game = gameManager?.game else { return }
        let me = PieceID.character(character.id)
        for (cardId, bonus) in chargedBonuses(of: character) {
            switch bonus {
            case .endOfTurnInfuse(let element):
                guard game.elementBoard.first(where: { $0.type == element })?.state != .strong else { continue }
                game.infuseElement(element)
                log("\(name(me)) infuses \(GameText.elementName(element))", category: .element)
                useCharge(cardId, of: character)
            case .endOfTurnHealAdjacent(let amount):
                for ally in alliesInRange(of: me, range: 1, includeSelf: false).sorted() {
                    let healed = heal(ally, amount: amount, source: me)
                    log(healLine(me, healed: ally, for: healed), category: .heal)
                }
                useCharge(cardId, of: character)
            default:
                continue
            }
        }
    }

    /// The attack value against `target` with the attacker's conditional bonuses (Single Out,
    /// Cull the Weak, Smoke Bomb, Spring the Trap), marking a charge of each that applies.
    func attackValueWithBonuses(_ value: Int, attacker: PieceID, target: PieceID) -> Int {
        guard case .character = attacker, let targetPos = boardState.piecePositions[target] else { return value }
        let neighbours = boardState.neighbors(of: targetPos).compactMap { boardState.piece(at: $0) }
        // The target's allies are the figures on its side; the attacker's, those on theirs.
        let isolated = !neighbours.contains { $0 != target && areAllies($0, target) }
        let flanked = isolated && neighbours.contains { $0 != attacker && areAllies($0, attacker) }
        let disabled = [.disarm, .immobilize, .stun].contains { isConditionActive($0, on: target) }
        var result = value
        for (_, bonus) in chargedBonuses(of: attacker) {
            switch bonus {
            case .bonusAgainstIsolated(let n) where isolated:
                result += n
                useFirstCharge(of: attacker) { $0 == bonus }
            case .bonusAgainstDisabled(let n) where disabled:
                result += n
                useFirstCharge(of: attacker) { $0 == bonus }
            case .doubleWhileInvisible where isConditionActive(.invisible, on: attacker):
                result *= 2
                useFirstCharge(of: attacker) { $0 == bonus }
            case .doubleAgainstFlanked where flanked:
                result *= 2
                useFirstCharge(of: attacker) { $0 == bonus }
            case .attackBonusOrElement(let n, _, _):
                // Crackling Air: "on your next four attacks", so a charge for each target.
                let turn = activePlayerTurn.flatMap { PieceID.character($0.characterID) == attacker ? $0 : nil }
                result += turn?.bonusPerAttack ?? n
                useFirstCharge(of: attacker) { $0 == bonus }
            case .destroyObstacleForAttack(let n):
                // "When possible": a melee attack with an obstacle beside the character.
                guard let attackerPos = boardState.piecePositions[attacker], boardState.areAdjacent(attackerPos, targetPos),
                      let obstacle = boardState.neighbors(of: attackerPos).sorted().first(where: isDestructibleObstacle)
                else { break }
                boardState.removeObstacle(at: obstacle)
                boardScene?.removeOverlaySprite(at: obstacle, offsetCol: offsetCol, offsetRow: offsetRow)
                log("\(name(attacker)) destroys an obstacle", category: .attack)
                result += n
                useFirstCharge(of: attacker) { $0 == bonus }
            default:
                break
            }
        }
        if result != value { log("\(name(attacker))\u{2019}s bonus: Attack \(result)", category: .attack) }
        return result
    }
}

// MARK: - Ending a bonus

extension BoardCoordinator {

    /// A card in a character's active area, as the party panel lists it.
    struct ActiveCard: Identifiable, Equatable {
        let id: Int
        let name: String
        /// Charges not yet marked, for a bonus with use circles.
        var usesLeft: Int? = nil
        /// A bonus that ends with the round anyway.
        var forTheRound = false
        /// Where the card goes when it leaves play: the lost pile, or the discard pile.
        var lost = false
        /// The summons that leave the board with it.
        var summons: [String] = []

        /// The panel's line: "Frost Armor · 1 left", "Wall of Doom · this round".
        var line: String {
            if let usesLeft { return "\(name) \u{00B7} \(usesLeft) left" }
            return forTheRound ? "\(name) \u{00B7} this round" : name
        }

        /// What ending it does, for the question asked before it is ended.
        var consequence: String {
            let pile = "The card goes to the \(lost ? "lost" : "discard") pile and its bonus ends."
            guard !summons.isEmpty else { return pile }
            return pile + " \(GameText.list(summons)) \(summons.count == 1 ? "leaves" : "leave") the board."
        }
    }

    /// The cards in a character's active area, in the order they were played.
    func activeCards(of character: GameCharacter) -> [ActiveCard] {
        guard let gameManager, !character.exhausted else { return [] }
        let deck = gameManager.characterManager.abilities(for: character)
        return character.activeCards.compactMap { cardId in
            guard let card = deck.first(where: { $0.cardId == cardId }) else { return nil }
            var entry = ActiveCard(id: cardId, name: card.name ?? "Card \(cardId)")
            entry.forTheRound = character.roundBonusCards.contains(cardId)
            entry.lost = character.lostWhenRemoved.contains(cardId)
            entry.summons = summons(broughtBy: card, of: character).map { name(.summon(id: $0.id)) }
            let slots = ChargedBonus.slots(of: card)
            if !entry.forTheRound, !slots.isEmpty, bonusInPlay(cardId, of: character)?.isUnlimited != true {
                entry.usesLeft = max(0, slots.count - character.bonusChargesUsed[cardId, default: 0])
            }
            return entry
        }
    }

    /// The living summons a card in play brought (by the half it is in play for).
    private func summons(broughtBy card: AbilityModel, of character: GameCharacter) -> [GameSummon] {
        guard let cardId = card.cardId else { return [] }
        let names = Self.summonNames(in: (isTopHalfInPlay(cardId, of: character) ? card.actions : card.bottomActions) ?? [])
        return character.summons.filter { !$0.dead && names.contains($0.name) }
    }

    /// A player may at any time move a card from their active area to its pile, ending its
    /// bonus (GH p.25): the lost pile if the action it was played for has the lost icon, the
    /// discard pile if not. A summon's card leaving play takes its summon off the board (p.26),
    /// and a Doom's takes its token off the enemy.
    @discardableResult
    func endActiveBonus(_ cardId: Int, of character: GameCharacter) -> Bool {
        guard let gameManager, !character.exhausted, character.activeCards.contains(cardId) else { return false }
        gameManager.characterManager.onBeforeMutate?()
        let me = PieceID.character(character.id)
        let card = gameManager.characterManager.abilities(for: character).first { $0.cardId == cardId }
        let cardName = card?.name ?? "a card"
        let lost = character.lostWhenRemoved.contains(cardId)
        log("\(name(me)) ends \(cardName): the card goes to the \(lost ? "lost" : "discard") pile", category: .info)
        if let doomed = activeDooms.first(where: { $0.doom.characterID == character.id && $0.doom.cardId == cardId }) {
            endDoom(doomed.doom, on: doomed.piece, reason: "its card left play")
            return true
        }
        for summon in card.map({ summons(broughtBy: $0, of: character) }) ?? [] {
            let piece = PieceID.summon(id: summon.id)
            log("\(name(piece)) leaves the board", category: .info)
            summon.dead = true
            removePieceFromBoard(piece)
        }
        character.removeFromActiveArea(cardId)
        // Put away in the turn it was played, it no longer counts as in play for that turn.
        if let turn = activePlayerTurn, turn.characterID == character.id {
            turn.persistentCardsThisTurn.removeAll { $0 == cardId }
            turn.roundCardsThisTurn.removeAll { $0 == cardId }
        }
        if lost { boardScene?.play(.lose) }
        boardScene?.refreshStatus(of: me)
        return true
    }
}

