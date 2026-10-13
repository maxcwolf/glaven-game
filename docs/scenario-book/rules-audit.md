# Gloomhaven scenario rules — what the game enforces

The status of every rule the scenario book prints (as noted in
[gh-scenario-rules.md](gh-scenario-rules.md)): one row a printed rule, **done**, **partial** (it
works in a simplified way; the row says how it differs) or **missing**, with where it is enforced
— the placements key, the function, the test — or what happens instead.

The table was first made on 2026-10-09 (commit `a3caf18`). Every row then partial or missing was
checked again against the data, the code and the tests on 2026-10-10 (commit `4c1ceae`), and the
done rows whose descriptions had gone stale were corrected. It was made by reading: a "done" row
means the data and code that enforce the rule were found, and usually a test that names it, not
that the scenario was played through. Keep it current: when a rule is built, rewrite its row in
the same commit (see [../rules-work.md](../rules-work.md)).

**447 rules: 391 done, 14 partial, 42 missing.**
79 of 95 scenarios have every printed rule done. The other 16: #55 (6 missing, 1 partial), #34 (4 missing, 2 partial), #76 (4 missing, 2 partial), #71 (4 missing, 0 partial), #73 (5 missing, 0 partial), #78 (5 missing, 0 partial), #21 (2 missing, 2 partial), #49 (4 missing, 0 partial), #74 (4 missing, 0 partial), #52 (1 missing, 1 partial), #68 (1 missing, 1 partial), #79 (1 missing, 1 partial), #82 (0 missing, 2 partial), #38 (0 missing, 1 partial), #47 (0 missing, 1 partial), #67 (1 missing, 0 partial).

Rules that were enforced wrongly, as against not at all, are findings of the engine audit
([../audits/2026-10-09-rules-audit.md](../audits/2026-10-09-rules-audit.md), rows S1-…, S2-…),
each with the test that pins its fix. How the data behind these rows is written — every key of
`placements/gh.json` — is in [README.md](README.md).

## What is still open

