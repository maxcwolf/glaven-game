import XCTest
@testable import GlavenGameLib

/// Monster data parity with Gloomhaven Secretariat semantics:
/// baseStat inheritance, expression-valued stats, level-modified monster names and standee counts.
final class MonsterDataTests: XCTestCase {

    private static let store: EditionDataStore = {
        let store = EditionDataStore()
        store.loadAllEditions()
        return store
    }()

    private func monster(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> MonsterData {
        try XCTUnwrap(Self.store.monsterData(name: name, edition: "gh"), "missing gh monster \(name)",
                      file: file, line: line)
    }

    // MARK: - baseStat inheritance

    func testBanditGuard_plainStatsUnchanged() throws {
        let data = try monster("bandit-guard")
        let normal = try XCTUnwrap(data.stat(for: .normal, at: 1))
        XCTAssertEqual(normal.type, .normal)
        XCTAssertEqual(normal.level, 1)
        XCTAssertEqual(normal.healthValue(characterCount: 2), 6)
        XCTAssertEqual(normal.movementValue(characterCount: 2), 3)
        XCTAssertEqual(normal.attackValue(characterCount: 2), 2)
        XCTAssertEqual(normal.rangeValue(characterCount: 2), 0)
        XCTAssertNil(normal.actions)

        let elite = try XCTUnwrap(data.stat(for: .elite, at: 1))
        XCTAssertEqual(elite.type, .elite)
        XCTAssertEqual(elite.healthValue(characterCount: 2), 9)
        XCTAssertEqual(elite.movementValue(characterCount: 2), 2)
        XCTAssertEqual(elite.attackValue(characterCount: 2), 3)
        XCTAssertEqual(elite.actions?.map(\.type), [.shield])
    }

    func testBlackImp_inheritsBaseMovement() throws {
        let data = try monster("black-imp")
        for level in 0...7 {
            for type in [MonsterType.normal, .elite] {
                let stat = try XCTUnwrap(data.stat(for: type, at: level), "black-imp \(type) L\(level)")
                XCTAssertEqual(stat.movement, .int(1), "black-imp \(type) L\(level) must inherit baseStat movement 1")
                XCTAssertEqual(stat.movementValue(characterCount: 2), 1)
            }
        }
        // Level entry fields still win and level actions are kept.
        let l1 = try XCTUnwrap(data.stat(for: .normal, at: 1))
        XCTAssertEqual(l1.healthValue(characterCount: 2), 4)
        XCTAssertEqual(l1.rangeValue(characterCount: 2), 3)
        XCTAssertEqual(l1.attackConditions, [.poison])
        XCTAssertEqual(try XCTUnwrap(data.stat(for: .normal, at: 0)).attackConditions, [])
    }

    func testGiantViper_inheritsPoisonAction() throws {
        let data = try monster("giant-viper")
        for level in 0...7 {
            for type in [MonsterType.normal, .elite] {
                let stat = try XCTUnwrap(data.stat(for: type, at: level))
                XCTAssertTrue(stat.attackConditions.contains(.poison), "giant-viper \(type) L\(level) attacks poison")
            }
        }
    }

    func testNightDemon_inheritsAttackersGainDisadvantage() throws {
        let stat = try XCTUnwrap(try monster("night-demon").stat(for: .elite, at: 1))
        XCTAssertTrue(stat.attackersGainDisadvantage)
        XCTAssertFalse(stat.hasAttackAdvantage)
    }

    func testCaveBearScenario54_combinesBaseAndLevelActions() throws {
        let data = try monster("cave-bear-scenario-54")
        // Below level 5 only the scenario poison applies.
        XCTAssertEqual(try XCTUnwrap(data.stat(for: .normal, at: 1)).attackConditions, [.poison])
        // From level 5 the printed wound is combined with the base poison.
        let l5 = try XCTUnwrap(data.stat(for: .normal, at: 5))
        XCTAssertEqual(Set(l5.attackConditions), [.poison, .wound])
        XCTAssertEqual(l5.actions?.count, 2)
    }

    func testCombineActions_deduplicatesIdenticalActions() {
        let base = MonsterStatModel(type: .normal, level: nil, health: nil,
                                    actions: [ActionModel(type: .condition, value: .string("poison"))],
                                    immunities: [.stun])
        let level = MonsterStatModel(level: 2, health: .int(5),
                                     actions: [ActionModel(type: .condition, value: .string("poison")),
                                               ActionModel(type: .shield, value: .int(1))],
                                     immunities: [.stun, .poison])
        let merged = level.inheriting(from: base)
        XCTAssertEqual(merged.type, .normal)
        XCTAssertEqual(merged.level, 2)
        XCTAssertEqual(merged.health, .int(5))
        XCTAssertEqual(merged.actions?.map(\.type), [.condition, .shield])
        XCTAssertEqual(merged.immunities, [.stun, .poison])
    }

    func testSongOfTheDeep_bossInheritsBaseMovementKeepsLevelActions() throws {
        let stat = try XCTUnwrap(try monster("song-of-the-deep").stat(for: .boss, at: 2))
        XCTAssertEqual(stat.movementValue(characterCount: 2), 3)
        XCTAssertEqual(stat.rangeValue(characterCount: 2), 4)
        XCTAssertEqual(stat.actions?.map(\.type), [.shield])
    }

    func testSightlessEye_inheritsRange() throws {
        let stat = try XCTUnwrap(try monster("the-sightless-eye").stat(for: .boss, at: 1))
        XCTAssertEqual(stat.rangeValue(characterCount: 2), 3)
        XCTAssertEqual(stat.attackValue(characterCount: 2), 6)
        XCTAssertEqual(stat.healthValue(characterCount: 3), 24) // "8xC"
        XCTAssertEqual(stat.special?.count, 2)
    }

    func testBosses_inheritImmunitiesAndSpecials() throws {
        let commander = try monster("bandit-commander")
        // Any requested type resolves to the boss block.
        let stat = try XCTUnwrap(commander.stat(for: .normal, at: 1))
        XCTAssertEqual(stat.type, .boss)
        XCTAssertEqual(stat.immunities, [.stun, .immobilize, .curse])
        XCTAssertEqual(stat.special?.count, 2)
        XCTAssertEqual(stat.healthValue(characterCount: 4), 40) // "10xC"

        // Every GH boss whose baseStat lists immunities exposes them at every level.
        let bosses = Self.store.monsters(for: "gh").filter { $0.isBoss && $0.baseStat?.immunities != nil }
        XCTAssertGreaterThanOrEqual(bosses.count, 14)
        for boss in bosses {
            for level in 0...7 {
                let s = try XCTUnwrap(boss.stat(for: .boss, at: level), "\(boss.name) L\(level)")
                XCTAssertEqual(s.immunities, boss.baseStat?.immunities, "\(boss.name) L\(level) immunities")
                XCTAssertEqual(s.special?.count, boss.baseStat?.special?.count, "\(boss.name) L\(level) special")
            }
        }
    }

    func testBossImmunities_reachSpawnedEntity() {
        let t = TestGame()
        t.addCharacter()
        guard let commander = t.addMonster(name: "bandit-commander", positions: [(.boss, HexCoord(5, 5))]),
              let entity = commander.entities.first else {
            return XCTFail("bandit-commander should spawn")
        }
        XCTAssertEqual(Set(entity.immunities), [.stun, .immobilize, .curse])
        XCTAssertEqual(entity.maxHealth, 10 * 2) // L1 "10xC", C = max(2, 1)
    }

    func testStatLookup_clampsLevelAndRejectsMissingType() throws {
        let data = try monster("bandit-guard")
        XCTAssertEqual(data.stat(for: .normal, at: 9)?.level, 7)
        XCTAssertEqual(data.stat(for: .normal, at: -1)?.level, 0)
        XCTAssertNil(data.stat(for: .boss, at: 1), "non-boss has no boss block")
    }

    func testAllGHMonsters_haveCompleteEvaluableStats() throws {
        let monsters = Self.store.monsters(for: "gh")
        XCTAssertGreaterThan(monsters.count, 70)
        for data in monsters {
            let types: [MonsterType] = data.isBoss ? [.boss] : [.normal, .elite]
            for level in 0...7 {
                for type in types {
                    let stat = try XCTUnwrap(data.stat(for: type, at: level), "\(data.name) \(type) L\(level)")
                    for c in 2...4 {
                        XCTAssertGreaterThan(stat.healthValue(characterCount: c), 0, "\(data.name) \(type) L\(level) C\(c) health")
                    }
                }
            }
        }
    }

    // MARK: - Expression-valued stats

    func testInoxBodyguard_attackScalesWithCharacterCount() throws {
        let data = try monster("inox-bodyguard")
        let l0 = try XCTUnwrap(data.stat(for: .boss, at: 0))
        XCTAssertEqual(l0.attack, .string("C"))
        XCTAssertEqual(l0.attack?.intValue, 0, "intValue cannot evaluate formulas — callers must use attackValue")
        XCTAssertEqual(l0.attackValue(characterCount: 3), 3)
        XCTAssertEqual(l0.attackValue(characterCount: 1), 2, "C is clamped to a minimum of 2")

        let l1 = try XCTUnwrap(data.stat(for: .boss, at: 1))
        XCTAssertEqual(l1.attack, .string("1+C"))
        XCTAssertEqual(l1.attackValue(characterCount: 2), 3)
        XCTAssertEqual(l1.attackValue(characterCount: 4), 5)
        XCTAssertEqual(l1.healthValue(characterCount: 4), 28) // "7xC"
        XCTAssertEqual(l1.movementValue(characterCount: 4), 2)
        XCTAssertTrue(l1.attackVariables.isEmpty)
    }

    func testDarkRider_attackUsesCardVariableX() throws {
        let stat = try XCTUnwrap(try monster("dark-rider").stat(for: .boss, at: 0))
        XCTAssertEqual(stat.attack, .string("3+X"))
        XCTAssertEqual(stat.attackVariables, ["X"])
        XCTAssertEqual(stat.attackValue(characterCount: 3), 3, "unknown X falls back to 0")
        XCTAssertEqual(stat.attackValue(characterCount: 3, variables: ["X": 2]), 5)
        XCTAssertEqual(stat.healthValue(characterCount: 3), 27) // "9xC"
    }

    func testMercilessOverseer_inheritsVariableAttack() throws {
        let stat = try XCTUnwrap(try monster("merciless-overseer").stat(for: .boss, at: 1))
        XCTAssertEqual(stat.attack, .string("V"))
        XCTAssertEqual(stat.attackVariables, ["V"])
        XCTAssertEqual(stat.attackValue(characterCount: 2, variables: ["V": 4]), 4)
        XCTAssertEqual(stat.attackValue(characterCount: 2), 0)
    }

    /// The Bloated Regent and the Hungry Soul have (H×C)/2 hit points rounded up (scenario book
    /// #75, #62).
    func testHalvedBossHealth_roundsUp() throws {
        let regent = try XCTUnwrap(try monster("bloated-regent").stat(for: .boss, at: 1))
        XCTAssertEqual(regent.healthValue(characterCount: 3), 15)
        let regent3 = try XCTUnwrap(try monster("bloated-regent").stat(for: .boss, at: 3))
        XCTAssertEqual(regent3.healthValue(characterCount: 3), 20) // 19.5 rounded up
        XCTAssertEqual(regent3.healthValue(characterCount: 4), 26)

        let soul = try XCTUnwrap(try monster("hungry-soul").stat(for: .boss, at: 1))
        XCTAssertEqual(soul.healthValue(characterCount: 3), 9)
        let soul2 = try XCTUnwrap(try monster("hungry-soul").stat(for: .boss, at: 2))
        XCTAssertEqual(soul2.healthValue(characterCount: 3), 11) // 10.5 rounded up
    }

    func testEvaluator_allDataExpressionForms() {
        func ev(_ s: String, L: Int = 2, C: Int = 3, vars: [String: Int] = [:]) -> Int {
            evaluateEntityValue(.string(s), level: L, characterCount: C, variables: vars)
        }
        XCTAssertEqual(evaluateEntityValue(.int(7)), 7)
        XCTAssertEqual(ev("5"), 5)
        XCTAssertEqual(ev("-"), 0)
        XCTAssertEqual(ev(""), 0)
        XCTAssertEqual(ev("C"), 3)
        XCTAssertEqual(ev("8xC"), 24)
        XCTAssertEqual(ev("1+C"), 4)
        XCTAssertEqual(ev("1+C+L"), 6)
        XCTAssertEqual(ev("(10xC)/2"), 15)
        XCTAssertEqual(ev("10xC/2"), 15)
        XCTAssertEqual(ev("13xC/2"), 19)
        XCTAssertEqual(ev("(7+L)xC"), 27)
        XCTAssertEqual(ev("Cx(3+L)"), 15)
        XCTAssertEqual(ev("(2xC)+L-2"), 6)
        XCTAssertEqual(ev("10+(2xL)"), 14)
        XCTAssertEqual(ev("15+5xL"), 25, "multiplication binds tighter than addition")
        XCTAssertEqual(ev("6+2xL"), 10)
        XCTAssertEqual(ev("8+Lx2"), 12)
        XCTAssertEqual(ev("4+(CxL)"), 10)
        XCTAssertEqual(ev("4+C+(2xL)"), 11)
        XCTAssertEqual(ev("L+(2xC)"), 8)
        XCTAssertEqual(ev("[2+(LxC/2){$math.floor}]"), 5)
        XCTAssertEqual(ev("[2+(LxC/2){$math.floor}]", L: 3), 6) // 2 + 4.5 → 6
        XCTAssertEqual(ev("[X/2{$math.ceil}]", vars: ["X": 3]), 2)
        XCTAssertEqual(ev("[Hx2]", vars: ["H": 6]), 12)
        XCTAssertEqual(ev("HxC", vars: ["H": 5]), 15)
        XCTAssertEqual(ev("3+X"), 3)
        XCTAssertEqual(ev("3+X", vars: ["X": 4]), 7)
        XCTAssertEqual(ev("C", C: 1), 2, "C has a minimum of 2")
        XCTAssertEqual(ev("[C{$math.max:3}]"), 3)
        XCTAssertEqual(ev("[LxC{$math.min:4}]"), 4)
        XCTAssertEqual(ev("-2+5"), 3)
    }

    func testEvaluator_malformedInputDoesNotCrash() {
        for bad in ["3+", "(", "((C)", "Performs", "alliesRange:3", "3//2", "1/0", "C x", "[", "]", "{", "1..2"] {
            XCTAssertEqual(evaluateEntityValue(.string(bad), level: 1, characterCount: 2), 0, "'\(bad)'")
        }
    }

    func testIntOrString_formulaHelpers() {
        XCTAssertFalse(IntOrString.int(3).isFormula)
        XCTAssertFalse(IntOrString.string("3").isFormula)
        XCTAssertTrue(IntOrString.string("1+C").isFormula)
        XCTAssertEqual(IntOrString.string("1+C").evaluated(characterCount: 4), 5)
        XCTAssertEqual(IntOrString.string("8xC").evaluated(level: 1, characterCount: 3), 24)
    }

    // MARK: - Level-modified monster names

    func testMonsterNameSpec_parse() {
        XCTAssertTrue(MonsterNameSpec.parse("living-corpse:+2") == ("living-corpse", 2))
        XCTAssertTrue(MonsterNameSpec.parse("bandit-guard:-1") == ("bandit-guard", -1))
        XCTAssertTrue(MonsterNameSpec.parse("city-guard-sun-solo:-2") == ("city-guard-sun-solo", -2))
        XCTAssertTrue(MonsterNameSpec.parse("cultist") == ("cultist", 0))
        XCTAssertEqual(MonsterNameSpec.baseName("infiltrator:+1"), "infiltrator")

        let absolute = MonsterNameSpec("stone-golem:3")
        XCTAssertEqual(absolute.name, "stone-golem")
        XCTAssertEqual(absolute.absoluteLevel, 3)
        XCTAssertEqual(absolute.level(forScenarioLevel: 6), 3)

        let unknown = MonsterNameSpec("weird:suffix")
        XCTAssertEqual(unknown.name, "weird:suffix")
        XCTAssertFalse(unknown.hasLevelModifier)
    }

    func testMonsterNameSpec_levelIsClamped() {
        let plus2 = MonsterNameSpec("living-corpse:+2")
        XCTAssertTrue(plus2.hasLevelModifier)
        XCTAssertEqual(plus2.level(forScenarioLevel: 3), 5)
        XCTAssertEqual(plus2.level(forScenarioLevel: 7), 7)
        let minus1 = MonsterNameSpec("vermling-scout:-1")
        XCTAssertEqual(minus1.level(forScenarioLevel: 0), 0)
        XCTAssertEqual(minus1.level(forScenarioLevel: 4), 3)
        XCTAssertEqual(MonsterNameSpec("cultist").level(forScenarioLevel: 4), 4)
    }

    /// Every monster name referenced by GH scenario/section data (monsters list, room standees,
    /// rule spawns) must resolve to monster data once the level suffix is stripped.
    func testAllScenarioMonsterNames_resolveAfterParsing() {
        let scenarios = Self.store.scenarios(for: "gh") + Self.store.sections(for: "gh")
        XCTAssertGreaterThan(scenarios.count, 100)
        var suffixed = Set<String>()
        for scenario in scenarios {
            var names = scenario.monsters ?? []
            names += (scenario.rooms ?? []).flatMap { ($0.monster ?? []).map(\.name) }
            names += (scenario.rules ?? []).flatMap { ($0.spawns ?? []).map(\.monster.name) }
            for raw in names {
                let spec = MonsterNameSpec(raw)
                if spec.hasLevelModifier { suffixed.insert(raw) }
                XCTAssertNotNil(Self.store.monsterData(name: spec.name, edition: "gh"),
                                "scenario \(scenario.index) monster '\(raw)' does not resolve")
            }
        }
        XCTAssertTrue(suffixed.isSuperset(of: ["living-corpse:+2", "infiltrator:+1", "the-harvester:+1",
                                               "stone-golem:+1", "bandit-guard:-1"]))
    }

    // MARK: - Standee counts

    func testMaxCount_fromData() throws {
        XCTAssertEqual(try monster("bandit-guard").maxCount, 6)
        XCTAssertEqual(try monster("living-bones").maxCount, 10)
        XCTAssertEqual(try monster("black-imp").maxCount, 10)
        XCTAssertEqual(try monster("cave-bear").maxCount, 4)
        XCTAssertEqual(try monster("inox-bodyguard").maxCount, 2)
        XCTAssertEqual(try monster("bandit-commander").maxCount, 1)
    }

    func testMaxCount_standeeCountOverridesCountAndEvaluatesFormulas() throws {
        var data = try monster("bandit-guard")
        data.standeeCount = .int(4)
        XCTAssertEqual(data.maxCount, 4)
        data.standeeCount = .string("C")
        XCTAssertEqual(data.maxCount(characterCount: 3), 3)
        data.standeeCount = nil
        data.count = nil
        XCTAssertEqual(data.maxCount, 6)
        data.boss = true
        XCTAssertEqual(data.maxCount, 1)
    }

    func testStandeeSharing_resolvesChains() throws {
        let lookup: (String) -> MonsterData? = { Self.store.monsterData(name: $0, edition: "gh") }
        let lieutenant = try monster("lieutenant")
        XCTAssertEqual(lieutenant.standeePoolName, "city-guard-saw-solo")
        XCTAssertEqual(lieutenant.standeePoolRoot(lookup: lookup).name, "city-guard")
        XCTAssertTrue(lieutenant.sharesStandees(with: try monster("city-guard"), lookup: lookup))
        XCTAssertTrue(try monster("ghost-wolf").sharesStandees(with: try monster("hound"), lookup: lookup))
        XCTAssertFalse(try monster("hound").sharesStandees(with: try monster("city-guard"), lookup: lookup))
        XCTAssertEqual(try monster("hound").standeePoolRoot(lookup: lookup).name, "hound")
    }

    // MARK: - Every card is carried out

    /// The ability decks the GH monsters draw from.
    private func monsterDecks() -> [(name: String, cards: [AbilityModel])] {
        let names = Set(Self.store.monsters(for: "gh").map { $0.deck ?? $0.name })
        return names.sorted().map { ($0, Self.store.abilities(forDeck: $0, edition: "gh")) }
    }

    /// Every boss special in the GH data: the stat card's, at every level.
    private func bossSpecials() -> [(name: String, number: Int, actions: [ActionModel])] {
        var result: [(String, Int, [ActionModel])] = []
        for data in Self.store.monsters(for: "gh").sorted(by: { $0.name < $1.name }) {
            var seen: [[ActionModel]] = []
            for level in 0...7 {
                for (index, special) in (data.stat(for: .boss, at: level)?.special ?? []).enumerated() where !seen.contains(special) {
                    seen.append(special)
                    result.append((data.name, index + 1, special))
                }
            }
        }
        return result
    }

    /// Every action on every GH monster ability card is of a kind the monster's turn performs:
    /// a card can't silently do nothing (as the Wind Demon's attack in a grid did).
    func testEveryMonsterCardActionIsOneTheTurnPerforms() {
        let decks = monsterDecks()
        XCTAssertGreaterThan(decks.count, 30)
        for deck in decks {
            XCTAssertFalse(deck.cards.isEmpty, "\(deck.name) has cards")
            for card in deck.cards {
                XCTAssertEqual(MonsterAbility.unperformed(in: card.actions ?? []), [],
                               "\(deck.name) card \(card.cardId ?? 0) (\(card.initiative))")
                XCTAssertNil(card.bottomActions, "\(deck.name) card \(card.cardId ?? 0): a monster card has one half")
            }
        }
    }

    /// The same for boss specials. The ones the turn can't carry out are named here, and the
    /// game tells the players to resolve them as printed: the Elder Drake's Zephyrs (an
    /// objective to summon) and the Prime Demon's throne and its "summon a demon".
    func testEveryBossSpecialActionIsPerformedOrKnownNotToBe() {
        let specials = bossSpecials()
        XCTAssertGreaterThan(specials.count, 20)
        var gaps: [String: [String]] = [:]
        for special in specials {
            let unperformed = MonsterAbility.unperformed(in: special.actions.filter { $0.type != .custom })
            if !unperformed.isEmpty { gaps["\(special.name) \(special.number)"] = unperformed }
        }
        XCTAssertEqual(gaps, ["elder-drake 2": ["summon"], "prime-demon 1": ["summon"], "prime-demon 2": ["summon"]])
    }

    /// What the validator is for: an ability of a kind the turn doesn't know is found, wherever
    /// it is printed — and a grouping is looked into, not taken for an ability.
    func testAnAbilityTheTurnDoesNotPerformIsFound() {
        let swing = ActionModel(type: .swing, value: .int(2))
        XCTAssertEqual(MonsterAbility.unperformed(in: [swing]), ["swing"])
        XCTAssertEqual(MonsterAbility.unperformed(in: [ActionModel(type: .grid, subActions: [swing])]), ["grid > swing"])
        let attack = ActionModel(type: .attack, value: .int(0), valueType: .plus, subActions: [ActionModel(type: .card, value: .int(1))])
        XCTAssertEqual(MonsterAbility.unperformed(in: [attack]), ["attack > card"])
        XCTAssertEqual(MonsterAbility.unperformed(in: [ActionModel(type: .summon, value: .string("demon"))]), ["summon"],
                       "a summon that names no monster")
    }

    /// Wind Demon 648: the attack in the grid is the card's attack, and the Air beside it gives
    /// +1 Attack and the six-hex area in place of the three-hex one.
    func testAGridOnACardIsOpenedIntoItsAbilities() throws {
        let card = try XCTUnwrap(Self.store.abilities(forDeck: "wind-demon", edition: "gh").first { $0.cardId == 648 })
        XCTAssertEqual(card.actions?.map(\.type), [.move, .grid])
        let actions = MonsterAbility.flattened(card.actions ?? [])
        XCTAssertEqual(actions.map(\.type), [.move, .attack], "its consume belongs to the attack")
        XCTAssertEqual(MonsterAbility.flattened(actions).map(\.id), actions.map(\.id), "opening it twice changes nothing")
        let attack = actions[1]
        let consume = try XCTUnwrap(MonsterAbility.attachedConsumes(of: attack).first)
        XCTAssertEqual(MonsterAbility.elements(of: consume), [.air])
        let plain = MonsterAbility.attack(attack, stat: nil, baseAttack: 2, baseRange: 3)
        let withAir = MonsterAbility.attack(attack, stat: nil, baseAttack: 2, baseRange: 3, consumed: [consume.id])
        XCTAssertEqual(plain.value, 2)
        XCTAssertEqual(withAir.value, 3)
        XCTAssertEqual(plain.area.map { AoEResolver.parsePattern($0).filter(\.isTarget).count }, 3)
        XCTAssertEqual(withAir.area.map { AoEResolver.parsePattern($0).filter(\.isTarget).count }, 6)
    }

    /// Whom a card names: the words of each `specialTarget` in the GH monster data.
    func testWhomAMonsterCardNames() {
        typealias Affected = MonsterAbility.Affected
        XCTAssertEqual(MonsterAbility.affected(by: nil, baseRange: 3), Affected(includesSelf: true))
        XCTAssertEqual(MonsterAbility.affected(by: "self", baseRange: 3), Affected(includesSelf: true))
        XCTAssertEqual(MonsterAbility.affected(by: "enemiesAdjacent", baseRange: 3), Affected(side: .enemies, range: 1))
        XCTAssertEqual(MonsterAbility.affected(by: "enemyAdjacent", baseRange: 3), Affected(side: .enemies, range: 1, onlyOne: true))
        XCTAssertEqual(MonsterAbility.affected(by: "enemiesRange:2", baseRange: 3), Affected(side: .enemies, range: 2))
        XCTAssertEqual(MonsterAbility.affected(by: "enemiesRange:", baseRange: 3), Affected(side: .enemies, range: 3), "the monster's own range")
        XCTAssertEqual(MonsterAbility.affected(by: "enemies", baseRange: 3), Affected(side: .enemies), "all of them, anywhere")
        XCTAssertEqual(MonsterAbility.affected(by: "alliesAdjacentAffect", baseRange: 0), Affected(side: .allies, range: 1))
        XCTAssertEqual(MonsterAbility.affected(by: "alliesRangeAffect:2", baseRange: 0), Affected(side: .allies, range: 2))
        XCTAssertEqual(MonsterAbility.affected(by: "alliesRange:3", baseRange: 0), Affected(side: .allies, range: 3))
        XCTAssertEqual(MonsterAbility.affected(by: "selfAlliesRange:2", baseRange: 0), Affected(includesSelf: true, side: .allies, range: 2))
        XCTAssertEqual(MonsterAbility.affected(by: "selfAlliesAffect", baseRange: 0), Affected(includesSelf: true, side: .allies))
        // Every value in the data is one of these forms.
        var values = Set<String>()
        func collect(_ actions: [ActionModel]) {
            for action in actions {
                if action.type == .specialTarget, let value = action.value?.stringValue { values.insert(value) }
                collect(action.subActions ?? [])
            }
        }
        for deck in monsterDecks() { for card in deck.cards { collect(card.actions ?? []) } }
        for special in bossSpecials() { collect(special.actions) }
        XCTAssertEqual(values.subtracting(["enemyOneAll"]).sorted(),
                       ["alliesAdjacentAffect", "alliesRange:3", "alliesRangeAffect:2", "enemies", "enemiesAdjacent",
                        "enemiesRange:", "enemiesRange:2", "enemiesRange:3", "enemiesRange:4", "enemyAdjacent", "self",
                        "selfAlliesAffect", "selfAlliesRange:2"])
    }

    /// The printed text on monster cards and boss specials: each line is one the turn acts on.
    /// The three it can't are named, and the game asks the players to resolve them.
    func testEveryPrintedLineOnAMonsterCardIsActedOn() {
        // What `MonsterTurnController` looks for in a card's text (lowercased).
        let acted = ["trap in an adjacent empty hex", "suffer", "if the target is adjacent to any of", "this round gain disadvantage",
                     "for each target damaged", "in a hex adjacent to the target", "with h equal to the summoning",
                     "move to next door and reveal room", "all allies add +1", "scouts act again", "hatch eggs", "eggs",
                     // Values of a stat formula, read by the attack itself.
                     "x = hexes moved", "v = number of scouts present"]
        var texts = Set<String>()
        func collect(_ actions: [ActionModel]) {
            for action in actions {
                if action.type == .custom, let key = action.value?.stringValue, key.hasPrefix("%data.custom.") {
                    texts.insert(Self.store.resolveCustomText(key, edition: "gh")?.lowercased() ?? "missing: \(key)")
                }
                collect(action.subActions ?? [])
            }
        }
        for deck in monsterDecks() { for card in deck.cards { collect(card.actions ?? []) } }
        for special in bossSpecials() { collect(special.actions) }
        XCTAssertGreaterThan(texts.count, 15)
        let left = texts.filter { text in !acted.contains { text.contains($0) } }.sorted()
        // (The Saw solo scenario's City Guard card has no text in the labels; solo scenarios aren't played.)
        XCTAssertEqual(left, ["fly to next perch of boulders", "mind control", "missing: %data.custom.gh.city-guard-saw-solo.1%", "throne moves"])
    }
}
