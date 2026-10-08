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
        guard let game = gameManager?.game else { return appearance }
        switch piece {
        case .character(let id):
            guard let character = game.characters.first(where: { $0.id == id }) else { break }
            appearance.portrait = ImageLoader.characterThumbnail(edition: character.edition, name: character.name)
            appearance.rimColor = SKColor(hex: character.color) ?? appearance.rimColor
            appearance.initials = String(GameText.characterName(character).prefix(2)).uppercased()
        case .monster(let name, let standee):
            guard let monster = game.monsters.first(where: { $0.name == name }) else { break }
            appearance.portrait = ImageLoader.monsterThumbnail(edition: monster.edition, name: monster.name)
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
        return PieceStatus(health: entity.health, maxHealth: entity.maxHealth,
                           conditions: ConditionName.allCases.filter(active.contains))
    }

    /// Bring every token on the board up to date (health, conditions, invisibility).
    func syncPieceVisuals() {
        boardScene?.refreshAllStatuses()
        refreshInvisibility()
    }
}
