# Changelog

All notable changes to this project will be documented in this file.
Format based on [Conventional Commits](https://www.conventionalcommits.org/).

## [Unreleased]

Since 1.0.0-beta.2: the game plays by the Gloomhaven rulebook, its FAQ and the scenario book —
all 95 scenarios with every printed rule, and the random dungeon deck — and the town and
campaign run between scenarios. 384 commits; a summary by area.

### Features

- Random dungeons: the random dungeon deck's twenty room cards and twenty monster cards, three rooms drawn by the deck's rules with A and B exits, treasure tiles, every room's penalties at a difficulty chosen at setup, and no campaign progress; #55 Foggy Thicket plays as one, completing every printed scenario rule

- **Scenarios as the book prints them**: objectives, escorts and lettered hexes placed from the
  scenario book; each scenario's own goal and losses; locked doors and pressure plates; traps
  that do what each scenario's legend says; standing effects, boss specials and rules that wait
  on the board; things carried (the doll, the claw, the Staff of Xorn, the artifacts); a board
  that moves as the round ends (wind, current, rolling boulders, rising water); monsters that
  don't act as their cards say (sleeping drakes, the siege cannon and its crew, cultists carrying
  their victim); the bosses' own rules (the Infernal Throne's altar, the Elder Drake's perches and
  Zephyrs, the Betrayer's mind control); walls and obstacles with hit points (the Harrower Hive's
  walls, the Noxious Cellar's boulders); and the small ones (#38's Orchid, #68's tree, #82's
  sacrifice and escape).
- **Choices the player makes**: a card lost to spare a captive or the crystal; an action given
  up to free a captive, cleanse a pump or loot a treasure; which Living Spirit goes, whose deck an
  escort draws from, where the wind takes you, which boulder row rolls; the element an
  "any element" bonus takes; where an area attack lies; a discardable card in play lost to
  negate damage; which shield comes first.
- **Classes and cards**: every printed action of a half performed in steps; charged and
  persistent bonuses; the Doomstalker's dooms; the Beast Tyrant's bear, set up beside him, his
  summon and the one who performs his Commands; Feedback Loop's move out and back; Detonation's
  and Flight of Flame's traps; Impending End and Darkened Skies; dozens of items played on the
  board, on the character's turn and on others'.
- **Town and campaign**: a town between scenarios — city and road events, the shop at the
  city's prices, levelling up with a card and a perk, the Enhancer (summon stats included), the
  Sanctuary, battle goals and personal quests, retirement and new classes, the campaign log;
  travelling on to the next scenario without returning to Gloomhaven; collective gold split by
  the players; Envelope X recorded when opened; several campaigns, each saved to its own file;
  table rules a group can play by.
- **Cards you can read**: a setting between the printed card scans and drawn cards that say
  everything a card prints in plain type, and a slider for the size of your cards in hand and in
  play.
- **The board**: a new layout from the mockup; portrait tokens; wall lines between tiles; attack
  previews and the modifier tray; a turn-order rail; learning mode and an illustrated How to Play;
  sound for what happens on the board; VoiceOver throughout and an 11-point text floor.

### Bug Fixes

- **Turn engine and rules**: rounds, conditions, monster decks and turns reworked to the
  rulebook and FAQ; line of sight and range counted round walls; push and pull counted round
  walls; elements infused and consumed by the rules; damage of every source negated by losing
  cards; Warding Strength and Cold Front used only once the player keeps their cards; standees
  that run out set up nearest the character who opened the door; numbered treasure looted once
  per campaign.
- **Maps**: monster places corrected against the scenario book; doors two hexes wide open as
  one; a door seen from its far side is on the map (scenario 12 can be finished).
- **Saves and the app**: saves that keep every field and load older ones; undo that stays in its
  scenario or in town; board hangs found by soak testing fixed; the app fills every iPad.

### Testing

- Headless play through the coordinator (`ScenarioSimulator`): every scenario played to its end
  with four seeds and checked for rule violations, and a ninth-level party that wins 53 to 58 of
  94; 1,726 tests; `scripts/mutate.py`, 432 deliberate rule breaks each caught by a test.

## [1.0.0-beta.2] - 2026-05-29

### Bug Fixes

- **los**: Block line of sight through obstacle interiors by @maxcwolf
- **actions**: Heal clears poison/wound; combined element consume picks one by @maxcwolf
- **scenario**: Exact-count monster spawning fixed at scenario setup by @maxcwolf
- **ai**: Summons and escorts no longer target allied monsters by @maxcwolf
- **ai**: Respect immobilize and difficult-terrain budget in monster movement by @maxcwolf
- **pathfinding**: Account for difficult-terrain cost in findPath and pathCost by @maxcwolf
- **conditions**: Correct afterTurn lifecycle, bane timing, and invisible classification by @maxcwolf

### Documentation

- Update CHANGELOG.md for v1.0.0-beta by @github-actions[bot]


**Full Changelog**: [v1.0.0-beta...v1.0.0-beta.2](https://github.com/maxcwolf/glaven-game/compare/v1.0.0-beta...v1.0.0-beta.2)

## [1.0.0-beta] - 2026-03-20

### Documentation

- Update CHANGELOG.md for v1.0.0-beta by @github-actions[bot]
- Update CHANGELOG.md for v1.0.0-beta by @github-actions[bot]
- Update CHANGELOG.md for v1.0.0-beta by @github-actions[bot]
- Update CHANGELOG.md for v1.0.0-beta by @github-actions[bot]
- Clean up TODO.md after completing all critical rules items by @maxcwolf

### Features

- Implement city/road event card system by @maxcwolf
- Implement personal quest auto-tracking and completion check by @maxcwolf
- Implement battle goal auto-evaluation at scenario end by @maxcwolf
- Render achievement stickers as text badges on GH world map by @maxcwolf
- Add sticker placement celebration screen on scenario victory by @maxcwolf
- Implement visual overlay sticker rendering on world map by @maxcwolf
- Implement 7 Frosthaven condition mechanics by @maxcwolf
- Implement dynamic obstacle/trap/hazard placement mid-scenario by @maxcwolf
- Implement trap condition effects (poison, bear, thorn traps) by @maxcwolf
- Add visual distinction for jump and fly movement by @maxcwolf
- Implement persistent ability card tracking by @maxcwolf
- Invisible figures can be hit by AoE attacks by @maxcwolf
- Apply level-based bonus XP on scenario victory by @maxcwolf
- Enforce max 10 curse/bless cards per attack modifier deck by @maxcwolf
- Implement treasure reward distribution on loot by @maxcwolf
- Implement teleport movement bypassing obstacles and traps by @maxcwolf
- Implement AoE spatial pattern evaluation for monster attacks by @maxcwolf
- Implement end-of-turn auto-loot for characters by @maxcwolf
- Implement escort AI movement/attack and objective count spawning by @maxcwolf
- Implement item spend/consume state during scenarios by @maxcwolf
- Implement hazardous terrain damage by @maxcwolf
- Implement statEffects rules and monster attack push/pull by @maxcwolf
- Enhance scenario rules and victory conditions by @maxcwolf
- Fixes and improvements by @maxcwolf


### New Contributors
- @maxcwolf made their first contribution in #
- @github-actions[bot] made their first contribution in #

