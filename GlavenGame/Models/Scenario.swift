import Foundation

@Observable
final class Scenario {
    let data: ScenarioData
    var revealedRooms: [Int] = []
    var additionalSections: [String] = []
    var isCustom: Bool = false
    var appliedRules: Set<String> = []
    var disabledRules: Set<Int> = []
    /// Cumulative kill counts by monster name, incremented by BoardCoordinator on entity death.
    var killCounts: [String: Int] = [:]
    /// Monster types the placements held back (`later`) that a rule has since set up.
    var releasedMonsters: Set<String> = []
    /// Set by ScenarioRulesManager when a finish rule fires; checked in BoardCoordinator.checkVictoryDefeat().
    var pendingFinish: String? = nil
    /// Each character's experience and gold when the scenario began (by character id), so the
    /// results can show what was gained in it.
    var startingExperience: [String: Int] = [:]
    var startingGold: [String: Int] = [:]
    /// What each character (by name) and the party did, for battle goals.
    var stats: [String: ScenarioCharacterStats] = [:]
    var partyStats = ScenarioPartyStats()

    init(data: ScenarioData, isCustom: Bool = false) {
        self.data = data
        self.isCustom = isCustom
    }

    var totalRoomCount: Int {
        data.rooms?.count ?? 0
    }

    var unrevealedRooms: [RoomData] {
        guard let rooms = data.rooms else { return [] }
        return rooms.filter { !revealedRooms.contains($0.roomNumber) }
    }

    var adjacentUnrevealedRooms: [RoomData] {
        guard let rooms = data.rooms else { return [] }
        let adjacentNumbers = Set(revealedRooms.flatMap { roomNum -> [Int] in
            rooms.first(where: { $0.roomNumber == roomNum })?.adjacentRooms ?? []
        })
        return rooms.filter { adjacentNumbers.contains($0.roomNumber) && !revealedRooms.contains($0.roomNumber) }
    }

    func ruleKey(index: Int) -> String {
        "\(data.edition)-\(data.index)-\(index)"
    }
}
