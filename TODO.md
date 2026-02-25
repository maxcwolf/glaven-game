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

Rules audit against the official Gloomhaven rulebook (133 GH scenarios). Organized by gameplay impact.

### Critical — scenarios unplayable without these

- [x] **Traps trigger on enter** — damage applied, trap removed, flying immune
- [x] **Short rest** — recover discards minus one random, optional re-pick for 1 HP
- [x] **Difficulty selector** — Story/Easy/Normal/Hard/Very Hard with floor() level formula
- [x] **Scenario finish conditions** — `finish: "won"/"lost"` enforced via `Scenario.pendingFinish`; checked after every kill and at round end
- [x] **Figure trigger types** — `dead`/`present`/`killed` in `ScenarioFigureRule` evaluated in `shouldTrigger()` (affects ~30 scenarios: escort-loss #56, kill-count win #10, timed victory #27, etc.)
- [x] **`rooms` reveal effect** — rules with a `rooms: [Int]` array now open those rooms immediately (affects #33, #53, #74, #79, #90, #92 + several solo scenarios)
- [x] **`amAdd` figure effect** — adds curse/minus1/bless etc. to all character AM decks at scenario start (20 scenarios: #2, #6, #14, #19, #23, #25, #26, #29, #31 …)
- [x] **`permanentCondition` figure effect** — applies un-removable condition to entities (solo #14 hound→invisible)
- [x] **`dormant`/`activate` figure effects** — toggle `entity.off` for deferred-spawn monsters (#3 Corrupted Laboratory)
- [x] **Objective entity death** — `EntityManager.changeHealth` now sets `dead = true` on `GameObjectiveEntity` at 0 HP
- [x] **`statEffects` rules** — `StatEffectRule`/`StatEffectData` models match actual JSON; `ScenarioRulesManager.applyScenarioStatEffects()` renames monsters, overrides decks, scales HP (Hx2/HxC formulas), adds immunities/stat actions; `MonsterManager.applyScenarioStatEffect()` applies to existing entities and persists for future spawns; snapshot serialization updated for backward compat
- [ ] **Hazardous terrain** — data exists on hexes but entering/passing does not deal damage
- [x] **Push/Pull (monster attacks)** — attack sub-action push/pull (`pendingPush`/`pendingPull` on `MonsterTurnResult`) now executes via `BoardCoordinator.performPushPull()` (async, auto-executes or prompts player for direction); player-turn push/pull already worked
- [ ] **Item use during turns** — items tracked/owned but can't be activated, spent, or refreshed during play
- [ ] **AoE spatial patterns** — multi-target works by proximity but hex-shaped AoE (line, cone, burst) not evaluated
- [ ] **Loot/coin pickup** — no end-of-turn auto-loot, no loot-action board collection; `lootTokens` board state exists but never triggers

### Moderate — affects some scenarios or character builds

- [x] **Rolling modifiers in monster turns** — already handled: `AttackModifierDrawOverlay.drawChain()` auto-chains rolling cards for both player and monster draws
- [ ] **Teleport** — treated as normal movement; should bypass all terrain and obstacles
- [ ] **Jump movement in player UI** — pathfinding correctly treats intermediate hexes as passable, but no visual distinction in player turn UI
- [ ] **Treasure rewards** — treasures can be marked looted but no actual gold/items distributed from `treasures.json` lookup
- [ ] **City/Road events** — not implemented
- [ ] **Battle goals** — `selectedBattleGoal` tracked per character but completion condition never evaluated

### Minor — advanced/Frosthaven-only conditions

- [ ] **Brittle** — no mechanics (should double damage from next source)
- [ ] **Ward** — no mechanics (should halve damage from next source)
- [ ] **Bane** — no mechanics (should add −10 curse to that figure's modifier deck)
- [ ] **Chill** — no mechanics (should reduce movement by 2)
- [ ] **Impair / Rupture / Infect / Plague / Enfeeble** — defined, no effect logic

### Priority order

1. ~~Trap triggering~~ ✅
2. ~~Short rest~~ ✅
3. ~~Difficulty selector~~ ✅
4. ~~Scenario finish conditions~~ ✅
5. ~~Figure triggers (dead/present/killed)~~ ✅
6. ~~rooms-reveal, amAdd, dormant/activate, permanentCondition~~ ✅
7. ~~`statEffects` rules~~ ✅
8. ~~Push/Pull forced movement~~ ✅ (monster attack sub-actions; top-level push on boss cards TBD)
9. ~~Rolling modifiers in monster turns~~ ✅ (already worked via drawChain())
10. Hazardous terrain
11. Item activation during turns
12. Loot/coin pickup
13. AoE spatial patterns
