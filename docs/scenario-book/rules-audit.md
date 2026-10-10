# Gloomhaven scenario rules — what the game implements

An audit of every rule the scenario book prints (as noted in
[gh-scenario-rules.md](gh-scenario-rules.md)) against the scenario data, the placements and the code,
made on 2026-10-09 at commit `a3caf18` by reading — nothing here was established by playing.
Each row is one printed rule: **done**, **partial** (it works in a simplified way; the row says how
it differs) or **missing**, with where it is implemented or what happens instead.

**447 rules: 239 done, 53 partial, 155 missing.**
34 of 95 scenarios have every printed rule done: #1, #4, #5, #6, #8, #10, #11, #13, #14, #15, #16, #17, #18, #19, #23, #24, #25, #27, #28, #29, #31, #32, #37, #40, #43, #53, #59, #60, #63, #64, #65, #72, #89, #94.
The most rules outstanding: #88 (7 missing, 1 partial), #34 (6 missing, 1 partial), #55 (6 missing, 1 partial), #42 (6 missing, 0 partial), #73 (6 missing, 0 partial), #78 (6 missing, 0 partial), #90 (5 missing, 2 partial), #95 (6 missing, 0 partial), #58 (5 missing, 1 partial), #79 (5 missing, 1 partial), #84 (5 missing, 1 partial), #71 (5 missing, 0 partial), #76 (4 missing, 2 partial), #77 (5 missing, 0 partial), #83 (5 missing, 0 partial).

