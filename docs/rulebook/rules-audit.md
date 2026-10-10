# Gloomhaven rules audit — what the game does against the rulebook

An audit of the game against the rules in [gh-rules.md](gh-rules.md) (the first-edition rulebook
and the official FAQ) and the scenario book, begun 2026-10-10 at commit `e19a083`. It was made
three ways: eight read-throughs of the code, one per rule area, each tracing the path real play
takes; two seeded playthroughs read line by line (scenario 1 with four characters, scenario 5 with
three); and the four-seed run of every scenario. File and line references are to `e19a083`.

Each finding has an id, the rule it breaks, what the game did, and its state:

- **fixed** — corrected, with a test that fails without the fix (named in the row);
- **open** — confirmed by reading the code, not yet corrected;
- **question** — the rule itself needs a decision.

About 125 findings. As of 2026-10-10 about 85 are fixed and 8 partly (five commits: the turn engine, trap
legends, the campaign, scenario rules, monster turns) and the rest are open; the largest open ones
are the walls beside doors (C2), doors ending a move (C3) and rooms with two doors (N1). Scenario-specific rules have their own table in
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
| B4 | ACT-2: a player may end an active bonus at any time | No way to do it | open |
| B11 | ACT-1: "on your next four attacks" marks a charge per attack | Crackling Air and Voice of the Night mark one charge per attack action (a Target 3 attack uses one); Master Physician marks one per figure healed though it says "Heal actions" | open |
| B13 | ACT-4 | A summon with no empty hex beside the character: the half was still performed and the card went active without a summon | fixed with T1 (the step now counts as not performed) |
| T6 | — | Rest log lines said "takes back N cards" with N the hand size, and "1 cards" | fixed |

## Elements

| Id | Rule | What the game did | State |
|---|---|---|---|
| B2 | ELE-2: an element already strong or waning can be infused and consumed in the same turn, in either order, and ends strong (FAQ) | Infusing a waning element made it unconsumable that turn; infusing a strong one and then consuming it left it inert | fixed — `ElementRuleTests` |
| T7 / B9 / D6 | ELE-4: a monster doesn't consume an element for an ability it doesn't perform (FAQ) | Every consume on the card is paid when the first monster of the type starts, even if none can perform the ability (seen: Night Demons, one disarmed and one dead of its wound, still consumed Dark). Savvas Icestorm's "Air: Push 4 instead" is paid and ignored | fixed — `MonsterTurnRulesTests` (`testADisarmedMonsterConsumesNothingForItsAttack`, `testTheFirstMonsterToAttackConsumesForThoseAfterIt`, `testAnIcestormsAirPushIsFourInstead`) |
| B13 | ELE-2 | A "any element" consume picks the element itself; Crackling Air and Foul Wind consume Air without asking | open |

## Attacks, modifiers, line of sight

