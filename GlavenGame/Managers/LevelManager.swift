import Foundation

@Observable
final class LevelManager {
    private let game: GameState

    init(game: GameState) {
        self.game = game
    }

    func scenarioLevel() -> Int {
        let chars = game.activeCharacters
        guard !chars.isEmpty else { return game.level }

        let totalLevels = chars.map(\.level).reduce(0, +)
        let avgLevel = Double(totalLevels) / Double(chars.count)
        var level = Int(ceil(avgLevel / 2.0))

        level += game.levelAdjustment

        if game.ge5Player && chars.count >= 5 {
            level += chars.count - 4
        }

        return max(0, min(7, level))
    }

    func calculateAndApplyLevel() {
        if game.levelCalculation {
            game.level = scenarioLevel()
        }
    }

    func setLevel(_ level: Int) {
        game.level = max(0, min(7, level))
    }

    func trap() -> Int { 2 + game.level }
    func experience() -> Int { 4 + game.level * 2 }
    func loot() -> Int { min(6, 2 + game.level / 2) }
    func terrain() -> Int { 1 + Int(ceil(Double(game.level) / 3.0)) }
}
