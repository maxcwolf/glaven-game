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

Rules audit against the official Gloomhaven rulebook. Organized by gameplay impact.

### Critical (core gameplay gaps)

- [x] **Traps don't trigger** — Data exists, pathfinding avoids them, but damage is now applied when a figure enters a trap hex. Trap is removed after triggering. Flying figures immune.
- [ ] **Hazardous terrain** — Data defined on hexes but no damage dealt when entered/passed through
- [ ] **Push/Pull** — Action types exist but no forced movement is executed
- [x] **Short rest** — Offered at end of round: recover discards minus one random, optional re-pick for 1 HP
- [ ] **Item use during turns** — Items are tracked/owned but can't be activated, consumed, spent, or refreshed during gameplay
- [ ] **AoE patterns** — No hex-based area-of-effect targeting — multi-target works but not spatial AoE shapes
- [ ] **Loot/coin pickup** — No end-of-turn auto-loot, no loot actions that actually collect coins from the board

### Moderate (affects some scenarios/builds)

- [ ] **Rolling modifiers** — Field exists on cards but not applied in combat resolution (should keep drawing until non-rolling)
- [ ] **Teleport** — Treated identically to normal movement — should bypass all terrain/obstacles
- [ ] **Jump movement distinction** — Intermediate hexes handled in pathfinding but not in player turn UI (same visual as normal move)
- [ ] **Treasure rewards** — Treasures can be marked looted but no actual reward (gold/items) is given
- [ ] **Scenario finish conditions** — `finish: "won"/"lost"` parsed but custom conditions not enforced
- [ ] **City/Road events** — Not implemented
- [ ] **Battle goals** — Data structure exists but not evaluated during play

### Minor (advanced/Frosthaven conditions)

- [ ] **Brittle** — Defined, no mechanics (should double damage from next source)
- [ ] **Ward** — Defined, no mechanics (should halve damage)
- [ ] **Bane** — Defined, no mechanics (should add -10 to next attack modifier)
- [ ] **Impair** — Defined, no mechanics
- [ ] **Chill** — Defined, no mechanics (should reduce movement)
- [ ] **Rupture/Infect/Plague** — Defined, no mechanics
- [ ] **Icy terrain** — Not implemented

### Recommended Priority Order

1. ~~Trap triggering~~ ✅
2. ~~Short rest~~ ✅
3. Push/Pull
4. Item activation
5. Loot/coin pickup
6. AoE patterns
