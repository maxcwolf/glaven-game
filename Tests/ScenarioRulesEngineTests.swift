import XCTest
@testable import GlavenGameLib

// MARK: - Expression evaluator

final class ScenarioExpressionTests: XCTestCase {

    private func cond(_ s: String, _ vars: [String: Int] = [:]) -> Bool? {
        ScenarioExpression.condition(s, variables: vars)
    }

    func testModuloRoundExpressions() {
        // These crashed NSPredicate(format:) (NSInvalidArgumentException on '%').
        XCTAssertEqual(cond("R % 2 == 0", ["R": 2]), true)
        XCTAssertEqual(cond("R % 2 == 0", ["R": 3]), false)
        XCTAssertEqual(cond("R % 2 == 1", ["R": 1]), true)
        XCTAssertEqual(cond("R % 4 == 0", ["R": 8]), true)
        XCTAssertEqual(cond("R % 6 == 5", ["R": 11]), true)
    }

    func testCharacterCountAndLogicalOperators() {
        XCTAssertEqual(cond("R % 2 == 0 || C > 2", ["R": 1, "C": 3]), true)
        XCTAssertEqual(cond("R % 2 == 0 || C > 2", ["R": 1, "C": 2]), false)
        XCTAssertEqual(cond("R % 2 == 0 || C > 2", ["R": 2, "C": 2]), true)
        XCTAssertEqual(cond("R == 1 || R == 3 || R == 5", ["R": 3]), true)
        XCTAssertEqual(cond("R == 1 || R == 3 || R == 5", ["R": 4]), false)
        XCTAssertEqual(cond("R > 4 && C >= 3", ["R": 5, "C": 3]), true)
        XCTAssertEqual(cond("R > 4 and C >= 3", ["R": 5, "C": 2]), false)
        XCTAssertEqual(cond("R == 1 or R == 2", ["R": 2]), true)
        XCTAssertEqual(cond("!(R == 1)", ["R": 1]), false)
        XCTAssertEqual(cond("not false"), true)
        XCTAssertEqual(cond("R != 3", ["R": 3]), false)
        XCTAssertEqual(cond("R <= 3", ["R": 3]), true)
        XCTAssertEqual(cond("R === 3", ["R": 3]), true)
        XCTAssertEqual(cond("true"), true)
        XCTAssertEqual(cond("false"), false)
    }

    func testArithmeticPrecedence() {
        XCTAssertEqual(ScenarioExpression.number("1 + 2 * 3"), 7)
        XCTAssertEqual(ScenarioExpression.number("(1 + 2) * 3"), 9)
        XCTAssertEqual(ScenarioExpression.number("10 % 4"), 2)
        XCTAssertEqual(ScenarioExpression.number("-R + 5", variables: ["R": 2]), 3)
        XCTAssertEqual(ScenarioExpression.number("7 / 2"), 3.5)
        XCTAssertEqual(cond("1 + 2 * 3 == 7"), true)
    }

    func testMultiplyByLowercaseX() {
        XCTAssertEqual(ScenarioExpression.integerValue("(2xC)+L-2", variables: ["C": 3, "L": 2]), 6)
        XCTAssertEqual(ScenarioExpression.integerValue("Cx(3+L)", variables: ["C": 2, "L": 1]), 8)
        XCTAssertEqual(ScenarioExpression.integerValue("HxC", variables: ["H": 5, "C": 3]), 15)
        XCTAssertEqual(ScenarioExpression.integerValue("Hx2", variables: ["H": 7]), 14)
        XCTAssertEqual(ScenarioExpression.integerValue("4+(2xL)", variables: ["L": 3]), 10)
        // A bare lowercase x is not a variable.
        XCTAssertNil(ScenarioExpression.integerValue("x"))
    }

    func testIntegerValueBracketFunctions() {
        XCTAssertEqual(ScenarioExpression.integerValue("3"), 3)
        XCTAssertEqual(ScenarioExpression.integerValue("F", variables: ["F": 4]), 4)
        XCTAssertEqual(ScenarioExpression.integerValue("[X/2{$math.ceil}]", variables: ["X": 5]), 3)
        XCTAssertEqual(ScenarioExpression.integerValue("[2+(LxC/2){$math.floor}]", variables: ["L": 1, "C": 3]), 3)
        XCTAssertEqual(ScenarioExpression.integerValue("[Hx2]", variables: ["H": 4]), 8)
        XCTAssertEqual(ScenarioExpression.integerValue("[L-3{$math.max:1}]", variables: ["L": 1]), 1)
        XCTAssertEqual(ScenarioExpression.integerValue("LxC/2", variables: ["L": 3, "C": 3]), 4, "truncates toward zero")
    }

