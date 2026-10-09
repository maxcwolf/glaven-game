import Foundation

/// Something on the screen that can be explained (a long-press, or a tap after the "?"), and
/// that a tip can point at.
enum LearnSubject: Hashable {
    case piece(PieceID)
    case hex(HexCoord)
    case element(ElementType)
    case condition(ConditionName)
    case modifierTray
    case turnRail
    case goal
    case monsterGroup(String)
    case monsterCard(String)
    case playedCards
    case cardPanel
    case log
    case topic(LearnTopic.ID)
    /// The board view itself, so figures on it can be placed in the overlay's space.
    case board
    /// Several figures on the board at once (a monster and its focus, for "Why?").
    case pieces([PieceID])
}

/// A rule taught the first time it comes up: the topic, a line about what just happened, and
/// what on the screen it's about.
struct LearnTip: Identifiable, Equatable {
    let id = UUID()
    let topic: LearnTopic.ID
    var lead: String?
    var anchor: LearnSubject?
}

/// What a long-press (or the "?") says about something, or why a monster did what it did.
struct Explanation: Identifiable, Equatable {
    struct Row: Equatable {
        let label: String
        let value: String
        var note: String?
    }

    let id = UUID()
    let subject: LearnSubject
    /// What the card sits beside, if not the subject (a "Why?" sits by the log).
    var anchor: LearnSubject?
    let title: String
    /// The figure's portrait beside the subtitle, if it's a figure.
    var portrait: PieceID?
    var subtitle: String?
    var detail: String?
    /// The figure's hit points ("9/9").
    var health: String?
    var rows: [Row] = []
    var paragraphs: [String] = []
    /// Numbered steps (a monster's "Why?").
    var steps: [Row] = []
    var footnote: String?
    /// The How to Play topic to read more in.
    var topic: LearnTopic.ID?
}

/// What a monster weighed on its turn, for "Why?": the enemies it could have focused on (best
/// first), how far it moved, and what its attacks did.
struct MonsterWhy: Identifiable, Equatable {
    let id = UUID()
    let monster: PieceID
    var candidates: [FocusCandidate]
    /// Its attack is ranged (it keeps out of reach of a disadvantaged shot).
    var ranged = false
    var moved = 0
    var attacks: [String] = []
    var focus: PieceID? { candidates.first?.pieceID }
    /// "A monster", or "A summon" for one fighting on the players' side.
    var kind: String {
        if case .summon = monster { return "A summon" }
        return "A monster"
    }
}

/// The How to Play sheet, opened at a topic.
struct HowToPlayRequest: Identifiable, Equatable {
    let id = UUID()
    var topic: LearnTopic.ID?
}

extension BoardCoordinator {

    var learningMode: Bool { gameManager?.game.learningMode ?? false }

    // MARK: - Tips

    /// Teach a rule the first time it comes up (in learning mode): one tip at a time, each
    /// shown once ever. A tip during the monsters' turns holds them until it's closed.
    func teach(_ topic: LearnTopic.ID, _ lead: String? = nil, at anchor: LearnSubject? = nil) {
        guard learningMode, let settings = gameManager?.settingsManager,
              !settings.seenTips.contains(topic.rawValue),
              pendingTip?.topic != topic, !tipQueue.contains(where: { $0.topic == topic }) else { return }
        tipQueue.append(LearnTip(topic: topic, lead: lead, anchor: anchor))
        showNextTip()
    }

    private func showNextTip() {
        guard pendingTip == nil, !tipQueue.isEmpty else { return }
        pendingTip = tipQueue.removeFirst()
        if isAutomatedTurn && !isPaused {
            setPaused(true)
            tipPausedPlayback = true
        }
    }

    /// "Got it": the tip is never shown again, and the next one (if any) comes up.
    func dismissTip() {
        guard let tip = pendingTip else { return }
        pendingTip = nil
        if let settings = gameManager?.settingsManager {
            settings.seenTips.insert(tip.topic.rawValue)
            settings.saveSettings()
        }
        showNextTip()
        if pendingTip == nil && tipPausedPlayback {
            tipPausedPlayback = false
            setPaused(false)
        }
    }

