# The scenario book, for the game

The map data the game is built on (from Virtual Gloomhaven Board) has tiles, doors, overlays and
monster positions, and the scenario data (from Gloomhaven Secretariat) has monsters, objectives
and rule triggers. Neither says **where** an objective or a lettered spawn hex is, or **what the
goal is**. Those come from the scenario book, and this folder is where what was read from it lives:

- [gh-scenario-rules.md](gh-scenario-rules.md) — the rules of all 95 scenarios as short notes:
  goal, losses, objectives, sections, special rules, boss specials, map letters.
- [rules-audit.md](rules-audit.md) — every one of those rules against the game: done, partial or
  missing, and where; and, at its top, what is still open by the kind of work it needs.
- `GlavenGame/Resources/ScenarioMaps/placements/gh.json` — the hexes, and the goals the game
  enforces for objectives (below).
- `GlavenGame/Resources/ScenarioMaps/placements/gh-traps.json` — what each scenario's traps do,
  from its map legend ([Traps](#traps-what-each-scenarios-traps-do), below).

How the work on these rules is done from start to finish, and what to do next, is in
[../rules-work.md](../rules-work.md); the helpers for reading the book
(`scripts/scenario-book/`: a page of the PDF as a picture, its text, and a tool that merges what
was read into `gh.json` keeping the file's layout) are described there.

The book itself (Scenario Book, second printing) isn't kept in the repository — the PDF is 319 MB.
It can be read online at <https://kirsanova.relfbo.qapubl.club/view/145446/2/>; page numbers in
the notes (p.55 for #41, and so on) are that book's.

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
    escorts have arrived), `{"lock": 0}` (that lock of `locks`, from 0, has been released; `{"locked": 0}` that it hasn't yet),
    `{"looted": "goal"}` (every goal treasure tile; a tile ref for the goal treasure on it; a
    treasure's number), `{"unrevealed": 2}` (that room isn't revealed yet), `{"occupied": {"markers": ["a"], "more":
    {"3": ["b"]}}}` (every pressure plate in play for this many characters has a figure on it),
    `{"partyAchievement": "sun-blessed"}` (the party has it), `{"noCharacterOn": ["d1b", "c2a"]}`
    (no character stands on those tiles). A rule with `"always": true` fires at once; without it, as the round ends
    ("at the end of the round in which…").
  - `setUp` — monster types held back by `later` are set up now, where the map prints them.
  - `traps` — letters whose hexes get a damage trap; a figure on foot standing on one springs it
    at once (#69).
  - in a figure effect: `"times": "F"` — the effect happens that many times, each on its own (a
    heal for every bone pile, of which Poison stops only the first: #58).
  - in a spawn's `count`: `N`, how many times the rule has applied, this time included
    (`"N % 2"`: every second spawn, #90).
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
  to each of their attacks), `move` (added to each of their Move abilities: #88's −1),
  `advantage`, `disadvantage` and `shield` (a number or a formula over
  X, C and L, added to their Shield, which never falls below none). X is what `per` counts:
  `{"objective": 1}` or `{"monster": "living-bones"}` on the board, or
  `{"tokens": 4, "lostWith": "ooze"}` — tokens of which one goes each time such a monster dies.
  `untilLooted` — only on a character who hasn't looted a goal treasure tile yet;
  `noItems` — they can't use any item (#80).
- `apart`: monster types that are a third side — enemies to the characters and to every other
  monster type, allies of one another (#85 Sun Demons, #91 Living Spirits, #92 the city's men).
- `sheltered`: objectives that are allies only to be healed: no monster attacks them and no
  ability touches them (#68's tree, which only the scenario harms).
- `inactive`: monster types that for a time don't act and can't be affected by anything, and
  whose hexes figures move through but can't stop on: `{"monsters": [...], "rounds": "odd"}`
  (or `"even"`: #61's two groups) or `"untilSetUp": true` (asleep until a rule's `setUp` names
  them: #79's Stone Golems). Drawn hollow.
- `cycles`: bosses that go round a set of places, by monster type: `letters` (lettered hexes in
  order, then the first again) or `"doors": true` (the scenario's `locks`, in order — it jumps
  into the doorway and opens it: #2's Bandit Commander); `"appears": true` (it isn't set up, and
  off the map as its turn starts it appears on its next hex) and `"leavesAfterMelee": true`
  (#48's Dark Rider). A `teleport` action in a special (#51's Gloom) takes the next hex. A
  figure on the hex means the closest free one.
- `specials`: a boss's two specials as this scenario prints them, in place of its stat card's
  (#36: "Move +0, Attack +0").
- `march`: monster types that don't move as their cards say — each turn they go `move` hexes
  toward the nearest hex lettered with one of `toward` (the closed door on the way, before those
  are revealed; `"opensDoors": true` lets them walk through it), then do the rest of their card
  (#77's City Guards). The goal's `lostIfStands` (`{"monsters": [...], "marker": "a"}`) loses
  the scenario when one of them stands on such a hex.
- `undamageable`: monster types nothing damages (conditions still apply), and `reprieve`
  (`{"killed": [...], "removes": "living-spirit"}`): for each death of one of the first, one of
  the second may be banished — the players are asked which (the nearest to the killer first) or
  none; with no one to ask, the nearest goes (#70).
- `focusFirst`: objectives the monsters that attack them go for first — one that can get within
  range this turn focuses on it, whoever is nearer (#35 and #36 the gate, #84 the crystal).
- `saves`: objectives a character may spare a source of damage by losing a card from their hand —
  `{"objective": 2}` as often as there are cards (#44's captives), `{"objective": 1, "times": 2}`
  twice a scenario (#84's crystal). As the damage is about to be suffered the party is asked
  (`SaveChoiceSheet`): let it suffer, or pick a card from any hand. The sheet says when
  the scenario is lost with the objective; headless play and the simulator's policies give a card
  only then.
- `carried`: things a character holds through the scenario, each `{"name": "doll", …}`
  (`BoardCoordinator+Carried`; who holds what is in `BoardState.carriedBy`, what lies where in
  `carriedLying`, and the party panel says "Holds the doll"). How it is come by: `"start":
  "choose"` (the players are asked as the scenario starts: #69's doll), `"droppedBy":
  "lurker-king"` (it lies where that monster dies, instead of a money token: #88's claw),
  `"treasure": "goal"` or `"62"` (whoever loots that tile: #58's Occult Dagger, #82's artifacts;
  with `"onlyQuest": "526"` only the character on that personal quest may loot it, where someone
  is). What it does: `"move": -2` on its holder's Moves; `"pierce": 4, "against":
  "the-harvester"` on its holder's attacks on that monster; `"lostWithHolder": true` loses the
  scenario if its holder is exhausted. With `"passes": true` it changes hands when another
  character performs a Loot action with the holder in range, and lies in the hex of a holder who
  is exhausted, to be looted like a treasure tile; without it, it stays with whoever has it. A
  goal's `reach` takes `"holding": "doll"`: only its holder getting there counts. Several things
  with the same `treasure` are given in the order written (#81's Crystal of Zenith, then its
  Sphere of Midnight), and `"spend": {"marker": "a", "adjacent": true, "damage": "2xC", "to":
  "the-colorless"}` lets the holder discard one as their turn ends at (or beside) that lettered
  hex: they are asked, and the monster suffers the damage. With `"start": "choose"`, an
  `"onlyQuest"` or `"item": "gh-114"` gives it without asking to the character on that quest or
  bearing that item (#54's Staff of Xorn is the Seeker's). `"soleHarmTo": ["harrower-infester"]`
  makes its holder the only one who damages that monster type, each point of that damage
  charging it up to `"charge": "2xCx(L+1)"`; a `reach` with `"charged": true` waits for it full.
- `asleep`: monster types set up asleep, `["spitting-drake"]` (#71, `BoardCoordinator+Sleep`). Unlike
  an `inactive` monster a sleeper is there to be attacked: it does nothing until a character or a
  character's summon attacks it, damages it, gives it a negative condition or ends any movement
  beside it, and then acts that round like a monster just spawned. Summons leave sleepers alone.
- `barred`: doorways shut to some monsters, open or not — `{"monsters": ["stone-golem"], "between":
  ["a2a", "m1a"], "from": "m1a"}` (#67, #73): no monster of those types standing on tile `from`
  (any, without it) enters or passes through the door between the two tiles, by its own move or a
  push or pull.
- `battery`: a gun that takes no turn and is fired by its crew — `{"gun": "siege-cannon", "crew":
  "city-archer", "move": 3, "line": "b", "side": "W", "tiles": ["g1a"]}` (#49,
  `BoardCoordinator+Battery`). Each round the crew member nearest the gun moves `move` toward a hex
  beside it that isn't lettered `line` instead of acting, and beside it fires: every character and
  summon on a `line` hex, in the row of one on `side` of it (W or E), or on one of `tiles` suffers
  the gun's stat-card Attack as damage.
- `carry`: monsters that carry an objective somewhere instead of acting — `{"carriers":
  "cultist-scenario-78", "objective": 1, "toward": "c", "altar": "d", "lost": "…"}` (#78,
  `BoardCoordinator+Carry`). Each carrier moves its stat-card Move: to the objective's side, then
  toward the hexes lettered `toward` (the nearest hex beside `altar` when they are taken), opening
  doors; the objective then follows as far as it was carried. A carrier starting its turn beside
  an `altar` hex with the objective beside one too loses the scenario for the reason written.
- `throne`: an objective that is a boss's hit points and jumps about the map — `{"boss":
  "prime-demon", "objective": 1, "cycle": ["a", …, "f"], "summons": {"a": "wind-demon", …},
  "eliteFrom": [3, 4]}` (#21, `BoardCoordinator+Throne`). Nothing damages the boss; the objective
  has its hit points and the boss falls with it. A special of the boss whose text is "Throne
  moves" sends the objective (and the obstacle it stands on) to the next lettered hex of `cycle`,
  moving aside who stands there and revealing the room, and summons `summons[letter]` there —
  elite from `eliteFrom[0]` characters on the first special, `eliteFrom[1]` on the second.
- `perch`: a boss that sits on every hex of an obstacle and flies from one to the next —
  `{"monster": "elder-drake", "cycle": ["a", "b", "c"], "start": "c", "summons": "zephyr",
  "count": 2}` (#34, `BoardCoordinator+Perch`). Write each letter on all the hexes of its obstacle.
  The boss is attacked through whichever of its hexes is nearest and attacks from the best of them
  (`BoardState.bodies`); a special whose text is "Fly to next perch…" summons `count` of `summons`
  beside it and takes it to the next letter. What it summons is untouchable — nothing damages or
  affects it and no summon focuses on it — and performs "Move 2, Attack C" as the boss's turn
  starts instead of having a turn of its own.
- `sway`: a boss whose specials move and turn the party — `{"boss": "the-betrayer", "flee": 4,
  "controlled": 2}` (#79, `BoardCoordinator+Sway`). After its first special each character and
  summon moves `flee` to end as far from it as they can; a special whose text is "Mind Control"
  draws them all to its side and turns the character last to play two cards this round, with
  their summons: that turn is a Move of `controlled` and the attacks of the top of the leading
  card, made on the party, with both cards discarded.
- `walls`: walls broken down by damage instead of doors — `{"objective": 1, "condition": "stun"}`
  (#76, `BoardCoordinator+Walls`). Every `breakable-wall` connector of the map is shut to everyone
  (no one opens it by walking in, or jumps it) and carries one of the scenario's objective
  `objective`, whose `health` is the wall's hit points; the objectives are made as the walls come
  into sight, so no room lists them and no hexes are written. A character attacks a wall like an
  enemy; a summon or anything else acting by itself leaves it alone. Destroyed, it is a corridor:
  its room is revealed — and any other tile its hex touches — and every enemy beside it gains
  `condition`. The default goal then needs every room revealed, not every wall down.
- `discardAtStart`: how many ability cards each character discards "at the start of the scenario
  as a scenario effect" (#76: `3`, `BoardCoordinator+StartDiscard`). Each character in turn chooses
  them from their hand (`StartDiscardPicker`) before anyone chooses cards for the first round;
  played without prompts, the last cards of the hand go.
- `drift`: what moves the party one hex as each round ends, before the round's other end-of-round
  rules (`BoardCoordinator+Drift`): `{"name": "wind", "directions": [["NW", "NE"], ["E"], ["SW", "SE"],
  ["W"]]}` (#71: the sides of a hex — NE, E, SE, SW, W, NW as the map lies in the game — by round,
  round and round; with two the players tap one, and may stay if one is shut) or `"byInitiative":
  {"monster": "lurker", "even": ["NW"], "odd": ["NE"]}` (#88: by this round's card of that
  monster type). `tiles` keeps it to figures on those tiles, `"sheltered": true` leaves alone a
  figure with an obstacle or wall on the side it comes from, `"blocked": 3` is the damage for one
  that can't be moved, and `"order": "top"` goes from the top of the map down instead of in
  initiative order. Characters and their summons are moved (a summon before its owner); the move
  is forced movement, so traps are sprung. Check which way the book prints the map before writing
  the sides.
- `rolling`: obstacles that roll along their rows as each round ends, after any `drift` —
  `{"subType": "boulder-1", "side": "W", "reenter": "b", "steps": [1, 2, 3]}` (#73,
  `BoardCoordinator+Rolling`). The obstacles with that art are the rollers; a row runs from each hex
  lettered `reenter` to the last hex of the map on that side, and a roller that gets there comes
  back in at the letter. The players choose which row rolls how far (each a different one of
  `steps`); a roller destroys an obstacle in its way, lies on traps and terrain without changing
  them, deals trap damage to a figure whose hex it enters and pushes the one it stops on a hex on.
  List the art under `indestructible` too, so no ability removes one.
- `flood`: water that rises on a tile, after any `drift` and `rolling` —
  `{"tile": "b1a", "every": "R % 2 == 0 || C > 2", "bail": "e", "dry": {"marker": "d",
  "characters": 3}, "lost": "…"}` (#74, `BoardCoordinator+Flood`): as a round for which `every`
  holds ends, the players tap a dry hex of the tile beside the water and it becomes water; with
  none left the scenario is lost for the reason written. A character looting a water hex of the
  tile picks the tile up (one at a time) and is rid of it as a turn ends on a hex lettered `bail`.
  `dry` takes the water off the lettered hexes at setup for that many characters.
- `tokens`: numbered tokens lying face down, `{"marker": "a", "count": 6}` (#95): the numbers 1 to
  `count` are shuffled with the game's seed and one is laid on each hex lettered `marker` as its
  room is revealed (`layNumberedTokens`; `BoardState.tokenHexes`, drawn as "?"). They are looted
  like money — by ending a turn on one or with a Loot action — and the number is told then
  (`tokensLooted`). A lock's `"tokens": [1, 2, 3, 4]` is turned once all of those are found.
- `drawsFromACharacter`: escorts whose attacks draw "from whichever attack modifier deck the
  players choose" (#44 Redthorn, #56 the captive Orchids): as one attacks the players are asked
  whose deck, and the card is drawn from that character's.
- `dig`: objectives dug up with movement, not attacked (#75's graves): during a Move a tap on one
  beside the mover spends a point of the move on it — a hit point, so `health: "1+C"` is the
  movement it takes — in as many moves as it needs; dug up, it is destroyed as any objective is
  (`whenDestroyed`, the goal's `destroy`).
- `forgo`: what a character beside an objective may give up an action for —
  `{"objective": 2, "strengthens": 1}`: the objective is freed and leaves the map, and objective 1
  attacks for 1 more with each one freed (#44's captives and Redthorn). Offered beside the basic
  action for a half none of whose abilities has been performed; the half's card is discarded as
  after a basic action. The simulator's policies free a captive whenever one is beside them.
  With `"does": "cleanse"` the button and the log say so, and with `"bottom": true` only a bottom
  action may be given up (#26's water pumps). The goal key `freed: [1, 2, 3]` is "every one of
  these objectives freed or cleansed" (as many as the party's size sets up, every room revealed).
  An objective that has left the map this way is no longer `present` to a scenario rule.
  `{"treasure": true, "bottom": true}` is the goal treasure tile beside the character, looted for
  the action given up as a Loot action would loot it (#52), once for each character where each
  must loot one.
- `splitStart`: there are two starting rooms and no more than half the party (rounded up) may
  start in the same one (#50, #58, #85).
- `water`: what water hexes do — `hurtsThePoisoned` (a poisoned character or summon walking in
  suffers trap damage, #68), `endOfTurn` (damage for any figure ending its turn there, #95), `cleanses` (a character ending
  a turn on a water hex of the named tiles is cleansed once: the tile goes, Shield against the
  named monsters' attacks and no more Poison, #87).
- `notes`: the special rules in words for the scenario brief — only those the game enforces.
  With notes written, the rules written here aren't described a second time from their data,
  no "More … arrive" lines are guessed, and a text the data ships is left out where a note says
  the same and more ("Chord 1, while it stands: …").
- `whenDestroyed`: what appears where an objective stood when it is destroyed, by objective
  (`{"1": {"name": "living-corpse", "player2": "normal", …}}`): a Living Corpse from each grave.
- `indestructible`: obstacles no ability destroys — `subTypes` (the map data's overlay sub-types:
  `"dark-pit"`, `"wall-section"`, `"boulder-3"`) or every obstacle of some `tiles` (#52's centre
  room). An obstacle that is an objective (a totem, an altar) is never destroyed by an ability.
  With `"solid": true` the obstacles of `tiles` also can't be "moved through in any way" and
  "block line of sight" (#52): a jump or a flight stops at them, a flier isn't pushed onto one,
  and sight is blocked as by a wall (`HexCell.solid`). Range is still counted across them.
- `startAmongMonsters`: a starting hex is offered only if its section of the room — what can be
  walked to from it without leaving the tile, obstacles in the way — holds a monster (#52:
  "Characters can only start in sections of the center room that contain monsters").
- `resetOnLoss`: numbered treasure handed back when the scenario is lost — its items leave the
  looter and the tile can be looted again (#82's chest).
- `passiveTurns`: escorts that do nothing but still take a turn at their initiative, in which
  their conditions act — Wound hurts (#27's Hail, at 99).
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
    `"adjacent": true`; with `"enter": true` entering the hex at any point of a move is enough),
    `either` (any one of several goals as well; an alternative's `conclusion` — `"82-A"` — is the
    conclusion section read when the scenario is won that way, whose rewards are applied).
    An escape where all must stand on the exit at once is also complete when every character
    was exhausted while standing on an exit hex (with the rest of the goal done).
  - lost: `lostAt` (objective → how many killed), `lostIfExhausted` (`"any"`, `"offExit"`,
    `"beforeLoot"`; `lostIfExhaustedOnceRevealed` delays it until a tile is revealed),
    `lostIfKilled` (monster types), `lostIfEmpty` (`[{"tiles": [...], "onceAppeared": "living-spirit",
    "text": "…"}]`: no character stands on those tiles — #90's rooms) and `lostBelow` (fewer than
    that many characters left unexhausted).
  - Where characters stand (`escape`, `occupy`, `reach`) is judged as a turn or the round ends.
- `laidOut`: map tiles on the map from the start though their room isn't revealed (#35's yard
  behind the gate). Only the monsters an already revealed room's data letters for hexes there
  (`marker` on the room's monster, the letter written on the tile) are set up; the room's own are
  set up when its door opens or a character or ally gets onto one of the tiles.
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
    step off (whoever is in the doorway is put out of it and suffers trap damage — a character
    may lose cards to negate it, like any damage); with `"firstAtTurnEnd": true` it opens the
    first time only as a turn ends on its plate (#66's door 1);
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
| 26 Ancient Cistern | water pumps | — (imps spawn beside their pump) | — | a character beside a pump gives up a bottom action to cleanse it (`forgo`); the goal is every pump cleansed (`freed`) |
| 27 Ruinous Rift | Hail | b–e | lost if Hail dies (win at round 10 is a scenario rule) | — |
| 29 Sanctuary of Gloom | 3 barred doors | — | — | — |
| 31 Plane of Night | rock column | b, c | win: destroy the column | — |
| 33 Savvas Armory | barred door | a (exits), c, d | win: loot all, then everyone on the exit; lost if exhausted off it | — |
| 35 Gloomhaven Battlements A | barred door | a, b (the battlements, where the first room's archers stand) | win: destroy the door, kill the Captain of the Guard | — |
| 36 Gloomhaven Battlements B | the gate (protected) | a–e | win: kill the Prime Demon (it arrives at e when the gate falls) | — |
| 38 Slave Pens | the Orchid | — | lost if he dies | he heads for the nearest enemy, not the shaman on the D tile |
| 39 Treacherous Divide | altar | — | win: destroy the altar | — |
| 42 Realm of the Voice | 6 vocal chords | — | win: destroy all | — |
| 44 Tribal Assault | Redthorn, 9 captives (protected) | — | lost if a captive is killed | a card may be lost to spare a captive (`saves`); a character beside one may give up an action to free it (`forgo`) |
| 45 Rebel Swamp | 6 totems | — | win: destroy all | — |
| 56 Bandit's Wood | 3 captive Orchids | — | lost when all three die (scenario rule) | — |
| 57 Investigation | — | a | win: kill the Infiltrator (he appears where the marked guard fell) | — |
| 58 Bloody Shack | 4 bone piles | — | win: kill the Harvester | the Occult Dagger is `carried`: looted by the Vengeance character only, Pierce 4 against the Harvester |
| 62 Pit of Souls | — | a, b, c | win: kill the Hungry Soul (appears at c after ten kills) | — |
| 68 Toxic Moor | the tree (sheltered) | — | lost if it is destroyed | a poisoned summon doesn't yet avoid water as it would a trap |
| 69 Well of the Unfortunate | — | a–d (traps appear at d when door 1 opens) | win: the doll's holder enters a hex beside the well | the doll is `carried`: chosen at set-up, passed by a Loot action, dropped where its holder is exhausted |
| 70 Chained Isle | — | a, b | — | — |
| 72 Oozing Grove | 3 trees | — (oozes rise beside their tree) | win: destroy all trees, kill all Oozes | — |
| 74 Merchant Ship | — | a–e | lost when the hold has no hex left for a water tile | the water rises as rounds end and is bailed (`flood`) |
| 75 Overgrown Graveyard | 9 graves | — (what rises, rises where the grave was) | win: all graves and the Bloated Regent | graves are dug up with movement spent beside them (`dig`), never attacked |
| 76 Harrower Hive | 23 walls, made as they come into sight (the objective is added to `76.json`; no hexes are written) | — | win: every room revealed and every enemy dead | `walls`, `discardAtStart` |
| 79 Lost Temple | Fish | a, b, c (pressure plates) | win: kill the Betrayer; lost if Fish is killed | the Betrayer's specials drive the party off and turn one of them (`sway`); of the mind-controlled top action only the attacks are made |
| 84 Crystalline Cave | the crystal | — | lost if it is destroyed | protected, no ally; twice a card may be lost to spare it (`saves`) |
| 86 Harried Village | 11 villagers | b–f | win: 7 reach the docks; lost at 5 killed | — |
| 90 Demonic Rift | — | b, c (the Living Spirits, once every demon is dead; a Night Demon at b as an even round ends with no one in the right-hand room) | win: every Living Spirit killed | — (`DemonicRiftTests`: both rooms set up, characters cross by the altars for 1 movement, the losses for an empty room) |
| 92 Back Alley Brawl | — | a, b, c (where the City Archer and the two City Guards are set up; not the book's letters) | win: every non-city enemy killed; lost if a guard or the archer is killed | — |
| 95 Payment Due | 5 boulders (3+L hit points; the objective is added to `95.json`) | a (the six numbered tokens), s (by door 1, where the demons arrive; not the book's letter) | win: kill the Prime Lieutenant | `tokens`; door 1 locked until 1 to 4 are looted; a demon as each round ends until then |

### Locked doors written

| Scenario | Doors | Key |
|---|---|---|
| 2 Barrow Lair | the four side rooms | none: the Bandit Commander opens them |
| 15 Shrine of Strength | both side rooms; the treasure room | plate (c); every character on a side-room plate |
| 33 Savvas Armory | door 1 | every character on a plate (c) |
| 41 Timeworn Tomb | door 2 | plate (b) unlocks it (and wakes the room's golems and artilleries) |
| 53 Crypt Basement | all six | as rounds 2, 4, 6 and 8 begin |
| 66 Clockwork Cove | doors 1, f, g, h; the two side rooms | door 1 opens the first time as a turn ends on plate (a); then all four are held open by plates a–d; plate (d) |
| 67 Arcane Library | door 2 | held open by a plate (a) |
| 69 Well of the Unfortunate | door 1 | plate (b) |
| 71 Windswept Highlands | doors b, c, d | the first, second and third treasure tile looted |
| 74 Merchant Ship | doors 1, 2 | as rounds 3 and 6 end |
| 79 Lost Temple | door 1 | none: the rule that every Stone Golem is dead opens it |
| 82 Burning Mountain | all six | one for each elite killed, in order |
| 84 Crystalline Cave | the three cave walls | as rounds 4, 6 and 9 begin |
| 95 Payment Due | door 1 | tokens 1 to 4 looted (it can then be opened; it doesn't open itself) |

#95's door 1 is locked with `tokens: [1, 2, 3, 4]`: the numbered tokens that must all have been
looted (see `tokens` above).

Letters written only for a rule: #41 c–g (where the middle room's artilleries and golems are
set up; not the book's letters), #83 the altar (a), #92 a–c (the city's men; not the book's letters).

#35's yard behind the gate is laid out from the start without being revealed (`laidOut`), so the
first room's four City Archers stand on the battlements (a) and (b) as the book sets them up.

Letters written only for a goal: #23 and #40 pressure plates; #25, #37, #41 and #71 exits; #66
plates a–e; #82 the altar hex g; #88 the crystal.

Objectives an obstacle or a door already draws on the map (altars, totems, trees, graves, the
crystal, barred doors) were taken from the map data and checked against the book; escorts,
tokens and letters were read from the book's maps.

## Traps: what each scenario's traps do

The map data draws every trap with one of three pieces of art (its overlay sub-type: `spike`, a
spike pit; `bear`, a wooden spring trap; `poison`, a green cloud), and the art says nothing about
what the trap does. Each scenario's map legend does: a "Damage Trap" deals 2 + L, a "Stun Trap"
only stuns, a "Poison and Damage Trap" does both, an "Immobilize and Poison Trap" deals no damage.
The same bear-trap art is a Stun trap in #2, a plain damage trap in #66, Immobilize and Poison in
#44 and Poison and Damage in #15. `placements/gh-traps.json` has every legend, by scenario number
(`ScenarioTraps`, loaded by `ScenarioTrapStore` beside the placements):

```json
"15": {"page": 21, "kinds": [{"damage": true, "conditions": ["poison"], "count": 4, "art": "bear"},
                             {"damage": true, "conditions": ["wound"], "count": 4, "art": "spike"}]},
"69": {"page": 88, "kinds": [{"damage": true, "conditions": [], "count": 4, "art": "bear", "legend": 6}]}
```

- `page` — the page of the book the legend is on.
- a kind's `damage` — whether it deals trap damage (2 + L); `conditions` — what it gives the
  figure that springs it, in the legend's order (a Curse is a card into that figure's deck).
- `count` — how many of that kind the map sets up; `legend` — the number the legend prints, where
  that is more because a rule places the rest during play (#69's two traps at (d), which the game
  doesn't place yet).
- which of the map's traps are that kind: `art`, those the map data draws with that art, or
  `tiles`, those on these hexes (by tile, in tile coordinates, as in the placements:
  `{"h3b": [[1, 0], [1, 1]]}`), for a scenario whose two kinds share their art. A kind with
  neither takes every trap no other kind claims. In the 95 scenarios the art always separates the
  kinds, so none needs `tiles`; where the map data's art isn't the book's (#11, #70, #71) only the
  drawing differs.

`BoardBuilder` gives each trap its legend's effect as its room is revealed (`HexCell.trapEffect`,
a `TrapEffect`), and springing it (`springTrap`) deals damage only if the legend says so and gives
exactly its conditions. A trap that stuns ends the move it was sprung on and the rest of that
figure's turn; one that immobilizes ends only the move. Traps a card or a monster makes carry
what is printed for them ("2 damage Poison trap", "Stun trap"). A trap nothing describes — a
scenario map without a legend here (the solo scenarios and Forgotten Circles aren't read yet), a
game saved before this — is still guessed from its art: `bear` Immobilize and damage, `poison`
Poison and damage, anything else damage.

75 of the 95 scenarios have traps on their maps. `testEveryScenarioWithATrapHasALegendThatCountsItsTraps`
fails when a map with a trap has no legend, a trap of the map is none of its legend's kinds, or a
kind's `count` isn't the number of such traps on the map; `testTheBoardGivesEveryTrapItsLegendEffect`
checks the built board. To read a legend, find the scenario's map page (the notes give it) and
look for the red-bordered trap hexes in the legend; the name under each is what goes here.

| Legend | Scenarios |
|---|---|
| Damage | 1, 3, 4, 5, 8, 10, 16, 17, 19, 23, 33, 38, 57, 62, 64, 65, 66, 69, 70, 71, 84, 85, 90, 92, 94; one of two kinds in 40, 79, 89, 95 |
| Stun (no damage) | 2, 9, 11, 12, 14, 18, 20, 24, 26, 43, 46, 58, 75, 76 |
| Stun and Damage | 25, 35, 36, 61, 67, 73, 77, 93 |
| Poison and Damage | 6, 41, 45, 52; one of two kinds in 15, 32, 54 |
| Wound and Damage | 82, 91; one of two kinds in 15, 32 |
| Immobilize and Damage | 30, 37, 39, 59, 80 |
| Muddle and Damage | 13, 88 |
| Curse and Damage | 31 |
| Disarm and Damage | 50 |
| Poison and Stun (no damage) | 7; one of two kinds in 40, 95 |
| Immobilize and Poison (no damage) | 44, 53, 81, 87; one of two kinds in 79 |
| Immobilize and Muddle (no damage) | 60 |
| Immobilize and Disarm (no damage) | one of two kinds in 54 |
| Poison (no damage) | one of two kinds in 89 |

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
| 21 | Infernal Throne | Kill the Prime Demon. | yes — the altar is its hit points (`throne`): it falls when the altar is destroyed | — | — |
| 22 | Temple of the Elements | Destroy all altars (a). | yes | — | — |
| 23 | Deep Ruins | Occupy all pressure plates simultaneously. | yes | — | — |
| 24 | Echo Chamber | Open all doors (fog tiles). | yes | — | — |
| 25 | Icecrag Ascent | All characters must escape through the exit (a). | yes | Any character becomes exhausted while not standing on an exit hex (a). | yes |
| 26 | Ancient Cistern | Cleanse all water pumps. | yes | — | — |
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
| 44 | Tribal Assault | Kill all enemies and protect all captive Orchids (a). | yes | Any captive Orchid is killed. | yes |
| 45 | Rebel Swamp | Destroy all totems (a). | yes | — | — |
| 46 | Nightmare Peak | Kill the Winged Horror. | yes | — | — |
| 47 | Lair of the Unseeing Eye | Kill the Sightless Eye. | yes | — | — |
| 48 | Shadow Weald | Kill the Dark Rider. | yes | — | — |
| 49 | Rebel's Stand | Kill the Siege Cannon. | yes | — | — |
| 50 | Ghost Fortress | Loot all treasure tiles. | yes | — | — |
| 51 | The Void | Kill the Gloom. | yes | — | — |
| 52 | Noxious Cellar | All characters must loot one treasure tile. | yes | Any character becomes exhausted before they have looted a treasure tile. | yes |
| 53 | Crypt Basement | Survive for ten rounds (the scenario is complete at the end of the tenth round). | yes (scenario rule) | — | — |
| 54 | Palace of Ice | Place the fully charged Staff of Xorn on the altar (a): the scenario is complete when the Seeker of Xorn ends their turn adjacent to the altar (a) after the staff is fully charged. | yes — the staff's holder beside the altar with the staff full | The Seeker of Xorn becomes exhausted. | yes |
| 55 | Foggy Thicket | Loot the treasure tile in the third room. | **no** — random dungeon, no map | — | — |
| 56 | Bandit's Wood | Kill all enemies and protect at least one captive Orchid. | yes | All three captive Orchids are killed. | yes |
| 57 | Investigation | Kill the Infiltrator. | yes | — | — |
| 58 | Bloody Shack | Kill the Harvester. | yes | — | — |
| 59 | Forgotten Grove | Kill all enemies and loot the treasure tile. | yes | — | — |
| 60 | Alchemy Lab | Loot all treasure tiles, then all characters must escape through the entrance. | yes | The scenario is not complete by the end of the twelfth round. Any character becomes exhausted before all treasure tiles are looted, or while not occupying an entrance hex. | yes (round 12 by scenario rule; exhaustion by goal) |
| 61 | Fading Lighthouse | Loot all treasure tiles. | yes | — | — |
| 62 | Pit of Souls | Kill the Hungry Soul. | yes — the Hungry Soul appears at (c) after ten Living Bones are killed | — | — |
| 63 | Magma Pit | Kill all enemies. | yes | — | — |
| 64 | Underwater Lagoon | Kill all enemies. | yes | — | — |
| 65 | Sulfur Mine | Kill all enemies and loot all treasure tiles. | yes | — | — |
| 66 | Clockwork Cove | Occupy pressure plate (e) — a character occupies it at the end of their turn. | yes | — | — |
| 67 | Arcane Library | Kill the Arcane Golem. | yes — the Stone Golem in the library | — | — |
| 68 | Toxic Moor | Kill all enemies and protect the tree (a). | yes | The tree is destroyed. | yes |
| 69 | Well of the Unfortunate | Bring the doll to the well (a) — complete when the doll is brought to a hex adjacent to the well. | yes — the doll's holder entering a hex beside the well | — | — |
| 70 | Chained Isle | Kill all demons. | yes | — | — |
| 71 | Windswept Highlands | Loot all treasure tiles, then all characters must escape through the exit (a). | yes | Any character becomes exhausted while not occupying an exit hex (a). | yes |
| 72 | Oozing Grove | Destroy all trees and kill all Oozes. | yes | — | — |
| 73 | Rockslide Ridge | Kill all enemies and loot all treasure tiles. | yes | — | — |
| 74 | Merchant Ship | Kill all enemies and keep the ship afloat. | yes | A water tile has to be added but cannot be placed because the B tile is full. | yes (`flood`) |
| 75 | Overgrown Graveyard | Dig up all graves and kill the Bloated Regent. | yes | — | — |
| 76 | Harrower Hive | Reveal all rooms and kill all enemies. | yes — every room, not every wall (`walls`) | — | — |
| 77 | Vault of Secrets | Loot all treasure tiles and kill all City Guards before the alarm is raised. | yes | Any City Guard occupies a pressure plate (a). | yes |
| 78 | Sacrifice Pit | Kill all enemies and stop the sacrifice. | yes | The victim is sacrificed: a Cultist (b) starts its turn adjacent to the altars (d) while the victim is also adjacent to the altars. | yes (`carry`) |
| 79 | Lost Temple | Kill the Betrayer. | yes | Fish is killed. | yes |
| 80 | Vigil Keep | Every character must loot one treasure tile, and then all characters must reach the B tile (escape). | yes | Any character becomes exhausted while not occupying the B tile. | yes |
| 81 | Temple of the Eclipse | Kill the Colorless. | yes | — | — |
| 82 | Burning Mountain | Sacrifice one artifact, or escape with all artifacts. | approximately — with the treasure looted, its holder on the altar hex (Conclusion A's rewards; no item is removed) or everyone at the entrance (Conclusion B's) | — | — |
| 83 | Shadows Within | Kill all enemies. | yes | — | — |
| 84 | Crystalline Cave | Kill all enemies and protect the crystal (a). | yes | The crystal is destroyed. | yes |
| 85 | Sun Temple | Kill all enemies. | yes | — | — |
| 86 | Harried Village | Save seven villagers before five are killed. | yes | Five villagers are killed. | yes |
| 87 | Corrupted Cove | Kill the Giant Ooze. | yes | — | — |
| 88 | Plane of Water | Bring the Lurker King's claw to the crystal (a) — the scenario is complete when the claw is carried to a hex adjacent to the crystal. | yes — the Lurker King dead and the claw's holder ending a turn beside the crystal | — | — |
| 89 | Syndicate Hideout | Kill all enemies. | yes | — | — |
| 90 | Demonic Rift | Close the rift (after Section 1: kill all Living Spirits). | yes — the spirits come when every demon is dead and a character stands in each room | No character is present in the left room at any time; only one character is left unexhausted; after Section 1, either room has no character present at any time. | yes |
| 91 | Wild Melee | Kill all enemies. | yes | — | — |
| 92 | Back Alley Brawl | Kill all non-city enemies. | yes | A City Guard or City Archer is killed. | yes |
| 93 | Sunken Vessel | Kill all enemies. | yes | — | — |
| 94 | Vermling Nest | Kill all enemies and loot the treasure tile. | yes | — | — |
| 95 | Payment Due | Kill the Prime Lieutenant. | yes | — | — |

## Open questions in the book itself

Noted while reading; the notes record what is printed and don't resolve these:

- **#12** — the "1" is printed on the door from the start room, but its section text reads as if
  it were about reaching Jekserah at the far end.
- **#21** — the rules call the altar "a", the map draws it on hex f. (The FAQ settles it: f, and
  it reorders which demon belongs to which letter — see the notes.)
- **#34, #48, #51** — only Boss Special 2 is printed.
- **#81** — no heal amount is printed for Boss Special 2, and it isn't said whether treasure tile
  68 counts as the first or second tile looted.
- **#83** — it isn't said whether Section 2's damage replaces Section 1's altar damage. (The FAQ
  settles it: Section 2's rules replace Section 1's, and that is what the game does.)
- **#87** — the map doesn't show which half of the main room is L2a and which L3b.
