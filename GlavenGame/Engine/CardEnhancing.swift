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

    /// The enhancements a slot can take that the board plays. Hex (area) and any-element
    /// enhancements aren't played yet, so they aren't sold.
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
        case .hex, .wild:
            return false
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
        EnhancementsManager.enhancementCost(
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
            result[index] = host
        }
        return result
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