    /// Tips as a round's cards are chosen: how a round goes, choosing cards, elites on the board,
    /// and a hand running short.
    func teachAtCardSelection() {
        guard learningMode, let game = gameManager?.game else { return }
        // Each shows once ever, so the first round they come up is the first round played.
        teach(.round, at: .turnRail)
        teach(.cardChoice, at: .cardPanel)
        if let monster = game.monsters.first(where: { $0.aliveEntities.contains { $0.type == .elite } }),
           let elite = monster.aliveEntities.filter({ $0.type == .elite }).map(\.number).min() {
            teach(.elites, at: .piece(.monster(name: monster.name, standee: elite)))
        }
        if let rules = scenarioBrief?.rules, !rules.isEmpty {
            teach(.specialRules, "This scenario has \(rules.count == 1 ? "a special rule" : "\(rules.count) special rules").", at: .goal)
        }
        if let short = game.characters.first(where: { !$0.exhausted && !$0.absent && $0.handCards.count <= 4 }) {
            teach(.handIsAClock, "\(characterName(short.id)) has \(short.handCards.count) cards left in hand.", at: .cardPanel)
        }
    }

    /// Tips in town, for what the party can do there now: level up, take perks, choose or finish
    /// a personal quest, shop, enhance.
    func teachInTown() {
        guard learningMode, let gameManager else { return }
        let manager = gameManager.characterManager
        let party = gameManager.game.characters.filter { !$0.absent }.sorted { $0.id < $1.id }
        func name(_ character: GameCharacter) -> String {
            GameText.characterName(character, labels: gameManager.editionStore)
        }
        for character in party where manager.canLevelUp(character) {
            teach(.levelUp, "\(name(character)) has \(character.experience) experience: enough for level \(character.level + 1).")
        }
        for character in party where manager.perksAvailable(for: character) > 0 {
            teach(.perks, "\(name(character)) has a perk to take.")
        }
        if let character = party.first(where: { $0.personalQuest == nil }) {
            teach(.personalQuest, "\(name(character)) has no personal quest yet.")
        }
        for character in party where character.personalQuest != nil && manager.questComplete(character) {
            teach(.retirement, "\(name(character))\u{2019}s personal quest is done.")
        }
        if let character = party.first(where: { $0.loot > 0 }) {
            teach(.shopping, "\(name(character)) has \(character.loot) gold to spend.")
        }
        if party.contains(where: { gameManager.enhancementsManager.enhancerOpen(edition: $0.edition) }) {
            teach(.enhancing)
        }
    }

    /// Tips for things the log already names: elements, doors, money, rests, exhaustion.
    func teachFromLog(_ category: TurnLogCategory, _ message: String) {
        guard learningMode else { return }
        switch category {
        case .element: teach(.elements)
        case .door: teach(.doors)
        case .loot: teach(.loot)
        case .rest: teach(.resting)
        case .death where message.hasSuffix("is exhausted"): teach(.exhaustion)
        default: break
        }
    }

    /// What the player has met of the rules, for How to Play's contents.
    var learnProgress: LearnProgress {
        LearnProgress(seen: gameManager?.settingsManager.seenTips ?? [], read: gameManager?.settingsManager.readTopics ?? [])
    }

    /// A topic opened in How to Play.
    func markRead(_ id: LearnTopic.ID) {
        guard let settings = gameManager?.settingsManager, !settings.readTopics.contains(id.rawValue) else { return }
        settings.readTopics.insert(id.rawValue)
        settings.saveSettings()
    }

    /// Open How to Play, at a topic.
    func openHowToPlay(_ topic: LearnTopic.ID? = nil) {
        howToPlay = HowToPlayRequest(topic: topic)
    }

    // MARK: - Explaining what's on the screen

    /// The "?": the next tap explains instead of acting.
    func toggleExplainMode() {
        explainMode.toggle()
        boardScene?.explainsTaps = explainMode
    }

