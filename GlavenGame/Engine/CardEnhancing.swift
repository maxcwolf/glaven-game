import Foundation

/// Enhancements on ability cards (GH p.42–43): the slots a card offers, what each slot can take
/// that the board plays, what it costs, and the card's actions with its enhancements applied.
///
/// A slot is addressed by `actionIndex`: the action's index in its half, or
/// `(index + 1) * 100 + subIndex` for a slot on one of its sub-actions.
enum CardEnhancing {

    struct Slot: Identifiable, Equatable {
        let cardId: Int
        let half: String
        let actionIndex: Int
        let slotIndex: Int
        let type: EnhancementSlotType
        /// The line the slot is printed on (Move 4, Range 2, Pierce 2…).
        let action: ActionModel
        /// The ability that line belongs to: a condition or element joins the attack, not its range.
        let host: ActionModel

        var id: String { "\(cardId)-\(half)-\(actionIndex)-\(slotIndex)" }
    }

    // MARK: - Slots

    static func slots(of card: AbilityModel) -> [Slot] {
        guard let cardId = card.cardId else { return [] }
        return slots(in: card.actions ?? [], cardId: cardId, half: "top")
            + slots(in: card.bottomActions ?? [], cardId: cardId, half: "bottom")
    }

    private static func slots(in actions: [ActionModel], cardId: Int, half: String) -> [Slot] {
        var result: [Slot] = []
        for (index, action) in actions.enumerated() {
            // A summon's stats, each a slot of its own that takes +1 (GH p.47).
            if let summon = action.summonValueObject {
                for (stat, name) in (summon.enhancements ?? []).enumerated() {
                    guard let line = summonStatLine(name, of: summon) else { continue }
                    result.append(Slot(cardId: cardId, half: half, actionIndex: summonStatAddress(index, stat),
                                       slotIndex: 0, type: .square, action: line, host: action))
                }
            }
            for (slot, type) in (action.enhancementTypes ?? []).enumerated() {
                result.append(Slot(cardId: cardId, half: half, actionIndex: index, slotIndex: slot,
                                   type: type, action: action, host: action))
            }
            for (subIndex, sub) in (action.subActions ?? []).enumerated() {
                for (slot, type) in (sub.enhancementTypes ?? []).enumerated() {
                    result.append(Slot(cardId: cardId, half: half, actionIndex: subAddress(index, subIndex),
                                       slotIndex: slot, type: type, action: sub, host: action))
                }
            }
        }
        return result
    }

    /// The address of a slot on sub-action `subIndex` of action `index`.
    static func subAddress(_ index: Int, _ subIndex: Int) -> Int {
        (index + 1) * 100 + subIndex
    }

    /// The address of a summon's stat slot: the `stat`th the card lists, on action `index`.
    static func summonStatAddress(_ index: Int, _ stat: Int) -> Int {
        10_000 + index * 10 + stat
    }

    /// A summon's stat as a line to enhance: Move, Attack, its hit points (the data's "heal")
    /// or Range, with its printed value.
    static func summonStatLine(_ name: String, of summon: SummonValueObject) -> ActionModel? {
        func value(_ stat: IntOrString?) -> Int { stat?.intValue ?? Int(stat?.stringValue ?? "") ?? 0 }
        switch name {
        case "move": return ActionModel(type: .move, value: .int(value(summon.movement)))
        case "attack": return ActionModel(type: .attack, value: .int(value(summon.attack)))
        case "heal": return ActionModel(type: .heal, value: .int(value(summon.health)))
        case "range": return ActionModel(type: .range, value: .int(value(summon.range)))
        default: return nil
        }
    }

    /// Whether a slot is one of a summon's stats.
    static func isSummonStat(_ slot: Slot) -> Bool { slot.actionIndex >= 10_000 }

    // MARK: - What a slot can take