| Id | Rule | What the game did | State |
|---|---|---|---|
| A1 | ATK-13: Retaliate is judged after the attack's push or pull (FAQ) | Judged before: pushing a retaliating monster away still cost the attacker; pulling one adjacent cost nothing | fixed — `ForcedMovementTests` (`testRetaliateDoesNotReachAnAttackerWhoPushedTheFigureAway`, `testRetaliateReachesAnAttackerWhoPulledTheFigureAdjacent`, and three more on amount, reach and death) |
| A5 / C4 | ATK-7: a flying figure is pushed over obstacles and springs no trap (FAQ) | Flyers were stopped by obstacles and sprang traps and hazards | fixed — `testAPushedFlyerTouchesNeitherTrapsNorHazardsAndCrossesObstacles` |
| A6 / C5 | ATK-7: a pushed figure passes through its allies but can't stop on a figure (FAQ) | Any figure behind the target blocked the push | fixed — `testAPushGoesThroughTheTargetsAlliesToAFreeHexBeyond`, `testAPushDoesNotGoThroughTheTargetsEnemies` |
| A7 / C6 | ATK-7: a push or pull is optional, all or nothing (FAQ) | The player could not decline | fixed — `testThePlayersOwnPushCanBeDeclined`, `testAPushOnceBegunCannotBeDeclined` |
| A9 | ATK-5: comparing cards with effects (FAQ: "+1 Stun" beats "+1"; "+0 Stun" against "+2" is ambiguous, so the first drawn) | Effects were ignored: Advantage kept a plain +1 over +1 Stun, and always took +2 over +0 Stun. Poison's +1 was counted in the comparison, which the FAQ excludes | fixed — `testAdvantageWeighsACardsEffects` |
| A2 | LOS-1: a sight line that touches a wall's corner or edge is blocked (FAQ) | Only a line passing through or along a wall is blocked; `LineOfSightTests` lines 147 and 167 assert the opposite of the rule | open |
| A3 | LOS-1: closed doors block line of sight | A shut door between two revealed rooms (a pressure-plate door that closed again, split starting rooms) doesn't | open |
| A4 / C10 | LOS-3: range isn't counted through walls | Range is plain hex distance everywhere (attacks, heals, loot, monster targeting, areas) | open |
| C2 | MOV-1, LOS-3: the edge of a map tile is a wall, also where two tiles' full hexes meet beside a door (FAQ) | Such hexes are adjacent: figures walk, attack in melee, push and see across the wall line. 60 doors in 42 scenarios (in #1, the hexes either side of door 1); seven more scenarios have tiles abutting with no connector at all (#6, #24, #40, #43, #67, #74, #82) | open |
| A8 | ATK-9, ATK-10: an added target is in addition to an area | With Backup Ammunition or Grim Bargain an area attack loses its area; a "+1 Target" modifier card drawn in an area attack gives nothing | open |
| A10 | ATK-10: the player places and may mirror an area | The game picks the placement covering most enemies; patterns are never mirrored (one chiral card, Scroll of Blizzards) | open |
| A11 | RND-9 | A deck that runs out and reshuffles mid-round forgets the ×2 or Null drawn earlier, so it isn't reshuffled at the end of the round | open |
| A12 | ATK-7 | "Further" and "closer" are plain distance, not counted around walls | open (low) |
| T11 | — | The turn log doesn't say when an attack had Advantage or Disadvantage, so a transcript can't be checked for it | fixed — the log line reads "attacks … with advantage / with disadvantage" |

## Movement, traps, doors, loot

