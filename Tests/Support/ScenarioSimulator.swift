import XCTest
import SwiftData
@testable import GlavenGameLib

/// Plays a real scenario headlessly through the BoardCoordinator turn loop. A `PlayerPolicy`
/// makes every player decision through the same coordinator calls the UI makes (card selection,
/// rests, hex and target picks, modifier draws, damage negation), while observers check every
/// attack, every movement and the board after each step against the rules.
///
/// Seeded runs are fully deterministic, so a transcript (`transcript`) can be compared against a
/// golden file.
@MainActor
final class ScenarioSimulator {

    struct Options {
        var characters: [String] = ["brute", "spellweaver", "cragheart", "scoundrel"]
        var characterLevel = 1
        /// Scenario difficulty (Easy plays at scenario level - 1).
        var difficulty: DifficultyMode = .normal
        /// Seed for every shuffle and random draw; nil keeps the system-seeded generator.
        var seed: UInt64?
        /// Let the coordinator resolve modifier draws, damage negation and push choices itself
        /// instead of the policy answering the prompts.
        var autoResolvePrompts = false
    }

    enum Outcome: String {
        case victory, defeat, unfinished
    }

    let index: String
    let gm: GameManager
    let coord: BoardCoordinator
    var policy: PlayerPolicy

    /// Rule violations found by the attack/move observers and the per-step board checks.
    private(set) var violations: [String] = []
    /// The turn log, with a board summary at the end of every round.
    private(set) var transcript: [String] = []

    private var logCursor = 0
    private var summarizedRound = -1
    /// The turn already prepared (weak: a new controller can reuse a freed one's address).
    private weak var preparedTurn: PlayerTurnController?
    private var defaultDecided: Set<String> = []

    // MARK: - Setup