    /// The enhancements a slot can take that the board plays.
    static func options(for slot: Slot, edition: String) -> [EnhancementAction] {
        // A summon's stat takes +1 and nothing else.
        if isSummonStat(slot) { return [.plus1] }
        return EnhancementsManager.availableActions(for: slot.type, actionType: slot.action.type, isSummon: false, edition: edition)
            .filter { plays($0, in: slot) }
            // Gloomhaven puts conditions and elements on main ability lines only (GH p.47): a
            // small line under one (Range, Target, Pierce, Push, Pull) takes its +1.
            .filter { edition != "gh" || !isSmallLine(slot) || $0 == .plus1 || $0 == .hex }
    }

    /// A line that modifies the ability above it rather than being one itself.
    static func isSmallLine(_ slot: Slot) -> Bool {
        slot.actionIndex >= 100 && ![.attack, .move, .heal, .shield, .retaliate, .loot].contains(slot.action.type)
    }

    static func plays(_ enhancement: EnhancementAction, in slot: Slot) -> Bool {
        switch enhancement {
        case .plus1:
            return slot.action.value?.intValue != nil && plusOneTypes.contains(slot.action.type)
        case .jump:
            return slot.action.type == .move && slot.host.type == .move
                && !(slot.host.subActions ?? []).contains { $0.type == .jump }
        case .hex:
            // An area with a hex marked where the card has room for one more.
            return slot.action.type == .area && slot.action.value?.stringValue.contains("enhance") == true
        case .wild:
            return [.attack, .move, .heal, .shield, .retaliate].contains(slot.host.type) || isConditionForEveryone(slot)
        default:
            if enhancement.isNegativeCondition {
                guard ConditionName(rawValue: enhancement.rawValue) != nil else { return false }
                return slot.host.type == .attack || (isConditionForEveryone(slot) && slot.host.value?.stringValue != enhancement.rawValue)
            }
            if enhancement.isPositiveCondition {
                guard ConditionName(rawValue: enhancement.rawValue) != nil else { return false }
                return [.heal, .shield, .retaliate].contains(slot.host.type)
                    || (isConditionForEveryone(slot) && slot.host.value?.stringValue != enhancement.rawValue)
            }
            if ElementType(rawValue: enhancement.rawValue) != nil {
                return [.attack, .move, .heal, .shield, .retaliate].contains(slot.host.type) || isConditionForEveryone(slot)
            }
            return false
        }
    }

    /// A condition printed as an ability of its own ("Stun, all adjacent enemies") that reaches
    /// everyone it names with no choosing: the board plays an element or a second condition
    /// beside it. One with a single target to pick isn't played with them yet.
    static func isConditionForEveryone(_ slot: Slot) -> Bool {
        guard slot.actionIndex < 100, slot.host.type == .condition,
              let spec = slot.host.subActions?.first(where: { $0.type == .specialTarget })?.value?.stringValue.lowercased()
        else { return false }
        return ["self", "enemiesadjacent", "enemies", "alliesadjacent", "alliesadjacentaffect", "alliesaffect",
                "selfalliesaffect", "selfalliesadjacentaffect"].contains(spec)
            || ["enemiesrange:", "alliesrangeaffect:", "selfalliesaffectrange:"].contains { spec.hasPrefix($0) }
    }

    private static let plusOneTypes: Set<ActionType> = [
        .attack, .move, .range, .target, .heal, .shield, .retaliate, .push, .pull, .pierce, .teleport,
    ]

    // MARK: - Cost

