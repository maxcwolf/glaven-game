import XCTest
@testable import GlavenGameLib

/// Cues raised in the same instant are heard one after another, not as a pile-up.
final class BoardSoundMixerTests: XCTestCase {

    /// The delays `sounds` get when all are raised at `time`.
    private func delays(_ sounds: [BoardSound], at time: TimeInterval = 100, in mixer: inout BoardSoundMixer) -> [TimeInterval?] {
        sounds.map { mixer.admit($0, at: time) }
    }

    private func assertDelays(_ sounds: [BoardSound], _ expected: [TimeInterval?], _ message: String = "",
                              file: StaticString = #filePath, line: UInt = #line) {
        var mixer = BoardSoundMixer()
        let got = delays(sounds, in: &mixer)
        XCTAssertEqual(got.count, expected.count, file: file, line: line)
        for (index, (a, b)) in zip(got, expected).enumerated() {
            switch (a, b) {
            case (nil, nil): continue
            case (let a?, let b?): XCTAssertEqual(a, b, accuracy: 0.0001, "\(sounds[index]) \(message)", file: file, line: line)
            default: XCTFail("\(sounds[index]): got \(String(describing: a)), expected \(String(describing: b)) \(message)", file: file, line: line)
            }
        }
    }

    /// Regression: an attack that poisons played the hit and the condition's note together.
    func testAConditionLandsAfterTheBlowThatCarriedIt() {
        assertDelays([.hit, .poison], [0, 0.15])
        assertDelays([.heavyHit, .stun], [0, 0.15])
        assertDelays([.blocked, .curse], [0, 0.15], "added effects apply even when no damage was dealt")
    }

    func testSeveralConditionsLandOneAfterAnother() {
        assertDelays([.hit, .poison, .wound], [0, 0.15, 0.30])
        assertDelays([.strengthen, .bless], [0, 0.15])
    }

    /// Regression: a poison trap played the trap, the hit and the condition all at once.
    func testATrapSnapsThenHitsThenPoisons() {
        assertDelays([.trap, .hit, .poison], [0, 0.10, 0.25])
    }

    /// At full speed the targets of an area attack are hit in the same instant: one impact.
    func testTheSameCueInTheSameInstantSoundsOnce() {
        assertDelays([.hit, .hit, .heavyHit], [0, nil, nil])
        assertDelays([.summon, .summon, .summon], [0, nil, nil], "three monsters spawned by one rule")
        assertDelays([.hit, .poison, .poison], [0, 0.15, nil], "the same condition on two figures")
    }

    func testTheSameCueLaterSoundsAgain() {
        var mixer = BoardSoundMixer()
        XCTAssertEqual(mixer.admit(.hit, at: 10), 0)
        XCTAssertNil(mixer.admit(.hit, at: 10.05))
        XCTAssertEqual(mixer.admit(.hit, at: 10.5), 0)
        XCTAssertEqual(mixer.admit(.poison, at: 20), 0, "a blow long past holds nothing back")
    }

    func testShieldSoundsBeforeTheDamageThatGetsThrough() {
        assertDelays([.shield, .hit], [0, 0.10])
    }

    /// The blow, the retaliation, then the damage it does: the second hit is not swallowed as a
    /// repeat of the first.
    func testRetaliateSitsBetweenTheTwoHits() {
        assertDelays([.hit, .retaliate, .hit], [0, 0.15, 0.27])
    }

    func testCardsThenTheRoundThenTheTurn() {
        assertDelays([.cardConfirm, .round, .turn], [0, 0.35, 1.05])
    }

    func testEndingATurnThenTheLostCardAndTheNextTurn() {
        assertDelays([.endTurn, .lose, .turn], [0, 0.30, 0.35])
    }

    func testARestThenTheCardItCosts() {
        assertDelays([.rest, .lose], [0, 0.40])
    }

    func testACharacterFallsAfterTheBlow() {
        assertDelays([.hit, .exhaust], [0, 0.10])
        assertDelays([.hit, .death], [0, 0], "a monster's death lands with the blow")
    }

    func testUnrelatedCuesAreNotHeld() {
        assertDelays([.step, .door, .loot, .heal, .card], [0, 0, 0, 0, 0])
    }
}
