# Gloomhaven rules audit — what the game does against the rulebook

An audit of the game against the rules in [gh-rules.md](../rulebook/gh-rules.md) (the first-edition rulebook
and the official FAQ) and the scenario book, begun 2026-10-10 at commit `e19a083`. It was made
three ways: eight read-throughs of the code, one per rule area, each tracing the path real play
takes; two seeded playthroughs read line by line (scenario 1 with four characters, scenario 5 with
three); and the four-seed run of every scenario. File and line references are to `e19a083`.

Each finding has an id, the rule it breaks, what the game did, and its state:

- **fixed** — corrected, with a test that fails without the fix (named in the row);
- **open** — confirmed by reading the code, not yet corrected;
- **question** — the rule itself needs a decision.

About 130 findings. As of 2026-10-10 about 110 are fixed and 6 partly (the turn engine, trap
legends, the campaign, scenario rules, monster turns, rooms with two doors and doors mid-move, the
walls between tiles with range and line of sight, areas, items, bonuses, solo play, round starts
and the maps' monster places) and the rest are open — listed with where to start on each in
`TODO.md` under "Missing Gloomhaven Rules" → "Open, in order". It was merged to `main` on
2026-10-10 (merge `236fb2d`); [../rules-work.md](../rules-work.md) says how to carry on. Scenario-specific rules have their own table in
[../scenario-book/rules-audit.md](../scenario-book/rules-audit.md); the scenario findings here are
the ones the re-audit found wrong or newly missing.

## How to read the areas

| Prefix | Area | Rules in gh-rules.md |
|---|---|---|
| T | Found by reading playthrough transcripts | all |
| A | Attacks, modifiers, line of sight | ATK, LOS |
| B | Conditions, elements, bonuses, summons, items | CND, ELE, ACT |
| C | Movement, traps, doors, loot | MOV |
| D | Monsters | MON |
| E | Setup, the round, turns, ending | SET, RND, TRN, END |
| F | Campaign and town | CMP |
| S1, S2 | Scenarios 1–50, 51–95 | scenario book |

## Player turns: what comes with performing an action

| Id | Rule | What the game did | State |
|---|---|---|---|
| T1 / E1 | TRN-6: XP needs at least one ability of the action performed (FAQ) | A half counted as performed as soon as any step started. Shield Bash's attack with no target still gave 2 XP; an attack by a disarmed character gave its XP; Hook Gun's Loot 2 with nothing to loot gave XP | fixed — `ActionPerformedTests` (`testAnAttackWithNoTargetGivesNoExperienceAndKeepsTheCard`, `testADisarmedCharacterGainsNothingFromAnAttack`, `testALootWithNothingInRangeIsNotPerformed`, `testDisarmingWithNoTrapBesideGivesNoExperience`) |
| T2 | ELE-1: an infusion printed on its own needs an ability performed (FAQ) | Massive Boulder's attack with no target still infused Earth | fixed — `testAStandaloneInfusionNeedsAnAbilityPerformed` |
| T3 | TRN-4: a lost icon costs the card only if an ability of that action was performed (FAQ) | Shield Bash with no target went to the lost pile | fixed — `testAnAttackWithNoTargetGivesNoExperienceAndKeepsTheCard` |
| T4 | TRN-6, ELE-1 | XP and infusions printed in a group beside an ability, or under its text or range, were never granted: Flamethrower (2 XP, Fire), Burning Oil, Icy Blast, Cold Front, Hardened Spikes, Explosive Punch, Rock Slide, Petrify, Clear the Way, Kinetic Assault and others. Element bonuses printed in such groups (Shaping the Ether, Simulacrum, Elemental Aegis) were never offered | fixed — `testGroupedExperienceAndInfusionComeWithTheAttack`, `testEveryPrintedExperienceAndInfusionIsReachable` (every card of every class) |
| E2 | TRN-3: XP is not optional; harm to oneself or allies can't be skipped once the action is performed | "Skip Rest of Half" dropped the action's XP, infusions and "suffer N damage" | fixed — `testSkippingTheRestOfAHalfKeepsItsExperience`, `testHarmToOneselfCannotBeSkippedOncePerforming` |
| — | A skipped target choice | Skipping an attack while choosing its target kept the element it had already infused or paid | fixed — `testSkippingATargetChoiceTakesTheStepBack` |
| — | MOV: "Move 0 is allowed" (FAQ) | Staying put was offered only for moves with text that happens as they end | fixed — `testAMoveMayBeMadeForNoHexes` |
| B1 | ACT-1: the two halves of a card are separate actions | A card in play for one half gave the other half's bonus: Crackling Air's bottom gave "+1 Attack on your next four attacks", Immortality's bottom gave "suffer no damage", Wall of Doom's top gave "+1 Attack this round"; also Master Physician, Fortified Position, Unending Chant | fixed — `testACardInPlayGivesOnlyTheBonusOfItsHalf`, `testEveryBonusCardGivesItsBonusForOneHalfOnly` |
| E11 | ACT-1 | Crackling Air's bottom went to the active area even when its Fire wasn't consumed | fixed — `testARoundBonusInsideAnUnpaidElementBonusDoesNotKeepTheCardInPlay` |
| T9 / B3 | ACT-4: a summon's card leaves play when the summon dies | The card stayed in the active area for the rest of the scenario (so Reviving Ether couldn't recover it and "cards lost" counts were off) | fixed — `testADeadSummonsCardLeavesTheActiveArea` |
| B4 | ACT-2: a player may end an active bonus at any time | No way to do it | fixed — the party panel lists each character's cards in play with a confirmed "End This Bonus"; `ActionPerformedTests` (`testAPlayerMayEndABonusAndItsCardGoesToItsPile`, `testEndingABonusWithoutTheLostIconDiscardsIt`, `testEndingASummonsCardRemovesTheSummon`, `testABonusEndedMidTurnNoLongerActs`) |
| B11 | ACT-1: "on your next four attacks" marks a charge per attack | Crackling Air and Voice of the Night mark one charge per attack action (a Target 3 attack uses one); Master Physician marks one per figure healed though it says "Heal actions" | fixed — `ChargedBonusTests` (`testCracklingAirMarksAChargeForEachAttack`, `testCracklingAirsLastChargeCoversOneAttackOfTwo`, `testVoiceOfTheNightMarksAChargeForEachAttack`, `testMasterPhysicianMarksAChargeForEachHealAction`). Every other charged bonus was read against its card and counts what it says |
| B13 | ACT-4 | A summon with no empty hex beside the character: the half was still performed and the card went active without a summon | fixed with T1 (the step now counts as not performed) |
| T6 | — | Rest log lines said "takes back N cards" with N the hand size, and "1 cards" | fixed |

## Elements