Fixed since the audit (the rows below still describe the state it found): boss summons bring the
number and rank their player count says (#9, #12, #20, #48, #79 and others); goal treasure that
needs a Loot action (#7, #30, #50, #52, #59, #61); #3's guard arrives as each round begins for
three or four characters; #22's altars strengthen the demons (hit points, attack, movement and
range for each one standing); figures immune to push and pull aren't moved (#47, the Elder Drake);
#51's damage lands as each turn ends, on summons too; #84's crystal and #86's villagers are
protected rather than allies; #75's graves each let out their own corpse; #26's imps appear beside
their own pump; #35's allied demons attack the gate; #61's demons are enemies (the alternating
rounds are still missing); #41 is won without waiting for a character exhausted on the way; #45
and #52 add two cards, as the book says; the Hungry Soul's and Bloated Regent's hit points round
up (#62, #75); #92's city guards arrive with the second room and needn't die; #90's Living Spirits
come when the demons are dead and killing them wins. Later fixes are listed in `TODO.md`.

### 1 · Black Barrow
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | no placements entry, no `finish` rule → default goal in `checkVictoryDefeat` |

### 2 · Barrow Lair
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Bandit Commander and all revealed enemies | done | placements goal `kill: ["bandit-commander"]`, `enemies: "revealed"` → `goalMet` |
| Setup: each character adds 3 Curse | done | scenario rule 0 (`round "R == 1"`, `start`, `amAdd curse:3`, `scenarioEffect`) → `applyAmAdd`; skipped for the "ignore negative scenario effects" perk |
| Doors a, b, c, d locked; only the Bandit Commander opens them | done | placements `locks` ×4 (m1a–a1a/a4b/a2a/a3b) with no key; `Pathfinder` and `moveAlong` refuse locked doors; `moveToNextDoor` passes `opensLockedDoors: true` |
| Boss special 1: Commander jumps to a door hex however far away and opens it; order a, b, c, d, then back to a | partial | `MonsterTurnController.moveToNextDoor` (matched on label "move to next door and reveal room"): he walks toward the **nearest** closed door with his own Move (3), paying terrain, stopped by Immobilize, and opens it only if he gets there that turn — no jump, no a→b→c→d order, nothing once all four are open. (The scenario JSON also letters the rooms differently from the book: its `b` is A3b, the book's is A4b — unused by the code.) |
| Boss special 2: summon 1 normal Living Bones (2 characters) or 1 elite (3–4) | done | `bandit-commander.json` special 2 `summon` (player2 normal, player3/4 elite) → `performSummon` → `summonMonster` (adjacent empty hex, standee limit) |

### 3 · Inox Encampment
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill 5×C enemies | done | placements goal `killCount: "5xC"` → `goalMet` sums `scenario.killCounts` of hostile types (C at least 2) |
| 1 normal Inox Guard spawns at (a): end of every odd round (2 characters), beginning of every round (3–4 characters) | partial | 2 characters: rule 0 (`round "R % 2 == 1"`, no `start` → round end), marker a = placements l1b [0,3] — correct. 3–4 characters: rule 1 is `round "true"` **without `start`**, so `isEligible` runs it at round END, not at the beginning: the guard for the beginning of round 1 never appears (every later one arrives one round-boundary late, i.e. the same moment) |
| Spawning stops once door 1 is opened | done | rule 2 (`always`, `requiredRooms: [6]` = E1b) `disableRules` index 0 and 1; evaluated on room reveal (`openDoor` → `evaluateRules(.figureChange)`) |

### 4 · Crypt of the Damned
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |

### 5 · Ruinous Crypt
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: all characters start with Disarm | done | rule 0 (`R == 1`, `start`, `gainCondition disarm`, `scenarioEffect`) → `EntityManager.addCondition`; active through each character's first turn. Note: it is applied in `RoundManager.transitionToNext`, i.e. after round-1 cards are chosen, so the Disarm isn't on the character while picking cards |

### 6 · Decaying Crypt
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: reveal the M tile (M1a) and kill all revealed enemies | done | placements goal `reveal: ["m1a"]`, `enemies: "revealed"` |
| Setup: each character adds 3 Curse | done | rule 0 `amAdd curse:3` at start of round 1 |

### 7 · Vibrant Grotto
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles | done | placements goal `loot: "goal"`; map has 5 treasure overlays with id `goal` (m1b, d2b, c2a, f1b, b4b) → `goalTreasureIsLooted` |
| Treasure tiles can only be looted with a Loot action, not by end-of-turn looting | missing | `lootAtEndOfTurn` → `lootHexes` picks up any treasure in the character's hex, goal tiles included; no scenario-7 exception anywhere (also looted by "loot every hex you enter" moves) |

### 8 · Gloomhaven Warehouse
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill both Inox Bodyguards | done | placements goal `kill: ["inox-bodyguard"]` (room 3 revealed, both entities dead) |

### 9 · Diamond Mine
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Merciless Overseer and loot the treasure tile | done | placements goal `kill: ["merciless-overseer"]`, `loot: "goal"` (goal chest on n1a) |
| Boss special 1: all Vermling Scouts immediately take an extra turn with this round's card | done | `MonsterTurnController` `.special`: label "All Scouts act again" → `executeMonsterGroup(scouts)` with `currentAbility` (scouts summoned this round are skipped, as for any new summon) |
| Boss special 2: summon 2 normal Scouts (2 characters), 1 normal + 1 elite (3), 2 elite (4) | partial | wrong counts. `MonsterSummonSpec.Wrapper` drops the data's `"count": 2`, and `type(forPlayerCount:)` falls back to `.normal` for an entry that has no variant for this player count instead of skipping it, so all three `valueObject` entries are summoned once: 2 chars → 3 normal; 3 chars → 2 normal + 1 elite; 4 chars → 1 elite + 2 normal (subject to free adjacent hexes/standees) |

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
| Boss special 1: summon 2 normal Living Bones (2 characters), 1 normal + 1 elite (3), 2 elite (4) | partial | summon is carried out (`performSummon`), but counts are wrong for the same reason as #9: `count` ignored and non-matching entries default to normal → 2 chars: 3 normal; 3 chars: 2 normal + 1 elite; 4 chars: 2 normal + 1 elite |
| Boss special 2: as special 1 with Living Corpses | partial | same data shape, same wrong counts (3 normal / 2 normal + 1 elite / 2 normal + 1 elite) |

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
| Boss Special 1: summon Living Bones — 2 normal (2 chars), 1 normal + 1 elite (3), 2 elite (4) | partial | `monster/jekserah.json` special[0] is a `summon` with three `valueObject` entries; `ActionModel.monsterSummons` drops the `count: 2` field and `MonsterSummonSpec.type(forPlayerCount:)` falls back to normal when an entry has nothing for that player count (instead of skipping it). `MonsterTurnController.performSummon` therefore summons three every time: 2 chars → 3 normal (book 2 normal); 3 → 2 normal + 1 elite (book 1 + 1); 4 → 2 normal + 1 elite (book 2 elite). The stat card's "Attack −1, all adjacent enemies" that follows is executed |
| Boss Special 2: same with Living Corpses | partial | special[1], same decoding, same wrong counts and ranks; the stat card's "Move −1, Attack +2" that follows is executed |

### 21 · Infernal Throne
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Demon | done | placements goal `kill: ["prime-demon"]` — but it is killed by attacking it directly (see below) |
| Objective: Altar shares hit points, initiative and immunities with the Prime Demon | missing | `21.json` has no `objectives` and no `rules`; placements has no tiles. No altar piece exists |
| The Prime Demon cannot be damaged; damage is dealt to the altar instead | missing | The Prime Demon is an ordinary boss that takes damage itself |
| Boss Special 1: altar jumps a→b→…→f (displacing figures, revealing the room and opening doors); altar summons a demon by location (normal for 2, elite for 3–4); Prime Demon "Move+2, Attack−1" | partial | `monster/prime-demon.json` special[0]: only the trailing Move +2 / Attack −1 is carried out (`MonsterTurnController` `.special` case → `executeCard`). The `custom` "Throne moves" is unmatched text (log: "Resolve the boss's special ability 1 as printed on its stat card"); the `summon` has `value: "demon"` and no `valueObject`, so `performSummon` returns without summoning; no room is revealed; letters a–f are not written |
| Boss Special 2: same, demon normal for 2–3, elite for 4 | partial | special[1] is identical data; same result: Move +2 / Attack −1 only |

### 22 · Temple of the Elements
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all altars (a) | done | placements goal `destroy: [1]` (all four dead and every door open) |
| Objectives: Altar ×4, 4+(C×L) HP each | done | `objectives[0]` health `4+(CxL)`; `rooms[1].objectives: [1,1,1,1]` creates all four when room 2 is revealed; placements put one on each corner tile (c1a, c2b, d1a, d2a), placed as each is revealed |
| Per altar not yet destroyed: all demons +1 max HP, +1 attack, +0.5 movement and +0.5 range (rounded up) | missing | Rule 0 is a persistent `statEffects` rule with `health: "X"`, `attack: "X"`, `movement`/`range: "[X/2{$math.ceil}]"`. `MonsterManager.applyScenarioStatEffect` only acts on `name`, `deck`, `actions`, `immunities`, `health`; `attack`, `movement`, `range` are decoded and never read. **Worse, the health part is wrong:** nothing supplies `X` (number of altars), so `evaluateStatEffectHealth("X")` evaluates to 0 → `max(1, 0)` = 1, and the result replaces the stat instead of being added. From the moment room 2 is revealed (altars present) every Earth/Flame/Frost/Wind Demon has max HP 1 — existing ones are rescaled to 1, new ones are created with 1 via `monster.statEffectHealthExpr` in `addEntity`. No test covers a `health: "X"` stat effect |
| Melee attacks gain no range from this | missing | Moot: no range bonus is applied at all |

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
| Escape once every character is on an exit hex or was exhausted on one | done | `goalMet` counts only unexhausted characters; one exhausted on an exit hex is no loss. Edge: if the last standing characters all become exhausted on exit hexes, `checkVictoryDefeat` ends it as "all characters exhausted" (defeat) |

### 26 · Ancient Cistern
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: cleanse all water pumps | missing | No goal written (placements has tiles only); plays as the default "kill all enemies with every room revealed" |
| Setup: each character adds 3 Curse cards | done | rule 0 `amAdd curse:3` |
| Number of pumps = C: a (2), a+b (3), a+b+c (4) | done | `rooms[2].objectives: [1, 1, "2:C > 2", "3:C > 3"]` (`spawnObjectiveByReference`); placed on l1a by placements; health 0 makes them untouchable scenery (`isUntouchable`) |
| A character adjacent to a pump may give up a bottom action to cleanse it | missing | No such action; a pump can never be removed |
| End of each round: every uncleansed pump summons one normal Black Imp | partial | Rules 1–3 spawn `count: "F"` normal Black Imps per letter while a pump with that letter is present. Never stops, since pumps can't be cleansed. Both "a" imps appear beside the same pump: `spawnHex(forMarker:)` returns the first (lowest-numbered) pump carrying the letter for every spawn |

### 27 · Ruinous Rift
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: protect Hail for ten rounds | done | rule 8 `round: "R == 10"`, `finish: "won"` at the end of round 10 |
| Lose: Hail is killed | done | placements goal `lostAt: {"1": 1}` |
| Objective: Hail, 4+(2×L) HP; ally, enemy of all monsters; initiative 99 for focus only | done | `objectives[0]` escort with no actions (never acts, `EscortAI` "passive escorts don't act"); monsters target escorts (`MonsterAI.gatherEnemies`); focus initiative 99 (`enemyInitiative`, default `resolvedInitiative`); placed at m1a [2,3] |
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
| The treasure tile can be looted only with a Loot action, never by end-of-turn looting | missing | End-of-turn looting calls the same `lootHexes` (BoardCoordinator.swift ~l.1612) with no exception for a goal treasure, so ending a turn on the hex loots it and wins |

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
| End of the round the last treasure tile is looted: a Savvas Icestorm at d (normal 2–3, elite 4) | missing | No rule in `33.json` and no `rules` in placements #33 |
| Door b is locked and opens when destroyed | done | placements `"door": true`; rule 0 also reveals room 2 when the Door is dead |
| Door 1 is locked; opens when every character is on a pressure plate (c) as a turn ends | done | placements lock `between: ["i1b","m1a"]`, `allOnPlates: {markers: ["c"]}` (`keyTurned`) |
| Escape once every character is on an exit hex or was exhausted on one | done | as #25 (same all-exhausted edge) |

### 34 · Scorched Summit
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Elder Drake | done | placements goal `kill: ["elder-drake"]` |
| Objectives: Zephyrs — cannot be damaged; "Move 2, Attack C" just before the Elder Drake's turn | missing | They only come from Special 2's `summon` with `value: "objectiveSpawn"`, which nothing reads (`monsterSummons` fails to decode it; no Swift code mentions `objectiveSpawn` or `initiativeShare`). No Zephyr ever appears |
| The Elder Drake occupies all three hexes of its obstacle | missing | It is a one-hex piece; the map data puts it at l3b (4,6), or the nearest empty hex if that one is impassable (could not confirm which without running). No multi-hex figure support |
| It can be targeted through any of its hexes and targets from any of them | missing | Follows from the above: one hex only |
| The Elder Drake cannot be forced to move | missing | `elder-drake.json` lists `push`/`pull` immunities but `performPushPull`/`beginPushPull` never check immunities (only `applyCondition` does), so it can be pushed and pulled. (It never moves by itself: no movement stat) |
| The huge boulder obstacles cannot be destroyed | missing | They are ordinary obstacles; destroy-obstacle effects (`placeToken .destroyObstacle`, Stone Pummel) have no exception |
| Boss Special 1: nothing printed in the scenario book (stat card: area attack) | partial | The stat card's Attack +0 with its area pattern is executed, anchored on the drake's single hex (the pattern's three "active" hexes are its three-hex body; `AoEResolver` uses the first as origin) |
| Boss Special 2: summon two Zephyrs, then fly to the next perch a → b → c → a | missing | Summon does nothing (above); `custom` "Fly to next perch of boulders" is unmatched text (log: "Resolve the boss's special ability 2 as printed on its stat card"); perches a–c not written. The special does nothing |

### 35 · Gloomhaven Battlements A
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy door 1 and kill the Captain of the Guard | done | placements goal `destroy: [1]`, `kill: ["captain-of-the-guard"]` |
| Setup: City Archers grouped at a and b are placed at the start | partial | Room 1 lists them (2 elite; +2 normal for 3; 4 elite for 4) so they are in play from round 1, but the map data has City Archer positions only on I1b/B2b (unrevealed) and no letters a/b are written, so `placeRevealedMonsters` falls back to its anchor: they stand beside the first monster position on the outside tiles, not on the battlements behind the gate. The standees' `marker: "a"/"b"` is not used for placement |
| Other enemies on the B and I tiles are not set up until door 1 is destroyed or a character/ally moves onto B or I | done | Room 2 (I1b + B2b through the corridors) is revealed only when the barred gate opens; there is no other way in |
| Objective: Door 1, (7+L)×C HP | done | `objectives[0]` health `(7+L)xC`, on the door at l3a [4,7] |
| Door 1 is locked and opens when destroyed | done | placements `"door": true` |
| All demons are allies of the characters and enemies of other monsters, still acting from ability cards | done | `allies: [earth/flame/frost/wind-demon]` → `monster.isAlly`; `MonsterAI.gatherEnemies` inverts sides; `MonsterTurnController` runs their cards |
| A demon that can get within range of the door focuses on it | missing | For an allied monster `gatherEnemies` never returns an objective (`guard !allyFaction`), so demons never attack the door at all — only characters and their summons can |

### 36 · Gloomhaven Battlements B
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Demon | done | placements goal `kill: ["prime-demon"]` — but it is on the board from round 1 (below) |
| Setup: do not set up the Prime Demon | missing | `rooms[0]` (initial) lists `prime-demon` as boss, so it is created at setup; with no map position it is put near the first monster position, acts and can be attacked from round 1 |
| Setup: City Archers are set up at the start | done | Room 1 lists two elite City Archers; I1b and B2b hold starting hexes so `BoardBuilder.buildStartingRoom` reveals them at setup and the archers take their map positions there |
| Objective: Door 1, 10+(2×L) HP; cannot be healed; not an ally of the characters | done | `objectives[0]`; placements `protect: [1]` → `isProtected`: scenery, never an ally (`areAllies`), so not a heal target; characters can't attack it |
| The Prime Demon spawns at e only once door 1 is destroyed | missing | Letter e is written (l3a [4,5]) but no rule spawns anything there |
| The Prime Demon starts with twice its stat-card hit points | done | rule 0 `statEffects` `health: "Hx2"`, `absolute` (`applyScenarioStatEffect`) |
| End of each round with door 1 standing: the Prime Demon suffers (2×C)+L−2 damage | done | rule 5: `present` Door (marker 1) + `damage` `(2xC)+L-2` on prime-demon |
| Door 1 is locked and opens when destroyed by demons | done | placements `"door": true` + `protect`: hostile monsters treat it as an enemy (`gatherEnemies`, `isProtected && maxHealth > 0`) |
| A demon that can get within range of the door focuses on it | partial | The gate is just one more enemy under the normal focus rules (closest first); no preference for it |
| City Archers are allies of the characters, still acting from ability cards | done | `allies: ["city-archer"]` |
| End of each round a demon spawns, cycling a Flame → b Earth → c Frost → d Wind | done | rules 1–4 (`R % 4`); letters a–d written |
| Spawn rank: all normal (2); Flame and Frost elite, Earth and Wind normal (3); all elite (4) | done | `player2/3/4` in rules 1–4 |
| End of round 8: door 1 is destroyed automatically if still standing | missing | No rule |
| Boss specials 1 and 2: ignore the stat card, perform "Move+0, Attack+0" | missing | The stat card's specials run unchanged: Move +2 / Attack −1 (the "Throne moves" text is logged as unresolved and the demon summon does nothing) |

### 37 · Doom Trench
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: all characters escape through the exit (a) | done | placements goal `escape: {marker: "a"}`, six hexes on k2a |
| Lose: a character exhausted while not on an exit hex | done | `lostIfExhausted: ["offExit"]` |
| Setup: each character adds 3 Curse cards | done | rule 0 `amAdd curse:3` |
| Escape once every character is on an exit hex or was exhausted on one | done | as #25 (same all-exhausted edge) |

### 38 · Slave Pens
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and protect the Orchid | done | default kill-all goal (placements goal has only text and a loss) |
| Lose: the Orchid is killed | done | placements goal `lostAt: {"1": 1}` |
| Objective: Orchid, 6+(3×L) HP; ally, enemy of all monsters; initiative 99, Move 3 toward the shaman on the D tile, opening doors and springing traps | partial | HP, side and initiative 99 are right (`objectives[0]`, escort, default initiative). The move's destination is only a `custom` label ("towards the shaman on the D tile") with no map letter, so `EscortTurnController.destination(of:)` finds nothing and he moves 3 toward the nearest revealed enemy by monster focus (`PlayerSideAI.plan`), not toward D1b; he does not head for or open doors |

### 39 · Treacherous Divide
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy the altar (a) | done | placements `goal.destroy: [1]`; altar placed on `d2b` [3,4]; `goalMet` wants it dead with every door open |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` at `R == 1`, `start` → `ScenarioRulesManager.applyAmAdd` (skipped for the "ignore negative scenario effects" perk) |
| Section 1: the altar has 6+(C×L) HP | done | `objectives[0].health` `"6+(CxL)"`; the objective is created with room 2 (D2b) in `ScenarioManager.openRoom` → `addObjectiveEntity` |
| Start of every round: Ice Strong, Fire Inert | done | scenario `rules[1]`: `round: "true"`, `start`, `elements` ice→strong, fire→inert → `applyElementRule` |
| Dark pit obstacles cannot be destroyed | missing | no data or code for it; any obstacle next to a character can be destroyed by an obstacle-destroying card or item (see "Obstacles" above) |

### 40 · Ancient Defense Network
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: occupy both pressure plates (a) simultaneously | done | placements `goal.occupy.markers: ["a"]`, plates on `a4b` [3,2] and `l1a` [2,2]; judged as a turn ends in `goalMet` |
| Setup: each character adds 3 "-1" cards | done | scenario `rules[0]`: `amAdd` `minus1:3` at `R == 1`, `start` |

### 41 · Timeworn Tomb
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: all characters escape through exit (a) | partial | placements `goal.escape` marker a, `leave: true` → `letCharactersLeave` / `everyoneEscaped`. Differs: `everyoneEscaped` asks every non-absent character to be in `escapedCharacters`, so a character exhausted before E1a is revealed (which is not a loss) can never be counted; once the others leave, `checkVictoryDefeat` finds everyone exhausted and declares defeat |
| Lose: any character exhausted (once door 2 is opened) | done | placements `lostIfExhausted: ["any"]`, `lostIfExhaustedOnceRevealed: "e1a"` → `exhaustionLoss` |
| Section 1: Stone Golems and Ancient Artilleries of L1a not set up until a character ends a turn on plate (b), then spawned | missing | they never appear at all: scenario JSON room 2 (L1a) lists only Living Corpses and Living Spirits, the map data names them only under `additionalMonsters`, and no rule spawns anything when the plate is occupied |
| Section 1: door 2 locked until a character has ended a turn on plate (b) | done | placements lock `l1a`–`e1a`, `plate: ["b"]`, `unlocksOnly: true`; plate on `l1a` [2,3] |
| Section 2: at the end of every round each character on (a) is removed, with their summons | done | `letCharactersLeave` (called from `resolvePendingResult` as the round ends) → `leaveScenario`, which removes the character's piece and kills/removes their summons |

### 42 · Realm of the Voice
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all vocal chords | done | placements `goal.destroy: [1…6]`; six objectives placed along `l2a` column 0 |
| Six vocal chords, each 2+(L×C/2) HP rounded down | done | `objectives[0…5].health` `"[2+(LxC/2){$math.floor}]"` (bracket + `$math.floor` handled by the entity-value evaluator) |
| Chord 1 alive: all monsters +1 Attack | missing | scenario `rules[0]` is only a `note` label plus a `present` trigger; it has no effect field, so `ScenarioRulesManager` applies nothing |
| Chord 2 alive: all monsters gain Advantage | missing | `rules[1]`: note + `present` trigger only |
| Chord 3 alive: all monsters heal 1 at the start of their turns | missing | `rules[2]`: note + `present` trigger only (monsters also get no `evaluateTurnRules` call) |
| Chord 4 alive: characters and summons suffer 1 damage at the start of their turns | missing | `rules[3]`: note + `present` trigger only |
| Chord 5 alive: characters and summons gain Disadvantage | missing | `rules[4]`: note + `present` trigger only |
| Chord 6 alive: characters and summons −1 Attack | missing | `rules[5]`: note + `present` trigger only |

### 43 · Drake Nest
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill 4×C drakes | done | placements `goal.killCount` `{"count": "4xC", "of": ["rending-drake", "spitting-drake"]}`, counted from `scenario.killCounts` |

### 44 · Tribal Assault
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the captives) | done | placements goal has only `text`, so the default in `checkVictoryDefeat` applies: every enemy dead, every room revealed |
| Lose: any captive Orchid is killed | missing | no `lostAt` in placements and no scenario rule; a captive's death changes nothing (README/TODO record this) |
| Redthorn (b): 6+(3×L) HP | done | `objectives[0].health` `"6+(3xL)"`; placed on `b1b` [0,2] |
| Redthorn: ally of the characters, enemy of all monsters | done | `escort: true` → player side in `isPlayerSide`; in `MonsterAI.gatherEnemies` |
| Redthorn acts on initiative 01: Move 3, Attack 3, Range 3 | done | `objectives[0]` `initiative: 1`, `actions` move 3 / attack 3 with range 3 → `EscortTurnController` / `EscortAI` |
| Redthorn draws from whichever attack modifier deck the players choose | partial | always the ally deck (`allyDeck: true`); no choice |
| Redthorn adds +1 Attack for each captive freed | missing | freeing a captive isn't modelled, and nothing raises his attack |
| Captive Orchids (a): nine, 4+(2×L) HP each | done | `objectives[1]` `"4+(2xL)"`; rooms list 5+1+2+1 = 9; placed on `m1b` ×5, `l1b`, `b4a` ×2, `b3a` |
| Captives cannot be healed | done | placements `protect: [2]` → not an escort, so `isScenery`: `areAllies` is false and no heal can target them |
| Captives are not allies of the characters; enemies of all monsters | done | `isProtected` → player side for `areEnemies`, in `MonsterAI.gatherEnemies` (`container.isProtected && maxHealth > 0`) |
| Captives: initiative 99 for monster focusing | done | `MonsterAI.enemyInitiative` returns 99.5 for a non-escort objective |
| A character may lose one card from hand to negate one source of damage to a captive | missing | no code; damage to a captive is simply suffered |
| A character adjacent to a captive may forgo an action (discard a card) to free it | missing | no code; captives stay on the board until killed or the scenario ends |

### 45 · Rebel Swamp
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: destroy all totems (a) | done | placements `goal.destroy: [1]`; six placed (`g1a`, `m1b` ×2, `f1b` ×2, `d1b`) |
| Setup: each character adds 2 "-1" cards | partial | scenario `rules[0]` adds `minus1:3` — three cards, not the two in the notes (one of the two sources is wrong; could not check against the book) |
| Six totems, each 1+C+L HP | done | `objectives[0]` `"1+C+L"`, `count: 6`, one per room mention |
| Any monster within two hexes of a totem performs Heal 2, Self at the start of its turn | missing | no rule in the scenario data, no code (grep "totem" finds nothing in the Swift sources) |

### 46 · Nightmare Peak
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Winged Horror | done | placements `goal.kill: ["winged-horror"]` (room 3 must be revealed) |
| Boss Special 1: after it attacks, every egg is destroyed and becomes a normal Night Demon | missing | `winged-horror.json` special 1 carries it as `custom` "Hatch eggs", which only logs "Resolve the boss's special ability 1…". Its two attacks (all adjacent enemies at −1, then +0 at range 3) are made; there are no eggs |
| Boss Special 2: after its attacks it summons C eggs (numbered tokens, 2+(L/2) HP rounded up, initiative 99 for summon focusing) | missing | special 2 carries it as `custom` "Summon [C] eggs": log line only. Move −1 and Attack +0 are made; no egg objective exists in the scenario data |

### 47 · Lair of the Unseeing Eye
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Sightless Eye | done | placements `goal.kill: ["the-sightless-eye"]` |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| Section 1: at the end of each round every character and summon still on the J tile suffers 3+L damage | missing | no rule in the scenario data, no code |
| Section 1: the Sightless Eye cannot be forced to move or have its position changed | missing | `the-sightless-eye.json` lists `pull`/`push` in `immunities`, but `performPushPull` checks only scenery and Heavy Greaves; `entity.immunities` is read only for conditions (`applyCondition`), so the Eye can be pushed and pulled |
| Boss Special 1: before attacking, summons one Deep Terror — normal (2 characters), elite (3–4) | done | special 1: `summon` deep-terror `player2: normal, player3/4: elite`, then the area attack → `performSummon` → `summonMonster` (adjacent hex, doesn't act this round) |
| Boss Special 2: before attacking, summons one Deep Terror — normal (2–3), elite (4) | done | special 2: `summon` deep-terror `player2/3: normal, player4: elite`, then the area attack |

### 48 · Shadow Weald
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Dark Rider | done | placements `goal.kill: ["dark-rider"]` |
| Setup: all characters start with Muddle | done | scenario `rules[0]`: `gainCondition` `muddle` at `R == 1`, `start` |
| Setup: the Dark Rider is not placed on the map at the start | missing | room 1 lists `dark-rider` as a boss, so `openInitialRooms` creates it and `placeRevealedMonsters` stands it on the board at setup (no map slot of its own: it takes the first monster position) |
| The Dark Rider is removed from the map immediately after any melee attack | missing | no code (grep "dark-rider"/"Dark Rider" finds only the "X = hexes moved" attack variable) |
| Not on the map at the start of its turn: appears on a marked hex, a→f in order, then acts | missing | no code, and letters a–f are not written in placements (`"48"` has empty `tiles`) |
| Boss Special 2: between moving and attacking, summons 1 normal Forest Imp (2 characters) or 2 (3–4) | partial | order is right (move, summon, attack −1). Count wrong at 2 characters: the two specs each summon one imp at every count (see "Monster Summon specs"), so 2 imps appear at 2 characters as well as at 3–4 |

### 49 · Rebel's Stand
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Siege Cannon | done | placements `goal.kill: ["siege-cannon"]`; it stands on the map's Ancient Artillery position in L3a |
| Siege Cannon has H×2 HP (H = elite Ancient Artillery's hit points) | done | `siege-cannon.json` health per level is exactly twice the elite artillery's (14/18/…/40 against 7/9/…/20) |
| Siege Cannon does not act; initiative 99 for summon focusing | missing | it is an ordinary boss with `deck: "ancient-artillery"`: it draws Ancient Artillery cards, acts at their initiative and shoots (Attack 3–5, Range 5–7). Nothing in the code names it |
| Each round the City Archer closest to the artillery does not act but performs Move 3 toward a non-b hex beside it | missing | the scenario JSON has no `rules` at all; no code; archers take their normal turns |
| If that archer is then adjacent, the cannon fires: characters and summons in the b hexes, the columns above them and all of G suffer an elite artillery's Attack | missing | no rule, no code, no b letters in placements |
| No City Archers on the map at the end of a round: one normal City Archer spawns at (a) | missing | no rule in the scenario data, no letter a in placements |

### 50 · Ghost Fortress
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles | done | placements `goal.loot: "goal"`; the four tiles carry treasure id `goal` in the map data |
| Setup: two starting rooms; no more than half the characters (rounded up) may enter from the same room | partial | both rooms (B3b, B2b) are revealed at setup with three starting hexes each (`BoardBuilder.buildStartingRoom`); `placeCharacter` accepts any free starting hex, so the per-room cap isn't enforced (two characters can share a room, three can all start in one) |
| Treasure tiles can only be looted with a Loot action, never by end-of-turn looting | missing | `lootAtEndOfTurn` loots a goal tile like any other (see "Goal treasure tiles") |

### 51 · The Void
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Gloom | done | placements `goal.kill: ["the-gloom"]` |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| Each character and character summon suffers 2 damage at the end of each of their turns | partial | scenario `rules[1]` (`alwaysApplyTurn: "after"`, `characterWithSummon`, damage 2) is evaluated only for characters — `evaluateTurnRules(.turnEnd, …)` has one call site, in `advanceToNextFigure`, for `.character`; summons never suffer it. The character's damage is queued in `ruleDamageDue`, which is drained only after round-start and round-end rules (`afterRuleDamage`), so it lands as the round ends, not as the turn ends |
| Dark pit obstacles cannot be destroyed | missing | see "Obstacles" above |
| Boss Special 2: before attacking, the Gloom jumps to a marked hex, a→b→c in order | missing | special 2 is `teleport` then Attack +1, Range 5, Poison/Wound/Stun. `.teleport` is not handled in `executeCard` (falls to `default`), and letters a–c aren't in placements; the Gloom makes the attack from where it stands |

### 52 · Noxious Cellar
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: every character loots one treasure tile | done | placements `goal.loot: "each"`; `mayLootGoalTreasure` lets each character loot only one; `goalLooters` tracks who has |
| Lose: a character is exhausted before looting a treasure tile | done | placements `lostIfExhausted: ["beforeLoot"]` → `exhaustionLoss` |
| Setup: each character adds 2 Curse cards | partial | scenario `rules[0]` adds `curse:3` — three, not the two in the notes (one of the two sources is wrong; could not check against the book) |
| Setup: characters may only start in sections of the center room that contain monsters | missing | the four starting hexes of M1a are all offered whatever the character count; nothing ties a starting hex to monsters being in its section |
| Center-room obstacles cannot be destroyed or moved through in any way, and block line of sight for ranged abilities | missing | they are ordinary obstacles (see "Obstacles" above) |
| Treasure tiles are looted only by a Loot action, or by an adjacent character forgoing a bottom action; never at end of turn | missing | end-of-turn looting takes a goal tile like any other, and there is no "forgo a bottom action to loot an adjacent tile" |

### 53 · Crypt Basement
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: survive ten rounds (complete at the end of round 10) | done | scenario `rules[5]`: `R == 10` (end of round) → `finish: "won"`; `hasOwnWinCondition` switches the kill-all default off |
| Setup: each character adds 3 Curse cards | done | scenario `rules[0]`: `amAdd` `curse:3` |
| All doors locked; they open by themselves at the start of rounds 2 (a), 4 (b), 6 (c), 8 (d) | done | placements `locks` `m1a`–`j1a`/`j2a`/`d2a`/`d1a` with `afterRound` 1/3/5/7 (both doors of a pair), and scenario `rules[1…4]` open rooms 2/4/3/5 at the start of rounds 2/4/6/8. The lock's key turns in `updateLocks(roundEnded: true)`, so the door opens as the previous round ends, before cards are chosen |

### 54 · Palace of Ice
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: the Seeker of Xorn ends a turn adjacent to the altar (a) with the staff fully charged | missing | no placements entry for 54; plays as "kill all enemies" (default goal) |
| Lose: the Seeker of Xorn becomes exhausted | missing | no loss written; nothing identifies the Seeker on the board |
| All Cave Bears add Poison to all their attacks | done | scenario `rules[0]` `statEffects` on `cave-bear` (`actions`: condition poison) → `MonsterManager.applyScenarioStatEffect` sets `additionalStatActions`, read by `GameMonster.attackStat` and applied in `MonsterAbility.attack` |
| Section 1: only the character equipped with the Staff of Xorn can damage the Harrower Infesters | missing | no code; anyone damages them (item gh-114 is only a ranged-attack Poison/Muddle item in `BoardCoordinator+Items`) |
| Section 1: each point of damage to an Infester puts a token on the staff; fully charged at 2×C×(L+1) | missing | no counter anywhere |

### 55 · Foggy Thicket
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot the treasure tile in the third room | missing | the scenario has no rooms and no `ScenarioMaps/55.json`; `GameManager.enterBoard` returns when there is no map, so no board ever starts (the setup list shows "No map") |
| Setup: each character adds 3 "-1" cards | partial | scenario `rules[0]` (`amAdd` `minus1:3`) is in the data and the manager would apply it at round 1, but no round is ever played |
| No fixed map: a random dungeon from a modified dungeon deck | missing | `rules[1].randomDungeon` is decoded (`ScenarioRule.randomDungeon`) and read by nothing; random dungeons are an open TODO item |
| Monster cards used: only Mangy, Wild, Scaled, Cutthroat, Tribal, Infected | missing | `randomDungeon.monsterCards` unused |
| Room cards used: only Trail, Encampment, Clearing, Road, Cabin, Crossroads | missing | `randomDungeon.dungeonCards` unused |
| Penalties: minor in the second room, major in the third | missing | not in the data, no code |
| Third room: the "12" hex holds a treasure tile, lootable only with a Loot action | missing | no code |

### 56 · Bandit's Wood
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and keep at least one captive Orchid alive) | done | no goal written, so the default: every enemy dead with every room revealed; the "at least one" half is the loss rule below |
| Lose: all three captive Orchids are killed | done | scenario `rules[0]`: `always`, `once`, `requiredRooms: [4]`, objective "Captive Orchid" marker a `dead` → `finish: "lost"` |
| Captive Orchids (a): three, 4+(2×L) HP each | done | `objectives[0]` `"4+(2xL)"`; room 4 lists three; placed on `m1b` [0,1], [1,0], [2,0] |
| Captives are allies of the characters and enemies of all monsters | done | `escort: true` → player side; monsters focus them (`MonsterAI.gatherEnemies`) |
| Captives act on initiative 50: Move 3, Attack 3 | done | `initiative: 50`, `actions` move 3 / attack 3 → `EscortTurnController` (each living Orchid in turn) |
| Captives draw from whichever character attack modifier deck the players choose | partial | always the ally deck (`allyDeck: true`) |

### 57 · Investigation
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Infiltrator | done | placements `goal.kill: ["infiltrator"]` |
| Section 2: when the elite City Guard of the main barracks dies, replace him with the Infiltrator | partial | scenario `rules[0]`: `requiredRooms: [3]`, city-guard marker "2" `dead` → spawns `infiltrator:+1` (boss). The spawn has no marker, so `spawnFromScenarioRule` puts him at the first other enemy's position (nearest empty hex), not where the guard fell |
| The Infiltrator is an elite Harrower Infester one level above the scenario level (maximum 7) | done | `infiltrator.json` stats equal the elite Harrower Infester's at each level and it uses that deck; `infiltrator:+1` → `MonsterNameSpec.level(forScenarioLevel:)`, clamped to 0…7 |
| Section 3: spawn at (a) 2 normal City Guards (2 characters), 1 normal + 1 elite (3), 2 elite (4) | done | scenario `rules[1]`: `requiredRooms: [4]`, three spawn entries by exact character count, `marker: "a"`; letter a on `f1b` [1,1] → `spawnHex(forMarker:)` |

### 58 · Bloody Shack
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Harvester | done | placements goal `kill: ["the-harvester"]` (`goalMet`; needs room 3 revealed and the boss dead) |
| Setup: two starting rooms, at most half the characters (rounded up) in the same one | partial | Both start tiles (C2a, D1b) are revealed at setup (`BoardBuilder.buildStartingRoom`) with two starting hexes each, so 3–4 characters are split by lack of hexes; `placeCharacter` has no check, so two characters can both start in one room |
| Section 1: only the character on the "Vengeance" quest may loot the treasure tile | missing | The goal chest on G2b is looted by anyone (`lootHexes`); no quest check |
| Section 1: looting it gives that character the Occult Dagger | missing | No dagger state anywhere in the Swift sources |
| Section 2: the City Guard is one level above the scenario level (max 7) and is the Harvester | done | `58.json` room 3 `the-harvester:+1` type boss; `MonsterNameSpec.level` clamps to 7; `monster/the-harvester.json` carries the elite City Guard's stats |
| Each bone pile (a) has L+(2×C) HP | done | `58.json` objectives `health: "L+(2xC)"`, count 4, room 3 `objectives: [1,1,1,1]`; placed on the four nests by placements tile `b1a` |
| Harvester gains Shield 1 for each bone pile on the map | missing | `58.json` has no `rules`; the Harvester only has its stat-card Shield |
| Harvester heals C−1 at the end of each round for each bone pile | missing | no rule, no code |
| The Occult Dagger's holder adds PIERCE 4 to attacks on the Harvester | missing | no dagger |

### 59 · Forgotten Grove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot the treasure tile | done | placements goal `enemies: "all"`, `loot: "goal"` |
| The treasure tile is looted only with a Loot action, never at end of turn | done | placements `lootActionOnly: true`; `lootHexes` skips the goal chest unless `byLootAction` (only `collectLootInRange` passes it). Uncommitted in the working tree when read. Swift Bow's loot-every-hex-entered (`BoardCoordinator+Movement` line 138) also doesn't count as a Loot action |

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
| Odd rounds: only Group 1 (Oozes, Giant Vipers) activates | missing | `61.json` rules 0/1 `toggleOff`/`toggleOn` only set `off` on each standee, which nothing reads: every monster type acts every round. Worse, `"allied": ["flame-demon","frost-demon"]` makes Group 2 fight on the players' side (`ScenarioManager` sets `isAllied`, `MonsterAI.isAllyFaction` = `isAlly || isAllied`): they attack Oozes and Vipers, never the party, and the party can't target them |
| The inactive group is unaffected by all abilities | missing | no code; "off" standees are attacked and affected as usual |
| Any figure may move through an inactive monster's hex but not end there | missing | no code |
| Even rounds: the opposite (Group 2 acts, Group 1 doesn't) | missing | same as the odd-round row |
| Treasure tiles are looted only with a Loot action | done | placements `lootActionOnly: true` (see #59; uncommitted when read) |

### 62 · Pit of Souls
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Hungry Soul | done | placements goal `kill: ["hungry-soul"]` |
| Every round start: one Living Bones at (a) and one at (b): normal/normal (2), elite/normal (3), elite/elite (4) | done | `62.json` rule 0 `round: "true"`, `start: true`; (a) p2 normal / p3 elite / p4 elite, (b) normal / normal / elite; markers a, b on tile `m1a` |
| When ten Living Bones have been killed, read Section 1 | done | placements `rules`: `killed` living-bones ≥ 10, `always`, `once` (merged in `EditionDataStore`; `killCount` reads `scenario.killCounts`) |
| Section 1: an elite Living Bones spawns at (c) as the Hungry Soul | done | that rule spawns `hungry-soul` (boss, living-bones deck, elite Living Bones' move/target) at marker c on `b2b` |
| Its HP is (H×C)/2 rounded up | partial | `monster/hungry-soul.json` health `"(6xC)/2"` … `"(14xC)/2"` is rounded down: one short with 3 characters where H is odd (levels 2, 4, 5, 6) |
| Extra Shield 5 on top of its regular Shield | partial | stat card has a flat Shield 5 at every level; an elite Living Bones' own Shield 1 (levels 1–4) or 2 (levels 5–7) isn't added |
| +2 Attack on all its attacks | done | stat attack is the elite's +2 at every level (4/4/5/5/6/6/6/6 against 2/2/3/3/4/4/4/4) |
| The round-start spawns continue after Section 1 | done | rule 0 is never disabled |
| Its Shield drops by 1 for each other Living Bones on the map (minimum 0) | missing | no rule or code; Shield stays 5 |

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
| Door 1 is locked; it opens when a character occupies plate (a) at the end of their turn | partial | lock `j1b`–`c1a` is `held: ["a","b"]` from the start: it opens the moment a character steps on (a) (`moveAlong` → `updateLocks`), not as the turn ends, and shuts again if they step off before Section 1 |
| Section 1: doors 1, f, g, h stay open only while a corresponding plate is occupied; a door closes when its last occupied plate is left | done | four `held` locks; `updateLocks` opens/shuts, `Pathfinder` treats `shutDoors` as closed |
| A figure in a door as it closes suffers trap damage and moves to the nearest unoccupied hex | partial | `shutDoor`: `levelManager.trap()` through `sufferDamage`, then `nearestEmptyHex`; a character can't lose cards to negate it |
| Plate (a) ↔ door 1; (b) ↔ 1 and f; (c) ↔ f and g; (d) ↔ g and h | done | `held` lists a,b / b,c / c,d / d on `j1b–c1a`, `c1a–d1a`, `d1a–d2a`, `d2a–c2b` |
| Doors i and j are locked and open permanently when a character ends a turn on plate (d) | done | locks `d1a–a1a` and `d2a–a2a` with `plate: ["d"]` |

### 67 · Arcane Library
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Arcane Golem | done | placements goal `kill: ["stone-golem"]` (the only Stone Golem is in room 3) |
| Door 2 is locked and stays open only while a character occupies a plate (a) | done | lock `a2a–m1a` `held: ["a"]`; markers a on `g1b` and `m1a` (`testADoorHeldOpenByAPlate`) |
| A figure in the door as it closes suffers trap damage and moves to the nearest unoccupied hex | partial | `shutDoor` as in #66; not negatable by losing cards |
| Section 2: the elite Stone Golem is one level above the scenario level (max 7) and is the Arcane Golem | done | room 3 `stone-golem:+1` elite; rule 0 statEffect `name: "arcane-golem"` |
| It has H×C HP (H = an elite Stone Golem's regular HP) | done | rule 0 statEffect `health: "HxC"`, `requiredRooms: [3]` (`applyScenarioStatEffect`) |
| It cannot enter or pass through door 2 | missing | only in the rule's note text; no movement restriction in `MonsterAI` / `Pathfinder` |

### 68 · Toxic Moor
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the tree — see Lose) | done | default goal; placements goal has only `text` |
| Lose: the tree is destroyed | missing | no `lostAt` in the placements goal; the tree's death ends nothing |
| Setup: all characters start with POISON (scenario effect) | done | `68.json` rule 0 `R == 1`, `start`, `gainCondition poison` |
| Setup: the tree (a) is set up at the start | done | room 1 (initial) lists objective 1; placements tile `b1b` puts it on the tree-3 obstacle, which the map data draws from the start |
| Tree: 17 HP | done | `68.json` objectives `health: 17` |
| It suffers 2 damage at the end of every round, even before its room is revealed | done | rule 1 `round: "true"` (end of round), `damage 2` on objective Tree marker a |
| Once its room is revealed, no damage in a round when no Rending Drake is on the M tile | missing | rule 1 has no such condition: the tree is dead at the end of round 9 whatever happens |
| Once revealed it can be healed like an ally; no other ability can affect it | partial | it is `escort: true`, so it can be healed — but as an escort it is also focused and attacked by monsters (`MonsterAI.gatherEnemies`) and takes conditions |
| A character or summon with POISON entering a water hex suffers trap damage | missing | water is plain difficult terrain; `moveAlong` has no poison check |
| A summon with POISON treats water hexes like traps | missing | no code in `SummonAI` / `Pathfinder` |

### 69 · Well of the Unfortunate
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: bring the doll to a hex adjacent to the well (a) | partial | placements goal `reach: {"marker": "a", "adjacent": true}`: any character ending a turn beside the well wins; the doll isn't modelled |
| Setup: choose a character to hold the doll | missing | no doll state |
| The doll changes hands only by another character's Loot action with the holder in range | missing | no doll state |
| If the holder is exhausted the doll is dropped in their hex | missing | no doll state |
| Door 1 is locked; opens when a character ends a turn on plate (b) | done | lock `l3a–j1a` `plate: ["b"]`, marker b on `b1b` |
| Section 1: spawn at (c) 2 Scouts + 1 Shaman: normal/normal (2), elite/normal (3), elite/elite (4) | done | `69.json` rule 0 `requiredRooms: [3]`, `once`; scouts p2 normal / p3 elite / p4 elite ×2, shaman normal / normal / elite; marker c on `l3a` |
| Section 1: two damage traps appear at (d); a non-flying figure standing there springs one at once | missing | marker d is written on `b1b` but no rule or code places traps |

### 70 · Chained Isle
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all demons | done | placements goal `kill: ["night-demon","wind-demon"]` |
| A normal Living Spirit spawns at the end of every round: (a) odd / (b) even (2); (a) odd, (a)+(b) even (3); (a)+(b) every round (4) | done | `70.json` rules 0 (`R % 2 == 1`) and 1 (`R % 2 == 0`), end-of-round; markers a on `l3a`, b on `l1b` |
| Living Spirits cannot be damaged in any way (conditions and other effects still apply) | missing | no rule, statEffect or code; they take damage and die as usual |
| Each time a demon dies the players may remove one Living Spirit | missing | no rule or code |

### 71 · Windswept Highlands
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles, then every character on an exit hex (a) | done | placements goal `loot: "goal"`, `escape: {"marker": "a"}` (four hexes on `g2a`) |
| Lose: a character exhausted while not on an exit hex | done | placements `lostIfExhausted: ["offExit"]` |
| Wind: at the end of every round every character and summon is forced one hex (left, up, right, down in turn), in initiative order | missing | `71.json` rules 0–3 are notes only ("Move left" …); no forced move |
| Spitting Drakes start asleep and do not act until woken | missing | no dormant state is set; drakes act from round 1 |
| A drake wakes when attacked, damaged, given a negative condition, or when a character or summon ends a move adjacent to it | missing | no code |
| Summons do not attack a sleeping drake unless directly controlled | missing | no code |
| A drake that wakes follows the rules for a newly spawned monster | missing | no code |
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
| Six boulders start at (a) and (b) and each row rolls 1, 2 or 3 hexes left at the end of every round, a different number per row, chosen by the players | missing | the six are fixed `boulder-1` obstacles in the map data; `73.json` rule 0 is a note ("Roll boulders down.") |
| Boulders are unaffected by abilities and overlays and destroy obstacles in their way (traps stay) | missing | no boulder mechanic |
| A figure a boulder moves onto suffers trap damage; if the boulder stops there the figure is forced one hex left | missing | no boulder mechanic |
| A boulder reaching the leftmost hex re-enters at (b) and keeps moving | missing | no boulder mechanic |
| Dark pit obstacles cannot be destroyed | missing | `dark-pit` is an ordinary obstacle: the destroy-obstacle abilities (`BoardCoordinator+Movement` `.destroyObstacle`) accept any obstacle hex |
| Section 1: the Inox on tile E cannot enter or pass through door 1 | missing | no movement restriction; once the door is open they come through |

### 74 · Merchant Ship
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (keeping the ship afloat — see Lose) | done | default goal: every enemy dead with both doors open |
| Lose: a water tile must be added but the B tile is full | missing | water tiles aren't added, so nothing can fill |
| Setup: remove the water tiles at (d) for three characters | missing | the 12 water hexes of `b1a` are always there; marker d is written but unused |
| A water tile is added to the B tile at the end of every even round (2) or every round (3–4) | missing | `74.json` rule 0 (`R % 2 == 0 \|\| C > 2`) is a note only ("Add water tile.") |
| A character picks up a water tile by looting and bails it by ending a turn on (e); one tile at a time | missing | marker e is written but unused; no carried-tile state |
| Doors 1 and 2 are locked and open at the end of rounds 3 and 6 | done | locks `g2b–i2b` `afterRound: 3`, `g2b–i1a` `afterRound: 6`, and rules 1/2 (`R == 3` → rooms [2], `R == 6` → rooms [3]) |
| Section 1: 1 normal Deep Terror at (a) (2); 1 elite at (a) (3); 2 normal at (b) (4) | done | rule 3 `requiredRooms: [2]`, `once`: marker a p2 normal / p3 elite, marker b p4 normal ×2 |
| Section 2: at (c) 2 normal Deep Terrors (2–3) or 2 elite (4) | done | rule 4 `requiredRooms: [3]`, `once`, count 2, marker c |

### 75 · Overgrown Graveyard
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: dig up all graves and kill the Bloated Regent | done | placements goal `destroy: [1,2,3]`, `kill: ["bloated-regent"]` |
| A character digs up a grave by spending 1+C movement while adjacent (not all at once) | partial | graves are objectives with `health: "1+C"` that are attacked: 1+C damage instead of 1+C movement |
| A dug-up grave spawns a Living Corpse in the nearest empty hex: normal (2); normal for (a), elite for (b) (3); elite (4) | partial | rules 0/1 give the right types and the corpse rises where the grave stood (`fallenObjective`), but each rule is `once` with a `dead` trigger that needs every (a) (or (b)) grave in play gone: destroy room 1's single (a) grave before the second room is revealed and the rule fires for it alone, so the other three (a) graves spawn nothing; reveal the second room first and all four corpses rise together at the last grave (`count: "F"`) |
| Section 1: grave (c) is dug up like the others and spawns an elite Living Corpse, the Bloated Regent | done | rule 2 `requiredRooms: [3]`, grave c `dead` → `bloated-regent` (boss, elite Living Corpse's stats) at marker c |
| The Regent has (H×C)/2 HP rounded up | partial | `monster/bloated-regent.json` `"10xC/2"` … `"25xC/2"` is rounded down: one short with 3 characters at levels 2–7 (H odd) |

### 76 · Harrower Hive
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: reveal all rooms and kill all enemies | partial | no placements entry: the default goal needs every enemy dead and every door open. The 23 walls are doors (below), so every one must be opened, not just one per room |
| Setup: each character discards three ability cards (scenario effect) | missing | `76.json` has no `rules`; no code |
| Walls (a): C+(L/2) HP rounded up, destroyed by damage, attacked like an enemy | missing | the map data's `breakable-wall` connectors become ordinary closed doors (`BoardBuilder.addRoom` treats every non-corridor connector as a door); a character opens one by walking into it, with no hit points and no attack |
| Summons attack walls only when directly controlled | missing | walls aren't attackable at all |
| Each tile is a separate room; a destroyed wall reveals the room(s) behind it and becomes a corridor | partial | opening a wall-door reveals the tile behind it and its room's monsters; the hex stays an open door. From reading `BoardBuilder` only (not run): a room first entered through one of the map data's empty tile copies (e.g. the start room's wall at (3,3) into E1b) gets no monster slots, so its monsters are placed from the fallback anchor (`placeRevealedMonsters`: first starting hex), and its obstacles, traps and treasure are skipped later as `preexisting` cells |
| When a wall is destroyed all enemies adjacent to it gain STUN | missing | no code |

### 77 · Vault of Secrets
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: loot all treasure tiles and kill all City Guards | done | placements goal `loot: "goal"` + `kill: ["city-guard"]` (`goalMet`: both goal chests on B2b/B3b looted, rooms 1–2 revealed, no guard alive). Only the guards the rooms place exist — see the two spawn rows |
| Lose: any City Guard occupies a pressure plate (a) | missing | no `rules` in 77.json; placements `tiles` is `{}` — no (a) plates written, no loss check anywhere |
| Section 1: left treasure tile looted → City Guard spawns at (b): normal (2) / elite (3–4) | missing | no rule, no (b) marker; looting a goal chest only bumps `goalTreasuresLooted` |
| Section 1: right treasure tile looted → City Guard spawns at (c): normal (2–3) / elite (4) | missing | no rule, no (c) marker |
| City Guards do not act normally: "Move 2" toward the closest plate (a), then every non-move ability on their card | missing | guards draw the City Guard deck and act with normal `MonsterAI` focus/movement |
| A City Guard entering the hex of door 1 opens it and reveals the room | missing | monsters path with `canOpenDoors: false`; door 1 opens only when a character walks in |

### 78 · Sacrifice Pit
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and stop the sacrifice) | done | default goal in `checkVictoryDefeat` (all hostile dead, all doors open); no placements entry for 78 |
| Lose: a Cultist (b) starts its turn adjacent to the altars (d) while the victim is adjacent too | missing | no rule, no markers, no victim; README goal table says the same |
| Objective: Victim (a), a token with no HP, immune to forced movement/IMMOBILIZE/STUN, moves only as described | missing | 78.json has no `objectives`; nothing stands at (a) |
| The two Cultists (b) don't act normally: "Move+0" together to carry the victim to (c)/the altar | missing | they are `cultist-scenario-78` (elite, deck `cultist`) and act as ordinary Cultists; rule 0's two `custom` actions are labels only |
| After the Cultists move, the victim moves the same number of hexes to stay adjacent to them | missing | no victim |
| Cultists (b) are immune to IMMOBILIZE and STUN | done | rule 0 (`requiredRooms: [2]`, persistent `statEffects`) → `immunities: ["immobilize","stun"]` → `MonsterManager.applyScenarioStatEffect` → `applyCondition` refuses them. (Victim: n/a, not in the game) |
| Cultists (b) and the victim are immune to forced movement | missing | only the label "Immune to forced movement" (`custom` action in `additionalStatActions`); push/pull code never looks at it |
| Cultists (b) and the victim can open doors | missing | label "Can open doors" only; monsters never open doors |

### 79 · Lost Temple
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Betrayer | done | placements goal `kill: ["the-betrayer"]` |
| Lose: Fish is killed | missing | goal has no `lostAt`; Fish's death (`handleDeath` `.objective`) changes nothing |
| Setup: plates in play — (a) for 2 characters, (a)+(b) for 3, (a)+(b)+(c) for 4 | missing | placements 79 has no markers/`plates`; no plate is drawn or tracked |
| Objective Fish: 6+(2×L) HP, ally to the characters, enemy to all monsters, starts on plate (a) of the D tile | done | `objectives[0]` (`escort`, `health: "6+2xL"`, `allyDeck`), placed at placements `d2a [0,3]`; escorts are player-side and in `MonsterAI.gatherEnemies` |
| Fish acts on initiative 99: back to his starting hex if moved off, then "Attack 3" on all adjacent enemies | missing | his action is a `custom` wrapper with the attack nested in `subActions`; `escortMove`/`escortAttack` read top-level actions only → `hasEscortActions` is false → `advanceToNextFigure` gives him no turn |
| Door 1 is locked; it opens when all Stone Golems are killed | done | placements lock `d2a–m1a` with no key + rule 0 (`killed: all` stone-golem → `rooms: [2]` → `openScenarioRooms`); `ScenarioLockTests` covers it |
| Stone Golems cannot act or be affected until every plate in play is occupied at the end of a turn; then they draw a card as if just revealed | missing | golems are placed active with the start room and act from round 1 |
| Boss special 1: summon Giant Vipers (1 elite for 2; 1 normal + 1 elite for 3; 2 elite for 4), then all characters and their summons are forced to "Move 4" away from the Betrayer | partial | the summon runs (`special[0]` → `performSummon`) but counts are wrong: all three `valueObject` entries are summoned and `count: 2` is ignored → 2p: 3 normal, 3p: 2 normal + 1 elite, 4p: 2 normal + 1 elite. The forced Move 4 is not in the data or code at all |
| Boss special 2: pull everyone adjacent; mind-control the character acting latest (Move 2 + top action of leading card, both cards discarded) and their summons | missing | `special[1]` is the single label "Mind Control"; the game logs "Resolve the boss's special ability 2 as printed on its stat card" and does nothing |

### 80 · Vigil Keep
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: every character loots one treasure tile, then all characters reach the B tile | done | placements goal `loot: "each"` + `escape: {tile: "b1a"}` (`goalMet`, judged as a turn ends); `ScenarioGoalTests` uses #80 |
| Lose: any character becomes exhausted while not on the B tile | done | `lostIfExhausted: ["offExit"]` → `exhaustionLoss` |
| Until a character has looted a treasure tile, they have Disadvantage on all attacks and cannot use any items | missing | `goalLooters` is read only by the goal and the loot check; nothing touches attacks or items |
| Each character may loot only one treasure tile | done | `mayLootGoalTreasure` (`lootHexes` skips a second goal chest for the same character) |

### 81 · Temple of the Eclipse
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Colorless | done | placements goal `kill: ["the-colorless"]` |
| Section 1: a character adjacent to the altar (a) at end of turn may discard the Crystal of Zenith or Sphere of Midnight → the Colorless suffers 2×C damage | missing | no rule, no (a) marker, no such tokens |
| Start of every round: Light and Dark Strong; Fire, Ice, Wind, Earth Inert | done | rule 0 (`round: "true"`, `start: true`, six `elements`) → `applyElementRule` each `roundStart` |
| First treasure tile looted gives the Crystal of Zenith, the second the Sphere of Midnight | missing | the two "G" chests loot as plain goal treasure (`lootTreasure` returns "Goal treasure", nothing is held) |
| Boss special 1: consume Dark → summon Night Demon (normal 2–3 / elite 4), then gain INVISIBLE | partial | INVISIBLE on self is applied (`.condition` + `specialTarget: self`). The Dark consume inside the special is never paid, so Dark is not consumed and the Night Demon is never summoned (data types per count are right) |
| Boss special 2: consume Light → summon Sun Demon (normal 2 / elite 3–4), then Shield 1 and heal self | partial | "Heal 4, self" runs (`performHeal`). The Light consume is never paid → no Sun Demon; the special's Shield 1 is not applied |

### 82 · Burning Mountain
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal A: after the chest is looted, the character holding its items ends a turn on (g) and removes one item from the game | partial | placements goal `lootIDs: ["62"]` + `either: [{reach: {marker: "g"}}, …]`: any character ending a turn on g wins; no holder is tracked and no item is removed |
| Goal B: after the chest is looted, all characters return to an entrance hex before becoming exhausted | partial | `either: […, {escape: {start: true}}]`: every *unexhausted* character on a starting hex as a turn ends; an exhausted character doesn't prevent it |
| If the scenario is lost, the treasure tile is reset (not kept) | missing | `lootTreasure` records `gh-82-62` in `game.lootedTreasures` and hands over items 110/115 at once; `finishScenario(success: false)` doesn't undo it |
| All doors locked; each elite killed opens one door, in order a, b, c, d, e, f | done | six placements locks with `eliteKills: 1…6` (`k1a–c1a`, `k1a–d1a`, `c1a–i1b`, `b2b–d1a`, `c1a–empty`, `empty–d1a`); `boardState.eliteKills` counted in `handleDeath`; `ScenarioLockTests` covers it |

### 83 · Shadows Within
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal; 83.json has no rules and no placements entry |
| Section 1: characters and their summons within 2 hexes of the altar (a) suffer 1 damage at the start of their turns | missing | no rule (`alwaysApplyTurn`), no (a) marker |
| Section 1: monsters within 2 hexes of the altar heal 1 at the start of their turns | missing | no rule |
| Flame Demons are not set up until all Cultists are dead | missing | room 3's two Flame Demons are placed when its door opens (TODO.md lists #83 under "not set up until a trigger") |
| Section 2: all characters and their summons suffer 2 damage at the start of each of their turns | missing | no rule |
| Section 2: start of every round, Fire is Strong | missing | no rule |

### 84 · Crystalline Cave
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies (and protect the crystal) | done | default goal (placements goal sets only a loss, so kill-all with every door open still applies) |
| Lose: the crystal is destroyed | done | placements goal `lostAt: {"1": 1}` → `goalLost` |
| Objective: crystal (a) with 4+C+(2×L) HP | done | `objectives[0].health: "4+C+(2xL)"`, placed on placements `l2a [0,3]` (the map's crystal obstacle) |
| The crystal cannot be healed and is not an ally of the characters | missing | it is `escort: true` and not in placements `protect`, so `isPlayerSide`/`areAllies` make it an ally and heals can target it (README: "treated as an ally") |
| Monster focus: a monster that can move within range to attack the crystal focuses on it, otherwise normal focus | partial | the crystal is a legal focus (escorts are in `gatherEnemies`) but is chosen only by the normal closest-enemy rules; no priority |
| Twice, when the crystal would suffer damage, a character may lose a hand card to negate it | missing | `sufferDamageWithMitigation` offers card loss only for a character's own damage |
| Start of round 4: corridor on (b), reveal the adjacent room | missing | no rule; A3a sits behind a `breakable-wall` map door that a character opens by walking in, at any time |
| Start of round 6: corridor on (c), reveal the adjacent room | missing | same — A2b behind an ordinary door, no round timing |
| Start of round 9: corridor at (d), reveal the adjacent room | missing | same — E1b behind an ordinary door, no round timing |

### 85 · Sun Temple
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal; no rules, no placements entry |
| Setup: two starting rooms; no more than half the characters (rounded up) from the same room | partial | both rooms are revealed at setup (`buildStartingRoom` adds every tile with starting hexes) and each has 2 starting hexes, which caps 3–4 characters correctly; with 2 characters both can be placed in one room — nothing checks the split |
| Section 1: all Sun Demons are enemies to both the characters and all other monster types | missing | no `allies`/rule; Sun Demons are ordinary enemies and no third faction exists |
| With "Sun-Blessed": start of every round Light Strong, Dark Inert | missing | no rule; party achievements aren't consulted by scenario rules |

### 86 · Harried Village
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: save seven villagers | done | placements goal `arrive: {objective: 1, marker: "b", count: 7}` → `noteEscortArrival` |
| Lose: five villagers are killed | done | `lostAt: {"1": 5}` |
| Villagers (a): 3+L HP each, 11 of them, enemies to all monster types | done | `objectives[0]` (`health: "3+L"`, `count: 11`, `escort`); 5 + 3 + 3 placed from placements as their tiles are revealed; monsters target escorts |
| Villagers cannot be healed and are not allies of the characters | missing | they are escorts and not in placements `protect` → allies, healable |
| Villagers act on initiative 99: "Move 3" toward the end of the docks (b); one reaching (b) is removed and saved | done | default initiative 99; `EscortTurnController.destination` reads marker b from label 86.1; `EscortAI.walk`; `noteEscortArrival` removes and counts it |
| Start of every odd round: Vermling Scouts at (c) and (d) — both normal (2); elite c + normal d (3); both elite (4) | partial | rule 0 (`round: "R % 2 == 1"`, no `start`) fires at the **end** of odd rounds, so nothing spawns at the start of round 1 and the c/d pair arrives going into even rounds. For 3 characters the data has c normal, d elite — the reverse of the notes |
| Start of every even round: Vermling Scouts at (e) and (f) — both normal (2); normal e + elite f (3); both elite (4) | partial | rule 1 (`R % 2 == 0`, no `start`) fires at the end of even rounds (one round-boundary late); types per count match |
| Lurkers are not set up until the end of the round in which the first villager is saved | missing | the Lurkers are in room 1's monster list and stand on H3a from setup (README says so) |

### 87 · Corrupted Cove
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Giant Ooze | done | placements goal `kill: ["giant-ooze"]` |
| Setup: each character adds 3 CURSE cards (scenario effect) | done | rule 0 (`R == 1`, `start`, `amAdd curse:3`, `scenarioEffect`) → `applyAmAdd` |
| The elite Ooze at the centre is the Giant Ooze, with H×C hit points (H = elite Ooze HP) | done | room 2 lists `giant-ooze` (boss); `monster/giant-ooze.json` health is elite-Ooze HP × C at every level, other stats equal the elite Ooze's. It stands by the room's first monster slot rather than a fixed centre hex |
| Four tokens on the Giant Ooze: Shield 2 per token, one removed each time any Ooze dies | missing | it has only the elite Ooze's own Shield from its stat line; no rule or counter |
| A character ending a turn on a water hex (a) removes the tile and gains Shield 2 against Ooze attacks and POISON immunity for the scenario, once | missing | no (a) markers; water is plain difficult terrain |

### 88 · Plane of Water
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: carry the Lurker King's claw to a hex adjacent to the crystal (a) | partial | placements goal `kill: ["lurker-king"]` + `reach: {marker: "a", adjacent: true}`: the King dead and any character ending a turn beside the crystal; no claw exists |
| Setup: all characters and their summons have −1 Move on all Move abilities | missing | 88.json has no rules |
| Current: at the end of each round every character and summon in the large room is forced one hex with the current (sheltered behind an obstacle/wall: no move); if blocked, 3 damage instead | missing | TODO.md lists "the current (#88)" as not built |
| Current is resolved from the top of the map to the bottom | missing | no current |
| Current direction depends on whether the Lurker initiative is even or odd | missing | no current |
| The elite Lurker next to the crystal is the Lurker King | done | room 2 lists `lurker-king` (boss) whose stats equal the elite Lurker's; it takes a Lurker slot, not necessarily the one by the crystal |
| When it dies it drops a claw (a treasure tile) instead of a money token | missing | `handleDeath` drops nothing for a boss; no claw |
| A character holding the claw has −2 Move | missing | no claw |
| The claw changes hands only by a Loot action on the holder's hex; it is dropped where the holder is exhausted | missing | no claw |

### 89 · Syndicate Hideout
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| All Cultists summon elite Giant Vipers instead of normal Living Bones | done | rule 0 (`always`, `alwaysApply`, `statEffects` deck `cultist-scenario-89`) → `switchDeck`; that deck's two summon cards name `giant-viper` type `elite` |

### 90 · Demonic Rift
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: close the rift — after Section 1, kill all Living Spirits | partial | no written goal; plays as the default "every enemy dead, every door open", which ends once the spirits and everything else are dead, but the spirits are not gated on Section 1 (next row but three) |
| Lose: no character is present in the left room at any time | missing | no rule or check |
| Lose: only one character is left unexhausted | missing | only "all exhausted" loses |
| Lose: after Section 1, either room has no character present | missing | no rule or check |
| Section 1 (all demons dead, a character in each room): a Living Spirit at every (b) and (c) — all normal (2); b elite + c normal (3); all elite (4) | partial | rule 0 has the right counts and types (2 at b, 2 at c) but no trigger (`always`, `once`, `round: "true"`, `rooms: [3]`): it fires at the start of round 1. The (c) hexes are on unrevealed D1b then, so those two appear beside the first monster in the left room (`spawnFromScenarioRule` fallback) |
| Characters cross between the rooms only through the altars: 1 movement from beside one altar to beside the other; summons and monsters cannot | missing | the map joins M1b and D1b with a door of subtype `altar`, treated as an ordinary door: a character walks in to open it and any figure then walks through (README: "the altar crossing isn't modelled") |
| End of every even round with no character in the right room: a Night Demon spawns next to the left altar (normal for 2; every second one elite for 3; elite for 4) | missing | no rule |

### 91 · Wild Melee
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal; allied monsters are excluded from `hostile` |
| Section 1: all Living Spirits are enemies to the characters and to all other monster types | partial | they are ordinary enemies: hostile to the characters and to the allied bears/hounds, but on the same side as the bandits (two factions only) |
| Cave Bears and Hounds are allies to the characters, enemies to all other monsters, and still act on a monster ability card | done | `allies: ["cave-bear","hound"]` → `monster.isAlly` → `MonsterAI.gatherEnemies`/`isPlayerSide` invert sides; they take turns through `MonsterTurnController` |

### 92 · Back Alley Brawl
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all non-city enemies | partial | placements goal `kill: [bandit-archer, bandit-guard, earth-demon, flame-demon, inox-guard, savvas-lavaflow]`. `goalMet` requires each named type to have had entities (`!monster.entities.isEmpty`); Earth and Flame Demons are in no room and only appear if the Savvas Lavaflow summons them, so unless one of each was summoned and killed the win never triggers |
| Lose: a City Guard or City Archer is killed | done | `lostIfKilled: ["city-guard","city-archer"]` → `goalLost` via `killCounts`; `ScenarioGoalTests.testKillingTheWrongEnemyLoses` |
| City Guards and City Archer are not set up until door 1 is opened (Section 1 sets them up) | partial | rule 0 spawns them (1 archer, 2 guards) but has no trigger (`always`, `once`, `round: "true"`) and its `rooms: [2]` is an effect: at the start of round 1 it spawns them — beside the first monster, since the spawns carry no marker — and then opens door 1 itself through `openScenarioRooms` |
| They are enemies to the characters and to all other monster types (and may be attacked) | partial | hostile to the characters and attackable; they are on the bandits' side, so neither attacks the other |

### 93 · Sunken Vessel
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies | done | default goal |
| Setup: all characters start with IMMOBILIZE (scenario effect) | missing | 93.json has no `rules`; no placements entry |

### 94 · Vermling Nest
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill all enemies and loot the treasure tile | done | placements goal `enemies: "all"` + `loot: "goal"` (the "G" chest on D1b) |

### 95 · Payment Due
| Rule (from the book) | Status | Where / what's missing |
|---|---|---|
| Goal: kill the Prime Lieutenant | done | placements goal `kill: ["prime-lieutenant"]` |
| Setup: numbered tokens 1–6 shuffled face down on the (a) hexes, lootable normally | missing | no objectives, markers or tokens (README: "the six numbered tokens … aren't modelled") |
| Section 1: the Savvas Lavaflow is the Prime Lieutenant | done | room 3 lists `prime-lieutenant` (boss, deck `savvas-lavaflow`, stats equal the elite Lavaflow's) |
| Door 1 is locked; it can be opened once tokens 1–4 are looted | missing | no lock written; the G1b→E1a door opens to any character from round 1 |
| Until tokens 1–4 are looted: end of every odd round a Flame Demon spawns by door 1 (normal for 2; elite for 3–4) | missing | 95.json has no rules |
| Until tokens 1–4 are looted: end of every even round an Earth Demon spawns by door 1 (normal for 2–3; elite for 4) | missing | no rule |
| Any figure ending its turn in a water hex suffers 1+L damage | missing | D1a's 19 water hexes are plain difficult terrain |
| Each boulder has 3+L hit points | missing | K2b's five boulders are indestructible obstacles |

# Summaries by part

## Summary for scenarios 1–19
- done: 40 rules, partial: 5, missing: 1
- Most common gaps:
  - **Boss summon counts** (#9 special 2, #12 specials 1 and 2): `MonsterSummonSpec` ignores `count` and summons entries meant for other player counts as normals — every player count gets the wrong mix. Same code path serves any other boss whose summon uses several `valueObject` entries.
  - **Bandit Commander's door special** (#2): a normal Move toward the nearest door instead of a jump in a→b→c→d order.
  - **Round-timing of the 3–4 character spawn** (#3): the data rule lacks `start`, so the round-1 guard is missing.
  - **#7 "Loot action only"** is not modelled at all.
- Not audited because the notes don't list them: the stat-card specials of the Inox Bodyguards (#8) and the Captain of the Guard (#11) (both have structured/handled specials in the monster data).
- Could not determine: whether the placement hexes (#3 a, #15 c–f, #19 b–e, Hail) match the book's printed map — only checked that they are consistent with the map data (e.g. #15's plates sit on the map's corridor overlays, #3's a is next to the E1b door).

## Summary for scenarios 20–38
- done: 63 rules, partial: 9, missing: 19
- Most common gaps:
  - **Boss specials** (#20, #21, #34, #36): anything beyond plain Move/Attack is lost. `summon` with `"demon"` or `"objectiveSpawn"` does nothing, `custom` text ("Throne moves", "Fly to next perch") is only logged, Jekserah's summon ignores `count` and per-player-count absence (always three, wrong ranks), and #36's "Move+0, Attack+0 instead" override doesn't exist.
  - **Objectives with behaviour** are absent or simplified: #21's altar (shared HP, undamageable boss), #34's Zephyrs and three-hex Elder Drake (also pushable, boulders destructible), #26's pump cleansing (so no goal), #38's Orchid destination.
  - **Monster stat modifiers from scenario rules**: `statEffects` only applies health/name/deck/actions/immunities. #22's attack/move/range bonus is ignored, and its `health: "X"` evaluates to 1, so demons there have 1 HP once door 1 is open — a bug, not just a gap.
  - **Allied or siege focus** (#35, #36): demons never attack #35's door (allied monsters can't target objectives) and have no door preference in #36.
  - **Timed/conditional spawns not in the scenario data**: #33's Icestorm after the last treasure, #36's Prime Demon arriving at e and the round-8 door collapse.
  - **Setup positions**: #35's starting City Archers are placed outside the gate instead of on battlements a/b; #36's Prime Demon is set up at the start.
  - #30's "Loot action only" restriction on the goal treasure isn't enforced.

## Summary for scenarios 39–57
- done: 48 rules, partial: 10, missing: 40
- Most common gaps:
  - **Boss specials and boss behaviour written only as text or not at all** — Winged Horror's eggs (#46), the Dark Rider leaving and reappearing on lettered hexes (#48), the Gloom's jump (#51, `teleport` unhandled), the Siege Cannon that should not act (#49, it shoots like an Ancient Artillery).
  - **Scenario rules the data carries only as a `note` label, or not at all** — all six vocal-chord penalties (#42), the totems' Heal 2 (#45), the Eye's end-of-round damage (#47), all three cannon/archer rules (#49, the JSON has no `rules`), monsters held back until a pressure plate (#41: those Stone Golems and Ancient Artilleries are in neither data file).
  - **Treasure that needs a Loot action** (#50, #52, #55) and **special obstacles** (dark pits #39/#51, the cellar's boulders #52): neither has a mechanic.
  - **Captives and props**: saving/freeing a captive and the loss on a captive's death (#44), the Staff of Xorn's charge, goal and loss (#54), the random dungeon (#55, unplayable: no map).
  - **Things that are close but off**: escorts always use the ally deck (#44, #56); per-turn rule damage reaches characters only and lands at round end (#51); monster summon specs ignore `count` and unlisted character counts (#48: two imps at 2 characters); push/pull immunity in monster data is never consulted (#47); the Infiltrator's position (#57); the per-room start cap (#50); a character exhausted early blocks the escape win (#41).
- Could not determine: whether the setup card counts for #45 (data 3 × "-1", notes 2) and #52 (data 3 Curse, notes 2) are wrong in the data or in the notes — no copy of the book text in the repository to check against.

## Summary for scenarios 58–76
- done: 54 rules, partial: 13, missing: 40
- Most common gaps:
  - Scenario mechanics with moving or carried pieces aren't built: wind (#71), boulders (#73), rising water and bailing (#74), the doll (#69), the Occult Dagger (#58), destructible walls (#76). Their rules exist only as `note` text or not at all.
  - Monster-specific restrictions and states are missing: sleeping drakes (#71), undamageable Living Spirits and their removal (#70), alternating monster groups (#61), monsters barred from a door (#67, #73).
  - Boss and objective modifiers tied to other figures are missing: the Harvester's Shield and healing per bone pile (#58), the Hungry Soul's Shield reduction (#62), the tree's damage stopping without Rending Drakes and the loss on its death (#68).
  - Things only approximated: graves attacked rather than dug, and corpses not rising one per grave (#75); HP that should round up rounds down (#62, #75); damage from a closing door can't be negated (#66, #67).
  - Setup effects are done where the data has a rule (#63 wound, #65 curses, #68 poison) and missing where it has none (#76 discard three cards, #74 water tiles at (d), #69 doll holder).
- Found beyond a plain gap: in #61 the data's `allied` list puts Flame and Frost Demons on the players' side, so the scenario plays wrongly rather than merely without the alternating rounds.
- Could not determine without running: #76's behaviour when a room is first entered through an empty tile copy (noted in its table); whether the hexes written for letters match the book's maps (not checked — the book's maps weren't available).

## Summary for scenarios 77–95
- done: 34 rules, partial: 16, missing: 55
- Most common gaps:
  - Scenario data with no rules at all for what the book prints: #77, #83, #85, #88, #93, #95 have an
    empty or absent `rules` array (start conditions, per-turn damage, timed spawns, element settings).
  - Props the game has no model for: carried tokens (claw #88, Crystal/Sphere #81, numbered tokens #95,
    artifact removal #82), water tiles with effects (#87, #95), the current (#88), destructible boulders
    (#95), a victim that is carried (#78), an altar crossing (#90).
  - "Not set up until …" and dormant monsters (#79 golems, #83 Flame Demons, #86 Lurkers, #92 city
    figures) and timed room reveals (#84 rounds 4/6/9): rooms simply reveal when a character opens the door.
  - Third-faction monsters ("enemies to the characters and to all other monster types": #85, #91, #92).
  - Monsters with scripted behaviour instead of the AI (#77 guards, #78 carrying Cultists) and escorts
    whose action is wrapped in text (#79 Fish gets no turn).
  - Boss specials: element-gated summons never happen (#81 both), text-only specials do nothing (#79
    special 2), summon counts by player count are wrong (#79 special 1).
- Things that look like bugs rather than gaps (found while reading, not run):
  - #92 goal lists `earth-demon` and `flame-demon`, which only exist if summoned — the win may never trigger.
  - #92 rule 0 and #90 rule 0 fire at the start of round 1 (no trigger); #92's also opens door 1.
  - #86 spawn rules run at round end, not round start, and the 3-character types at c/d are swapped
    against the notes.
  - #84 crystal and #86 villagers are healable allies (not in placements `protect`).
