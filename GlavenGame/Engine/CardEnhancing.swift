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

    // MARK: - What a slot can take

    /// The enhancements a slot can take that the board plays.
    static func options(for slot: Slot, edition: String) -> [EnhancementAction] {
        EnhancementsManager.availableActions(for: slot.type, actionType: slot.action.type, isSummon: false, edition: edition)
            .filter { plays($0, in: slot) }
    }

    static func plays(_ enhancement: EnhancementAction, in slot: Slot) -> Bool {
        switch enhancement {
        case .plus1:
            return slot.action.value?.intValue != nil && plusOneTypes.contains(slot.action.type)
        case .jump:
            return slot.action.type == .move && slot.host.type == .move
        case .hex:
            // An area with a hex marked where the card has room for one more.
            return slot.action.type == .area && slot.action.value?.stringValue.contains("enhance") == true
        case .wild:
            return [.attack, .move, .heal, .shield, .retaliate].contains(slot.host.type)
        default:
            if enhancement.isNegativeCondition {
                return slot.host.type == .attack && ConditionName(rawValue: enhancement.rawValue) != nil
            }
            if enhancement.isPositiveCondition {
                return [.heal, .shield, .retaliate].contains(slot.host.type) && ConditionName(rawValue: enhancement.rawValue) != nil
            }
            if ElementType(rawValue: enhancement.rawValue) != nil {
                return [.attack, .move, .heal, .shield, .retaliate].contains(slot.host.type)
            }
            return false
        }
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
            let earlier = EnhancementsManager.enhancementCount(on: slot.cardId, in: enhancements) * 75
            return 200 / targets + level + earlier
        }
        return EnhancementsManager.enhancementCost(
            action: enhancement, slotType: slot.type, actionType: slot.action.type,
            cardLevel: card.level?.intValue ?? 1,
            previousEnhancements: EnhancementsManager.enhancementCount(on: slot.cardId, in: enhancements),
            isMultiTarget: targetsSeveral(slot.host),
            isLost: slot.half == "top" ? card.lost == true : card.bottomLost == true,
            isPersistent: card.persistent == true,
            isSummon: false, edition: edition)
    }

    /// An ability that targets several figures costs double (GH p.43).
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
        let mine = enhancements.filter { $0.cardId == cardId && $0.actionHalf == half }
            .sorted { ($0.actionIndex, $0.slotIndex) < ($1.actionIndex, $1.slotIndex) }
        for enhancement in mine {
            let index = enhancement.actionIndex < 100 ? enhancement.actionIndex : enhancement.actionIndex / 100 - 1
            let subIndex = enhancement.actionIndex < 100 ? nil : enhancement.actionIndex % 100
            guard result.indices.contains(index) else { continue }
            var host = result[index]
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