    func testHealthFilterVariables() {
        XCTAssertEqual(cond("HP < H", ["HP": 3, "H": 5]), true)
        XCTAssertEqual(cond("HP == H", ["HP": 5, "H": 5]), true)
    }

    func testMalformedInputReturnsNilWithoutCrashing() {
        let bad = ["", "   ", "R %", "%", "R == == 1", "(R == 1", "R == 1)", "R @ 2", "R %% 2",
                   "R = 1", "R & 1", "R | 1", "()", "[", "1 2", "R ==", "&& R", "{$math.ceil}",
                   "R % 0 == 0", "1 / 0", "Z == 1", "R == 1 && Q > 2", "SUBQUERY(x, $x, TRUE)",
                   "'a' == 'a'", "R == 1;", "\u{0}"]
        for source in bad {
            XCTAssertNil(ScenarioExpression.condition(source, variables: ["R": 1, "C": 2]),
                         "expected nil for \(source.debugDescription)")
        }
        XCTAssertNil(ScenarioExpression.integerValue("[1/0{$math.ceil}]"))
        XCTAssertNil(ScenarioExpression.integerValue("[2{$math.bogus}]"))
        XCTAssertNil(ScenarioExpression.integerValue("99999999999 * 99999999999"), "too large for Int")

        // Deep nesting is rejected instead of exhausting the stack.
        let deep = String(repeating: "(", count: 5000) + "1" + String(repeating: ")", count: 5000)
        XCTAssertNil(ScenarioExpression.number(deep))
        let deepNot = String(repeating: "!", count: 5000) + "1"
        XCTAssertNil(ScenarioExpression.number(deepNot))
        // Moderate nesting is fine.
        let ok = String(repeating: "(", count: 20) + "1" + String(repeating: ")", count: 20)
        XCTAssertEqual(ScenarioExpression.number(ok), 1)
    }

    func testVariablesCollected() {
        let node = ScenarioExpression.parse("R % 2 == 0 || C > 2")
        XCTAssertNotNil(node)
        XCTAssertEqual(node.map(ScenarioExpression.variables(in:)), ["R", "C"])
    }
}

// MARK: - Every expression in the bundled data parses

final class ScenarioDataExpressionTests: XCTestCase {

