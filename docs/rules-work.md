# The rules work: where it stands and how to go on

The aim is a game that plays Gloomhaven (first edition, base game) exactly as the rulebook, the
official FAQ and the scenario book say. This page is the way in for anyone — a person or a new
session — picking that work up. It says what has been done, which document answers which
question, how a piece of work is done from start to finish, and what to do next.

## Where it stands (2026-10-14)

- `main` has everything up to merge `53c1ab1` (the cards); `feat/cards-4` adds town and campaign
  and is pushed, not merged ("Work in progress" below). Nothing is local only.
- **The engine** (turns, attacks, movement, monsters, campaign) was audited rule by rule against
  the rulebook and FAQ: about 130 findings, all fixed but a few latent cases no Gloomhaven card
  triggers, each fix with a test that fails without it
  ([audits/2026-10-09-rules-audit.md](audits/2026-10-09-rules-audit.md)).
- **The scenarios**: the book prints 447 rules for the 95 scenarios, and all 447 are enforced
  (2026-10-14; at the audit of 2026-10-10 it was 353, 21 partly and 73 not yet). The last was
  #55, a random dungeon, done with the random dungeon mode ([random-dungeons.md](random-dungeons.md)). Every rule has a row in
  [scenario-book/rules-audit.md](scenario-book/rules-audit.md).