    /// A long-press (or a tap after the "?") on the board: the figure there, or the hex.
    func explainHex(at hex: HexCoord) {
        if let piece = boardState.piece(at: hex) {
            explain(.piece(piece))
        } else {
            explain(.hex(hex))
        }
    }

    /// Learning state that belongs to one board.
    func resetLearning() {
        pendingTip = nil
        tipQueue = []
        tipPausedPlayback = false
        explanation = nil
        explainMode = false
        boardScene?.explainsTaps = false
        boardScene?.clearWhy()
        monsterWhys = [:]
        currentWhyID = nil
    }

    /// Explain something (a long-press, or a tap after the "?").
    func explain(_ subject: LearnSubject) {
        explainMode = false
        boardScene?.explainsTaps = false
        closeWhy()
        explanation = explanation(for: subject)
    }

    func closeExplanation() {
        explanation = nil
        closeWhy()
    }

    /// What to say about something on the screen.
    func explanation(for subject: LearnSubject) -> Explanation {
        switch subject {
        case .piece(let piece): return explainPiece(piece)
        case .hex(let hex): return explainHex(hex)
        case .element(let element): return explainElement(element)
        case .condition(let condition):
            let topic = LearnTopic.id(for: condition).map(LearnTopic.topic)
            return Explanation(subject: subject, title: GameText.conditionName(condition),
                               paragraphs: topic?.paragraphs ?? [], topic: topic?.id)
        case .modifierTray: return explainTray()
        case .turnRail: return explainTurnOrder()
        case .goal:
            let brief = scenarioBrief
            return Explanation(subject: subject, title: "The goal", detail: brief?.goal,
                               paragraphs: LearnTopic.topic(.scenarioGoal).paragraphs, topic: .scenarioGoal)
        case .monsterGroup(let name): return explainMonsterGroup(name)
        case .monsterCard(let name): return explainMonsterCard(name)
        case .playedCards:
            return Explanation(subject: subject, title: "Your two cards",
                               paragraphs: LearnTopic.topic(.yourTurn).paragraphs + LearnTopic.topic(.playedCards).paragraphs,
                               topic: .yourTurn)
        case .cardPanel:
            return Explanation(subject: subject, title: "Choosing cards",
                               paragraphs: LearnTopic.topic(.cardChoice).paragraphs + LearnTopic.topic(.handIsAClock).paragraphs.prefix(1),
                               topic: .cardChoice)
        case .log:
            return Explanation(subject: subject, title: "What just happened",
                               paragraphs: ["The latest moves, attacks and damage, newest at the bottom. Tap it to see the whole battle log."]
                                   + (learningMode ? ["A monster's lines have a \u{201C}Why?\u{201D}: it shows how the monster chose its target."] : []),
                               topic: .focus)
        case .topic(let id):
            let topic = LearnTopic.topic(id)
            return Explanation(subject: subject, title: topic.title, paragraphs: topic.paragraphs, topic: id)
        case .pieces(let pieces):
            return pieces.first.map { explainPiece($0) } ?? Explanation(subject: subject, title: "The board")
        case .board:
            return Explanation(subject: subject, title: "The board",
                               paragraphs: ["Long-press a figure or a hex to learn what it is."], topic: .moving)
        }
    }

