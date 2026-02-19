import Foundation

@Observable
final class ObjectiveManager {
    private let game: GameState
    var onBeforeMutate: (() -> Void)?

    init(game: GameState) {
        self.game = game
    }

    // MARK: - Add/Remove Objectives

    func addObjective(name: String, health: Int, escort: Bool = false, initiative: Int = 99) {
        onBeforeMutate?()
        let container = GameObjectiveContainer(
            name: name,
            edition: game.edition ?? "",
            title: name,
            escort: escort,
            level: game.level
        )
        container.initiative = initiative

        let entity = GameObjectiveEntity(number: 1, health: health, maxHealth: health)
        container.entities.append(entity)

        game.figures.append(.objective(container))
    }

    func removeObjective(_ container: GameObjectiveContainer) {
        onBeforeMutate?()
        game.figures.removeAll { $0.id == "obj-\(container.id)" }
    }

    // MARK: - Entity Management

    func addEntity(to container: GameObjectiveContainer, health: Int? = nil) {
        onBeforeMutate?()
        let usedNumbers = Set(container.entities.map(\.number))
        var nextNumber = 1
        while usedNumbers.contains(nextNumber) { nextNumber += 1 }

        let hp = health ?? container.entities.first?.maxHealth ?? 1
        let entity = GameObjectiveEntity(number: nextNumber, health: hp, maxHealth: hp)
        container.entities.append(entity)
    }

    func removeEntity(_ entity: GameObjectiveEntity, from container: GameObjectiveContainer) {
        onBeforeMutate?()
        container.entities.removeAll { $0.uuid == entity.uuid }

        // Auto-remove empty containers
        if container.entities.isEmpty {
            removeObjective(container)
        }
    }
}
