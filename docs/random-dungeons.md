# Random dungeons

The random dungeon deck (rulebook pp. 50–51, "Game Variant: Random Dungeon Deck"): instead of a
scenario from the book, the party plays three rooms, each set up from a **room card** (a map, twelve
numbered hexes, obstacles, A/B entrances and exits, a minor and a major penalty) and a **monster
card** (what goes on each number — monsters by player count, traps, terrain, loot, a treasure).
The next room is set up when its door is opened. The goal is to clear all three rooms. A random
dungeon doesn't progress the campaign: it gives experience, gold, checkmarks and personal quest
progress. Scenario #55 Foggy Thicket is one, from six room and six monster cards, with a treasure
on the third room's "12".

## The rules, as the game reads them

- RD-1 Three rooms; each from the top of the shuffled room and monster decks.
- RD-2 Exits and entrances are A or B. The next room must have an entrance of the type of the
  exit used: room cards from the top that don't match are discarded.
- RD-3 Two exits: the party uses either; the other is closed off. Two entrances: the one matching
  the exit used (in the first room the party chooses where to start).
- RD-4 First room: characters start on any empty hex within two hexes of the entrance.
- RD-5 Entrances and exits are the half-hex at the tile's puzzle connection nearest the arrow.
- RD-6 Penalties as a room is revealed: suggested none in the first room, the minor penalty of
  the second, the major penalty of the third; players may raise it up to the major penalty of
  every room. "The character who opened the door" in the first room: the players choose who;
  "the previous room" in the first room: nothing happens.
- RD-7 Treasure tiles hold what the monster card prints (never campaign content); traps do what
  the card's trap line says (the red damage symbol = a damage trap).
- RD-8 Running out of an overlay tile: use a comparable one. Standee numbers are random; running
  out of a monster type, as usual.

## Data

- **Monster cards** are in the edition data: `EditionData/gh/sections/rnd-554.json` … `rnd-573.json`
  (group `randomMonsterCard`: `rooms[0].monster` by `marker`, `overlays` by `marker` with traps'
  effects and treasures' contents).
- **Room cards** are not in any data set. They are written by hand from the cards into
  `Resources/ScenarioMaps/placements/gh-dungeons.json` (`DungeonRoomCard`, `DungeonCardStore`),
  in tile coordinates: `tiles` (with `matchTurns`, the turn at which the card draws the tile, and a
  `join` for a room's second tile), `entrances`/`exits` (type and the half-hex), `numbers`,
  `overlays`, `minor`, `major`.
- Reading a card: `TILE_SHEET=f1b TILE_SHEET_TURNS=0 TILE_SHEET_OUT=/tmp/tiles swift test --filter testRenderTileSheet`
  draws a tile with its coordinates (the ring just off the edge in cyan). Checking a written
  card: `ROOM_SHEET=all ROOM_SHEET_OUT=/tmp/rooms swift test --filter testRenderRoomSheet` draws each
  room as the game lays it out with its numbers, entrances and exits. Card images: Worldhaven,
  `images/random-dungeons/gloomhaven/` (not bundled).

## How it is built

- `RandomDungeon` (Engine): the draws — room card, monster card, the entrance used, and the room
  behind each exit (both exits of a room, so either can be taken). `RandomDungeon.draw` follows
  RD-1/RD-2 from one shared pair of decks, so no room card is in a dungeon twice. Kept in the save
  and built again from it.
- `RandomDungeonMap.build` (Engine): the dungeon as the map data's tile tree (`VGBScenario`) — the
  first room is the root; each next room hangs from its exit as a door, turned so it lies on the
  far side of the door and covers no room before it; a room's second tile joins by a corridor.
  Monster card figures become map monsters by player count, its things become overlays (coin,
  chest with id `rnd-<card>-<number>`, trap, terrain), its traps' effects a `ScenarioTraps`; the
  first room gets starting hexes (RD-4).

## Status (2026-10-14)

Built: the data model and loader, the draw, the map, and all twenty room cards — each drawn by
`testRenderRoomSheet` and checked against its card (numbers, obstacles, entrances, exits). Where a
room's two tiles meet on a hex of neither (Armory's 1, Burrow's 2: the card covers it with a grey
corridor piece), the `join` is that hex, which the corridor makes a cell. Several cards print their
tiles a quarter turn from any of the six ways a tile lies; `matchTurns` then is the turn read after
turning the card, and only the difference between a room's two tiles matters. The monster-card data
had four mistakes, fixed against the cards: Defiled's forest imp on 1 instead of 7, "mormal" (Wild)
and "nromal" (Scaled), and Horrific's lurker missing from its monster list
(`testEveryMonsterCardIsWritten`). About one dungeon in two hundred has a room that would lie on a
room before it however it is turned; the rules don't say what then, and the game draws again
(`RandomDungeonMap.draw`).

Playable (2026-10-14): the Random Dungeon is offered in town, always and again, and doesn't
progress the campaign (a win keeps experience, gold, the success bonus, battle goals and quest
progress; nothing is marked completed or unlocked). A scenario with a `randomDungeon` rule is drawn
as it is set (`ScenarioManager.drawDungeon`, from the decks the rule names), kept on the scenario
and in the save (`Scenario.randomDungeon`, `ScenarioSnapshot.randomDungeon`), played as data with a
room per drawn room (`RandomDungeon.scenarioData`), its map built from the draws wherever a map is
loaded (`ScenarioManager.map(for:)`). The exit not taken is closed off (RD-3,
`BoardCoordinator+Dungeon`), so the default goal — every enemy dead, every door open — is the
dungeon's. Treasure tiles hold what their monster card prints (RD-7, `lootDungeonTreasure`; the
recovery picker can take from the lost pile). The all-scenarios playthrough plays one each seed;
five seeded veteran games were all won without a violation. Tests: `RandomDungeonTests`
(ten); mutations `dungeon…` in `scripts/mutate.py` (eight), each noticed.

