# The scenario book, for the game

The map data the game is built on (from Virtual Gloomhaven Board) has tiles, doors, overlays and
monster positions, and the scenario data (from Gloomhaven Secretariat) has monsters, objectives
and rule triggers. Neither says **where** an objective or a lettered spawn hex is, or **what the
goal is**. Those come from the scenario book, and this folder is where what was read from it lives:

- [gh-scenario-rules.md](gh-scenario-rules.md) — the rules of all 95 scenarios as short notes:
  goal, losses, objectives, sections, special rules, boss specials, map letters.
- [rules-audit.md](rules-audit.md) — every one of those rules against the game: done, partial or
  missing, and where.
- `GlavenGame/Resources/ScenarioMaps/placements/gh.json` — the hexes, and the goals the game
  enforces for objectives (below).

## Placements: where objectives and lettered hexes are

`placements/gh.json` is keyed by scenario number, then by map tile, in the tile's own coordinates
(the same ones the map data's overlays use), so a tile can be written without knowing where it
ends up on the board:

```json
"19": {"goal": {"text": "Protect Hail until she reaches the altar.",
                "arrive": {"objective": 1, "marker": "b", "count": 1, "adjacent": true},
                "lostAt": {"1": 1}},
       "tiles": {
         "d2a": {"objectives": [{"objective": 1, "cells": [[0, 2]]}], "markers": {"c": [[2, 4]]}},
         "i1b": {"markers": {"b": [[2, 3]]}}
       }}
```

- `objectives`: which of the scenario's objectives (1-based, as its rooms list them) stands on
  `cells[0]`; the other cells are the rest of an obstacle it is drawn as (a three-hex tree), cleared
  when it is destroyed. `"door": true` — it bars the door on that hex, which opens when it is
  destroyed.
- `markers`: the hexes of a letter. A rule's spawn "at c" goes to the first free one.
- `protect`: objectives that are the monsters' to attack and no ally of the party (captives, a gate,
  the crystal, the villagers): they aren't healed or helped.
- `rules`: rules the scenario data lacks, in its own format, added after the scenario's own.
  `dropRules`: the scenario's own rules to leave out, by their place in its list (from 0) — ones the
  data gets wrong or leaves for a person to trigger, written again in `rules`. A dropped rule keeps
  its place, since rules refer to each other by index.
  Rules written here can use a few things the scenario data has no word for:
  - `when` — things that have happened on the board, all at once: `{"saved": 1}` (that many
    escorts have arrived), `{"lock": 0}` (that lock of `locks`, from 0, has been released),
    `{"looted": "goal"}` (every goal treasure tile; a tile ref for the goal treasure on it; a
    treasure's number). A rule with `"always": true` fires at once; without it, as the round ends
    ("at the end of the round in which…").
  - `setUp` — monster types held back by `later` are set up now, where the map prints them.
  - in a figure's `identifier`: `"tile": "j1a"` (only figures standing on that tile) and
    `"near": {"marker": "a", "range": 2}` or `{"objective": "Totem", "range": 2}`.
  - `"alwaysApplyTurn": "turn"` rules reach monsters and summons as their own turns start, and
    `heal` is a real heal (Poison stops it).
  - in a spawn: `"placed": true` — set up late rather than spawned, so it drops money.
- `later`: monster types that aren't set up with their rooms (the Lurkers of #86 until a villager
  is saved); a rule's `setUp` brings them, on the places the map data has for them. Monsters the
  data doesn't have at all (the golems of #41's middle room) are spawned by a rule at letters
  written for them — letters the book doesn't print, since nothing shows a letter on the board.
- `effects`: what the scenario does to attacks and Shields for as long as it holds
  (`ScenarioPlacements.Effect`): `on` — `"monsters"`, `"party"` (characters and their summons) or
  one monster type; `whileStanding` — only while that objective stands; then any of `attack` (added
  to each of their attacks), `advantage`, `disadvantage` and `shield` (a number or a formula over
  X, C and L, added to their Shield, which never falls below none). X is what `per` counts:
  `{"objective": 1}` or `{"monster": "living-bones"}` on the board, or
  `{"tokens": 4, "lostWith": "ooze"}` — tokens of which one goes each time such a monster dies.
- `notes`: the special rules in words for the scenario brief — only those the game enforces.
  With notes written, the rules written here aren't described a second time from their data,
  no "More … arrive" lines are guessed, and a text the data ships is left out where a note says
  the same and more ("Chord 1, while it stands: …").
