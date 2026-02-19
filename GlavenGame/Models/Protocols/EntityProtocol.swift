import Foundation

protocol Entity: AnyObject, Identifiable {
    var number: Int { get set }
    var health: Int { get set }
    var maxHealth: Int { get set }
    var level: Int { get set }
    var active: Bool { get set }
    var off: Bool { get set }
    var entityConditions: [EntityCondition] { get set }
    var immunities: [ConditionName] { get set }
    var markers: [String] { get set }
    var tags: [String] { get set }
    var shield: ActionModel? { get set }
    var shieldPersistent: ActionModel? { get set }
    var retaliate: [ActionModel] { get set }
    var retaliatePersistent: [ActionModel] { get set }
}
