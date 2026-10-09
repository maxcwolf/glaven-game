import XCTest
import SwiftUI
@testable import GlavenGameLib

/// How to Play: every topic's text, links, pictures and place in the book.
@MainActor
final class HowToPlayTests: XCTestCase {

    func testEveryTopicHasItsPictureAndWhereItShowsUp() {
        for topic in LearnTopic.all {
            XCTAssertFalse(topic.onTheBoard.isEmpty, topic.title)
            XCTAssertTrue(topic.onTheBoard.hasSuffix("."), "\(topic.title): a sentence")
        }
    }

    /// Every "topic:" link names a topic, and plain text has no Markdown left in it.
    func testLinksGoToTopicsAndPlainTextIsPlain() throws {
        let link = try NSRegularExpression(pattern: #"\]\(topic:([A-Za-z]+)\)"#)
        var links = 0
        for topic in LearnTopic.all {
            for paragraph in topic.paragraphs {
                for match in link.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                    let name = String(paragraph[Range(match.range(at: 1), in: paragraph)!])
                    XCTAssertNotNil(LearnTopic.ID(rawValue: name), "\(topic.title) links to \(name)")
                    XCTAssertNotEqual(name, topic.id.rawValue, "\(topic.title) links to itself")
                    links += 1
                }
                let plain = LearnTopic.plain(paragraph)
                XCTAssertFalse(plain.contains("**") || plain.contains("](") || plain.contains("["), plain)
                XCTAssertFalse(LearnText.attributed(paragraph).characters.isEmpty)
            }
        }
        XCTAssertGreaterThan(links, 15)
        XCTAssertEqual(LearnTopic.plain("A [muddled](topic:muddle) figure has **disadvantage**."),
                       "A muddled figure has disadvantage.")
        XCTAssertEqual(LearnText.topic(of: URL(string: "topic:advantage")!), .advantage)
        XCTAssertNil(LearnText.topic(of: URL(string: "https://example.com")!))
    }

    /// Previous and Next read the whole book through, in order; each topic knows its place.
    func testPreviousAndNextReadTheBookThrough() {
        var seen: [LearnTopic.ID] = []
        var topic: LearnTopic? = LearnTopic.all.first
        while let page = topic { seen.append(page.id); topic = page.next }
        XCTAssertEqual(seen, LearnTopic.all.map(\.id))
        XCTAssertNil(LearnTopic.all.first?.previous)
        XCTAssertEqual(LearnTopic.topic(.advantage).previous?.id, .modifiers)
        XCTAssertEqual(LearnTopic.topic(.advantage).place.index, 3)
        XCTAssertEqual(LearnTopic.topic(.advantage).place.of, 7)
    }

    func testSearchFindsTitlesAndText() {
        XCTAssertEqual(LearnTopic.search("").count, LearnTopic.all.count)
        XCTAssertEqual(LearnTopic.search("Wound").first?.id, .wound)
        let disadvantage = Set(LearnTopic.search("disadvantage").map(\.id))
        XCTAssertTrue(disadvantage.isSuperset(of: [.advantage, .muddle, .attacking]), "\(disadvantage)")
        XCTAssertTrue(LearnTopic.search("zzz").isEmpty)
    }

    /// Ticks for what's been met (a tip in play, or read here); "New" for met but not read.
    func testTicksAndNew() throws {
        let progress = LearnProgress(seen: ["poison", "wound"], read: ["wound", "stun"])
        XCTAssertTrue(progress.knows(.poison) && progress.knows(.wound) && progress.knows(.stun))
        XCTAssertFalse(progress.knows(.muddle))
        XCTAssertTrue(progress.isNew(.poison))
        XCTAssertFalse(progress.isNew(.wound), "read since")
        XCTAssertFalse(progress.isNew(.stun), "read, never met in play")
        XCTAssertEqual(progress.count(.conditions).known, 3)
        XCTAssertEqual(progress.count(.conditions).of, 10)

        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        sim.coord.markRead(.focus)
        XCTAssertTrue(sim.gm.settingsManager.readTopics.contains("focus"))
        XCTAssertTrue(sim.coord.learnProgress.knows(.focus))
    }

    // MARK: - Diagrams

