import Foundation

/// A trap or obstacle a card places (Proximity Mine, Volatile Concoction, Avalanche).
enum PlacedToken: Equatable {
    /// Damage, the trap's sub-type (its added condition), and the experience its owner gains
    /// when an enemy springs it.
    case trap(damage: Int, subType: String?, experience: Int)
    case obstacle
    /// Not placed but taken away: an adjacent obstacle destroyed (Rock Tunnel, Explosive Punch).
    case destroyObstacle

    var name: String {
        switch self {
        case .trap(let damage, let subType, _):
            return subType == "poison" ? "a \(damage) damage poison trap" : "a \(damage) damage trap"
        case .obstacle, .destroyObstacle: return "an obstacle"
        }
    }

    /// What the player does with it: "Place an obstacle", "Destroy an obstacle".
    var verb: String { self == .destroyObstacle ? "Destroy" : "Place" }

    var imageName: String {
        switch self {
        case .trap(_, let subType, _): return subType == "poison" ? "trap-poison" : "trap-spike"
        case .obstacle, .destroyObstacle: return "obstacle-boulder-1"
        }
    }
}

/// How a figure travels along a path, which decides which hexes' terrain affects it.
enum MovementStyle {
    /// Normal movement: every hex entered triggers traps and hazardous terrain.
    case normal
    /// Jump: only the last hex counts as entered (GH p.17).
    case jump
    /// Flying: unaffected by traps and terrain for the whole move.
    case fly
    /// Push/pull: every hex entered triggers traps and hazards (difficult terrain doesn't apply).
    case forced
}

extension BoardCoordinator {

    /// Move a piece along `path` (first element = current hex), resolving traps, hazardous
    /// terrain and — for characters — closed doors on every hex actually entered.
    /// Returns false if the figure died (or became exhausted) along the way.
    @discardableResult
    @MainActor func moveAlong(_ pieceID: PieceID, path: [HexCoord], style: MovementStyle) async -> Bool {
        guard path.count > 1 else { return isOnBoard(pieceID) }
        moveObserver?(pieceID, path, style)
        // The acting character's own movement, for the items that count it.
        if style != .forced, case .character(let id) = pieceID, activePlayerTurn?.characterID == id {
            activePlayerTurn?.hexesMoved += path.count - 1
            activePlayerTurn?.lastMoveLength = path.count - 1
            activePlayerTurn?.hexesPassed.append(contentsOf: path.dropFirst().dropLast())
        }
        let hazardProof = (entity(for: pieceID) as? GameCharacter).map { PassiveItems.ignoresHazards($0.carriedItems) } ?? false
        let opensDoors: Bool = { if case .character = pieceID { return true }; return false }()

        let generation = boardGeneration
        var segmentStart = 0
        for index in 1..<path.count {
            let hex = path[index]
            let isLast = index == path.count - 1
            let entered = style == .normal || style == .forced || (style == .jump && isLast)
            let cell = boardState.cells[hex]
            let hitsTrap = entered && cell?.isTrap == true
            let hitsHazard = entered && cell?.isHazard == true && !hazardProof
            let wadesHazard = entered && cell?.isHazard == true && hazardProof
            let opensDoor = opensDoors && boardState.doors.contains { $0.coord == hex && !$0.isOpen }

            guard hitsTrap || hitsHazard || wadesHazard || opensDoor || isLast else { continue }

            await animateMove(pieceID, along: Array(path[segmentStart...index]), as: MoveAnimation(style))
            // The board was left or restarted while the figure walked: nothing more happens.
            guard isCurrentBoard(generation) else { return false }
            segmentStart = index
            if !boardState.isOccupied(hex) || boardState.piecePositions[pieceID] == hex {
                boardState.movePiece(pieceID, to: hex)
            }

            if hitsTrap {
                guard await springTrap(at: hex, on: pieceID), isCurrentBoard(generation) else { return false }
                // Immobilize takes effect at once (e.g. a bear trap): the rest of the move is lost.
                if style != .forced && isConditionActive(.immobilize, on: pieceID) {
                    log("\(name(pieceID)) is immobilized and stops", category: .condition)
                    return isOnBoard(pieceID)
                }
            }
            if hitsHazard {
                guard await enterHazard(at: hex, on: pieceID), isCurrentBoard(generation) else { return false }
            }
            // Magma Waders: no harm from hazardous terrain, and Heal 2 on a turn that enters it.
            if wadesHazard, let turn = activePlayerTurn,
               case .character(let id) = pieceID, turn.characterID == id, !turn.magmaWadersHealed,
               (entity(for: pieceID) as? GameCharacter)?.carriedItems.contains(PassiveItems.magmaWaders) == true {
                turn.magmaWadersHealed = true
                let healed = heal(pieceID, amount: 2, source: pieceID)
                log("\(name(pieceID))\u{2019}s Magma Waders heal \(healed)", category: .heal)
            }
            if opensDoor {
                openDoor(at: hex)
            }
        }
        if let turn = activePlayerTurn, case .character(let id) = pieceID, turn.characterID == id,
           style != .forced, !turn.afterMoveTexts.isEmpty {
            for text in turn.afterMoveTexts {
                if text.contains("force one adjacent enemy to perform") {
                    // Sinister Opportunity: "…perform Move 1, with you controlling the action, and
                    // ending in a hex adjacent to you."
                    var move = ActionModel(type: .move, value: .int(1))
                    if turn.afterMoveTexts.contains(where: { $0.contains("ending in a hex adjacent to you") }) {
                        move.subActions = [ActionModel(type: .specialTarget, value: .string("endAdjacentToController"))]
                    }
                    _ = beginChoosingPerformer(for: move, by: pieceID, enemies: true, range: 1)
                } else if text.contains("every hex you enter") {
                    lootHexes(for: pieceID, coords: Array(path.dropFirst()))
                } else if text.contains("suffer") {
                    await printedDamage(text, amount: PlayerTurnController.damageAmount(in: text), by: pieceID,
                                  around: boardState.piecePositions[pieceID])
                }
            }
            turn.afterMoveTexts = []
        }
        if let turn = activePlayerTurn, case .character(let id) = pieceID, turn.characterID == id,
           style != .forced, !turn.movedThroughConditions.isEmpty {
            if !turn.movedThroughNeedsLoop || path.first == path.last {
                for condition in turn.movedThroughConditions {
                    applyCondition(condition, toEnemiesOn: turn.hexesPassed, from: pieceID)
                }
            }
            turn.movedThroughConditions = []
        }
        return isOnBoard(pieceID)
    }

