#!/usr/bin/env python3
"""Mutation checks for the rule tests: break one rule in the game code, run the rule tests, and
say which tests noticed. A mutation no test fails for is a rule without a test.

    scripts/mutate.py --list            the mutations
    scripts/mutate.py <name> [filter]   apply one, run the tests (optionally only `filter`), restore
    scripts/mutate.py --all             every mutation in turn (slow: a build and a test run each)
    scripts/mutate.py --scenario        only the scenario-rule mutations (S), against the scenario tests

The file is restored with `git checkout`, so the script refuses to touch a file with uncommitted
changes. A pattern "found 0 times" means the game code has moved on: update the mutation.
"""
import subprocess, sys, re, os
WT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCR=os.path.join(WT, ".build", "mutations")
os.makedirs(SCR, exist_ok=True)
FILTER=("AttackRuleTests|ConditionRuleTests|RoundRuleTests|LootRuleTests|MovementRuleTests|RevealRuleTests|ScenarioEndRuleTests|"
        "ScenarioLevelRuleTests|ForcedMovementTests|RB_|PlayLedgerTests|PlaythroughTests|RestRuleTests|BoardRulesRegressionTests|"
        "JumpFlyMovementTests|HealAndConsumeRuleTests|CombatEffectsTests|TurnFlowTests|E2E|AttackModifier|BoardSimulationTests|MonsterTurnRulesTests|ScenarioFinishEdgeCaseTests|DynamicObstacleTests|FeatureTests|EscortAITests|TeleportTests|HexCoordTests|"
        "MoneyTokenTests|SetupRulesTests|ItemUseRuleTests|ChargedBonusTests|ActionPerformedTests|ScenarioEnforcedRuleTests|ScenarioReauditTests|ModifierDeckRoundEndTests")