| Id | Rule | What the game did | State |
|---|---|---|---|
| B2 | ELE-2: an element already strong or waning can be infused and consumed in the same turn, in either order, and ends strong (FAQ) | Infusing a waning element made it unconsumable that turn; infusing a strong one and then consuming it left it inert | fixed — `ElementRuleTests` |
| T7 / B9 / D6 | ELE-4: a monster doesn't consume an element for an ability it doesn't perform (FAQ) | Every consume on the card is paid when the first monster of the type starts, even if none can perform the ability (seen: Night Demons, one disarmed and one dead of its wound, still consumed Dark). Savvas Icestorm's "Air: Push 4 instead" is paid and ignored | fixed — `MonsterTurnRulesTests` (`testADisarmedMonsterConsumesNothingForItsAttack`, `testTheFirstMonsterToAttackConsumesForThoseAfterIt`, `testAnIcestormsAirPushIsFourInstead`) |
| B13 | ELE-2 | A "any element" consume picks the element itself; Crackling Air and Foul Wind consume Air without asking | open — see N7 too. A printed consume can already be declined (`PlayerTurnController.consumeOptions` / `toggleConsume`, shown in `BoardView`); missing are the choice of which element an "any element" consume takes (`GameState.chooseElements` picks, strong first) and declining the consumes active bonuses make by themselves (`consumeForAttack`, `consumeForRange`, `attackBonusOrElement` in the attack step of `PlayerTurnController`). `BoardCoordinator.PendingElementChoice` is an element picker that could be reused |

## Attacks, modifiers, line of sight

| Id | Rule | What the game did | State |
|---|---|---|---|
| A1 | ATK-13: Retaliate is judged after the attack's push or pull (FAQ) | Judged before: pushing a retaliating monster away still cost the attacker; pulling one adjacent cost nothing | fixed — `ForcedMovementTests` (`testRetaliateDoesNotReachAnAttackerWhoPushedTheFigureAway`, `testRetaliateReachesAnAttackerWhoPulledTheFigureAdjacent`, and three more on amount, reach and death) |
| A5 / C4 | ATK-7: a flying figure is pushed over obstacles and springs no trap (FAQ) | Flyers were stopped by obstacles and sprang traps and hazards | fixed — `testAPushedFlyerTouchesNeitherTrapsNorHazardsAndCrossesObstacles` |
| A6 / C5 | ATK-7: a pushed figure passes through its allies but can't stop on a figure (FAQ) | Any figure behind the target blocked the push | fixed — `testAPushGoesThroughTheTargetsAlliesToAFreeHexBeyond`, `testAPushDoesNotGoThroughTheTargetsEnemies` |
| A7 / C6 | ATK-7: a push or pull is optional, all or nothing (FAQ) | The player could not decline | fixed — `testThePlayersOwnPushCanBeDeclined`, `testAPushOnceBegunCannotBeDeclined` |
| A9 | ATK-5: comparing cards with effects (FAQ: "+1 Stun" beats "+1"; "+0 Stun" against "+2" is ambiguous, so the first drawn) | Effects were ignored: Advantage kept a plain +1 over +1 Stun, and always took +2 over +0 Stun. Poison's +1 was counted in the comparison, which the FAQ excludes | fixed — `testAdvantageWeighsACardsEffects` |
| A2 | LOS-1: a sight line that touches a wall's corner or edge is blocked (FAQ) | Only a line passing through or along a wall is blocked; `LineOfSightTests` lines 147 and 167 assert the opposite of the rule | fixed: a touch blocks, the two ends of the line excepted (`LineOfSightTests.testLOS_lineGrazingWallCornerIsBlocked`, `testLOS_singleWallHexHidesTheRowBeyondIt`, `testLOS_alongAWallFromAHexBesideIt`) |
| A3 | LOS-1: closed doors block line of sight | A shut door between two revealed rooms (a pressure-plate door that closed again, split starting rooms) doesn't | fixed (`WallLineTests.testAClosedDoorBlocksLineOfSight`) |
| A4 / C10 | LOS-3: range isn't counted through walls | Range is plain hex distance everywhere (attacks, heals, loot, monster targeting, areas) | fixed: `BoardState.range` counts round walls, closed doors and wall lines, for attacks, heals, loot, monster focus and targeting, areas and Retaliate (`WallLineTests.testRangeIsCountedRoundAWall`, `testThereIsNoLootingAcrossAWallLine`) |
| C2 | MOV-1, LOS-3: the edge of a map tile is a wall, also where two tiles' full hexes meet beside a door (FAQ) | Such hexes are adjacent: figures walk, attack in melee, push and see across the wall line. 60 doors in 42 scenarios (in #1, the hexes either side of door 1); seven more scenarios have tiles abutting with no connector at all (#6, #24, #40, #43, #67, #74, #82) | fixed: `BoardState.wallEdges`, drawn by `BoardBuilder.wallEdges` between full hexes of two tiles; no move, jump, flight, push, melee, loot or adjacency across one (`WallLineTests`, `MapRevealTests.testWallLinesNeverCutOffPartOfAMap`) |
| A8 | ATK-9, ATK-10: an added target is in addition to an area | With Backup Ammunition or Grim Bargain an area attack loses its area; a "+1 Target" modifier card drawn in an area attack gives nothing | fixed: the area is placed as ever and each added target (printed, from an item or from a drawn "+1 Target") is then one more enemy within the attack's range — range 1 for a melee area (`AreaAttackRuleTests.testATargetAddedToAnAreaAttackIsOneMoreEnemyInRange`) |
| A10 | ATK-10: the player places and may mirror an area | The game picks the placement covering most enemies; patterns are never mirrored (one chiral card, Scroll of Blizzards) | partly: patterns are tried in their mirror image too, for characters and monsters, and the in-range hex of a ranged area may be empty but not a wall (`AreaAttackRuleTests`). Still open: the player taps one enemy and the game picks the placement that covers it and the most others, rather than letting the player place the area |
| A11 | RND-9 | A deck that runs out and reshuffles mid-round forgets the ×2 or Null drawn earlier, so it isn't reshuffled at the end of the round | fixed — `ModifierDeckRoundEndTests.testADeckThatRanOutMidRoundIsStillShuffledAtTheEndOfTheRound` |
| A12 | ATK-7 | "Further" and "closer" are plain distance, not counted around walls | open (low) |
| T11 | — | The turn log doesn't say when an attack had Advantage or Disadvantage, so a transcript can't be checked for it | fixed — the log line reads "attacks … with advantage / with disadvantage" |

## Movement, traps, doors, loot

