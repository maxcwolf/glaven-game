# iPad campaign playthrough — 2026-10-09

A fresh Gloomhaven campaign on Easy (scenario level 0), learning mode on, played entirely through the
iPad simulator UI. Party: Cragheart (Seeker of Xorn) and Spellweaver (Take Back the Trees).

`campaign-after-scenario-2.json` is the save at the end (in town, after #2). To continue, copy it into
the app container's `Documents/Campaigns/` and load it from Campaigns:

```sh
cp docs/playthroughs/2026-10-09-ipad/campaign-after-scenario-2.json \
  "$(xcrun simctl get_app_container booted com.glaven.GlavenGame data)/Documents/Campaigns/2129A36B-69D5-4C69-916A-41EE56E00352.json"
```

## What was played

1. Town: recruit, personal quests, starting items (Leather Armor, Iron Helmet, Minor Stamina Potion).
2. Road event 24 (A), battle goals (Opener, Scrambler).
3. **#1 Black Barrow — won in 13 rounds.** Doors and rooms, traps, loot, short and long rests,
   lose-a-card to negate damage, Leather Armor, Minor Stamina Potion, elements, persistent/loss cards,
   Reviving Ether. Victory screen: XP, +4 success bonus, Opener met, First Steps, #2 unlocked.
4. Town: city event 12 (B), Sanctuary donation (blessings), shop (Iron Helmet).
5. Road event 21 (A: Wound + 3 damage), battle goals (Aggressor, Diehard).
6. **#2 Barrow Lair — lost on purpose in round 2.** Exhaustion of each character, defeat screen,
   back to town with no rewards, blessings gone from the deck, failed scenario logged, #2 still open.

## What worked

Monster focus and "Why?", initiative order, ranged disadvantage when adjacent, shields, Retaliate,
Strengthen/advantage, Immobilize, Poison removed by a heal, Wound at turn start, traps on entering,
loot and gold at level 0, rest flows (short-rest re-pick, long-rest heal and choice), negating damage
by losing a hand card or two discards, exhaustion warnings, spent items refreshed by a long rest,
victory and defeat screens, city/road event effects (gold, reputation, checkmarks, wound, damage),
sanctuary blessings, buying in the shop.

## Findings

Severity: **bug** (wrong result), **rules** (diverges from the rulebook), **ux**, **style**.

| # | Area | Severity | Finding |
|---|------|----------|---------|
| 1 | cards | bug | Skipping a persistent half (Backup Ammunition's "Special Effect") still puts the card in the active area; it later gave +1 Target. |
| 2 | cards | bug | Skipping a loss half (Crater's bottom) still sends the card to the lost pile (Frost Armor's skipped loss half correctly went to discard). |
| 3 | events | bug | "Discard 2 cards" (road event 24 A) shows no cards to pick before the first scenario (no hand yet), Accept is enabled, nothing is discarded, yet the result says it was. |
| 4 | campaign | bug | Event-unlocked scenarios (`manualScenarios`, #82 Burning Mountain) never appear in the town list. |
| 5 | campaign | bug | A won #1 Black Barrow is still listed as open ("2 OPEN"). |
| 6 | board | bug | The last-draw panel from scenario 1 is still shown when scenario 2 begins. |
| 7 | rest | rules | After "Take 1 Damage to Re-pick" the re-pick is offered again; it's once per rest. |
| 8 | rules | rules | Element consumption is automatic: Mana Bolt took the Earth the Cragheart infused for Earthen Clod. Consuming should be the player's choice. |
| 9 | rules | rules | A move with a rider (Rumbling Advance: adjacent figures suffer 1) can't be "Move 0" to keep the rider. |
| 10 | save | bug? | Recruiting and choosing quests doesn't save a new campaign; the file isn't written during a scenario either. |
| 11 | rules | verify | #2's "each character adds 3 Curses" start rule — not confirmed in play; needs a test. |
| 12 | learning | ux | The first attack shows four first-time tips back to back, and one swallowed the tap on the target. |
| 13 | learning | ux | The Resting tip appears after the short-rest prompt is answered. |
| 14 | board | ux | Rest prompts still appear after the last enemy dies, before victory. |
| 15 | board | ux | Card halves whose text is performed by the board read "Special Effect" (Reviving Ether, Backup Ammunition, Crater bottom). |
| 16 | board | ux | Tapping a hex whose path crosses a closed door opens it without warning. |
| 17 | log | ux | Healing a poisoned figure logs "heals Cragheart for 0" instead of "removes Poison". |
| 18 | town | ux | The header switches to "In town" (and shows Prosperity etc.) as soon as the first recruit joins. |
| 19 | town | ux | The Easy hint repeats itself: "Scenario level 0 · Scenario level −1 (min 0)." |
| 20 | quests | ux | Quests that open an envelope (513, 526) show no reward line. |
| 21 | shop | ux | Item tiles don't mention their −1 modifier cards (Hide Armor). |
| 22 | events | style | The Road Event header icon renders as "/ : \" text. |
| 23 | rest | style | Short Rest and Long Rest dialogs are still in the old style. |
| 24 | events | style | The gold-sharing dialog is still in the old style. |
| 25 | quests | feature | Hold "Unlocks the Plagueherald/Doomstalker" in the quest picker to learn about the class. |
| 26 | settings | feature | A game option to go back to the start of the previous turn. |