M={
 "poison0": ("GlavenGame/Engine/CombatResolver.swift", "        if isPoisoned {\n            attackValue += 1\n        }", "        if isPoisoned {\n            attackValue += 0\n        }"),
 "retaliateShielded": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "            await sufferDamageWithMitigation(retaliate, to: attacker,", "            await sufferDamageWithMitigation(max(0, retaliate - self.shield(of: attacker)), to: attacker,"),
 "noRangedAdjacentDisadvantage": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "        var disadvantage = (attack.isRanged && boardState.areAdjacent(attackerPos, targetPos)) || disadvantagedThisRound.contains(target)", "        var disadvantage = disadvantagedThisRound.contains(target)"),
 "effectsOnTheDead": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "        if !died && isOnBoard(target) {\n            for condition in result.allConditions {", "        if true {\n            for condition in result.allConditions {"),
 "noEffectsOnNull": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "        if !died && isOnBoard(target) {\n            for condition in result.allConditions {", "        if !died && isOnBoard(target) && !result.isMiss {\n            for condition in result.allConditions {"),
 "trapShielded": ("GlavenGame/Board/BoardCoordinator+Movement.swift", "        let damage = effect.damage ? (cell.trapDamage ?? gameManager.levelManager.trap()) : 0\n        let subType", "        let damage = effect.damage ? max(0, (cell.trapDamage ?? gameManager.levelManager.trap()) - shield(of: pieceID)) : 0\n        let subType"),
 "hazardPoisoned": ("GlavenGame/Board/BoardCoordinator+Movement.swift", "        let damage = gameManager.levelManager.terrain()\n", "        let damage = gameManager.levelManager.terrain() + (isConditionActive(.poison, on: pieceID) ? 1 : 0)\n"),
 "summonDrawsMonsterDeck": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "            guard let owner = summonOwner(of: attacker) else { return { nil } }\n            return { am.drawCharacterCard(for: owner) }", "            guard summonOwner(of: attacker) != nil else { return { nil } }\n            return { am.drawMonsterCard() }"),
 "allyDrawsMonsterDeck": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "            return isPlayerSide(attacker) ? { am.drawAllyCard() } : { am.drawMonsterCard() }", "            return { am.drawMonsterCard() }"),
 "noEndOfRoundReshuffle": ("GlavenGame/Managers/RoundManager.swift", "            if character.attackModifierDeck.needsShuffle {", "            if false {"),
 "reshuffleKeepsDrawnBless": ("GlavenGame/Models/Structs/AttackModifierDeck.swift", "        var newCards = attackModifiers.filter { !$0.type.isSpecial }\n", "        var newCards = attackModifiers\n"),
 "blessCausesReshuffle": ("GlavenGame/Models/Structs/AttackModifierDeck.swift", "        return cards[0...current].contains(where: { $0.shuffle && !$0.type.isSpecial })", "        return cards[0...current].contains(where: { $0.shuffle || $0.type.isSpecial })"),
 "newSummonActs": ("GlavenGame/Board/SummonTurnController.swift", "            if summon.state == .new {", "            if false {"),
 "conditionEndsWithTheTurnItCame": ("GlavenGame/Managers/EntityManager.swift", "            if types.contains(.afterTurn) && condition.state == .normal {", "            if types.contains(.afterTurn) && (condition.state == .normal || condition.state == .new) {"),
 "stunKeepsCards": ("GlavenGame/Board/BoardCoordinator.swift", "                    character.handCards.removeAll { $0 == cardId }\n                    character.discardedCards.append(cardId)", "                    _ = cardId"),
 "noEndOfTurnLoot": ("GlavenGame/Board/BoardCoordinator.swift", "        if let pos = boardState.piecePositions[pieceID] {\n            lootHexes(for: pieceID, coords: [pos])\n        }", "        _ = pieceID"),
 "lootIgnoresSight": ("GlavenGame/Board/BoardCoordinator.swift", "            return coord == pos || LineOfSight.hasLOS(from: pos, to: coord, board: boardState)\n        }\n        if coords.isEmpty {", "            return true\n        }\n        if coords.isEmpty {"),
 "revealedDontDraw": ("GlavenGame/Board/BoardCoordinator.swift", "            if isMidRound, !monster.abilityDrawn, !inactive.contains(monster.name) {", "            if false {"),
 "revealedDontActThisRound": ("GlavenGame/Board/BoardCoordinator.swift", "        if isMidRound {\n            for piece in placed where !inactive.contains(piece.name) {", "        if false {\n            for piece in placed where !inactive.contains(piece.name) {"),
 "revealedActLast": ("GlavenGame/Board/BoardCoordinator.swift", "            let insertAt = turnOrder.indices.first { $0 > currentTurnIndex && turnOrder[$0].initiative > initiative }\n                ?? turnOrder.count\n            turnOrder.insert(entry, at: insertAt)", "            let insertAt = turnOrder.count\n            turnOrder.insert(entry, at: insertAt)"),
 "revealedMissTheirPlace": ("GlavenGame/Board/BoardCoordinator.swift", "            let insertAt = turnOrder.indices.first { $0 > currentTurnIndex && turnOrder[$0].initiative > initiative }\n                ?? turnOrder.count\n            turnOrder.insert(entry, at: insertAt)", "            if turnOrder.indices.contains(currentTurnIndex), initiative < turnOrder[currentTurnIndex].initiative { continue }\n            let insertAt = turnOrder.indices.first { $0 > currentTurnIndex && turnOrder[$0].initiative > initiative }\n                ?? turnOrder.count\n            turnOrder.insert(entry, at: insertAt)"),
 "jumpLandsFree": ("GlavenGame/Board/BoardCoordinator+Movement.swift", "|| (style == .jump && isLast)", "|| false"),
 "goldRate": ("GlavenGame/Managers/LevelManager.swift", "let table = [2, 2, 3, 3, 4, 4, 5, 6]", "let table = [2, 2, 2, 3, 4, 4, 5, 5]"),
 "victoryDespiteExhaustion": ("GlavenGame/Board/BoardCoordinator.swift", "        if !allChars.isEmpty && allChars.allSatisfy({ $0.exhausted }) {\n            endReason = .partyExhausted", "        if !allChars.isEmpty && allChars.allSatisfy({ $0.exhausted }) && pendingResult != .victory {\n            endReason = .partyExhausted"),
 "exhaustedKeepsHand": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "            character.lostCards.append(contentsOf: character.handCards + character.discardedCards + character.activeCards)\n            character.handCards = []", "            character.lostCards.append(contentsOf: character.discardedCards + character.activeCards)"),
 "pierceIgnored": ("GlavenGame/Engine/CombatResolver.swift", "        let effectiveShield = max(0, shield - pierce - modifierPierce)", "        let effectiveShield = max(0, shield)"),
 "shieldsDontAdd": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "CombatResolver.totalShield(shield: entity.shield, shieldPersistent: entity.shieldPersistent)", "(entity.shieldPersistent?.value?.intValue ?? entity.shield?.value?.intValue ?? 0)"),
 "levelRoundsDown": ("GlavenGame/Managers/LevelManager.swift", "        var level = (totalLevels + divisor - 1) / divisor", "        var level = totalLevels / divisor"),
 "summonCurseToMonsterDeck": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "            case .summon:\n                summonOwner(of: pieceID)?.attackModifierDeck.addCard(type: type)", "            case .summon:\n                gameManager.game.monsterAttackModifierDeck.addCard(type: type)"),
 "strengthenNoAdvantage": ("GlavenGame/Board/BoardCoordinator+Combat.swift", "            advantage = advantage || CombatResolver.hasAdvantage(attacker: attackerEntity)\n            disadvantage = CombatResolver.hasDisadvantage(attacker: attackerEntity, isRangedAdjacent: disadvantage)\n        }\n\n        // Show who attacks whom", "            disadvantage = CombatResolver.hasDisadvantage(attacker: attackerEntity, isRangedAdjacent: disadvantage)\n        }\n\n        // Show who attacks whom"),
 "targetsIgnoreRange": ("GlavenGame/Board/BoardCoordinator.swift", "            guard boardState.isWithin(max(1, range), from: pos, to: coord),\n                  LineOfSight.hasLOS(from: pos, to: coord, board: boardState) else { continue }\n            targets.insert(id)", "            guard boardState.isWithin(max(1, range) + 2, from: pos, to: coord),\n                  LineOfSight.hasLOS(from: pos, to: coord, board: boardState) else { continue }\n            targets.insert(id)"),
 "turnOrderDescending": ("GlavenGame/Board/BoardCoordinator.swift", "        }.sorted { $0.initiative < $1.initiative }\n\n        currentTurnIndex = -1", "        }.sorted { $0.initiative > $1.initiative }\n\n        currentTurnIndex = -1"),
 "bonusXpOnLoss": ("GlavenGame/Managers/ScenarioManager.swift", "        if success {\n            // Record completion", "        for character in game.characters where !success && !character.absent { character.experience += levelManager.experience() }\n        if success {\n            // Record completion"),
 "exhaustedDontCount": ("GlavenGame/Models/GameState.swift", "        max(2, characters.filter { !$0.absent }.count)", "        max(2, characters.filter { !$0.absent && !$0.exhausted }.count)"),
 "invisibleIsFocused": ("GlavenGame/Engine/MonsterAI.swift", "                return includeInvisible || !isActive(.invisible, on: char)", "                return true"),
 "longRestNoDiscardCheck": ("GlavenGame/Board/BoardCoordinator.swift", "              character.discardedCards.count >= 2 else { return }\n        character.initiative = 99", "              character.discardedCards.count >= 0 else { return }\n        character.initiative = 99"),
 "alliedMonstersDropMoney": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "            if entity.summonState == nil && !MonsterAI.isAllyFaction(monster) {", "            if entity.summonState == nil {"),
 "bossesDropNoMoney": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "            if entity.summonState == nil && !MonsterAI.isAllyFaction(monster) {", "            if entity.summonState == nil && entity.type != .boss && !MonsterAI.isAllyFaction(monster) {"),
 "soloChangesNothing": ("GlavenGame/Models/GameState.swift", "    var monsterLevel: Int { min(7, level + (solo ? 1 : 0)) }", "    var monsterLevel: Int { level }"),
 "soloRaisesGold": ("GlavenGame/Managers/LevelManager.swift", "        let table = [2, 2, 3, 3, 4, 4, 5, 6]\n", "        let table = [2, 2, 3, 3, 4, 4, 5, 6]\n        if game.solo { return table[max(0, min(7, game.monsterLevel))] }\n"),
 "escapeIsExhaustion": ("GlavenGame/Board/BoardCoordinator+Outcome.swift", "                exhausted: character.exhausted && !boardState.escapedCharacters.contains(character.id),", "                exhausted: character.exhausted,"),
 "stunnedUseItems": ("GlavenGame/Board/BoardCoordinator+Items.swift", "        !isConditionActive(.stun, on: .character(character.id))\n    }", "        true || !isConditionActive(.stun, on: .character(character.id))\n    }"),
 "restGivesUsesBack": ("GlavenGame/Board/BoardCoordinator.swift", "        for key in character.spentItems { character.itemSlotsUsed[key] = nil }\n", "        character.itemSlotsUsed.removeAll()\n"),
 "armourWaitsToBeAsked": ("GlavenGame/Board/BoardCoordinator+Items.swift", "        holder(of: item, attacked: target).map { $0.data.slots > 1 } ?? false", "        holder(of: item, attacked: target).map { $0.data.slots > 99 } ?? false"),
 "ownDamageNotNegated": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "        guard amount > 0, !autoResolvePrompts,\n              let character = gameManager?.game.characters.first(where: { $0.id == characterID }),", "        guard amount > 0, !autoResolvePrompts, amount < 0,\n              let character = gameManager?.game.characters.first(where: { $0.id == characterID }),"),
 "chargePerFigureHealed": ("GlavenGame/Board/BoardCoordinator+Bonuses.swift", "        if let decided = turn.healActionCleanses { return decided }\n", ""),
 "attackBonusMarksNoCharge": ("GlavenGame/Board/BoardCoordinator+Bonuses.swift", "                result += turn?.bonusPerAttack ?? n\n                useFirstCharge(of: attacker) { $0 == bonus }", "                result += turn?.bonusPerAttack ?? n"),
 "endedBonusStillActs": ("GlavenGame/Board/BoardCoordinator+Bonuses.swift", "            turn.persistentCardsThisTurn.removeAll { $0 == cardId }\n            turn.roundCardsThisTurn.removeAll { $0 == cardId }", "            _ = turn"),
 "noItemsOnARestTurn": ("GlavenGame/Board/BoardCoordinator+Items.swift", "            return turn.phase != .selectTopCard\n", "            return turn.phase != .selectTopCard && !turn.isLongRest\n"),
 "restTurnSkipsBonuses": ("GlavenGame/Board/PlayerTurnController.swift", "        guard isLongRest, phase == .turnComplete, !steps.isEmpty, !(character?.exhausted ?? true) else { return done() }", "        guard isLongRest, phase == .turnComplete, steps.isEmpty, !steps.isEmpty, !(character?.exhausted ?? true) else { return done() }"),
 "roundStartRulesWaitForTheCards": ("GlavenGame/Board/BoardCoordinator.swift", "        gameManager.scenarioRulesManager.evaluateRulesForTheRoundToCome()\n", ""),
}
# Scenario rules (the mechanisms of placements/gh.json): run against the scenario tests.
SCENARIO_FILTER=("ScenarioSpecialRuleTests|ScenarioReauditTests|ScenarioEnforcedRuleTests|ScenarioLockTests|ScenarioGoalTests|"
                 "ScenarioSpawnTests|DemonicRiftTests|BattlementsTests|MonsterTextTests|MonsterSummonTests")
