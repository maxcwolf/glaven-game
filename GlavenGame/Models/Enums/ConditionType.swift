import Foundation

enum ConditionType: String, Codable, CaseIterable {
    case standard, entity, character, monster, objective
    case turn, afterTurn, expire
    case stack, stackable
    case apply, autoApply
    case clearHeal, preventHeal
    case positive, negative, neutral, hidden
    case expiredIndicator, amDeck, highlightOnly, special
}
