import Foundation

enum ActionType: String, Codable, CaseIterable {
    case attack, damage, heal, move
    case push, pull, pierce, range, target
    case condition, shield, retaliate
    case element, summon, spawn
    case area, fly, jump, teleport, swing
    case trigger, loot, grid
    case box, card, hint, custom, nonCalc
    case specialTarget, concatenation, concatenationSpacer, grant
    case suffer, sufferDamage, experience, forceRefresh
    case refreshItem, refreshSpent
    case special, forceBox, monsterType, switchType, boxFhSubActions, extra
    case text
    case immune, elementHalf, removeNegativeConditions
}