    private var diagrams: [(String, LearnDiagram)] {
        LearnTopic.all.compactMap { topic in
            if case .diagram(let d) = topic.art { return (topic.title, d) }
            return nil
        }
    }

    func testDiagramsStayOnTheirGrid() {
        XCTAssertGreaterThanOrEqual(diagrams.count, 9)
        for (title, d) in diagrams {
            let grid = Set(d.hexes)
            let used = Set(d.figures.keys).union(d.terrain.keys).union(d.lit).union(d.path).union(d.labels.keys)
                .union(d.lines.flatMap { [$0.from, $0.to] }).union([d.ring].compactMap { $0 })
            XCTAssertTrue(used.isSubset(of: grid), "\(title): \(used.subtracting(grid))")
        }
    }

    /// A move goes hex by hex, never through a wall, an obstacle or an enemy (Moving's path
    /// goes round the obstacle); a push lands where the arrow ends.
    func testPathsMoveOneHexAtATime() {
        for (title, d) in diagrams where d.path.count > 1 {
            for (a, b) in zip(d.path, d.path.dropFirst()) {
                XCTAssertEqual(a.distance(to: b), 1, "\(title): \(a) to \(b)")
            }
            for hex in d.path.dropFirst() {
                XCTAssertNotEqual(d.terrain[hex], .wall, title)
                XCTAssertNotEqual(d.terrain[hex], .obstacle, title)
            }
        }
        let moving = LearnDiagram.moving
        // The numbers count movement: difficult terrain costs 2.
        var cost = 0
        for hex in moving.path.dropFirst() {
            cost += moving.terrain[hex] == .difficult ? 2 : 1
            XCTAssertEqual(moving.labels[hex], "\(cost)")
        }
    }

    /// How monsters choose: the numbers are the hexes of movement to attack each hero (melee),
    /// and the focus is the nearer; Money's lit hexes are Loot 1's reach.
    func testDiagramNumbersAreTrue() {
        let focus = LearnDiagram.focus
        let monster = LearnDiagram.Hex(0, 1)
        XCTAssertEqual(monster.distance(to: .init(2, 1)), 2)
        XCTAssertEqual(LearnDiagram.Hex(2, 1).distance(to: .init(3, 1)), 1, "next to the Brute")
        XCTAssertEqual(monster.distance(to: .init(3, 3)), 4)
        XCTAssertEqual(LearnDiagram.Hex(3, 3).distance(to: .init(4, 3)), 1, "next to the Spellweaver")
        XCTAssertEqual(focus.ring, .init(3, 1))
        XCTAssertEqual(LearnDiagram.loot.lit, LearnDiagram.loot.within(1, of: .init(2, 1)))
        XCTAssertEqual(LearnDiagram.loot.lit.count, 6)
        // Attacking: range 3, enemy 3 out of it.
        let attacking = LearnDiagram.attacking
        XCTAssertLessThanOrEqual(LearnDiagram.Hex(1, 1).distance(to: .init(3, 2)), 3)
        XCTAssertLessThanOrEqual(LearnDiagram.Hex(1, 1).distance(to: .init(4, 0)), 3)
        XCTAssertGreaterThan(LearnDiagram.Hex(1, 1).distance(to: .init(6, 2)), 3)
        XCTAssertFalse(attacking.lit.contains(.init(6, 2)))
    }

    /// Regression: the Attacking map (8 hexes across) was drawn at a fixed size wider than the
    /// page on an iPad, and pushed the whole book off both sides of the screen. Every picture
    /// fits the width it's given.
    func testEveryPictureFitsThePage() throws {
        let sim = try ScenarioSimulator(scenario: "1", options: .init(seed: 2))
        for width in [CGFloat(360), 584] {
            for topic in LearnTopic.all {
                let host = NSHostingController(rootView: LearnArtView(art: topic.art, width: width).environment(sim.gm))
                let fitted = host.sizeThatFits(in: CGSize(width: width + 36, height: 2000))
                XCTAssertLessThanOrEqual(fitted.width, width + 36 + 0.5, "\(topic.title) at \(width): \(fitted.width)")
            }
        }
    }
}

