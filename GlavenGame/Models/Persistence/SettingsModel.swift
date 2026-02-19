import Foundation
import SwiftData

@Model
final class SettingsModel {
    var selectedEditionsData: Data?
    var locale: String = "en"
    var theme: String = "default"
    var automaticTheme: Bool = true
    var abilities: Bool = true
    var applyConditions: Bool = true
    var automaticStandees: Bool = true
    var randomStandees: Bool = false
    var sortFigures: Bool = true
    var initiativeRequired: Bool = false
    var characterAttackModifierDeck: Bool = false
    var lootDeck: Bool = false
    var animations: Bool = true
    var soundEffects: Bool = true
    var compact: Bool = false
    var uiScale: Double = 1.0
    var lightMode: Bool = false
    var excludedConditionsData: Data?
    var animationSpeed: Double = 1.0
    var hapticFeedback: Bool = true

    // FH-specific toggles
    var fhPets: Bool = true
    var fhGarden: Bool = true
    var fhTrials: Bool = true
    var fhFavors: Bool = true
    var fhAlchemist: Bool = true

    // Custom edition data URLs (JSON-encoded [String])
    var editionDataUrlsData: Data?

    init() {}
}
