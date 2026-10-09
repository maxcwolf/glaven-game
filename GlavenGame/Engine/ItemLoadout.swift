import Foundation

/// What a character brings to a scenario (GH p.9): at most one head, one body and one legs item,
/// two hands' worth (a two-handed item takes both), and small items up to half their level,
/// rounded up. They may own more and leave the rest at home.
enum ItemLoadout {

    /// Why an item can't be brought as well.
    enum Problem: Equatable {
        case slotTaken(ItemSlot)
        case handsFull
        case smallItemsFull(limit: Int)

        var text: String {
            switch self {
            case .slotTaken(let slot): return "A \(slot.displayName.lowercased()) item is already brought"
            case .handsFull: return "Both hands are full"
            case .smallItemsFull(let limit): return "Already bringing \(limit) small item\(limit == 1 ? "" : "s")"
            }
        }
    }

    /// Cloak of Pockets: "Increase your small item limit by 2."
    static let cloakOfPockets = "gh-16"

    static func smallItemLimit(level: Int, carrying keys: [String]) -> Int {
        (level + 1) / 2 + (keys.contains(cloakOfPockets) ? 2 : 0)
    }

    /// Whether `key` can be brought beside `carried` (which it isn't one of).
    static func problem(bringing key: String, beside carried: [String], level: Int,
                        item: (String) -> ItemData?) -> Problem? {
        guard let slot = item(key)?.slot else { return nil }
        let slots = carried.compactMap { item($0)?.slot }
        switch slot {
        case .head, .body, .legs:
            return slots.contains(slot) ? .slotTaken(slot) : nil
        case .onehand, .twohand:
            let hands = slots.reduce(0) { $0 + ($1 == .onehand ? 1 : $1 == .twohand ? 2 : 0) }
            return hands + (slot == .twohand ? 2 : 1) > 2 ? .handsFull : nil
        case .small:
            let limit = smallItemLimit(level: level, carrying: carried + [key])
            return slots.filter { $0 == .small }.count + 1 > limit ? .smallItemsFull(limit: limit) : nil
        }
    }

    /// The items left behind so that what's brought fits: those already left behind, and then,
    /// in the order they were acquired, any that don't fit beside the ones before them.
    static func leftBehind(owned: [String], leftBehind: [String], level: Int,
                           item: (String) -> ItemData?) -> [String] {
        var carried: [String] = []
        var left: [String] = []
        // Cloak of Pockets first: it decides how many small items fit.
        let order = owned.filter { $0 == cloakOfPockets } + owned.filter { $0 != cloakOfPockets }
        for key in order {
            if leftBehind.contains(key) || problem(bringing: key, beside: carried, level: level, item: item) != nil {
                left.append(key)
            } else {
                carried.append(key)
            }
        }
        return owned.filter(left.contains)
    }
}
