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

Still to do, in order:

1. Penalties (RD-6). Read for every card (`DungeonPenalty.byRoom`, checked against the printed
   text by `testEveryPenaltyIsRead`) and falling as a door opens at the suggested difficulty
   (`applyDungeonPenalty`). Played: conditions (permanent ones too), curses, damage (which may be
   negated as usual), Bless cards for the monsters, elements inert, Strengthen (and for good),
   Invisible on elites, and as standing effects kept on the scenario (`Scenario.dungeonEffects`,
   saved): Shield this round or for good, +1 Attack, +1 Move, "Retaliate 2, Range 3" (Den; an
   effect's `retaliate`/`retaliateRange`, counted in `performAttack`). Still to play: +1 Range
   (Trail), heal 1 at each turn's start (Passage), no consuming elements
   (Clearing), cards lost or discarded (Cabin, Crossroads — the start-of-scenario discard picker
   can be widened), items spent or consumed (Trail, Hallway), a normal enemy made elite and
   enemies put back in the previous room (Encampment, Road); the difficulty as a choice at setup
   (`RandomDungeon.penalties`: none, suggested, major); the first room's penalty at "major"
   ("the opener": the players choose who).
2. The first room's entrance chosen by the players when it has two (RD-4; today the first).
3. The room's title on reveal: the monster card's adjective and the room card's noun ("Mangy
   Trail").
4. #55 Foggy Thicket: its six-card decks are already used when it is drawn; still its three −1
   cards (a start rule in the data — check it applies), the third room's "12" a treasure tile only
   a Loot action takes (instead of whatever the monster card puts there), the goal to loot it, and
   adding it to the all-scenarios playthrough.