- `whenDestroyed`: what appears where an objective stood when it is destroyed, by objective
  (`{"1": {"name": "living-corpse", "player2": "normal", …}}`): a Living Corpse from each grave.
- `goal`: the scenario's goal and losses as the book prints them (`ScenarioPlacements.Goal`).
  Everything under "to win" must hold at once; any loss loses.
  - `text` — the goal in the book's words, for the scenario brief.
  - to win: `kill` (monster types, every one), `killCount` (`{"count": "5xC", "of": [types]}`),
    `enemies` (`"all"`, or `"revealed"` for those on the board), `reveal` (tiles, or `"*"`),
    `loot` (`"goal"`: every goal treasure tile; `"each"`: every character loots one),
    `lootIDs` (numbered treasure), `destroy` (objectives), `arrive` (an escort to a letter),
    `escape` (`{"marker": "a"}`, `{"tile": "b1a"}` or `{"start": true}`; `"leave": true` when
    characters leave one by one as rounds end), `occupy` (pressure plates by letter, with `more`
    by character count), `reach` (a character ends a turn on a letter, or beside it with
    `"adjacent": true`), `either` (any one of several goals as well).
  - lost: `lostAt` (objective → how many killed), `lostIfExhausted` (`"any"`, `"offExit"`,
    `"beforeLoot"`; `lostIfExhaustedOnceRevealed` delays it until a tile is revealed),
    `lostIfKilled` (monster types).
  - Where characters stand (`escape`, `occupy`, `reach`) is judged as a turn or the round ends.
- `lootActionOnly`: the goal treasure tiles can only be looted with a Loot action; ending a turn
  on one doesn't pick it up (#7, #30, #50, #52, #59, #61).
- `locks`: doors a scenario rule keeps locked (`ScenarioPlacements.Lock`, `BoardCoordinator+Locks`).
  A lock names the two tiles its door joins (`"between": ["d1a", "h3b"]`) — both doors, where two
  join the same pair — and at most one key:
  - `plate` — a character ends a turn on a pressure plate with one of these letters;
  - `allOnPlates` — every character stands on a plate as a turn ends (plates by letter, `more` by
    character count);
  - `afterRound` — the round has ended ("at the start of round 2" is `1`);
  - `looted` — that many goal treasure tiles looted; `eliteKills` — that many elites killed;
  - `held` — open only while a character stands on one of these plates; it shuts again when they
    step off (whoever is in the doorway suffers trap damage and is put out of it);
  - no key — only a scenario rule or a monster's ability opens it (#2, #79).
  `"unlocksOnly": true` leaves the door for a character to open; otherwise the key opens it and
  reveals the room. `note` is what the player is told when asking about the door.
  A locked door carries a padlock on the board and can't be walked into.
