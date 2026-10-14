import XCTest
@testable import GlavenGameLib

/// CMP-8, FAQ: "the result is distributed among all characters however they choose if the word
/// 'collective' is included" — an event's collective gold and its collective cost are the
/// players' to split (`EventCardManager.Choices.goldShares`, `goldPaid`).
@MainActor
final class CollectiveGoldTests: XCTestCase {

    private func party() throws -> (gm: GameManager, a: GameCharacter, b: GameCharacter) {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let (a, b) = (gm.game.characters[0], gm.game.characters[1])
        a.loot = 20
        b.loot = 4
        return (gm, a, b)
    }

    /// City event 17, A: "the party gains 10 collective gold".
    func testTheGoldIsSharedAsThePlayersChoose() throws {
        let (gm, a, b) = try party()
        gm.game.events.setCards("city", ["17"])
        let outcome = try XCTUnwrap(gm.eventCardManager.outcome(try XCTUnwrap(gm.eventCardManager.topCard(.city)), option: "A"))
        XCTAssertEqual(gm.eventCardManager.collectiveGold(in: outcome).gained, 10)
        var choices = EventCardManager.Choices()
        choices.goldShares = [b.id: 10]
        gm.eventCardManager.resolve(.city, option: "A", choices: choices)
        XCTAssertEqual(a.loot, 20, "all of it to the Spellweaver, as chosen")
        XCTAssertEqual(b.loot, 14)

        // Not chosen, or not adding up: shared out evenly.
        let (other, c, d) = try party()
        other.game.events.setCards("city", ["17"])
        var wrong = EventCardManager.Choices()
        wrong.goldShares = [d.id: 3]
        other.eventCardManager.resolve(.city, option: "A", choices: wrong)
        XCTAssertEqual(c.loot + d.loot, 34)
        XCTAssertEqual(c.loot, 25)
    }

    /// City event 2, A: "pay 10 collective gold" — who pays is the players' to say, each within
    /// what they have; left alone, the richest pays.
    func testTheCostIsPaidAsThePlayersChoose() throws {
        let (gm, a, b) = try party()
        gm.game.events.setCards("city", ["02"])
        var choices = EventCardManager.Choices()
        choices.goldPaid = [a.id: 6, b.id: 4]
        XCTAssertTrue(gm.eventCardManager.canPay(choices.goldPaid, total: 10))
        XCTAssertFalse(gm.eventCardManager.canPay([b.id: 10], total: 10), "no one pays more than they have")
        gm.eventCardManager.resolve(.city, option: "A", choices: choices)
        XCTAssertEqual(a.loot, 14)
        XCTAssertEqual(b.loot, 0)

        let (other, c, d) = try party()
        other.game.events.setCards("city", ["02"])
        other.eventCardManager.resolve(.city, option: "A")
        XCTAssertEqual(c.loot, 10, "the richest pays")
        XCTAssertEqual(d.loot, 4)
    }

    /// The sheet's starting split: even shares, and the richest paying first.
    func testTheSheetsStartingSplit() throws {
        let (gm, a, b) = try party()
        XCTAssertEqual(EventSheet.richestPay(10, party: [a, b]), [a.id: 10, b.id: 0])
        XCTAssertEqual(EventSheet.richestPay(20, party: [a, b])[b.id], 2, "down to even, then turn about")
        XCTAssertEqual(EventSheet.evenShares(10, party: [a, b], gameManager: gm).values.reduce(0, +), 10)
    }
}