    private func explainPiece(_ piece: PieceID) -> Explanation {
        guard let game = gameManager?.game else { return Explanation(subject: .piece(piece), title: name(piece)) }
        let entity = entity(for: piece)
        let health = entity.map { "\($0.health)/\($0.maxHealth)" }
        var rows: [Explanation.Row] = []
        let conditions = entity?.entityConditions.filter { !$0.expired }.map(\.name) ?? []
        if !conditions.isEmpty {
            rows.append(.init(label: "Conditions", value: GameText.list(conditions.map(GameText.conditionName)),
                              note: conditions.compactMap { LearnTopic.id(for: $0).map(LearnTopic.topic)?.paragraphs.first }.first.map(LearnTopic.plain)))
        }

        switch piece {
        case .monster(let monsterName, _):
            let monster = game.monsters.first { $0.name == monsterName }
            let type = (entity as? GameMonsterEntity)?.type ?? .normal
            let subtitle: String
            let detail: String
            switch type {
            case .elite: subtitle = "Elite \u{00B7} the gold ring"; detail = "Tougher than a normal one (white ring)"
            case .boss: subtitle = "Boss"; detail = "Its stat card lists its special abilities"
            case .normal: subtitle = "Normal \u{00B7} the white ring"; detail = "An elite (gold ring) would be tougher"
            }
            if let monster, let stats = monsterStatsThisRound(monster, type: type) {
                rows.insert(.init(label: "This round", value: stats.value, note: stats.note), at: 0)
            }
            if let monster { rows.insert(actsAtRow(.monster(monster)), at: min(1, rows.count)) }
            rows.append(.init(label: "How it acts", value: "On its own",
                              note: "It picks a focus: the enemy it can attack with the least movement. It moves toward it, then attacks."))
            return Explanation(subject: .piece(piece), title: name(piece), portrait: piece, subtitle: subtitle, detail: detail,
                               health: health, rows: rows, topic: .focus)

        case .character(let id):
            guard let character = game.characters.first(where: { $0.id == id }) else { break }
            rows.insert(.init(label: "Cards", value: "Hand \(character.handCards.count) \u{00B7} discard \(character.discardedCards.count) \u{00B7} lost \(character.lostCards.count)",
                              note: "Two cards a round: when the hand and discard pile can't give two more, the character is exhausted."), at: 0)
            if character.initiative > 0 || character.longRest {
                rows.insert(actsAtRow(.character(character)), at: 1)
            }
            rows.append(.init(label: "Experience", value: "\(character.experience)", note: nil))
            return Explanation(subject: .piece(piece), title: name(piece), portrait: piece,
                               subtitle: "Level \(character.level)", health: health, rows: rows, topic: .handIsAClock)

        case .summon:
            let owner = summonOwner(of: piece)
            if let summon = entity as? GameSummon {
                rows.insert(.init(label: "Stats", value: "Move \(summon.movement) \u{00B7} Attack \(summon.attack.intValue ?? 0)"
                                  + (summon.range > 0 ? ", range \(summon.range)" : ""), note: nil), at: 0)
            }
            rows.append(.init(label: "How it acts", value: "On its own, just before \(owner.map { characterName($0.id) } ?? "its summoner")",
                              note: "It follows the monsters' rules, with your enemies as its foes, and draws from \(owner.map { characterName($0.id) + "\u{2019}s" } ?? "its summoner\u{2019}s") modifier deck."))
            return Explanation(subject: .piece(piece), title: name(piece), portrait: piece,
                               subtitle: owner.map { "\(characterName($0.id))\u{2019}s summon" }, health: health, rows: rows, topic: .summons)

        case .objective:
            return Explanation(subject: .piece(piece), title: name(piece), health: health,
                               paragraphs: ["A figure the scenario cares about: the brief says what to do with it."], topic: .scenarioGoal)
        }
        return Explanation(subject: .piece(piece), title: name(piece), health: health, rows: rows)
    }

    /// "Move 1 · Attack 3, range 2" for this round, from the stat card and the ability card.
    private func monsterStatsThisRound(_ monster: GameMonster, type: MonsterType) -> (value: String, note: String)? {
        guard let game = gameManager?.game, let stat = monster.attackStat(for: type) else { return nil }
        let characterCount = max(2, game.characters.filter { !$0.absent }.count)
        func value(_ v: IntOrString?) -> Int {
            v.map { evaluateEntityValue($0, level: monster.level, characterCount: characterCount) } ?? 0
        }
        let baseMove = value(stat.movement), baseRange = value(stat.range)
        let baseAttack = stat.attackValue(characterCount: characterCount, level: monster.level,
                                          variables: MonsterAI.attackVariables(for: monster, gameState: game))
        guard let ability = gameManager?.monsterManager.currentAbility(for: monster) else {
            var parts = ["Move \(baseMove)", "Attack \(baseAttack)"]
            if baseRange > 1 { parts[1] += ", range \(baseRange)" }
            return (parts.joined(separator: " \u{00B7} "), "Its stat card. Each round its ability card changes these.")
        }
        let actions = ability.actions ?? []
        var parts: [String] = []
        if let move = MonsterAbility.move(in: actions, baseMove: baseMove) { parts.append("Move \(move.value)") }
        if let action = actions.first(where: { $0.type == .attack }) {
            let attack = MonsterAbility.attack(action, stat: stat, baseAttack: baseAttack, baseRange: baseRange)
            parts.append("Attack \(attack.value)" + (attack.isRanged ? ", range \(attack.range)" : ""))
        }
        if parts.isEmpty { parts = ["No move or attack"] }
        return (parts.joined(separator: " \u{00B7} "),
                "Its ability card this round (initiative \(ability.initiative)) changes its stat card\u{2019}s numbers.")
    }

