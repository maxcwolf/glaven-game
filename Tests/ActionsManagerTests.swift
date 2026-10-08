import XCTest
@testable import GlavenGameLib

/// Regression tests for interactive action application in ActionsManager.
///  - A Heal must actually remove the conditions it can clear (Poison/Wound), matching
///    its own isApplicable check and the long-rest convention. It must NOT clear
///    conditions Heal cannot remove (immobilize/stun/disarm/muddle…).
///  - A combined element consume ("fire:earth") needs and consumes ALL listed elements
///    ("If a single augment lists multiple element uses, all elements must be used").
final class ActionsManagerTests: XCTestCase {

    private func manager(_ t: TestGame) -> ActionsManager {
        ActionsManager(game: t.game, monsterManager: t.monsterManager)
    }

    // MARK: - #15 Heal removes Poison/Wound

    func testInteractiveHeal_removesPoisonAndWound_evenAtFullHealth() {
        let t = TestGame()
        let char = t.addCharacter()
        char.maxHealth = 10; char.health = 10
        char.entityConditions = [EntityCondition(name: .poison), EntityCondition(name: .wound)]

        let am = manager(t)
        let action = ActionModel(type: .heal, value: .int(3))
        XCTAssertTrue(am.isApplicable(entity: char, action: action, index: "0"),
                      "heal is applicable to clear poison/wound even at full health")

        am.applyInteractiveAction(entity: char, figure: char,
                                  interactiveAction: InteractiveAction(action: action, index: "0"))

        XCTAssertFalse(char.entityConditions.contains { $0.name == .poison }, "heal removes poison")
        XCTAssertFalse(char.entityConditions.contains { $0.name == .wound }, "heal removes wound")
        XCTAssertEqual(char.health, 10, "already at full health")
    }

    func testInteractiveHeal_doesNotRemoveImmobilize() {
        // Guard: Heal clears only Poison/Wound, never immobilize/stun/etc.
        let t = TestGame()
        let char = t.addCharacter()
        char.maxHealth = 10; char.health = 5
        char.entityConditions = [EntityCondition(name: .immobilize)]

        let am = manager(t)
        let action = ActionModel(type: .heal, value: .int(3))
        am.applyInteractiveAction(entity: char, figure: char,
                                  interactiveAction: InteractiveAction(action: action, index: "0"))

        XCTAssertEqual(char.health, 8, "heal restores HP")
        XCTAssertTrue(char.entityConditions.contains { $0.name == .immobilize },
                      "heal must NOT remove immobilize")
    }

    // MARK: - Combined element consume requires every listed element

    func testInteractiveElementConsume_consumesAllOfList() {
        let t = TestGame()
        let char = t.addCharacter()
        t.game.elementBoard = ElementModel.defaultBoard()
        func setState(_ type: ElementType, _ state: ElementState) {
            if let i = t.game.elementBoard.firstIndex(where: { $0.type == type }) {
                t.game.elementBoard[i].state = state
            }
        }
        setState(.fire, .strong)
        setState(.earth, .strong)

        let am = manager(t)
        let action = ActionModel(type: .element, value: .string("fire:earth"), valueType: .minus)
        am.applyInteractiveAction(entity: char, figure: char,
                                  interactiveAction: InteractiveAction(action: action, index: "0"))

        func state(_ type: ElementType) -> ElementState {
            t.game.elementBoard.first { $0.type == type }!.state
        }
        XCTAssertEqual(state(.fire), .consumed)
        XCTAssertEqual(state(.earth), .consumed, "a combined consume 'fire:earth' consumes both elements")
    }

    func testInteractiveElementConsume_needsEveryListedElement() {
        let t = TestGame()
        let char = t.addCharacter()
        t.game.elementBoard = ElementModel.defaultBoard()
        if let i = t.game.elementBoard.firstIndex(where: { $0.type == .fire }) {
            t.game.elementBoard[i].state = .strong
        }
        let am = manager(t)
        let action = ActionModel(type: .element, value: .string("fire:earth"), valueType: .minus)
        am.applyInteractiveAction(entity: char, figure: char,
                                  interactiveAction: InteractiveAction(action: action, index: "0"))
        XCTAssertEqual(t.game.elementBoard.first { $0.type == .fire }!.state, .strong,
                       "earth is inert, so the augment can't be paid and fire is not consumed")
    }

    func testInfusingWaningElementMakesItStrongAgain() {
        let game = GameState()
        game.elementBoard = ElementModel.defaultBoard()
        let i = game.elementBoard.firstIndex { $0.type == .ice }!
        game.elementBoard[i].state = .waning
        game.infuseElement(.ice)
        XCTAssertEqual(game.elementBoard[i].state, .new, "becomes strong at the end of the turn")
    }
}
