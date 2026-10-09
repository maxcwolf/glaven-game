import Foundation

/// Items used on the board (GH p.26): on the character's own turn, when the item's moment comes
/// — during their move, during their attack, or any time in their turn. A spent item is
/// refreshed by a long rest; a consumed one is gone for the scenario.
///
/// "To a single attack" is played as the whole attack action for now. Items whose effects the
/// board doesn't play yet are still marked used by hand on the character sheet.
struct BoardItemEffect: Equatable {
    enum Moment: Equatable {
        case turn, move, attack, meleeAttack, rangedAttack
        /// A melee or ranged attack on a single target (not an area or a multi-target attack).
        case singleMeleeAttack, singleRangedAttack
    }

    enum Part: Equatable {
        case extraMove(Int)
        case jump
        case selfCondition(ConditionName)
        case advantage
        case ignoreShields
        case attackConditions([ConditionName])
        case attackBonus(Int)
        case pierce(Int)
        case heal(Int)
        /// Recover up to this many discarded cards to the hand.
        case recover(Int)
        case infuse(ElementType)
        /// Refresh every spent item.
        case refreshSpent
        case removeNegativeConditions
        case adjacentEnemies(ConditionName)
        case enemiesInRange(ConditionName, Int)
        case selfAndAdjacentAllies(ConditionName)
        /// More range for the attack being targeted.
        case extraRange(Int)
        case sufferDamage(Int)
        case loot(Int)
        /// Infuse this many elements of the player's choosing.
        case infuseAny(Int)
        /// Turn the attack into the item's printed area (Battle-Axe, Long Spear…).
        case areaFromItem
        /// Remove one negative condition of the player's choosing.
        case removeOneNegativeCondition
    }

    let moment: Moment
    let parts: [Part]
    /// Elements the item consumes to work ("wild": any one); it can't be used without them.
    var consumes: [ElementType] = []

    init(_ moment: Moment, _ parts: Part...) {
        self.moment = moment
        self.parts = parts
    }

    init(_ moment: Moment, consuming elements: [ElementType], _ parts: Part...) {
        self.moment = moment
        self.parts = parts
        self.consumes = elements
    }