    init(scenario index: String, options: Options = Options(), policy: PlayerPolicy? = nil) throws {
        if let seed = options.seed {
            GameRandom.shared = GameRandom(seed: seed)
        }
        let schema = Schema([SettingsModel.self, SavedGameModel.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let gm = GameManager(modelContainer: container)
        gm.setEdition("gh")
        for name in options.characters {
            gm.characterManager.addCharacter(name: name, edition: "gh")
        }
        for character in gm.game.characters where character.level != options.characterLevel {
            gm.characterManager.setLevel(options.characterLevel, for: character)
            character.health = character.maxHealth
        }

        gm.game.difficulty = options.difficulty
        let scenario = try XCTUnwrap(gm.editionStore.scenarios(for: "gh").first { $0.index == index && $0.solo == nil },
                                     "scenario \(index) exists")
        gm.startScenarioOnBoard(scenario)
        let coord = gm.boardCoordinator
        XCTAssertEqual(coord.boardPhase, .setup, "board started for scenario \(index)")
        coord.boardScene = nil
        coord.autoResolvePrompts = options.autoResolvePrompts
        coord.turnDelayNanoseconds = 0

        self.index = index
        self.gm = gm
        self.coord = coord
        self.policy = policy ?? TacticalPolicy()

        coord.attackObserver = { [unowned self] attacker, target in self.checkAttack(attacker, target) }
        coord.moveObserver = { [unowned self] piece, path, style in self.checkMove(piece, path, style) }

        // Characters go on free starting hexes (allies may stand on some), where the policy wants.
        for character in gm.game.characters where !character.absent {
            let free = coord.boardState.startingLocations.filter { !coord.boardState.isOccupied($0) }
            guard !free.isEmpty else {
                XCTFail("scenario \(index): no free starting hex for \(character.name)")
                break
            }
            coord.placeCharacter(characterID: character.id, at: self.policy.startingHex(for: character, options: free, sim: self))
        }
        coord.finishSetup()
        collectLog()
    }

    /// Keep playing a scenario that `gm` resumed from a save (it is on the board, in card selection).
    init(resuming gm: GameManager, scenario index: String, policy: PlayerPolicy? = nil) {
        let coord = gm.boardCoordinator
        coord.boardScene = nil
        coord.turnDelayNanoseconds = 0
        self.index = index
        self.gm = gm
        self.coord = coord
        self.policy = policy ?? TacticalPolicy()
        coord.attackObserver = { [unowned self] attacker, target in self.checkAttack(attacker, target) }
        coord.moveObserver = { [unowned self] piece, path, style in self.checkMove(piece, path, style) }
        collectLog()
    }

    // MARK: - Playing

    var result: Outcome {
        switch coord.scenarioResult {
        case .victory: return .victory
        case .defeat: return .defeat
        default: return .unfinished
        }
    }

    /// Play until the scenario ends or `rounds` rounds have been completed.
    /// `eachStep` runs before every step (tests use it to tweak the game).
    @discardableResult
    func play(rounds: Int, eachStep: (() -> Void)? = nil) async -> Outcome {
        var idleSteps = 0
        var lastSignature = ""
        while coord.scenarioResult == nil && !(gm.game.round >= rounds && coord.boardPhase == .cardSelection) {
            eachStep?()
            step()
            await settle()
            collectLog()
            checkBoard()

            let signature = progressSignature()
            if signature == lastSignature {
                idleSteps += 1
                if idleSteps > 500 {
                    violations.append("scenario \(index) stalled in round \(gm.game.round): \(signature)")
                    break
                }
            } else {
                idleSteps = 0
                lastSignature = signature
            }
        }
        collectLog()
        if coord.scenarioResult != nil { summarize(final: true) }
        return result
    }

    /// Why the result is not one the rules allow, or nil if it is. A victory needs the scenario's
    /// own goal, or (without one) every enemy dead and every room revealed; a defeat needs the
    /// scenario's failure condition or every character exhausted (GH p.47).
    func outcomeProblem() -> String? {
        let scenario = gm.game.scenario
        switch result {
        case .unfinished:
            return "scenario \(index) did not finish (round \(gm.game.round))"
        case .victory:
            if scenario?.pendingFinish == "won" { return nil }
            if scenario?.data.rules?.contains(where: { $0.finish == "won" }) == true {
                return "scenario \(index) won by killing everything, but it has its own goal"
            }
            let alive = gm.game.monsters.filter { !MonsterAI.isAllyFaction($0) && !$0.off && !$0.aliveEntities.isEmpty }
            if !alive.isEmpty { return "scenario \(index) won with \(alive.map(\.name)) still alive" }
            if coord.boardState.doors.contains(where: { !$0.isOpen }) { return "scenario \(index) won with rooms unrevealed" }
            return nil
        case .defeat:
            if scenario?.pendingFinish == "lost" { return nil }
            let standing = gm.game.characters.filter { !$0.absent && !$0.exhausted }
            return standing.isEmpty ? nil : "scenario \(index) lost with \(standing.map(\.name)) still standing"
        }
    }

    /// Answer whatever the game is waiting for, if anything.
    private func step() {
        if let draw = coord.pendingModifierDraw {
            // As the draw overlay does: one draw, or two for advantage/disadvantage.
            coord.completeModifierDraw(selectedCards: CombatResolver.drawModifiers(
                advantage: draw.advantage, disadvantage: draw.disadvantage, draw: draw.drawCard))
            return
        }
        if coord.pendingRecovery != nil {
            coord.resolveRecovery([])
            return
        }
        if coord.pendingInitiativeChange != nil {
            coord.resolveInitiativeChange(0)
            return
        }
        if coord.pendingElementChoice != nil {
            coord.resolveElementChoice([])
            return
        }
        if coord.pendingConditionRemoval != nil {
            coord.resolveConditionRemoval(nil)
            return
        }
        if coord.pendingItemUse != nil {
            // Policies don't spend items, so seeded games play the same with or without them.
            coord.resolvePendingItemUse(false)
            return
        }
        if let pending = coord.pendingDamage,
           let character = character(pending.characterID) {
            coord.resolvePendingDamage(choice: policy.negateDamage(pending.damage, character: character, sim: self))
            return
        }
        if let rest = coord.pendingShortRest, let character = character(rest.characterID) {
            if !rest.committed {
                switch policy.shortRest(character: character, cardToLose: rest.randomCardId, sim: self) {
                case .skip:
                    coord.skipShortRest()
                case .rest:
                    coord.commitShortRest()
                    coord.resolveShortRest()
                case .restAndRepick:
                    coord.commitShortRest()
                    coord.rerollShortRest()
                    if coord.pendingShortRest != nil { coord.resolveShortRest() }
                }
            } else {
                coord.resolveShortRest()
            }
            return
        }
        if let rest = coord.pendingLongRest, let character = character(rest.characterID) {
            coord.resolveLongRest(characterID: rest.characterID,
                                  discardIndex: policy.longRestLoss(character: character, sim: self))
            return
        }
        if coord.boardPhase == .cardSelection {
            summarize(final: false)
            if let id = coord.cardSelectingCharacterID, let character = character(id) {
                if let pair = policy.chooseCards(for: character, hand: hand(of: character), sim: self) {
                    coord.chooseCards(for: id, leading: pair.leading, other: pair.other)
                } else {
                    coord.chooseLongRest(for: id)
                }
            }
            return
        }
        if answerInteraction() { return }

        guard let turn = coord.activePlayerTurn else { return }
        if turn.phase == .turnComplete {
            coord.finishPlayerTurn()
            return
        }
        guard case .idle = coord.interactionMode, !turn.awaitingAsync else { return }
        if preparedTurn !== turn {
            preparedTurn = turn
            defaultDecided = []
            if !turn.hasActed { policy.prepareTurn(turn, sim: self) }
        }
        let half = "\(turn.phase)"
        if turn.currentActionIndex == 0, !defaultDecided.contains(half) {
            defaultDecided.insert(half)
            if policy.useDefaultAction(turn, sim: self) {
                turn.useDefaultAction()
                return
            }
        }
        turn.executeCurrentAction()
    }

    /// Answer a pending hex or figure selection. Returns false if nothing was pending.
    private func answerInteraction() -> Bool {
        switch coord.interactionMode {
        case .selectingMove(let piece, _, let hexes, _, let mode):
            if let hex = policy.moveDestination(for: piece, options: hexes, mode: mode, sim: self) {
                coord.handleHexTap(hex)
            } else {
                coord.activePlayerTurn?.skipRemainingActions()
            }
        case .selectingAttackTarget(let attacker, _, let targets):
            if let target = policy.attackTarget(for: attacker, options: targets, chosen: [], sim: self) {
                coord.handlePieceTap(target)
            } else {
                coord.activePlayerTurn?.skipRemainingActions()
            }
        case .selectingMultiAttackTargets(let attacker, _, let targets, let count, let chosen):
            if chosen.count < count,
               let next = policy.attackTarget(for: attacker, options: targets.subtracting(chosen),
                                              chosen: chosen, sim: self) {
                coord.handlePieceTap(next)
            } else if chosen.isEmpty {
                coord.activePlayerTurn?.skipRemainingActions()
            } else {
                coord.confirmMultiAttack()
            }
        case .selectingConditionTarget(let piece, let condition, let targets):
            if let target = policy.conditionTarget(for: piece, condition: condition, options: targets, sim: self) {
                coord.handlePieceTap(target)
            }
        case .selectingHealTarget(let healer, _, let targets):
            coord.handlePieceTap(policy.healTarget(for: healer, options: targets, sim: self))
        case .placingSummon(_, let owner, let hexes):
            if let hex = policy.summonHex(for: owner, options: hexes, sim: self) {
                coord.handleHexTap(hex)
            }
        case .selectingPushPullHex(let target, let origin, let hexes, _, let isPush):
            if let hex = policy.forcedMoveHex(for: target, from: origin, options: hexes, isPush: isPush, sim: self) {
                coord.handleHexTap(hex)
            }
        case .selectingForcedMoveTarget(let piece, _, let isPush, let targets):
            if let target = policy.forcedMoveTarget(for: piece, options: targets, isPush: isPush, sim: self) {
                coord.handlePieceTap(target)
            }
        case .idle, .watchingMonsterTurn, .placingCharacter:
            return false
        }
        return true
    }

    /// Let the turn loop's tasks run (all on the main actor; no wall-clock waits).
    private func settle() async {
        for _ in 0..<4 { await Task.yield() }
    }

    private func progressSignature() -> String {
        let turn = coord.activePlayerTurn.map { "\($0.characterID):\($0.phase):\($0.currentActionIndex):\($0.awaitingAsync)" }
        return [
            "\(gm.game.round)", "\(coord.boardPhase)", "\(coord.currentTurnIndex)", "\(coord.turnLog.count)",
            "\(coord.interactionMode)", turn ?? "-",
            "\(coord.pendingDamage != nil)\(coord.pendingModifierDraw != nil)\(coord.pendingShortRest != nil)\(coord.pendingLongRest != nil)\(coord.pendingItemUse != nil)",
        ].joined(separator: " ")
    }

    // MARK: - Lookups for policies

    func character(_ id: String) -> GameCharacter? {
        gm.game.characters.first { $0.id == id }
    }

    /// The ability cards in a character's hand, in hand order.
    func hand(of character: GameCharacter) -> [AbilityModel] {
        let deck = gm.editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: "gh")
        return character.handCards.compactMap { id in deck.first { $0.cardId == id } }
    }

    func card(_ id: Int, of character: GameCharacter) -> AbilityModel? {
        gm.editionStore.abilities(forDeck: character.characterData?.deck ?? character.name, edition: "gh")
            .first { $0.cardId == id }
    }

    func position(_ piece: PieceID) -> HexCoord? {
        coord.boardState.piecePositions[piece]
    }

    /// Enemies of `piece` on the board that can be targeted (invisible ones excluded), in a fixed order.
    func enemies(of piece: PieceID) -> [PieceID] {
        coord.boardState.piecePositions.keys.sorted().filter { other in
            other != piece && coord.areEnemies(piece, other) && coord.entity(for: other) != nil
                && !(coord.entity(for: other)?.entityConditions.contains { $0.name == .invisible && !$0.expired } ?? false)
        }
    }

    func health(_ piece: PieceID) -> (current: Int, max: Int) {
        guard let entity = coord.entity(for: piece) else { return (0, 0) }
        return (entity.health, entity.maxHealth)
    }

    // MARK: - Transcript

    private func collectLog() {
        while logCursor < coord.turnLog.count {
            let entry = coord.turnLog[logCursor]
            let line = entry.trace.map { "\(entry.message) [\($0)]" } ?? entry.message
            transcript.append(entry.isRoundHeader ? "=== \(entry.message) ===" : line)
            logCursor += 1
        }
    }

    /// A board summary once per round (when card selection starts) and at the end.
    private func summarize(final: Bool) {
        guard final || summarizedRound != gm.game.round else { return }
        summarizedRound = gm.game.round
        collectLog()
        transcript.append(final ? "--- final state (round \(gm.game.round)) ---" : "--- state after round \(gm.game.round) ---")
        transcript.append(contentsOf: stateSummary())
    }

    func stateSummary() -> [String] {
        var lines: [String] = []
        let elements = gm.game.elementBoard.filter { $0.state != .inert }
            .map { "\($0.type.rawValue) \($0.state.rawValue)" }
        lines.append("elements: \(elements.isEmpty ? "none" : elements.joined(separator: ", "))")
        for character in gm.game.characters where !character.absent {
            let where_ = position(.character(character.id)).map { "\($0)" } ?? "off board"
            let status = character.exhausted ? " EXHAUSTED" : ""
            lines.append("\(character.name) \(where_) hp \(character.health)/\(character.maxHealth)"
                + " hand \(character.handCards.count) discard \(character.discardedCards.count)"
                + " lost \(character.lostCards.count) active \(character.activeCards.count)"
                + " xp \(character.experience) gold \(character.loot)\(conditions(character))\(status)")
            for summon in character.summons where !summon.dead {
                let at = position(.summon(id: summon.id)).map { "\($0)" } ?? "off board"
                lines.append("  summon \(summon.name) \(at) hp \(summon.health)/\(summon.maxHealth)\(conditions(summon))")
            }
        }
        for piece in coord.boardState.piecePositions.keys.sorted() {
            guard case .monster(let name, let standee) = piece, let entity = coord.monsterEntity(name: name, standee: standee)
            else { continue }
            lines.append("\(name) #\(standee) \(entity.type.rawValue) \(position(piece)!) hp \(entity.health)/\(entity.maxHealth)\(conditions(entity))")
        }
        let loot = coord.boardState.lootTokens.filter { $0.value > 0 }.sorted { $0.key < $1.key }
        if !loot.isEmpty {
            lines.append("money tokens: " + loot.map { "\($0.key)x\($0.value)" }.joined(separator: " "))
        }
        let doors = coord.boardState.doors
        lines.append("doors open: \(doors.filter(\.isOpen).count)/\(doors.count)")
        return lines
    }

    private func conditions(_ entity: any Entity) -> String {
        let active = entity.entityConditions.filter { !$0.expired }
            .map { $0.value > 1 ? "\($0.name.rawValue) \($0.value)" : $0.name.rawValue }
            .sorted()
        return active.isEmpty ? "" : " [\(active.joined(separator: ", "))]"
    }

    // MARK: - Rule checks

    private func violation(_ message: String) {
        violations.append("scenario \(index) round \(gm.game.round): \(message)")
        collectLog()
        transcript.append("!! VIOLATION: \(message)")
    }

    /// Every attack: both figures on the board, enemies of each other, the target visible and in
    /// line of sight (GH p.18–19).
    private func checkAttack(_ attacker: PieceID, _ target: PieceID) {
        guard let from = position(attacker), let to = position(target) else {
            violation("\(attacker) attacks \(target), but one of them is not on the board")
            return
        }
        if attacker == target { violation("\(attacker) attacks itself") }
        if !coord.areEnemies(attacker, target) { violation("\(attacker) attacks its ally \(target)") }
        if coord.entity(for: target)?.entityConditions.contains(where: { $0.name == .invisible && !$0.expired }) == true {
            violation("\(attacker) attacks invisible \(target)")
        }
        if !LineOfSight.hasLOS(from: from, to: to, board: coord.boardState) {
            violation("\(attacker) at \(from) attacks \(target) at \(to) without line of sight")
        }
    }

    /// Every movement: starts where the figure stands, steps between adjacent hexes on the map,
    /// never through walls; normal moves avoid obstacles and enemies; figures that can't open
    /// doors never enter a closed one; the move ends on an empty hex (GH p.17).
    private func checkMove(_ piece: PieceID, _ path: [HexCoord], _ style: MovementStyle) {
        let board = coord.boardState
        guard path.first == position(piece) else {
            violation("\(piece) moves from \(path.first.map { "\($0)" } ?? "?") but stands at \(position(piece).map { "\($0)" } ?? "nowhere")")
            return
        }
        let opensDoors: Bool = { if case .character = piece { return true }; return false }()
        for (a, b) in zip(path, path.dropFirst()) where a.distance(to: b) != 1 {
            violation("\(piece) moves from \(a) to non-adjacent \(b)")
        }
        for (i, hex) in path.enumerated().dropFirst() {
            let isLast = i == path.count - 1
            guard let cell = board.cells[hex], cell.overlay != .wall else {
                violation("\(piece) moves through \(hex), which is off the map or a wall")
                continue
            }
            if !opensDoors && board.isClosedDoor(hex) {
                violation("\(piece) moves through the closed door at \(hex)")
            }
            switch style {
            case .normal, .forced:
                if !cell.passable { violation("\(piece) moves through the obstacle at \(hex) (\(style))") }
                if let other = board.piece(at: hex), other != piece, coord.areEnemies(piece, other) || style == .forced {
                    violation("\(piece) moves through \(other) at \(hex) (\(style))")
                }
            case .jump:
                if isLast && !cell.passable { violation("\(piece) jumps onto the obstacle at \(hex)") }
            case .fly:
                break
            }
            if isLast, let other = board.piece(at: hex), other != piece {
                violation("\(piece) ends its move on \(other) at \(hex)")
            }
        }
    }

    /// Board consistency after every step.
    private func checkBoard() {
        let board = coord.boardState
        var seen: [HexCoord: PieceID] = [:]
        for (piece, hex) in board.piecePositions.sorted(by: { $0.key < $1.key }) {
            if let other = seen[hex] { violation("\(piece) and \(other) share \(hex)") }
            seen[hex] = piece
            guard let cell = board.cells[hex], cell.overlay != .wall else {
                violation("\(piece) stands off the map at \(hex)")
                continue
            }
            switch piece {
            case .character(let id):
                guard let c = character(id) else { violation("piece for unknown character \(id)"); continue }
                if c.exhausted { violation("exhausted \(c.name) is still on the board") }
                if !cell.passable { violation("\(c.name) stands on an obstacle at \(hex)") }
            case .monster(let name, let standee):
                guard let entity = coord.monsterEntity(name: name, standee: standee), !entity.dead else {
                    let entities = gm.game.monsters.first { $0.name == name }?.entities
                        .map { "#\($0.number)\($0.dead ? " dead" : "")" } ?? []
                    violation("piece \(piece) at \(hex) has no living monster (\(entities.joined(separator: ", ")))"); continue
                }
                let flying = gm.game.monsters.first { $0.name == name }?.monsterData?.flying == true
                if !cell.passable && !flying { violation("\(piece) stands on an obstacle at \(hex)") }
            case .summon:
                guard let summon = coord.entity(for: piece) as? GameSummon, !summon.dead else {
                    violation("piece \(piece) has no living summon"); continue
                }
                if !cell.passable && !summon.flying { violation("\(summon.name) stands on an obstacle at \(hex)") }
            case .objective:
                continue
            }
            if let entity = coord.entity(for: piece) {
                if entity.health > entity.maxHealth { violation("\(piece) has \(entity.health)/\(entity.maxHealth) HP") }
                if entity.health <= 0 { violation("\(piece) is on the board with \(entity.health) HP") }
            }
        }
        for character in gm.game.characters where !character.exhausted && !character.absent {
            let total = character.handCards.count + character.discardedCards.count
                + character.lostCards.count + character.activeCards.count
            if total != character.handSize {
                violation("\(character.name) has \(total) of \(character.handSize) cards")
            }
        }
        for monster in gm.game.monsters {
            let alive = monster.aliveEntities
            if alive.count > monster.maxCount {
                violation("\(alive.count) \(monster.name) alive, only \(monster.maxCount) standees")
            }
            if Set(alive.map(\.number)).count != alive.count {
                violation("\(monster.name) has duplicate standee numbers")
            }
        }
    }
}

/// How a character handles the end-of-round short rest.
enum ShortRestDecision {
    case skip, rest, restAndRepick
}