Penalties (RD-6): every room card's two are read (`DungeonPenalty.byRoom`, checked against the
printed text by `testEveryPenaltyIsRead`) and fall as the door opens at the suggested difficulty
(`applyDungeonPenalty`): conditions (permanent too), curses, damage (negated as usual), Bless cards
for the monsters, elements inert, cards lost or discarded (the players choose, with the start
discard picker widened), items spent or consumed, Strengthen and Invisible, a normal enemy made
elite (the players choose) and enemies of the previous room set up again (on their clear numbers,
the monster card's first such), and as standing effects kept on the scenario and in the save
(`Scenario.dungeonEffects`): Shield this round or for good, +1 Attack, +1 Move and Range (ranged
attacks only), "Retaliate 2, Range 3", heal 1 as each enemy's turn starts, no consuming.

#55 Foggy Thicket is done: its decks, its −1 cards, its goal treasure on the third room's "12"
(placements `dungeonTreasure`, `lootActionOnly`, `goal.loot`). It and a Random Dungeon are in the
all-scenarios playthrough.

Setup (2026-10-14): the penalties are a choice beside the difficulty when a random dungeon is
chosen (None, Suggested, Major; `RandomDungeon.penalties`); at Major the first room's major penalty
falls as the party starts, the players choosing who "opened the door" (`applyFirstRoomPenalty`). A
first room with two entrances asks where the party starts (RD-4, `chooseFirstEntrance`,
`startAtEntrance`). Each room is named by its two cards as it is set up ("The Mangy Trail").

Nothing of the variant is left to build. Choices the rules leave open, as the game reads them:
a room that can't be laid apart from the rooms before it makes the game draw the dungeon again;
"replace an enemy in the previous room" sets up again the monster card's first such enemy (for the
party's size) whose number is clear; a penalty's "+1 Range" widens ranged attacks only; the
success bonus experience is given for a random dungeon won.

Seen on the 11-inch iPad Pro simulator (2026-10-14): setup with its Penalties row, the brief, the
first room and its starting hexes. The brief now names the dungeon without a number and shows only
the first room's monsters (it had listed every drawn room's, rooms behind exits never taken
included). Open question: a road event is drawn before a random dungeon as before any scenario; the
variant "doesn't progress the campaign", and a road event can change gold and reputation.
