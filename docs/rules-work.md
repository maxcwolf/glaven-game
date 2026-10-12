# The rules work: where it stands and how to go on

The aim is a game that plays Gloomhaven (first edition, base game) exactly as the rulebook, the
official FAQ and the scenario book say. This page is the way in for anyone — a person or a new
session — picking that work up. It says what has been done, which document answers which
question, how a piece of work is done from start to finish, and what to do next.

## Where it stands (2026-10-10)

- Everything is on `main` (merge `236fb2d`, "scenario rules and the rules audit"); the branch
  `feat/scenario-rules` carries on from there. Nothing is local only.
- **The engine** (turns, attacks, movement, monsters, campaign) was audited rule by rule against
  the rulebook and FAQ: about 130 findings, about 115 fixed, each with a test that fails without
  the fix. What is open is listed in `TODO.md`.
- **The scenarios**: the book prints 447 rules for the 95 scenarios. 353 are enforced, 21 partly
  and 73 not yet; 67 scenarios have every printed rule done. Every rule has a row in
  [scenario-book/rules-audit.md](scenario-book/rules-audit.md), re-checked on 2026-10-10.
- As last run by the audit: 1,534 tests pass; the all-scenarios playthrough runs every scenario
  with four seeds without a rule violation; a scripted "veteran" party wins 70 of the 95 scenarios
  (the 25 it never wins are mostly goals it doesn't play for).
- **Not yet seen on a device:** the interface added by the audit (the Solo switch, cards in play
  with "End This Bonus", the damage sheet's "Let <card> take it", the long-rest sheet, the wall
  lines between tiles) and everything scenario rules draw (pressure plates, padlocks, hollow
  inactive monsters, eggs). Reading the golden transcripts' diffs against the rulebook is the
  other check a merge of this size deserves.

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

1. **Tests and checks, before building on top.** A look at the new interface and at what
   scenario rules draw, on a device. (`scripts/mutate.py` has 96 mutations, 36 of them scenario
   rules — `--scenario` — and each is noticed by a test: add one with every new mechanism.)
2. **Scenario rules** — 94 printed rules in 28 scenarios, in this order because each group is one
   mechanism used several times:
   - *a prompt for a choice the player can't make yet*: losing a card to spare a captive or the
     crystal (#44, #84), giving up an action to cleanse a pump, free a captive, loot an adjacent
     tile or dig a grave (#26, #44, #52, #75), choosing which Living Spirit goes (#70). It unlocks
     goals and losses the game can't check today (#26, #44). The damage sheet
     (`DamageChoiceSheet`, `promptDamageMitigation`) is the model; monsters hit captives often,
     so the prompt must be quick to answer;
   - *things that are carried*: #69's doll, #88's claw, #82's artifacts, #81's relics, #58's
     dagger, #54's staff, #95's tokens;
   - *a board that moves as the round ends*: #71's wind, #88's current, #73's boulders, #74's
     rising water;
   - *monsters that don't act as their cards say* (`inactive` and `march` are the mechanisms to
     extend): #71's sleeping drakes, #49's cannon and archer, #78's carriers and their victim;
   - *bosses still played from their stat cards*: #21, #34, #79;
   - *walls and obstacles with hit points*: #76, #95, #52;
   - a few small ones, and #55, a random dungeon with no map, which is a project of its own.
3. **Engine rules** still open, each with an id in the engine audit: element choices, placing
   an area by hand, the rest of negating damage, standees that run out.
4. **Cards** — first the abilities printed under a Move that are never performed (N18: nine
   cards, one fix where steps are built) — then **town and campaign**, and what isn't Gloomhaven.

## History, briefly

- 2026-10-08/09 — the turn engine reworked to the rulebook; the scenario book read into notes;
  objectives, lettered hexes, goals and locked doors written as data.
- 2026-10-09/10 — scenario special rules, batch by batch (rules that wait on the board, standing
  effects, a third side, inactive monsters, boss cycles, marching guards, and so on).
- 2026-10-10 — the engine audit against the rulebook and FAQ, a re-audit of the scenario rules
  already built, walls between map tiles, trap legends, the mutation runner.
