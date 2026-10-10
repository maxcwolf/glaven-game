# The scenario book, for the game

The map data the game is built on (from Virtual Gloomhaven Board) has tiles, doors, overlays and
monster positions, and the scenario data (from Gloomhaven Secretariat) has monsters, objectives
and rule triggers. Neither says **where** an objective or a lettered spawn hex is, or **what the
goal is**. Those come from the scenario book, and this folder is where what was read from it lives:

- [gh-scenario-rules.md](gh-scenario-rules.md) — the rules of all 95 scenarios as short notes:
  goal, losses, objectives, sections, special rules, boss specials, map letters.
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
- `protect`: objectives that are the monsters' to attack and no ally of the party (captives, a gate).
- `goal`: what the book asks of the objectives — `destroy` (objectives), `kill` (monster types),
  `arrive` (an escort to a letter), `enemies` (every enemy too), `lostAt` (objective → how many
  killed loses), and `text` for the scenario brief.

### Writing one

```sh
PLACEMENT_SHEET=19 PLACEMENT_SHEET_OUT=/tmp/s19.png swift test --filter testRenderPlacementSheet
```

renders the scenario's whole map with every hex labelled by its tile and tile coordinates, and
what is already written drawn in (letters in red, objectives in cyan). Put it beside the book's
map and read the coordinates off. `PLACEMENT_SHEET_TURN=90` (or 270) turns the sheet where the
book prints the map turned. `testEveryWrittenPlacementLandsOnItsMap` then checks every hex is on
its map, every door objective is on a door and every objective number exists.

### What is written