    func testEveryGHRuleExpressionParsesAndEvaluates() {
        let store = EditionDataStore()
        store.loadAllEditions()

        var checked = 0
        for edition in ["gh", "fh", "jotl"] {
            let all = store.scenarios(for: edition).map { ("scenario", $0) }
                + store.sections(for: edition).map { ("section", $0) }
            if edition == "gh" {
                XCTAssertGreaterThanOrEqual(store.scenarios(for: edition).count, 100, "gh scenarios loaded")
                XCTAssertFalse(store.sections(for: edition).isEmpty, "gh sections loaded")
            }

            for (kind, data) in all {
                for (index, rule) in (data.rules ?? []).enumerated() {
                    let label = "\(edition) \(kind) \(data.index) rule \(index)"

                    if let round = rule.round {
                        checked += 1
                        let trimmed = round.trimmingCharacters(in: .whitespaces)
                        if Int(trimmed) == nil && trimmed != "start" {
                            guard let node = ScenarioExpression.parse(trimmed) else {
                                XCTFail("\(label): round '\(round)' does not parse"); continue
                            }
                            XCTAssertTrue(ScenarioExpression.variables(in: node).isSubset(of: ["R", "C", "L"]),
                                          "\(label): round '\(round)' uses unknown variables")
                            for r in 1...12 {
                                for c in 1...4 {
                                    XCTAssertNotNil(ScenarioExpression.condition(trimmed, variables: ["R": r, "C": c, "L": 1]),
                                                    "\(label): round '\(round)' fails at R=\(r) C=\(c)")
                                }
                            }
                        }
                    }

                    for spawn in rule.spawns ?? [] {
                        if case .string(let s) = spawn.count {
                            checked += 1
                            XCTAssertNotNil(ScenarioExpression.integerValue(s, variables: ["C": 2, "L": 1, "R": 1, "F": 1]),
                                            "\(label): spawn count '\(s)' does not evaluate")
                        }
                    }

                    for figure in rule.figures ?? [] {
                        if ["damage", "heal", "setHp"].contains(figure.type ?? ""), case .string(let s) = figure.value {
                            checked += 1
                            // F: how many figures the rule's triggers count ("for each bone pile").
                            XCTAssertNotNil(ScenarioExpression.integerValue(s, variables: ["C": 2, "L": 1, "R": 1, "F": 1]),
                                            "\(label): \(figure.type ?? "") value '\(s)' does not evaluate")
                        }
                        if figure.type == "killed", case .string(let s) = figure.value, s != "all" {
                            checked += 1
                            XCTAssertNotNil(ScenarioExpression.integerValue(s, variables: ["C": 2, "L": 1, "R": 1]),
                                            "\(label): killed value '\(s)' does not evaluate")
                        }
                        if let hp = figure.identifier?.hp {
                            checked += 1
                            XCTAssertNotNil(ScenarioExpression.condition(hp, variables: ["HP": 3, "H": 5, "C": 2, "L": 1]),
                                            "\(label): hp filter '\(hp)' does not evaluate")
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 150, "expected to check the bundled rule expressions")
    }

    func testPreviouslyCrashingScenariosEvaluate() {
        let store = EditionDataStore()
        store.loadAllEditions()
        for index in ["3", "36", "61", "70", "71", "72", "74", "86"] {
            guard let data = store.scenarioData(index: index, edition: "gh") else {
                XCTFail("missing gh scenario \(index)"); continue
            }
            let modulo = (data.rules ?? []).compactMap(\.round).filter { $0.contains("%") }
            XCTAssertFalse(modulo.isEmpty, "scenario \(index) should contain a % round expression")
            for expr in modulo {
                XCTAssertNotNil(ScenarioExpression.condition(expr, variables: ["R": 1, "C": 2, "L": 1]),
                                "scenario \(index): '\(expr)'")
            }
        }
    }
}

// MARK: - Rules manager

final class ScenarioRulesManagerPhaseTests: XCTestCase {

    // MARK: Fixtures

    private func makeGame(characters: Int = 2, level: Int = 1) -> TestGame {
        let t = TestGame(level: level)
        let names = ["brute", "tinkerer", "spellweaver", "scoundrel"]
        for i in 0..<characters {
            t.addCharacter(name: names[i], pos: HexCoord(1, i + 1))
        }
        return t
    }

    private func rulesManager(_ t: TestGame) -> ScenarioRulesManager {
        ScenarioRulesManager(game: t.game, monsterManager: t.monsterManager, entityManager: t.entityManager)
    }

    @discardableResult
    private func installRules(_ json: String, on t: TestGame, index: String = "900") -> Scenario {
        let rules = try! JSONDecoder().decode([ScenarioRule].self, from: Data(json.utf8))
        var data = ScenarioData(index: index, name: "Test", edition: "gh")
        data.rules = rules
        let scenario = Scenario(data: data)
        t.game.scenario = scenario
        return scenario
    }

    @discardableResult
    private func installRealScenario(_ index: String, on t: TestGame) -> Scenario {
        let data = t.editionStore.scenarioData(index: index, edition: "gh")!
        let scenario = Scenario(data: data)
        t.game.scenario = scenario
        return scenario
    }

    private func curses(_ c: GameCharacter) -> Int {
        c.attackModifierDeck.cards.filter { $0.type == .curse }.count
    }

    private func addObjective(_ t: TestGame, name: String, marker: String, count: Int = 1, hp: Int = 5) -> GameObjectiveContainer {
        let container = GameObjectiveContainer(name: name, edition: "gh", title: name)
        for i in 0..<count {
            let e = GameObjectiveEntity(number: i + 1, health: hp, maxHealth: hp)
            e.marker = marker
            container.entities.append(e)
        }
        t.game.figures.append(.objective(container))
        return container
    }

    // MARK: Phase eligibility

    func testPhaseEligibility() throws {
        let rules = try JSONDecoder().decode([ScenarioRule].self, from: Data(#"""
        [{"round": "R == 1", "start": true},
         {"round": "R == 1"},
         {"round": "true", "always": true},
         {"figures": [{"type": "dead", "identifier": {"type": "monster", "name": "x"}}]},
         {"note": "no conditions"}]
        """#.utf8))
        let e = ScenarioRulesManager.isEligible
        XCTAssertEqual(RulePhase.allCases.map { e(rules[0], $0) }, [true, false, false])
        XCTAssertEqual(RulePhase.allCases.map { e(rules[1], $0) }, [false, true, false])
        XCTAssertEqual(RulePhase.allCases.map { e(rules[2], $0) }, [true, true, true])
        XCTAssertEqual(RulePhase.allCases.map { e(rules[3], $0) }, [true, true, true])
        XCTAssertEqual(RulePhase.allCases.map { e(rules[4], $0) }, [false, false, false])
    }

    // MARK: Crash regression (bug 1)

    func testScenario3ModuloSpawnDoesNotCrashAndFiresAtOddRoundEnd() {
        let t = makeGame(characters: 2)
        installRealScenario("3", on: t)
        let rm = rulesManager(t)
        func guards() -> Int { t.game.monsters.first { $0.name == "inox-guard" }?.entities.count ?? 0 }

        t.game.round = 1
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(guards(), 0, "non-start rule must not fire at round start")
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(guards(), 1, "R % 2 == 1 spawns one 2-player inox guard at the end of round 1")
        rm.evaluateRules()
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(guards(), 1, "fires at most once per round")

        t.game.round = 2
        rm.evaluateRules(phase: .roundStart)
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(guards(), 1, "even round: no spawn")

        t.game.round = 3
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(guards(), 2)
    }

    func testEveryGHScenarioEvaluatesAllPhasesWithoutCrashing() {
        let t = makeGame(characters: 3)
        let rm = rulesManager(t)
        for data in t.editionStore.scenarios(for: "gh") {
            t.game.scenario = Scenario(data: data)
            for round in 1...3 {
                t.game.round = round
                rm.evaluateRules(phase: .roundStart)
                rm.evaluateRules(phase: .figureChange)
                rm.evaluateRules(phase: .roundEnd)
            }
        }
    }

    func testCharacterCountVariableIsSubstituted() {
        let json = #"[{"round": "R % 2 == 0 || C > 2", "finish": "won"}]"#

        let three = makeGame(characters: 3)
        let s3 = installRules(json, on: three)
        three.game.round = 1
        rulesManager(three).evaluateRules(phase: .roundEnd)
        XCTAssertEqual(s3.pendingFinish, "won", "C = 3 satisfies C > 2 in round 1")

        let two = makeGame(characters: 2)
        let s2 = installRules(json, on: two)
        let rm2 = rulesManager(two)
        two.game.round = 1
        rm2.evaluateRules(phase: .roundEnd)
        XCTAssertNil(s2.pendingFinish, "C = 2, odd round")
        two.game.round = 2
        rm2.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(s2.pendingFinish, "won")
    }

    func testUnparseableRoundExpressionIsNotTriggered() {
        let t = makeGame()
        let scenario = installRules(#"[{"round": "R %% 2 ==", "finish": "won"}, {"round": "Q > 1", "finish": "lost"}]"#, on: t)
        t.game.round = 2
        let rm = rulesManager(t)
        for phase in RulePhase.allCases { rm.evaluateRules(phase: phase) }
        XCTAssertNil(scenario.pendingFinish)
    }

    // MARK: Repeat firing (bug 2)

    func testScenario2CursesAddedOnceNotPerKill() {
        let t = makeGame(characters: 2)
        installRealScenario("2", on: t)
        let rm = rulesManager(t)
        let chars = t.game.characters
        let before = chars.map(curses)

        t.game.round = 1
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(chars.map(curses), before.map { $0 + 3 }, "R == 1 start rule adds 3 curses")

        // Kills during round 1 re-evaluate rules — must not add more curses.
        for _ in 0..<4 { rm.evaluateRules() }
        rm.evaluateRules(phase: .roundStart)
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(chars.map(curses), before.map { $0 + 3 })

        t.game.round = 2
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(chars.map(curses), before.map { $0 + 3 })
    }

    func testCursesAreShuffledIntoUndrawnCards() {
        let t = makeGame(characters: 1)
        installRules(#"[{"round": "R == 1", "start": true, "figures": [{"identifier": {"type": "character", "name": ".*"}, "type": "amAdd", "value": "curse:3"}]}]"#, on: t)
        let c = t.game.characters[0]
        c.attackModifierDeck.current = 5 // 6 cards already drawn
        t.game.round = 1
        rulesManager(t).evaluateRules(phase: .roundStart)
        let positions = c.attackModifierDeck.cards.indices.filter { c.attackModifierDeck.cards[$0].type == .curse }
        XCTAssertEqual(positions.count, 3)
        XCTAssertTrue(positions.allSatisfy { $0 > 5 }, "curses go into the undrawn part of the deck")
        XCTAssertEqual(Set(c.attackModifierDeck.cards.map(\.id)).count, c.attackModifierDeck.cards.count, "unique card ids")
    }

    func testMinusOneCardsHaveValueAndSurviveReshuffle() {
        let t = makeGame(characters: 1)
        installRules(#"[{"round": "R == 1", "start": true, "figures": [{"identifier": {"type": "character", "name": ".*"}, "type": "amAdd", "value": "minus1:3"}]}]"#, on: t)
        let c = t.game.characters[0]
        let baseMinus = c.attackModifierDeck.attackModifiers.filter { $0.type == .minus1 }.count
        t.game.round = 1
        rulesManager(t).evaluateRules(phase: .roundStart)
        let added = c.attackModifierDeck.cards.filter { $0.type == .minus1 }
        XCTAssertEqual(added.count, baseMinus + 3)
        XCTAssertTrue(added.allSatisfy { $0.value == -1 })
        XCTAssertEqual(c.attackModifierDeck.attackModifiers.filter { $0.type == .minus1 }.count, baseMinus + 3,
                       "scenario -1 cards persist through reshuffles")
    }

    func testOnceRuleFiresOnlyOnceAcrossPhasesAndRounds() {
        let t = makeGame(characters: 1)
        installRules(#"[{"round": "true", "always": true, "once": true, "figures": [{"identifier": {"type": "character", "name": ".*"}, "type": "amAdd", "value": "curse:1"}]}]"#, on: t)
        let rm = rulesManager(t)
        let c = t.game.characters[0]
        let before = curses(c)
        for round in 1...3 {
            t.game.round = round
            for phase in RulePhase.allCases { rm.evaluateRules(phase: phase) }
        }
        XCTAssertEqual(curses(c), before + 1)
    }

    func testRoundKeyIsRecordedInAppliedRules() {
        let t = makeGame()
        let scenario = installRules(#"[{"round": "true", "finish": "won"}]"#, on: t)
        t.game.round = 4
        rulesManager(t).evaluateRules(phase: .roundEnd)
        let key = scenario.ruleKey(index: 0)
        XCTAssertTrue(scenario.appliedRules.contains(key))
        XCTAssertTrue(scenario.appliedRules.contains(ScenarioRulesManager.roundKey(key, round: 4)))

        // Undo restores appliedRules from a snapshot; without the round key the rule can fire again.
        scenario.appliedRules = []
        scenario.pendingFinish = nil
        rulesManager(t).evaluateRules(phase: .roundEnd)
        XCTAssertEqual(scenario.pendingFinish, "won")
    }

    // MARK: Start vs end of round (bug 3)

    func testScenario27WinsAtEndOfRound10NotStart() {
        let t = makeGame()
        let scenario = installRealScenario("27", on: t)
        let rm = rulesManager(t)

        t.game.round = 9
        rm.evaluateRules(phase: .roundStart)
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertNil(scenario.pendingFinish)

        t.game.round = 10
        rm.evaluateRules(phase: .roundStart)
        rm.evaluateRules()
        XCTAssertNil(scenario.pendingFinish, "R == 10 is an end-of-round rule")
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(scenario.pendingFinish, "won")
    }

    func testScenario60DamageAllAtRoundStartAfterRound6AndLossAtEndOfRound12() {
        let t = makeGame(characters: 2)
        let scenario = installRealScenario("60", on: t)
        let monster = t.addSimpleMonster(name: "test-monster", positions: [(1, HexCoord(5, 5), 10)])
        let summon = GameSummon(name: "bear", health: 6, maxHealth: 6)
        t.game.characters[0].summons.append(summon)
        let rm = rulesManager(t)

        t.game.round = 6
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(t.game.characters.map(\.health), [10, 10], "R > 6 not yet")

        t.game.round = 7
        rm.evaluateRules(phase: .roundStart)
        rm.evaluateRules()
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(t.game.characters.map(\.health), [8, 8], "identifier type 'all' hits characters once per round")
        XCTAssertEqual(monster.entities[0].health, 8, "... monsters")
        XCTAssertEqual(summon.health, 4, "... and summons")

        t.game.round = 12
        rm.evaluateRules(phase: .roundStart)
        XCTAssertNil(scenario.pendingFinish, "R == 12 loss is an end-of-round rule")
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(scenario.pendingFinish, "lost")
    }

    // MARK: Figure triggers & spawn counts (bugs 4 & 5)

    func testAlwaysDeadTriggerSpawnsFPerDeadObjectiveOnFigureChange() {
        let t = makeGame(characters: 2)
        installRules(#"""
        [{"round": "true", "always": true, "once": true,
          "figures": [{"identifier": {"type": "objective", "edition": "objective", "name": "Grave", "marker": "a"}, "type": "dead"}],
          "spawns": [{"monster": {"name": "living-corpse", "player2": "normal", "player3": "normal", "player4": "elite"}, "marker": "a", "count": "F"}]}]
        """#, on: t)
        let graves = addObjective(t, name: "Grave", marker: "a", count: 2)
        let rm = rulesManager(t)
        func corpses() -> [GameMonsterEntity] { t.game.monsters.first { $0.name == "living-corpse" }?.entities ?? [] }

        t.game.round = 1
        rm.evaluateRules()
        XCTAssertTrue(corpses().isEmpty)

        graves.entities[0].dead = true
        rm.evaluateRules()
        XCTAssertTrue(corpses().isEmpty, "one grave still standing")

        graves.entities[1].dead = true
        rm.evaluateRules()
        XCTAssertEqual(corpses().count, 2, "F = number of destroyed graves")
        XCTAssertTrue(corpses().allSatisfy { $0.markers.contains("a") })

        rm.evaluateRules()
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(corpses().count, 2, "once rule")
    }

    func testNonAlwaysPresentTriggerFiresOncePerRoundEnd() {
        let t = makeGame(characters: 2)
        installRules(#"""
        [{"round": "true",
          "figures": [{"identifier": {"type": "objective", "edition": "objective", "name": "Water Pump", "marker": "a"}, "type": "present"}],
          "spawns": [{"monster": {"name": "black-imp", "type": "normal"}, "marker": "a", "count": "F"}]}]
        """#, on: t)
        let pump = addObjective(t, name: "Water Pump", marker: "a", hp: 0)
        let rm = rulesManager(t)
        func imps() -> Int { t.game.monsters.first { $0.name == "black-imp" }?.aliveEntities.count ?? 0 }

        t.game.round = 1
        rm.evaluateRules()
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(imps(), 0, "end-of-round rule")
        rm.evaluateRules(phase: .roundEnd)
        rm.evaluateRules(phase: .roundEnd)
        rm.evaluateRules()
        XCTAssertEqual(imps(), 1)

        t.game.round = 2
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(imps(), 2)

        pump.entities[0].dead = true
        t.game.round = 3
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(imps(), 2, "pump gone: no spawn")
    }

    func testKilledThreshold() {
        let t = makeGame()
        let scenario = installRules(#"""
        [{"round": "true", "always": true, "once": true,
          "figures": [{"identifier": {"type": "monster", "name": "night-demon"}, "type": "killed", "value": "6"}],
          "finish": "won"}]
        """#, on: t)
        let rm = rulesManager(t)
        t.game.round = 2
        scenario.killCounts["night-demon"] = 5
        rm.evaluateRules()
        XCTAssertNil(scenario.pendingFinish)
        scenario.killCounts["night-demon"] = 6
        rm.evaluateRules()
        XCTAssertEqual(scenario.pendingFinish, "won")
    }

    func testDamageValueExpressionUsesCharacterCountAndLevel() {
        let t = makeGame(characters: 3, level: 2)
        installRules(#"""
        [{"round": "true", "figures": [
            {"type": "present", "identifier": {"type": "objective", "edition": "objective", "name": "Door", "marker": "1"}},
            {"type": "damage", "value": "(2xC)+L-2", "identifier": {"type": "monster", "edition": "gh", "name": "prime-demon"}}]}]
        """#, on: t)
        _ = addObjective(t, name: "Door", marker: "1")
        let demon = t.addSimpleMonster(name: "prime-demon", positions: [(1, HexCoord(6, 6), 30)])
        t.game.round = 1
        rulesManager(t).evaluateRules(phase: .roundEnd)
        XCTAssertEqual(demon.entities[0].health, 24, "(2x3)+2-2 = 6 damage")
    }

    func testHpIdentifierFilter() {
        let t = makeGame()
        installRules(#"[{"round": "true", "figures": [{"identifier": {"type": "monster", "name": ".*", "hp": "HP < H"}, "type": "damage", "value": "1"}]}]"#, on: t)
        let monster = t.addSimpleMonster(name: "patient", positions: [(1, HexCoord(5, 5), 5), (2, HexCoord(6, 5), 5)])
        monster.entities[1].health = 3
        t.game.round = 1
        rulesManager(t).evaluateRules(phase: .roundEnd)
        XCTAssertEqual(monster.entities.map(\.health), [5, 2])
    }

    func testCharacterWithSummonTargetsSummons() {
        let t = makeGame(characters: 1)
        installRules(#"[{"round": "true", "figures": [{"identifier": {"type": "characterWithSummon", "name": ".*"}, "type": "damage", "value": 2}]}]"#, on: t)
        let summon = GameSummon(name: "bear", health: 6, maxHealth: 6)
        t.game.characters[0].summons.append(summon)
        t.game.round = 1
        rulesManager(t).evaluateRules(phase: .roundEnd)
        XCTAssertEqual(t.game.characters[0].health, 8)
        XCTAssertEqual(summon.health, 4)
    }

    // MARK: Cascades, turn rules, persistent stat effects

    func testRoomOpenedByRuleCascadesIntoRequiredRoomsRule() {
        let t = makeGame()
        let scenario = installRules(#"""
        [{"round": "true", "always": true, "once": true, "requiredRooms": [2], "finish": "won"},
         {"round": "R == 1", "rooms": [2]}]
        """#, on: t)
        let rm = rulesManager(t)
        rm.onOpenRooms = { rooms in scenario.revealedRooms.append(contentsOf: rooms) }
        t.game.round = 1
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(scenario.revealedRooms, [2])
        XCTAssertEqual(scenario.pendingFinish, "won", "follow-up pass picks up the newly revealed room")
    }

    func testReentrantEvaluationIsDeferredNotRecursive() {
        let t = makeGame()
        let scenario = installRules(#"[{"round": "R == 1", "rooms": [2]}, {"round": "true", "always": true, "once": true, "requiredRooms": [2], "finish": "won"}]"#, on: t)
        let rm = rulesManager(t)
        var calls = 0
        rm.onOpenRooms = { rooms in
            calls += 1
            scenario.revealedRooms.append(contentsOf: rooms)
            rm.evaluateRules() // e.g. a room-reveal hook re-entering the rules engine
        }
        t.game.round = 1
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(scenario.pendingFinish, "won")
    }

    func testTurnRulesOnlyApplyToTheActingFigure() {
        let t = makeGame(characters: 2)
        installRules(#"[{"round": "true", "always": true, "figures": [{"identifier": {"type": "characterWithSummon", "name": ".*"}, "type": "damage", "value": "2"}], "alwaysApplyTurn": "after"}]"#, on: t)
        let rm = rulesManager(t)
        t.game.round = 1
        for phase in RulePhase.allCases { rm.evaluateRules(phase: phase) }
        XCTAssertEqual(t.game.characters.map(\.health), [10, 10], "per-turn rules are not phase rules")

        rm.evaluateTurnRules(.turnStart, for: t.game.characters[0])
        XCTAssertEqual(t.game.characters.map(\.health), [10, 10], "timing mismatch")
        rm.evaluateTurnRules(.turnEnd, for: t.game.characters[0])
        XCTAssertEqual(t.game.characters.map(\.health), [8, 10])
    }

    func testPersistentDeckOverrideDoesNotDiscardDrawnAbilityOnReapply() {
        let t = makeGame()
        installRules(#"""
        [{"round": "true", "always": true, "alwaysApply": true,
          "statEffects": [{"identifier": {"type": "monster", "edition": "gh", "name": "cultist"}, "statEffect": {"deck": "cultist-scenario-89"}}]}]
        """#, on: t)
        let cultist = t.addMonster(name: "cultist", positions: [(.normal, HexCoord(5, 5))])!
        let rm = rulesManager(t)
        t.game.round = 1
        rm.evaluateRules(phase: .roundStart)
        XCTAssertEqual(cultist.deckOverride, "cultist-scenario-89")

        cultist.ability = 2 // drawn this round
        rm.evaluateRules()
        rm.evaluateRules(phase: .roundEnd)
        XCTAssertEqual(cultist.ability, 2, "re-applying the persistent effect must not reshuffle the deck")
    }
}
