import XCTest
import SwiftUI
@testable import GlavenGameLib

/// Learning mode: tips the first time each rule comes up, explanations on a long-press or after
/// the "?", and "Why?" on what the monsters do.
@MainActor
final class LearningModeTests: XCTestCase {

    // MARK: - The explanations

    func testEveryRuleIsWrittenDown() {
        XCTAssertEqual(Set(LearnTopic.all.map(\.id)), Set(LearnTopic.ID.allCases), "a topic for every id, once")
        XCTAssertEqual(LearnTopic.all.count, LearnTopic.ID.allCases.count)
        for topic in LearnTopic.all {
            XCTAssertFalse(topic.paragraphs.isEmpty, topic.title)
        }
        for chapter in LearnTopic.Chapter.allCases {
            XCTAssertFalse(LearnTopic.topics(in: chapter).isEmpty, chapter.rawValue)
        }
        // Gloomhaven's conditions each have their own.
        for condition in [ConditionName.poison, .wound, .immobilize, .disarm, .stun, .muddle, .curse, .invisible, .strengthen, .bless] {
            XCTAssertNotNil(LearnTopic.id(for: condition), condition.rawValue)
        }
    }

    // MARK: - On for the first campaign

    func testTheFirstCampaignTeachesTheGame() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.beginNewGame()
        XCTAssertTrue(gm.game.learningMode, "a player's first campaign")

        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.saveGame()
        gm.beginNewGame()
        XCTAssertFalse(gm.game.learningMode, "not once there's a campaign already")
        gm.setLearningMode(true)
        XCTAssertTrue(gm.game.learningMode)
    }

    func testLearningModeIsSavedWithTheCampaign() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.game.learningMode = true
        let snapshot = gm.game.toSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let restored = GameState()
        restored.restore(from: try JSONDecoder().decode(GameSnapshot.self, from: data), editionStore: gm.editionStore)
        XCTAssertTrue(restored.learningMode)

        gm.game.learningMode = false
        XCTAssertNil(gm.game.toSnapshot().learningMode, "off isn't written")
    }

    /// Switched on mid-scenario, it's in the save that Continue resumes from (the round's start).
    func testTheSwitchIsSavedMidScenario() throws {
        let gm = try SaveAndContinueTestsSupport.manager()
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == "1" && $0.solo == nil })
        gm.startScenarioOnBoard(scenario)
        gm.checkpointRound()
        gm.setLearningMode(true)
        XCTAssertEqual(gm.roundCheckpoint?.learningMode, true)
    }

    // MARK: - Tips

    private func board(learning: Bool) throws -> ScenarioSimulator {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2, autoResolvePrompts: true))
        sim.gm.game.learningMode = learning
        return sim
    }

    func testATipShowsOnceAndOnlyInLearningMode() throws {
        let off = try board(learning: false)
        off.coord.teach(.poison)
        XCTAssertNil(off.coord.pendingTip)

        let sim = try board(learning: true)
        let coord = sim.coord
        coord.teach(.poison, "Bandit Guard 1 has Poison.")
        coord.teach(.wound)
        coord.teach(.poison)
        XCTAssertEqual(coord.pendingTip?.topic, .poison, "one at a time")
        XCTAssertEqual(coord.pendingTip?.lead, "Bandit Guard 1 has Poison.")
        XCTAssertEqual(coord.tipQueue.map(\.topic), [.wound], "not queued twice")
        coord.dismissTip()
        XCTAssertEqual(coord.pendingTip?.topic, .wound)
        XCTAssertTrue(sim.gm.settingsManager.seenTips.contains("poison"))
        coord.dismissTip()
        coord.teach(.poison)
        XCTAssertNil(coord.pendingTip, "a tip shows once ever")
    }

    /// Tips that come up together say so: "1 of 3" and Next, then Got it on the last (iPad
    /// playthrough 2026-10-09: the first attack brought four, one after another, and the next
    /// one caught a tap meant for the board).
    func testTipsThatComeTogetherAreCounted() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        coord.teach(.elements)
        XCTAssertNil(coord.tipPosition, "a tip alone isn't numbered")
        coord.teach(.attacking)
        coord.teach(.modifiers)
        XCTAssertEqual(coord.tipPosition?.index, 1)
        XCTAssertEqual(coord.tipPosition?.total, 3)
        XCTAssertEqual(coord.tipButtonTitle, "Next")
        coord.dismissTip()
        XCTAssertEqual(coord.tipPosition?.index, 2)
        coord.dismissTip()
        XCTAssertEqual(coord.tipPosition?.index, 3)
        XCTAssertEqual(coord.tipButtonTitle, "Got it")
        coord.dismissTip()
        XCTAssertNil(coord.pendingTip)
        coord.teach(.shieldAndRetaliate)
        XCTAssertNil(coord.tipPosition, "a new run starts over")
    }

    func testATipHoldsTheMonstersTurnUntilItsClosed() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        coord.interactionMode = .watchingMonsterTurn
        coord.teach(.focus)
        XCTAssertTrue(coord.isPaused)
        coord.dismissTip()
        XCTAssertFalse(coord.isPaused, "it goes on once the tip is closed")

        coord.setPaused(true)
        coord.teach(.elites)
        coord.dismissTip()
        XCTAssertTrue(coord.isPaused, "a pause the player chose stays")
    }

    /// A tip that came up before the monsters' turn began (as the player's turn ended) holds them
    /// at their first step all the same.
    func testATipShownBeforeTheMonstersHoldsThem() async throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        coord.teach(.playedCards)
        coord.interactionMode = .watchingMonsterTurn
        var stepped = false
        Task { @MainActor in
            await coord.beat()
            stepped = true
        }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(stepped, "held by the tip")
        XCTAssertTrue(coord.isPaused)
        coord.dismissTip()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(stepped)
        XCTAssertFalse(coord.isPaused)
    }

    /// Two rounds of play teach the basics as they come up, without holding the game up.
    func testPlayingTeachesAsItGoes() async throws {
        let sim = try board(learning: true)
        var taught: [LearnTopic.ID] = []
        await sim.play(rounds: 2) {
            if let tip = sim.coord.pendingTip { taught.append(tip.topic) }
        }
        for topic in [LearnTopic.ID.round, .cardChoice, .initiative, .yourTurn, .monstersAct, .modifiers, .focus] {
            XCTAssertTrue(taught.contains(topic), "taught \(topic)")
        }
        XCTAssertEqual(taught.count, Set(taught).count, "each once")
        XCTAssertGreaterThanOrEqual(sim.gm.game.round, 2)
        XCTAssertTrue(sim.violations.isEmpty, sim.violations.joined(separator: "\n"))
    }

    // MARK: - Why?

    /// Each monster's turn keeps what it weighed: its focus is the best candidate, and its move
    /// and attack lines can show why.
    func testWhyRecordsWhatTheMonsterWeighed() async throws {
        let sim = try board(learning: true)
        await sim.play(rounds: 1)
        let coord = sim.coord
        let lines = coord.turnLog.filter { $0.whyID != nil }
        XCTAssertFalse(lines.isEmpty, "monster lines carry their decision")
        for line in lines {
            let why = try XCTUnwrap(coord.monsterWhys[line.whyID!])
            XCTAssertEqual(why.candidates, why.candidates.sorted(by: FocusCandidate.ordered))
            XCTAssertTrue(line.message.hasPrefix(coord.name(why.monster)), line.message)
        }
        let attacked = try XCTUnwrap(coord.monsterWhys.values.first { !$0.attacks.isEmpty })
        let focus = try XCTUnwrap(attacked.focus)
        coord.showWhy(attacked.id)
        let explanation = try XCTUnwrap(coord.explanation)
        XCTAssertEqual(explanation.title, "Why \(coord.name(focus))?")
        XCTAssertEqual(explanation.anchor, .pieces([attacked.monster] + attacked.candidates.map(\.pieceID)),
                       "beside the monster and the enemies it weighed")
        XCTAssertEqual(explanation.steps.map(\.value).first, "Its focus")
        XCTAssertEqual(explanation.steps.last?.value, "Its attack")
    }

    /// The focus step says what decided it: movement, then distance, then initiative, or traps.
    func testWhySaysWhatDecidedTheFocus() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        let guardPiece = PieceID.monster(name: "bandit-guard", standee: 1)
        let brute = PieceID.character(sim.gm.game.characters[0].id)
        let other = PieceID.character(sim.gm.game.characters[1].id)
        func focusNote(_ a: FocusCandidate, _ b: FocusCandidate) -> String {
            coord.whyExplanation(MonsterWhy(monster: guardPiece, candidates: [a, b])).steps.first?.note ?? ""
        }
        let near = FocusCandidate(pieceID: brute, negativeHexes: 0, pathCost: 2, proximity: 3, initiative: 10)
        XCTAssertTrue(focusNote(near, .init(pieceID: other, negativeHexes: 0, pathCost: 3, proximity: 4, initiative: 20))
            .contains("least movement"))
        XCTAssertTrue(focusNote(near, .init(pieceID: other, negativeHexes: 0, pathCost: 2, proximity: 4, initiative: 20))
            .contains("nearer one"))
        let adjacent = FocusCandidate(pieceID: brute, negativeHexes: 0, pathCost: 2, proximity: 1, initiative: 10)
        XCTAssertTrue(focusNote(adjacent, .init(pieceID: other, negativeHexes: 0, pathCost: 2, proximity: 2, initiative: 20))
            .contains("1 hex away"), "one hex, not hexes")
        XCTAssertTrue(focusNote(near, .init(pieceID: other, negativeHexes: 0, pathCost: 2, proximity: 3, initiative: 20))
            .contains("acts first"))
        XCTAssertTrue(focusNote(near, .init(pieceID: other, negativeHexes: 1, pathCost: 1, proximity: 1, initiative: 5))
            .contains("trap"))
        // In reach, but next to it with a ranged attack: it stepped away first (p.30).
        let beside = FocusCandidate(pieceID: brute, negativeHexes: 0, pathCost: 0, proximity: 1, initiative: 10)
        let steppedAway = coord.whyExplanation(MonsterWhy(monster: guardPiece, candidates: [beside], ranged: true, moved: 2,
                                                          attacks: ["Brute: 2 + 0 = 2 damage"]))
        XCTAssertTrue(steppedAway.steps[1].note?.contains("disadvantage") == true, steppedAway.steps[1].note ?? "")
        let alone = coord.whyExplanation(MonsterWhy(monster: guardPiece, candidates: [near]))
        XCTAssertTrue(alone.steps.first?.note?.contains("only enemy") == true)
        let none = coord.whyExplanation(MonsterWhy(monster: guardPiece, candidates: []))
        XCTAssertTrue(none.title.contains("do nothing"))
    }

    // MARK: - Explaining what's on the screen

    private func freeHex(_ coord: BoardCoordinator) throws -> HexCoord {
        try XCTUnwrap(coord.boardState.cells.keys.sorted().first { coord.isEmptyHex($0) })
    }

    func testExplanationsSayWhatThingsAre() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        let elite = try XCTUnwrap(coord.spawnMonster(name: "living-bones", type: .elite, at: freeHex(coord), origin: .placed))
        let monster = coord.explanation(for: .piece(elite))
        XCTAssertEqual(monster.subtitle, "Elite \u{00B7} the gold ring")
        XCTAssertTrue(monster.rows.contains { $0.label == "Acts at" })
        XCTAssertTrue(monster.rows.contains { $0.label == "How it acts" })
        XCTAssertEqual(monster.topic, .focus)

        let brute = coord.explanation(for: .piece(.character(sim.gm.game.characters[0].id)))
        XCTAssertTrue(brute.rows.first?.value.hasPrefix("Hand ") == true)

        let poison = coord.explanation(for: .condition(.poison))
        XCTAssertEqual(poison.paragraphs, LearnTopic.topic(.poison).paragraphs)

        if let index = sim.gm.game.elementBoard.firstIndex(where: { $0.type == .fire }) {
            sim.gm.game.elementBoard[index].state = .strong
        }
        XCTAssertTrue(coord.explanation(for: .element(.fire)).detail?.hasPrefix("Strong") == true)

        let trapHex = try XCTUnwrap(coord.boardState.cells.values.first { $0.isTrap }?.coord
            ?? coord.boardState.cells.keys.sorted().first)
        coord.boardState.cells[trapHex]?.overlay = .trap
        XCTAssertEqual(coord.explanation(for: .hex(trapHex)).title, "Trap")
    }

    /// After the "?", the next tap on the board explains what it lands on instead of acting.
    func testTheQuestionMarkExplainsTheNextTap() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        let guardPiece = try XCTUnwrap(coord.spawnMonster(name: "living-bones", type: .normal, at: freeHex(coord), origin: .placed))
        let mode = String(describing: coord.interactionMode)
        coord.toggleExplainMode()
        XCTAssertTrue(coord.explainMode)
        coord.handlePieceTap(guardPiece)
        XCTAssertEqual(coord.explanation?.subject, .piece(guardPiece))
        XCTAssertFalse(coord.explainMode, "one tap, then back to play")
        XCTAssertEqual(String(describing: coord.interactionMode), mode, "the tap did nothing else")
        coord.closeExplanation()
        XCTAssertNil(coord.explanation)
    }

    // MARK: - Where the card goes

    func testTheCardSitsBesideWhatItExplainsAndOnScreen() {
        let screen = CGSize(width: 1376, height: 1032)
        let left = LearningOverlay.cardOrigin(width: 400, height: 300, near: CGRect(x: 20, y: 300, width: 320, height: 200), in: screen)
        XCTAssertEqual(left.x, 358, "to the right of something on the left")
        let right = LearningOverlay.cardOrigin(width: 400, height: 300, near: CGRect(x: 1030, y: 300, width: 320, height: 200), in: screen)
        XCTAssertEqual(right.x, 1030 - 18 - 400, "to the left of something on the right")
        let low = LearningOverlay.cardOrigin(width: 400, height: 300, near: CGRect(x: 20, y: 950, width: 320, height: 60), in: screen)
        XCTAssertLessThanOrEqual(low.y + 300, screen.height - 24, "kept on screen")
        let middle = LearningOverlay.cardOrigin(width: 400, height: 300, near: nil, in: screen)
        XCTAssertEqual(middle.x, (1376 - 400) / 2)
    }

    // MARK: - Drawing them writes nothing

    func testTheCardsAndHowToPlayDraw() throws {
        let sim = try board(learning: true)
        let coord = sim.coord
        let views: [AnyView] = [
            AnyView(TipCard(tip: LearnTip(topic: .modifiers, lead: "Here Bandit Guard 1 drew \u{2212}1."), coordinator: coord)),
            AnyView(ExplanationCard(explanation: coord.explanation(for: .piece(.character(sim.gm.game.characters[0].id))),
                                    coordinator: coord)),
            AnyView(HowToPlayBook(coordinator: coord, topic: .focus)),
        ]
        for view in views {
            let renderer = ImageRenderer(content: view.environment(sim.gm).frame(width: 600, height: 700))
            XCTAssertNotNil(renderer.cgImage)
        }
        XCTAssertNil(coord.pendingTip)
    }
}