    /// What the Enhancer charges for `enhancement` in `slot`, given what the card already has.
    static func cost(_ enhancement: EnhancementAction, in slot: Slot, card: AbilityModel,
                     enhancements: [Enhancement], edition: String) -> Int {
        // Gloomhaven's hex: 200 gold divided by the hexes the area already targets (not doubled
        // for several targets).
        if enhancement == .hex, edition == "gh", let pattern = slot.action.value?.stringValue {
            // A hex already added to this area counts as one it targets.
            let added = enhancements.filter {
                $0.cardId == slot.cardId && $0.actionHalf == slot.half && $0.actionIndex == slot.actionIndex && $0.action == .hex
            }.count
            let targets = max(1, pattern.components(separatedBy: "target").count - 1 + added)
            let level = max(0, (card.level?.intValue ?? 1) - 1) * 25
            let earlier = EnhancementsManager.enhancementCount(on: slot.cardId, half: slot.half, in: enhancements) * 75
            return 200 / targets + level + earlier
        }
        // Dearer for each enhancement already on the same action — this half of the card.
        return EnhancementsManager.enhancementCost(
            action: enhancement, slotType: slot.type, actionType: slot.action.type,
            cardLevel: card.level?.intValue ?? 1,
            previousEnhancements: EnhancementsManager.enhancementCount(on: slot.cardId, half: slot.half, in: enhancements),
            isMultiTarget: targetsSeveral(slot.host) && !neverDoubled(enhancement, in: slot),
            isLost: slot.half == "top" ? card.lost == true : card.bottomLost == true,
            isPersistent: card.persistent == true,
            isSummon: isSummonStat(slot), edition: edition)
    }

    /// The doubling for several targets "does not apply to target, area-of-effect hex, or
    /// element enhancements" (GH p.47): one more target is itself the cost of reaching more, and
    /// an element is infused once however many are hit.
    static func neverDoubled(_ enhancement: EnhancementAction, in slot: Slot) -> Bool {
        enhancement.isElement || enhancement == .hex || (enhancement == .plus1 && slot.action.type == .target)
    }

    /// An ability that targets several figures costs double (GH p.47). An ability that reaches
    /// several only by consuming an element, or that summons several figures, is single-target
    /// (FAQ): only what is printed beside the ability itself counts.
    static func targetsSeveral(_ action: ActionModel) -> Bool {
        (action.subActions ?? []).contains { sub in
            switch sub.type {
            case .target: return (sub.value?.intValue ?? 1) > 1
            case .area: return true
            case .specialTarget:
                let spec = sub.value?.stringValue.lowercased() ?? ""
                return spec.hasPrefix("enemies") || spec.hasPrefix("allies") || spec.hasPrefix("all")
            default: return false
            }
        }
    }

    /// The enhancements on a card in a few words, for its tile: "+1 Move", "Poison", "Fire".
    static func summary(of card: AbilityModel, enhancements: [Enhancement]) -> [String] {
        let slots = slots(of: card)
        return enhancements.filter { $0.cardId == card.cardId }
            .sorted { ($0.actionHalf == "bottom" ? 1 : 0, $0.actionIndex, $0.slotIndex)
                    < ($1.actionHalf == "bottom" ? 1 : 0, $1.actionIndex, $1.slotIndex) }
            .map { enhancement in
                guard enhancement.action == .plus1,
                      let slot = slots.first(where: { $0.half == enhancement.actionHalf && $0.actionIndex == enhancement.actionIndex })
                else { return enhancement.action.displayName }
                return "+1 \(GameText.words(fromCamelCase: slot.action.type.rawValue).capitalized)"
            }
    }

    // MARK: - Playing an enhanced card

