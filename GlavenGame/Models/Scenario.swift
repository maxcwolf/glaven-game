import Foundation

@Observable
final class Scenario {
    let data: ScenarioData
    var revealedRooms: [Int] = []
    var additionalSections: [String] = []
    var isCustom: Bool = false
    var appliedRules: Set<String> = []
    var disabledRules: Set<Int> = []

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
