#!/usr/bin/env python3
"""Mutation checks for the rule tests: break one rule in the game code, run the rule tests, and
say which tests noticed. A mutation no test fails for is a rule without a test.

    scripts/mutate.py --list            the mutations
    scripts/mutate.py <name> [filter]   apply one, run the tests (optionally only `filter`), restore
    scripts/mutate.py --all             every mutation in turn (slow: a build and a test run each)

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
        p=subprocess.Popen(["swift","test","--filter",flt or FILTER],cwd=WT,stdout=open(log,"w"),stderr=subprocess.STDOUT)
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
elif sys.argv[1]=="--all":
    missed=[name for name in M if run(name)==1]
    print("NOT CAUGHT:", ", ".join(missed) or "none")
else:
    sys.exit(run(sys.argv[1], sys.argv[2] if len(sys.argv)>2 else None))