    /// The board's effects, by item key.
    static let byItem: [String: BoardItemEffect] = [
        "gh-1": .init(.move, .extraMove(2)),                                  // Boots of Striding
        "gh-2": .init(.move, .jump),                                          // Winged Shoes
        "gh-5": .init(.turn, .selfCondition(.invisible)),                     // Cloak of Invisibility
        "gh-6": .init(.attack, .advantage),                                   // Eagle-Eye Goggles
        "gh-9": .init(.rangedAttack, .ignoreShields),                         // Piercing Bow
        "gh-10": .init(.meleeAttack, .attackConditions([.stun])),             // War Hammer
        "gh-11": .init(.meleeAttack, .attackConditions([.poison])),           // Poison Dagger
        "gh-12": .init(.turn, .heal(3)),                                      // Minor Healing Potion
        "gh-13": .init(.turn, .recover(2)),                                   // Minor Stamina Potion
        "gh-14": .init(.attack, .attackBonus(1)),                             // Minor Power Potion
        "gh-19": .init(.rangedAttack, .attackConditions([.immobilize])),      // Weighted Net
        "gh-21": .init(.attack, .attackConditions([.stun])),                  // Stun Powder
        "gh-24": .init(.turn, .heal(1)),                                      // Amulet of Life
        "gh-25": .init(.meleeAttack, .attackConditions([.wound])),            // Jagged Sword
        "gh-27": .init(.turn, .heal(5)),                                      // Major Healing Potion
        "gh-28": .init(.turn, .refreshSpent),                                 // Moon Earring
        "gh-34": .init(.turn, .recover(3)),                                   // Major Stamina Potion
        "gh-36": .init(.move, .extraMove(3)),                                 // Boots of Dashing
        "gh-41": .init(.attack, .attackBonus(2)),                             // Major Power Potion
        "gh-49": .init(.turn, .refreshSpent, .heal(3)),                       // Sun Earring
        "gh-53": .init(.meleeAttack, .attackConditions([.curse])),            // Black Knife
        "gh-55": .init(.turn, .heal(7)),                                      // Super Healing Potion
        "gh-62": .init(.attack, .attackConditions([.stun, .poison, .curse])), // Doom Powder
        "gh-63": .init(.turn, .selfAndAdjacentAllies(.strengthen)),           // Lucky Eye
        "gh-64": .init(.move, .extraMove(4)),                                 // Boots of Sprinting
        "gh-69": .init(.turn, .refreshSpent, .heal(3), .recover(2)),          // Star Earring
        "gh-83": .init(.turn, .infuse(.ice)),                                 // Wand of Frost
        "gh-84": .init(.turn, .infuse(.air)),                                 // Wand of Storms
        "gh-85": .init(.turn, .infuse(.fire)),                                // Wand of Infernos
        "gh-86": .init(.turn, .infuse(.earth)),                               // Wand of Tremors
        "gh-87": .init(.turn, .infuse(.light)),                               // Wand of Brilliance
        "gh-88": .init(.turn, .infuse(.dark)),                                // Wand of Darkness
        "gh-90": .init(.turn, .removeNegativeConditions),                     // Major Cure Potion
        "gh-96": .init(.move, .extraMove(3), .jump),                          // Rocket Boots
        "gh-112": .init(.meleeAttack, .attackBonus(2), .pierce(2)),           // Ancient Drill
        "gh-114": .init(.rangedAttack, .attackConditions([.poison, .muddle])), // Staff of Xorn
        "gh-119": .init(.turn, .adjacentEnemies(.curse)),                     // Skull of Hatred
        "gh-126": .init(.turn, .adjacentEnemies(.poison)),                    // Remote Spider
        "gh-128": .init(.turn, .enemiesInRange(.muddle, 2)),                  // Black Censer
        "gh-143": .init(.turn, .selfCondition(.invisible), .infuse(.dark)),   // Smoke Elixir
        "gh-31": .init(.rangedAttack, .extraRange(1)),                        // Hawk Helm
        "gh-59": .init(.rangedAttack, .extraRange(2)),                        // Telescopic Lens
        "gh-37": .init(.attack, consuming: [.wild], .attackBonus(1)),         // Robes of Evocation
        "gh-54": .init(.rangedAttack, consuming: [.wild], .attackBonus(1)),   // Staff of Eminence
        "gh-77": .init(.meleeAttack, consuming: [.ice], .attackBonus(2)),     // Frigid Blade
        "gh-78": .init(.meleeAttack, consuming: [.air], .attackBonus(2)),     // Storm Blade
        "gh-79": .init(.meleeAttack, consuming: [.fire], .attackBonus(2)),    // Inferno Blade
        "gh-80": .init(.meleeAttack, consuming: [.earth], .attackBonus(2)),   // Tremor Blade
        "gh-81": .init(.meleeAttack, consuming: [.light], .attackBonus(2)),   // Brilliant Blade
        "gh-82": .init(.meleeAttack, consuming: [.dark], .attackBonus(2)),    // Night Blade
        "gh-121": .init(.turn, consuming: [.dark], .infuse(.light)),          // Orb of Dawn
        "gh-122": .init(.turn, consuming: [.light], .infuse(.dark)),          // Orb of Twilight
        "gh-102": .init(.rangedAttack, .sufferDamage(3), .attackBonus(1)),    // Sacrificial Robes
        "gh-117": .init(.meleeAttack, .sufferDamage(2), .attackBonus(1)),     // Bloody Axe
        "gh-127": .init(.turn, .loot(1)),                                     // Giant Remote Spider
        "gh-20": .init(.turn, .infuseAny(1)),                                 // Minor Mana Potion
        "gh-48": .init(.turn, .infuseAny(2)),                                 // Major Mana Potion
        "gh-118": .init(.turn, .infuseAny(1)),                                // Staff of Elements
        "gh-75": .init(.turn, consuming: [.wild], .infuseAny(1)),             // Circlet of Elements
        "gh-89": .init(.turn, .removeOneNegativeCondition),                   // Minor Cure Potion
        "gh-18": .init(.singleMeleeAttack, .areaFromItem),                    // Battle-Axe
        "gh-26": .init(.singleMeleeAttack, .areaFromItem),                    // Long Spear
        "gh-47": .init(.singleMeleeAttack, .areaFromItem),                    // Reaping Scythe
        "gh-33": .init(.singleRangedAttack, .areaFromItem),                   // Volatile Bomb
    ]
}

