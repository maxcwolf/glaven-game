import Foundation
import SwiftData

@Observable
final class SettingsManager {
    var selectedEditions: [String] = []
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
    var lootDeckEnabled: Bool = false
    var animations: Bool = true
    var soundEffects: Bool = true
    var compact: Bool = false
    var uiScale: CGFloat = 1.0
    var lightMode: Bool = false
    var excludedConditions: Set<ConditionName> = []
    var animationSpeed: Double = 1.0  // 0.5 = fast, 1.0 = normal, 2.0 = slow
    var hapticFeedback: Bool = true

    // FH-specific toggles
    var fhPets: Bool = true
    var fhGarden: Bool = true
    var fhTrials: Bool = true
    var fhFavors: Bool = true
    var fhAlchemist: Bool = true

    // Custom edition data URLs
    var editionDataUrls: [String] = []

    private var modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSettings()
    }

    func loadSettings() {
        let descriptor = FetchDescriptor<SettingsModel>()
        if let settings = try? modelContext.fetch(descriptor).first {
            if let data = settings.selectedEditionsData {
                selectedEditions = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
            locale = settings.locale
            theme = settings.theme
            automaticTheme = settings.automaticTheme
            abilities = settings.abilities
            applyConditions = settings.applyConditions
            automaticStandees = settings.automaticStandees
            randomStandees = settings.randomStandees
            sortFigures = settings.sortFigures
            initiativeRequired = settings.initiativeRequired
            characterAttackModifierDeck = settings.characterAttackModifierDeck
            lootDeckEnabled = settings.lootDeck
            animations = settings.animations
            soundEffects = settings.soundEffects
            compact = settings.compact
            uiScale = CGFloat(settings.uiScale)
            lightMode = settings.lightMode
            if let data = settings.excludedConditionsData {
                excludedConditions = (try? JSONDecoder().decode(Set<ConditionName>.self, from: data)) ?? []
            }
            animationSpeed = settings.animationSpeed
            hapticFeedback = settings.hapticFeedback
            fhPets = settings.fhPets
            fhGarden = settings.fhGarden
            fhTrials = settings.fhTrials
            fhFavors = settings.fhFavors
            fhAlchemist = settings.fhAlchemist
            if let data = settings.editionDataUrlsData {
                editionDataUrls = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            }
        }
    }

    func saveSettings() {
        let descriptor = FetchDescriptor<SettingsModel>()
        let settings = (try? modelContext.fetch(descriptor).first) ?? SettingsModel()
        settings.selectedEditionsData = try? JSONEncoder().encode(selectedEditions)
        settings.locale = locale
        settings.theme = theme
        settings.automaticTheme = automaticTheme
        settings.abilities = abilities
        settings.applyConditions = applyConditions
        settings.automaticStandees = automaticStandees
        settings.randomStandees = randomStandees
        settings.sortFigures = sortFigures
        settings.initiativeRequired = initiativeRequired
        settings.characterAttackModifierDeck = characterAttackModifierDeck
        settings.lootDeck = lootDeckEnabled
        settings.animations = animations
        settings.soundEffects = soundEffects
        settings.compact = compact
        settings.uiScale = Double(uiScale)
        settings.lightMode = lightMode
        settings.excludedConditionsData = try? JSONEncoder().encode(excludedConditions)
        settings.animationSpeed = animationSpeed
        settings.hapticFeedback = hapticFeedback
        settings.fhPets = fhPets
        settings.fhGarden = fhGarden
        settings.fhTrials = fhTrials
        settings.fhFavors = fhFavors
        settings.fhAlchemist = fhAlchemist
        settings.editionDataUrlsData = try? JSONEncoder().encode(editionDataUrls)

        if settings.modelContext == nil {
            modelContext.insert(settings)
        }
        try? modelContext.save()
    }

    /// Returns the effective theme based on auto-detection or manual selection.
    func effectiveTheme(edition: String?) -> String {
        if automaticTheme {
            switch edition {
            case "fh": return "fh"
            case "bb": return "bb"
            default: return "default"
            }
        }
        return theme
    }
}