| Scenario | Objectives placed | Letters placed | Goal / loss enforced | Still approximate |
|---|---|---|---|---|
| 3 Inox Encampment | — | a | — | goal (kill 5×C) not modelled |
| 19 Forgotten Crypt | Hail | b–e | win when Hail ends beside the altar; lost if she dies | — |
| 22 Temple of the Elements | 4 altars | — | win: destroy all altars | — |
| 26 Ancient Cistern | water pumps | — (imps spawn beside their pump) | — | cleansing a pump isn't modelled, so the goal isn't |
| 27 Ruinous Rift | Hail | b–e | lost if Hail dies (win at round 10 is a scenario rule) | — |
| 29 Sanctuary of Gloom | 3 barred doors | — | — | — |
| 31 Plane of Night | rock column | b, c | win: destroy the column | — |
| 33 Savvas Armory | barred door | a (exits), c, d | — | loot-all-then-escape goal not modelled |
| 35 Gloomhaven Battlements A | barred door | — | — | demons don't prefer the door |
| 36 Gloomhaven Battlements B | the gate (protected) | a–e | — | Prime Demon's arrival and door timer not modelled |
| 38 Slave Pens | the Orchid | — | lost if he dies | he heads for the nearest enemy, not the shaman on the D tile |
| 39 Treacherous Divide | altar | — | win: destroy the altar | — |
| 42 Realm of the Voice | 6 vocal chords | — | win: destroy all | — |
| 44 Tribal Assault | Redthorn, 9 captives (protected) | — | — | losing a card to save a captive, and freeing one, aren't modelled — so a captive's death doesn't lose yet |
| 45 Rebel Swamp | 6 totems | — | win: destroy all | — |
| 56 Bandit's Wood | 3 captive Orchids | — | lost when all three die (scenario rule) | — |
| 57 Investigation | — | a | — | goal (kill the Infiltrator) not modelled |
| 58 Bloody Shack | 4 bone piles | — | — | goal (kill the Harvester) not modelled |
| 62 Pit of Souls | — | a, b, c | — | — |
| 68 Toxic Moor | the tree | — | — | its damage should stop once no Rending Drake is on the M tile; until then its death doesn't lose |
| 69 Well of the Unfortunate | — | a–d | — | the doll and the well aren't modelled |
| 70 Chained Isle | — | a, b | — | — |
| 72 Oozing Grove | 3 trees | — (oozes rise beside their tree) | win: destroy all trees, kill all Oozes | — |
| 74 Merchant Ship | — | a–e | — | water tiles aren't modelled |
| 75 Overgrown Graveyard | 9 graves | — (what rises, rises where the grave was) | win: all graves and the Bloated Regent | graves are attacked rather than dug up with movement |
| 79 Lost Temple | Fish | — | — | Fish's return-and-attack turn and his fate aren't modelled |
| 84 Crystalline Cave | the crystal | — | lost if it is destroyed | it is treated as an ally (it shouldn't be healable) |
| 86 Harried Village | 11 villagers | b–f | win: 7 reach the docks; lost at 5 killed | Lurkers are set up from the start |
| 90 Demonic Rift | — | b, c | — | the altar crossing isn't modelled |

Objectives an obstacle or a door already draws on the map (altars, totems, trees, graves, the
crystal, barred doors) were taken from the map data and checked against the book; escorts,
tokens and letters were read from the book's maps.

## Every scenario's goal, and whether the game checks it

Where the game has no rule for a goal it falls back to "kill every enemy, with every room
revealed" — sometimes more than the book asks, sometimes not what it asks at all. This is the
list to work down for scenario-specific goals.

| # | Scenario | Goal | Goal in the game | Other ways to lose | Loss in the game |
|---|---|---|---|---|---|
| 1 | Black Barrow | Kill all enemies. | yes | — | — |
| 2 | Barrow Lair | Kill the Bandit Commander and all revealed enemies. | **no** — plays as "kill all enemies" | — | — |
| 3 | Inox Encampment | Kill a number of enemies equal to 5×C. | **no** — plays as "kill all enemies" | — | — |
| 4 | Crypt of the Damned | Kill all enemies. | yes | — | — |
| 5 | Ruinous Crypt | Kill all enemies. | yes | — | — |
| 6 | Decaying Crypt | Reveal the M tile (M1a) and kill all revealed enemies. | **no** — plays as "kill all enemies" | — | — |
| 7 | Vibrant Grotto | Loot all treasure tiles. | **no** — plays as "kill all enemies" | — | — |
| 8 | Gloomhaven Warehouse | Kill both Inox Bodyguards. | **no** — plays as "kill all enemies" | — | — |
| 9 | Diamond Mine | Kill the Merciless Overseer and loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 10 | Plane of Elemental Power | Kill all enemies. | yes | — | — |
| 11 | Gloomhaven Square A | Kill the Captain of the Guard. | **no** — plays as "kill all enemies" | — | — |
| 12 | Gloomhaven Square B | Kill Jekserah. | **no** — plays as "kill all enemies" | — | — |
| 13 | Temple of the Seer | Kill all enemies. | yes | — | — |
| 14 | Frozen Hollow | Kill all enemies. | yes | — | — |
| 15 | Shrine of Strength | Loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 16 | Mountain Pass | Kill all enemies. | yes | — | — |
| 17 | Lost Island | Kill all enemies. | yes | — | — |
| 18 | Abandoned Sewers | Kill all enemies. | yes | — | — |
| 19 | Forgotten Crypt | Protect Hail (a) until she reaches the altar (b); the scenario is complete when she ends her turn in a hex adjacent to the altar. | yes (objective goal) | Hail is killed. | yes |
| 20 | Necromancer's Sanctum | Kill Jekserah. | **no** — plays as "kill all enemies" | — | — |
| 21 | Infernal Throne | Kill the Prime Demon. | **no** — plays as "kill all enemies" | — | — |
| 22 | Temple of the Elements | Destroy all altars (a). | yes (objective goal) | — | — |
| 23 | Deep Ruins | Occupy all pressure plates simultaneously. | **no** — plays as "kill all enemies" | — | — |
| 24 | Echo Chamber | Open all doors (fog tiles). | **no** — plays as "kill all enemies" | — | — |
| 25 | Icecrag Ascent | All characters must escape through the exit (a). | **no** — plays as "kill all enemies" | Any character becomes exhausted while not standing on an exit hex (a). | **no** |
| 26 | Ancient Cistern | Cleanse all water pumps. | **no** — plays as "kill all enemies" | — | — |
| 27 | Ruinous Rift | Protect Hail (a) for ten rounds. | yes (scenario rule) | Hail is killed. | yes |
| 28 | Outer Ritual Chamber | Kill all enemies. | yes | — | — |
| 29 | Sanctuary of Gloom | Kill all enemies. | yes | — | — |
| 30 | Shrine of the Depths | Loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 31 | Plane of Night | Destroy the rock column (a). | yes (objective goal) | — | — |
| 32 | Decrepit Wood | Reveal the G tile, kill all revealed enemies, and loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 33 | Savvas Armory | Loot all treasure tiles, then all characters must escape through the exit (a). | **no** — plays as "kill all enemies" | Any character becomes exhausted while not standing on an exit hex (a). | **no** |
| 34 | Scorched Summit | Kill the Elder Drake. | **no** — plays as "kill all enemies" | — | — |
| 35 | Gloomhaven Battlements A | Destroy door 1 and kill the Captain of the Guard. | **no** — plays as "kill all enemies" | — | — |
| 36 | Gloomhaven Battlements B | Kill the Prime Demon. | **no** — plays as "kill all enemies" | — | — |
| 37 | Doom Trench | All characters must escape through the exit (a). | **no** — plays as "kill all enemies" | Any character becomes exhausted while not occupying an exit hex (a). | **no** |
| 38 | Slave Pens | Kill all enemies and protect the Orchid (a). | **no** — plays as "kill all enemies" | The Orchid is killed. | yes |
| 39 | Treacherous Divide | Destroy the altar (a). | yes (objective goal) | — | — |
| 40 | Ancient Defense Network | Occupy both pressure plates (a) simultaneously. | **no** — plays as "kill all enemies" | — | — |
| 41 | Timeworn Tomb | All characters must escape through the exit (a). | **no** — plays as "kill all enemies" | Any character becomes exhausted (printed under Section 2). | **no** |
| 42 | Realm of the Voice | Destroy all vocal chords. | yes (objective goal) | — | — |
| 43 | Drake Nest | Kill a number of drakes equal to 4×C. | **no** — plays as "kill all enemies" | — | — |
| 44 | Tribal Assault | Kill all enemies and protect all captive Orchids (a). | **no** — plays as "kill all enemies" | Any captive Orchid is killed. | **no** |
| 45 | Rebel Swamp | Destroy all totems (a). | yes (objective goal) | — | — |
| 46 | Nightmare Peak | Kill the Winged Horror. | **no** — plays as "kill all enemies" | — | — |
| 47 | Lair of the Unseeing Eye | Kill the Sightless Eye. | **no** — plays as "kill all enemies" | — | — |
| 48 | Shadow Weald | Kill the Dark Rider. | **no** — plays as "kill all enemies" | — | — |
| 49 | Rebel's Stand | Kill the Siege Cannon. | **no** — plays as "kill all enemies" | — | — |
| 50 | Ghost Fortress | Loot all treasure tiles. | **no** — plays as "kill all enemies" | — | — |
| 51 | The Void | Kill the Gloom. | **no** — plays as "kill all enemies" | — | — |
| 52 | Noxious Cellar | All characters must loot one treasure tile. | **no** — plays as "kill all enemies" | Any character becomes exhausted before they have looted a treasure tile. | **no** |
| 53 | Crypt Basement | Survive for ten rounds (the scenario is complete at the end of the tenth round). | yes (scenario rule) | — | — |
| 54 | Palace of Ice | Place the fully charged Staff of Xorn on the altar (a): the scenario is complete when the Seeker of Xorn ends their turn adjacent to the altar (a) after the staff is fully charged. | **no** — plays as "kill all enemies" | The Seeker of Xorn becomes exhausted. | **no** |
| 55 | Foggy Thicket | Loot the treasure tile in the third room. | **no** — plays as "kill all enemies" | — | — |
| 56 | Bandit's Wood | Kill all enemies and protect at least one captive Orchid. | **no** — plays as "kill all enemies" | All three captive Orchids are killed. | yes |
| 57 | Investigation | Kill the Infiltrator. | **no** — plays as "kill all enemies" | — | — |
| 58 | Bloody Shack | Kill the Harvester. | **no** — plays as "kill all enemies" | — | — |
| 59 | Forgotten Grove | Kill all enemies and loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 60 | Alchemy Lab | Loot all treasure tiles, then all characters must escape through the entrance. | **no** — plays as "kill all enemies" | The scenario is not complete by the end of the twelfth round. Any character becomes exhausted before all treasure tiles are looted, or while not occupying an entrance hex. | yes |
| 61 | Fading Lighthouse | Loot all treasure tiles. | **no** — plays as "kill all enemies" | — | — |
| 62 | Pit of Souls | Kill the Hungry Soul. | **no** — plays as "kill all enemies" | — | — |
| 63 | Magma Pit | Kill all enemies. | yes | — | — |
| 64 | Underwater Lagoon | Kill all enemies. | yes | — | — |
| 65 | Sulfur Mine | Kill all enemies and loot all treasure tiles. | **no** — plays as "kill all enemies" | — | — |
| 66 | Clockwork Cove | Occupy pressure plate (e) — a character occupies it at the end of their turn. | **no** — plays as "kill all enemies" | — | — |
| 67 | Arcane Library | Kill the Arcane Golem. | **no** — plays as "kill all enemies" | — | — |
| 68 | Toxic Moor | Kill all enemies and protect the tree (a). | **no** — plays as "kill all enemies" | The tree is destroyed. | **no** |
| 69 | Well of the Unfortunate | Bring the doll to the well (a) — complete when the doll is brought to a hex adjacent to the well. | **no** — plays as "kill all enemies" | — | — |
| 70 | Chained Isle | Kill all demons. | **no** — plays as "kill all enemies" | — | — |
| 71 | Windswept Highlands | Loot all treasure tiles, then all characters must escape through the exit (a). | **no** — plays as "kill all enemies" | Any character becomes exhausted while not occupying an exit hex (a). | **no** |
| 72 | Oozing Grove | Destroy all trees and kill all Oozes. | yes (objective goal) | — | — |
| 73 | Rockslide Ridge | Kill all enemies and loot all treasure tiles. | **no** — plays as "kill all enemies" | — | — |
| 74 | Merchant Ship | Kill all enemies and keep the ship afloat. | **no** — plays as "kill all enemies" | A water tile has to be added but cannot be placed because the B tile is full. | **no** |
| 75 | Overgrown Graveyard | Dig up all graves and kill the Bloated Regent. | yes (objective goal) | — | — |
| 76 | Harrower Hive | Reveal all rooms and kill all enemies. | **no** — plays as "kill all enemies" | — | — |
| 77 | Vault of Secrets | Loot all treasure tiles and kill all City Guards before the alarm is raised. | **no** — plays as "kill all enemies" | Any City Guard occupies a pressure plate (a). | **no** |
| 78 | Sacrifice Pit | Kill all enemies and stop the sacrifice. | **no** — plays as "kill all enemies" | The victim is sacrificed: a Cultist (b) starts its turn adjacent to the altars (d) while the victim is also adjacent to the altars. | **no** |
| 79 | Lost Temple | Kill the Betrayer. | **no** — plays as "kill all enemies" | Fish is killed. | **no** |
| 80 | Vigil Keep | Every character must loot one treasure tile, and then all characters must reach the B tile (escape). | **no** — plays as "kill all enemies" | Any character becomes exhausted while not occupying the B tile. | **no** |
| 81 | Temple of the Eclipse | Kill the Colorless. | **no** — plays as "kill all enemies" | — | — |
| 82 | Burning Mountain | Sacrifice one artifact, or escape with all artifacts. | **no** — plays as "kill all enemies" | — | — |
| 83 | Shadows Within | Kill all enemies. | yes | — | — |
| 84 | Crystalline Cave | Kill all enemies and protect the crystal (a). | **no** — plays as "kill all enemies" | The crystal is destroyed. | yes |
| 85 | Sun Temple | Kill all enemies. | yes | — | — |
| 86 | Harried Village | Save seven villagers before five are killed. | yes (objective goal) | Five villagers are killed. | yes |
| 87 | Corrupted Cove | Kill the Giant Ooze. | **no** — plays as "kill all enemies" | — | — |
| 88 | Plane of Water | Bring the Lurker King's claw to the crystal (a) — the scenario is complete when the claw is carried to a hex adjacent to the crystal. | **no** — plays as "kill all enemies" | — | — |
| 89 | Syndicate Hideout | Kill all enemies. | yes | — | — |
| 90 | Demonic Rift | Close the rift (after Section 1: kill all Living Spirits). | **no** — plays as "kill all enemies" | No character is present in the left room at any time; only one character is left unexhausted; after Section 1, either room has no character present at any time. | **no** |
| 91 | Wild Melee | Kill all enemies. | yes | — | — |
| 92 | Back Alley Brawl | Kill all non-city enemies. | **no** — plays as "kill all enemies" | A City Guard or City Archer is killed. | **no** |
| 93 | Sunken Vessel | Kill all enemies. | yes | — | — |
| 94 | Vermling Nest | Kill all enemies and loot the treasure tile. | **no** — plays as "kill all enemies" | — | — |
| 95 | Payment Due | Kill the Prime Lieutenant. | **no** — plays as "kill all enemies" | — | — |

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