/// Items that are always on (no use, no spending).
enum PassiveItems {
    /// The basic Attack 2 / Move 2 becomes stronger (Versatile Dagger, Balanced Blade;
    /// Comfortable Shoes, Serene Sandals).
    static let defaultAttack: [String: Int] = ["gh-40": 3, "gh-67": 4]
    static let defaultMove: [String: Int] = ["gh-29": 3, "gh-57": 4]
    /// Boots of Levitation, Cloak of Phasing.
    static let flying: Set<String> = ["gh-71", "gh-58"]
    /// Heavy Basinet; Protective Charm; Drakescale Armor.
    static let immunities: [String: [ConditionName]] = [
        "gh-38": [.stun, .muddle], "gh-52": [.poison, .wound], "gh-103": [.poison, .wound],
    ]
    /// Silent Stiletto: every melee attack gains Pierce 1.
    static let meleePierce: [String: Int] = ["gh-137": 1]
    /// Mask of Terror: every melee attack gains Push 1.
    static let meleePush: [String: Int] = ["gh-66": 1]

    /// Heavy Greaves: no forced movement.
    static let unmovable = "gh-22"
    /// Drakescale Helm: muddle becomes strengthen.
    static let muddleToStrengthen = "gh-108"
    /// Chain Hood: Shield 1 while adjacent to three or more monsters.
    static let chainHood = "gh-76"
    /// Kills on the wearer's own turn: Necklace of Teeth heals 1, Imposing Blade gives Shield 1
    /// for the round.
    static let necklaceOfTeeth = "gh-106"
    static let imposingBlade = "gh-134"

    /// Drakescale Boots, Magma Waders: hazardous terrain does no harm.
    static let hazardProof: Set<String> = ["gh-98", "gh-99"]
    static let magmaWaders = "gh-99"
    /// At the end of the wearer's turn, by hexes moved: Shoes of Happiness (6+: 1 experience),
    /// Endurance Footwraps (4+: Heal 1), Steel Sabatons (1 or fewer: Shield 1 for the round).
    static let shoesOfHappiness = "gh-72"
    static let enduranceFootwraps = "gh-97"
    static let steelSabatons = "gh-50"
    /// Horned Helm: after moving 4 or more hexes, +1 on the next melee attack this turn.
    static let hornedHelm = "gh-107"

    static func ignoresHazards(_ items: [String]) -> Bool { items.contains(where: hazardProof.contains) }

    /// Halberd: a single-target melee attack reaches any enemy within 2 hexes.
    static let halberd = "gh-68"

    static func defaultAttack(for items: [String]) -> Int { items.compactMap { defaultAttack[$0] }.max() ?? 2 }
    static func defaultMove(for items: [String]) -> Int { items.compactMap { defaultMove[$0] }.max() ?? 2 }
    static func flies(_ items: [String]) -> Bool { items.contains(where: flying.contains) }
    static func immune(_ items: [String], to condition: ConditionName) -> Bool {
        items.contains { immunities[$0]?.contains(condition) == true }
    }
    static func meleePierce(for items: [String]) -> Int { items.compactMap { meleePierce[$0] }.reduce(0, +) }
    static func meleePush(for items: [String]) -> Int { items.compactMap { meleePush[$0] }.reduce(0, +) }
}

extension BoardCoordinator {

