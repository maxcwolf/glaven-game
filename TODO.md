# GlavenGame — Feature Parity TODO

Tracking features needed for parity with [Gloomhaven Secretariat](https://github.com/Lurkars/gloomhavensecretariat) (Angular), plus native platform improvements.

## Core Gameplay

- [x] Character add/remove
- [x] Monster spawning (from scenario data)
- [x] Initiative input (native keyboard + auto-confirm)
- [x] Round flow (draw → play transitions)
- [x] Conditions (add/remove/expire/turn-based)
- [x] Attack modifier decks (monster, ally, character)
- [x] Loot deck (draw, apply to character)
- [x] Character perks (perk sheet with AM deck modifications)
- [x] Battle goals (draw, track completion)
- [x] Items (shop buy/sell by slot, character inventory)
- [x] Long rest card recovery
- [x] Objective tokens and containers on the board

## Scenario System

- [x] Scenario selection by edition
- [x] Room reveals (section-based)
- [x] Scenario rules display
- [x] Scenario conclusion (success/failure)
- [x] Scenario stats tracking (damage, heals, kills, coins)
- [x] Treasure/goal overlay tracking
- [x] Treasure label system
- [x] Room treasures shown on reveal
- [x] Scenario setup component
- [x] Scenario summary with rewards
- [x] Section dialog
- [x] Random scenario generator
- [x] Random monster card dialog
- [x] Linked scenarios (flow requirements)
- [x] Solo scenarios

## Monster AI

- [x] Ability card rendering (recursive actions, conditions, elements, monsterType sections)
- [x] Standee management (add/remove/toggle type)
- [x] Monster ability deck dialog (view drawn/remaining, shuffle)
- [x] Interactive actions (self-targeting heal, conditions, elements)
- [x] AoE hex grid visualization
- [x] Monster stats dialog with level-specific stats
- [x] Monster stat effect application
- [x] Number picker dialog (quantity selection)
- [ ] Focus / auto-targeting (nearest, path distance)
- [ ] Pathfinding visualization
- [x] Named monster support (bosses with custom decks)

## Character Detail

- [x] Level / XP / Gold display
- [x] Auto level-up (XP changes recalculate level + stats)
- [x] Summons (add from character data, color picker)
- [x] Health bar with +/- controls
- [x] Drag-to-adjust XP and gold
- [x] Item slots (head, body, legs, one-hand, two-hand, small)
- [x] Character sheet dialog (full detailed view with tabs)
- [x] Character full-view mode
- [x] Ability cards dialog with full visualization
- [x] Character ability cards (hand management, lost/discard)
- [x] Enhancement dialog (card enhancements)
- [x] Loot cards dialog (character inventory with sorting)
- [x] Move resources dialog
- [x] Retirement dialog
- [x] Personal quest tracking
- [x] Character identity selection system
- [x] Perk deck editing (add/remove AM cards based on selected perks)

## Campaign & Party

- [x] Party sheet (reputation, prosperity, achievements, completed scenarios, character summary)
- [x] Full campaign mode with scenario progression tracking
- [x] Scenario chart (interactive campaign flow visualization)
- [x] World map (interactive map with building placement, scenario locations)
- [x] Party statistics dialog
- [x] Party treasures dialog
- [x] Party resources dialog
- [x] Prosperity/reputation visual progress indicators
- [x] Character unlocks (envelope system)
- [x] Enhancements (sticker system)
- [x] Retirement tracking
- [x] Campaign log

### Frosthaven Campaign

- [x] Building management UI (garden, stables, alchemist, hall of revelry, barracks)
- [x] Building upgrade dialog
- [x] Week/seasonal advancement dialog
- [x] Morale system
- [x] Soldiers management (barracks)
- [x] Defense rating system
- [x] Pet card management (stables)
- [x] Garden herb management
- [x] Outpost attack effects UI

## Event Cards

- [x] Event card draw component with card flipping animation
- [x] Event card deck visualization
- [x] Event card effects application UI
- [x] Event attack effects
- [x] Event condition effects
- [x] Random scenario selection from events
- [x] Random item selection from events

## Challenge & Trial Systems (FH)

- [x] Challenge deck component
- [x] Challenge deck dialog and fullscreen view
- [x] Challenge card dialog
- [x] Trial card component and dialog
- [x] Favor system UI and tokens

## Attack Modifier

- [x] Additional attack modifier select dialog (extra decks)

## Items & Loot

- [x] Full items dialog (detailed item browser)
- [x] Random item dialog (from loot)
- [x] Item distill dialog (FH alchemy/imbuement)
- [x] Item details dialog

## Managers (Game Logic)

- [x] **ActionsManager** — Character/entity actions, movement areas, ability selections
- [x] **BuildingsManager** — FH buildings, upgrades, resource limits
- [x] **ChallengesManager** — Challenge card decks (FH)
- [x] **EnhancementsManager** — Card enhancements for abilities
- [x] **EventCardManager** — Event card decks and effects
- [x] **ImbuementManager** — Item imbue mechanics (FH)
- [x] **ItemManager** — Item availability based on prosperity, buildings, unlocks
- [x] **ObjectiveManager** — Objective tokens and containers
- [x] **StorageManager** — Backup/restore, data export/import
- [x] **TrialsManager** — Trial cards and favor tokens (FH)

## Data Management

- [x] Named save slots
- [x] Game backup/restore with multiple slots
- [x] Export / import game state (JSON file sharing)
- [x] Edition data URL management (custom editions)
- [x] Custom edition / community content loading
- [ ] iCloud sync between devices

## Undo/Redo

- [x] Undo/redo buttons in header
- [x] Action history visualization dialog
- [x] Step-through past actions

## Settings

- [x] Settings panel (core Angular settings ported)
- [x] Condition application exclusions per condition
- [x] FH-specific toggles (pets, garden, trials, favors, alchemist)
- [x] Animation controls
- [x] Locale/language selection
- [x] Keyboard shortcuts configuration
- [ ] Server ping configuration

## UI/UX

- [x] Tap-to-expand character cards
- [x] Drag XP/gold adjustment
- [x] Keyboard shortcuts (Cmd+Z undo, Cmd+S save)
- [x] Animations (card flip, health changes, condition apply, element glow)
- [x] Sound effects & haptic feedback (toggleable)
- [x] Edition-specific theming (PirataOne/warm for GH, GermaniaOne/cool for FH)
- [x] Parchment background textures
- [x] Monster ability card textures
- [x] AM card images with 3D flip animation
- [x] Health glow, active figure glow, grayscale exhausted
- [x] Full menu system with submenus
- [x] Keyboard shortcuts dialog
- [x] About/info dialog
- [x] Multiple theme support (FH, Modern, BB, Default GH)
- [x] Portrait mode layout adjustment
- [x] Debug mode with debug menu
- [x] Context menu support
- [x] Fullscreen mode for ability cards / AM draws
- [x] Pinch zoom control
- [x] Light theme option
- [x] Responsive layout (sidebar on wide screens)
- [x] Accessibility (VoiceOver, Dynamic Type)

## Standalone Tools

- [x] Attack modifier tool (standalone deck builder)
- [x] Loot deck tool (standalone)
- [x] Initiative tool (standalone tracker)
- [x] Decks viewer tool
- [x] Event cards tool
- [x] Treasures tool
- [x] Random monster cards tool

## Editor Tools

- [x] Edition editor (JSON data editor)
- [x] Character editor
- [x] Deck editor
- [x] Monster editor
- [x] Action editor

## Server / Sync

- [ ] Server/WebSocket sync between devices

## Platform

- [x] macOS 14+
- [x] iPadOS 17+
- [x] App icon and branding
- [x] iPhone layout (compact width adaptations)
- [ ] Unit tests

---

## Missing Gloomhaven Rules

Full rules audit against the official Gloomhaven v1 rulebook and 114 GH scenario JSONs. Last updated 2026-03-13.

### Completed

- [x] **Traps trigger on enter** — damage applied, trap removed, flying immune
- [x] **Short rest** — recover discards minus one random, optional re-pick for 1 HP
- [x] **Difficulty selector** — Story/Easy/Normal/Hard/Very Hard with floor() level formula
- [x] **Scenario finish conditions** — `finish: "won"/"lost"` enforced via `Scenario.pendingFinish`; checked after every kill and at round end
- [x] **Figure trigger types** — `dead`/`present`/`killed` in `ScenarioFigureRule` evaluated in `shouldTrigger()` (affects ~30 scenarios)
- [x] **`rooms` reveal effect** — rules with a `rooms: [Int]` array open those rooms immediately
- [x] **`amAdd` figure effect** — adds curse/minus1/bless etc. to all character AM decks at scenario start (20+ scenarios)
- [x] **`permanentCondition` figure effect** — applies un-removable condition to entities
- [x] **`dormant`/`activate` figure effects** — toggle `entity.off` for deferred-spawn monsters
- [x] **Objective entity death** — `EntityManager.changeHealth` sets `dead = true` on `GameObjectiveEntity` at 0 HP
- [x] **`statEffects` rules** — renames monsters, overrides decks, scales HP (Hx2/HxC), adds immunities/stat actions
- [x] **Hazardous terrain** — `checkForHazard()` deals terrain damage on enter/push/pull/start-of-turn; flying immune
- [x] **Push/Pull (monster attacks)** — attack sub-action push/pull via `performPushPull()`
- [x] **Item use during turns** — `spentItems`/`consumedItems` on `GameCharacter`; long rest clears spent; scenario end clears both
- [x] **Rolling modifiers** — `drawChain()` auto-chains rolling cards for both player and monster draws
- [x] **Advantage/Disadvantage cancellation** — when both are true, neither branch triggers; single card drawn (correct GH behavior)
- [x] **Monster focus tiebreakers** — full chain: shortest path → proximity → initiative in `MonsterAI.findFocus()`
- [x] **Monster trap avoidance** — `Pathfinder` avoids traps first, falls back to allowing traps if no other path
- [x] **Retaliate range check** — `CombatResolver` checks `attackerDefenderDistance <= retaliateRange`
- [x] **Spawn in occupied hex** — `BoardBuilder.findNearestEmpty()` BFS fallback when spawn hex is occupied
- [x] **Scenario links/unlocks** — completing scenarios unlocks new ones via `unlocks` array
- [x] **Global/party achievements** — `checkSingleRequirement()` gates scenario access
- [x] **Escort AI and movement** — `EscortAI.computeTurn()` uses summon-like AI (focus → pathfind → attack) with `EscortTurnController` for animated execution; draws from ally or monster AM deck based on `allyDeck` flag
- [x] **Objective `count` field** — `ObjectiveData.count` parsed from scenario JSON; `ScenarioManager.addObjective()` creates multiple entities per container
- [x] **Character exhaustion from cards** — `advanceToNextCardSelection()` handles forced long rest and exhaustion; 0 HP exhaustion via `EntityManager`
- [x] **Loot/coin pickup** — end-of-turn auto-loot in `finishPlayerTurn()`; movement loot via `checkForLoot()`; loot-action via `collectLootInRange()`; monster death drops via `dropLoot()`
- [x] **AoE spatial patterns** — `AoEResolver` transforms AoE patterns to board coords with rotation, integrated into MonsterAI

### High — affects many scenarios or core character builds

- [x] **Teleport movement** — `beginTeleportAction()` shows all passable hexes within range regardless of obstacles/enemies; `executeTeleport()` places directly without pathfinding and skips trap/hazard triggers
- [x] **Treasure reward distribution** — `TreasureLootSheet.applyTreasureReward()` parses reward strings and distributes gold, XP, items, conditions, damage, heals, party achievements to characters/party
- [ ] **Persistent ability tracking** — `AbilityModel.persistent` flag exists but no ongoing effect system; persistent cards should stay in active area providing continuous bonuses (shield, retaliate, element generation)
- [x] **Curse/Bless deck limits** — `addCurse()`/`addBless()` now enforce max 10 per deck before inserting
- [x] **Ally deck for escorts** — `EscortTurnController` draws from ally or monster AM deck based on `container.useAllyDeck` flag
- [ ] **End-of-scenario bonus XP** — level-based bonus XP (4 + level × 2) tracked in `LevelManager.experience()` but not confirmed to be applied to characters at scenario conclusion

### Moderate — affects some scenarios or character builds

- [ ] **Jump movement visual** — pathfinding correctly treats intermediate hexes as passable, but player turn UI shows no visual distinction between move and jump
- [ ] **Battle goal evaluation** — `selectedBattleGoal` tracked per character but completion conditions never auto-evaluated; should award checkmarks toward perks
- [ ] **City/Road events between scenarios** — event card system exists but no automatic prompting between scenarios for city/road event draws
- [ ] **Icy terrain** — no forced-movement mechanic for icy terrain (continue movement in same direction until hitting obstacle)
- [ ] **Dynamic obstacles** — no mechanism to create or destroy obstacles mid-scenario; `HexCell` overlays are immutable after board build; some scenario rules and abilities create/destroy obstacles
- [ ] **Personal quest auto-completion** — `personalQuest` tracked but completion conditions never auto-evaluated; retirement should trigger automatically when quest is fulfilled
- [ ] **XP from ability cards** — XP is added when `.experience` actions fire, but no "once per card use" enforcement; some ability cards grant XP on use
- [ ] **Summon placement validation** — no enforcement that summons must be placed on an empty hex adjacent to the summoner; `placingSummon` interaction mode exists but valid hex calculation may be incomplete

### Minor — edge cases, advanced mechanics, FH-only conditions

- [ ] **Brittle** (FH) — no mechanics; should double damage from next source
- [ ] **Ward** (FH) — no mechanics; should halve damage from next source, rounded down
- [ ] **Bane** (FH) — no mechanics; should deal 10 damage at end of affected figure's next turn
- [ ] **Chill** (FH) — no mechanics; stackable, should reduce movement by 1 per stack
- [ ] **Impair** (FH) — no mechanics; should cause disadvantage on all attacks
- [ ] **Rupture** (FH) — no mechanics; should cause suffer 1 damage on positive condition gain
- [ ] **Infect** (FH) — no mechanics; should prevent healing (both heal actions and passive regeneration)
- [ ] **Plague** (FH) — no mechanics
- [ ] **Enfeeble** (FH) — no mechanics
- [ ] **Invisible + AoE interaction** — invisible figures excluded from monster focus (correct) but should still be hittable by AoE attacks that include their hex
- [ ] **Multi-hex obstacles** — `HexCell` stores one overlay per hex; no support for obstacles spanning multiple hexes (rare in GH, more common in FH)
- [ ] **Trap condition effects** — some traps apply conditions (poison, wound) in addition to or instead of damage; current trap handling only supports damage via `trapDamage: Int?`
- [ ] **Random dungeon mode** — `randomDungeon` field in scenario rules not handled; procedural dungeon generation not implemented
- [ ] **Pathfinding visualization** — AI pathfinding works but no visual debug overlay for monster movement decisions

### Priority order (remaining)

1. ~~Escort AI and movement~~ ✅
2. ~~Character exhaustion from cards~~ ✅ (already implemented)
3. ~~Objective `count` field~~ ✅
4. ~~Loot/coin pickup~~ ✅
5. ~~AoE spatial patterns~~ ✅
6. ~~Teleport movement~~ ✅
7. ~~Treasure reward distribution~~ ✅
8. Persistent ability tracking (ongoing effects)
9. ~~Curse/Bless deck limits~~ ✅
10. ~~Ally deck for escorts~~ ✅
11. Battle goal evaluation
12. City/Road events
13. Jump visual distinction
14. FH conditions (Brittle, Ward, Bane, Chill, etc.)
