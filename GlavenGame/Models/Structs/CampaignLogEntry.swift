import Foundation

enum CampaignLogType: String, Codable {
    case scenarioCompleted
    case scenarioFailed
    case characterAdded
    case characterRetired
    case characterExhausted
    case achievementGained
    case prosperityGained
    case reputationChanged
    case treasureLooted
    case itemAcquired
    case levelUp
    case characterUnlocked
}

struct CampaignLogEntry: Codable, Identifiable {
    let id: UUID
    let type: CampaignLogType
    let message: String
    let details: String?
    let timestamp: Date

    init(type: CampaignLogType, message: String, details: String? = nil) {
        self.id = UUID()
        self.type = type
        self.message = message
        self.details = details
        self.timestamp = Date()
    }
}