    /// The acting character's items that can be used right now.
    func usableItems() -> [ItemData] {
        guard let turn = activePlayerTurn, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == turn.characterID }) else { return [] }
        return character.items.compactMap { key -> ItemData? in
            guard !character.spentItems.contains(key), !character.consumedItems.contains(key),
                  let effect = BoardItemEffect.byItem[key], isMoment(effect.moment, for: turn),
                  effect.consumes.isEmpty || gameManager.game.canConsumeElements(effect.consumes),
                  let item = itemData(key) else { return nil }
            return item
        }
    }

    private func isMoment(_ moment: BoardItemEffect.Moment, for turn: PlayerTurnController) -> Bool {
        let me = PieceID.character(turn.characterID)
        switch (moment, interactionMode) {
        case (.turn, .watchingMonsterTurn), (.turn, .placingCharacter):
            return false
        case (.turn, _):
            return turn.phase == .executeTopAction || turn.phase == .executeBottomAction
        case (.move, .selectingMove(let mover, _, _, let teleport, _)):
            return mover == me && !teleport
        case (.attack, .selectingAttackTarget(let attacker, _, _)),
             (.attack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me
        case (.meleeAttack, .selectingAttackTarget(let attacker, _, _)),
             (.meleeAttack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me && turn.currentAttackRange() <= 1
        case (.rangedAttack, .selectingAttackTarget(let attacker, _, _)),
             (.rangedAttack, .selectingMultiAttackTargets(let attacker, _, _, _, _)):
            return attacker == me && turn.currentAttackRange() > 1
        case (.singleMeleeAttack, .selectingAttackTarget(let attacker, _, _)):
            return attacker == me && turn.currentAttackRange() <= 1 && turn.pendingAreaPattern == nil
        case (.singleRangedAttack, .selectingAttackTarget(let attacker, _, _)):
            return attacker == me && turn.currentAttackRange() > 1 && turn.pendingAreaPattern == nil
        default:
            return false
        }
    }

    /// Use an item: its effect now, then it's spent or consumed, and counted for battle goals.
    @discardableResult
    func useItem(_ item: ItemData) -> Bool {
        guard usableItems().contains(where: { $0.itemKey == item.itemKey }),
              let turn = activePlayerTurn, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == turn.characterID }),
              let effect = BoardItemEffect.byItem[item.itemKey] else { return false }
        let me = PieceID.character(character.id)
        gameManager.characterManager.onBeforeMutate?()
        // Items with neither mark (the element blades and orbs) can be used again.
        if item.consumed {
            character.consumedItems.insert(item.itemKey)
        } else if item.spent {
            character.spentItems.insert(item.itemKey)
        }
        gameManager.scenarioStatsManager.recordItemUse(by: character.name)
        log("\(name(me)) uses \(item.name)", category: .info)

        if !effect.consumes.isEmpty, let used = gameManager.game.consumeElements(effect.consumes) {
            log("\(name(me)) consumes \(GameText.list(used.map(GameText.elementName)))", category: .element)
        }
        for part in effect.parts {
            perform(part, of: item, character: character, turn: turn)
        }
        return true
    }

    private func perform(_ part: BoardItemEffect.Part, of item: ItemData, character: GameCharacter,
                         turn: PlayerTurnController) {
        let me = PieceID.character(character.id)
        switch part {
        case .extraMove(let extra):
            if case .selectingMove(_, let range, _, _, let mode) = interactionMode {
                beginMoveAction(pieceID: me, moveRange: range + extra, mode: mode)
            }
        case .jump:
            if case .selectingMove(_, let range, _, _, let mode) = interactionMode, mode != .fly {
                beginMoveAction(pieceID: me, moveRange: range, mode: .jump)
            }
        case .selfCondition(let condition):
            applyCondition(condition, to: me)
        case .advantage:
            turn.pendingAdvantage = true
        case .ignoreShields:
            turn.pendingPierce += 99
        case .attackConditions(let conditions):
            turn.pendingConditions.append(contentsOf: conditions)
        case .attackBonus(let bonus):
            turn.addToAttack(bonus)
        case .pierce(let amount):
            turn.pendingPierce += amount
        case .heal(let amount):
            let healed = heal(me, amount: amount, source: me)
            log("\(name(me)) heals for \(healed)", category: .heal, trace: "Heal \(amount), self")
        case .recover(let count):
            if character.discardedCards.count <= count {
                recover(character.discardedCards, for: character)
            } else {
                pendingRecovery = PendingRecovery(characterID: character.id, count: count, itemName: item.name)
            }
        case .infuse(let element):
            gameManager?.game.infuseElement(element)
            log("\(name(me)) infuses \(GameText.elementName(element))", category: .element)
        case .refreshSpent:
            character.spentItems.removeAll()
            log("\(name(me)) refreshes their spent items", category: .info)
        case .removeNegativeConditions:
            character.entityConditions.removeAll { $0.name.isNegative && !$0.permanent }
            boardScene?.refreshStatus(of: me)
            log("\(name(me)) removes negative conditions", category: .condition)
        case .adjacentEnemies(let condition):
            applyConditionToAllEnemies(from: me, condition: condition, range: 1)
        case .enemiesInRange(let condition, let range):
            applyConditionToAllEnemies(from: me, condition: condition, range: range)
        case .selfAndAdjacentAllies(let condition):
            applyCondition(condition, to: me)
            applyConditionToAllAllies(from: me, condition: condition, range: 1)
        case .extraRange(let extra):
            switch interactionMode {
            case .selectingAttackTarget(_, let range, _):
                turn.extendAttackRange(by: extra)
                beginAttackAction(pieceID: me, range: range + extra)
            case .selectingMultiAttackTargets(_, let range, _, let count, let selected) where selected.isEmpty:
                turn.extendAttackRange(by: extra)
                beginAttackAction(pieceID: me, range: range + extra, targetCount: count)
            default:
                break
            }
        case .sufferDamage(let amount):
            log("\(name(me)) suffers \(amount) damage", category: .damage)
            sufferDamage(amount, to: me)
        case .loot(let range):
            collectLootInRange(pieceID: me, range: range)
        case .areaFromItem:
            guard let pattern = item.actions?.first(where: { $0.type == .area })?.value?.stringValue,
                  case .selectingAttackTarget(_, let range, _) = interactionMode else { break }
            turn.setAreaPattern(pattern)
            beginAttackAction(pieceID: me, range: range)
        case .infuseAny(let count):
            pendingElementChoice = PendingElementChoice(characterID: character.id, count: count, itemName: item.name)
        case .removeOneNegativeCondition:
            let negatives = character.entityConditions.filter { $0.name.isNegative && !$0.permanent }.map(\.name)
            if negatives.count == 1 {
                removeCondition(negatives[0], from: character)
            } else if negatives.count > 1 {
                pendingConditionRemoval = PendingConditionRemoval(characterID: character.id, options: negatives,
                                                                  itemName: item.name)
            }
        }
    }

    /// Infusing elements of the player's choosing (Mana Potions, Staff of Elements).
    struct PendingElementChoice: Identifiable, Equatable {
        let id = UUID()
        let characterID: String
        let count: Int
        let itemName: String
    }

    /// Called from the picker: infuse the chosen elements (at most the pending count, each once).
    func resolveElementChoice(_ elements: [ElementType]) {
        guard let pending = pendingElementChoice, let game = gameManager?.game else { return }
        pendingElementChoice = nil
        var chosen: [ElementType] = []
        for element in elements where element != .wild && !chosen.contains(element) && chosen.count < pending.count {
            chosen.append(element)
        }
        for element in chosen { game.infuseElement(element) }
        if !chosen.isEmpty {
            log("\(name(.character(pending.characterID))) infuses \(GameText.list(chosen.map(GameText.elementName)))",
                category: .element)
        }
    }

    /// Removing one negative condition of the player's choosing (Minor Cure Potion).
    struct PendingConditionRemoval: Identifiable, Equatable {
        let id = UUID()
        let characterID: String
        let options: [ConditionName]
        let itemName: String
    }

    func resolveConditionRemoval(_ condition: ConditionName?) {
        guard let pending = pendingConditionRemoval else { return }
        pendingConditionRemoval = nil
        guard let condition, pending.options.contains(condition),
              let character = gameManager?.game.characters.first(where: { $0.id == pending.characterID }) else { return }
        removeCondition(condition, from: character)
    }

    private func removeCondition(_ condition: ConditionName, from character: GameCharacter) {
        character.entityConditions.removeAll { $0.name == condition && !$0.permanent }
        boardScene?.refreshStatus(of: .character(character.id))
        log("\(name(.character(character.id))) is no longer \(GameText.conditionName(condition).lowercased())", category: .condition)
    }

    // MARK: - Initiative

    /// Boots of Speed (10) and Boots of Quickness (20): after every card is revealed, the
    /// wearer's leading initiative may go up or down by that much.
    static let initiativeBoots: [String: Int] = ["gh-15": 10, "gh-43": 20]

    struct PendingInitiativeChange: Identifiable, Equatable {
        let id = UUID()
        let characterID: String
        let itemKey: String
        let itemName: String
        let amount: Int
        let initiative: Int
    }

    func initiativeItemOffers() -> [PendingInitiativeChange] {
        guard !autoResolvePrompts, let game = gameManager?.game else { return [] }
        return game.activeCharacters.filter { !$0.exhausted && !$0.absent && !$0.longRest }.compactMap { character in
            guard let key = character.items.first(where: { Self.initiativeBoots[$0] != nil }),
                  !character.spentItems.contains(key), let item = itemData(key) else { return nil }
            return PendingInitiativeChange(characterID: character.id, itemKey: key, itemName: item.name,
                                           amount: Self.initiativeBoots[key] ?? 0, initiative: character.initiative)
        }
    }

    func offerNextInitiativeChange() {
        if initiativeOffers.isEmpty {
            pendingInitiativeChange = nil
            buildTurnOrderAndStart()
        } else {
            pendingInitiativeChange = initiativeOffers.removeFirst()
        }
    }

    /// The player's answer: change the initiative by `delta` (± the boots' amount; 0 keeps it).
    func resolveInitiativeChange(_ delta: Int) {
        guard let pending = pendingInitiativeChange, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == pending.characterID }) else { return }
        if delta != 0 && abs(delta) == pending.amount {
            gameManager.characterManager.onBeforeMutate?()
            character.initiative = min(99, max(1, character.initiative + delta))
            character.spentItems.insert(pending.itemKey)
            gameManager.scenarioStatsManager.recordItemUse(by: character.name)
            log("\(name(.character(character.id))) uses \(pending.itemName): initiative \(character.initiative)", category: .round)
        }
        offerNextInitiativeChange()
    }

    /// Items that look at how far the character moved, as their turn ends.
    func applyEndOfTurnItems(_ turn: PlayerTurnController) {
        guard let character = gameManager?.game.characters.first(where: { $0.id == turn.characterID }) else { return }
        let me = PieceID.character(character.id)
        let moved = turn.hexesMoved
        if character.items.contains(PassiveItems.shoesOfHappiness), moved >= 6 {
            character.experience += 1
            log("\(name(me))\u{2019}s Shoes of Happiness: 1 experience", category: .info)
        }
        if character.items.contains(PassiveItems.enduranceFootwraps), moved >= 4 {
            let healed = heal(me, amount: 1, source: me)
            log("\(name(me))\u{2019}s Endurance Footwraps heal \(healed)", category: .heal)
        }
        if character.items.contains(PassiveItems.steelSabatons), moved <= 1 {
            let total = (character.shield?.value?.intValue ?? 0) + 1
            character.shield = ActionModel(type: .shield, value: .int(total))
            boardScene?.refreshStatus(of: me)
            log("\(name(me))\u{2019}s Steel Sabatons: Shield 1 this round", category: .condition)
        }
    }

    /// Necklace of Teeth and Imposing Blade, when the wearer kills an enemy on their own turn.
    func rewardKillOnOwnTurn(_ character: GameCharacter) {
        let me = PieceID.character(character.id)
        if character.items.contains(PassiveItems.necklaceOfTeeth) {
            let healed = heal(me, amount: 1, source: me)
            log("\(name(me))\u{2019}s Necklace of Teeth heals \(healed)", category: .heal)
        }
        if character.items.contains(PassiveItems.imposingBlade) {
            let total = (character.shield?.value?.intValue ?? 0) + 1
            character.shield = ActionModel(type: .shield, value: .int(total))
            boardScene?.refreshStatus(of: me)
            log("\(name(me))\u{2019}s Imposing Blade: Shield 1 this round", category: .condition)
        }
    }

    /// Recovering discarded cards: which ones (up to `count`) go back to the hand.
    struct PendingRecovery: Identifiable, Equatable {
        let id = UUID()
        let characterID: String
        let count: Int
        let itemName: String
    }

    /// Called from the picker with the cards chosen (at most the pending count, all from the discard pile).
    func resolveRecovery(_ cardIds: [Int]) {
        guard let pending = pendingRecovery,
              let character = gameManager?.game.characters.first(where: { $0.id == pending.characterID }) else { return }
        let chosen = Array(cardIds.filter(character.discardedCards.contains).prefix(pending.count))
        pendingRecovery = nil
        recover(chosen, for: character)
    }

    private func recover(_ cardIds: [Int], for character: GameCharacter) {
        guard !cardIds.isEmpty else { return }
        for id in cardIds {
            if let index = character.discardedCards.firstIndex(of: id) {
                character.handCards.append(character.discardedCards.remove(at: index))
            }
        }
        log("\(name(.character(character.id))) recovers \(cardIds.count) card\(cardIds.count == 1 ? "" : "s")", category: .info)
    }

    func itemData(_ key: String) -> ItemData? {
        let parts = key.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let id = Int(parts[1]) else { return nil }
        return gameManager?.editionStore.itemData(id: id, edition: String(parts[0]))
    }
}