    /// Damage printed on a card: "all adjacent allies and enemies", "all adjacent allies",
    /// "all allies", or (with `around` the target's hex) "adjacent to the target".
    /// Damage printed outside an attack ("all adjacent enemies suffer 2 damage"); characters may
    /// negate it by losing cards, as any damage (p.22).
    @MainActor func printedDamage(_ text: String, amount: Int, by pieceID: PieceID, around hex: HexCoord?) async {
        guard amount > 0 else { return }
        var victims: [PieceID] = []
        if text.contains("all allies suffer") {
            victims = boardState.piecePositions.keys.filter { $0 != pieceID && !areEnemies(pieceID, $0) && isFigure($0) }
        } else if let hex {
            let besides = hex.neighbors.compactMap { boardState.piece(at: $0) }.filter { $0 != pieceID && isFigure($0) }
            if text.contains("allies and enemies") {
                victims = besides
            } else if text.contains("allies") {
                victims = besides.filter { !areEnemies(pieceID, $0) }
            } else if text.contains("enemies") {
                victims = besides.filter { areEnemies(pieceID, $0) }
            }
        }
        let generation = boardGeneration
        for victim in victims.sorted() where isOnBoard(victim) && isCurrentBoard(generation) {
            log("\(name(victim)) suffers \(amount) damage", category: .damage)
            await sufferDamageWithMitigation(amount, to: victim, source: name(pieceID), killer: pieceID)
        }
    }

    /// Figures (not objectives) for printed damage.
    private func isFigure(_ piece: PieceID) -> Bool {
        if case .objective = piece { return false }
        return true
    }

    // MARK: - Actions another figure performs

