import Foundation

/// Combined edition data format used by remote URLs.
/// Mirrors the Angular `EditionData` structure where all data is in a single JSON.
struct RemoteEditionData: Codable {
    var edition: String
    var conditions: [ConditionName]?
    var characters: [CharacterData]?
    var monsters: [MonsterData]?
    var decks: [DeckData]?
    var scenarios: [ScenarioData]?
    var sections: [ScenarioData]?
    var items: [ItemData]?
    var battleGoals: [BattleGoalData]?
    var personalQuests: [PersonalQuestData]?
    var treasures: [String]?
    var extensions: [String]?
    var extends: [String]?
    var logoUrl: String?
    var worldMap: WorldMapDimensions?
    var additional: Bool?
}
