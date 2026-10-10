import Foundation

/// A scenario's standing effects on attacks and shields (`ScenarioPlacements.Effect`): what a
/// vocal chord does while it stands, the Hungry Soul's Shield falling with every Living Bones
/// around it.
extension BoardCoordinator {

    var scenarioEffects: [ScenarioPlacements.Effect] { scenarioData?.placements?.effects ?? [] }

    /// The effects in force that touch a figure.
    func scenarioEffects(on pieceID: PieceID) -> [ScenarioPlacements.Effect] {
        scenarioEffects.filter { touches($0, pieceID) && isInForce($0) }
    }

    private func touches(_ effect: ScenarioPlacements.Effect, _ pieceID: PieceID) -> Bool {
        if effect.untilLooted == true {
            guard case .character(let id) = pieceID, !boardState.goalLooters.contains(id) else { return false }
        }
        switch (effect.on, pieceID) {
        case ("party", .character), ("party", .summon): return true
        case ("monsters", .monster): return !isPlayerSide(pieceID)
        case (let name, .monster(let monster, _)): return name == monster
        default: return false
        }
    }

    func isInForce(_ effect: ScenarioPlacements.Effect) -> Bool {
        if let objective = effect.whileStanding, standing(objective: objective) == 0 { return false }
        if let room = effect.room, gameManager?.game.scenario?.revealedRooms.contains(room) != true { return false }
        return true
    }

    /// How many of an objective (1-based) stand on the board.
    private func standing(objective index: Int) -> Int {
        boardState.piecePositions.keys.filter {
            if case .objective = $0 { return objectiveContainer(of: $0)?.objectiveIndex == index }
            return false
        }.count
    }

    /// Bring every character's bar on items in line with the scenario's effects (Vigil Keep: no
    /// items until the character has looted a treasure tile).
    func updateItemBars() {
        for character in gameManager?.game.characters ?? [] {
            let barred = scenarioEffects(on: .character(character.id)).contains { $0.noItems == true }
            if character.itemsBarred != barred { character.itemsBarred = barred }
        }
    }

    // MARK: - Water

    private func isWater(_ hex: HexCoord) -> Bool {
        guard let cell = boardState.cells[hex] else { return false }
        return cell.overlay == .difficultTerrain && cell.overlaySubType == "water"
    }

    /// Whether a figure entering `hex` on foot suffers trap damage from its water: a poisoned
    /// character or character summon, where the scenario says so.
    func waterHurtsOnEntering(_ hex: HexCoord, _ pieceID: PieceID) -> Bool {
        guard scenarioData?.placements?.water?.hurtsThePoisoned == true, isWater(hex) else { return false }
        switch pieceID {
        case .character, .summon: return isConditionActive(.poison, on: pieceID)
        default: return false
        }
    }

    /// The damage a figure suffers for ending its turn where it stands, in a scenario whose
    /// water does that.
    func waterDamageAtTurnEnd(for pieceID: PieceID) -> Int? {
        guard let formula = scenarioData?.placements?.water?.endOfTurn, let game = gameManager?.game,
              let hex = boardState.piecePositions[pieceID], isWater(hex) else { return nil }
        let variables = ["C": max(2, game.characters.filter { !$0.absent }.count), "L": game.level]
        return ScenarioExpression.integerValue(formula, variables: variables).flatMap { $0 > 0 ? $0 : nil }
    }

    /// A monster's or summon's turn ends in water that hurts.
    func sufferWaterAtTurnEnd(_ pieceID: PieceID) {
        guard let damage = waterDamageAtTurnEnd(for: pieceID) else { return }
        log("\(name(pieceID)) ends the turn in the water and suffers \(damage) damage", category: .damage)
        sufferDamage(damage, to: pieceID)
    }

    /// What the scenario adds to each of a figure's attacks.
    func scenarioAttackBonus(of pieceID: PieceID) -> Int {
        scenarioEffects(on: pieceID).reduce(0) { $0 + ($1.attack ?? 0) }
    }

    func scenarioGivesAdvantage(to pieceID: PieceID) -> Bool {
        scenarioEffects(on: pieceID).contains { $0.advantage == true }
    }

    func scenarioGivesDisadvantage(to pieceID: PieceID) -> Bool {
        scenarioEffects(on: pieceID).contains { $0.disadvantage == true }
    }

    /// What the scenario adds to (or takes from) a figure's Shield.
    func scenarioShield(of pieceID: PieceID) -> Int {
        guard let game = gameManager?.game else { return 0 }
        return scenarioEffects(on: pieceID).reduce(0) { total, effect in
            guard let formula = effect.shield else { return total }
            var counted = 0
            if let objective = effect.per?.objective { counted += standing(objective: objective) }
            if let monster = effect.per?.monster {
                counted += boardState.piecePositions.keys.filter {
                    if case .monster(monster, _) = $0 { return $0 != pieceID }
                    return false
                }.count
            }
            if let tokens = effect.per?.tokens {
                counted += max(0, tokens - (effect.per?.lostWith.flatMap { game.scenario?.killCounts[$0] } ?? 0))
            }
            let variables = ["X": counted, "C": max(2, game.characters.filter { !$0.absent }.count), "L": game.level]
            return total + (ScenarioExpression.integerValue(formula, variables: variables) ?? 0)
        }
    }

    /// A figure's Shield as an attack meets it: its own and the scenario's.
    func shield(of pieceID: PieceID) -> Int {
        guard let entity = entity(for: pieceID) else { return 0 }
        return max(0, CombatResolver.totalShield(shield: entity.shield, shieldPersistent: entity.shieldPersistent)
                      + scenarioShield(of: pieceID))
    }
}