S={
 "factSavedIgnored": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "            guard arrived >= saved else { return false }", "            guard arrived >= 0 * saved else { return false }"),
 "factLockIgnored": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "        if let lock = fact.lock, !boardState.releasedLocks.contains(lock) { return false }", "        if let lock = fact.lock, lock < 0 { return false }"),
 "factUnrevealedIgnored": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "        if let room = fact.unrevealed, gameManager?.game.scenario?.revealedRooms.contains(room) != false { return false }", "        if let room = fact.unrevealed, room < 0 { return false }"),
 "factOccupiedIgnored": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "            guard !hexes.isEmpty, hexes.allSatisfy(boardState.isOccupied) else { return false }", "            guard !hexes.isEmpty else { return false }"),
 "factLootedIgnored": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "            if looted == Self.goalTreasureID {\n                guard treasureIsLooted(looted) else { return false }", "            if looted == Self.goalTreasureID {\n                guard treasureIsLooted(looted) || true else { return false }"),
 "standingLosesNothing": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "                if case .monster(let name, _)? = boardState.piece(at: hex), stands.monsters.contains(name) {", "                if case .monster(let name, _)? = boardState.piece(at: hex), stands.monsters.contains(name), false {"),
 "lootActionNotNeeded": ("GlavenGame/Board/BoardCoordinator+Goals.swift", "    var goalTreasureNeedsLootAction: Bool { scenarioData?.placements?.lootActionOnly == true }", "    var goalTreasureNeedsLootAction: Bool { false }"),
 "scenarioAttackIgnored": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        scenarioEffects(on: pieceID).reduce(0) { $0 + ($1.attack ?? 0) }", "        scenarioEffects(on: pieceID).reduce(0) { $0 + 0 * ($1.attack ?? 0) }"),
 "scenarioAdvantageIgnored": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        scenarioEffects(on: pieceID).contains { $0.advantage == true }", "        scenarioEffects(on: pieceID).contains { $0.advantage == true && false }"),
 "scenarioDisadvantageIgnored": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        scenarioEffects(on: pieceID).contains { $0.disadvantage == true }", "        scenarioEffects(on: pieceID).contains { $0.disadvantage == true && false }"),
 "scenarioShieldIgnored": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "            return total + (ScenarioExpression.integerValue(formula, variables: variables) ?? 0)", "            return total + 0 * (ScenarioExpression.integerValue(formula, variables: variables) ?? 0)"),
 "itemsNotBarred": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "contains { $0.noItems == true }", "contains { $0.noItems == true && false }"),
 "effectLastsAfterLooting": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "            guard case .character(let id) = pieceID, !boardState.goalLooters.contains(id) else { return false }", "            guard case .character = pieceID else { return false }"),
 "waterSparesThePoisoned": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        case .character, .summon: return isConditionActive(.poison, on: pieceID)", "        case .character, .summon: return false && isConditionActive(.poison, on: pieceID)"),
 "waterHarmlessAtTurnEnd": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        return ScenarioExpression.integerValue(formula, variables: variables).flatMap { $0 > 0 ? $0 : nil }", "        return ScenarioExpression.integerValue(formula, variables: variables).flatMap { $0 > 9999 ? $0 : nil }"),
 "cleansedNotShielded": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        return cleansing.shield\n", "        return 0 * cleansing.shield\n"),
 "cleansedStillPoisoned": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        return boardState.cleansed.contains(id)\n    }\n\n    // MARK: - Those that can't be damaged", "        return false && boardState.cleansed.contains(id)\n    }\n\n    // MARK: - Those that can't be damaged"),
 "undamageableDamaged": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "        return scenarioData?.placements?.undamageable?.contains(name) == true", "        return false && scenarioData?.placements?.undamageable?.contains(name) == true"),
 "noReprieve": ("GlavenGame/Board/BoardCoordinator+Effects.swift", "reprieve.killed.contains(name) else { return }", "reprieve.killed.contains(name), false else { return }"),
 "inactiveCanBeAttacked": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "        return MonsterAI.inactiveMonsters(game).contains(name)\n    }", "        return false && MonsterAI.inactiveMonsters(game).contains(name)\n    }"),
 "shelteredCanBeAttacked": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "        if objectiveContainer(of: pieceID)?.isSheltered == true || isInactive(pieceID) { return true }", "        if isInactive(pieceID) { return true }"),
 "inactiveMonstersAct": ("GlavenGame/Engine/MonsterAI.swift", "              written.inactive != nil else { return [] }", "              written.inactive != nil, false else { return [] }"),
 "apartSideIsMonsters": ("GlavenGame/Engine/MonsterAI.swift", "        monster.isAlly ? .party : monster.standsApart ? .apart : .monsters", "        monster.isAlly ? .party : .monsters"),
 "focusFirstIgnored": ("GlavenGame/Engine/MonsterAI.swift", "        return candidates.filter(isFirst) + candidates.filter { !isFirst($0) }", "        return candidates.filter { _ in _ = isFirst; return true }"),
 "cycleStandsStill": ("GlavenGame/Board/BoardCoordinator+Bosses.swift", "            boardState.cycleSteps[name] = step + offset + 1\n", "            boardState.cycleSteps[name] = step + offset\n"),
 "bossStaysAfterMelee": ("GlavenGame/Board/BoardCoordinator+Bosses.swift", "        log(\"\\(self.name(pieceID)) vanishes\", category: .move)\n        removePieceFromBoard(pieceID)", "        log(\"\\(self.name(pieceID)) vanishes\", category: .move)"),
 "bossNeverAppears": ("GlavenGame/Board/BoardCoordinator+Bosses.swift", "        guard case .monster(let name, let standee) = pieceID, comesAndGoes(name),", "        guard case .monster(let name, let standee) = pieceID, comesAndGoes(name), false,"),
 "commanderDoorsStayShut": ("GlavenGame/Board/BoardCoordinator+Bosses.swift", "        if !door.isOpen { openDoor(at: door.coord) }\n        guard isOnBoard(pieceID) else { return true }", "        guard isOnBoard(pieceID) else { return true }"),
 "eggsNeverHatch": ("GlavenGame/Board/BoardCoordinator+Bosses.swift", "        for egg in eggs {\n            guard let hex = boardState.piecePositions[egg] else { continue }\n            (entity(for: egg) as? GameObjectiveEntity)?.dead = true", "        for egg in eggs.prefix(0) {\n            guard let hex = boardState.piecePositions[egg] else { continue }\n            (entity(for: egg) as? GameObjectiveEntity)?.dead = true"),
 "marchersStandStill": ("GlavenGame/Board/BoardCoordinator+March.swift", "        var budget = march.move\n", "        var budget = 0 * march.move\n"),
 "keysNeverTurn": ("GlavenGame/Board/BoardCoordinator+Locks.swift", "            if keyTurned(lock, turnEnded: turnEnded, roundEnded: roundEnded) { boardState.releasedLocks.insert(index) }", "            if false, keyTurned(lock, turnEnded: turnEnded, roundEnded: roundEnded) { boardState.releasedLocks.insert(index) }"),
 "heldDoorsStayOpen": ("GlavenGame/Board/BoardCoordinator+Locks.swift", "                } else if !held, door.isOpen, !boardState.shutDoors.contains(door.coord) {", "                } else if false, !held, door.isOpen, !boardState.shutDoors.contains(door.coord) {"),
 "lockedDoorsWalkable": ("GlavenGame/Engine/Pathfinder.swift", "            self.closedDoors = canOpenDoors ? (opensLockedDoors ? [] : closed.intersection(board.lockedDoors)) : closed", "            self.closedDoors = canOpenDoors ? [] : closed"),
 "heldMonstersSetUpWithTheRoom": ("GlavenGame/Managers/ScenarioManager.swift", "        setUpMonsters(of: room, playerCount: playerCount, edition: edition) { !held.contains($0) }", "        setUpMonsters(of: room, playerCount: playerCount, edition: edition) { _ in _ = held; return true }"),
 "risenFromTheDestroyedStayDown": ("GlavenGame/Board/BoardCoordinator+Rules.swift", "            if let stood, let index, let risen = scenarioData?.placements?.whenDestroyed?[String(index)],", "            if false, let stood, let index, let risen = scenarioData?.placements?.whenDestroyed?[String(index)],"),
 "scenarioSpecialsIgnored": ("GlavenGame/Board/MonsterTurnController.swift", "                guard let special = coordinator.scenarioData?.placements?.specials?[monster.name] ?? stat?.special,", "                guard let special = stat?.special,"),
}
M.update(S)
def run(name, flt=None):
    path,old,new=M[name]
    full=os.path.join(WT,path)
    if subprocess.run(["git","-C",WT,"status","--porcelain","--",path],capture_output=True,text=True).stdout.strip():
        print(f"MUTATION {name}: {path} has uncommitted changes; commit or stash them first"); return 2
    src=open(full).read()
    if src.count(old)!=1:
        print(f"MUTATION {name}: pattern found {src.count(old)} times in {path}"); return 2
    open(full,"w").write(src.replace(old,new))
    try:
        log=os.path.join(SCR,f"{name}.log")
        p=subprocess.Popen(["swift","test","--filter",flt or (SCENARIO_FILTER if name in S else FILTER)],cwd=WT,stdout=open(log,"w"),stderr=subprocess.STDOUT)
        try: p.wait(timeout=600)
        except subprocess.TimeoutExpired:
            # A hung test (a prompt nobody answers) is the mutation showing, but not a failure.
            p.kill(); subprocess.run(["pkill","-f",os.path.join(WT,".build")]); print(f"MUTATION {name}: TIMEOUT (see {log})"); return 1
        out=open(log).read()
        if "error:" in out and "Test Case" not in out:
            print(f"MUTATION {name}: BUILD FAILED"); print("\n".join(l for l in out.splitlines() if "error:" in l)[:800]); return 2
        failed=sorted(set(re.findall(r"Test Case '-\[GlavenGameTests\.(\w+ \w+)\]' failed", out)))
        total=re.findall(r"Executed (\d+) tests?, with (?:\d+ tests? skipped and )?(\d+) failures?", out)
        print(f"MUTATION {name}: {len(failed)} test(s) failed" + (f" of {total[-1][0]}" if total else " (no summary: crash?)"))
        for f in failed[:14]: print("   ", f.replace(" ", "."))
        return 0 if failed else 1
    finally:
        subprocess.run(["git","-C",WT,"checkout","--",path],check=True)

if len(sys.argv)<2 or sys.argv[1]=="--list":
    for name,(path,_,_) in M.items(): print(f"{name:32} {path}")
elif sys.argv[1] in ("--all","--scenario"):
    missed=[name for name in (S if sys.argv[1]=="--scenario" else M) if run(name)==1]
    print("NOT CAUGHT:", ", ".join(missed) or "none")
else:
    sys.exit(run(sys.argv[1], sys.argv[2] if len(sys.argv)>2 else None))