// MARK: - When an enemy attacks

/// Items offered while an enemy attacks the character: before the draw (disadvantage), or once
/// the attack would damage (a shield for the attack). Items with use slots (the armours) are
/// spent once every slot is marked.
struct DefenseItem: Equatable {
    let key: String
    /// Offered before the draw: the attacker gains disadvantage.
    var disadvantage = false
    /// Shield for this attack.
    var shield = 0
    /// Retaliate for this attack (an adjacent attacker).
    var retaliate = 0

    static let all: [DefenseItem] = [
        DefenseItem(key: "gh-4", disadvantage: true),              // Leather Armor
        DefenseItem(key: "gh-30", disadvantage: true, shield: 1),  // Studded Leather
        DefenseItem(key: "gh-8", shield: 1),                       // Heater Shield
        DefenseItem(key: "gh-3", shield: 1),                       // Hide Armor (2 uses)
        DefenseItem(key: "gh-23", shield: 1),                      // Chainmail (3)
        DefenseItem(key: "gh-44", shield: 1),                      // Splintmail (4)
        DefenseItem(key: "gh-65", shield: 1),                      // Platemail (5)
        DefenseItem(key: "gh-104", shield: 1),                     // Steam Armor (5)
        DefenseItem(key: "gh-74", shield: 1, retaliate: 1),        // Swordedge Armor (3)
        DefenseItem(key: "gh-46", shield: 1, retaliate: 2),        // Spiked Shield
        DefenseItem(key: "gh-32", shield: 2),                      // Tower Shield
        DefenseItem(key: "gh-61", shield: 4),                      // Wall Shield
        DefenseItem(key: "gh-91", shield: 4),                      // Steel Ring
    ]
    static let beforeDraw = all.filter(\.disadvantage)
    static let onDamage = all.filter { !$0.disadvantage }

