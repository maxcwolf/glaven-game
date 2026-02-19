import Foundation

// MARK: - VGB Scenario JSON Models

struct VGBScenario: Codable {
    let id: Int
    let title: String
    let mapTileData: VGBMapTileData
    let angle: Double
    let additionalMonsters: [String]?
}

struct VGBMapTileData: Codable {
    let ref: String
    let doors: [VGBDoor]
    let overlays: [VGBOverlay]
    let monsters: [VGBMonster]
    let turns: Int
}

struct VGBDoor: Codable {
    let subType: String
    let direction: String
    let room1X: Int
    let room1Y: Int
    let room2X: Int
    let room2Y: Int
    let mapTileData: VGBMapTileData
}

struct VGBOverlay: Codable {
    let ref: VGBOverlayRef
    let direction: String
    let cells: [[Int]]
}

struct VGBOverlayRef: Codable {
    let type: String
    let subType: String?
    let id: String?
    let amount: Int?
}

struct VGBMonster: Codable {
    let monster: String
    let initialX: Int
    let initialY: Int
    let twoPlayer: String
    let threePlayer: String
    let fourPlayer: String
}