    /// When a figure acts this round, between whom.
    private func actsAtRow(_ figure: AnyFigure) -> Explanation.Row {
        let index = turnOrder.firstIndex { entry in
            switch (entry.figure, figure) {
            case (.monster(let a), .monster(let b)): return a === b
            case (.character(let a), .character(let b)): return a === b
            default: return false
            }
        }
        guard let index else {
            return .init(label: "Acts at", value: "Not decided yet",
                         note: "Once everyone has chosen cards, the order is set by initiative, lowest first.")
        }
        let initiative = Int(turnOrder[index].initiative)
        var around: [String] = []
        if index > 0 {
            let before = turnOrder[index - 1]
            around.append("after \(figureName(before.figure)) (\(Int(before.initiative)))")
        }
        if index + 1 < turnOrder.count {
            let after = turnOrder[index + 1]
            around.append("before \(figureName(after.figure)) (\(Int(after.initiative)))")
        }
        let note = around.isEmpty ? "The only one acting this round." : around.joined(separator: ", ").capitalizedFirst + "."
        return .init(label: "Acts at", value: "Initiative \(initiative)", note: note)
    }

    private func explainHex(_ hex: HexCoord) -> Explanation {
        let subject = LearnSubject.hex(hex)
        var paragraphs: [String] = []
        var title = "A hex"
        if let cell = boardState.cells[hex] {
            switch cell.overlay {
            case .trap:
                title = "Trap"
                let damage = cell.trapDamage ?? gameManager?.levelManager.trap() ?? 0
                paragraphs.append("It springs on the first figure to enter it: \(damage) damage. Then it's gone. Monsters walk around traps when they can.")
            case .hazard:
                title = "Hazardous terrain"
                paragraphs.append("A figure entering it suffers damage, each time it enters. Monsters avoid it when they can; flying and jumping pass over it.")
            case .difficultTerrain:
                title = "Difficult terrain"
                paragraphs.append("Entering it costs two movement instead of one. Flying and jumping ignore it.")
            case .obstacle:
                title = "Obstacle"
                paragraphs.append("Nothing can move through it or stop on it (flying passes over), but it doesn't block line of sight.")
            case .door:
                title = boardState.isClosedDoor(hex) ? "Closed door" : "Open door"
                paragraphs.append(LearnTopic.topic(.doors).paragraphs[0])
            case .treasure:
                title = "Treasure"
                paragraphs.append("A character who ends their turn here opens it. Some hold items, some gold, some a trap.")
            case .wall:
                title = "Wall"
                paragraphs.append("Walls block movement and line of sight.")
            default:
                break
            }
        }
        if (boardState.lootTokens[hex] ?? 0) > 0 {
            if title == "A hex" { title = "Money token" }
            paragraphs.append(LearnTopic.topic(.loot).paragraphs[0])
        }
        if paragraphs.isEmpty {
            paragraphs.append("An empty hex. Long-press a figure, an element or a panel to learn about it.")
        }
        let topic: LearnTopic.ID = title == "Money token" || title == "Treasure" ? .loot
            : title.contains("door") ? .doors : .moving
        return Explanation(subject: subject, title: title, paragraphs: paragraphs, topic: topic)
    }

