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

    /// Infuse an element: it becomes strong at the end of the current turn, so what was made
    /// this turn can't be consumed this turn. An element that was already there stays as it was
    /// until then — strong or waning, it can still be consumed, before or after the infusion,
    /// and it ends the turn strong either way (GH p.24, FAQ).
    func infuseElement(_ type: ElementType) {
        guard type != .wild, let idx = elementBoard.firstIndex(where: { $0.type == type }),
              elementBoard[idx].state != .always else { return }
        let fresh = elementsInfusedThisTurn.insert(type).inserted
        switch elementBoard[idx].state {
        case .strong, .waning, .new, .always:
            if fresh, elementBoard[idx].state != .strong { onElementChange?(.infused) }
        default:
            elementBoard[idx].state = .new
            onElementChange?(.infused)
        }
    }

    /// The end of a figure's turn: what it consumed is gone, and what it infused is strong.
    func settleElementsAtEndOfTurn() {
        for i in elementBoard.indices {
            if elementBoard[i].state == .consumed || elementBoard[i].state == .partlyConsumed {
                elementBoard[i].state = .inert
            }
            if elementBoard[i].state == .new || (elementsInfusedThisTurn.contains(elementBoard[i].type) && elementBoard[i].state != .always) {
                elementBoard[i].state = .strong
            }
        }
        elementsInfusedThisTurn = []
    }

    /// Pick concrete elements for an augment: named elements first, then each "wild" takes a
    /// different remaining available element (strong before waning).
    /// The elements a consume's "any element" would take, strong ones first, besides those it
    /// names: what is consumed when the player doesn't choose.
    func wildCandidates(besides named: [ElementType]) -> [ElementType] {
        ElementType.gameElements
            .filter { isElementAvailable($0) && !named.contains($0) }
            .sorted { a, b in
                let sa = elementBoard.first { $0.type == a }?.state == .strong
                let sb = elementBoard.first { $0.type == b }?.state == .strong
                return sa && !sb
            }
    }

    private func chooseElements(for types: [ElementType]) -> [ElementType]? {
        guard !types.isEmpty else { return nil }
        var chosen: [ElementType] = []
        for type in types where type != .wild {
            guard isElementAvailable(type), !chosen.contains(type) else { return nil }
            chosen.append(type)
        }
        let wildCount = types.filter { $0 == .wild }.count
        if wildCount > 0 {
            let candidates = wildCandidates(besides: chosen)
            guard candidates.count >= wildCount else { return nil }
            chosen.append(contentsOf: candidates.prefix(wildCount))
        }
        return chosen
    }
}