- `plates`: letters that are pressure plates no lock or goal names. Every plate in play is drawn.
- `rules`: rules the book prints and the scenario data leaves out, in the data's own rule format
  (#62: the Hungry Soul after ten Living Bones). They are added after the scenario's own.

### Writing one

```sh
PLACEMENT_SHEET=19 PLACEMENT_SHEET_OUT=/tmp/s19.png swift test --filter testRenderPlacementSheet
```

renders the scenario's whole map with every hex labelled by its tile and tile coordinates, and
what is already written drawn in (letters in red, objectives in cyan). Put it beside the book's
map and read the coordinates off. `PLACEMENT_SHEET_TURN=90` (or 180, 270) turns the sheet where the
book prints the map turned. `testEveryWrittenGoalRefersToThingsInItsScenario` checks a goal names
monsters, objectives, letters, tiles and treasure its scenario has, and `testEveryWrittenPlacementLandsOnItsMap` then checks every hex is on
its map, every door objective is on a door and every objective number exists.

### What is written

| Scenario | Objectives placed | Letters placed | Goal / loss enforced | Still approximate |
|---|---|---|---|---|
| 3 Inox Encampment | — | a | win: 5×C kills | — |
| 19 Forgotten Crypt | Hail | b–e | win when Hail ends beside the altar; lost if she dies | — |
| 22 Temple of the Elements | 4 altars | — | win: destroy all altars | — |
| 26 Ancient Cistern | water pumps | — (imps spawn beside their pump) | — | cleansing a pump isn't modelled, so the goal isn't |
| 27 Ruinous Rift | Hail | b–e | lost if Hail dies (win at round 10 is a scenario rule) | — |
| 29 Sanctuary of Gloom | 3 barred doors | — | — | — |
| 31 Plane of Night | rock column | b, c | win: destroy the column | — |
| 33 Savvas Armory | barred door | a (exits), c, d | win: loot all, then everyone on the exit; lost if exhausted off it | — |
| 35 Gloomhaven Battlements A | barred door | — | — | the allied demons attack the door as any enemy, without preferring it |
| 36 Gloomhaven Battlements B | the gate (protected) | a–e | — | the demons don't prefer the gate; the Prime Demon's specials are its stat card's |
| 38 Slave Pens | the Orchid | — | lost if he dies | he heads for the nearest enemy, not the shaman on the D tile |
| 39 Treacherous Divide | altar | — | win: destroy the altar | — |
| 42 Realm of the Voice | 6 vocal chords | — | win: destroy all | — |
| 44 Tribal Assault | Redthorn, 9 captives (protected) | — | — | losing a card to save a captive, and freeing one, aren't modelled — so a captive's death doesn't lose yet |
| 45 Rebel Swamp | 6 totems | — | win: destroy all | — |
| 56 Bandit's Wood | 3 captive Orchids | — | lost when all three die (scenario rule) | — |
| 57 Investigation | — | a | win: kill the Infiltrator | he appears near other monsters, not where the guard fell |
| 58 Bloody Shack | 4 bone piles | — | win: kill the Harvester | the bone piles' Shield and healing aren't modelled |
| 62 Pit of Souls | — | a, b, c | win: kill the Hungry Soul (appears at c after ten kills) | its extra Shield isn't modelled |
| 68 Toxic Moor | the tree | — | — | its damage should stop once no Rending Drake is on the M tile; until then its death doesn't lose |
| 69 Well of the Unfortunate | — | a–d | win: a character beside the well | the doll isn't carried |
| 70 Chained Isle | — | a, b | — | — |
| 72 Oozing Grove | 3 trees | — (oozes rise beside their tree) | win: destroy all trees, kill all Oozes | — |
| 74 Merchant Ship | — | a–e | — | water tiles aren't modelled |
| 75 Overgrown Graveyard | 9 graves | — (what rises, rises where the grave was) | win: all graves and the Bloated Regent | graves are attacked rather than dug up with movement |
| 79 Lost Temple | Fish | — | win: kill the Betrayer | Fish's turn, the dormant golems and his loss aren't modelled |
| 84 Crystalline Cave | the crystal | — | lost if it is destroyed | protected, no ally; losing a card to spare it isn't modelled |
| 86 Harried Village | 11 villagers | b–f | win: 7 reach the docks; lost at 5 killed | — |
| 90 Demonic Rift | — | b, c (the Living Spirits, once every demon is dead) | win: every Living Spirit killed | the altar crossing and the losses for leaving a room aren't modelled |

### Locked doors written

| Scenario | Doors | Key |
|---|---|---|
| 2 Barrow Lair | the four side rooms | none: the Bandit Commander opens them |
| 15 Shrine of Strength | both side rooms; the treasure room | plate (c); every character on a side-room plate |
| 33 Savvas Armory | door 1 | every character on a plate (c) |
| 41 Timeworn Tomb | door 2 | plate (b) unlocks it (and wakes the room's golems and artilleries) |
| 53 Crypt Basement | all six | as rounds 2, 4, 6 and 8 begin |
| 66 Clockwork Cove | doors 1, f, g, h; the two side rooms | held open by plates a–d; plate (d) |
| 67 Arcane Library | door 2 | held open by a plate (a) |
| 69 Well of the Unfortunate | door 1 | plate (b) |
| 71 Windswept Highlands | doors b, c, d | the first, second and third treasure tile looted |
| 74 Merchant Ship | doors 1, 2 | as rounds 3 and 6 end |
| 79 Lost Temple | door 1 | none: the rule that every Stone Golem is dead opens it |
| 82 Burning Mountain | all six | one for each elite killed, in order |
| 84 Crystalline Cave | the three cave walls | as rounds 4, 6 and 9 begin |

Not locked yet: #95's door 1 (its key is the six numbered tokens, which aren't modelled).
In #66 door 1 opens as a character steps onto plate (a) rather than as their turn ends, and
trap damage from a closing door can't be negated by losing cards.

Letters written only for a rule: #41 c–g (where the middle room's artilleries and golems are
set up; not the book's letters), #83 the altar (a).

Letters written only for a goal: #23 and #40 pressure plates; #25, #37, #41 and #71 exits; #66
plates a–e; #82 the altar hex g; #88 the crystal.

Objectives an obstacle or a door already draws on the map (altars, totems, trees, graves, the
crystal, barred doors) were taken from the map data and checked against the book; escorts,
tokens and letters were read from the book's maps.

## Every scenario's goal, and whether the game checks it

The goal the game checks is the scenario data's own win rule where it has one, otherwise the goal
written in `placements/gh.json`, otherwise the default: every enemy dead with every room revealed.
"Approximately" marks a goal checked without one of the book's props (a doll, a claw). 90 of 95
goals are checked; the notes say what around a goal is still missing.

| # | Scenario | Goal | Goal in the game | Other ways to lose | Loss in the game |
|---|---|---|---|---|---|
| 1 | Black Barrow | Kill all enemies. | yes | — | — |
| 2 | Barrow Lair | Kill the Bandit Commander and all revealed enemies. | yes | — | — |
| 3 | Inox Encampment | Kill a number of enemies equal to 5×C. | yes | — | — |
| 4 | Crypt of the Damned | Kill all enemies. | yes | — | — |
| 5 | Ruinous Crypt | Kill all enemies. | yes | — | — |
| 6 | Decaying Crypt | Reveal the M tile (M1a) and kill all revealed enemies. | yes | — | — |
| 7 | Vibrant Grotto | Loot all treasure tiles. | yes | — | — |
| 8 | Gloomhaven Warehouse | Kill both Inox Bodyguards. | yes | — | — |
| 9 | Diamond Mine | Kill the Merciless Overseer and loot the treasure tile. | yes | — | — |
| 10 | Plane of Elemental Power | Kill all enemies. | yes | — | — |
| 11 | Gloomhaven Square A | Kill the Captain of the Guard. | yes | — | — |
| 12 | Gloomhaven Square B | Kill Jekserah. | yes | — | — |
| 13 | Temple of the Seer | Kill all enemies. | yes | — | — |
| 14 | Frozen Hollow | Kill all enemies. | yes | — | — |
| 15 | Shrine of Strength | Loot the treasure tile. | yes | — | — |
| 16 | Mountain Pass | Kill all enemies. | yes | — | — |
| 17 | Lost Island | Kill all enemies. | yes | — | — |
| 18 | Abandoned Sewers | Kill all enemies. | yes | — | — |
| 19 | Forgotten Crypt | Protect Hail (a) until she reaches the altar (b); the scenario is complete when she ends her turn in a hex adjacent to the altar. | yes | Hail is killed. | yes |
| 20 | Necromancer's Sanctum | Kill Jekserah. | yes | — | — |
| 21 | Infernal Throne | Kill the Prime Demon. | yes — kill the Prime Demon (the altar that takes its damage isn't modelled, so it is attacked directly) | — | — |
| 22 | Temple of the Elements | Destroy all altars (a). | yes | — | — |
| 23 | Deep Ruins | Occupy all pressure plates simultaneously. | yes | — | — |
| 24 | Echo Chamber | Open all doors (fog tiles). | yes | — | — |
| 25 | Icecrag Ascent | All characters must escape through the exit (a). | yes | Any character becomes exhausted while not standing on an exit hex (a). | yes |
| 26 | Ancient Cistern | Cleanse all water pumps. | **no** — cleansing a pump isn't modelled; plays as "kill all enemies" | — | — |
| 27 | Ruinous Rift | Protect Hail (a) for ten rounds. | yes (scenario rule) | Hail is killed. | yes |
| 28 | Outer Ritual Chamber | Kill all enemies. | yes | — | — |
| 29 | Sanctuary of Gloom | Kill all enemies. | yes | — | — |
| 30 | Shrine of the Depths | Loot the treasure tile. | yes | — | — |
| 31 | Plane of Night | Destroy the rock column (a). | yes | — | — |
| 32 | Decrepit Wood | Reveal the G tile, kill all revealed enemies, and loot the treasure tile. | yes | — | — |
| 33 | Savvas Armory | Loot all treasure tiles, then all characters must escape through the exit (a). | yes | Any character becomes exhausted while not standing on an exit hex (a). | yes |
| 34 | Scorched Summit | Kill the Elder Drake. | yes | — | — |
| 35 | Gloomhaven Battlements A | Destroy door 1 and kill the Captain of the Guard. | yes | — | — |
| 36 | Gloomhaven Battlements B | Kill the Prime Demon. | yes | — | — |
| 37 | Doom Trench | All characters must escape through the exit (a). | yes | Any character becomes exhausted while not occupying an exit hex (a). | yes |
| 38 | Slave Pens | Kill all enemies and protect the Orchid (a). | yes | The Orchid is killed. | yes |
| 39 | Treacherous Divide | Destroy the altar (a). | yes | — | — |
| 40 | Ancient Defense Network | Occupy both pressure plates (a) simultaneously. | yes | — | — |
| 41 | Timeworn Tomb | All characters must escape through the exit (a). | yes | Any character becomes exhausted (printed under Section 2). | yes |
| 42 | Realm of the Voice | Destroy all vocal chords. | yes | — | — |
| 43 | Drake Nest | Kill a number of drakes equal to 4×C. | yes | — | — |
| 44 | Tribal Assault | Kill all enemies and protect all captive Orchids (a). | yes | Any captive Orchid is killed. | **no** — needs the card-to-save rule first |
| 45 | Rebel Swamp | Destroy all totems (a). | yes | — | — |
| 46 | Nightmare Peak | Kill the Winged Horror. | yes | — | — |
| 47 | Lair of the Unseeing Eye | Kill the Sightless Eye. | yes | — | — |
| 48 | Shadow Weald | Kill the Dark Rider. | yes | — | — |
| 49 | Rebel's Stand | Kill the Siege Cannon. | yes | — | — |
| 50 | Ghost Fortress | Loot all treasure tiles. | yes | — | — |
| 51 | The Void | Kill the Gloom. | yes | — | — |
| 52 | Noxious Cellar | All characters must loot one treasure tile. | yes | Any character becomes exhausted before they have looted a treasure tile. | yes |
| 53 | Crypt Basement | Survive for ten rounds (the scenario is complete at the end of the tenth round). | yes (scenario rule) | — | — |
| 54 | Palace of Ice | Place the fully charged Staff of Xorn on the altar (a): the scenario is complete when the Seeker of Xorn ends their turn adjacent to the altar (a) after the staff is fully charged. | **no** — charging the staff isn't modelled; plays as "kill all enemies" | The Seeker of Xorn becomes exhausted. | **no** |
| 55 | Foggy Thicket | Loot the treasure tile in the third room. | **no** — random dungeon, no map | — | — |
| 56 | Bandit's Wood | Kill all enemies and protect at least one captive Orchid. | yes | All three captive Orchids are killed. | yes |
| 57 | Investigation | Kill the Infiltrator. | yes | — | — |
| 58 | Bloody Shack | Kill the Harvester. | yes | — | — |
| 59 | Forgotten Grove | Kill all enemies and loot the treasure tile. | yes | — | — |
| 60 | Alchemy Lab | Loot all treasure tiles, then all characters must escape through the entrance. | yes | The scenario is not complete by the end of the twelfth round. Any character becomes exhausted before all treasure tiles are looted, or while not occupying an entrance hex. | yes (round 12 by scenario rule; exhaustion by goal) |
| 61 | Fading Lighthouse | Loot all treasure tiles. | yes | — | — |
| 62 | Pit of Souls | Kill the Hungry Soul. | yes — the Hungry Soul appears at (c) after ten Living Bones are killed (its extra Shield isn't modelled) | — | — |
| 63 | Magma Pit | Kill all enemies. | yes | — | — |
| 64 | Underwater Lagoon | Kill all enemies. | yes | — | — |
| 65 | Sulfur Mine | Kill all enemies and loot all treasure tiles. | yes | — | — |
| 66 | Clockwork Cove | Occupy pressure plate (e) — a character occupies it at the end of their turn. | yes | — | — |
| 67 | Arcane Library | Kill the Arcane Golem. | yes — the Stone Golem in the library | — | — |
| 68 | Toxic Moor | Kill all enemies and protect the tree (a). | yes | The tree is destroyed. | **no** — needs the tree's damage to stop first |
| 69 | Well of the Unfortunate | Bring the doll to the well (a) — complete when the doll is brought to a hex adjacent to the well. | approximately — any character ending a turn beside the well (the doll isn't carried) | — | — |
| 70 | Chained Isle | Kill all demons. | yes | — | — |
| 71 | Windswept Highlands | Loot all treasure tiles, then all characters must escape through the exit (a). | yes | Any character becomes exhausted while not occupying an exit hex (a). | yes |
| 72 | Oozing Grove | Destroy all trees and kill all Oozes. | yes | — | — |
| 73 | Rockslide Ridge | Kill all enemies and loot all treasure tiles. | yes | — | — |
| 74 | Merchant Ship | Kill all enemies and keep the ship afloat. | kill all enemies: yes; the water isn't modelled | A water tile has to be added but cannot be placed because the B tile is full. | **no** |
| 75 | Overgrown Graveyard | Dig up all graves and kill the Bloated Regent. | yes | — | — |
| 76 | Harrower Hive | Reveal all rooms and kill all enemies. | **no** — destructible walls aren't modelled; plays as "kill all enemies" | — | — |
| 77 | Vault of Secrets | Loot all treasure tiles and kill all City Guards before the alarm is raised. | yes | Any City Guard occupies a pressure plate (a). | **no** — guards don't head for the plates |
| 78 | Sacrifice Pit | Kill all enemies and stop the sacrifice. | kill all enemies: yes; the sacrifice isn't modelled | The victim is sacrificed: a Cultist (b) starts its turn adjacent to the altars (d) while the victim is also adjacent to the altars. | **no** |
| 79 | Lost Temple | Kill the Betrayer. | yes (the Stone Golems aren't dormant) | Fish is killed. | **no** — Fish's turn and the dormant golems come first |
| 80 | Vigil Keep | Every character must loot one treasure tile, and then all characters must reach the B tile (escape). | yes | Any character becomes exhausted while not occupying the B tile. | yes |
| 81 | Temple of the Eclipse | Kill the Colorless. | yes | — | — |
| 82 | Burning Mountain | Sacrifice one artifact, or escape with all artifacts. | approximately — with the treasure looted, a character on the altar hex or everyone at the entrance (no artifact is removed) | — | — |
| 83 | Shadows Within | Kill all enemies. | yes | — | — |
| 84 | Crystalline Cave | Kill all enemies and protect the crystal (a). | yes | The crystal is destroyed. | yes |
| 85 | Sun Temple | Kill all enemies. | yes | — | — |
| 86 | Harried Village | Save seven villagers before five are killed. | yes | Five villagers are killed. | yes |
| 87 | Corrupted Cove | Kill the Giant Ooze. | yes | — | — |
| 88 | Plane of Water | Bring the Lurker King's claw to the crystal (a) — the scenario is complete when the claw is carried to a hex adjacent to the crystal. | approximately — the Lurker King dead and any character ending a turn beside the crystal (the claw isn't carried) | — | — |
| 89 | Syndicate Hideout | Kill all enemies. | yes | — | — |
| 90 | Demonic Rift | Close the rift (after Section 1: kill all Living Spirits). | yes — the spirits come when every demon is dead | No character is present in the left room at any time; only one character is left unexhausted; after Section 1, either room has no character present at any time. | **no** |
| 91 | Wild Melee | Kill all enemies. | yes | — | — |
| 92 | Back Alley Brawl | Kill all non-city enemies. | yes | A City Guard or City Archer is killed. | yes |
| 93 | Sunken Vessel | Kill all enemies. | yes | — | — |
| 94 | Vermling Nest | Kill all enemies and loot the treasure tile. | yes | — | — |
| 95 | Payment Due | Kill the Prime Lieutenant. | yes | — | — |

## Open questions in the book itself

Noted while reading; the notes record what is printed and don't resolve these:

- **#12** — the "1" is printed on the door from the start room, but its section text reads as if
  it were about reaching Jekserah at the far end.
- **#21** — the rules call the altar "a", the map draws it on hex f.
- **#34, #48, #51** — only Boss Special 2 is printed.
- **#81** — no heal amount is printed for Boss Special 2, and it isn't said whether treasure tile
  68 counts as the first or second tile looted.
- **#83** — it isn't said whether Section 2's damage replaces Section 1's altar damage.
- **#87** — the map doesn't show which half of the main room is L2a and which L3b.