    private func explainElement(_ element: ElementType) -> Explanation {
        let state = gameManager?.game.elementBoard.first { $0.type == element }?.state ?? .inert
        let now: String
        switch state {
        case .inert, .consumed, .partlyConsumed: now = "Not in play. An action that infuses it will make it strong."
        case .new: now = "Infused this turn: it becomes strong when the turn ends."
        case .strong: now = "Strong: it can be consumed, and wanes at the end of the round."
        case .waning: now = "Waning: it can still be consumed, and is gone at the end of the round."
        case .always: now = "Always available in this scenario."
        }
        return Explanation(subject: .element(element), title: GameText.elementName(element), detail: now,
                           paragraphs: LearnTopic.topic(.elements).paragraphs, topic: .elements)
    }

    private func explainTray() -> Explanation {
        var rows: [Explanation.Row] = []
        if let reveal = lastModifierReveal {
            rows.append(.init(label: "Last draw", value: "\(name(reveal.attacker)) \u{2192} \(name(reveal.defender))",
                              note: reveal.sum))
        }
        return Explanation(subject: .modifierTray, title: "Attack modifier cards", rows: rows,
                           paragraphs: LearnTopic.topic(.modifiers).paragraphs, topic: .modifiers)
    }

    private func explainTurnOrder() -> Explanation {
        Explanation(subject: .turnRail, title: "The turn order",
                    paragraphs: LearnTopic.topic(.initiative).paragraphs
                        + ["A tick marks those who have acted; the ringed one is acting now."],
                    topic: .initiative)
    }

    private func explainMonsterGroup(_ name: String) -> Explanation {
        let label = monsterTypeName(name)
        return Explanation(subject: .monsterGroup(name), title: label,
                           paragraphs: ["Every \(label) on the board, by number, with their hit points. Elites (gold) act before normal ones."]
                               + LearnTopic.topic(.monstersAct).paragraphs,
                           topic: .monstersAct)
    }

    private func explainMonsterCard(_ name: String) -> Explanation {
        let label = monsterTypeName(name)
        let initiative = gameManager?.game.monsters.first { $0.name == name }
            .flatMap { gameManager?.monsterManager.currentAbilityInitiative(for: $0) }
        return Explanation(subject: .monsterCard(name), title: "\(label): this round",
                           detail: initiative.map { "Initiative \($0)" },
                           paragraphs: ["Each monster type draws one ability card a round. Its number is their initiative; its actions change their stat card\u{2019}s Move and Attack, and every \(label) does them in order."],
                           topic: .monstersAct)
    }

    // MARK: - Why a monster did what it did

    /// A monster's turn begins: what it could focus on.
    func beginWhy(for monster: PieceID, candidates: [FocusCandidate], ranged: Bool = false) {
        let why = MonsterWhy(monster: monster, candidates: candidates, ranged: ranged)
        monsterWhys[why.id] = why
        currentWhyID = why.id
        if learningMode && !candidates.isEmpty {
            teach(.focus, "Tap \u{201C}Why?\u{201D} beside a monster\u{2019}s lines in Recent to see how it chose.", at: .log)
        }
    }

    func noteWhyMove(_ hexes: Int) {
        guard let id = currentWhyID else { return }
        monsterWhys[id]?.moved += hexes
    }

    func noteWhyAttack(on target: PieceID) {
        guard let id = currentWhyID else { return }
        let sum = lastModifierReveal.flatMap { $0.defender == target ? $0.sum : nil }
        monsterWhys[id]?.attacks.append(sum.map { "\(name(target)): \($0)" } ?? "It attacked \(name(target)).")
    }

    func endWhy() { currentWhyID = nil }

    /// Show why a monster did what it did: the steps, and its choice drawn on the board.
    func showWhy(_ id: UUID) {
        guard let why = monsterWhys[id] else { return }
        explainMode = false
        explanation = whyExplanation(why)
        var chips: [PieceID: String] = [:]
        for (index, candidate) in why.candidates.enumerated() where isOnBoard(candidate.pieceID) {
            let reach = candidate.pathCost == 0 ? "in reach" : Self.hexes(candidate.pathCost)
            chips[candidate.pieceID] = index == 0 ? "Focus \u{00B7} \(reach)" : reach
        }
        boardScene?.showWhy(chips: chips, from: why.monster, to: why.focus)
    }

