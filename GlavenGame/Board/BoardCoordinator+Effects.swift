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
