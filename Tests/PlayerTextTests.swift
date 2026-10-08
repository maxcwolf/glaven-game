import XCTest
@testable import GlavenGameLib

/// Everything the player reads (battle log, HUD headings, action buttons) uses display names and
/// plain words: no internal ids ("gh-brute", "bandit-guard #2"), no grid coordinates, no enum names.
@MainActor
final class PlayerTextTests: XCTestCase {

    /// Problems with one line of player text, or [] if it reads cleanly. `rawNames` are class and
    /// monster ids ("tinkerer", "bandit-guard") that must never appear as written.
    static func lint(_ text: String, rawNames: [String] = []) -> [String] {
        var problems: [String] = []
        let checks: [(pattern: String, problem: String)] = [
            (#"\b(gh|fh|jotl|cs|toa|bb|gh2e)-[a-z]"#, "edition-prefixed id"),
            (#"\b(char|summon|monster|objective)\("#, "PieceID description"),
            (#"[a-z]+-[a-z]+ #?\d"#, "monster slug"),
            (#"[A-Za-z] #\d"#, "standee written as #n"),   // "Bandit Guard #2"; "#1 Black Barrow" is a scenario
            (#"\(-?\d+, ?-?\d+\)"#, "grid coordinate"),
            (#"\.\.\."#, "three dots instead of …"),
            (#"\b[a-z]+[A-Z][a-z]+"#, "camelCase identifier"),
            (#"\(init \d+\)|\binit \d"#, "abbreviation \"init\""),
            (#"\b(TOP|BTM)\b"#, "TOP/BTM jargon"),
        ]
        for check in checks where text.range(of: check.pattern, options: .regularExpression) != nil {
            problems.append(check.problem)
        }
        for name in rawNames where text.range(of: #"\b\#(name)\b"#, options: .regularExpression) != nil {
            problems.append("raw name \"\(name)\"")
        }
        if let first = text.first, first.isLowercase {
            problems.append("starts in lowercase")
        }
        return problems
    }

    private func assertReadable(_ lines: [String], _ context: String, rawNames: [String] = [],
                                file: StaticString = #filePath, line: UInt = #line) {
        var failures: [String] = []
        for text in Set(lines).sorted() {
            let problems = Self.lint(text, rawNames: rawNames)
            if !problems.isEmpty { failures.append("\(problems.joined(separator: ", ")): \(text)") }
        }
        XCTAssertEqual(failures, [], "\(context): player text that reads like code", file: file, line: line)
    }

    /// Lines the game used to show (from the UX audit's playthrough) all fail the lint; their
    /// rewrites pass.
    func testLintCatchesTheOldWording() {
        let old = [
            "Placed gh-cragheart at (3, 4)",
            "tinkerer → bandit-guard #1: 1 +0(mod) -1(shield) = 0",
            "gh-tinkerer: TOP Stun Shot (init 20) / BTM Hook Gun",
            "bandit-guard #2: Move 2 to (2,2)",
            "Monsters acting...",
            "char(gh-scoundrel): Moved to (1, 5)",
            "Turn: tinkerer (20)",
        ]
        for line in old {
            XCTAssertFalse(Self.lint(line, rawNames: ["tinkerer", "bandit-guard"]).isEmpty, "lint should reject \"\(line)\"")
        }
        let new = [
            "Cragheart takes position",
            "Tinkerer attacks Bandit Guard 1: 1 + 0 − 1 shield = no damage",
            "Tinkerer plays Stun Shot (20) and Hook Gun",
            "Bandit Guard 2 moves 2 hexes",
            "Bandit Guard acting…",
            "Tinkerer\u{2019}s Turn \u{00B7} 20",
        ]
        for line in new {
            XCTAssertEqual(Self.lint(line), [], line)
        }
    }

    // MARK: - Battle log

    /// Seeded games covering bandits, archers, a boss and its summons, a summoning party,
    /// traps, doors, loot, rests and elements.
    func testBattleLogUsesDisplayNames() async throws {
        let games: [(scenario: String, seed: UInt64, party: [String]?)] = [
            ("1", 1, nil), ("2", 3, nil), ("4", 5, ["tinkerer", "mindthief", "spellweaver"]), ("3", 7, nil),
        ]
        for game in games {
            var options = ScenarioSimulator.Options(seed: game.seed)
            if let party = game.party { options.characters = party }
            let sim = try ScenarioSimulator(scenario: game.scenario, options: options)
            await sim.play(rounds: 4)
            let messages = sim.coord.turnLog.filter { !$0.isRoundHeader }.map(\.message)
            XCTAssertGreaterThan(messages.count, 30)
            let rawNames = sim.gm.game.characters.map(\.name) + sim.gm.game.monsters.map(\.name)
            assertReadable(messages, "scenario \(game.scenario)", rawNames: rawNames)
        }
    }

    /// Coordinates and raw sums stay available to test transcripts, outside the player's text.
    func testTechnicalDetailMovesToTheTrace() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 1))
        await sim.play(rounds: 2)
        let moves = sim.coord.turnLog.filter { $0.category == .move && $0.message.contains(" moves ") }
        XCTAssertFalse(moves.isEmpty)
        for move in moves {
            XCTAssertNotNil(move.trace?.range(of: #"to \(-?\d+,-?\d+\)"#, options: .regularExpression), move.message)
        }
        let attacks = sim.coord.turnLog.filter { $0.category == .attack && $0.message.contains(" attacks ") }
        XCTAssertFalse(attacks.isEmpty)
        for attack in attacks {
            XCTAssertTrue(attack.message.hasSuffix("damage") || attack.message.hasSuffix("miss"), attack.message)
            XCTAssertNotNil(attack.trace, "the compact sum is kept for transcripts")
        }
    }

    // MARK: - HUD

    func testPhaseTitleAndRoundFollowThePlay() async throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        // Setup has been finished by the simulator; round 1's cards are being chosen.
        XCTAssertEqual(sim.coord.phaseTitle, "Choose Cards")
        XCTAssertEqual(sim.coord.displayedRound, 1, "not \"Round 0\" while choosing round 1's cards")

        var turnTitles: [String] = []
        await sim.play(rounds: 2) {
            if sim.coord.boardPhase == .execution {
                turnTitles.append(sim.coord.phaseTitle)
                XCTAssertEqual(sim.coord.displayedRound, sim.gm.game.round)
            }
        }
        XCTAssertFalse(turnTitles.isEmpty)
        for title in Set(turnTitles) {
            XCTAssertNotNil(title.range(of: #"^[A-Z][A-Za-z ]+\x{2019}s Turn \x{00B7} \d+$"#, options: .regularExpression)
                            ?? (title == "Round in Progress" ? title.startIndex..<title.endIndex : nil),
                            "unexpected heading \(title)")
        }
        assertReadable(turnTitles, "turn headings")
    }

    func testSetupHidesTheRoundCounter() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "tinkerer", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        XCTAssertEqual(gm.boardCoordinator.phaseTitle, "Place Your Characters")
        XCTAssertNil(gm.boardCoordinator.displayedRound)
    }

    // MARK: - Names and terms

    func testEveryActionTypeHasAPlayerFacingTitle() {
        for type in ActionType.allCases {
            let title = GameText.actionTitle(ActionModel(type: type, value: .int(2)))
            XCTAssertFalse(title.isEmpty, "\(type)")
            XCTAssertEqual(Self.lint(title), [], "\(type): \(title)")
        }
        XCTAssertEqual(GameText.actionTitle(ActionModel(type: .sufferDamage, value: .int(1))), "Suffer 1 Damage")
        XCTAssertEqual(GameText.actionTitle(ActionModel(type: .condition, value: .string("poison"))), "Poison")
        XCTAssertEqual(GameText.actionTitle(ActionModel(type: .element, value: .string("fire"))), "Infuse Fire")
        XCTAssertEqual(GameText.actionTitle(ActionModel(type: .attack, value: .int(3),
                                                        subActions: [ActionModel(type: .range, value: .int(2))])),
                       "Attack 3, Range 2")
    }

    func testConditionAndElementNames() {
        for condition in ConditionName.allCases {
            XCTAssertEqual(Self.lint(GameText.conditionName(condition)), [], "\(condition)")
        }
        for element in ElementType.allCases {
            XCTAssertEqual(Self.lint(GameText.elementName(element)), [], "\(element)")
        }
        XCTAssertEqual(GameText.conditionName(.immobilize), "Immobilize")
        XCTAssertEqual(GameText.list(["Fire", "Ice", "Air"]), "Fire, Ice and Air")
    }

    func testPieceNames() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = try XCTUnwrap(gm.game.characters.first)
        XCTAssertEqual(GameText.pieceName(.character(brute.id), game: gm.game, labels: gm.editionStore), "Brute")
        brute.title = "Grok"
        XCTAssertEqual(GameText.pieceName(.character(brute.id), game: gm.game, labels: gm.editionStore), "Grok")
        XCTAssertEqual(GameText.pieceName(.monster(name: "bandit-guard", standee: 2), game: gm.game,
                                          labels: gm.editionStore), "Bandit Guard 2")
        XCTAssertEqual(GameText.titleCased("gh-living-bones"), "Living Bones")
    }

    func testReadableAttackSums() {
        let plus1 = AttackModifier(type: .plus1, value: 1, valueType: .plus)
        XCTAssertEqual(CombatResolver.readableBreakdown(base: 2, isPoisoned: false, preDrawnCards: [plus1],
                                                       shield: 0, isMiss: false, finalDamage: 3), "2 + 1 = 3 damage")
        XCTAssertEqual(CombatResolver.readableBreakdown(base: 1, isPoisoned: false, preDrawnCards: [],
                                                       shield: 1, isMiss: false, finalDamage: 0), "1 − 1 shield = no damage")
        XCTAssertEqual(CombatResolver.readableBreakdown(base: 2, isPoisoned: true,
                                                       preDrawnCards: [AttackModifier(type: .double_, value: 2, valueType: .multiply)],
                                                       shield: 0, isMiss: false, finalDamage: 6), "2 + 1 poison ×2 = 6 damage")
        XCTAssertEqual(CombatResolver.readableBreakdown(base: 3, isPoisoned: false, preDrawnCards: [],
                                                       shield: 0, isMiss: true, finalDamage: 0), "miss")
    }
}