| Id | Rule | What the game did | State |
|---|---|---|---|
| C1 | MOV-5: a trap does what the scenario's legend says | Effects come from the tile art in the map data (spike / bear / poison), always with 2+L damage. #2's two Stun traps deal damage and Immobilize; #31's Curse traps only damage; #44's Immobilize-and-Poison traps deal damage; about two thirds of the 75 scenarios with traps differ. A Stun trap should also end the move | fixed — `placements/gh-traps.json` holds all 75 legends; `TrapConditionTests` (traps sprung on the real boards of #1, #2, #15, #31, #44), `TrapLegendTests` |
| C3 | MOV-8: a character who opens a door keeps the rest of the move | The move ends on the door hex (the room beyond doesn't exist until revealed, and the leftover movement isn't offered) | open |
| — | MOV-8: a closed door is a wall to monsters | Parasitic Influence could walk an enemy onto a closed door without opening it (found by a playthrough once the fixes above changed its course) | fixed — `testAnEnemyMovedByACardCannotEnterAClosedDoor` |
| C8 | ATK-11: allied monsters drop no money (FAQ) | They do (#11, #12, #35, #36, #91). Bosses drop none, which no rule says | open |
| C9 | MOV-7: obstacles may not be placed to cut the map in two | No check | open |
| C11 | MOV-10 | A numbered treasure already looted in the campaign is still drawn on a replay (it gives nothing) | open (low) |
| D9 | MON-3: a jump's last hex is a normal move | A jumping monster that can't reach an attack hex this turn may end on a trap | open |

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
| D13 | MON-2, MON-9 | Low: focus ties by plain distance; two characters on the same initiative aren't ordered by their second card; monster Loot ignores line of sight | open (low): two characters on the same initiative aren't ordered by their second card; focus ties by plain distance |

## Setup, the round, resting, ending

| Id | Rule | What the game did | State |
|---|---|---|---|
| E5 / B5 | RND-4: the long rest is a turn; its Wound damage comes first and can be negated; the Heal 2 is optional (FAQ) | A resting character's Wound damage couldn't be negated and could exhaust them before the heal; the heal was forced | fixed — `RestRuleTests` (`testARestingCharactersWoundCanBeNegatedBeforeTheRestHeals`, `testTheRestsHealMayBeDeclined`, `testPoisonTakesTheRestsHeal`) |
| B6 | ACT-8: an item with uses left isn't spent, and a rest doesn't give its uses back (FAQ) | A long rest reset partly used items (Hide Armor) | partly fixed — uses kept through a rest (`testALongRestLosesOneDiscardTakesBackTheRestHealsTwoAndRefreshesSpentItems`); a multi-use item is still offered each time rather than used whenever it applies |
| B8 | TRN-7: items may be used on a long-rest turn (FAQ) | Not possible; "start/end of your next turns" bonuses (Lumbering Bash, Auto Turret) also do nothing on a rest turn | partly fixed — items are offered on the rest panel (`testItemsCanBeUsedOnALongRestTurnUnlessStunned`); "start/end of your next turns" bonus steps still do nothing on a rest turn |
| E13 | — | A turn spent stunned or resting didn't count for pressure plates, turn-end rules or goals judged as a turn ends | fixed — `testARestTurnEndsWithLooting`; the stunned and resting turn ends share the normal one |
| E3 | RND-3: a short rest may be taken in the scenario's last round (FAQ) | Not offered once the scenario was decided (matters for battle goals); `testNoShortRestOnceTheScenarioIsDecided` asserts the old behaviour | fixed — `testAShortRestIsOfferedInTheScenariosLastRound` |
| E9 | RND-3: the 1 damage for losing a different card can be negated (FAQ) | It couldn't | fixed — `testTheRedrawsDamageCanBeNegated` |
| E10 | RND-6: a long rest goes after a character on initiative 99 (FAQ) | Before | fixed — `testALongRestGoesAfterACharacterOnNinetyNine` |
| E7 | SET-3: solo play is one level higher | Not applied; the setup also offers a "story" difficulty (−2) the rulebook doesn't have | open |
| E12 / S1-5 | — | A character who escapes through the exit is recorded as exhausted (personal quests, Protector, Streamliner) | open |
| B7 | CND-4: a stunned character uses no items | Defence items, Boots of Speed, Dampening Ring and Heart of the Betrayer are still offered | open |
| B10 | TRN-7: items at any time in the turn | Not once both halves are done, before End Turn | fixed — "turn" items stay usable until the turn is ended |
| B12 | ATK-14: any damage may be negated by losing cards | Not for item costs, the Berserker's "suffer up to N", a printed "suffer damage" step, or a door shutting on a figure | partly fixed — the short-rest redraw and a closing door now offer the choice; item costs and the Berserker's "suffer up to N" still don't |
| S-gen | — | "Start of round" scenario rules run after cards are chosen (#5's Disarm, #48's Muddle, #31/#39's elements) | open |

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
| — | #35 | The City Archers are set up beside the party instead of on the battlements | open — their hexes are on tiles the game only lays out when the gate falls |
| — | #49, #78 | Missing immunity to forced movement (Siege Cannon, Cultists (b)) | fixed — `testTheCarriersAndTheCannonCantBeForcedToMove` |
| — | #66, #69, #76, #85, #88, #90, #95 | Smaller printed rules not enforced (door 1's timing, entering a hex beside the well, discarding three cards, Sun-Blessed, −1 Move, the Night Demon, boulders with hit points) | fixed for #66, #69, #85, #88, #90 (`ScenarioReauditTests`); open for #76 (discarding three cards) and #95 (boulders with hit points) |

Larger mechanics still not built are listed in `TODO.md` ("Scenario special rules… not built").

## Found while fixing

| Id | Rule | What the game does | State |
|---|---|---|---|
| N1 | MOV-9 | A room with two doors can be revealed empty: the map data holds a copy of the tile for each door and only one copy has the overlays, monsters and onward doors. Entered by the other door, the room has no traps, treasure or monsters (#7's F1b from D2b; #53's J2a). Maps affected: #6, #7, #15, #21, #24, #32, #43, #53, #76, #78, #82, #84, #94 | open |
| N2 | SET-1 | In nine rooms the map data's monster places disagree with the book (the scenario data, which decides who appears, is right): #3 B1a, #6 M1a, #10 L1b/L3a, #11 L2b, #12 H1b, #17 B4a, #26 C1a, #31 L2a, #44 M1b. A monster with no place of its own is put on a fallback hex | open |
| N3 | CMP-9 | Nothing in the data unlocks #72, #73, #76 or #77 (pinned by `testEveryScenarioCanBeUnlocked`) | question |
| N4 | CMP-6 | The FAQ's special cases for the doubled cost aren't followed (an element on a multi-target ability and a multi-figure summon are priced as single-target) | open |
| N5 | — | "All allies in the same room as you suffer 2 damage" hurts adjacent allies only | open |
| N6 | CMP-8 | Travelling on without returning to Gloomhaven, a linked scenario or a retry skipping the road event, and the city event being optional all need town-screen changes (F19) | open |

## Tests that don't prove what they say

Found while auditing; each needs rewriting to go through the code real play uses, or deleting.
The monster and campaign ones below were strengthened or corrected with their fixes (`RulebookTests`
focus and movement tests, `E2EGameTests` 248–882, `EnhancementTests`, `TownTests`,
`PersonalQuestAutotrackTests`, `TrapConditionTests`); the rest are still as described.

- **Assert fields nothing reads:** `RulebookTests` lines 78–97 and 182–194, `E2EGameTests` 370 and
  388 check `AttackResult.retaliateDamage` / `appliedConditions`, which `performAttack` never uses.
- **Tautologies and vacuous passes:** `RulebookTests` 559, `CoverageGapTests` 38 and 46 (pass the
  flag they assert); `E2EGameTests` 819 (`>= 0`); `FeatureTests` 478 (loop over a possibly empty
  list — the only test of the push direction rule); `RulebookTests` 416, 390, 364 and
  `DynamicObstacleTests` 106 (assertions inside `if let`); `CoverageGapTests` 128–215 (inside
  `if let scenario`).
- **Test an API the game never calls:** all of `ActionsManagerTests`; `RulebookTests` 837 and 847
  and `FeatureTests` 141–168 (`addBless` / `addCurse`).
- **Set a value and assert it:** `RulebookTests` 890–915 and `CoverageGapTests` 223–268 (loot),
  `PersistentAbilityTests` 14–29, `TrapConditionTests` 10–77.
- **Named for one thing, test another:** `RulebookTests` 249 and 276 (focus: plain distance gives
  the same answer); `E2EGameTests` 140, 248, 671, 797, 848, 882; `JumpFlyMovementTests` 12 and 33
  (`>=`); `MonsterSummonTests` (data parsing only); `RoomRevealTests` (rendering only).
- **Pin behaviour the rules forbid:** `CombatEffectsTests` 154 and `MonsterTextTests` 114 (D1);
  `LineOfSightTests` 147 and 167 (A2); `EnhancementTests` 56–95 (F6–F8);
  `PersonalQuestAutotrackTests` 88–104 (F2).
- **The simulator** checks attacks' line of sight with the engine's own function and never checks
  range; for turn flow it checks only card conservation. It has not won a game in 376 runs, so
  goals and late rooms are exercised only by unit tests.

## Rules with no test that would catch a break

Elites before normals (RND-7); only types on the board draw (RND-5); a card drawn for a type that
arrives mid-round (MON-12); monsters of a revealed room acting at the right time (MOV-9); a
character opening a door through a real move (MOV-8); Loot X with line of sight (ACT-7); summons
and monsters never looting (TRN-5); numbered treasure refused the second time (MOV-10); exhaustion
at card selection (RND-2); a summon acting before its owner and not in the round it arrives
(RND-8); modifier decks reshuffling at the end of the round (RND-9); a goal met in the round the
last character is exhausted (END-1); the two "ignore negative effects" perks (SET-6, SET-8);
ranged attack on an adjacent enemy; effects not applied to a target the attack killed; a condition
gained on a figure's own turn lasting through its next; a stunned character's cards and items;
scenario availability (requirements, blocks, counted achievements).