    /// Iron Helmet's key: not offered, it always applies.
    static let ironHelmet = "gh-7"

    var question: String {
        var gains: [String] = []
        if shield > 0 { gains.append("Shield \(shield)") }
        if retaliate > 0 { gains.append("Retaliate \(retaliate)") }
        let gain = "gain \(GameText.list(gains))"
        if disadvantage {
            return gains.isEmpty ? "Give the attacker disadvantage?" : "Give the attacker disadvantage and \(gain)?"
        }
        return "G\(gain.dropFirst()) against this attack?"
    }
}

extension BoardCoordinator {

    struct PendingItemUse: Identifiable {
        let id = UUID()
        let characterID: String
        let itemName: String
        let question: String
        let attacker: String
        var continuation: CheckedContinuation<Bool, Never>?
    }

    /// Called from the UI: use the offered item, or not.
    func resolvePendingItemUse(_ use: Bool) {
        guard let pending = pendingItemUse else { return }
        pendingItemUse = nil
        pending.continuation?.resume(returning: use)
    }

    /// Offer a defence item to the character being attacked; true when they use it (it is then
    /// spent and counted). Headless play never uses them.
    @MainActor func offerDefenseItem(_ item: DefenseItem, to target: PieceID, from attacker: PieceID) async -> Bool {
        let key = item.key
        guard case .character(let id) = target, !autoResolvePrompts, let gameManager,
              let character = gameManager.game.characters.first(where: { $0.id == id }),
              character.items.contains(key),
              !character.spentItems.contains(key), !character.consumedItems.contains(key),
              let data = itemData(key) else { return false }
        let use = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingItemUse = PendingItemUse(characterID: id, itemName: data.name, question: item.question,
                                            attacker: name(attacker), continuation: continuation)
        }
        guard use else { return false }
        gameManager.characterManager.onBeforeMutate?()
        // An item with use slots (Hide Armor: two) is spent once they are all marked.
        let used = character.itemSlotsUsed[key, default: 0] + 1
        if data.slots > 1 && used < data.slots {
            character.itemSlotsUsed[key] = used
        } else {
            if data.consumed { character.consumedItems.insert(key) } else { character.spentItems.insert(key) }
            character.itemSlotsUsed[key] = nil
        }
        gameManager.scenarioStatsManager.recordItemUse(by: character.name)
        log("\(name(target)) uses \(data.name)", category: .info)
        return true
    }
}