    /// Offer a printed action to another figure (an ally, or an enemy the character controls).
    /// False when no one can take it.
    func beginChoosingPerformer(for action: ActionModel, by pieceID: PieceID, enemies: Bool, range: Int,
                                summonsOnly: Bool = false) -> Bool {
        guard let position = boardState.piecePositions[pieceID] else { return false }
        let candidates = Set(boardState.piecePositions.filter { piece, hex in
            piece != pieceID && hex.distance(to: position) <= range && entity(for: piece) != nil
                && areEnemies(pieceID, piece) == enemies && LineOfSight.hasLOS(from: position, to: hex, board: boardState)
                && (!summonsOnly || { if case .character(let id) = pieceID { return summonOwner(of: piece)?.id == id }; return false }())
        }.keys)
        guard !candidates.isEmpty else {
            log("\(name(pieceID)) has no \(enemies ? "enemy" : "ally") in range to perform it", category: .info)
            return false
        }
        interactionMode = .choosingPerformer(pieceID: pieceID, action: action, candidates: candidates)
        let hexes = Set(candidates.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(hexes, style: enemies ? .forcedMove : .heal, offsetCol: offsetCol, offsetRow: offsetRow)
        return true
    }

    /// The chosen figure performs the action, the character controlling it.
    func perform(_ action: ActionModel, by performer: PieceID) {
        let value = action.value?.intValue ?? 0
        log("\(name(performer)) performs \(GameText.actionTitle(action))", category: .info)
        switch action.type {
        case .move:
            beginMoveAction(pieceID: performer, moveRange: value)
            // "Ending in a hex adjacent to you": only those destinations.
            if action.subActions?.contains(where: { $0.value?.stringValue == "endAdjacentToController" }) == true,
               let controller = activePlayerTurn.flatMap({ boardState.piecePositions[.character($0.characterID)] }),
               case .selectingMove(let mover, let range, let hexes, let teleport, let mode) = interactionMode {
                let beside = hexes.filter { $0.isAdjacent(to: controller) }
                interactionMode = .selectingMove(pieceID: mover, range: range, validHexes: beside, teleport: teleport, mode: mode)
                boardScene?.highlightHexes(beside, style: .move, offsetCol: offsetCol, offsetRow: offsetRow)
            }
        case .attack:
            if let controller = activePlayerTurn.map({ PieceID.character($0.characterID) }), areEnemies(controller, performer) {
                beginForcedEnemyAttack(action, by: performer, controller: controller)
                return
            }
            let range = action.subActions?.first { $0.type == .range }?.value?.intValue ?? 1
            activePlayerTurn?.preparePerformedAttack(value: value, range: max(1, range))
            beginAttackAction(pieceID: performer, range: max(1, range))
        default:
            activePlayerTurn?.advanceAfterAsyncAction()
        }
    }

    /// An enemy forced to attack another enemy, the character choosing the target (Submissive
    /// Affliction). By the Mindthief FAQ an unsigned value is the attack itself ("Attack 2", not
    /// +2) and a signed range is added to the monster's base range; the monster's modifier deck
    /// and stat-card attack effects apply.
    func beginForcedEnemyAttack(_ action: ActionModel, by performer: PieceID, controller: PieceID) {
        guard case .monster(let name, let standee) = performer,
              let monster = gameManager?.game.monsters.first(where: { $0.name == name }),
              let forcedEntity = monsterEntity(name: name, standee: standee),
              let position = boardState.piecePositions[performer] else {
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        if isConditionActive(.disarm, on: performer) {
            log("\(self.name(performer)) is disarmed and can\u{2019}t attack", category: .condition)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        let stat = monster.attackStat(for: forcedEntity.type)
        let characterCount = max(2, (gameManager?.game.characters.filter { !$0.absent }.count) ?? 2)
        let baseRange = stat?.rangeValue(characterCount: characterCount, level: monster.level) ?? 0
        let baseAttack = stat?.attackValue(characterCount: characterCount, level: monster.level) ?? 0
        var forced = action
        if forced.valueType == nil { forced.valueType = .fixed }
        let spec = MonsterAbility.attack(forced, stat: stat, baseAttack: baseAttack, baseRange: baseRange)
        let targets = Set(boardState.piecePositions.filter { piece, hex in
            piece != performer && areEnemies(controller, piece) && entity(for: piece) != nil
                && !isConditionActive(.invisible, on: piece) && position.distance(to: hex) <= spec.range
                && LineOfSight.hasLOS(from: position, to: hex, board: boardState)
        }.keys)
        guard !targets.isEmpty else {
            log("\(self.name(performer)) has no other enemy within range \(spec.range) to attack", category: .attack)
            activePlayerTurn?.advanceAfterAsyncAction()
            return
        }
        pendingForcedAttack = AttackParameters(value: spec.value, isRanged: baseRange > 0 || spec.range > 1,
                                               pierce: spec.pierce, conditions: spec.conditions,
                                               push: spec.push, pull: spec.pull, advantage: spec.advantage)
        interactionMode = .selectingAttackTarget(pieceID: performer, range: spec.range, validTargets: targets)
        let hexes = Set(targets.compactMap { boardState.piecePositions[$0] })
        boardScene?.highlightHexes(hexes, style: .attack, offsetCol: offsetCol, offsetRow: offsetRow)
    }

    // MARK: - Traps and obstacles from cards

    /// Ask the player to place `count` tokens in empty hexes next to the character; false when
    /// there's no room (the rest of the action is lost).
    func beginPlacingTokens(_ token: PlacedToken, count: Int, by pieceID: PieceID) -> Bool {
        guard count > 0, let position = boardState.piecePositions[pieceID] else { return false }
        let hexes = Set(position.neighbors.filter { hex in
            token == .destroyObstacle ? boardState.cells[hex]?.overlay == .obstacle : isEmptyHex(hex)
        })
        guard !hexes.isEmpty else {
            log(token == .destroyObstacle ? "\(name(pieceID)) has no obstacle beside them"
                                          : "\(name(pieceID)) has no empty hex beside them for \(token.name)", category: .info)
            return false
        }
        interactionMode = .placingToken(pieceID: pieceID, token: token, remaining: count, validHexes: hexes)
        boardScene?.highlightHexes(hexes, style: .summon, offsetCol: offsetCol, offsetRow: offsetRow)
        return true
    }

    func placeToken(_ token: PlacedToken, at hex: HexCoord, by pieceID: PieceID, remaining: Int) {
        switch token {
        case .trap(let damage, let subType, let experience):
            boardState.placeTrap(at: hex, damage: damage, subType: subType)
            if experience > 0, case .character(let id) = pieceID { characterTraps[hex] = (id, experience) }
        case .obstacle:
            boardState.placeObstacle(at: hex)
        case .destroyObstacle:
            boardState.removeObstacle(at: hex)
        }
        if token == .destroyObstacle {
            boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        } else {
            boardScene?.addOverlaySprite(imageName: token.imageName, at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        }
        boardScene?.clearHighlights()
        log("\(name(pieceID)) \(token.verb.lowercased())s \(token.name)", category: .info, trace: "at \(hex)")
        interactionMode = .idle
        if remaining > 1, beginPlacingTokens(token, count: remaining - 1, by: pieceID) { return }
        activePlayerTurn?.advanceAfterAsyncAction()
    }

    /// A trap a monster places (an Archer's, a Flame Demon's): no choice, no turn to advance.
    func placeTrap(damage: Int, at hex: HexCoord, by pieceID: PieceID) {
        let token = PlacedToken.trap(damage: damage, subType: nil, experience: 0)
        boardState.placeTrap(at: hex, damage: damage)
        boardScene?.addOverlaySprite(imageName: token.imageName, at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        log("\(name(pieceID)) places \(token.name)", category: .info, trace: "at \(hex)")
    }

    /// Thief's Knack: disarm one trap next to the figure.
    func disarmTrap(besides pieceID: PieceID) {
        guard let position = boardState.piecePositions[pieceID],
              let trap = position.neighbors.sorted().first(where: { boardState.cells[$0]?.isTrap == true }) else {
            log("\(name(pieceID)) has no adjacent trap to disarm", category: .info)
            return
        }
        boardState.removeTrap(at: trap)
        boardScene?.removeOverlaySprite(at: trap, offsetCol: offsetCol, offsetRow: offsetRow)
        log("\(name(pieceID)) disarms a trap", category: .info)
    }

    /// A condition for every enemy standing on one of `hexes` ("all enemies moved through").
    func applyCondition(_ condition: ConditionName, toEnemiesOn hexes: [HexCoord], from pieceID: PieceID) {
        let passed = Set(hexes)
        let targets = boardState.piecePositions.filter { passed.contains($0.value) && areEnemies(pieceID, $0.key) }
            .map(\.key).sorted()
        for target in targets { applyCondition(condition, to: target) }
        log(targets.isEmpty ? "\(name(pieceID)) moved through no enemy"
                            : "\(name(pieceID)) gives \(GameText.list(targets.map(name))) \(GameText.conditionName(condition))",
            category: .condition)
    }

    func isOnBoard(_ pieceID: PieceID) -> Bool {
        boardState.piecePositions[pieceID] != nil
    }

    /// Animate a piece along a path (skipped when no scene is attached, e.g. in tests).
    @MainActor func animateMove(_ pieceID: PieceID, along path: [HexCoord], as animation: MoveAnimation = .walk) async {
        guard path.count > 1 else { return }
        await waitWhilePaused()
        guard let scene = boardScene else { return }
        // Parked by move until the animation finishes; teardown resumes whatever is still parked
        // (a scene that's gone never finishes its animations). Whichever comes first resumes it.
        let move = UUID()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingMoveAnimations[move] = continuation
            scene.movePiece(id: pieceID, along: path, animation: animation, offsetCol: offsetCol, offsetRow: offsetRow) { [weak self] in
                self?.pendingMoveAnimations.removeValue(forKey: move)?.resume()
            }
        }
    }

    /// Spring the trap on `hex` (GH p.13): damage traps inflict 2 + L, sub-types add their
    /// conditions, and the trap is removed. Returns false if the figure died.
    @MainActor func springTrap(at hex: HexCoord, on pieceID: PieceID) async -> Bool {
        guard let gameManager, let cell = boardState.cells[hex], cell.isTrap else { return true }
        // Neutralizer: a trap sprung on a character's (or their summon's) turn is theirs.
        if let character = creditedCharacter(for: actingPiece) {
            gameManager.scenarioStatsManager.recordTrap(by: character.name)
        }
        let damage = cell.trapDamage ?? gameManager.levelManager.trap()
        let subType = cell.overlaySubType

        boardState.removeTrap(at: hex)
        boardScene?.removeOverlaySprite(at: hex, offsetCol: offsetCol, offsetRow: offsetRow)
        boardScene?.play(.trap)
        log("\(name(pieceID)) springs a trap and suffers \(damage) damage", category: .damage, trace: subType)
        // Proximity Mine: experience for its owner when an enemy springs it.
        if let (owner, experience) = characterTraps.removeValue(forKey: hex), areEnemies(.character(owner), pieceID),
           let character = gameManager.game.characters.first(where: { $0.id == owner }) {
            character.experience += experience
            log("\(name(.character(owner))) gains \(experience) XP", category: .info)
        }

        if await sufferDamageWithMitigation(damage, to: pieceID, source: "a trap") {
            return false
        }
        for condition in Self.trapConditions(for: subType) {
            applyCondition(condition, to: pieceID)
        }
        return isOnBoard(pieceID)
    }

    /// Enter hazardous terrain: damage on entering, the terrain stays. Returns false if the figure died.
    @MainActor func enterHazard(at hex: HexCoord, on pieceID: PieceID) async -> Bool {
        guard let gameManager else { return true }
        let damage = gameManager.levelManager.terrain()
        log("\(name(pieceID)) suffers \(damage) damage from hazardous terrain", category: .damage)
        if await sufferDamageWithMitigation(damage, to: pieceID, source: "hazardous terrain") {
            return false
        }
        return isOnBoard(pieceID)
    }

    /// Conditions a trap applies in addition to its damage, by overlay sub-type.
    static func trapConditions(for subType: String?) -> [ConditionName] {
        switch subType {
        case "poison": return [.poison]
        case "bear": return [.immobilize]
        case "thorns": return [.wound]
        default: return []
        }
    }
}