- Last verified 2026-10-14 (card style and size added): 1,741 tests pass; the all-scenarios
  playthrough runs every scenario, #55 and a Random Dungeon with four seeds (384 runs) without a
  rule violation; the scripted "veteran" parties win 53 and
  58 of the 94 playable scenarios (those they never win are mostly goals they don't play for);
  `scripts/mutate.py`'s 445 mutations are each noticed by a test.
- **Not yet seen on a device:** the interface added by the audit (the Solo switch, cards in play
  with "End This Bonus", the damage sheet's "Let <card> take it", the long-rest sheet, the wall
  lines between tiles) and everything scenario rules draw (pressure plates, padlocks, hollow
  inactive monsters, eggs). Reading the golden transcripts' diffs against the rulebook is the
  other check a merge of this size deserves.

### Work in progress (2026-10-14)

`main` has everything up to merge `53c1ab1` (the cards). The work since — town and campaign —
is on `feat/cards-4`, not merged (merging is the owner's call).
The branches:

- **`feat/scenario-rules-3`** (2026-10-12): tests for the three rules no test caught; mutations
  for the audit fixes that were only read and for the scenario mechanisms; the golden
  transcripts read against the rules; fixes N17 (Scroll of Recall's Pull), N13 (Unending Chant;
  charges marked only when an action is performed), N19 (#36 hanging at the start of round 9 —
  a hang that is on `main`) and N18 (an ability printed under a Move was never performed: nine
  cards).
- **`feat/cards-4`** (2026-10-13), which starts from the head of `feat/scenario-rules-3` and so
  holds all of the above too. It was made in a worktree (`.claude/worktrees/cards-4`) while a
  second session had the main checkout. It adds: Singing Arrow's Curse over its area; the
  play ledger no longer miscounting #9's Scouts (N12); the audit's new screens rendered and
  looked at (N16) with the cards in play made finger-sized; a door two hexes wide opening as
  one (N21). `scripts/mutate.py` has 445 mutations, each noticed by a test. Group 2 is begun: a card lost
  from any hand spares the crystal (#84) or a captive (#44) — `saves`, `SaveChoiceSheet` — and a
  character beside a captive gives up an action to free it (`forgo`), with #44's loss switched on.

To pick it up, work on `feat/cards-4` (or merge it into `feat/scenario-rules-3` first — it is a
fast-forward):

1. **Verified** at the head of `feat/cards-4` on 2026-10-14: `swift test` 1,741 tests, none
   failing; the four-seed all-scenarios playthrough (384 runs) without a violation; the veteran
   playthrough passing (53 and 58 of 94 won, as before). `main` has the branch up to merge
   `77bb551`; the card style setting and card size slider came after and are on the branch.
2. **Next**, from `TODO.md` → "Open, in order": group 1 is done but for a glance at two things
   on the iPad (the Solo switch as a switch; the scrolling card lists in the damage and rest
   sheets) and the drawings that need a game in progress (#46's eggs, #48's Dark Rider, the
   bosses' jumps). Then the rest of group 2. Built so far: the card that spares an objective
   (`saves`: #84, #44) and the action given up to free a captive (`forgo`: #44, with its loss).
   The same rule cleanses #26's pumps (`does`, `bottom`; goal `freed`) and loots #52's treasure
   (`treasure`); #75's graves are dug with movement (`dig`). The players choose which
   Living Spirit goes (#70) and whose deck Redthorn and the Orchids draw from (#44, #56): the
   first group of scenario rules, "a choice the player couldn't make", is done. The second,
   things that are carried, is done too (`carried`, `BoardCoordinator+Carried`: #69, #88, #58,
   #82, #81, #54; `tokens` for #95's numbered tokens, its locked door, its demons and — because
   three tokens lie behind them — its boulders with hit points). The third, a board that moves
   as the round ends, is done as well: `drift` (#71's wind, #88's current), `rolling` (#73's
   boulders) and `flood` (#74's rising water), each run from `proceedAfterShortRests` before the
   round's other end-of-round rules, with two new prompts — `chooseHex` (tap one of a few hexes)
   and `chooseOption` (an answer in words). The fourth, monsters that don't act as their cards
   say, is done too: `asleep` (#71's drakes), `barred` (#67's golem, #73's Inox), `battery` (#49's
   Siege Cannon and its crew) and `carry` (#78's Cultists and their victim). The fifth, the
   bosses, is done but for one clause: `throne` (#21's altar that is the Prime Demon's hit points
   and jumps), `perch` (#34's Elder Drake on three hexes — `BoardState.bodies` — its flight and
   its Zephyrs) and `sway` (#79's Betrayer: the party driven off, drawn in, and one of them
   mind controlled — of the top action played for them only the attacks are made). The sixth,
   walls and obstacles with hit points, is done: `walls` (#76's 23 walls, each an objective on a
   shut `breakable-wall` connector; the Stun, the rooms behind, summons leaving them alone) with
   `discardAtStart` (its three cards, `StartDiscardPicker`), and `indestructible.solid` with
   `startAmongMonsters` (#52's boulders that nothing jumps, flies over or sees past — `HexCell.solid`
   — and its starting sections). The seventh, the small ones, is done too: `seeks` (#38's Orchid
   heads for the shaman on the D tile), #68's tree only healed (`alliesInRange(healing:)`) and
   poisoned summons going round its water (`BoardState.avoidedAsTraps`), #79's mind-controlled
   character playing the whole top action and the Betrayer's specials needing sight (FAQ), and
   #82's last two pieces (`Goal.sacrifices`: the artifact given up on the altar; `Exit.all`).
   Every printed rule of 94 of the 95 scenarios is done; the one left is #55, a random dungeon
   with no map, which needs the random dungeon mode built first (`TODO.md`). Group 3, the engine
   rules the audit left open, is done too (2026-10-14): element choices, the player placing an
   area, the rest of negating damage, standees that run out, push and pull around walls, treasure
   on a replay, and moves made in legs (Feedback Loop). Group 4, Cards, is done too
   (2026-10-14): the Beast Tyrant's bear (N20) — set up beside him, his summon, the performer of
   his Commands — with Earthen Spikes' and Patch Fur's bonuses for all summoned allies, an
   attack's "Strengthen self" for its attacker, Frightening Curse's controlled Move 1, Detonation's
   and Flight of Flame's traps, Impending End and Darkened Skies. Left under Cards: three Beast
   Tyrant cards with no data and his text bonuses about the bear. Group 5, town and campaign, is
   done too (2026-10-14): travelling on without returning to Gloomhaven (F19, N6), collective
   gold split by the players (F20), summon stat enhancements (F8), Envelope X recorded. Left:
   single-target condition lines at the Enhancer, and the question N3. Group 6 is begun
   (2026-10-14) with the random dungeon mode, the one piece of it that is Gloomhaven's: the
   twenty room cards written from the cards and checked, the draw, the map, the exits, the
   treasures, most of the penalties, and #55 playable — [random-dungeons.md](random-dungeons.md)
   says what is left. The Frosthaven items (icy terrain, Plague, Enfeeble) are parked by the
   owner's choice.
3. Merging to `main` (`git merge --no-ff -m "merge: …"`, then push) is done when the owner asks.

## Which document answers what

| Question | Document | Kept current by |
|---|---|---|
| What is there to do, in what order? | `TODO.md` → "Missing Gloomhaven Rules" → "Open, in order" | ticking items as they are done, adding gaps as they are found |
| What does the rulebook say? | [rulebook/gh-rules.md](rulebook/gh-rules.md): every rule as a numbered line (SET, RND, TRN, MOV, LOS, ATK, CND, ELE, ACT, MON, END, CMP) with the FAQ's rulings worked in | adding a ruling when the FAQ is consulted |
| Where did the engine break a rule, and is it fixed? | [audits/2026-10-09-rules-audit.md](audits/2026-10-09-rules-audit.md): one row a finding, with the fix and the test that pins it | marking a row fixed, with its test's name |
| What does a scenario print? | [scenario-book/gh-scenario-rules.md](scenario-book/gh-scenario-rules.md): goal, losses, objectives, sections, special rules, boss specials and map letters of all 95, with the book's page | correcting a note when the book or FAQ shows it wrong |
| Does the game enforce that scenario rule? | [scenario-book/rules-audit.md](scenario-book/rules-audit.md): one row a printed rule — done, partial or missing, and where | rewriting the row when the rule is built |
| How is scenario data written, and what does each key do? | [scenario-book/README.md](scenario-book/README.md): every key of `placements/gh.json` and `gh-traps.json`, how to read a hex off the book's map, what is written for each scenario | adding a key's paragraph with the key |
| What needs the owner's decision? | [open-questions.md](open-questions.md) | — |
| How does the code hang together? | `CLAUDE.md` (project guide, kept locally — it is not in the repository) | — |

Two audits, two jobs: the one in `audits/` is about the engine and is a list of *findings*; the
one in `scenario-book/` is a *status table* of every printed scenario rule. A scenario rule that
was found enforced wrongly has a row in both (ids S1…, S2… in the engine audit).

## How a piece of work is done

1. **Pick it** from "Open, in order" in `TODO.md`. Read the rule itself, not a memory of it: the
   line in `gh-rules.md` and the FAQ for an engine rule; the scenario's notes and its page of the
   book for a scenario rule; the card scan (`GlavenGame/Resources/CardImages/gh/<cardId>.jpeg`)
   and `EditionData/gh/label/en.json` for a card's text.
2. **Build it.** Engine rules live in `GlavenGame/Board` and `GlavenGame/Engine`. Scenario rules
   are *data first*: a key in `GlavenGame/Resources/ScenarioMaps/placements/gh.json`, enforced
   by a small extension of the coordinator (`BoardCoordinator+Goals`, `+Locks`, `+Effects`,
   `+Bosses`, `+March`, `+Spawning`) or by a rule in the scenario-data format that
   `ScenarioRulesManager` evaluates. Look for an existing key that already says it before
   inventing one — the README lists them all — and prefer a mechanism a second scenario can use
   to one written for a single scenario.
3. **Test it on the real board.** A scenario rule is tested on its own scenario
   (`ScenarioSimulator(scenario: "77", …)`, as in `Tests/ScenarioSpecialRuleTests.swift`); an
   engine rule on the shared fixture (`Tests/Support/RuleBoard.swift`). The test must go through
   the calls real play makes.
4. **Prove the test.** Take the fix out and see the test fail: `git stash push <file>`, run the
   test, `git stash pop` (never `git checkout` a file with uncommitted work). For standing
   rules `scripts/mutate.py <name>` does it: it breaks one rule, runs the rule tests and says
   which noticed. A fix whose test doesn't fail without it isn't done. A mutation nothing
   notices has three possible causes, all met in practice: the test's set-up makes the rule
   moot (a token out of sight that is also out of range), the mutated line is one of several
   copies of the rule, or the line does nothing another line doesn't — then the code goes.
5. **Verify the batch:**
   ```sh
   swift test
   SIM_ALL=1 SIM_SEEDS=4 swift test --filter testAllScenariosPlayToALegitimateEnd
   SIM_ALL=1 swift test --filter testVeteranPartiesWinMostScenarios
   GOLDEN_RECORD=1 swift test --filter GoldenTurnLogTests   # then read the diff against the rules
   ```
   One checkout, one run at a time: a second `swift test` (or a mutation run) in the same folder
   builds against whatever the first has changed.
6. **Write it down**, in the same commit: the row in the audit it belongs to (status, where, the
   test's name); for scenario data, the key's paragraph and the scenario's lines in the README;
   the item in `TODO.md`; a line in the scenario's `notes` if players need to know the rule (the
   scenario brief shows them).
7. **Commit** with a lowercase Conventional Commits subject (`fix: …`, `feat: …`), no
   attribution lines.

Conventions that tests enforce: adjacency and range are asked of the board
(`boardState.areAdjacent`, `neighbors(of:)`, `range(from:to:)`, `isWithin`), never of the bare
hex grid, because the edge between two map tiles is a wall (`BoardGeometryGuardTests`); every
shuffle and draw goes through `GameRandom.shared`; figures and hexes are visited in `PieceID` /
`HexCoord` order.

### Reading the scenario book

The book is the only source for where an objective or a lettered hex is, what the goal is, and
which monsters stand where for how many characters. It isn't in the repository (319 MB); it can
be read at <https://kirsanova.relfbo.qapubl.club/view/145446/2/>, and with a local copy of the
PDF:

```sh
# the page as a picture (the notes give each scenario's page); scale 2 reads a page
swift scripts/scenario-book/page.swift "Scenario Book.pdf" 98 2.1 /tmp/p98.png
# a part of it, large enough to read a monster token's border (fractions of the page, top-left origin)
swift scripts/scenario-book/page.swift "Scenario Book.pdf" 55 4.5 /tmp/tomb.png 0.37 0.48 0.74 0.71
# the same map as the game has it, every hex labelled with its tile and tile coordinates
PLACEMENT_SHEET=77 PLACEMENT_SHEET_OUT=/tmp/s77.png swift test --filter testRenderPlacementSheet
# write what was read (keeps the file's layout); then run the placement tests
scripts/scenario-book/place.py 77 '{"n1b": {"markers": {"a": [[3, 6], [4, 6]]}}, "plates": ["a"]}'
swift test --filter 'ScenarioPlacementTests|ScenarioSpecialRuleTests'
```

Put the two pictures side by side and read coordinates off the sheet. The book often prints a
map turned against the game's (`PLACEMENT_SHEET_TURN=90`, 180 or 270 turns the sheet): find two
things both show — a monster, a treasure tile, an obstacle — and work out the turn from them
before reading a letter. A monster token's border says who is set up: the upper-left segment is
for two characters, the upper-right for three, the bottom for four; white is normal, yellow elite,
black none. The text of the PDF comes out with its columns interleaved
(`swift scripts/scenario-book/text.swift "Scenario Book.pdf" /tmp/book` writes a file a page), so
use it to find a rule and the page image to read it.

## What to do next

The task list is `TODO.md` → "Missing Gloomhaven Rules" → "Open, in order"; it is grouped and
ordered like this:

1. **Tests and checks, before building on top.** Done but for a glance on the iPad at what the
   off-screen renderer can't draw. (`scripts/mutate.py` has 445 mutations, 280 of them scenario
   rules — `--scenario` — and each is noticed by a test: add one with every new mechanism.)
2. **Scenario rules** (done 2026-10-14 but for #55) — 94 printed rules in 28 scenarios were
   open on 2026-10-12, done in this order because each group is one mechanism used several times:
   - *a prompt for a choice the player can't make yet* (done 2026-10-13): losing a card to spare a captive or the
     crystal (#44, #84), giving up an action to cleanse a pump, free a captive, loot an adjacent
     tile or dig a grave (#26, #44, #52, #75), choosing which Living Spirit goes (#70). It unlocks
     goals and losses the game can't check today (#26, #44). The damage sheet
     (`DamageChoiceSheet`, `promptDamageMitigation`) is the model; monsters hit captives often,
     so the prompt must be quick to answer;
   - *things that are carried* (done 2026-10-13): #69's doll, #88's claw, #82's artifacts, #81's
     relics, #58's dagger, #54's staff, #95's tokens;
   - *a board that moves as the round ends* (done 2026-10-13): #71's wind, #88's current, #73's
     boulders, #74's rising water;
   - *monsters that don't act as their cards say* (done 2026-10-13): #71's sleeping drakes, #49's
     cannon and archer, #78's carriers and their victim, #67's and #73's barred doors;
   - *bosses still played from their stat cards* (done 2026-10-13; #79's mind-controlled top
     action is attacks only): #21, #34, #79;
   - *walls and obstacles with hit points* (done 2026-10-13): #76's walls and discarded cards,
     #52's boulders and starting sections, #95's boulders;
   - *the small ones* (done 2026-10-14): #38's Orchid, #68's tree and poisoned summons, #79's
     mind control, #82's sacrifice and escape;
   - #55, a random dungeon with no map, which is a project of its own.
3. **Engine rules** (done 2026-10-14, each with its id in the engine audit): element choices
   (B13, N7: "any element" picked, Air kept, Crackling Air paid as played), placing an area
   (A10), the rest of negating damage (N8 a card in play lost, N9 Warding Strength and Cold
   Front after the choice, N10 the shield order), standees that run out (N11), push and pull
   around walls (A12), treasure on a replay (C11), and a move in legs for Feedback Loop. Left: the
   latent cases no Gloomhaven card triggers (`TODO.md`).
4. **Cards** and **town and campaign** (done 2026-10-14: the Beast Tyrant's bear, travelling on,
   collective gold, summon enhancements, Envelope X; left: three Beast Tyrant cards the data
   leaves empty, his text bonuses about the bear, single-target condition enhancements, N3).
5. **What isn't Gloomhaven, and tools** — under way. The random dungeon mode first (playable;
   [random-dungeons.md](random-dungeons.md) lists what is left), then multi-hex obstacles as one
   piece and a debug overlay for monster movement. The Frosthaven mechanics (icy terrain,
   Plague and Enfeeble) wait until Frosthaven can be played (the owner's choice, 2026-10-14).

## History, briefly

- 2026-10-08/09 — the turn engine reworked to the rulebook; the scenario book read into notes;
  objectives, lettered hexes, goals and locked doors written as data.
- 2026-10-09/10 — scenario special rules, batch by batch (rules that wait on the board, standing
  effects, a third side, inactive monsters, boss cycles, marching guards, and so on).
- 2026-10-10 — the engine audit against the rulebook and FAQ, a re-audit of the scenario rules
  already built, walls between map tiles, trap legends, the mutation runner.
- 2026-10-12 — the three rules no test caught, mutations for every scenario mechanism, the golden
  transcripts read against the rulebook; Scroll of Recall, Unending Chant, #36's hang.
- 2026-10-13 — the scenario rules that were left, group by group: choices the player makes,
  things that are carried, a board that moves, monsters that don't act as their cards say,
  bosses, walls with hit points.
- 2026-10-14 — the small scenario rules, the engine rules the audit left open, the Beast
  Tyrant's bear and the other cards, town and campaign (travelling on, collective gold, summon
  enhancements), and the changelog.
