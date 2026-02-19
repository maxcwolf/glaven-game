import Foundation

struct MonsterData: Codable, Hashable, Identifiable {
    var id: String { "\(edition)-\(name)" }
    var name: String
    var edition: String
    var count: IntOrString?
    var baseStat: MonsterStatModel?
    var stats: [MonsterStatModel]
    var deck: String?
    var boss: Bool?
    var flying: Bool?
    var immortal: Bool?
    var hidden: Bool?
    var spoiler: Bool?
    var standeeCount: IntOrString?
    var standeeShare: String?
    var pet: String?

    var isBoss: Bool { boss ?? false }

    func stat(for type: MonsterType, at level: Int) -> MonsterStatModel? {
        let resolvedType = isBoss ? .boss : type
        let baseType = baseStat?.type ?? .normal
        return stats.first(where: {
            ($0.type ?? baseType) == resolvedType && ($0.level ?? 0) == level
        })
    }

    var maxCount: Int {
        count?.intValue ?? (isBoss ? 1 : 6)
    }
}
