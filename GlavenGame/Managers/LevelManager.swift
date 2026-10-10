import Foundation

@Observable
final class LevelManager {
    private let game: GameState

    init(game: GameState) {
        self.game = game
    }

    /// Recommended scenario level: average character level ÷ 2, rounded UP (GH rulebook p.15),
    /// then adjusted by difficulty, never below 0 (the game's own "Story" setting, −2, included)
    /// or above 7. Solo play doesn't change it: it raises `GameState.monsterLevel`.
    func scenarioLevel() -> Int {
        let chars = game.activeCharacters
        guard !chars.isEmpty else { return game.level }

        let totalLevels = chars.map(\.level).reduce(0, +)
        // ceil(total / (2 * count)) == ceil(average / 2), in integer arithmetic.
        let divisor = 2 * chars.count
        var level = (totalLevels + divisor - 1) / divisor

        level += game.difficulty.rawValue

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

    /// Damage dealt by a damage trap: 2 + L — in solo play one more, with the monsters' level.
    func trap() -> Int { 2 + game.monsterLevel }

    /// Bonus experience on scenario success: 4 + 2L.
    func experience() -> Int { 4 + game.level * 2 }

    /// Gold per money token (GH scenario level table): 2,2,3,3,4,4,5,6 for L0–L7.
    func loot() -> Int {
        let table = [2, 2, 3, 3, 4, 4, 5, 6]
        return table[max(0, min(table.count - 1, game.level))]
    }

    /// Damage dealt by entering hazardous terrain.
    /// GH: half of trap damage, rounded down. FH: 1 + ceil(L/3).
    func terrain() -> Int {
        if game.edition == "fh" {
            return 1 + Int(ceil(Double(game.monsterLevel) / 3.0))
        }
        return trap() / 2
    }
}
