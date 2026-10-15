# GlavenGame — Testing

Last updated: 2026-10-14

Almost everything is tested headless: the board is played through the same coordinator calls the
interface makes, so a rule test is a short game. What can only be judged by eye is rendered to
images by tests that write a file when asked, and there is a short checklist for a device at the
end.

One `swift test` (or mutation run) at a time per checkout: two at once share the build folder
and fail each other.

## The suite

```sh
swift test                      # 1,741 tests on 2026-10-14, about three minutes after a build
swift test --filter AttackRuleTests
```

- **Rule tests** play through the coordinator on a shared fixture (`Tests/Support/RuleBoard.swift`):
  `AttackRuleTests`, `ConditionRuleTests`, `MovementRuleTests`, `RoundRuleTests`, `LootRuleTests`,
  `RevealRuleTests`, `WallLineTests`, `DoorRuleTests`, `RestRuleTests`… Each rule of the rulebook
  and FAQ ([docs/rulebook/gh-rules.md](docs/rulebook/gh-rules.md)) that the engine audit looked at
  names its test in [docs/audits/2026-10-09-rules-audit.md](docs/audits/2026-10-09-rules-audit.md).
- **Scenario rules** are tested on the real maps (`ScenarioSpecialRuleTests`, `ScenarioGoalTests`,
  `ScenarioLockTests`, `ScenarioPlacementTests`, and one class for each mechanism: `DriftTests`,
  `CarriedThingTests`, `WallTests`, `SwayTests`…). Each printed rule's row in
  [docs/scenario-book/rules-audit.md](docs/scenario-book/rules-audit.md) names its test.
- **Data checks** read every card, monster, scenario and placement: every printed XP and element
  reachable, every trap legend counting its traps, every door on a hex, every written rule naming
  things in its scenario, every scenario reachable in the campaign.
- **Golden transcripts** (`GoldenTurnLogTests`): seeded games of #1, #2 and #4 compared turn by turn
  with hand-checked logs in `Tests/Golden/`. A diff there means turn play changed — check it
  against the rulebook, then re-record:

  ```sh
  GOLDEN_RECORD=1 swift test --filter GoldenTurnLogTests
  ```

## Whole games

`Tests/Support/ScenarioSimulator` plays real scenarios through the coordinator with a
`PlayerPolicy` answering every prompt (`ScriptedPolicy`, `TacticalPolicy`, `VeteranPolicy`). It
checks every attack (range, sight, enemies, visibility), every move (adjacency, walls, obstacles,
doors, end hex) and the board after each step, and `PlayLedger` checks the round as a whole
(initiative order, rests, cards conserved, gold looted).

```sh
# every scenario to a legitimate end, four seeds each (~3 min)
SIM_ALL=1 SIM_SEEDS=4 swift test --filter testAllScenariosPlayToALegitimateEnd

# ninth-level parties that win most scenarios
SIM_ALL=1 swift test --filter testVeteranPartiesWinMostScenarios

# one game written out turn by turn
SIM_SCENARIO=1 SIM_SEED=2 SIM_DIFFICULTY=easy SIM_OUT=/tmp/s1.log swift test --filter testDebugPlaythrough
```

Other switches: `SIM_FROM`/`SIM_TO` (a range of scenarios), `SIM_PARTY`, `SIM_LEVEL`, `SIM_ROUNDS`,
`SIM_VETERAN`, `SIM_WIN`.

## Proving a test: mutations

`scripts/mutate.py` breaks one rule in the game code and runs the tests that should notice; it
restores the file with `git checkout`, so commit first. Every fix adds one (445 on 2026-10-14, each
noticed by a test).

```sh
python3 scripts/mutate.py --list
python3 scripts/mutate.py <name> <TestClass>
python3 scripts/mutate.py --scenario        # the scenario mechanisms only
python3 scripts/mutate.py --all             # every engine mutation
```

## Pictures

Tests that render a screen or a map to a PNG when given a path, for looking at what can't be
asserted:

```sh
BOARD_RENDER=15 BOARD_RENDER_OUT=/tmp/s15.png swift test --filter testRenderScenarioMap
PLACEMENT_SHEET=19 PLACEMENT_SHEET_OUT=/tmp/s19.png swift test --filter testRenderPlacementSheet
INTERFACE_RENDER_OUT=/tmp/ui swift test --filter testRenderTheAuditsInterface
TOWN_RENDER_OUT=/tmp/town swift test --filter testRenderTown
```

The others: `testRenderMainMenu` (`MENU_RENDER_OUT`), `testRenderCampaigns`, `testRenderTableRules`,
`testRenderEvent`, `testRenderEnhancer`, `testRenderQuestPicker`, `testRenderGoalPicker`,
`testRenderCardChoice`, `testRenderLoadout`, `testRenderRestPanel`, `testRenderRewardChoices`,
`testRenderBriefAndResults`, `testRenderFloatingText`, `testRenderElementChoice` — each takes the
`*_RENDER_OUT` variable named in its test.

## CI

`.github/workflows/tests.yml` runs the suite on every push to `main` and every pull request, and
every scenario to the end with four seeds nightly. `.github/workflows/release.yml` builds a
macOS DMG and regenerates `CHANGELOG.md` from the commit messages when a version tag is pushed.

## On a device

The renderer can't play animations, sound or touch. On the iPad simulator
(`xcodegen generate && open GlavenGame.xcodeproj`), a playthrough of a scenario or two should show:

- [ ] The app launches; a new campaign can be started, characters recruited, a scenario chosen
- [ ] Characters are placed on the starting hexes by tapping; cards are chosen and initiative shown
- [ ] Moves, attacks and areas are aimed by tapping hexes and figures; monsters move and attack,
      animated, with their focus explained ("Why?")
- [ ] Loot is picked up at the end of a turn on its hex, or by a Loot action — not in passing
- [ ] An invisible figure is not focused on or targeted by its enemies, area attacks included
- [ ] Doors open rooms, traps spring, the wall lines between tiles are drawn
- [ ] Resting, losing a card to negate damage, exhaustion and the end of the scenario
- [ ] Back in town (or travelling on): events, shop, level up, perks, enhancing
- [ ] Sound plays and VoiceOver reads the board

A recorded campaign to continue from is in
[docs/playthroughs/2026-10-09-ipad/](docs/playthroughs/2026-10-09-ipad/README.md).