By the kind of work it needs, which is also the order it is best done in (`TODO.md`, "Open, in
order", has the same list as tasks). The rows below say what the game does today for each.

- **A choice the player has no way to make yet.** (Losing a card from hand to negate damage to
  something else — #44's captives, #84's crystal — is built: `saves`.) Giving up an action or part of a move to
  do something (built: `forgo` for #44's captives, #26's pumps and #52's treasure, `dig` for #75's graves): #26 cleansing a pump (which is its goal), #44 freeing a captive, #52 looting an
  adjacent tile, #75 digging a grave with movement. Choosing: which Living Spirit goes (#70),
  whose attack modifier deck an escort draws from (#44, #56). With these, #44's loss ("a captive
  dies") and Redthorn's +1 Attack for each captive freed can be switched on.
- **Things that are carried.** #69 the doll, #88 the Lurker King's claw (and −2 Move for its
  holder), #82 the chest's artifacts (who holds them decides both goals), #81 the Crystal of
  Zenith and Sphere of Midnight, #58 the Occult Dagger (and who may loot it), #54 the Staff of
  Xorn with its charge, goal and loss, #95 the six numbered tokens (with the locked door and the
  demons that keep coming until four are looted). **All built** (2026-10-13).
- **A board that moves as the round ends.** #71 the wind and #88 the current (built 2026-10-13: `drift`), #73 the boulders, #74
  the water rising in the hold (with its loss and the bailing).
- **Monsters that don't act as their cards say.** #71's Spitting Drakes asleep until woken; #49's
  Siege Cannon that never acts, the archer who walks to it, its firing and the archer who
  arrives when none is left; #78's two Cultists carrying the victim to the altar, the victim
  itself and the loss; #67's Arcane Golem and #73's Inox kept from a door.
- **Bosses.** #21: the altar that shares the Prime Demon's hit points, takes its damage, jumps
  a → f and summons by where it lands. #34: the Elder Drake on three hexes, its Zephyrs and its
  flight between perches. #79: the Betrayer's forced "Move 4" and its mind control.
- **Walls and obstacles with hit points.** #76's destructible walls (and its three discarded
  cards, the Stun, summons leaving walls alone), #95's boulders (built 2026-10-13), #52's centre-room obstacles
  that jumping and flying figures still cross and that don't block sight.
- **Small ones.** #38's Orchid heads for the nearest enemy, not the shaman; #68's tree can take a
  condition given to allies, and a poisoned summon doesn't avoid water; #52's starting hexes
  aren't limited to sections with monsters; a Push or Pull printed as its own ability ignores
  immunity (#34, #47).
- **#55 Foggy Thicket** is a random dungeon with no map: it can't be started at all.

### 1 · Black Barrow
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | no placements entry, no `finish` rule → default goal in `checkVictoryDefeat` |

### 2 · Barrow Lair
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Bandit Commander and all revealed enemies | done | placements goal `kill: ["bandit-commander"]`, `enemies: "revealed"` → `goalMet` |
| Setup: each character adds 3 Curse | done | scenario rule 0 (`round "R == 1"`, `start`, `amAdd curse:3`, `scenarioEffect`) → `applyAmAdd`; skipped for the "ignore negative scenario effects" perk |
| Doors a, b, c, d locked; only the Bandit Commander opens them | done | placements `locks` ×4 (m1a–a1a, a4b, a2a, a3b = doors a–d) with no key: `Pathfinder` and `moveAlong` refuse a locked door (`BoardState.lockedDoors`) and `updateLocks` never releases one; only the Commander's special opens them (`jumpToNextDoor`, next row). `ScenarioLockTests.testOnlyTheCommanderOpensTheSideRooms` |
| Boss special 1: Commander jumps to a door hex however far away and opens it; order a, b, c, d, then back to a | done | placements `cycles: {"bandit-commander": {"doors": true}}` → `MonsterTurnController` `.special` (text "move to next door and reveal room") → `BoardCoordinator.jumpToNextDoor`: he is put straight into the doorway of the next lock in the order written (a, b, c, d, then a again), however far away; a shut door opens and reveals its room, and a doorway that is taken sends him to the nearest empty hex (FAQ). `ScenarioSpecialRuleTests.testTheCommanderJumpsToEachDoorInTurn`. The side rooms hold what their tiles print: `ScenarioReauditTests.testTheBarrowsSideRoomsHoldWhatTheBookPrints`. (`moveToNextDoor`, the old walk to the nearest door, is only the fallback for a scenario without the cycle) |
| Boss special 2: summon 1 normal Living Bones (2 characters) or 1 elite (3–4) | done | `bandit-commander.json` special 2 `summon` (player2 normal, player3/4 elite) → `performSummon` → `summonMonster` (adjacent empty hex, standee limit) |

### 3 · Inox Encampment
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill 5×C enemies | done | placements goal `killCount: "5xC"` → `goalMet` sums `scenario.killCounts` of hostile types (C at least 2) |
| 1 normal Inox Guard spawns at (a): end of every odd round (2 characters), beginning of every round (3–4 characters) | done | 2 characters: rule 0 (`round "R % 2 == 1"`, no `start` → as odd rounds end). 3–4 characters: rule 1 (`round "true"`, `start: true`) → `ScenarioRulesManager.evaluateRulesForTheRoundToCome`, applied as card selection begins, so the first guard is there before round 1 is played. Marker a = placements l1b [0,3]. `ScenarioPlacementTests.testTheEncampmentsGuardArrivesAsTheRoundBegins`, `ScenarioEnforcedRuleTests.testTheEncampmentsGuardsStopComingWhenTheDoorOpens`. (A spawn with no Inox Guard standee free brings nothing — with four characters all can be on the map already) |
| Spawning stops once door 1 is opened | done | rule 2 (`always`, `requiredRooms: [6]` = E1b) `disableRules` index 0 and 1; evaluated on room reveal (`openDoor` → `evaluateRules(.figureChange)`) |

### 4 · Crypt of the Damned
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 5 · Ruinous Crypt
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: all characters start with Disarm | done | rule 0 (`R == 1`, `start`, `gainCondition disarm`, `scenarioEffect`) → `EntityManager.addCondition`, applied before round 1's cards are chosen (`ScenarioRulesManager.evaluateRulesForTheRoundToCome`, called as card selection begins) and active through each character's first turn. `ScenarioEnforcedRuleTests.testCharactersAreDisarmedWhileTheFirstCardsAreChosen`, `testCharactersStartDisarmedOrMuddled` |

### 6 · Decaying Crypt
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: reveal the M tile (M1a) and kill all revealed enemies | done | placements goal `reveal: ["m1a"]`, `enemies: "revealed"` |
| Setup: each character adds 3 Curse | done | rule 0 `amAdd curse:3` at start of round 1 |

### 7 · Vibrant Grotto
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles | done | placements goal `loot: "goal"`; map has 5 treasure overlays with id `goal` (m1b, d2b, c2a, f1b, b4b) → `goalTreasureIsLooted` |
| Treasure tiles can only be looted with a Loot action, not by end-of-turn looting | done | placements `lootActionOnly: true` → `goalTreasureNeedsLootAction`: `lootHexes` leaves a goal tile where it is unless a Loot ability is doing the looting (`collectLootInRange` passes `byLootAction: true`), so neither `lootAtEndOfTurn` nor a move that loots the hexes it enters picks one up; the scenario brief says so. `ScenarioGoalTests.testGoalTreasureThatNeedsALootAction` (played on #30, the same flag) |

### 8 · Gloomhaven Warehouse
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill both Inox Bodyguards | done | placements goal `kill: ["inox-bodyguard"]` (room 3 revealed, both entities dead) |

### 9 · Diamond Mine
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Merciless Overseer and loot the treasure tile | done | placements goal `kill: ["merciless-overseer"]`, `loot: "goal"` (goal chest on n1a) |
| Boss special 1: all Vermling Scouts immediately take an extra turn with this round's card | done | `MonsterTurnController` `.special`: label "All Scouts act again" → `executeMonsterGroup(scouts)` with `currentAbility` (scouts summoned this round are skipped, as for any new summon) |
| Boss special 2: summon 2 normal Scouts (2 characters), 1 normal + 1 elite (3), 2 elite (4) | done | `merciless-overseer.json` special 2 `summon`: one entry with `count: 2` (player2 normal, player4 elite) and two player3 entries (normal, elite). `MonsterSummonSpec.summoned(forPlayerCount:)` brings `count` of an entry's rank for the player count at the table and nothing from an entry that has none for it: 2 normal / 1 normal + 1 elite / 2 elite (`performSummon` → `summonMonster`, beside the boss, free hexes and standees permitting). `MonsterSummonDataTests.testABossSummonsWhatItsPlayerCountSays` (the same data shape), `testEveryBossSummonBringsSomethingAtEveryCount` |

### 10 · Plane of Elemental Power
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 11 · Gloomhaven Square A
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Captain of the Guard | done | placements goal `kill: ["captain-of-the-guard"]` |
| Living Bones and Living Corpses are allies of the characters and enemies of all other monster types | done | scenario `allies: ["living-bones","living-corpse"]` → `GameMonster.isAlly` (`ScenarioManager`); `MonsterAI.gatherEnemies` / `isAllyFaction` make them fight hostile monsters and vice versa; excluded from goal/"hostile" counts |

### 12 · Gloomhaven Square B
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill Jekserah | done | placements goal `kill: ["jekserah"]` |
| City Guards and City Archers are allies of the characters and enemies of all other monster types | done | scenario `allies: ["city-archer","city-guard"]`, same mechanism as #11 |
| Boss special 1: summon 2 normal Living Bones (2 characters), 1 normal + 1 elite (3), 2 elite (4) | done | `jekserah.json` special 1 `summon` (player3 normal; player3 elite; player2 normal / player4 elite with `count: 2`) → `MonsterSummonSpec.summoned(forPlayerCount:)`: 2 normal / 1 normal + 1 elite / 2 elite (`performSummon`). `MonsterSummonDataTests.testABossSummonsWhatItsPlayerCountSays`; the stat card's "Attack −1, all adjacent enemies" that follows is performed |
| Boss special 2: as special 1 with Living Corpses | done | special 2, the same data shape with `living-corpse`: 2 normal / 1 normal + 1 elite / 2 elite; the stat card's "Move −1, Attack +2" that follows is performed |

### 13 · Temple of the Seer
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 14 · Frozen Hollow
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: each character adds three −1 cards | done | rule 0 `amAdd minus1:3` → `AttackModifierDeck.addCard` (kept through reshuffles for the scenario) |

### 15 · Shrine of Strength
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot the treasure tile | done | placements goal `loot: "goal"` (goal chest on c1a) |
| Doors (a) locked; open when any character occupies plate (c) at the end of their turn | done | placements locks d1a–h3b and d1a–h1b with `plate: ["c"]` (c = d1a [2,2]); `updateLocks(turnEnded:)` → `keyTurned`, doors open and reveal both rooms |
| Doors (b) locked; open when all characters occupy a plate on the H tiles at end of a turn: (d) for 2, (d)+(e) for 3, (d)+(e)+(f) for 4 | done | lock d1a–c1a (both doors) `allOnPlates: {markers:[d], more:{3:[e],4:[e,f]}}`; d on h1b [6,1] and h3b [0,1], e h3b [6,1], f h1b [0,1]. Checked as "every non-exhausted character stands on a plate in play", so with an exhausted character the remaining ones suffice |

### 16 · Mountain Pass
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 17 · Lost Island
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 18 · Abandoned Sewers
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 19 · Forgotten Crypt
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: Hail ends her turn adjacent to the altar (b) | done | placements goal `arrive: {objective 1, marker b, adjacent}`; `EscortTurnController` → `noteEscortArrival` after her turn → `goalMet` |
| Lose: Hail is killed | done | placements `lostAt: {"1": 1}` → `goalLost` |
| Setup: each character adds 3 Curse | done | rule 0 `amAdd curse:3` at start of round 1 |
| Hail has 4+(2×L) HP | done | scenario `objectives[0].health "4+(2xL)"` → `ScenarioManager.addObjectiveEntity`; placed at d2a [0,2] |
| Hail is an ally of the characters and an enemy of all monster types | done | `escort: true` → `isPlayerSide`, and `MonsterAI.gatherEnemies` lets monsters focus escorts |
| Hail acts on initiative 99 every round: Move 2 toward the altar (b) | done | no `initiative` in data → `resolvedInitiative` 99 (sorted as 98.5 in `RoundManager`); action `move 2` + label "towards the altar %game.mapMarker.b%" → `EscortTurnController.destination` → `EscortAI.walk` |
| …opening doors and springing traps if necessary | done | `EscortAI.walk` (`canOpenDoors: true`, `avoidTraps: true` — traps only when no route avoids them); `doorsToward` heads for the closed door on the way while (b) is unrevealed; `moveAlong` opens the door / springs the trap |
| Section 1 (door 1): at (c) 1 normal Cultist (2 characters) or 2 (3–4) | done | rule 1 (`always`, `once`, `requiredRooms [3]` = C2b), marker c = d2a [2,4]; second one goes to the nearest empty hex |
| Section 2 (door 2): at (d) 1 normal Living Spirit (2–3 characters) or 2 (4) | done | rule 2 (`requiredRooms [4]` = C1a), marker d = d1a [1,3] |
| Section 3 (door 3): at (e) 1 normal Living Bones (2 characters) or 2 (3–4) | done | rule 3 (`requiredRooms [5]` = I1b), marker e = c2b [0,2] |

### 20 · Necromancer's Sanctum
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill Jekserah | done | placements goal `kill: ["jekserah"]` (`goalMet`: room 4 revealed, none alive) |
| Boss Special 1: summon Living Bones — 2 normal (2 chars), 1 normal + 1 elite (3), 2 elite (4) | done | `monster/jekserah.json` special 1: `ActionModel.monsterSummons` keeps each entry's `count`, and `MonsterSummonSpec.summoned(forPlayerCount:)` skips an entry with nothing for this player count, so `MonsterTurnController.performSummon` brings 2 normal (2 characters), 1 normal + 1 elite (3) or 2 elite (4). `MonsterSummonDataTests.testABossSummonsWhatItsPlayerCountSays`, `testTheCountIsKept`. The stat card's "Attack −1, all adjacent enemies" that follows is performed |
| Boss Special 2: same with Living Corpses | done | special 2, the same data shape and decoding with `living-corpse`: the book's counts and ranks; the stat card's "Move −1, Attack +2" that follows is performed |

### 21 · Infernal Throne
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Demon | done | placements goal `kill: ["prime-demon"]` — but it is killed by attacking it directly (see below) |
| Objective: Altar shares hit points, initiative and immunities with the Prime Demon | missing | `21.json` has no `objectives` and no `rules`, and placements #21 holds only the goal (`tiles` is empty). No altar piece exists. Needs an objective that shares the boss's hit points and turn, and the hexes a–f written (`TODO.md`: "Bosses still played from their stat cards") |
| The Prime Demon cannot be damaged; damage is dealt to the altar instead | missing | The Prime Demon is an ordinary boss — attacks and damage land on it directly, and killing it wins (`goal.kill`). Needs the altar above, with all damage sent to it |
| Boss Special 1: altar jumps a→b→…→f (displacing figures, revealing the room and opening doors); altar summons a demon by location (normal for 2, elite for 3–4); Prime Demon "Move+2, Attack−1" | partial | Of `monster/prime-demon.json` special 1 only the trailing Move +2, Attack −1 is performed (`MonsterTurnController` `.special` → `executeCard`). The `custom` "Throne moves" matches nothing and is logged ("Resolve the boss's special ability 1 as printed on its stat card" — asserted for #21 in `ScenarioSpecialRuleTests.testThePrimeDemonsSpecialsAtTheBattlements`); the `summon` has `value: "demon"` and no `valueObject`, so `performSummon` summons nothing (a gap named in `MonsterDataTests.testEveryBossSpecialActionIsPerformedOrKnownNotToBe`). No altar jump, no room revealed, no demon by location; letters a–f are not written |
| Boss Special 2: same, demon normal for 2–3, elite for 4 | partial | Special 2 is identical data with the same result — Move +2, Attack −1 only, the rest left to the players by a log line |

### 22 · Temple of the Elements
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all altars (a) | done | placements goal `destroy: [1]` (all four dead and every door open) |
| Objectives: Altar ×4, 4+(C×L) HP each | done | `objectives[0]` health `4+(CxL)`; `rooms[1].objectives: [1,1,1,1]` creates all four when room 2 is revealed; placements put one on each corner tile (c1a, c2b, d1a, d2a), placed as each is revealed |
| Per altar not yet destroyed: all demons +1 max HP, +1 attack, +0.5 movement and +0.5 range (rounded up) | done | rule 0 (persistent `statEffects` on `.*demon.*`, `reference` Altar `present`): `ScenarioRulesManager.applyScenarioStatEffects` counts the altars standing as X (all four exist from the moment room 2 is revealed, their rooms revealed or not) → `MonsterManager.applyScenarioStatEffect` adds X to maximum hit points (a point gained is a point healed, a point lost only lowers the ceiling) and sets `statBonusAttack` = X and `statBonusMovement`/`statBonusRange` = X/2 rounded up, which `GameMonster.stat(for:)` adds to the stat card. Re-applied on every rule evaluation, so each altar destroyed takes its share away and a demon that arrives later has the bonus too. `ScenarioSpecialRuleTests.testAltarsStrengthenTheDemons`, `testADemonSpawnedLaterHasTheBonusToo` |
| Melee attacks gain no range from this | done | `GameMonster.stat(for:)` leaves a range of 0 (or "-") as it is, so only demons with a printed range gain any; asserted in `testAltarsStrengthenTheDemons` (a melee and a ranged demon) |

### 23 · Deep Ruins
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: occupy all pressure plates simultaneously | done | placements goal `occupy`, judged as a turn ends (`goalMet`) |
| Setup: each character adds 3 "−1" cards | done | rule 0 `amAdd minus1:3` at the start of round 1 (`applyAmAdd`) |
| Number of plates = C: a (2), a+b (3), a+b+c (4) | done | `occupy.markers: ["a"]`, `more: {"3": ["b"], "4": ["b","c"]}`; letters on d1a and m1a (`platesInPlay`) |

### 24 · Echo Chamber
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: open all doors | done | placements goal `reveal: ["*"]` → every door open, enemies need not be dead |

### 25 · Icecrag Ascent
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: all characters escape through the exit (a) | done | placements goal `escape: {marker: "a"}`, five hexes on g2a; all standing characters on exit hexes as a turn ends |
| Lose: a character exhausted while not on an exit hex | done | `lostIfExhausted: ["offExit"]` (`exhaustionLoss`, judged where they stood) |
| Setup: each character adds 2 "−1" cards | done | rule 0 `amAdd minus1:2` |
| Escape once every character is on an exit hex or was exhausted on one | done | `goalMet` counts only unexhausted characters; one exhausted on an exit hex is no loss and is remembered (`exhaustionLoss` → `boardState.exhaustedOnExit`), and with every character exhausted on an exit hex `everyoneEscaped` wins it rather than ending as "all characters exhausted". `ScenarioReauditTests.testAnEscapeIsCompleteWithEveryoneExhaustedOnTheExit`, `testAnEscapeIsLostByExhaustionAwayFromTheExit` |

### 26 · Ancient Cistern
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: cleanse all water pumps | done | placements goal `freed: [1, 2, 3]` → `goalMet`: every pump set up (two, three or four by the party's size) cleansed, with every room revealed; the imps needn't die. `ScenarioSpecialRuleTests.testAPumpIsCleansedForABottomActionAndTheCisternIsWon` |
| Setup: each character adds 3 Curse cards | done | rule 0 `amAdd curse:3` |
| Number of pumps = C: a (2), a+b (3), a+b+c (4) | done | `rooms[2].objectives: [1, 1, "2:C > 2", "3:C > 3"]` (`spawnObjectiveByReference`); placed on l1a by placements; health 0 makes them untouchable scenery (`isUntouchable`) |
| A character adjacent to a pump may give up a bottom action to cleanse it | done | placements `forgo` with `does: "cleanse"`, `bottom: true` for the three pump objectives → the button "Cleanse Water Pump" beside the basic Move, for a bottom action not yet begun (never a top one); the card is discarded and the pump leaves the map, after which it summons no imp (an objective off the map is no longer `present` to a rule). Same test |
| End of each round: every uncleansed pump summons one normal Black Imp | done | rules 1–3 (round end, a pump with that letter `present`) spawn `count: "F"` normal Black Imps — one for each pump carrying the letter — and `spawnHex(forMarker:)` puts each beside the pump with the fewest monsters next to it, so the two (a) pumps get one each. `ScenarioSpecialRuleTests.testEachPumpGetsItsOwnImp`. A pump that is gone would stop summoning, but none can be cleansed yet (row above), so in play it never stops |

### 27 · Ruinous Rift
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: protect Hail for ten rounds | done | rule 8 `round: "R == 10"`, `finish: "won"` at the end of round 10 |
| Lose: Hail is killed | done | placements goal `lostAt: {"1": 1}` |
| Objective: Hail, 4+(2×L) HP; ally, enemy of all monsters; initiative 99 for focus only | done | `objectives[0]` escort with no actions, placed at m1a [2,3]; monsters target escorts (`MonsterAI.gatherEnemies`) with focus initiative 99 (`enemyInitiative`, default `resolvedInitiative`). FAQ: placements `passiveTurns: [1]` gives her a turn at 99 in which she does nothing but her conditions act — a Wound hurts her (`takePassiveTurn`; `ScenarioReauditTests.testHailsWoundHurtsHerOnHerTurn`) |
| End of round 1: one demon at b | done | rule 0 (Night Demon at b) |
| End of round 2: one demon at c | done | rule 1 (Wind Demon at c) |
| After round 2: two different demons each round — d and e on odd rounds, b and c on even | done | rules 2–7 (rounds 3–9); letters b–e written on m1a |
| Type cycle Night → Wind → Frost → Sun → Earth → Flame → Night | done | Written out round by round in rules 0–7 (through round 9) |
| Spawn rank: all normal (2); Wind, Sun, Flame elite (3); all elite (4) | done | `player2/3/4` on every spawn in rules 0–7 |

### 28 · Outer Ritual Chamber
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal (no placements entry) |
| Living Corpses are two levels above the scenario level, max 7 | done | `monsters: ["living-corpse:+2"]` and room standees named `living-corpse:+2`; `MonsterNameSpec.level(forScenarioLevel:)` clamps to 0…7 |

### 29 · Sanctuary of Gloom
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: each character adds 3 "−1" cards | done | rule 0 `amAdd minus1:3` |
| Objectives: Doors (a) ×3, 4+L HP each | done | `objectives[0]` health `4+L`; `rooms[0].objectives: [1,1,1]` |
| Doors (a) are locked; each opens when destroyed | done | placements e1a objectives with `"door": true` (`isDoorBarred`; `clearObjectiveSite` opens the door) |

### 30 · Shrine of the Depths
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot the treasure tile | done | placements goal `loot: "goal"`; map treasure id `goal` on n1b |
| The treasure tile can be looted only with a Loot action, never by end-of-turn looting | done | placements `lootActionOnly: true` → `goalTreasureNeedsLootAction`: `lootHexes` skips the goal tile unless called by a Loot ability (`collectLootInRange`, `byLootAction: true`), so ending a turn on the hex leaves it there and doesn't win. `ScenarioGoalTests.testGoalTreasureThatNeedsALootAction` |

### 31 · Plane of Night
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy the rock column (a) | done | placements goal `destroy: [1]` |
| Setup: each character adds 3 Curse cards | done | rule 0 `amAdd curse:3` |
| Objective: rock column, (8+L)×C HP | done | `objectives[0]` health `(8+L)xC`, placed at l2a [2,3] |
| Section 1: from then on, end of odd rounds a Night Demon at b (normal 2–3, elite 4); end of even rounds one at c (normal 2, elite 3–4) | done | rules 2 and 3 (`R % 2`, `requiredRooms: [3]`); letters b, c written on l2a |
| Start of every round: Dark strong, Light inert | done | rule 1 (`start: true`, `elements`) → `applyElementRule` |

### 32 · Decrepit Wood
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: reveal the G tile, kill all revealed enemies, loot the treasure tile | done | placements goal `reveal: ["g2b"]`, `enemies: "revealed"`, `loot: "goal"` |

### 33 · Savvas Armory
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles, then all characters escape through the exit (a) | done | placements goal `loot: "goal"` (four `goal` chests on m1a) + `escape: {marker: "a"}` |
| Lose: a character exhausted while not on an exit hex | done | `lostIfExhausted: ["offExit"]` |
| Objective: Door b, 4+L HP | done | `objectives[0]`, placed on the door at a4b [3,0] |
| Section 1: end of the round door 1 is opened, a Savvas Lavaflow at d (normal 2, elite 3–4) | done | rule 1 (`once`, `requiredRooms: [4]`, round end); letter d on c2b |
| End of the round the last treasure tile is looted: a Savvas Icestorm at d (normal 2–3, elite 4) | done | placements `rules`: `round "true"`, `once`, `when: [{"looted": "goal"}]`, spawn `savvas-icestorm` (player2 and player3 normal, player4 elite) at d (c2b [1,0]) — no `always`, so it fires as that round ends. `ScenarioSpecialRuleTests.testTheIcestormComesWhenTheLastTreasureIsLooted` |
| Door b is locked and opens when destroyed | done | placements `"door": true`; rule 0 also reveals room 2 when the Door is dead |
| Door 1 is locked; opens when every character is on a pressure plate (c) as a turn ends | done | placements lock `between: ["i1b","m1a"]`, `allOnPlates: {markers: ["c"]}` (`keyTurned`) |
| Escape once every character is on an exit hex or was exhausted on one | done | as #25; with everyone exhausted on the exit while a treasure tile is still unlooted it is no escape (`ScenarioReauditTests.testAnEscapeStillNeedsTheTreasure`) |

### 34 · Scorched Summit
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Elder Drake | done | placements goal `kill: ["elder-drake"]` |
| Objectives: Zephyrs — cannot be damaged; "Move 2, Attack C" just before the Elder Drake's turn | missing | They would come from Special 2's `summon` with `value: "objectiveSpawn"`, which `ActionModel.monsterSummons` doesn't decode and nothing else reads (no Swift code mentions `objectiveSpawn` or `initiativeShare`); the gap is named in `MonsterDataTests.testEveryBossSpecialActionIsPerformedOrKnownNotToBe`. No Zephyr ever appears. Needs an objective a monster summons: undamageable, untouched by any ability, acting just before the boss |
| The Elder Drake occupies all three hexes of its obstacle | missing | It is a one-hex piece, set up from the map data's single position for it (l3b [4,6]). There are no multi-hex figures |
| It can be targeted through any of its hexes and targets from any of them | missing | Follows from the above: it is attacked at, and attacks from, its one hex |
| The Elder Drake cannot be forced to move | partial | `elder-drake.json` lists `push` and `pull` immunities and `BoardCoordinator.performPushPull` refuses a target with them (a push or pull on an attack, on all adjacent enemies, or on a chosen enemy within range); tested on #47's Sightless Eye, the same check (`ScenarioSpecialRuleTests.testAnImmovableBossIsNotPushed`). Not covered: a Push/Pull printed as its own ability after an attack goes `beginStandalonePushPull` → `beginPushPull` without that check, so it would still move the drake. (It never moves by itself: no movement stat) |
| The huge boulder obstacles cannot be destroyed | done | placements `indestructible: {"subTypes": ["boulder-3"]}` → `isDestructibleObstacle`, asked by every way an ability destroys an obstacle (a destroy-obstacle token, Stone Pummel's bonus, Heaving Swing's push into one). `ScenarioReauditTests.testWhatTheScenarioSaysCantBeDestroyedIsnt` |
| Boss Special 1: nothing printed in the scenario book (stat card: area attack) | partial | The stat card's Attack +0 with its area pattern is performed, anchored on the drake's single hex (the pattern's three "active" hexes are its three-hex body; `AoEResolver` takes the first as the origin), so the area is the printed one only as seen from that hex |
| Boss Special 2: summon two Zephyrs, then fly to the next perch a → b → c → a | missing | The summon does nothing (above) and the `custom` "Fly to next perch of boulders" matches nothing — the log says "Resolve the boss's special ability 2 as printed on its stat card". Perches a–c are not written (placements #34 `tiles` is empty). Needs the Zephyrs, the three perches as letters and the flight tied to them (a `cycles` entry, as #51's Gloom has), and a three-hex figure to land |

### 35 · Gloomhaven Battlements A
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy door 1 and kill the Captain of the Guard | done | placements goal `destroy: [1]`, `kill: ["captain-of-the-guard"]` |
| Setup: City Archers grouped at a and b are placed at the start | done | placements `laidOut: ["i1b", "b2b"]` puts the yard's tiles on the map without revealing their room, and letters a (i1b [0,0], [1,0]) and b (b2b [2,0], [3,0]) are written: room 1's archers carry `marker: "a"`/`"b"` and are set up on those hexes at the start (two for 2 characters, four for 3–4), with line of sight and range over the wall sections. `BattlementsTests.testTheArchersStandOnTheBattlementsFromTheStart`, `testTheArchersSeeOverTheWall`. |
| Other enemies on the B and I tiles are not set up until door 1 is destroyed or a character/ally moves onto B or I | done | Room 2 (I1b + B2b) is set up when the barred gate is destroyed (`revealRoom`) or as soon as a character or ally stands on one of the laid-out tiles behind it — a Jump clears a wall section — (`setUpLaidOutRoomsEntered`), never on the archers' lettered hexes. `BattlementsTests.testTheRestAreSetUpWhenTheGateIsDestroyed`, `testTheRestAreSetUpWhenACharacterGetsOverTheWall` |
| Objective: Door 1, (7+L)×C HP | done | `objectives[0]` health `(7+L)xC`, on the door at l3a [4,7] |
| Door 1 is locked and opens when destroyed | done | placements `"door": true` |
| All demons are allies of the characters and enemies of other monsters, still acting from ability cards | done | `allies: [earth/flame/frost/wind-demon]` → `monster.isAlly`; `MonsterAI.gatherEnemies` inverts sides; `MonsterTurnController` runs their cards |
| A demon that can get within range of the door focuses on it | done | Allied monsters count a thing to destroy among their enemies (`MonsterAI.gatherEnemies`: for the ally faction an objective that is no escort, not protected and has hit points), and placements `focusFirst: [1]` → `MonsterAI.prioritized` puts the gate first for a demon that can get within range of it this turn; otherwise the normal rules. `ScenarioSpecialRuleTests.testAlliedDemonsGoForTheGate`, `testAlliedMonstersAttackWhatIsToBeDestroyed` |

### 36 · Gloomhaven Battlements B
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Demon | done | placements goal `kill: ["prime-demon"]`; the boss is held back (`later`) and has no entity until the gate falls, and `goalMet` needs one to have existed and none left alive |
| Setup: do not set up the Prime Demon | done | placements `later: ["prime-demon"]` → `ScenarioManager.heldBackMonsters`: room 1's boss isn't created at setup. `ScenarioSpecialRuleTests.testThePrimeDemonComesWhenTheGateFalls` ("not set up") |
| Setup: City Archers are set up at the start | done | Room 1 lists two elite City Archers; I1b and B2b hold starting hexes so `BoardBuilder.buildStartingRoom` reveals them at setup and the archers take their map positions there |
| Objective: Door 1, 10+(2×L) HP; cannot be healed; not an ally of the characters | done | `objectives[0]`; placements `protect: [1]` → `isProtected`: scenery, never an ally (`areAllies`), so not a heal target; characters can't attack it |
| The Prime Demon spawns at e only once door 1 is destroyed | done | placements `rules`: `always`, `once`, Door (marker 1) `dead` → `prime-demon` (boss) at e (l3a [4,5]) with `placed: true` — set up late, not spawned. `testThePrimeDemonComesWhenTheGateFalls` |
| The Prime Demon starts with twice its stat-card hit points | done | rule 0 `statEffects` `health: "Hx2"`, `absolute` (`applyScenarioStatEffect`) |
| End of each round with door 1 standing: the Prime Demon suffers (2×C)+L−2 damage | done | The demon isn't on the map while the gate stands, so the scenario's rule 5 (Door `present` + `damage (2xC)+L-2`) has nothing to hurt; a placements rule (`always`, `once`, prime-demon `present`) deals `(R-1)x((2xC)+L-2)` the moment it appears — one share for every round that ended with the gate standing, all eight when the gate falls by itself. `testThePrimeDemonComesWhenTheGateFalls` |
| Door 1 is locked and opens when destroyed by demons | done | placements `"door": true` + `protect`: hostile monsters treat it as an enemy (`gatherEnemies`, `isProtected && maxHealth > 0`) |
| A demon that can get within range of the door focuses on it | done | placements `focusFirst: [1]` → `MonsterAI.prioritized`: a monster that attacks the gate and can get within range of it this turn has it lead its focus candidates, whoever is nearer; otherwise the normal rules. The same mechanism is tested on #35 and #84 (`testAlliedDemonsGoForTheGate`, `testMonstersGoForTheCrystalWhenTheyCanReachIt`); for #36 `testAlliedMonstersAttackWhatIsToBeDestroyed` only shows that its demons target the gate |
| City Archers are allies of the characters, still acting from ability cards | done | `allies: ["city-archer"]` |
| End of each round a demon spawns, cycling a Flame → b Earth → c Frost → d Wind | done | rules 1–4 (`R % 4`); letters a–d written |
| Spawn rank: all normal (2); Flame and Frost elite, Earth and Wind normal (3); all elite (4) | done | `player2/3/4` in rules 1–4 |
| End of round 8: door 1 is destroyed automatically if still standing | done | placements `rules`: `round "R == 9"`, `start: true`, `damage 999` to the Door — applied as round 9 begins, before its cards are chosen, so round 8 and its damage are over; the Prime Demon then arrives with eight rounds' damage. `testThePrimeDemonComesWhenTheGateFalls` (which also checks the gate still stands as round 8 begins) |
| Boss specials 1 and 2: ignore the stat card, perform "Move+0, Attack+0" | done | placements `specials: {"prime-demon": [...]}` — Move +0, Attack +0 twice — replace the stat card's in `MonsterTurnController` `.special`: nothing is summoned and nothing is left "as printed". `ScenarioSpecialRuleTests.testThePrimeDemonsSpecialsAtTheBattlements` |

### 37 · Doom Trench
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: all characters escape through the exit (a) | done | placements goal `escape: {marker: "a"}`, six hexes on k2a |
| Lose: a character exhausted while not on an exit hex | done | `lostIfExhausted: ["offExit"]` |
| Setup: each character adds 3 Curse cards | done | rule 0 `amAdd curse:3` |
| Escape once every character is on an exit hex or was exhausted on one | done | as #25 |

### 38 · Slave Pens
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and protect the Orchid | done | default kill-all goal (placements goal has only text and a loss) |
| Lose: the Orchid is killed | done | placements goal `lostAt: {"1": 1}` |
| Objective: Orchid, 6+(3×L) HP; ally, enemy of all monsters; initiative 99, Move 3 toward the shaman on the D tile, opening doors and springing traps | partial | HP, side and initiative 99 are right (`objectives[0]`, `escort: true`, default initiative; placed at c2a [1,3]). His Move 3's destination is only the text "towards the shaman on the D tile", which names no map letter, so `EscortTurnController.destination(of:)` finds nothing and `EscortAI.computeTurn` falls back to `PlayerSideAI.plan`: he moves 3 toward the nearest revealed enemy, not toward D1b, and doesn't make for or open the doors on the way. Needs a destination that is a monster or a tile (or a letter written on D1b and named in his move) |

### 39 · Treacherous Divide
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy the altar (a) | done | placements `goal.destroy: [1]`; altar placed on `d2b` [3,4]; `goalMet` wants it dead with every door open |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` at `R == 1`, `start` → `ScenarioRulesManager.applyAmAdd` (skipped for the "ignore negative scenario effects" perk) |
| Section 1: the altar has 6+(C×L) HP | done | `objectives[0].health` `"6+(CxL)"`; the objective is created with room 2 (D2b) in `ScenarioManager.openRoom` → `addObjectiveEntity` |
| Start of every round: Ice Strong, Fire Inert | done | scenario `rules[1]`: `round: "true"`, `start`, `elements` ice→strong, fire→inert → `applyElementRule` |
| Dark pit obstacles cannot be destroyed | done | placements `indestructible.subTypes: ["dark-pit"]` → `isDestructibleObstacle` (`BoardCoordinator+Effects`), which every way an ability destroys an obstacle asks first (the destroy-obstacle choice, Stone Pummel's bonus, Heaving Swing's push into an obstacle); the six dark pits are barred, the three boulders can still be destroyed; the brief says it (`notes`); `ScenarioReauditTests.testWhatTheScenarioSaysCantBeDestroyedIsnt`, `testNoAbilityDestroysADarkPit` |

### 40 · Ancient Defense Network
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: occupy both pressure plates (a) simultaneously | done | placements `goal.occupy.markers: ["a"]`, plates on `a4b` [3,2] and `l1a` [2,2]; judged as a turn ends in `goalMet` |
| Setup: each character adds 3 "-1" cards | done | scenario `rules[0]`: `amAdd` `minus1:3` at `R == 1`, `start` |

### 41 · Timeworn Tomb
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: all characters escape through exit (a) | done | placements `goal.escape` marker a (`e1a` [2,4]), `leave: true` → `letCharactersLeave` / `everyoneEscaped`: won once someone has left and every other character has left or is exhausted, so one exhausted before E1a is revealed (no loss) isn't waited for; an escape never undoes a loss (an exhaustion with E1a open loses even after someone has left); `ScenarioSpecialRuleTests.testEscapeDoesNotWaitForTheExhausted`, `ScenarioReauditTests.testTheTombIsLostByExhaustionAfterAnotherHasLeft`, `testLeavingThroughTheExitIsNotExhaustion` |
| Lose: any character exhausted (once door 2 is opened) | done | placements `lostIfExhausted: ["any"]`, `lostIfExhaustedOnceRevealed: "e1a"` → `exhaustionLoss` |
| Section 1: Stone Golems and Ancient Artilleries of L1a not set up until a character ends a turn on plate (b), then spawned | done | the scenario data's room 2 still lists only the Living Corpses and Living Spirits; placements `rules[0]` (`once`, `when: [{lock: 0}]`) sets the rest up (`placed: true`) the moment the plate lock is released as a turn ends on (b) (`updateLocks(turnEnded:)`): two normal Ancient Artilleries at c, one more at d for 3–4 characters and at e for 4, a Stone Golem at f (normal, elite for 4) and at g (normal, elite for 3–4); the letters c–g on `l1a` are written for this rule and aren't the book's; `ScenarioSpecialRuleTests.testTheTombsGuardiansWakeWithThePlate` |
| Section 1: door 2 locked until a character has ended a turn on plate (b) | done | placements lock `l1a`–`e1a`, `plate: ["b"]`, `unlocksOnly: true`; plate on `l1a` [2,3] |
| Section 2: at the end of every round each character on (a) is removed, with their summons | done | `letCharactersLeave` (called from `resolvePendingResult` as the round ends) → `leaveScenario`, which removes the character's piece and kills/removes their summons |

### 42 · Realm of the Voice
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all vocal chords | done | placements `goal.destroy: [1…6]`; six objectives placed along `l2a` column 0 |
| Six vocal chords, each 2+(L×C/2) HP rounded down | done | `objectives[0…5].health` `"[2+(LxC/2){$math.floor}]"` (bracket + `$math.floor` handled by the entity-value evaluator) |
| Chord 1 alive: all monsters +1 Attack | done | placements `effects[0]`: `on: "monsters"`, `whileStanding: 1`, `attack: 1` → `scenarioAttackBonus` (`BoardCoordinator+Effects`) added in `performAttack` while objective 1 stands; the scenario data's own rule is still only a note; `ScenarioSpecialRuleTests.testEachVocalChordHasItsPenalty` |
| Chord 2 alive: all monsters gain Advantage | done | placements `effects[1]`: `on: "monsters"`, `whileStanding: 2`, `advantage: true` → `scenarioGivesAdvantage` in `performAttack`; `testEachVocalChordHasItsPenalty` |
| Chord 3 alive: all monsters heal 1 at the start of their turns | done | placements `rules[0]`: `present` Vocal Cord 3, `alwaysApplyTurn: "turn"`, `heal` 1 on every monster → `ScenarioRulesManager.evaluateTurnRules(.turnStart, …)`, now called for each monster in `MonsterTurnController`; `testEachVocalChordHasItsPenalty` |
| Chord 4 alive: characters and summons suffer 1 damage at the start of their turns | done | placements `rules[1]`: `present` Vocal Cord 4, `alwaysApplyTurn: "turn"`, `damage` 1 on `characterWithSummon` → `evaluateTurnRules(.turnStart, …)` for characters (`continueCharacterTurn`: queued in `ruleDamageDue` and suffered, or negated with a card, before the turn is played) and for summons (`SummonTurnController`); `testEachVocalChordHasItsPenalty`, `ScenarioReauditTests.testTheFourthChordHurtsAsTheTurnStarts`, `testTheFourthChordsDamageCanBeNegatedBeforeTheTurn` |
| Chord 5 alive: characters and summons gain Disadvantage | done | placements `effects[2]`: `on: "party"` (characters and their summons), `whileStanding: 5`, `disadvantage: true` → `scenarioGivesDisadvantage` in `performAttack`, shown in the attack preview; `testEachVocalChordHasItsPenalty` |
| Chord 6 alive: characters and summons −1 Attack | done | placements `effects[3]`: `on: "party"`, `whileStanding: 6`, `attack: -1` → `scenarioAttackBonus` in `performAttack`, `expectedDamage` and the attack preview; `testEachVocalChordHasItsPenalty` |

### 43 · Drake Nest
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill 4×C drakes | done | placements `goal.killCount` `{"count": "4xC", "of": ["rending-drake", "spitting-drake"]}`, counted from `scenario.killCounts` |

### 44 · Tribal Assault
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the captives) | done | placements goal has only `text`, so the default in `checkVictoryDefeat` applies: every enemy dead, every room revealed |
| Lose: any captive Orchid is killed | done | placements goal `lostAt: {"2": 1}` → `goalLost`; a captive freed is not one killed (`BoardCoordinator.freedTag`); `ScenarioSpecialRuleTests.testACaptiveKilledLosesTribalAssaultAndOneFreedDoesNot` |
| Redthorn (b): 6+(3×L) HP | done | `objectives[0].health` `"6+(3xL)"`; placed on `b1b` [0,2] |
| Redthorn: ally of the characters, enemy of all monsters | done | `escort: true` → player side in `isPlayerSide`; in `MonsterAI.gatherEnemies` |
| Redthorn acts on initiative 01: Move 3, Attack 3, Range 3 | done | `objectives[0]` `initiative: 1`, `actions` move 3 / attack 3 with range 3 → `EscortTurnController` / `EscortAI` |
| Redthorn draws from whichever attack modifier deck the players choose | done | placements `drawsFromACharacter: [1]` → as he attacks, `EscortTurnController` asks whose deck (`chooseFigure`, the characters on the board) and draws from it; headless play takes the first character's. `ScenarioSpecialRuleTests.testRedthornDrawsFromTheDeckThePlayersChoose` |
| Redthorn adds +1 Attack for each captive freed | done | placements `forgo: [{"objective": 2, "strengthens": 1}]` → `BoardCoordinator.free` raises his Attack by 1 with each captive freed; `testACharacterBesideACaptiveGivesUpAnActionToFreeIt` |
| Captive Orchids (a): nine, 4+(2×L) HP each | done | `objectives[1]` `"4+(2xL)"`; rooms list 5+1+2+1 = 9; placed on `m1b` ×5, `l1b`, `b4a` ×2, `b3a` |
| Captives cannot be healed | done | placements `protect: [2]` → not an escort, so `isScenery`: `areAllies` is false and no heal can target them |
| Captives are not allies of the characters; enemies of all monsters | done | `isProtected` → player side for `areEnemies`, in `MonsterAI.gatherEnemies` (`container.isProtected && maxHealth > 0`) |
| Captives: initiative 99 for monster focusing | done | `MonsterAI.enemyInitiative` returns 99.5 for a non-escort objective |
| A character may lose one card from hand to negate one source of damage to a captive | done | placements `saves: [{"objective": 2}]` → `BoardCoordinator.promptSave` in `resolveDamage`: as a captive is about to suffer, the party is asked on `SaveChoiceSheet` and a card from any hand spares it, as often as there are cards; `ScenarioSpecialRuleTests.testACaptiveIsSparedAsOftenAsThereAreCards` |
| A character adjacent to a captive may forgo an action (discard a card) to free it | done | placements `forgo` → `PlayerTurnController.forgoTargets` / `forgoAction(toFree:)`: offered beside the basic action ("Free Captive Orchid 3") for a half not yet begun; the half's abilities are passed over, its card discarded (never lost, no experience) and the captive leaves the map; `testACharacterBesideACaptiveGivesUpAnActionToFreeIt` |

### 45 · Rebel Swamp
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all totems (a) | done | placements `goal.destroy: [1]`; six placed (`g1a`, `m1b` ×2, `f1b` ×2, `d1b`) |
| Setup: each character adds 2 "-1" cards | done | scenario `rules[0]`: `amAdd` `minus1:2` at `R == 1`, `start` → `ScenarioRulesManager.applyAmAdd` (the data's three was corrected to the book's two); `ScenarioSpecialRuleTests.testSetupCardCountsAreTheBooks` |
| Six totems, each 1+C+L HP | done | `objectives[0]` `"1+C+L"`, `count: 6`, one per room mention |
| Any monster within two hexes of a totem performs Heal 2, Self at the start of its turn | done | placements `rules[0]`: `alwaysApplyTurn: "turn"`, `heal` 2 on monsters picked by `near: {objective: "Totem", range: 2}` → `evaluateTurnRules(.turnStart, …)` in `MonsterTurnController`; a Heal like any other (on a poisoned monster it only removes the Poison), and a destroyed totem no longer counts; the brief says it (`notes`); `ScenarioSpecialRuleTests.testTotemsHealTheMonstersNearThem` |

### 46 · Nightmare Peak
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Winged Horror | done | placements `goal.kill: ["winged-horror"]` (room 3 must be revealed) |
| Boss Special 1: after it attacks, every egg is destroyed and becomes a normal Night Demon | done | `MonsterTurnController` reads special 1's text ("Hatch eggs"), makes its two attacks (all adjacent enemies at −1, then +0 at range 3), then calls `hatchEggs` (`BoardCoordinator+Bosses`): every egg is removed and a normal Night Demon is spawned on its hex; `ScenarioSpecialRuleTests.testTheWingedHorrorsEggs` |
| Boss Special 2: after its attacks it summons C eggs (numbered tokens, 2+(L/2) HP rounded up, initiative 99 for summon focusing) | done | `MonsterTurnController` reads special 2's text ("Summon [C] eggs"), performs Move −1 and Attack +0, then `layEggs(by:count:)` with the character count: each egg is an "Egg" objective with 2+(L+1)/2 hit points and initiative 99, an enemy the party and its summons can attack (`MonsterAI.enemyInitiative` gives 99.5), placed on a free hex beside the Horror (the first in hex order, not the one nearest an enemy); `testTheWingedHorrorsEggs` |

### 47 · Lair of the Unseeing Eye
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Sightless Eye | done | placements `goal.kill: ["the-sightless-eye"]` |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| Section 1: at the end of each round every character and summon still on the J tile suffers 3+L damage | done | placements `rules[0]`: `round: "true"` (round end), `requiredRooms: [2]`, `damage` `3+L` on `characterWithSummon` picked by `tile: "j1a"` → `ScenarioRulesManager` (a character's damage is queued in `ruleDamageDue`, a summon's suffered at once); nothing before door 1 is open; the brief says it (`notes`); `ScenarioSpecialRuleTests.testTheFirstCaveOfTheLairHurtsThoseWhoStay` |
| Section 1: the Sightless Eye cannot be forced to move or have its position changed | partial | `the-sightless-eye.json` lists `pull`/`push` in `immunities`, and `performPushPull` now returns for a target whose `immunities` hold the push or pull ("can't be pushed"); `ScenarioSpecialRuleTests.testAnImmovableBossIsNotPushed`. A Push or Pull printed as its own ability, made after the attack, goes through `beginStandalonePushPull` → `beginPushPull`, which has no such check (engine audit N17), so that one would still move it |
| Boss Special 1: before attacking, summons one Deep Terror — normal (2 characters), elite (3–4) | done | special 1: `summon` deep-terror `player2: normal, player3/4: elite`, then the area attack → `performSummon` → `summonMonster` (adjacent hex, doesn't act this round) |
| Boss Special 2: before attacking, summons one Deep Terror — normal (2–3), elite (4) | done | special 2: `summon` deep-terror `player2/3: normal, player4: elite`, then the area attack |

### 48 · Shadow Weald
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Dark Rider | done | placements `goal.kill: ["dark-rider"]` |
| Setup: all characters start with Muddle | done | scenario `rules[0]`: `gainCondition` `muddle` at `R == 1`, `start` |
| Setup: the Dark Rider is not placed on the map at the start | done | placements `cycles["dark-rider"].appears: true` → `comesAndGoes`: its entity is created with room 1, but `unplacedMonsterEntities` leaves out a type that comes and goes, so `placeRevealedMonsters` never stands it: it has no piece at setup; `ScenarioSpecialRuleTests.testTheDarkRiderComesAndGoes` |
| The Dark Rider is removed from the map immediately after any melee attack | done | placements `cycles["dark-rider"].leavesAfterMelee: true` → `leaveAfterMeleeAttack` (`BoardCoordinator+Bosses`), called from `MonsterTurnController` after each attack that isn't ranged; off the map it isn't dead; `testTheDarkRiderComesAndGoes` |
| Not on the map at the start of its turn: appears on a marked hex, a→f in order, then acts | done | placements `cycles["dark-rider"].letters: [a…f]` with the six hexes written on `l3a` (a, c, e) and `l1b` (b, d, f) → `appearIfOffMap` as its turn starts in `MonsterTurnController` → `takeNextCycleHex` (the next letter, a again after f; the closest unoccupied hex if a figure stands there), then it plays its card; `testTheDarkRiderComesAndGoes` |
| Boss Special 2: between moving and attacking, summons 1 normal Forest Imp (2 characters) or 2 (3–4) | done | `dark-rider.json` special 2: Move +0, `summon` forest-imp (`player2: normal`; `player3/4: normal` with `count: 2`), Attack −1; `summoned(forPlayerCount:)` now brings only the entry for the party's size and keeps its count — one imp for 2 characters, two for 3–4; `MonsterSummonDataTests.testTheCountIsKept`, `testABossSummonsWhatItsPlayerCountSays` |

### 49 · Rebel's Stand
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Siege Cannon | done | placements `goal.kill: ["siege-cannon"]`; it stands on the map's Ancient Artillery position in L3a |
| Siege Cannon has H×2 HP (H = elite Ancient Artillery's hit points) | done | `siege-cannon.json` health per level is exactly twice the elite artillery's (14/18/…/40 against 7/9/…/20) |
| Siege Cannon does not act; initiative 99 for summon focusing | missing | unchanged: it is an ordinary boss with `deck: "ancient-artillery"`, so it draws Ancient Artillery cards, acts at their initiative and shoots (Attack 3–5, Range 5–7), and is focused at that initiative. Only the FAQ's immunity to push and pull is in (`siege-cannon.json` `immunities`; `ScenarioReauditTests.testTheCarriersAndTheCannonCantBeForcedToMove`). `TODO.md`: "Monsters that don't act as their cards say" |
| Each round the City Archer closest to the artillery does not act but performs Move 3 toward a non-b hex beside it | missing | the scenario JSON has no `rules` and #49's placements have only the goal; no code; archers take their normal turns. Needs the b letters and a turn override for the nearest archer (something like `march`) |
| If that archer is then adjacent, the cannon fires: characters and summons in the b hexes, the columns above them and all of G suffer an elite artillery's Attack | missing | no rule, no code, no b letters in placements (`"49"` has empty `tiles`) |
| No City Archers on the map at the end of a round: one normal City Archer spawns at (a) | missing | no rule in the scenario data or the placements, and no letter a written; could be a placements rule (round end, no City Archer present, spawn at a) once the hex is written |

### 50 · Ghost Fortress
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles | done | placements `goal.loot: "goal"`; the four tiles carry treasure id `goal` in the map data |
| Setup: two starting rooms; no more than half the characters (rounded up) may enter from the same room | done | placements `splitStart: true` → `freeStartingHexes(for:)` leaves out the starting hexes of a room that already holds half the party (rounded up), and `placeCharacter` refuses them ("No more than half the party may start in the same room"); a character already placed may still change hexes within their room; the brief says it (`notes`); `ScenarioSpecialRuleTests.testNoMoreThanHalfThePartyStartsInOneRoom` |
| Treasure tiles can only be looted with a Loot action, never by end-of-turn looting | done | placements `lootActionOnly: true` → `goalTreasureNeedsLootAction`: `lootHexes` passes over a goal tile unless `byLootAction` (only `collectLootInRange`, a Loot ability, sets it), so ending a turn on one or walking over it leaves it; the brief says so; `ScenarioGoalTests.testGoalTreasureThatNeedsALootAction` (played on #30, the same flag) |

### 51 · The Void
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Gloom | done | placements `goal.kill: ["the-gloom"]` |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| Each character and character summon suffers 2 damage at the end of each of their turns | done | scenario `rules[1]` (`alwaysApplyTurn: "after"`, `characterWithSummon`, damage 2) → `evaluateTurnRules(.turnEnd, …)` for characters in `advanceToNextFigure` (the damage in `ruleDamageDue` is now suffered there, before the next figure acts) and for each summon as its own turn ends in `SummonTurnController`; `ScenarioSpecialRuleTests.testTheVoidHurtsAsEachTurnEnds` |
| Dark pit obstacles cannot be destroyed | done | placements `indestructible.subTypes: ["dark-pit"]` → `isDestructibleObstacle` (see #39); `ScenarioReauditTests.testWhatTheScenarioSaysCantBeDestroyedIsnt` |
| Boss Special 2: before attacking, the Gloom jumps to a marked hex, a→b→c in order | done | placements `cycles["the-gloom"].letters: [a, b, c]` with the hexes written on `d2a`, `d1a` and `m1a`; `MonsterTurnController` now performs the special's `teleport` → `jumpAlongCycle` → `takeNextCycleHex` (a again after c; the closest free hex if the marked one is taken), then looks for its focus anew and makes the Attack +1, Range 5; `ScenarioSpecialRuleTests.testTheGloomJumpsRoundItsThreeHexes` |

### 52 · Noxious Cellar
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: every character loots one treasure tile | done | placements `goal.loot: "each"`; `mayLootGoalTreasure` lets each character loot only one; `goalLooters` tracks who has |
| Lose: a character is exhausted before looting a treasure tile | done | placements `lostIfExhausted: ["beforeLoot"]` → `exhaustionLoss` |
| Setup: each character adds 2 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:2` at `R == 1`, `start` → `ScenarioRulesManager.applyAmAdd` (the data's three was corrected to the book's two); `ScenarioSpecialRuleTests.testSetupCardCountsAreTheBooks` |
| Setup: characters may only start in sections of the center room that contain monsters | missing | unchanged: the four starting hexes of M1a are all offered whatever the character count (`freeStartingHexes` only knows `splitStart`); nothing ties a starting hex to monsters being in its section. Needs the sections written as data |
| Center-room obstacles cannot be destroyed or moved through in any way, and block line of sight for ranged abilities | partial | can't be destroyed: placements `indestructible.tiles: ["m1a"]` → `isDestructibleObstacle` (`ScenarioReauditTests.testWhatTheScenarioSaysCantBeDestroyedIsnt`). Not enforced: a jumping or flying figure still crosses them as it does any obstacle (`Pathfinder`), and they don't block line of sight (`LineOfSight` counts only walls) |
| Treasure tiles are looted only by a Loot action, or by an adjacent character forgoing a bottom action; never at end of turn | done | placements `lootActionOnly: true` → a goal tile is taken only by a Loot ability (`lootHexes` with `byLootAction`), never by ending a turn on it or walking over it (`ScenarioGoalTests.testGoalTreasureThatNeedsALootAction`); placements `forgo: [{"treasure": true, "bottom": true}]` → "Loot the Treasure" beside the basic Move for a character next to a goal tile who has yet to loot one: the bottom action is given up, its card discarded, the tile looted (`ScenarioSpecialRuleTests.testATreasureBesideACharacterIsLootedForABottomActionGivenUp`) |

### 53 · Crypt Basement
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: survive ten rounds (complete at the end of round 10) | done | scenario `rules[5]`: `R == 10` (end of round) → `finish: "won"`; `hasOwnWinCondition` switches the kill-all default off |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| All doors locked; they open by themselves at the start of rounds 2 (a), 4 (b), 6 (c), 8 (d) | done | placements `locks` `m1a`–`j1a`/`j2a`/`d2a`/`d1a` with `afterRound` 1/3/5/7 (both doors of a pair), and scenario `rules[1…4]` open rooms 2/4/3/5 at the start of rounds 2/4/6/8. The lock's key turns in `updateLocks(roundEnded: true)`, so the door opens as the previous round ends, before cards are chosen |

### 54 · Palace of Ice
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: the Seeker of Xorn ends a turn adjacent to the altar (a) with the staff fully charged | done | placements `n1a` marker a [0,3] (the altar, read off p.71) and goal `reach: {"marker": "a", "adjacent": true, "holding": "Staff of Xorn", "charged": true}`: the staff's holder ending a turn beside the altar once the staff is full. `CarriedThingTests.testTheStaffOfXornIsChargedByItsHolderAndPlacedOnTheAltar` |
| Lose: the Seeker of Xorn becomes exhausted | done | placements `carried: [{"name": "Staff of Xorn", "start": "choose", "onlyQuest": "510", "item": "gh-114", …, "lostWithHolder": true}]`: the character on the Seeker of Xorn quest holds the staff (else the one bearing the item, else the players choose), and the scenario is lost with them (`carriedLoss`). Same test |
| All Cave Bears add Poison to all their attacks | done | scenario `rules[0]` `statEffects` on `cave-bear` (`actions`: condition poison) → `MonsterManager.applyScenarioStatEffect` sets `additionalStatActions`, read by `GameMonster.attackStat` and applied in `MonsterAbility.attack` |
| Section 1: only the character equipped with the Staff of Xorn can damage the Harrower Infesters | done | `soleHarmTo: ["harrower-infester"]` → `carriedWard` in `sufferDamage`: damage from anyone or anything but the staff's holder does nothing to an Infester; the rest of an attack (its conditions) still lands. Same test |
| Section 1: each point of damage to an Infester puts a token on the staff; fully charged at 2×C×(L+1) | done | `charge: "2xCx(L+1)"` → `chargeCarried`: each point the holder takes off an Infester is a point of charge (`BoardState.carriedCharge`, saved with the board), never more than full; the party panel shows "Holds the Staff of Xorn · 3 of 8". Same test |

### 55 · Foggy Thicket
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot the treasure tile in the third room | missing | unchanged: the scenario has no rooms and there is no `ScenarioMaps/55.json`; `GameManager.enterBoard` returns when there is no map, so no board ever starts (the setup list shows "No map"). Needs random dungeons (open in `TODO.md`: "Random dungeon mode") |
| Setup: each character adds 3 "-1" cards | partial | scenario `rules[0]` (`amAdd` `minus1:3`) is in the data and would be applied at the start of round 1 like #53's curses, but no round is ever played on a board |
| No fixed map: a random dungeon from a modified dungeon deck | missing | `rules[1].randomDungeon` is decoded (`ScenarioRule.randomDungeon`, `RandomDungeonRule`) and read by nothing |
| Monster cards used: only Mangy, Wild, Scaled, Cutthroat, Tribal, Infected | missing | `randomDungeon.monsterCards` (554, 558, 560, 564, 567, 571) unused |
| Room cards used: only Trail, Encampment, Clearing, Road, Cabin, Crossroads | missing | `randomDungeon.dungeonCards` unused |
| Penalties: minor in the second room, major in the third | missing | not in the data, no code |
| Third room: the "12" hex holds a treasure tile, lootable only with a Loot action | missing | no code (the Loot-action-only half exists as placements `lootActionOnly`, but there is no room to put the tile in) |

### 56 · Bandit's Wood
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and keep at least one captive Orchid alive) | done | no goal written, so the default: every enemy dead with every room revealed; the "at least one" half is the loss rule below |
| Lose: all three captive Orchids are killed | done | scenario `rules[0]`: `always`, `once`, `requiredRooms: [4]`, objective "Captive Orchid" marker a `dead` → `finish: "lost"` |
| Captive Orchids (a): three, 4+(2×L) HP each | done | `objectives[0]` `"4+(2xL)"`; room 4 lists three; placed on `m1b` [0,1], [1,0], [2,0] |
| Captives are allies of the characters and enemies of all monsters | done | `escort: true` → player side; monsters focus them (`MonsterAI.gatherEnemies`) |
| Captives act on initiative 50: Move 3, Attack 3 | done | `initiative: 50`, `actions` move 3 / attack 3 → `EscortTurnController` (each living Orchid in turn) |
| Captives draw from whichever character attack modifier deck the players choose | done | placements `drawsFromACharacter: [1]` → asked as each Orchid attacks, as for Redthorn (#44); the same code and test |

### 57 · Investigation
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Infiltrator | done | placements `goal.kill: ["infiltrator"]` |
| Section 2: when the elite City Guard of the main barracks dies, replace him with the Infiltrator | done | placements `dropRules: [0]` and `rules[0]`: the same trigger (`requiredRooms: [3]`, city-guard marker "2" `dead`, `once`) with the spawn `infiltrator:+1` (boss) at `marker: "2"` — the letter the dead guard carried, so `spawnHex(forMarker:)` gives the hex he fell on (`fallenFigure`, set in `handleDeath`); `testTheInfiltratorTakesTheFallenGuardsPlace` |
| The Infiltrator is an elite Harrower Infester one level above the scenario level (maximum 7) | done | `infiltrator.json` stats equal the elite Harrower Infester's at each level and it uses that deck; `infiltrator:+1` → `MonsterNameSpec.level(forScenarioLevel:)`, clamped to 0…7 |
| Section 3: spawn at (a) 2 normal City Guards (2 characters), 1 normal + 1 elite (3), 2 elite (4) | done | scenario `rules[1]`: `requiredRooms: [4]`, three spawn entries by exact character count, `marker: "a"`; letter a on `f1b` [1,1] → `spawnHex(forMarker:)` |

### 58 · Bloody Shack
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Harvester | done | placements goal `kill: ["the-harvester"]` (`goalMet`; needs room 3 revealed and the boss dead) |
| Setup: two starting rooms, at most half the characters (rounded up) in the same one | done | placements `splitStart: true` → `freeStartingHexes(for:)` leaves out the hexes of a room that already holds half the party (rounded up) and `placeCharacter` refuses them; `testNoMoreThanHalfThePartyStartsInOneRoom` |
| Section 1: only the character on the "Vengeance" quest may loot the treasure tile | done | placements `carried: [{"name": "Occult Dagger", "treasure": "goal", "onlyQuest": "526", "pierce": 4, "against": "the-harvester"}]` → `mayLootTreasure`: with a character on quest 526 in the party the tile is theirs alone (anyone's when no one is). `CarriedThingTests.testOnlyTheVengeanceCharacterTakesTheDaggerAndItPiercesTheHarvester`, `testWithNoOneOnTheQuestAnyoneTakesTheDagger` |
| Section 1: looting it gives that character the Occult Dagger | done | `noteTreasureLooted` → the looter holds it (`BoardState.carriedBy`); it doesn't change hands. Same test |
| Section 2: the City Guard is one level above the scenario level (max 7) and is the Harvester | done | `58.json` room 3 `the-harvester:+1` type boss; `MonsterNameSpec.level` clamps to 7; `monster/the-harvester.json` carries the elite City Guard's stats |
| Each bone pile (a) has L+(2×C) HP | done | `58.json` objectives `health: "L+(2xC)"`, count 4, room 3 `objectives: [1,1,1,1]`; placed on the four nests by placements tile `b1a` |
| Harvester gains Shield 1 for each bone pile on the map | done | placements `effects`: `on: "the-harvester"`, `shield: "X"`, `per: {"objective": 1}` → `scenarioShield(of:)` added in `shield(of:)` (`BoardCoordinator+Effects`), in the attack preview too; `testBonePilesShieldAndHealTheHarvester` |
| Harvester heals C−1 at the end of each round for each bone pile | done | placements `rules[0]`: end of round, `requiredRooms: [3]`, Bone Pile `present` → the Harvester `heal` `C-1`, `times: "F"` (one heal for each pile standing, so Poison stops only the first); `testBonePilesShieldAndHealTheHarvester`, `testEachBonePileHealsTheHarvesterOnItsOwn` |
| The Occult Dagger's holder adds PIERCE 4 to attacks on the Harvester | done | `carriedPierce` added to the attack in `performAttack`, for the holder against the Harvester only. Same test |

### 59 · Forgotten Grove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot the treasure tile | done | placements goal `enemies: "all"`, `loot: "goal"` |
| The treasure tile is looted only with a Loot action, never at end of turn | done | placements `lootActionOnly: true` → `goalTreasureNeedsLootAction`; `lootHexes` skips the goal chest unless `byLootAction` (only `collectLootInRange` passes it), so neither the end of a turn nor Swift Bow's loot-every-hex-entered (`moveAlong`) picks it up; `testGoalTreasureThatNeedsALootAction` (on #30, the same key) |

### 60 · Alchemy Lab
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles, then every character back on an entrance hex | done | placements goal `loot: "goal"`, `escape: {"start": true}` (starting hexes, judged as a turn or round ends) |
| Lose: not complete by the end of round 12 | done | `60.json` rule 1 `round: "R == 12"`, `finish: "lost"` (end-of-round rule); a win already pending that round is kept |
| Lose: a character exhausted before all treasure is looted, or off an entrance hex | done | placements `lostIfExhausted: ["beforeLoot", "offExit"]` (`exhaustionLoss`) |
| From the start of round 7, every round all figures suffer 2 damage (scenario effect) | done | `60.json` rule 0 `round: "R > 6"`, `start: true`, identifier `type: "all"`, `damage 2`; characters take it through `afterRuleDamage` (may lose cards), others through `changeHealth` + `sweepDeadFigures`; the ignore-negative-scenario-effects perk is honoured |

### 61 · Fading Lighthouse
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles | done | placements goal `loot: "goal"` (four goal chests) |
| Odd rounds: only Group 1 (Oozes, Giant Vipers) activates | done | placements `inactive`: flame-demon and frost-demon `rounds: "odd"` → `ScenarioPlacements.inactiveMonsters(round:)` / `MonsterAI.inactiveMonsters`: no card drawn for them (`RoundManager`), no place in the order (`buildTurnOrderAndStart`), no turn (`MonsterTurnController`). The demons are enemies again (`isAllyFaction` is `isAlly` only). `testTheLighthousesGroupsTakeRoundsAbout`, `testOnlyOneGroupActsEachRoundAtTheLighthouse`, `testTheLighthousesDemonsAreEnemies` |
| The inactive group is unaffected by all abilities | done | `isInactive` → `isUntouchable`: an inactive monster is no one's enemy and no one's ally (`areEnemies`, `areAllies`), so it isn't targeted, attacked, healed or helped, and `gatherEnemies` / `PlayerSideAI.hostileMonsters` leave it out; drawn hollow. `testTheLighthousesGroupsTakeRoundsAbout` |
| Any figure may move through an inactive monster's hex but not end there | done | an inactive monster's hex is not an enemy's: `movementSets` puts it with the allies' hexes — moved through, not stopped on — and monsters' paths do the same since `gatherEnemies` leaves it out; `testTheLighthousesGroupsTakeRoundsAbout` |
| Even rounds: the opposite (Group 2 acts, Group 1 doesn't) | done | placements `inactive`: ooze and giant-viper `rounds: "even"`, as the odd-round row; between rounds it is the round to come that counts. `testOnlyOneGroupActsEachRoundAtTheLighthouse` |
| Treasure tiles are looted only with a Loot action | done | placements `lootActionOnly: true` (see #59) |

### 62 · Pit of Souls
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Hungry Soul | done | placements goal `kill: ["hungry-soul"]` |
| Every round start: one Living Bones at (a) and one at (b): normal/normal (2), elite/normal (3), elite/elite (4) | done | `62.json` rule 0 `round: "true"`, `start: true`; (a) p2 normal / p3 elite / p4 elite, (b) normal / normal / elite; markers a, b on tile `m1a` |
| When ten Living Bones have been killed, read Section 1 | done | placements `rules`: `killed` living-bones ≥ 10, `always`, `once` (merged in `EditionDataStore`; `killCount` reads `scenario.killCounts`) |
| Section 1: an elite Living Bones spawns at (c) as the Hungry Soul | done | that rule spawns `hungry-soul` (boss, living-bones deck, elite Living Bones' move/target) at marker c on `b2b` |
| Its HP is (H×C)/2 rounded up | done | `monster/hungry-soul.json` health `"[(6xC)/2{$math.ceil}]"` … `"[(14xC)/2{$math.ceil}]"` → `ScenarioExpression` rounds up; `MonsterDataTests.testHalvedBossHealth_roundsUp` |
| Extra Shield 5 on top of its regular Shield | done | stat card Shield 5/6/6/6/6/7/7/7 for levels 0–7: 5 plus an elite Living Bones' own 0/1/1/1/1/2/2/2; `testTheHungrySoulsShieldFallsWithTheBonesAroundIt` checks it against the elite's card |
| +2 Attack on all its attacks | done | stat attack is the elite's +2 at every level (4/4/5/5/6/6/6/6 against 2/2/3/3/4/4/4/4) |
| The round-start spawns continue after Section 1 | done | rule 0 is never disabled |
| Its Shield drops by 1 for each other Living Bones on the map (minimum 0) | done | placements `effects`: `on: "hungry-soul"`, `shield: "0-X"`, `per: {"monster": "living-bones"}` → `scenarioShield(of:)`; `shield(of:)` never goes below none; `testTheHungrySoulsShieldFallsWithTheBonesAroundIt` |

### 63 · Magma Pit
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal in `checkVictoryDefeat` (no placements entry) |
| Setup: all characters start with WOUND (scenario effect) | done | `63.json` rule 0 `round: "R == 1"`, `start: true`, `gainCondition wound`, `scenarioEffect` |

### 64 · Underwater Lagoon
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal (no rules, no placements entry) |

### 65 · Sulfur Mine
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot all treasure tiles | done | placements goal `enemies: "all"`, `loot: "goal"` (five goal chests) |
| Setup: four CURSE cards in each character's deck (scenario effect) | done | `65.json` rule 0 `round: "R == 1"`, `start: true`, `amAdd "curse:4"` (`applyAmAdd`, capped at ten curses by the deck) |

### 66 · Clockwork Cove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: a character ends their turn on pressure plate (e) | done | placements goal `reach: {"marker": "e"}`, plate drawn through `plates: ["e"]` |
| Door 1 is locked; it opens when a character occupies plate (a) at the end of their turn | done | lock `j1b`–`c1a` `held: ["a","b"]` with `firstAtTurnEnd: true`: `updateLocks` opens it the first time only with `turnEnded` (walking over the plate opens nothing); after that it is held like the others; `testTheCovesFirstDoorOpensAsATurnEndsOnItsPlate` |
| Section 1: doors 1, f, g, h stay open only while a corresponding plate is occupied; a door closes when its last occupied plate is left | done | four `held` locks; `updateLocks` opens/shuts, `Pathfinder` treats `shutDoors` as closed |
| A figure in a door as it closes suffers trap damage and moves to the nearest unoccupied hex | done | `shutDoor`: `levelManager.trap()` damage, then `nearestEmptyHex`; a character's goes through `ruleDamageDue`, so cards may be lost to negate it, others through `sufferDamage`; `testDamageFromAClosingDoorCanBeNegated`, `testADoorHeldOpenByAPlate` (both on #67's door, the same code) |
| Plate (a) ↔ door 1; (b) ↔ 1 and f; (c) ↔ f and g; (d) ↔ g and h | done | `held` lists a,b / b,c / c,d / d on `j1b–c1a`, `c1a–d1a`, `d1a–d2a`, `d2a–c2b` |
| Doors i and j are locked and open permanently when a character ends a turn on plate (d) | done | locks `d1a–a1a` and `d2a–a2a` with `plate: ["d"]` |

### 67 · Arcane Library
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Arcane Golem | done | placements goal `kill: ["stone-golem"]` (the only Stone Golem is in room 3) |
| Door 2 is locked and stays open only while a character occupies a plate (a) | done | lock `a2a–m1a` `held: ["a"]`; markers a on `g1b` and `m1a` (`testADoorHeldOpenByAPlate`) |
| A figure in the door as it closes suffers trap damage and moves to the nearest unoccupied hex | done | `shutDoor` as in #66: trap damage (a character may lose cards to negate it, through `ruleDamageDue`) and out to the nearest empty hex; `testADoorHeldOpenByAPlate`, `testDamageFromAClosingDoorCanBeNegated` |
| Section 2: the elite Stone Golem is one level above the scenario level (max 7) and is the Arcane Golem | done | room 3 `stone-golem:+1` elite; rule 0 statEffect `name: "arcane-golem"` |
| It has H×C HP (H = an elite Stone Golem's regular HP) | done | rule 0 statEffect `health: "HxC"`, `requiredRooms: [3]` (`applyScenarioStatEffect`) |
| It cannot enter or pass through door 2 | missing | still only in the scenario rule's note text. Shut, the door stops it like anyone; held open by a plate, nothing in `MonsterAI` / `Pathfinder` keeps the golem from walking through, nor a push or pull from moving it there. Needs a hex barred to one monster type |

### 68 · Toxic Moor
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the tree — see Lose) | done | default goal; the placements goal has `text` and the loss below, nothing to win by |
| Lose: the tree is destroyed | done | placements goal `lostAt: {"1": 1}` → `goalLost`; `testTheTreeOfToxicMoor` |
| Setup: all characters start with POISON (scenario effect) | done | `68.json` rule 0 `R == 1`, `start`, `gainCondition poison` |
| Setup: the tree (a) is set up at the start | done | room 1 (initial) lists objective 1; placements tile `b1b` puts it on the tree-3 obstacle, which the map data draws from the start |
| Tree: 17 HP | done | `68.json` objectives `health: 17` |
| It suffers 2 damage at the end of every round, even before its room is revealed | done | placements `dropRules: [1]` and `rules[0]`: end of round, `when: [{"unrevealed": 2}]` (the M tile's room not yet open), `damage 2` on objective Tree marker a; `testTheTreeOfToxicMoor` |
| Once its room is revealed, no damage in a round when no Rending Drake is on the M tile | done | placements `rules[1]`: end of round, `requiredRooms: [2]`, a rending-drake `present` with identifier `tile: "m1b"` → `damage 2` on the tree; with none on the tile as the round ends, nothing; `testTheTreeOfToxicMoor` |
| Once revealed it can be healed like an ally; no other ability can affect it | partial | placements `sheltered: [1]` → `isSheltered`: no monster focuses or attacks it (`gatherEnemies`), it is no one's enemy (`isUntouchable`), and it is healed as an ally (`testTheTreeOfToxicMoor`). But being an ally in `alliesInRange` and an escort, a character's other ally-targeted abilities still reach it — a condition given to allies (`beginConditionAction(onAllies:)`, `applyConditionToAllAllies`) lands on it — and "once revealed" isn't checked (before then only range and line of sight keep a heal from it) |
| A character or summon with POISON entering a water hex suffers trap damage | done | placements `water: {"hurtsThePoisoned": true}` → `waterHurtsOnEntering` in `moveAlong`: a poisoned character or summon entering a water hex on foot (not jumping or flying over) suffers `levelManager.trap()` through `sufferDamageWithMitigation`; monsters don't; `testWaterHurtsThePoisonedInToxicMoor` |
| A summon with POISON treats water hexes like traps | missing | a poisoned summon suffers the damage (row above) but doesn't avoid the water: `Pathfinder.isNegative` counts only traps and hazards, so `SummonAI` plans through it as plain difficult terrain. Needs water counted as a negative hex for a poisoned summon |

### 69 · Well of the Unfortunate
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: bring the doll to a hex adjacent to the well (a) | done | placements goal `reach: {"marker": "a", "adjacent": true, "enter": true, "holding": "doll"}`: the doll's holder entering a hex beside the well wins, even on the way past (`noteGoalHexesEntered`); anyone else there doesn't. `CarriedThingTests.testOnlyTheDollsHolderWinsAtTheWell`, `ScenarioReauditTests.testEnteringAHexBesideTheWellWins` |
| Setup: choose a character to hold the doll | done | placements `carried: [{"name": "doll", "start": "choose", "passes": true}]` → `assignCarriedAtSetup`: the players are asked who holds it as the scenario starts (headless: the first character); the party panel says who does. `testThePlayersChooseWhoHoldsTheDoll` |
| The doll changes hands only by another character's Loot action with the holder in range | done | `collectLootInRange` reaches a holder in the Loot's range and sight and `lootHexes` hands the thing over (a Loot with only the holder in range is a Loot performed); ending a turn beside the holder does nothing. `testTheDollChangesHandsByALootAction` |
| If the holder is exhausted the doll is dropped in their hex | done | `leaveScenario` → `dropCarried(of:)`: it lies in the hex they stood on (`BoardState.carriedLying`, saved with the board, drawn as a marked token) and whoever loots that hex holds it. `testAnExhaustedHoldersDollLiesWhereTheyStood` |
| Door 1 is locked; opens when a character ends a turn on plate (b) | done | lock `l3a–j1a` `plate: ["b"]`, marker b on `b1b` |
| Section 1: spawn at (c) 2 Scouts + 1 Shaman: normal/normal (2), elite/normal (3), elite/elite (4) | done | `69.json` rule 0 `requiredRooms: [3]`, `once`; scouts p2 normal / p3 elite / p4 elite ×2, shaman normal / normal / elite; marker c on `l3a` |
| Section 1: two damage traps appear at (d); a non-flying figure standing there springs one at once | done | placements `rules` (`requiredRooms: [3]`, `once`, `traps: ["d"]`; marker d = two hexes on `b1b`) → `ScenarioRulesManager.onPlaceTraps` → `placeScenarioTraps`: a damage trap (`levelManager.trap()`) on each free hex; a figure on foot standing on one springs it at once (a character through `ruleDamageDue`, so cards may be lost to negate it); `testTheWellsTrapsAppearWhenItsDoorOpens` |

### 70 · Chained Isle
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all demons | done | placements goal `kill: ["night-demon","wind-demon"]` |
| A normal Living Spirit spawns at the end of every round: (a) odd / (b) even (2); (a) odd, (a)+(b) even (3); (a)+(b) every round (4) | done | `70.json` rules 0 (`R % 2 == 1`) and 1 (`R % 2 == 0`), end-of-round; markers a on `l3a`, b on `l1b` |
| Living Spirits cannot be damaged in any way (conditions and other effects still apply) | done | placements `undamageable: ["living-spirit"]` → `isUndamageable`: `sufferDamage` does nothing to one, an attack's conditions still apply, and a Wound doesn't hurt it as its turn starts (`deferWoundDamage`); `testLivingSpiritsCantBeDamagedAndGoWithTheDemons`, `testAWoundDoesNotHurtALivingSpirit` |
| Each time a demon dies the players may remove one Living Spirit | done | placements `reprieve` (`killed: ["night-demon","wind-demon"]`, `removes: "living-spirit"`) → `grantReprieve` from `handleDeath` queues the death and `resolveReprieves` asks, once the blow is settled or as the turn ends: which spirit (the nearest to the killer first), or "Leave Them". The one chosen is banished, not counted as a kill. Headless play takes the nearest. `ScenarioSpecialRuleTests.testThePlayersChooseWhichLivingSpiritGoes`, `testLivingSpiritsCantBeDamagedAndGoWithTheDemons` |

### 71 · Windswept Highlands
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles, then every character on an exit hex (a) | done | placements goal `loot: "goal"`, `escape: {"marker": "a"}` (four hexes on `g2a`) |
| Lose: a character exhausted while not on an exit hex | done | placements `lostIfExhausted: ["offExit"]` |
| Wind: at the end of every round every character and summon is forced one hex (left, up, right, down in turn), in initiative order | done | placements `drift: {name: "wind", directions: [[NW, NE], [E], [SW, SE], [W]]}` (the book prints this map a quarter turn round: its left is up on ours) → `BoardCoordinator+Drift`: `driftToCome` as the round's turns are over, `driftAsTheRoundEnds` moves each character, a summon before its owner, by `moveAlong(.forced)` (a trap is sprung); with two hexes open the players tap one (`chooseHex`), with one of the two shut they may stay instead (FAQ); nowhere to go, no move. `DriftTests.testTheWindTurnsWithTheRounds`, `testThePlayersChooseBetweenTwoHexes`, `testTheWindGoesInInitiativeOrderAndIsStoppedByWhatIsInTheWay`, `testTheWindBlowsAFigureIntoATrap`, `testTheWindBlowsAsARoundOfPlayEnds`. (Waking a drake by ending this move beside it belongs to the rows below) |
| Spitting Drakes start asleep and do not act until woken | missing | no sleeping state is set (placements has no `inactive` entry for #71): the drakes act from round 1 |
| A drake wakes when attacked, damaged, given a negative condition, or when a character or summon ends a move adjacent to it | missing | no code; nothing is asleep to wake |
| Summons do not attack a sleeping drake unless directly controlled | missing | no code; summons focus on drakes like any enemy |
| A drake that wakes follows the rules for a newly spawned monster | missing | no code; nothing is asleep to wake |
| Doors b, c, d are locked and open on the first, second and third treasure tile looted | done | locks `h2b–a2b` `looted: 1`, `l3a–a3a` `looted: 2`, `h2b–g2a` `looted: 3` (`boardState.goalTreasuresLooted`; `testLootedTreasureOpensDoors`) |
| Escape is complete when every character stands on an exit hex or was exhausted on one | done | `goalMet` judges the characters still standing; exhaustion on an exit hex doesn't lose (`exhaustionLoss`) |

### 72 · Oozing Grove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all trees and kill all Oozes | done | placements goal `destroy: [1,2,3]`, `kill: ["ooze"]` |
| Trees (a), (b), (c): C×(3+L) HP each | done | `72.json` objectives `health: "Cx(3+L)"`; placed on the three tree obstacles |
| At the end of every round one tree summons an Ooze in the order a, b, c: normal (2), normal on odd / elite on even rounds (3), elite (4) | done | rules 0–5 `R % 6 == 1…0`, end-of-round; p3 normal on rules 0/2/4, elite on 1/3/5; the Ooze is put beside the tree that carries the letter (`spawnHex(forMarker:)`) |
| A destroyed tree keeps its place in the order and summons nothing | done | each rule requires its tree `present` |

### 73 · Rockslide Ridge
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot all treasure tiles | done | placements goal `enemies: "all"`, `loot: "goal"` (three goal chests on `e1b`) |
| Six boulders start at (a) and (b) and each row rolls 1, 2 or 3 hexes left at the end of every round, a different number per row, chosen by the players | missing | the six are fixed `boulder-1` obstacles in the map data (`ScenarioMaps/73.json`); `73.json` rule 0 is a note ("Roll boulders down.") and placements has no rule or letters (`tiles: {}`). It would need a rolling-boulder mechanic and a prompt for each row's distance |
| Boulders are unaffected by abilities and overlays and destroy obstacles in their way (traps stay) | missing | no boulder mechanic; the six boulders are ordinary obstacles a destroy-obstacle ability can remove (only `dark-pit` is in `indestructible`) |
| A figure a boulder moves onto suffers trap damage; if the boulder stops there the figure is forced one hex left | missing | no boulder mechanic |
| A boulder reaching the leftmost hex re-enters at (b) and keeps moving | missing | no boulder mechanic |
| Dark pit obstacles cannot be destroyed | done | placements `indestructible: {"subTypes": ["dark-pit"]}` → `isDestructibleObstacle` (asked by every destroy-obstacle ability); `testWhatTheScenarioSaysCantBeDestroyedIsnt` (#73's pits), `testNoAbilityDestroysADarkPit` |
| Section 1: the Inox on tile E cannot enter or pass through door 1 | missing | no movement restriction in placements or code: once door 1 is open the Inox of `e1b` walk through it like any monster. It would need a door (or tile) a monster type can't cross |

### 74 · Merchant Ship
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (keeping the ship afloat — see Lose) | done | default goal: every enemy dead with both doors open |
| Lose: a water tile must be added but the B tile is full | missing | water tiles aren't added, so nothing can fill; placements #74 has no `goal` and no loss |
| Setup: remove the water tiles at (d) for three characters | missing | the 12 water hexes of `b1a` are always there; marker d is written but unused |
| A water tile is added to the B tile at the end of every even round (2) or every round (3–4) | missing | `74.json` rule 0 (`R % 2 == 0 \|\| C > 2`) is a note only ("Add water tile."); no rising-water mechanic (it would need a prompt for where the tile goes) |
| A character picks up a water tile by looting and bails it by ending a turn on (e); one tile at a time | missing | marker e is written but unused; no carried-tile state |
| Doors 1 and 2 are locked and open at the end of rounds 3 and 6 | done | locks `g2b–i2b` `afterRound: 3`, `g2b–i1a` `afterRound: 6`, and rules 1/2 (`R == 3` → rooms [2], `R == 6` → rooms [3]) |
| Section 1: 1 normal Deep Terror at (a) (2); 1 elite at (a) (3); 2 normal at (b) (4) | done | rule 3 `requiredRooms: [2]`, `once`: marker a p2 normal / p3 elite, marker b p4 normal ×2 |
| Section 2: at (c) 2 normal Deep Terrors (2–3) or 2 elite (4) | done | rule 4 `requiredRooms: [3]`, `once`, count 2, marker c |

### 75 · Overgrown Graveyard
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: dig up all graves and kill the Bloated Regent | done | placements goal `destroy: [1,2,3]`, `kill: ["bloated-regent"]` |
| A character digs up a grave by spending 1+C movement while adjacent (not all at once) | done | placements `dig: [1, 2, 3]` → during a Move a tap on a grave beside the mover spends one point on it (`BoardCoordinator.dig`), the grave's hit points (1+C) being what is left to dig, kept from turn to turn; the move goes on with the rest. Graves are no longer attacked (`isDug` → `isUntouchable`). `ScenarioSpecialRuleTests.testAGraveIsDugWithMovementSpentBesideIt` |
| A dug-up grave spawns a Living Corpse in the nearest empty hex: normal (2); normal for (a), elite for (b) (3); elite (4) | done | placements `dropRules: [0, 1]` (the data's once-only rules) and `whenDestroyed` — objective 1 (a) normal / normal / elite, objective 2 (b) normal / elite / elite → `handleDeath` spawns each grave's own corpse on the hex the grave stood on (the grave is taken off the map, so that hex is the empty one); `testEveryGraveLetsOutItsCorpse`, `testWhatAGraveLetsOutAppearsWhereItStood` |
| Section 1: grave (c) is dug up like the others and spawns an elite Living Corpse, the Bloated Regent | done | rule 2 `requiredRooms: [3]`, grave c `dead` → `bloated-regent` (boss, elite Living Corpse's stats) at marker c |
| The Regent has (H×C)/2 HP rounded up | done | `monster/bloated-regent.json` health `[(10xC)/2{$math.ceil}]` … `[(25xC)/2{$math.ceil}]` (H = the elite Living Corpse's hit points at each level); `MonsterDataTests.testHalvedBossHealth_roundsUp` (20 for three characters at level 3) |

### 76 · Harrower Hive
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: reveal all rooms and kill all enemies | partial | no placements entry: the default goal (`checkVictoryDefeat`) needs every enemy dead and every door on the board open. The walls are doors (below), so every wall must be opened, not just one into each room |
| Setup: each character discards three ability cards (scenario effect) | missing | `76.json` has no `rules` and there is no placements entry; no code discards cards at a scenario's start (it would need a prompt before round 1) |
| Walls (a): C+(L/2) HP rounded up, destroyed by damage, attacked like an enemy | missing | the map data's 23 `breakable-wall` connectors become ordinary closed doors (`BoardBuilder` records every non-corridor connector as a door): a character opens one by walking into it; no hit points, nothing to attack. It would need doors that are objectives |
| Summons attack walls only when directly controlled | missing | walls aren't attackable at all |
| Each tile is a separate room; a destroyed wall reveals the room(s) behind it and becomes a corridor | partial | each tile is its own room and opening a wall-door reveals the tile behind it with its monsters, overlays and onward walls, whichever wall it is entered by (`MapRevealTests.testARoomIsTheSameWhicheverDoorItIsEnteredBy`, `BoardSimulationTests.testOpeningDoorsRevealsWholeMap`) — but the wall is opened by walking into it rather than destroyed, and its hex stays an open door, not a corridor |
| When a wall is destroyed all enemies adjacent to it gain STUN | missing | no code: opening a wall-door stuns no one |

### 77 · Vault of Secrets
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles and kill all City Guards | done | placements goal `loot: "goal"` + `kill: ["city-guard"]` (`goalMet`: both goal chests on B2b/B3b looted, rooms 1–2 revealed, no guard alive — the two that arrive with the treasure included; `testLootingTheVaultBringsGuards`) |
| Lose: any City Guard occupies a pressure plate (a) | done | placements goal `lostIfStands: {"monsters": ["city-guard"], "marker": "a"}`, marker a = two hexes on `n1b`, drawn as plates (`plates: ["a"]`) → `goalLost`; `testTheVaultsGuardsMarchForTheAlarm` |
| Section 1: left treasure tile looted → City Guard spawns at (b): normal (2) / elite (3–4) | done | placements `rules` 0: `when: [{"looted": "b2b"}]`, `once`, city-guard normal / elite / elite at marker b (`n1b`); `testLootingTheVaultBringsGuards` |
| Section 1: right treasure tile looted → City Guard spawns at (c): normal (2–3) / elite (4) | done | placements `rules` 1: `when: [{"looted": "b3b"}]`, `once`, city-guard normal / normal / elite at marker c (`n1b`); `testLootingTheVaultBringsGuards` |
| City Guards do not act normally: "Move 2" toward the closest plate (a), then every non-move ability on their card | done | placements `march: {"city-guard": {"toward": ["a"], "move": 2, "opensDoors": true}}` → `MonsterTurnController` runs `marchStep` (`BoardCoordinator+March`) in place of the card's Move actions, then the rest of the card; an immobilized guard doesn't march but still does the rest; `testTheVaultsGuardsMarchForTheAlarm`, `testAMarchingGuardStillAttacks` |
| A City Guard entering the hex of door 1 opens it and reveals the room | done | `march.opensDoors: true` → `marchStep` paths with `canOpenDoors` and calls `openDoor` as the guard walks into the doorway, revealing N1b; `testTheVaultsGuardsMarchForTheAlarm` |

### 78 · Sacrifice Pit
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and stop the sacrifice) | done | default goal in `checkVictoryDefeat` (all hostile dead, all doors open); no placements entry for 78 |
| Lose: a Cultist (b) starts its turn adjacent to the altars (d) while the victim is adjacent too | missing | still no placements entry for 78: no goal, no (c)/(d) markers, no victim, so nothing can lose it (README goal table: "the sacrifice isn't modelled"; `TODO.md`: "Monsters that don't act as their cards say"). Needs the victim and the carrying first |
| Objective: Victim (a), a token with no HP, immune to forced movement/IMMOBILIZE/STUN, moves only as described | missing | 78.json has no `objectives` and there is no placements entry; nothing stands at (a) (`TODO.md`: "Monsters that don't act as their cards say") |
| The two Cultists (b) don't act normally: "Move+0" together to carry the victim to (c)/the altar | missing | they are `cultist-scenario-78` (elite, deck `cultist`) and take ordinary Cultist turns from the shared Cultist deck; rule 0's two `custom` actions are labels only. Needs a mechanic like placements `march` (toward (c)) plus the victim |
| After the Cultists move, the victim moves the same number of hexes to stay adjacent to them | missing | no victim |
| Cultists (b) are immune to IMMOBILIZE and STUN | done | rule 0 (`requiredRooms: [2]`, persistent `statEffects`) → `immunities: ["immobilize","stun"]` → `MonsterManager.applyScenarioStatEffect` → `applyCondition` refuses them. (Victim: n/a, not in the game) |
| Cultists (b) and the victim are immune to forced movement | done | `monster/cultist-scenario-78.json` `baseStat.immunities` now has `"push"`, `"pull"` (and immobilize, stun) → `performPushPull` returns for an immune target; `ScenarioReauditTests.testTheCarriersAndTheCannonCantBeForcedToMove`. (Victim: n/a, not in the game) |
| Cultists (b) and the victim can open doors | missing | label "Can open doors" only (`custom` action in the stat effect); `opensDoors` is true for characters only and `MonsterAI` paths with `canOpenDoors: false`, so a closed door is a wall to them (only `march` monsters, #77, and the Bandit Commander open doors) |

### 79 · Lost Temple
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Betrayer | done | placements goal `kill: ["the-betrayer"]` |
| Lose: Fish is killed | done | placements goal `lostAt: {"1": 1}` → `goalLost`; `ScenarioSpecialRuleTests.testFishHoldsHisPlate` (his death → `.defeat`) |
| Setup: plates in play — (a) for 2 characters, (a)+(b) for 3, (a)+(b)+(c) for 4 | done | placements markers `a` (D2a, K1a, K2b), `b` (K1a), `c` (K2b) and rule 0 `when: [{occupied: {markers: ["a"], more: {"3": ["b"], "4": ["b","c"]}}}]` → `platesInPlay`, drawn by `pressurePlateHexes`; `testTheTemplesGolemsWakeWhenEveryPlateIsHeld` (two and three characters) |
| Objective Fish: 6+(2×L) HP, ally to the characters, enemy to all monsters, starts on plate (a) of the D tile | done | `objectives[0]` (`escort`, `health: "6+2xL"`, `allyDeck`), placed at placements `d2a [0,3]`; escorts are player-side and in `MonsterAI.gatherEnemies` |
| Fish acts on initiative 99: back to his starting hex if moved off, then "Attack 3" on all adjacent enemies | done | `GameObjectiveContainer.standingAttack` reads the attack nested in his `custom` action (so `hasEscortActions` is true; initiative 99) → `EscortAI.computeTurn` walks him back to `objectiveSites` home, then attacks every adjacent enemy for 3; `testFishHoldsHisPlate` |
| Door 1 is locked; it opens when all Stone Golems are killed | done | placements lock `d2a–m1a` with no key + rule 0 (`killed: all` stone-golem → `rooms: [2]` → `openScenarioRooms`); `ScenarioLockTests` covers it |
| Stone Golems cannot act or be affected until every plate in play is occupied at the end of a turn; then they draw a card as if just revealed | done | placements `inactive: [{monsters: ["stone-golem"], untilSetUp: true}]` → `MonsterAI.inactiveMonsters` / `isInactive` (no turn, not an enemy, not affected); the `occupied` rule's `setUp: ["stone-golem"]` → `placeMonstersSetUpLater` wakes them through `readyNewMonsters` as just revealed; `testTheTemplesGolemsWakeWhenEveryPlateIsHeld`, `testTheGolemsWakeAsTheTurnEnds` |
| Boss special 1: summon Giant Vipers (1 elite for 2; 1 normal + 1 elite for 3; 2 elite for 4), then all characters and their summons are forced to "Move 4" away from the Betrayer | partial | the summon is right now: `the-betrayer.json` `special[0]` gives 1 elite for 2, 1 normal + 1 elite for 3, 2 elite for 4 (`MonsterSummonDataTests.testTheBetrayerSummonsItsVipers`). The forced "Move 4" away from the Betrayer is not in the data or the code (README: "forced moves … aren't modelled"; `TODO.md`: "Bosses still played from their stat cards") — it needs forced movement of characters and their summons, chosen by the players |
| Boss special 2: pull everyone adjacent; mind-control the character acting latest (Move 2 + top action of leading card, both cards discarded) and their summons | missing | `special[1]` is the single `custom` label; `MonsterTurnController` logs "Resolve the boss's special ability 2 as printed on its stat card" and does nothing. Needs the forced move to the Betrayer and a mind-controlled turn (sides swapped for one character and their summons) |

### 80 · Vigil Keep
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: every character loots one treasure tile, then all characters reach the B tile | done | placements goal `loot: "each"` + `escape: {tile: "b1a"}` (`goalMet`, judged as a turn ends); `ScenarioGoalTests` uses #80 |
| Lose: any character becomes exhausted while not on the B tile | done | `lostIfExhausted: ["offExit"]` → `exhaustionLoss` |
| Until a character has looted a treasure tile, they have Disadvantage on all attacks and cannot use any items | done | placements `effects: [{on: "party", untilLooted: true, disadvantage: true, noItems: true}]` → `scenarioEffects(on:)` (`goalLooters`) → `scenarioGivesDisadvantage` in `performAttack` and the preview, `updateItemBars` → `GameCharacter.itemsBarred` (no carried items); each character for themselves, summons untouched; `ScenarioSpecialRuleTests.testVigilKeepBarsItemsUntilTheTreasure` |
| Each character may loot only one treasure tile | done | `mayLootGoalTreasure` (`lootHexes` skips a second goal chest for the same character) |

### 81 · Temple of the Eclipse
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Colorless | done | placements goal `kill: ["the-colorless"]` |
| Section 1: a character adjacent to the altar (a) at end of turn may discard the Crystal of Zenith or Sphere of Midnight → the Colorless suffers 2×C damage | done | placements `d1a` marker a [1,0] (the altar, read off p.103) and `spend: {"marker": "a", "adjacent": true, "damage": "2xC", "to": "the-colorless"}` on both relics → as the holder's turn ends beside the altar they are asked (`resolveCarriedSpends`): discard it and the Colorless suffers 2×C, or "Keep It". `CarriedThingTests.testTheRelicsAreLootedInOrderAndDiscardedBesideTheAltar` |
| Start of every round: Light and Dark Strong; Fire, Ice, Wind, Earth Inert | done | rule 0 (`round: "true"`, `start: true`, six `elements`) → `applyElementRule` each `roundStart` |
| First treasure tile looted gives the Crystal of Zenith, the second the Sphere of Midnight | done | placements `carried`: two things with `treasure: "goal"`, given in the order written to whoever loots a goal tile (`noteTreasureLooted`); neither changes hands. Same test |
| Boss special 1: consume Dark → summon Night Demon (normal 2–3 / elite 4), then gain INVISIBLE | done | `the-colorless.json` `special[0]`: the Dark consume is paid as the special comes to it (`MonsterTurnController` `.special` → `executeCard` → `.element` consume → `performSummon`), no Dark no demon, INVISIBLE on self either way; `ScenarioSpecialRuleTests.testTheColorlessPaysForItsSummonsWithElements` |
| Boss special 2: consume Light → summon Sun Demon (normal 2 / elite 3–4), then Shield 1 and heal self | done | `special[1]`: Light is consumed for the Sun Demon (same test), "Heal 4, self" runs (the book prints no amount; 4 is the data's), and Shield 1 is gained until the end of the round (`.shield` in `executeCard`; `MonsterTurnRulesTests.testABossSpecialsShieldIsGainedWhenItIsPerformed`) |

### 82 · Burning Mountain
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal A: after the chest is looted, the character holding its items ends a turn on (g) and removes one item from the game | partial | placements `carried: [{"name": "artifacts", "treasure": "62", "lostWithHolder": true}]` and `either: [{reach: {marker: "g", holding: "artifacts"}, conclusion: "82-A"}, …]`: whoever looted the chest holds the artifacts, and it is their holder ending a turn on g that wins with Conclusion A's rewards (`CarriedThingTests.testTheArtifactsHolderSacrificesOneOrLosesThemAll`, `ScenarioGoalTests.testEitherOfTwoWays`, `ScenarioReauditTests.testSacrificingOnTheMountainIsConclusionA`). Still missing: no item is removed from the game — the player isn't asked which |
| Goal B: after the chest is looted, all characters return to an entrance hex before becoming exhausted | partial | `either: […, {escape: {start: true}, conclusion: "82-B"}]`: every unexhausted character on a starting hex as a turn ends wins with Conclusion B's rewards (`testEscapingTheMountainIsConclusionB`); the holder's exhaustion loses the scenario (FAQ; `lostWithHolder`, `testTheArtifactsHolderSacrificesOneOrLosesThemAll`). Another character's exhaustion isn't waited for and doesn't prevent it |
| If the scenario is lost, the treasure tile is reset (not kept) | done | placements `resetOnLoss: ["62"]` → `settleScenarioEnd(victory: false)` takes items 110/115 back from the looter and removes `gh-82-62` from `game.lootedTreasures`, on abandoning too; `testTheMountainsChestIsResetOnALoss`, `testTheMountainsChestIsResetWhenTheScenarioIsAbandoned` |
| All doors locked; each elite killed opens one door, in order a, b, c, d, e, f | done | six placements locks with `eliteKills: 1…6` (`k1a–c1a`, `k1a–d1a`, `c1a–i1b`, `b2b–d1a`, `c1a–empty`, `empty–d1a`); `boardState.eliteKills` counted in `handleDeath`; `ScenarioLockTests` covers it |

### 83 · Shadows Within
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal in `checkVictoryDefeat` (placements 83 has rules and the altar marker but no `goal`); the held-back Flame Demons are set up before it can be met |
| Section 1: characters and their summons within 2 hexes of the altar (a) suffer 1 damage at the start of their turns | done | placements marker `a` (`m1a [2,3]`) and rule 0 (`alwaysApplyTurn: "turn"`, `requiredRooms: [3]`, `characterWithSummon` `near: {marker: "a", range: 2}`, damage 1) → `evaluateTurnRules(.turnStart)`, suffered before the turn is played; `ScenarioSpecialRuleTests.testTheAltarOfShadowsWithin` |
| Section 1: monsters within 2 hexes of the altar heal 1 at the start of their turns | done | placements rule 1 (monster `near` a within 2, heal 1, as its turn starts); `testTheAltarOfShadowsWithin` |
| Flame Demons are not set up until all Cultists are dead | done | placements `later: ["flame-demon"]` (held back by `heldBackMonsters`/`holdBack`) and rule 2 (`killed: all` cultist, `once` → `setUp: ["flame-demon"]` → `placeMonstersSetUpLater`, where the map prints them); `testTheAltarOfShadowsWithin` |
| Section 2: all characters and their summons suffer 2 damage at the start of each of their turns | done | placements rule 3 (all Cultists killed → every `characterWithSummon` damage 2 as their turn starts); rule 2's `disableRules: [0, 1]` ends Section 1's damage and healing (FAQ); `testTheAltarOfShadowsWithin`, `ScenarioReauditTests.testTheAltarsFirstRulesEndWithTheCultists` |
| Section 2: start of every round, Fire is Strong | done | placements rule 4 (`start: true`, all Cultists killed → `elements: fire strong`) each `roundStart`; `testTheAltarOfShadowsWithin` |

### 84 · Crystalline Cave
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the crystal) | done | default goal (placements goal sets only a loss, so kill-all with every door open still applies) |
| Lose: the crystal is destroyed | done | placements goal `lostAt: {"1": 1}` → `goalLost` |
| Objective: crystal (a) with 4+C+(2×L) HP | done | `objectives[0].health: "4+C+(2xL)"`, placed on placements `l2a [0,3]` (the map's crystal obstacle) |
| The crystal cannot be healed and is not an ally of the characters | done | placements `protect: [1]` → `GameObjectiveContainer.isProtected`: `areAllies` is false, `alliesInRange` leaves it out so no heal or ally ability reaches it, and monsters still target it (`gatherEnemies`); `ScenarioSpecialRuleTests.testWhatIsProtectedIsNoAlly` |
| Monster focus: a monster that can move within range to attack the crystal focuses on it, otherwise normal focus | done | placements `focusFirst: [1]` → `MonsterAI.prioritized` puts the crystal first among the focus candidates whenever its path cost is within this turn's move, else the normal order; `testMonstersGoForTheCrystalWhenTheyCanReachIt` |
| Twice, when the crystal would suffer damage, a character may lose a hand card to negate it | done | placements `saves: [{"objective": 1, "times": 2}]` → `promptSave`; the uses are counted in `BoardState.savesUsed` (saved with the board) and the sheet says how many are left; `ScenarioSpecialRuleTests.testACardFromAnyHandSparesTheCrystalTwice` |
| Start of round 4: corridor on (b), reveal the adjacent room | done | placements lock `l2a–a3a` with `afterRound: 3` → `keyTurned`/`updateLocks(roundEnded:)`: a wall no one can walk through until round 3 ends, then it opens and A3a is revealed (the map's door stands in for the corridor tile); `testTheCaveWallsComeDownByTheRound` |
| Start of round 6: corridor on (c), reveal the adjacent room | done | placements lock `l2a–a2b` with `afterRound: 5` — opens and reveals A2b as round 5 ends; `testTheCaveWallsComeDownByTheRound` |
| Start of round 9: corridor at (d), reveal the adjacent room | done | placements lock `l2a–e1b` with `afterRound: 8` — opens and reveals E1b as round 8 ends; `testTheCaveWallsComeDownByTheRound` |

### 85 · Sun Temple
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal in `checkVictoryDefeat` (placements 85 has `rules`, `apart` and `splitStart` but no `goal`); the Sun Demons standing apart still count as enemies to kill |
| Setup: two starting rooms; no more than half the characters (rounded up) from the same room | done | placements `splitStart: true` → `freeStartingHexes` leaves out the starting hexes of a room that already holds half the party (rounded up) and `placeCharacter` refuses them, for two characters as well; `ScenarioSpecialRuleTests.testNoMoreThanHalfThePartyStartsInOneRoom` (#58 with two, #50 with three, #85 with four) |
| Section 1: all Sun Demons are enemies to both the characters and all other monster types | done | placements `apart: ["sun-demon"]` → `GameMonster.standsApart` (set in `ScenarioManager`, kept in saves) → `areEnemies`/`areAllies` and `MonsterAI.gatherEnemies`/`gatherAllyPositions`: a third side against the party and every other monster type, allies of one another; `testSunDemonsAreEveryonesEnemies`. In force from the start, which is the same thing: the Sun Demons are only in the room behind door 1 |
| With "Sun-Blessed": start of every round Light Strong, Dark Inert | done | placements rule 0 (`start: true`, `when: [{partyAchievement: "sun-blessed"}]`, `elements` light strong, dark inert) each `roundStart`; `ScenarioReauditTests.testSunBlessedLightsTheSunTemple` |

### 86 · Harried Village
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: save seven villagers | done | placements goal `arrive: {objective: 1, marker: "b", count: 7}` → `noteEscortArrival` |
| Lose: five villagers are killed | done | `lostAt: {"1": 5}` |
| Villagers (a): 3+L HP each, 11 of them, enemies to all monster types | done | `objectives[0]` (`health: "3+L"`, `count: 11`, `escort`); 5 + 3 + 3 placed from placements as their tiles are revealed; monsters target escorts |
| Villagers cannot be healed and are not allies of the characters | done | placements `protect: [1]` → `GameObjectiveContainer.isProtected` (`ScenarioManager`) → `BoardCoordinator.areAllies` is false for them, so no heal or ally ability reaches them, while monsters still target them (`MonsterAI.gatherEnemies`); `ScenarioSpecialRuleTests.testWhatIsProtectedIsNoAlly` |
| Villagers act on initiative 99: "Move 3" toward the end of the docks (b); one reaching (b) is removed and saved | done | default initiative 99; `EscortTurnController.destination` reads marker b from label 86.1; `EscortAI.walk`; `noteEscortArrival` removes and counts it |
| Start of every odd round: Vermling Scouts at (c) and (d) — both normal (2); elite c + normal d (3); both elite (4) | done | 86.json rule 0 (`round: "R % 2 == 1"`, `start`; c normal/elite/elite, d normal/normal/elite) is applied before the cards for the round are chosen (`ScenarioRulesManager.evaluateRulesForTheRoundToCome`), so round 1 has its pair; markers c (B1b) and d (M1b) from placements; `ScenarioSpecialRuleTests.testTheLurkersWaitForTheFirstVillagerSaved` (round 1's two scouts, elite at c and normal at d for three) |
| Start of every even round: Vermling Scouts at (e) and (f) — both normal (2); normal e + elite f (3); both elite (4) | done | 86.json rule 1 (`round: "R % 2 == 0"`, `start`; e normal/normal/elite, f normal/elite/elite), applied the same way as the round begins; markers e (B1b) and f (M1b) from placements. No test of its own (the odd-round rule's test covers the mechanism) |
| Lurkers are not set up until the end of the round in which the first villager is saved | done | placements `later: ["lurker"]` holds them back (`ScenarioManager.heldBackMonsters`; their map places wait in `BoardState.heldMonsterSlots`) and the written rule (`once`, `when: [{saved: 1}]`, `setUp: ["lurker"]`, judged as a round ends) sets them up on H3a → `setUpHeldBack` / `placeMonstersSetUpLater`; `ScenarioSpecialRuleTests.testTheLurkersWaitForTheFirstVillagerSaved` |

### 87 · Corrupted Cove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Giant Ooze | done | placements goal `kill: ["giant-ooze"]` |
| Setup: each character adds 3 CURSE cards (scenario effect) | done | rule 0 (`R == 1`, `start`, `amAdd curse:3`, `scenarioEffect`) → `applyAmAdd` |
| The elite Ooze at the centre is the Giant Ooze, with H×C hit points (H = elite Ooze HP) | done | room 2 lists `giant-ooze` (boss); `monster/giant-ooze.json` health is elite-Ooze HP × C at every level, other stats equal the elite Ooze's. It stands on its own place on L2a in the map data (`ScenarioMaps/87.json`, corrected against the book; `MapMonsterPlaceTests.testEveryMonsterOfARoomHasItsOwnPlaceOnTheMap`) |
| Four tokens on the Giant Ooze: Shield 2 per token, one removed each time any Ooze dies | done | placements `effects: [{on: "giant-ooze", shield: "2xX", per: {tokens: 4, lostWith: "ooze"}}]` → `BoardCoordinator.scenarioShield` (four less the Oozes killed, from `killCounts`, never below none), added to its own Shield in `shield(of:)`; `ScenarioSpecialRuleTests.testTheGiantOozeLosesATokenWithEveryOoze` |
| A character ending a turn on a water hex (a) removes the tile and gains Shield 2 against Ooze attacks and POISON immunity for the scenario, once | done | placements `water.cleanses` (`tiles: ["l2a","l3b"]`, `shield: 2`, `against: ["ooze","giant-ooze"]`) → `cleanseAtTurnEnd` (the tile goes, `BoardState.cleansed`), `cleansedShield` in `performAttack`, `scenarioWardsOff` for Poison; `ScenarioSpecialRuleTests.testTheCovesWaterCleanses`. The (a) hexes are the three water hexes of the main room's tiles rather than lettered markers |

### 88 · Plane of Water
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: carry the Lurker King's claw to a hex adjacent to the crystal (a) | done | placements goal `kill: ["lurker-king"]` + `reach: {marker: "a", adjacent: true, holding: "claw"}`: the claw's holder ending a turn beside the crystal. `CarriedThingTests.testTheClawsHolderBesideTheCrystalWins` |
| Setup: all characters and their summons have −1 Move on all Move abilities | done | placements `effects: [{on: "party", move: -1}]` → `BoardCoordinator.scenarioMoveBonus` (characters in `beginMoveAction`, summons through `SummonTurnController`; monsters unchanged); `ScenarioReauditTests.testEveryMoveIsOneLessOnThePlaneOfWater` |
| Current: at the end of each round every character and summon in the large room is forced one hex with the current (sheltered behind an obstacle/wall: no move); if blocked, 3 damage instead | done | placements `drift: {name: "current", tiles: [g2a, n1a], sheltered: true, blocked: 3, …}` → `driftAsTheRoundEnds`: only figures on those tiles; one with an obstacle, a wall or the room's edge on the side the current comes from stays unharmed (`givesShelter`); one whose hex ahead is a figure, an obstacle or a wall suffers 3 (which a character may negate with cards). `DriftTests.testShelterFromTheCurrentAndWhatItCostsToBeInItsWay` |
| Current is resolved from the top of the map to the bottom | done | `drift.order: "top"` → `driftOrder` sorts by row, whatever the initiatives; `DriftTests.testTheCurrentIsResolvedFromTheTopOfTheMap` |
| Current direction depends on whether the Lurker initiative is even or odd | done | `drift.byInitiative: {monster: "lurker", even: [NW], odd: [NE]}` (our map lies as the book's diagram does) → `driftInitiative`: the card the Lurkers (or the King, who shares their deck) acted on this round; when none of them is left a Lurker card is drawn for the current alone (our reading: the book and the FAQ don't say). `DriftTests.testTheCurrentFollowsTheLurkersInitiative` |
| The elite Lurker next to the crystal is the Lurker King | done | room 2 lists `lurker-king` (boss) whose stats equal the elite Lurker's; the map data gives it its own place on N1a, the hex beside the crystal's (a) (`ScenarioMaps/88.json`, corrected against the book; `MapMonsterPlaceTests.testEveryMonsterOfARoomHasItsOwnPlaceOnTheMap`) |
| When it dies it drops a claw (a treasure tile) instead of a money token | done | placements `carried: [{"name": "claw", "droppedBy": "lurker-king", "move": -2, "passes": true}]` → `handleDeath`: the claw lies where the King died and no money token drops. `testTheLurkerKingDropsHisClawAndItWeighsItsHolderDown` |
| A character holding the claw has −2 Move | done | `carriedMoveBonus` in `scenarioMoveBonus`: −2 for the holder on top of the scenario's −1. Same test |
| The claw changes hands only by a Loot action on the holder's hex; it is dropped where the holder is exhausted | done | the carried mechanism of #69's doll (`passes`): `testTheDollChangesHandsByALootAction`, `testAnExhaustedHoldersDollLiesWhereTheyStood` |

### 89 · Syndicate Hideout
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| All Cultists summon elite Giant Vipers instead of normal Living Bones | done | rule 0 (`always`, `alwaysApply`, `statEffects` deck `cultist-scenario-89`) → `switchDeck`; that deck's two summon cards name `giant-viper` type `elite` |

### 90 · Demonic Rift
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: close the rift — after Section 1, kill all Living Spirits | done | written goal `kill: ["living-spirit"]` (`DemonicRiftTests.testTheSpiritsComeWhenTheDemonsAreDeadAndACharacterStandsInEachRoom`) |
| Lose: no character is present in the left room at any time | done | `lostIfEmpty` (`testTheLeftRoomMayNeverBeEmpty`) |
| Lose: only one character is left unexhausted | done | `lostBelow: 2` (`testOnlyOneCharacterLeftLosesTheScenario`) |
| Lose: after Section 1, either room has no character present | done | `lostIfEmpty` with `onceAppeared` (`testTheRightRoomMayNotBeEmptyOnceTheSpiritsHaveCome`) |
| Section 1 (all demons dead, a character in each room): a Living Spirit at every (b) and (c) — all normal (2); b elite + c normal (3); all elite (4) | done | the written rule waits for every demon's death and `characterOn` each room (`ScenarioEnforcedRuleTests.testTheRiftsSpiritsHaveTheirRanks`) |
| Characters cross between the rooms only through the altars: 1 movement from beside one altar to beside the other; summons and monsters cannot | done | the `altar` connector is a crossing (`BoardState.crossings`): both rooms are set up at the start, the altars can't be entered or destroyed, and `Pathfinder` lets a character step across (`testACharacterBesideOneAltarStepsBesideTheOtherForOneMovement`) |
| End of every even round with no character in the right room: a Night Demon spawns next to the left altar (normal for 2; every second one elite for 3; elite for 4) | done | written rule (`ScenarioReauditTests`) |

### 91 · Wild Melee
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal; allied monsters are excluded from `hostile` |
| Section 1: all Living Spirits are enemies to the characters and to all other monster types | done | placements `apart: ["living-spirit"]` → `GameMonster.standsApart` (`ScenarioManager`) → `MonsterAI.side` `.apart`, a third side against the party, the bandits and the allied bears and hounds (`areEnemies`, `MonsterAI.gatherEnemies`); `ScenarioSpecialRuleTests.testThreeSidesInTheMeleeAndTheBrawl`. The spirits only stand in the rooms behind door 1 |
| Cave Bears and Hounds are allies to the characters, enemies to all other monsters, and still act on a monster ability card | done | `allies: ["cave-bear","hound"]` → `monster.isAlly` → `MonsterAI.gatherEnemies`/`isPlayerSide` invert sides; they take turns through `MonsterTurnController` |

### 92 · Back Alley Brawl
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all non-city enemies | done | placements goal `spare: ["city-guard","city-archer"]` → `goalMet` leaves the spared types out of `hostile` and asks for every other enemy dead with every room revealed (no longer a list of types that must have appeared); `ScenarioSpecialRuleTests.testTheBrawlIsWonWithTheGuardsAlive` |
| Lose: a City Guard or City Archer is killed | done | `lostIfKilled: ["city-guard","city-archer"]` → `goalLost` via `killCounts`; `ScenarioGoalTests.testKillingTheWrongEnemyLoses` |
| City Guards and City Archer are not set up until door 1 is opened (Section 1 sets them up) | done | placements `dropRules: [0]` removes the data's rule; the written rule waits for room 2 (`requiredRooms: [2]`) and sets up the archer at a and the guards at b and c at the far end of H3b (`placed`: set up, not spawned; archer elite for 3–4, second guard elite for 4, as the data has them); `ScenarioSpecialRuleTests.testTheBrawlIsWonWithTheGuardsAlive`, `ScenarioReauditTests.testTheCitysMenAreSetUpBehindTheParty` |
| They are enemies to the characters and to all other monster types (and may be attacked) | done | placements `apart: ["city-guard","city-archer"]` → `standsApart` → `MonsterAI.side` `.apart`: enemies of the party and of the bandits, allies of one another; `ScenarioSpecialRuleTests.testThreeSidesInTheMeleeAndTheBrawl` |

### 93 · Sunken Vessel
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: all characters start with IMMOBILIZE (scenario effect) | done | placements rule (`round: "R == 1"`, `start`, `gainCondition` `immobilize` on every character, `scenarioEffect`), applied before the first cards are chosen; `ScenarioSpecialRuleTests.testTheSunkenVesselStartsEveryoneImmobilized` |

### 94 · Vermling Nest
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot the treasure tile | done | placements goal `enemies: "all"` + `loot: "goal"` (the "G" chest on D1b) |

### 95 · Payment Due
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Lieutenant | done | placements goal `kill: ["prime-lieutenant"]` |
| Setup: numbered tokens 1–6 shuffled face down on the (a) hexes, lootable normally | done | placements `tokens: {marker: "a", count: 6}` with the six (a) hexes on D1a and K2b → `layNumberedTokens` (shuffled once with the game's seed, one laid on each lettered hex as its room is revealed, drawn as "?"); looted by ending a turn on one or by a Loot action (`lootNumberedToken`: the number is logged then); `CarriedThingTests.testTheTokensAreLootedAndFourOfThemUnlockTheDoor`, `testTheTokensAreShuffled` |
| Section 1: the Savvas Lavaflow is the Prime Lieutenant | done | room 3 lists `prime-lieutenant` (boss, deck `savvas-lavaflow`, stats equal the elite Lavaflow's) |
| Door 1 is locked; it can be opened once tokens 1–4 are looted | done | placements `locks: [{between: [g1b, e1a], tokens: [1, 2, 3, 4], unlocksOnly: true}]` → `keyTurned` (every number listed is among `tokensLooted`); unlocked, it opens to a character walking in; same test (three of the four, with 5 and 6, leave it locked) |
| Until tokens 1–4 are looted: end of every odd round a Flame Demon spawns by door 1 (normal for 2; elite for 3–4) | done | placements rule `round: "R % 2 == 1"`, `when: [{locked: 0}]` (the fact "lock 0 isn't released yet", `boardFactHolds`), spawning at the letter written on the G1b hex beside the door; same test |
| Until tokens 1–4 are looted: end of every even round an Earth Demon spawns by door 1 (normal for 2–3; elite for 4) | done | placements rule `round: "R % 2 == 0"`, `when: [{locked: 0}]`; same test |
| Any figure ending its turn in a water hex suffers 1+L damage | done | placements `water: {endOfTurn: "1+L"}` → `BoardCoordinator.waterDamageAtTurnEnd` (characters as their turn ends; monsters and summons through `sufferWaterAtTurnEnd` in `MonsterTurnController` / `SummonTurnController`); `ScenarioSpecialRuleTests.testEndingATurnInTheWaterOfPaymentDue` |
| Each boulder has 3+L hit points | done | `95.json` lists an objective "Boulder" (health `3+L`), five in room 4, and the placements stand one on each of K2b's five boulder hexes: a thing to destroy, attacked like an enemy; destroyed, its obstacle goes with it (`clearObjectiveSite`) — which is the only way on foot to the far room's three tokens; `CarriedThingTests.testTheBouldersAreDestroyedToReachTheTokens`. Was: K2b's five boulders were plain obstacle overlays with no hit points. Needed obstacles that are objectives with health |
