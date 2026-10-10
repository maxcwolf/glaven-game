#if DEBUG
import Foundation
import SpriteKit

/// A long session without a player, for finding leaks and slowdowns: launched with
/// `GLAVEN_SOAK=1` (`SIMCTL_CHILD_GLAVEN_SOAK=1 xcrun simctl launch …`), the app plays the first
/// GH scenarios over and over on the real board — SwiftUI and SpriteKit drawing as they do for a
/// player — answering every question through the same calls the buttons make. After each
/// scenario it writes a line of measurements to `Documents/soak.log` (and the console): memory,
/// the scene's node count, the turn log, and how long a step took. Sound is off, and each
/// game's save is deleted as the next begins.
@MainActor
final class SoakDriver {
    static var shared: SoakDriver?

    private let gm: GameManager
    private var timer: Timer?
    private var scenarioIndex = 0
    private var games = 0
    private var steps = 0
    private var slowestStep: TimeInterval = 0
    private let scenarios = ["1", "2", "3", "4"]
    private let started = Date()
    /// The save the last soak game made (never one the app opened with).
    private var lastSoakCampaign: UUID?

    private var coord: BoardCoordinator { gm.boardCoordinator }

    static func startIfAsked(_ gm: GameManager) {
        guard ProcessInfo.processInfo.environment["GLAVEN_SOAK"] == "1", shared == nil else { return }
        let driver = SoakDriver(gm: gm)
        shared = driver
        driver.begin()
    }

    private init(gm: GameManager) { self.gm = gm }

    private func begin() {
        log("soak start: \(Self.memoryMB()) MB")
        startScenario()
        // A step every 50 ms: quick, but slow enough for the board to draw and animate.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func startScenario() {
        // Each game saves as a new campaign; the last one goes, so Campaigns doesn't fill up.
        if let finished = lastSoakCampaign { gm.deleteCampaign(finished) }
        gm.newGame()
        gm.setEdition("gh")
        gm.game.learningMode = true   // tips come and go too
        gm.characterManager.addCharacter(name: "cragheart", edition: "gh")
        gm.characterManager.addCharacter(name: "spellweaver", edition: "gh")
        let index = scenarios[scenarioIndex % scenarios.count]
        scenarioIndex += 1
        guard let data = gm.editionStore.scenarios(for: "gh").first(where: { $0.index == index && $0.solo == nil }) else { return }
        gm.startScenarioOnBoard(data)
        coord.briefPresentation = nil
        for character in gm.game.characters where !character.absent {
            if let hex = coord.boardState.startingLocations.sorted().first(where: { !coord.boardState.isOccupied($0) }) {
                coord.placeCharacter(characterID: character.id, at: hex)
            }
        }
        coord.finishSetup()
    }

    private func tick() {
        let start = Date()
        if coord.scenarioResult != nil || gm.game.round > 25 {
            finishScenario()
            return
        }
        step()
        steps += 1
        slowestStep = max(slowestStep, Date().timeIntervalSince(start))
    }

    private func finishScenario() {
        games += 1
        let nodes = coord.boardScene.map(Self.nodeCount) ?? 0
        log("game \(games) (#\(scenarios[(scenarioIndex - 1) % scenarios.count]), \(coord.scenarioResult.map { "\($0)" } ?? "cut off") round \(gm.game.round)): "
            + "\(Self.memoryMB()) MB, \(nodes) nodes, log \(coord.turnLog.count), \(steps) steps, "
            + "slowest step \(Int(slowestStep * 1000)) ms, \(Int(Date().timeIntervalSince(started))) s in")
        steps = 0
        slowestStep = 0
        lastSoakCampaign = gm.currentCampaignID   // made by this game: newGame cleared the last
        coord.exitBoard()
        startScenario()
    }

    // MARK: - Answering, as the buttons do

