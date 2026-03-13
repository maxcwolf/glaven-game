# GlavenGame — Manual Test Plan

Last updated: 2026-03-13

## Prerequisites

- Build and run via `xcodegen generate && open GlavenGame.xcodeproj` or `swift build`
- Start a new game with the **Gloomhaven** edition

## Automated Tests

Run the automated test suite:
```sh
swift test
```

35 tests covering: AoE resolution, curse/bless limits, escort AI, objective count parsing, loot board state, teleport vs pathfinding, treasure reward parsing, bonus XP, entity conditions, hex coordinate math, invisible+AoE interaction.

---

## 1. Escort AI and Movement

**Scenario:** #19 (Forgotten Crypt)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Select Scenario #19 | Loads with Hail escort objective |
| 2 | Add 2 characters, place them, start scenario | Hail appears on board with health bar |
| 3 | Set initiatives and advance to execution phase | Turn order includes "Hail" at initiative 99 |
| 4 | Wait for Hail's turn | Hail moves toward nearest monster (Move 2) — animated |
| 5 | Observe Hail has no attack | Hail should only move (scenario 19 escort has move only) |

**Scenario:** #44 (Tribal Assault)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Select Scenario #44, start | Redthorn escort appears at initiative 1 |
| 2 | Wait for Redthorn's turn | Redthorn moves (Move 3) AND attacks (Attack 3, Range 3) |
| 3 | Verify AM deck used | Redthorn uses ally AM deck (not monster deck) |
| 4 | Apply Stun to Redthorn via context menu | Next turn: Redthorn skips ("Stunned — skipped" in log) |
| 5 | Apply Disarm to Redthorn | Next turn: Redthorn moves but does not attack |

## 2. Objective Count

**Scenario:** #56 (Bandit's Wood)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Select Scenario #56, reveal room with escorts | **3** Captive Orchid escort tokens appear (not 1) |
| 2 | Check each token | All three have independent health bars |
| 3 | Kill one Captive Orchid | Other two remain alive and functional |

**Scenario:** #86 (Sunken Vessel)

| Step | Action | Expected |
|------|--------|----------|
| 1 | Select Scenario #86, reveal escort room | **11** Villager escort tokens appear |

## 3. End-of-Turn Auto-Loot

| Step | Action | Expected |
|------|--------|----------|
| 1 | Start any scenario, kill a monster | Loot token appears on the hex where monster died |
| 2 | Move a character onto that hex | Loot auto-collected (gold notification, log entry) |
| 3 | Kill a monster on a hex NOT adjacent to any character | Loot stays on board |
| 4 | End a character's turn while standing on a loot token | Loot on character's current hex auto-collected |
| 5 | Use "Loot 1" action near multiple loot tokens | Tokens within range 1 collected |

## 4. AoE Spatial Patterns

| Step | Action | Expected |
|------|--------|----------|
| 1 | Start a scenario with Flame Demons or Cultists | Monsters with AoE ability cards |
| 2 | Place 2+ characters adjacent to each other, near a monster | Within AoE range |
| 3 | Wait for monster AoE ability card | Monster attacks multiple characters in the AoE pattern |
| 4 | Check combat log | Shows multiple targets hit by single attack |
| 5 | Place characters far apart (outside AoE shape) | AoE only hits those in the pattern hexes |

## 5. Teleport Movement

| Step | Action | Expected |
|------|--------|----------|
| 1 | Use a character with teleport ability | Teleport action available |
| 2 | Activate teleport with obstacles between you and destination | Valid hexes shown in **purple** (not cyan) |
| 3 | Confirm hex on other side of wall is selectable | Hex highlighted despite obstacle blocking path |
| 4 | Select that hex | Character teleports directly (instant placement) |
| 5 | Teleport over a trap | Character does NOT take trap damage |
| 6 | Teleport over hazardous terrain | Character does NOT take hazard damage |
| 7 | Verify occupied hexes not selectable | Can't teleport onto another figure |

## 6. Treasure Reward Distribution

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open Treasures dialog during a scenario | Shows available treasures with reward descriptions |
| 2 | Click "Loot" on a gold treasure (e.g., "Gain 15 gold") | Active character's gold increases by 15 |
| 3 | Click "Loot" on a damage treasure (e.g., "Suffer 5 damage") | Active character's health decreases by 5 |
| 4 | Click "Loot" on an item treasure | Item unlocked in party inventory |
| 5 | Click "Loot" on XP treasure | Character's XP increases |
| 6 | Verify treasure marked as "Looted" after collection | Shows green checkmark, can't loot again |

## 7. Curse/Bless Deck Limits

| Step | Action | Expected |
|------|--------|----------|
| 1 | Open AM deck dialog for monster deck | Shows current deck contents |
| 2 | Add 10 Bless cards | All 10 added to deck |
| 3 | Try to add an 11th Bless card | Card NOT added (stays at 10 bless) |
| 4 | Add 10 Curse cards | All 10 added |
| 5 | Try to add an 11th Curse card | Card NOT added (stays at 10 curse) |
| 6 | Repeat for a character's personal AM deck | Same 10-card cap applies |

## 8. End-of-Scenario Bonus XP

| Step | Action | Expected |
|------|--------|----------|
| 1 | Note all character XP values before completing scenario | Record starting XP |
| 2 | Note the scenario level (shown in footer) | Determines bonus amount |
| 3 | Complete a scenario successfully | Victory dialog appears |
| 4 | Check character XP | Increased by (4 + scenario_level × 2) + any scenario-specific rewards |
| 5 | Level 0 scenario: bonus = **4 XP** | Verify exact amount |
| 6 | Level 3 scenario: bonus = **10 XP** | Verify exact amount |
| 7 | Exhaust a character, then win | Exhausted character does NOT receive bonus XP |

## 9. Invisible + AoE Interaction

| Step | Action | Expected |
|------|--------|----------|
| 1 | Apply Invisible condition to a character (context menu) | Character becomes invisible |
| 2 | Place invisible character adjacent to a visible character, near a monster | Both near AoE source |
| 3 | Monster turn with AoE attack | AoE hits both characters — invisible one takes damage too |
| 4 | Monster turn with single-target attack | Invisible character is NOT targeted |
| 5 | Monster focus selection | Should skip invisible character, focus visible one |

## 10. Character Exhaustion from Cards

| Step | Action | Expected |
|------|--------|----------|
| 1 | Play cards until hand has 1 card and discard has 1 card | Near exhaustion |
| 2 | Advance to card selection phase | Character auto-exhausted, removed from board |
| 3 | Play until hand has 1 card but discard has 3+ cards | Near forced rest |
| 4 | Advance to card selection | Character enters forced long rest (initiative 99) |
| 5 | Exhaust all characters | Scenario defeat triggered |

---

## Quick Smoke Test Checklist

- [ ] App launches without crash
- [ ] Can create a new game with Gloomhaven edition
- [ ] Can add characters and start a scenario
- [ ] Character placement on starting hexes works
- [ ] Monster turns execute with animated movement and attacks
- [ ] Escort turns animate (move/attack) on escort scenarios
- [ ] Loot tokens appear when monsters die
- [ ] Loot auto-collected on move and end-of-turn
- [ ] Teleport shows purple highlights through obstacles
- [ ] Treasures distribute actual rewards on loot
- [ ] Curse/Bless decks cap at 10 each
- [ ] Bonus XP awarded on scenario victory
- [ ] AoE attacks hit multiple targets spatially
- [ ] Invisible figures excluded from focus but hit by AoE
- [ ] Card exhaustion triggers correctly