    /// A half's actions with the character's enhancements on that card applied.
    static func apply(_ enhancements: [Enhancement], to actions: [ActionModel], cardId: Int?, half: String) -> [ActionModel] {
        guard let cardId else { return actions }
        var result = actions
        // A condition added to a condition ability is played as one more beside it.
        var beside: [(index: Int, action: ActionModel)] = []
        let mine = enhancements.filter { $0.cardId == cardId && $0.actionHalf == half }
            .sorted { ($0.actionIndex, $0.slotIndex) < ($1.actionIndex, $1.slotIndex) }
        for enhancement in mine {
            // +1 on a summon's stat: the summon the card makes is that much stronger.
            if enhancement.actionIndex >= 10_000 {
                let index = (enhancement.actionIndex - 10_000) / 10, stat = (enhancement.actionIndex - 10_000) % 10
                guard enhancement.action == .plus1, result.indices.contains(index), var summon = result[index].summonValueObject,
                      let name = summon.enhancements?.indices.contains(stat) == true ? summon.enhancements?[stat] : nil else { continue }
                func plus(_ stat: IntOrString?) -> IntOrString { .int((stat?.intValue ?? Int(stat?.stringValue ?? "") ?? 0) + 1) }
                switch name {
                case "move": summon.movement = plus(summon.movement)
                case "attack": summon.attack = plus(summon.attack)
                case "heal": summon.health = plus(summon.health)
                case "range": summon.range = plus(summon.range)
                default: break
                }
                result[index].summonValueObject = summon
                continue
            }
            let index = enhancement.actionIndex < 100 ? enhancement.actionIndex : enhancement.actionIndex / 100 - 1
            let subIndex = enhancement.actionIndex < 100 ? nil : enhancement.actionIndex % 100
            guard result.indices.contains(index) else { continue }
            var host = result[index]
            if subIndex == nil, host.type == .condition, enhancement.action.isCondition {
                let reach = (host.subActions ?? []).filter { [.specialTarget, .range, .target].contains($0.type) }
                beside.append((index, ActionModel(type: .condition, value: .string(enhancement.action.rawValue),
                                                  subActions: reach.isEmpty ? nil : reach)))
                continue
            }
            if let subIndex {
                guard var subs = host.subActions, subs.indices.contains(subIndex) else { continue }
                if enhancement.action == .plus1 {
                    subs[subIndex] = plusOne(subs[subIndex])
                    host.subActions = subs
                } else {
                    host = adding(enhancement.action, to: host)
                }
            } else {
                host = enhancement.action == .plus1 ? plusOne(host) : adding(enhancement.action, to: host)
            }
            if enhancement.action == .hex, let original = actions[index].subActions?.first(where: { $0.type == .area }) {
                host = addingHex(enhancement.slotIndex, of: original, to: host)
            }
            result[index] = host
        }
        for extra in beside.reversed() {
            result.insert(extra.action, at: extra.index + 1)
        }
        return result
    }

    /// The hexes an area marks for enhancement, in the order of its hex slots.
    static func markedHexes(in area: ActionModel) -> [ActionHex] {
        ActionHex.parse(area.value?.stringValue ?? "").filter { $0.type == .enhance }
    }

    /// The area's `slot`th marked hex (as printed, `original`) becomes a target hex.
    private static func addingHex(_ slot: Int, of original: ActionModel, to host: ActionModel) -> ActionModel {
        let marked = markedHexes(in: original)
        guard marked.indices.contains(slot) else { return host }
        let hex = marked[slot]
        var host = host
        host.subActions = host.subActions?.map { sub in
            guard sub.type == .area, let pattern = sub.value?.stringValue else { return sub }
            var sub = sub
            sub.value = .string(pattern.replacingOccurrences(of: "(\(hex.x),\(hex.y),enhance)", with: "(\(hex.x),\(hex.y),target)"))
            return sub
        }
        return host
    }

    private static func plusOne(_ action: ActionModel) -> ActionModel {
        guard let value = action.value?.intValue else { return action }
        var action = action
        action.value = .int(value + 1)
        return action
    }

    /// The ability with a condition, element or jump added, as if printed on the card.
    private static func adding(_ enhancement: EnhancementAction, to host: ActionModel) -> ActionModel {
        var host = host
        var subs = host.subActions ?? []
        if enhancement == .jump {
            subs.append(ActionModel(type: .jump, value: .string(""), small: true))
        } else if ElementType(rawValue: enhancement.rawValue) != nil {
            subs.append(ActionModel(type: .element, value: .string(enhancement.rawValue)))
        } else if enhancement.isCondition {
            subs.append(ActionModel(type: .condition, value: .string(enhancement.rawValue)))
            // Shield and Retaliate are the character's own: a condition on them is theirs too.
            if [.shield, .retaliate].contains(host.type),
               !subs.contains(where: { $0.type == .specialTarget && $0.value?.stringValue == "self" }) {
                subs.append(ActionModel(type: .specialTarget, value: .string("self"), hidden: true))
            }
        }
        host.subActions = subs
        return host
    }
}