    func closeWhy() { boardScene?.clearWhy() }

    /// "1 hex", "3 hexes".
    static func hexes(_ n: Int) -> String { "\(n) hex\(n == 1 ? "" : "es")" }

    func whyExplanation(_ why: MonsterWhy) -> Explanation {
        let monster = name(why.monster)
        var steps: [Explanation.Row] = []
        guard let focus = why.focus else {
            return Explanation(subject: .piece(why.monster), anchor: .log, title: "Why did \(monster) do nothing?",
                               steps: [.init(label: "1", value: "No focus",
                                             note: "It couldn\u{2019}t find an enemy to reach and attack, so it didn\u{2019}t move or attack.")],
                               topic: .focus)
        }
        let target = name(focus)
        func hexes(_ n: Int) -> String { n == 0 ? "without moving" : "after \(Self.hexes(n)) of movement" }
        let first = why.candidates[0]
        if why.candidates.count == 1 {
            steps.append(.init(label: "1", value: "Its focus", note: "\(target) was the only enemy it could reach and attack."))
        } else {
            let second = why.candidates[1]
            let other = name(second.pieceID)
            let note: String
            switch FocusCandidate.reason(first, over: second) {
            case .movement:
                let rest = why.candidates.dropFirst().map { "\(name($0.pieceID)) \($0.pathCost)" }
                note = "\(why.kind) goes for the enemy it can attack with the least movement. It could attack \(target) \(hexes(first.pathCost)); \(GameText.list(rest))."
            case .proximity:
                note = "\(target) and \(other) were equally easy to reach, so it took the nearer one: \(target) was \(Self.hexes(first.proximity)) away, \(other) \(second.proximity)."
            case .initiative:
                note = "\(target) and \(other) were equally easy to reach and equally near, so it took the one who acts first: \(target) (initiative \(Int(first.initiative))) before \(other) (\(Int(second.initiative)))."
            case .traps:
                note = "Reaching \(other) meant crossing a trap or hazardous terrain, and \(why.kind.lowercased().dropFirst(2))s avoid those when they can."
            }
            steps.append(.init(label: "1", value: "Its focus", note: note))
        }
        let attacked = !why.attacks.isEmpty
        let move: String
        if why.moved == 0 {
            move = attacked ? "It could already attack \(target), so it didn\u{2019}t move." : "It didn\u{2019}t move."
        } else if first.pathCost == 0 && why.ranged && first.proximity == 1 {
            move = "It could already attack \(target), but a ranged attack on an enemy next to it has disadvantage, so it first moved \(Self.hexes(why.moved)) away."
        } else if first.pathCost == 0 {
            move = "It could already attack \(target); it moved \(Self.hexes(why.moved)) to a better hex to attack from."
        } else {
            move = "It moved \(Self.hexes(why.moved))" + (attacked ? ", until it could attack \(target)." : " toward \(target), as far as it could.")
        }
        steps.append(.init(label: "2", value: "Its move", note: move))
        if attacked {
            steps.append(.init(label: "3", value: why.attacks.count == 1 ? "Its attack" : "Its attacks",
                               note: why.attacks.joined(separator: " ")))
        }
        return Explanation(subject: .piece(why.monster), anchor: .pieces([why.monster] + why.candidates.map(\.pieceID)), title: "Why \(target)?", steps: steps,
                           footnote: "On a tie it picks the nearer enemy, then the one who acts first.", topic: .focus)
    }

    /// A short name for an attack modifier card: "+1", "−1", "×2", "Miss".
    static func modifierName(_ card: AttackModifier) -> String {
        switch card.type {
        case .null_, .curse: return "Miss"
        case .double_, .bless: return "\u{00D7}2"
        default: return card.value >= 0 ? "+\(card.value)" : "\u{2212}\(-card.value)"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