    private func step() {
        if let draw = coord.pendingModifierDraw {
            coord.completeModifierDraw(selectedCards: CombatResolver.drawModifiers(
                advantage: draw.advantage, disadvantage: draw.disadvantage, baseAttack: draw.comparedAttack,
                draw: draw.drawCard))
            return
        }
        if coord.pendingTip != nil { coord.dismissTip(); return }
        if coord.explanation != nil { coord.closeExplanation(); return }
        if coord.pendingRecovery != nil { coord.resolveRecovery([]); return }
        if coord.pendingInitiativeChange != nil { coord.resolveInitiativeChange(0); return }
        if coord.pendingSufferChoice != nil { coord.resolveSufferChoice(0); return }
        if let pending = coord.pendingAllyChoice { coord.resolveAllyChoice(pending.characterIDs.first); return }
        if coord.pendingItemRefresh != nil { coord.resolveItemRefresh([]); return }
        if coord.pendingElementChoice != nil { coord.resolveElementChoice([]); return }
        if coord.pendingConditionRemoval != nil { coord.resolveConditionRemoval(nil); return }
        if coord.pendingCardPlay != nil { coord.resolveCardPlay([]); return }
        if coord.pendingActionChoice != nil { coord.resolveActionChoice(nil); return }
        if coord.pendingFigureChoice != nil { coord.resolveFigureChoice(nil); return }
        if coord.pendingItemUse != nil { coord.resolvePendingItemUse(true); return }
        if coord.pendingDamage != nil { coord.resolvePendingDamage(choice: .takeDamage); return }
        if let rest = coord.pendingShortRest {
            if rest.committed { coord.resolveShortRest() } else { coord.commitShortRest() }
            return
        }
        if let rest = coord.pendingLongRest { coord.resolveLongRest(characterID: rest.characterID, discardIndex: 0); return }
        if coord.boardPhase == .cardSelection {
            if let id = coord.cardSelectingCharacterID, let character = gm.game.characters.first(where: { $0.id == id }) {
                let hand = hand(of: character)
                if hand.count >= 2 {
                    coord.chooseCards(for: id, leading: hand[0], other: hand[1])
                } else {
                    coord.chooseLongRest(for: id)
                }
            }
            return
        }
        if answerInteraction() { return }
        guard let turn = coord.activePlayerTurn else { return }
        if turn.phase == .turnComplete { coord.finishPlayerTurn(); return }
        guard case .idle = coord.interactionMode, !turn.awaitingAsync else { return }
        turn.executeCurrentAction()
    }

    private func answerInteraction() -> Bool {
        switch coord.interactionMode {
        case .selectingMove(let piece, _, let hexes, _, _):
            // Toward the nearest enemy.
            let enemies = enemyHexes(of: piece)
            let best = hexes.sorted().min { a, b in
                (enemies.map { a.distance(to: $0) }.min() ?? 0) < (enemies.map { b.distance(to: $0) }.min() ?? 0)
            }
            if let best { coord.handleHexTap(best) } else { coord.activePlayerTurn?.skipRemainingActions() }
        case .selectingAttackTarget(_, _, let targets):
            if let target = targets.sorted().first { coord.handlePieceTap(target) } else { coord.activePlayerTurn?.skipRemainingActions() }
        case .selectingMultiAttackTargets(_, _, let targets, let count, let chosen):
            if chosen.count < count, let next = targets.subtracting(chosen).sorted().first {
                coord.handlePieceTap(next)
            } else if chosen.isEmpty {
                coord.activePlayerTurn?.skipRemainingActions()
            } else {
                coord.confirmMultiAttack()
            }
        case .selectingConditionTarget(_, _, let targets):
            if let target = targets.sorted().first { coord.handlePieceTap(target) }
        case .selectingHealTarget(_, _, let targets):
            if let target = targets.sorted().first { coord.handlePieceTap(target) }
        case .choosingPerformer(_, _, let candidates):
            if let piece = candidates.sorted().first { coord.handlePieceTap(piece) }
        case .placingToken(_, _, _, let hexes):
            if let hex = hexes.sorted().first { coord.handleHexTap(hex) }
        case .placingSummon(_, _, let hexes):
            if let hex = hexes.sorted().first { coord.handleHexTap(hex) }
        case .selectingPushPullHex(_, _, let hexes, _, _):
            if let hex = hexes.sorted().first { coord.handleHexTap(hex) }
        case .selectingForcedMoveTarget(_, _, _, let targets):
            if let target = targets.sorted().first { coord.handlePieceTap(target) }
        case .idle, .watchingMonsterTurn, .placingCharacter:
            return false
        }
        return true
    }

    private func hand(of character: GameCharacter) -> [AbilityModel] {
        let deck = gm.characterManager.abilities(for: character)
        return character.handCards.compactMap { id in deck.first { $0.cardId == id } }
    }

    private func enemyHexes(of piece: PieceID) -> [HexCoord] {
        coord.boardState.piecePositions.compactMap { other, hex in
            other != piece && coord.areEnemies(piece, other) ? hex : nil
        }
    }

    // MARK: - Measuring

    private func log(_ line: String) {
        print("[soak] \(line)")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("soak.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    static func nodeCount(_ node: SKNode) -> Int {
        node.children.reduce(1) { $0 + nodeCount($1) }
    }

    /// The process's memory footprint, as Xcode's gauge shows it.
    static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
#endif