/// Learning mode beyond the board's monsters: "Why?" for summons, tips in town, and the
/// special rules tip.
@MainActor
final class LearningBeyondMonstersTests: XCTestCase {

    private var gm: GameManager!
    private var coord: BoardCoordinator { gm.boardCoordinator }

    override func setUp() async throws {
        gm = try SaveAndContinueTestsSupport.manager()
        gm.game.level = 1
        gm.game.learningMode = true
        coord.boardState = makeBoard(cols: 12, rows: 12)
        coord.autoResolvePrompts = true
        coord.turnDelayNanoseconds = 0
    }

    /// A summon's move and attack lines carry its decision: the enemies it weighed, best first,
    /// and "Why?" speaks of a summon.
    func testWhyForASummon() async throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        coord.boardState.placePiece(.character(brute.id), at: HexCoord(0, 3))
        var data = SummonDataModel(name: "rat", health: .int(5))
        data.attack = .int(2)
        data.movement = .int(3)
        data.range = .int(0)
        gm.characterManager.addSummon(from: data, for: brute)
        let summon = try XCTUnwrap(brute.summons.first)
        summon.state = .active
        let piece = PieceID.summon(id: summon.id)
        coord.boardState.placePiece(piece, at: HexCoord(1, 3))
        let near = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(4, 3), origin: .placed))
        let far = try XCTUnwrap(coord.spawnMonster(name: "bandit-guard", type: .normal, at: HexCoord(9, 3), origin: .placed))

        await SummonTurnController(coordinator: coord, gameManager: gm).executeSummonTurns(for: brute)

        let lines = coord.turnLog.filter { $0.whyID != nil }
        XCTAssertFalse(lines.isEmpty, "its move and attack lines carry its decision")
        let why = try XCTUnwrap(lines.first.flatMap { coord.monsterWhys[$0.whyID!] })
        XCTAssertEqual(why.monster, piece)
        XCTAssertEqual(why.focus, near)
        XCTAssertEqual(why.candidates.map(\.pieceID), [near, far])
        XCTAssertGreaterThan(why.moved, 0)
        XCTAssertEqual(why.attacks.count, 1)
        let explanation = coord.whyExplanation(why)
        XCTAssertTrue(explanation.steps.first?.note?.hasPrefix("A summon goes for") == true, explanation.steps.first?.note ?? "")
    }

    /// In town, each thing the party can newly do teaches its rule, once.
    func testTownTeachesWhatThePartyCanDo() throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        let brute = gm.game.characters[0]
        brute.experience = 50
        brute.loot = 30
        coord.teachInTown()
        var taught: [LearnTopic.ID] = []
        while let tip = coord.pendingTip {
            taught.append(tip.topic)
            coord.dismissTip()
        }
        XCTAssertTrue(taught.contains(.levelUp), "\(taught)")
        XCTAssertTrue(taught.contains(.personalQuest), "no quest yet: \(taught)")
        XCTAssertTrue(taught.contains(.shopping), "\(taught)")
        XCTAssertFalse(taught.contains(.retirement), "no quest done")

        coord.teachInTown()
        XCTAssertNil(coord.pendingTip, "each once")

        gm.game.learningMode = false
        gm.settingsManager.seenTips = []
        coord.teachInTown()
        XCTAssertNil(coord.pendingTip, "only in learning mode")
    }

    /// A scenario with special rules teaches them at its first card choice.
    func testSpecialRulesAreTaught() throws {
        gm.characterManager.addCharacter(name: "brute", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let scenarios = gm.editionStore.scenarios(for: "gh").filter { $0.solo == nil }
        let withRules = try XCTUnwrap(scenarios.first {
            !ScenarioBrief.make(for: $0, labels: gm.editionStore).rules.isEmpty
        })
        gm.startScenarioOnBoard(withRules)
        gm.boardCoordinator.finishSetup()
        var taught: [LearnTopic.ID] = []
        while let tip = coord.pendingTip {
            taught.append(tip.topic)
            if tip.topic == .specialRules { XCTAssertEqual(tip.anchor, .goal) }
            coord.dismissTip()
        }
        XCTAssertTrue(taught.contains(.specialRules), "\(withRules.index): \(taught)")
    }
}
