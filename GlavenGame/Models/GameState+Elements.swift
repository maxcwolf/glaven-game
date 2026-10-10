import Foundation

/// What just happened to an element on the infusion table.
enum ElementChange { case infused, consumed }

/// Elemental infusion table rules (GH p.24).
extension GameState {

    /// Strong or waning elements can be consumed.
    func isElementAvailable(_ type: ElementType) -> Bool {
        guard let element = elementBoard.first(where: { $0.type == type }) else { return false }
        return element.state == .strong || element.state == .waning || element.state == .always
    }

    /// Whether every element of an augment can be paid for ("wild" = any other available one).
    func canConsumeElements(_ types: [ElementType]) -> Bool {
        chooseElements(for: types) != nil
    }

    /// Consume all elements an augment lists — all or nothing ("If a single augment lists multiple
    /// element uses, all elements must be used to activate the augment"). Returns the elements
    /// consumed, or nil if the augment can't be paid for.
    @discardableResult
    func consumeElements(_ types: [ElementType]) -> [ElementType]? {
        guard let chosen = chooseElements(for: types) else { return nil }
        for type in chosen {
            if let idx = elementBoard.firstIndex(where: { $0.type == type }),
               elementBoard[idx].state != .always {
                elementBoard[idx].state = .consumed
            }
        }
        onElementChange?(.consumed)
        return chosen
    }

    /// Infuse an element: it becomes strong at the end of the current turn (it can't be consumed
    /// by the infusing figure this turn). A waning element is renewed; a strong one stays strong.
    func infuseElement(_ type: ElementType) {
        guard type != .wild, let idx = elementBoard.firstIndex(where: { $0.type == type }) else { return }
        switch elementBoard[idx].state {
        case .strong, .new, .always:
            break
        default:
            elementBoard[idx].state = .new
            onElementChange?(.infused)
        }
    }

    /// Pick concrete elements for an augment: named elements first, then each "wild" takes a
    /// different remaining available element (strong before waning).
    private func chooseElements(for types: [ElementType]) -> [ElementType]? {
        guard !types.isEmpty else { return nil }
        var chosen: [ElementType] = []
        for type in types where type != .wild {
            guard isElementAvailable(type), !chosen.contains(type) else { return nil }
            chosen.append(type)
        }
        let wildCount = types.filter { $0 == .wild }.count
        if wildCount > 0 {
            let candidates = ElementType.gameElements
                .filter { isElementAvailable($0) && !chosen.contains($0) }
                .sorted { a, b in
                    let sa = elementBoard.first { $0.type == a }?.state == .strong
                    let sb = elementBoard.first { $0.type == b }?.state == .strong
                    return sa && !sb
                }
            guard candidates.count >= wildCount else { return nil }
            chosen.append(contentsOf: candidates.prefix(wildCount))
        }
        return chosen
    }
}