| Id | Rule | What the game did | State |
|---|---|---|---|
| C1 | MOV-5: a trap does what the scenario's legend says | Effects come from the tile art in the map data (spike / bear / poison), always with 2+L damage. #2's two Stun traps deal damage and Immobilize; #31's Curse traps only damage; #44's Immobilize-and-Poison traps deal damage; about two thirds of the 75 scenarios with traps differ. A Stun trap should also end the move | fixed — `placements/gh-traps.json` holds all 75 legends; `TrapConditionTests` (traps sprung on the real boards of #1, #2, #15, #31, #44), `TrapLegendTests` |
| C3 | MOV-8: a character who opens a door keeps the rest of the move | The move ends on the door hex (the room beyond doesn't exist until revealed, and the leftover movement isn't offered) | fixed (`DoorRuleTests`) |
| — | MOV-8: a closed door is a wall to monsters | Parasitic Influence could walk an enemy onto a closed door without opening it (found by a playthrough once the fixes above changed its course) | fixed — `testAnEnemyMovedByACardCannotEnterAClosedDoor` |
| C8 | ATK-11: allied monsters drop no money (FAQ) | They do (#11, #12, #35, #36, #91). Bosses drop none, which no rule says | fixed — `MoneyTokenTests` (`testAnAlliedMonsterDropsNoMoneyToken`, `testABossDropsAMoneyToken`: neither the rulebook nor the FAQ sets bosses apart, so one set up with its room drops a token) |
| C9 | MOV-7: obstacles may not be placed to cut the map in two | No check | fixed: `BoardState.obstacleWouldDivideMap` (`ObstaclePlacementRuleTests`) |
| C11 | MOV-10 | A numbered treasure already looted in the campaign is still drawn on a replay (it gives nothing) | open (low) |
| D9 | MON-3: a jump's last hex is a normal move | A jumping monster that can't reach an attack hex this turn may end on a trap | fixed (`MonsterAIMovementTests.testAJumpingMonsterDoesNotComeDownOnATrapOnItsWay`) |

## Monsters

| Id | Rule | What the game did | State |
|---|---|---|---|
| T5 / E6 / C7 | SET-2: standees are placed at random | Always the lowest free number, elites first — so within a type the same monster always acted first | fixed — `SetupRulesTests` (and a reused standee no longer keeps a dead elite's mark) |
| D1 | MON-8: an ability card's Shield and Retaliate start when the monster acts, and a stunned monster doesn't gain them (FAQ) | On for every monster of the type from the moment the card is drawn, stunned or not, and for monsters summoned that round | fixed — `testAGuardsCardShieldStartsWithItsTurnAndLastsTheRound`, `testAStunnedMonsterKeepsOnlyItsStatCardsShield`, `testAMonsterSummonedThisRoundHasNoCardShield` |
| D2 | MON-1 | Wind Demon card 648 never attacks (its attack is inside a group the executor doesn't open), though it consumes Air | fixed — `testAWindDemonAttacksWithTheCardThatPrintsItsAttackInAGrid`; `MonsterDataTests.testEveryMonsterCardActionIsOneTheTurnPerforms` checks every card |
| D3 | MON-9 | Heals that affect several figures heal one: Shaman/Necromancer "all adjacent allies", Captain of the Guard "self and all allies", Sun Demon with Light, Savvas Lavaflow with Earth | fixed — `testAShamansHealReachesEveryAdjacentAlly`, `testTheCaptainsHealReachesHimselfAndEveryAlly`, `testASunDemonsLightHealReachesEveryAllyInRange`, `testALavaflowsEarthHealReachesThree` |
| D4 | MON-5: a disarmed monster moves as if for a melee attack (FAQ) | It still positions for its ranged attack | fixed — `testADisarmedArcherClosesInOnItsFocus`, `testADisarmedRangedSummonClosesInOnItsFocus` |
| D5 | MON-6: a muddled ranged monster doesn't step back from its focus (FAQ) | It does | fixed — `testAMuddledArcherDoesNotStepAwayFromItsFocus` |
| D7 | MON-8 | Savvas Icestorm's "Shield 1, self and all allies within Range 2" goes to every Icestorm anywhere and no one else | fixed — `testAnIcestormShieldsItselfAndTheAlliesWithinTwo` |
| D8 | MON-1 | Savvas Lavaflow's paid "Wound / Disarm all enemies" reaches adjacent enemies only | fixed — `testALavaflowWoundsAndDisarmsEveryEnemy` |
| D10 | RND-5: one ability deck per deck name — Bandit, City and Inox Guards share the Guard deck and act on one card | Each type draws from its own copy (#62, #67, #75, #78, #87, #88, #92) | fixed — `MonsterDeckRulesTests` (`testGuardsOfTwoTypesActOnOneCardEveryRound` and five more). Taken from the FAQ's entry on types sharing a deck and the single printed Guard deck |
| D11 | MON-6: among attack hexes, least Disadvantage on the additional targets | Not weighed | fixed — `testAShamanAvoidsDisadvantageOnItsSecondTarget` |
| D12 | MON-7 | "One adjacent enemy" abilities (Living Corpse's Muddle and Immobilize) take the first adjacent enemy, not the focus | fixed — `testALivingCorpseGrabsItsFocus` |
| T8 | MON-1 | Night Demon's "All adjacent enemies and allies suffer 1 damage" hurts allies only (the code matches the words in the other order) | fixed — `testANightDemonHurtsEnemiesAndAlliesBesideIt`, `testPrintedDamageHurtsWhomTheWordsName` (every card text with "suffer") |
| S1-3 | MON-11 | The Captain of the Guard's "all allies +1 Attack this round" reaches monsters on the other side and gives the Captain himself +2 | fixed — `testTheCaptainsOrderIsForHisAlliesOnly` |
| D13 | MON-2, MON-9 | Low: focus ties by plain distance; two characters on the same initiative aren't ordered by their second card; monster Loot ignores line of sight | fixed: focus ties count proximity as range, round walls; characters on the same initiative are ordered by their second card (`RoundRuleTests.testInitiativeOrderAndItsTies`); monster Loot needs line of sight |

## Setup, the round, resting, ending

| Id | Rule | What the game did | State |
|---|---|---|---|
| E5 / B5 | RND-4: the long rest is a turn; its Wound damage comes first and can be negated; the Heal 2 is optional (FAQ) | A resting character's Wound damage couldn't be negated and could exhaust them before the heal; the heal was forced | fixed — `RestRuleTests` (`testARestingCharactersWoundCanBeNegatedBeforeTheRestHeals`, `testTheRestsHealMayBeDeclined`, `testPoisonTakesTheRestsHeal`) |
| B6 | ACT-8: an item with uses left isn't spent, and a rest doesn't give its uses back (FAQ) | A long rest reset partly used items (Hide Armor) | fixed — uses kept through a rest (`testALongRestLosesOneDiscardTakesBackTheRestHealsTwoAndRefreshesSpentItems`); the six armours with use circles (Hide Armor, Chainmail, Splintmail, Platemail, Swordedge Armor, Steam Armor) are used whenever an attack would damage, unasked and in headless play too — `ItemUseRuleTests` (`testAnArmourWithUseCirclesIsUsedWithoutAsking`, `testWhichArmoursWorkByThemselves`, `testAnAttackThatDoesNoDamageMarksNoCircle`, `testLosingACardInsteadLeavesTheArmourUnused`) |
| B8 | TRN-7: items may be used on a long-rest turn (FAQ) | Not possible; "start/end of your next turns" bonuses (Lumbering Bash, Auto Turret) also do nothing on a rest turn | fixed — items are offered on the rest panel (`testItemsCanBeUsedOnALongRestTurnUnlessStunned`); start-of-turn bonuses act before the rest's card is chosen and end-of-turn ones before the turn ends, a charge each (`testAStartOfTurnBonusActsOnARestTurn`, `testAStartOfTurnBonusOnARestTurnMayBeSkipped`, `testAnEndOfTurnBonusActsOnARestTurn`) |
| E13 | — | A turn spent stunned or resting didn't count for pressure plates, turn-end rules or goals judged as a turn ends | fixed — `testARestTurnEndsWithLooting`; the stunned and resting turn ends share the normal one |
| E3 | RND-3: a short rest may be taken in the scenario's last round (FAQ) | Not offered once the scenario was decided (matters for battle goals); `testNoShortRestOnceTheScenarioIsDecided` asserts the old behaviour | fixed — `testAShortRestIsOfferedInTheScenariosLastRound` |
| E9 | RND-3: the 1 damage for losing a different card can be negated (FAQ) | It couldn't | fixed — `testTheRedrawsDamageCanBeNegated` |
| E10 | RND-6: a long rest goes after a character on initiative 99 (FAQ) | Before | fixed — `testALongRestGoesAfterACharacterOnNinetyNine` |
| E7 | SET-3: solo play raises the monster level and trap damage by 1, not gold or bonus experience (p.15) | Not applied; the setup also offers a "story" difficulty (−2) the rulebook doesn't have | fixed — a "Solo" switch beside the difficulty; `SetupRulesTests` (`testSoloPlayRaisesMonstersAndTrapsButNotGoldOrExperience`, `testSoloPlayNeverGoesAboveLevelSeven`, `testNoDifficultyTakesTheLevelBelowZero`, `testTheSetupScreenSaysWhatSoloPlayDoes`). "Story" stays as the game's own setting; no difficulty takes the level below 0 |
| E12 / S1-5 | — | A character who escapes through the exit is recorded as exhausted (personal quests, Protector, Streamliner) | fixed — `ScenarioReauditTests.testLeavingThroughTheExitIsNotExhaustion` |
| B7 | CND-4: a stunned character uses no items | Defence items, Boots of Speed, Dampening Ring and Heart of the Betrayer are still offered | fixed — `ItemUseRuleTests` (`testAStunnedCharacterIsOfferedNoShieldButKeepsTheirArmour`, `testAStunnedCharacterIsOfferedNoItemOutsideTheirTurn`, `testAStunnedCharacterMakesNoAttackBack`). Passive items and armours with use circles still work (FAQ: Stun doesn't affect persistent effects or passive items) |
| B10 | TRN-7: items at any time in the turn | Not once both halves are done, before End Turn | fixed — "turn" items stay usable until the turn is ended |
| B12 | ATK-14: any damage may be negated by losing cards | Not for item costs, the Berserker's "suffer up to N", a printed "suffer damage" step, or a door shutting on a figure; never where a bonus would negate the damage anyway | fixed — `ItemUseRuleTests` (`testAnItemsDamageCanBeNegated`, `testTheBerserkersChosenDamageCanBeNegatedAndThenCountsForNothing`, `testAPrintedSufferDamageCanBeNegated`, `testCardsMayBeLostBeforeANegatingChargeIsSpent`: the choice is offered, and left alone the charge takes it) |
| S-gen | RND-11 | "Start of round" scenario rules run after cards are chosen (#5's Disarm, #48's Muddle, #31/#39's elements) | fixed — applied as card selection begins, monster cards still drawn after it; `ScenarioEnforcedRuleTests` (`testCharactersAreDisarmedWhileTheFirstCardsAreChosen`, `testTheRoundsElementsAreSetBeforeCardsAreChosen`) |

## Campaign and town

| Id | Rule | What the game did | State |
|---|---|---|---|
| F1 | CMP-9 | #51 The Void can never be played: it needs "End of Corruption" three times, and the count is lost | fixed — `CampaignRulesTests.testTheVoidOpensAfterThreeEndsOfCorruption` |
| F2 | CMP-7 | The five personal-quest scenario chains (#52, #55, #57, #59, #61) never unlock; quest 510 would complete after #52 alone | fixed — `testAQuestUnlocksItsScenarioAndEndsWithTheChain`, `testEveryQuestChainEndsWhereTheStoryDoes` |
| F3 | CMP-9 | A met requirement is treated as an unlock, so scenarios open early (#20 after #8, #28 after #6, #35/#36 after #10, and more) | fixed — `testPrerequisitesAloneOpenNothing`, `testWinningAPrerequisiteDoesntPutAScenarioOnTheMap` |
| F4 | CMP-9 | #92 can never be played (achievement id misspelt); two more misspelt ids in #36 and #50 | fixed — `testEveryAchievementAScenarioNamesCanBeEarned`, `testRefusingTheDebtCollectorsOpensTheBackAlleyBrawl` |
| F5 | CMP-9 | Achievements of one type don't replace each other (City Rule, Artifact, The Drake); the starting City Rule: Militaristic is never set | fixed — `testANewAchievementOfATypeReplacesTheOld` (City Rule and Artifact are the typed ones) |
| F6 | CMP-6 | Six enhancement prices are second-edition values (+1 Target, Jump, Immobilize, Curse, Strengthen, Bless); Regenerate is sold | fixed — `EnhancementTests.testEveryPriceOnTheEnhancerChart` |
| F7 | CMP-6 | The +75 for an earlier sticker counts the whole card, not the same action | fixed — `testEarlierEnhancementsCountOnTheSameActionOnly` |
| F8 | CMP-6 | Elements can't go on attack slots; Jump can never be bought; summon enhancements are missing | partly fixed — elements on attack slots, Jump on every Move, a second condition on lines that reach everyone they name (`testJumpIsSoldOnEveryMoveAndNothingFromFrosthaven`, `testAConditionLineTakesAnotherCondition`); summon stat enhancements and single-target condition lines are still not sold |
| F9 | CMP-6 | No limit on enhanced cards by prosperity | fixed — `testEnhancedCardsAreLimitedByProsperity` |
| F10 | CMP-6 | Enhancements belong to the character, not the class's cards | fixed — `testANewCharacterOfTheClassKeepsItsEnhancements` |
| F11 | CMP-7 | No extra perk after a retirement; an already-unlocked class gives nothing; the retiree's quest is dealt again | fixed — `testOnlyAFulfilledQuestRetires`, `testARetirementGivesTheNextCharacterAnExtraPerk`, `testAnAlreadyUnlockedClassBringsADesignAndAScenario`, `testARetiredCharactersQuestIsNeverDealtAgain` |
| F12 | CMP-2 | A sold unique item is gone for good; a duplicate from a treasure pays nothing | fixed — `testAUniqueItemSoldBackIsInTheShop`, `testADuplicateTreasureItemPaysItsSalePrice` |
| F13 | CMP-8 | City event 15, option B does nothing | fixed — `EventCardTests.testDisposingOfTheBodiesCostsGoldOrACheckmark` |
| F14 | END-4, CMP-4 | Losing checkmarks or prosperity can cross a perk or prosperity threshold | fixed — `testLosingACheckmarkStopsAtAPerkEarned`, `testLosingProsperityStopsAtTheLevelReached` |
| F15 | CMP-3 | Two pending level-up choices can both take the top level | fixed — `CardPoolTests.testAHigherLevelRecruitChoosesALevelAtATime` |
| F16 | MOV-10 | Treasure 49 (unlock #17) does nothing | fixed — `testATreasureMapUnlocksItsScenario` |
| E4 / F17 | END-3 | Purist is judged from item state a long rest clears | fixed — `BoardItemTests.testAnItemUsedBeforeALongRestStillBreaksPurist` |
| E8 / F23 | SET-6 | The "ignore negative item effects" perk also cancels Second Skin | fixed — `AttackModifierRulesTests.testSecondSkinStillWorksWithThePerk` |
| F18 | CMP-1 | Reputation milestones (+10, −10) unlock nothing | fixed — +10 and −10 open the Sunkeeper and the Nightshroud, ±20 add their events (rulebook p.49); `testReputationStopsAtTwentyAndBringsItsEvents` |
| F19 | CMP-8 | The party always returns to town: a linked scenario or an immediate retry still draws a road event; the city event is forced | open |
| F20 | CMP-8 | Collective results aren't the players' to split | open |
| F21 | CMP-7 | Quest 514 counts the character's own exhaustion (FAQ: only others'); 519 counts checkmarks that aren't battle goals; 532 counts retirements before the character joined | fixed — `testAStudyOfAnatomyCountsOnlyTheOthers`, `testBattleLegendCountsOnlyBattleGoals`, `testAHelpingHandCountsRetirementsWhileInTheParty` |
| F22 | — | The character sheet lets checkmarks and perks be changed freely | fixed — checkmarks are display-only, a perk once taken stays, recruits are held to the prosperity level |

## Scenarios (found wrong by the re-audit)

| Id | Scenario | What the game did | State |
|---|---|---|---|
| S1-1 | #41 | Can be won after a loss: an exhaustion after another character has left through the exit turns into a victory | fixed — `ScenarioReauditTests.testTheTombIsLostByExhaustionAfterAnotherHasLeft` |
| S1-2 | #2 | The treasure room and the room opposite have each other's monsters (room refs swapped in the data) — to verify against the book | fixed (the scenario data was wrong; book p.4) — `testTheBarrowsSideRoomsHoldWhatTheBookPrints` |
| S1-4 | #42 | Chord 4's damage lands at the end of a character's turn, not the start | fixed — `testTheFourthChordHurtsAsTheTurnStarts` |
| S2-1 | #83 | The first set of special rules keeps firing after Section 2 replaces it | fixed — `testTheAltarsFirstRulesEndWithTheCultists` |
| S2-2 | #70 | Wound still damages the Living Spirits, which "cannot be damaged in any way" | fixed — `testAWoundDoesNotHurtALivingSpirit` |
| S2-3 | #58 | The bone piles heal the Harvester in one heal, so Poison cancels all of it (FAQ: each pile is its own heal) | fixed — `testEachBonePileHealsTheHarvesterOnItsOwn` |
| S2-4 | #81 | The Colorless's special 2 never gains its Shield 1 | fixed — `testABossSpecialsShieldIsGainedWhenItIsPerformed` |
| S2-5 | #92 | The city's men appear beside a bandit, not behind the party, and as spawned (no money) | fixed (book p.115) — `testTheCitysMenAreSetUpBehindTheParty` |
| S2-6 | #82 | The chest's items are kept after a lost attempt; the conclusion's rewards are never applied | fixed — `testSacrificingOnTheMountainIsConclusionA`, `testEscapingTheMountainIsConclusionB`, `testTheMountainsChestIsResetOnALoss`. Who holds the artifacts still isn't tracked (holder exhausted should lose) |
| S2-9 | #25, #33, #37, #60, #71 | The last character exhausted on an exit hex, with the others exhausted on exits, should win (FAQ); it is an all-exhausted defeat | fixed — `testAnEscapeIsCompleteWithEveryoneExhaustedOnTheExit` |
| — | #27 | Hail takes no turn, so her Wound never hurts her (FAQ: initiative 99) | fixed — `testHailsWoundHurtsHerOnHerTurn` |
| — | #34, #35, #36, #39, #51, #73 | Obstacles the scenario says can't be destroyed can be | fixed — `testWhatTheScenarioSaysCantBeDestroyedIsnt`, `testNoAbilityDestroysADarkPit` |
| — | #35 | The City Archers are set up beside the party instead of on the battlements | fixed: the tiles behind the gate are laid out from the start (`laidOut`), the archers of (a) and (b) stand on the battlements and shoot over the wall sections, and the rest are set up when the gate is destroyed or a character or ally gets over the wall (`BattlementsTests`) |
| — | #49, #78 | Missing immunity to forced movement (Siege Cannon, Cultists (b)) | fixed — `testTheCarriersAndTheCannonCantBeForcedToMove` |
| — | #66, #69, #76, #85, #88, #90, #95 | Smaller printed rules not enforced (door 1's timing, entering a hex beside the well, discarding three cards, Sun-Blessed, −1 Move, the Night Demon, boulders with hit points) | fixed for #66, #69, #85, #88, #90 (`ScenarioReauditTests`); open for #76 (discarding three cards) and #95 (boulders with hit points) |

Scenario rules still not built are listed, by the kind of work they need, in
[../scenario-book/rules-audit.md](../scenario-book/rules-audit.md) ("What is still open") and as
tasks in `TODO.md` ("Open, in order", group 2).

## Found while fixing

| Id | Rule | What the game does | State |
|---|---|---|---|
| N1 | MOV-9 | A room with two doors can be revealed empty: the map data holds a copy of the tile for each door and only one copy has the overlays, monsters and onward doors. Entered by the other door, the room has no traps, treasure or monsters (#7's F1b from D2b; #53's J2a). Maps affected: #6, #7, #15, #21, #24, #32, #43, #53, #76, #78, #82, #84, #94 | fixed (`MapRevealTests.testARoomIsTheSameWhicheverDoorItIsEnteredBy`, `testOpeningEveryDoorRevealsEverythingOnTheMap`) |
| N2 | SET-1 | The map data's monster places disagreed with the scenario data in 22 rooms (a missing place, a wrong rank for a party size, a place under another monster's name, two on one hex): #3 B1a, #6 M1a, #10 L1b/L3a, #11 L2b, #12 H1b, #17 B4a, #26 C1a, #31 L2a, #44 M1b, #71 L3a, #75 L3a, #76 G2a, #78 M1a, #81 D1a, #82 C1a/I1b, #87 L2a, #88 D2b/N1a, #89 I2b; in #85 it was the scenario data that lacked three four-character demons the book prints. A monster with no place of its own was put on a fallback hex | fixed against the scenario book, room by room (`MapMonsterPlaceTests`: every monster of every room has its own place of the right rank for 2, 3 and 4 characters, and no two places share a hex) |
| N3 | CMP-9 | Nothing in the data unlocks #72, #73, #76 or #77 (pinned by `testEveryScenarioCanBeUnlocked`) | question |
| N4 | CMP-6 | The doubling for several targets was also charged for an element and for a +1 on a Target line, which the rulebook excepts (with area hexes); the FAQ's single-target cases (targets gained only by consuming an element, an ability that summons several) were already priced single | fixed (`EnhancementTests.testOneMoreTargetAndElementsAreNeverDoubled`, `testTargetsGainedByConsumingAnElementDontDouble`) |
| N5 | — | Inferno (Spellweaver 9): "Target all enemies in the same room as you" attacked one adjacent enemy, and "All allies in the same room as you suffer 2 damage" did nothing | fixed: a room is what walls and doorways bound (`BoardState.room`); every enemy in it in line of sight is attacked, in melee, and the allies in it suffer the damage (`InfernoTests`) |
| N6 | CMP-8 | Travelling on without returning to Gloomhaven, a linked scenario or a retry skipping the road event, and the city event being optional all need town-screen changes (F19) | open |
| N7 | ELE-2 | Crackling Air's Air is consumed (without asking) at each Attack action that finds it; the FAQ has it consumed once, as the card is played, with a token on the card to remember the +2 for all four attacks | open |
| N8 | ATK-14 | A card in the active area can't be lost to negate damage (FAQ: it can, as if discarded or lost already) | open |
| N9 | ATK-14 | Warding Strength's and Cold Front's charges are marked before the lose-a-card choice is offered (the armours with use circles and the "suffer no damage" bonuses now leave the choice first) | open (low) |
| N10 | TRN-7 | The single-use shields are offered after the armours with use circles have applied; the FAQ lets the player choose which Shield to use first | open (low) |
| N11 | SET-1 | When a monster type runs out of standees as a room is set up, `placeRevealedMonsters` fills the places in map order; the rulebook sets up those nearest the revealing character first (seen in #85 with four characters: eight Sun Demons for six standees) | open |
| N12 | MON-7 | In #9 (seeds 2 and 3 of the veteran playthrough) the ledger reports a character "attacked 2 times by one attack ability" by a Vermling Scout in the round the Merciless Overseer has its scouts act again. Either the ledger miscounts the extra turn (it tries to allow for it) or a scout attacks twice in one turn: not yet looked into | open |
| N13 | ACT-1 | Read in passing by the bonuses pass, not verified: Unending Chant doubles only Curses applied by attacks, not by other abilities; Potent Potables and Angelic Ascension may mark their charge as the step starts even if the action then finds no target; Frost Armor's "suffer no damage instead" is read as a printed self-damage step of 0 | fixed 2026-10-12 — all three bonuses were wrong as suspected (and Backup Ammunition and Grim Bargain's doubling with them): a Curse from any ability is doubled (`BoardCoordinator.applyCondition(_:to:by:)`), and a bonus counted in Attack or Heal actions marks its charge once the action is performed. `ChargedBonusTests` (`testUnendingChantDoublesACurseThatIsNoAttack`, `testAnAttackActionWithNoTargetMarksNoCharge`, `testAHealActionWithNoOneToHealMarksNoCharge`); mutations `curseDoubledOnlyByAttacks`, `curseNeverDoubled`, `attackChargeBeforeTheTarget`, `rangedChargeBeforeTheTarget`, `actionChargesNeverMarked`, `healChargeBeforeTheTarget`. Frost Armor's text does go to the printed-damage step with an amount of 0, where nothing happens: left alone |
| N14 | CND-5 | A Cultist's attack as it dies reached an invisible character (found by the veteran playthroughs) | fixed (`ConditionRuleTests.testADyingCultistsAttackDoesNotReachAnInvisibleCharacter`) |
| N15 | LOS-2 | Impaling Eruption attacked an enemy on the way to its target without line of sight to it (found by the all-scenarios run once a wall's corner blocks sight) | fixed (the all-scenarios playthrough, #57 seed 4) |
| N16 | — | Interface added for these rules and not yet looked at on a device or in a rendered screen: the Solo switch on the setup screen, the rows of cards in play with "End This Bonus" in the party panel (28-point rows: check the tap size), the damage sheet's "Let <card> take it" line, the long-rest sheet's heal toggle and items, the wall lines drawn between tiles | open (review) |
| N17 | ATK-6 | A Push or Pull printed as its own ability (performed after the attack, `PlayerTurnController` → `beginStandalonePushPull` → `beginPushPull`) makes none of the checks `performPushPull` makes: the target's push/pull immunity (#47 the Sightless Eye, #34 the Elder Drake, #49 the Siege Cannon, #78's Cultists), an objective on the map, Heavy Greaves. Found on 2026-10-10 by reading, while the scenario rule table was re-checked | fixed 2026-10-12 — reproduced with the one card that takes that path, Scroll of Recall ("Pull 1, Range 3, Target 3", its range line an action of its own in the data): the Pull did nothing, or after an attack pulled that attack's target from anywhere. The range line is attached to its Pull (`attachingForcedMoveRange`), a chosen Push or Pull takes as many targets as printed, each through `performPushPull`, and `beginStandalonePushPull` is removed. `ForcedMovementTests.testAPullWithItsOwnRangeAndTargetsPullsEachEnemyChosen`; mutations `pullTakesOneTargetOnly`, `rangeLineLeftOnItsOwn`, `forcedMoveIgnoresImmunity` |
| N18 | ACT | Found 2026-10-12 by playing the cards on a test board: an ability the data nests inside a Move (Tuning the Outcome's "Curse, Range 3", Power Ballad's Strengthen, Warding Dagger's and Crushing Hammer's Shield, Forceful Swipe's and Lash Out's Push, Maul, Natural Remedy, Unending Chant's bottom) is never performed — only the Move is. Singing Arrow's Curse ignores its three-hex area | open (`TODO.md`, Cards) |
| N19 | — | Found 2026-10-12 by the veteran playthrough: #36 stalls in round 8 in the middle of a monster's turn (seed 1, both veteran parties) and the scenario never ends. Present on `main` at `aec9e30`, so not from the fixes of that day | open (`TODO.md`, group 1) |

## Tests that don't prove what they say

The tests found weak by the audit, and what became of each (2026-10-10, test-suite pass; only
`Tests/` changed). "Board" means through `BoardCoordinator` — `performAttack`, `applyCondition`,
the turn controllers, a real turn.

| What was wrong | Where | Now |
|---|---|---|
| Asserted `AttackResult.appliedConditions`, which `performAttack` never reads | `RulebookTests` `testPipeline_missStillAppliesConditions`, `…killedTargetGetsNoConditions`, `…hitAppliesConditions` | deleted — `AttackRuleTests.testAnAttacksConditionsAndPushLandOnANullDraw`, `testAnAttackStoppedByShieldStillAppliesItsEffects`, `testAnAttackThatKillsItsTargetAppliesNoneOfItsEffects` (board) |
| Asserted `AttackResult.retaliateDamage`, never read | `RulebookTests` `testRetaliate_*` (3), `E2EGameTests` `testCombatResolver_retaliateApplied`, `…OutOfRange` | deleted — `ForcedMovementTests` (amount, reach, death, push, pull) and `AttackRuleTests.testRetaliateDrawsNoCardAndIgnoresShieldAndPoison` |
| Passed the flag they asserted | `RulebookTests` `testPoison_plusOneToAttack`, `testStrengthen_givesAdvantage`, `testMuddle_givesDisadvantage`, `testRangedAdjacent_givesDisadvantage`; `CoverageGapTests` `AdvantageDisadvantageThroughAITests` (4) | deleted — `ConditionRuleTests.testStrengthenGivesAdvantageMuddleDisadvantageAndBothCancel`, `AttackRuleTests.testARangedAttackOnAnAdjacentEnemyDrawsTwoCardsAndKeepsTheWorse`, `testAnArcherBesideItsTargetShootsWithDisadvantage`, `testPoisonOnTheTargetAddsOneToAnEnemysAttack` (cards counted in a real attack) |
| Called `AttackModifierManager.addBless` / `addCurse`, which the game never calls | `RulebookTests` `testMaxBlessLimit`, `testMaxCurseLimit`, `testBlessCurseRemovedOnShuffle`; `FeatureTests` `AttackModifierLimitTests` (3); `E2EGameTests` `testBlessCurseInteraction` (also `>= 0`) | deleted — `CombatEffectsTests.testBlessAndCurseCardsAreSharedBetweenDecks`, `ConditionRuleTests.testTheTenCursesOfEachSide`, `testACurseGoesIntoTheDeckItsFigureDrawsFrom`, `RoundRuleTests.testBlessAndCurseAreRemovedWhenDrawnAndCauseNoReshuffle`, `testAnUndrawnBlessStaysInTheDeckThroughAReshuffle` |
| Called `ActionsManager.applyInteractiveAction`, which nothing in the game calls | all of `ActionsManagerTests` | file replaced by `HealAndConsumeRuleTests` (a heal card played on a poisoned, wounded ally; a two-element consume through `GameState.consumeElements`); what a heal removes is `ConditionRuleTests.testWhatAHealRemoves` |
| Set a value and asserted it | `RulebookTests` `RB_LootTests` (3), `CoverageGapTests` `EndOfTurnAutoLootTests` (3), `E2EGameTests` `testKillMonster_dropsLoot` | deleted — `LootRuleTests` (end of turn, summons and monsters, a push, Loot X, the level's gold) |
| | `PersistentAbilityTests` `testActiveCardsProperty_existsOnCharacter`, `testActiveCards_canAddAndRemove`, `testAbilityModel_persistentFlag`, `testActiveCards_notCountedAsHandOrDiscard` | deleted — `TurnFlowTests.testAPerformedPersistentHalfStaysActive`, `RoundRuleTests.testACharacterWithOnlyActiveCardsIsExhaustedAtCardSelection` |
| | `FeatureTests` `TeleportTests` (2), `testParseAbilityCard_extractsAoEPattern`; `DynamicObstacleTests.testDynamicTrap_triggersOnEntry` | rewritten through `beginTeleportAction` and `moveAlong`; the AoE one deleted (`MonsterTurnRulesTests`, `AoEResolverTests`) |
| Could pass with nothing checked (`if let`, an empty loop, `>= 0`, `isEmpty ||`) | `CoverageGapTests` `ScenarioFinishEdgeCaseTests` (4, inside `if let scenario`; bonus XP `>=`); `MonsterTrapAvoidanceFallbackTests` (3); `RulebookTests` `testMonsterTrapAvoidance`, `testMonsterTrapsOnlyPath`; `E2EGameTests` `testMonsterAI_movesTowardCharacter`, `testPathfindingAroundObstacles`, `testDrawAllCardsAndShuffle`, `testEscortAI_fullTurn`; `FeatureTests` `testPushCandidates`, `testResolveTargets_*` (2), `testEscortWithMoveAction_movesTowardEnemy`; `PersistentAbilityTests` snapshot tests; `BoardSimulationTests.testScenario1_playsRoundsConsistently` | rewritten: unwrapped, exact outcomes (bonus XP exactly 8 and none for an absent character; the path's hexes; the escort's steps and target; three push hexes, each two away) |
| Named for one thing, tested another | `E2EGameTests` `testInitiativeOrdering_characterBeforeMonster` (no ability card, assertion in `if let`) | deleted — `RoundRuleTests.testInitiativeOrderAndItsTies` (the coordinator's turn order) |
| | `E2EGameTests` `testThreeRoundSimulation` (a hand-rolled loop around `CombatResolver`), `testLineOfSight_blockedByObstacle` (asserted nothing; obstacles don't block), `testDifficultTerrain_costsExtra`, `testFlyingIgnoresTerrainCost` (`count > 0`) | deleted — `BoardSimulationTests` / `PlaythroughTests`, `LineOfSightTests.testLOS_notBlockedByObstacleDirectlyBetween`, `RB_TerrainTests` |
| | `JumpFlyMovementTests` `testJump_ignoresTrapsOnIntermediateHexes`, `testJump_ignoresDifficultTerrainOnIntermediate` (`>=`), `testBeginMoveAction_exists` (compiles) | rewritten in a corridor with exact costs (a jump's last hex in difficult terrain costs 2) and through `beginMoveAction` / `beginJumpMoveAction` / `beginFlyMoveAction` |
| | `FeatureTests` `testGatherEnemies_includesInvisibleForAoE` (the flag is for what blocks a monster's way; an area never targets the invisible) | renamed and extended: `InvisibleEnemiesTests.testGatherEnemies_canIncludeTheInvisibleAsFiguresInTheWay` |
| | `MonsterSummonTests` (data parsing only), `RoomRevealTests` (rendering only) | renamed `MonsterSummonDataTests`, `RoomRevealDrawingTests`; the rules are in `MonsterTurnRulesTests` and the new `RevealRuleTests` |
| | `BoardSimulationTests.testScenario1_toughPartyRevealsRoomsAndWins` (500 hit points, monsters set to 1, cards handed back) | replaced by `testScenario1_veteranPartyRevealsRoomsAndWins`: a party that wins by the rules |
| Weak numbers | `ForcedMovementTests` trap and hazard damage (`< 30`); `RulebookTests.testDefaultDeckSize` (count only) | exact: 3 and 1 at level 1; the twenty cards by type |

Left as they are: `ConditionLifecycleTests`, `RB_ConditionTests` and `E2EConditionLifecycleTests`
drive `EntityManager`'s restore / apply / expire by hand — the calls real turns make, in the
order they make them; the same durations are now also played through real turns
(`ConditionRuleTests`). `PlaybackTests` checks what it says. `LineOfSightTests`' two tests that pinned the
opposite of A2 now assert the rule ("line grazing a wall corner is blocked", "a single wall hex
hides the row beyond it"). The `RulebookTests` pipeline tests call `CombatResolver` with its inputs supplied:
they prove the arithmetic, and `AttackRuleTests` proves the board supplies the right inputs.

**Mutations.** `scripts/mutate.py` breaks one rule at a time in the game code (96 named
mutations: poison adding 0, Retaliate reduced by Shield, no Disadvantage for a ranged attack on an
adjacent enemy, effects on a killed target, a summon drawing from the monster deck, no reshuffle
at the end of the round, a jump landing free on a trap, the gold rate, turn order reversed…), runs
the rule tests and names the tests that noticed; `--all` lists the mutations no test caught. A
mutation nothing catches is a rule without a test: write that test. The full run of 2026-10-10: 32 of the 35 were
noticed by a test; not caught were `lootIgnoresSight`, `revealedWaitForTheirPlace` and
`roomForFourAlways`. All three were closed on 2026-10-12, and each taught something about
mutations: the loot test's hidden token was out of range as well as out of sight (now a token in
range of a Loot 3 and behind a wall hex); the reveal mutation broke a branch that did nothing the
other branch didn't (the code is now one rule, with `revealedActLast` and `revealedMissTheirPlace`
in its place); and the room mutation broke one of twenty copies of the character count (now
`GameState.characterCount`, broken by `exhaustedDontCount`). The fixes of the turn-and-items
batch (C8, E7, E12, B7, B6, B12, B11, B4, B8, start-of-round rules), whose failing-before half had
only been read, have fifteen mutations of their own since the same day; three of their tests
could not see the rule broken and were changed (solo play at a level where its gold differs, the
scenario summary of an escape, a stunned character's offers answered instead of waited on).
The scenario mechanisms have 36 more (`scripts/mutate.py --scenario`: the `when` facts, standing
effects, water, inactive monsters, sides, boss cycles, marching, locks, monsters set up late…),
run against the scenario tests. 96 mutations, each noticed by a test (nine more came with the fixes of N13 and N17).

**The simulator** (`Tests/Support/ScenarioSimulator`, `PlayLedger`, `PlayerPolicies`). It now
also checks, of every playthrough: each attack within its attack's range (read from the card and
stat card, not from the engine's targeting); no enemy attacked twice by one attack ability;
figures acting in initiative order, once a round, a summon before its owner and not in the round
it arrives; a rest only with two discards; cards conserved and none held by the exhausted; gold
gained equal to tokens looted × the level's rate. `PlayLedgerTests` shows each check firing on a
bad event. Line of sight is still judged with the engine's own function; the ledger's own range check is plain hex
distance, beside the simulator's check that range reaches round the walls at all. With `Options.veteranParty` (ninth-level Brute, Sunkeeper and Berserker with their
level-up cards and perks, at scenario level 0 — a level the players may choose, p.15) and
`VeteranPolicy`, playthroughs reach the end: over two seeds of all 94 scenarios this party wins 117 of 188 games (62%) and 52 of the 60 games won by killing every enemy (87%); with a Scoundrel added, 116 of 188 and 47 of 60 (`testVeteranPartiesWinMostScenarios`, `SIM_ALL=1`). The first-level `TacticalPolicy` party still wins none of its 188.
`PlaythroughTests.testTheVeteranPartyWinsSixKindsOfScenario` wins #1, #13 (kill all), #9 (a boss
and a treasure), #94 (enemies and a treasure), #25 (an escape) and #51 (the Gloom) on every test
run (each with a seed the party wins with: about one game in three is lost to the cards). Still never won by a playthrough: scenarios #7, #12, #15, #19, #26, #27, #30, #33, #40, #50, #52, #59, #60, #61, #66, #67, #69, #70, #71, #73, #79, #82, #85, #90, #92 (25 of 94) — mostly goals the policy doesn't play for (a treasure only a Loot action takes, pressure plates, escorts, objectives to protect) and the longest boss fights.

## Rules with no test that would catch a break

Tests added for what the audit listed (rule ids from gh-rules.md), all through real play:

| Rule | Test |
|---|---|
| ATK-1 ranged attack on an adjacent enemy | `AttackRuleTests` `testARangedAttackOnAnAdjacentEnemyDrawsTwoCardsAndKeepsTheWorse`, `testARangedCardPlayedOnAnAdjacentEnemyHasDisadvantage`, `testAnArcherBesideItsTargetShootsWithDisadvantage` |
| ATK-2, ATK-8, ATK-12, CND-2 on the board | `testPoisonOnTheTargetAddsOneToAnEnemysAttack`, `testShieldReducesAnAttackAndSeveralShieldsAdd`, `testPierceIgnoresThatMuchShield`, `testAnAttacksDamageIsNeverBelowZero`, `testPoisonComesBeforeTheCardAndShieldAfterIt` |
| ATK-3, CND-8 no draw, no Shield, no Poison | `testRetaliateDrawsNoCardAndIgnoresShieldAndPoison`, `testTrapsAndHazardsDrawNoCardAndIgnoreShieldAndPoison`, `testAWoundDrawsNoCardAndIgnoresShieldAndPoison` |
| ATK-6 effects on a Null, none on the dead | `testAnAttacksConditionsAndPushLandOnANullDraw`, `testAnAttackStoppedByShieldStillAppliesItsEffects`, `testAnAttackThatKillsItsTargetAppliesNoneOfItsEffects` |
| ATK-10 each target its own draw | `testEachTargetOfAnAreaIsItsOwnAttackWithItsOwnDraw` |
| SET-9, ACT-5, MON-7 whose deck | `testEveryFigureDrawsFromItsOwnSidesDeck` |
| RND-9, RND-10 reshuffles | `RoundRuleTests` `testADeckThatDrewATimesTwoOrANullIsReshuffledAtTheEndOfTheRound`, `testBlessAndCurseAreRemovedWhenDrawnAndCauseNoReshuffle`, `testAnUndrawnBlessStaysInTheDeckThroughAReshuffle` |
| RND-6 order and ties | `testInitiativeOrderAndItsTies` |
| RND-8 summons | `testASummonActsJustBeforeItsOwnerAndNotInTheRoundItArrives`, `testASummonActsBeforeMonstersThatFollowItsOwner` |
| ATK-15, RND-2 exhaustion | `testAnExhaustedCharactersCardsAreAllLostAndTheirSummonsLeave`, `testACharacterWithOnlyActiveCardsIsExhaustedAtCardSelection` |
| CND-1, CND-4 durations (character, monster, summon) | `ConditionRuleTests` `testAConditionGainedOutsideACharactersTurnEndsWithTheirNextTurn`, `…OnACharactersOwnTurnLastsThroughTheirNextTurn`, `testReapplyingAConditionRenewsItsDuration`, `…OutsideAMonstersTurn…`, `…OnAMonstersOwnTurn…`, `…OnASummonsOwnTurn…` |
| CND-4 Stun, Immobilize, Disarm | `testAStunnedCharactersTwoCardsAreDiscardedAndNothingIsPerformed`, `testAnImmobilizedCharacterCannotMoveAndADisarmedOneCannotAttack` |
| CND-5 Invisible, Strengthen | `testAnInvisibleCharacterIsNotAttacked`, `testAnInvisibleMonsterCannotBeTargeted`, `testStrengthenGivesAdvantageMuddleDisadvantageAndBothCancel` |
| CND-2, CND-3 heals; CND-6 Curse | `testWhatAHealRemoves`, `testACurseGoesIntoTheDeckItsFigureDrawsFrom`, `testTheTenCursesOfEachSide` |
| TRN-5, ACT-7, LOS-2 looting | `LootRuleTests` (5) |
| MOV-3, MOV-5, MOV-6, SET-4 traps and hazards | `MovementRuleTests` (5): a jump's last hex, a push, every level |
| MOV-8, MOV-9, SET-1 reveals | `RevealRuleTests` (5): Black Barrow's second room, opened by a real move |
| END-1 … END-3 | `ScenarioEndRuleTests` (4) |
| SET-3, SET-4 the level | `ScenarioLevelRuleTests` (2) |

Already covered when this pass began: elites before normals, only types on the board drawing, a
card for a type arriving mid-round (`MonsterTurnRulesTests`, `MonsterDeckRulesTests`), a numbered
treasure refused the second time and scenario availability (`CampaignRulesTests`), the two
"ignore negative effects" perks (`AttackModifierRulesTests`).

Rule violations these tests found — all three since corrected, the tests now plain assertions:

| Rule | Case | Fix | Test |
|---|---|---|---|
| CND-5, MON-14 | A Cultist's attack as it dies hit an invisible character beside it (seen in veteran playthroughs of #4, #83, #89 with a Scoundrel) | `resolveDeathAttacks` leaves out the invisible | `ConditionRuleTests.testADyingCultistsAttackDoesNotReachAnInvisibleCharacter` |
| CND-4 (B7) | A stunned character was still offered their defence item when attacked | `canUseItems` | `ConditionRuleTests.testAStunnedCharacterIsNotOfferedTheirShieldItem` |
| RND-9 (A11) | A deck that ran out and was shuffled in mid-round wasn't shuffled at the end of the round | `AttackModifierDeck.shuffleOwed` | `RoundRuleTests.testADeckThatRanOutMidRoundIsStillReshuffledAtTheEndOfTheRound` |

Still with no test that would catch a break: line of sight by an independent reckoning (the
simulator and `LootRuleTests` use the engine's `hasLOS`; `WallLineTests` and `LineOfSightTests`
pin it case by case); the player's choice among equal area placements (A10, not built); a
character's attack whose step has a custom or special-target line, and a boss's attacks, are not
range-checked by the simulator; `PlayLedger.rangeProblem` and `VeteranPolicy` measure plain hex
distance, which is never more than the range counted round walls, so they can miss an attack that
reached too far round a wall but can't raise a false alarm.