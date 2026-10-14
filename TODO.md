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
- [x] Focus / auto-targeting (nearest, path distance)
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

- [x] Campaigns: each saved to its own file (Documents/Campaigns on iPad, in the Files app); New Campaign never replaces one; the Campaigns list plays, renames, duplicates, exports and deletes them, and imports a shared one; the old SwiftData autosave and named slots carry over (`CampaignTests`)
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
- [ ] **Card style setting** (asked 2026-10-10): a Settings switch, changeable at any time (mid-scenario too), between the real card scans — the default, the way the game is played — and the simpler drawn cards the app had before, which are easier to read and parse at a glance. It should cover every place ability cards appear (hand and card selection, the turn panel's played cards, previews), take effect at once, and be remembered

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

Most of the items above belong to the companion-app views, which the game itself no longer
reaches; `ContentView` only shows the main menu, the party screen and the board.

### Look & feel audit 2026-10-08 (`docs/audits/2026-10-08-ux-audit.pdf`)
- [x] Board layout from the mockup (`docs/mockups/`): one top bar (menu, round and phase, goal, a turn rail that shows who is ready or choosing during card selection and "2 of 3 acting" in play, small elements lit by state); party and monster panels sized to their contents with portraits; the log as recent notes with the whole log a tap away; card selection as the real card scans with Lead/Second badges, the board fitting above it (`testTheTopBarDuringCardSelection`, `testTheTopBarDuringPlay`)
- [x] Turn panel: the two played cards as the real card scans, the half each gives lit and the half being performed ringed in brass; the next step as the one brass button, the rest quiet (Swap Cards, Top/Bottom First, the basic action, Skip Rest of Half, items); the instruction with Cancel and Skip inside the panel while a step waits; Begin Scenario, End Turn and the rest prompts brass; no green, cyan or orange buttons left on the board (`testThePlayedCardsStaySmall`); the quiet buttons wrap inside the panel rather than running out of it (`testTheTurnButtonsStayInsideThePanel`)
- [x] Scenario brief: the scenario's monsters as portraits, the map (rooms and starting tile) and the rewards for winning (achievements, gold and XP, items, a new class, the scenarios it unlocks), beside the goal, defeat and special rules (`testBriefsSayWhatTheScenarioAsks`)
- [x] Attack previews: while choosing a target, a chip under each says the damage it would take ("2 dmg") and the instruction gives the sum ("3 − 1 shield = 2 + draw", poison, advantage, conditions), spoken to VoiceOver too; the drawn modifiers' sum as chips in the tray ("Attack 2", "−1 card", "−1 shield", "= 0", conditions) (`testTheAttackPreviewSaysWhatTheAttackWillDo`, `testTheDrawSumAsChips`)
- [x] Pause and Fast-Forward while monsters, summons and escorts take their turns (Space and F): paused, the turn stops before its next move, attack or figure; fast-forward plays four times quicker; both end when a character's turn or a new round comes, and leaving the board releases a paused turn (`PlaybackTests`)
- [x] Learning mode (`docs/mockups/learn-*.png`), on for a player's first campaign and switchable in setup or the game menu: a tip the first time each rule comes up (about 40, in our own words; one at a time, each shown once ever, the monsters held while one is up), with a spotlight on what it's about and the moment's own numbers ("Here Brute drew −1: 2 − 1 − 1 shield = no damage"); long-press (right-click on the Mac) anything to learn what it is; the "?" outlines everything and explains the next tap; "Why?" on each monster's lines in Recent shows the enemies it weighed, its focus and why, drawn on the board; How to Play in the game menu, opened at the topic (`LearningModeTests`)
- [x] How to Play as a book (`docs/mockups/howto-*.png`): wide, two panes, the contents with a tick for each topic met in play or read and "New" for those met but not read, a search, one topic at a time with Previous and Next (arrow keys too); titles in Pirata One, the text in a serif with key terms in bold and links between topics; each topic's picture is the game's own art (modifier cards, card scans, condition and element icons, monster tokens) or a hex diagram (moving, doors, loot, summons, attacking, line of sight, push and pull, how monsters choose, winning); "On the board" says where each rule shows up (`HowToPlayTests`)
- [x] Learning mode beyond the board's monsters: "Why?" for summons' turns too (the enemies a summon weighed, its move and attacks); tips in town as each thing becomes possible (levelling up, perks, personal quests, retirement, the shop, enhancing) with How to Play in the town bar; a "Special rules" tip for scenarios that have them; a "Between Scenarios" chapter in How to Play (`LearningBeyondMonstersTests`)
- [x] Fills every iPad screen: a launch screen, so iOS no longer letterboxes the app to an older iPad's size (black bars on the 11-inch iPad Pro M4); checked on the 13-inch and 11-inch iPad Pro and the iPad mini (`ProjectSettingsTests`)
- [x] Town screen in the board's look (`docs/mockups/town-*.png`): a top bar with the town's standing and what can be done there; the party as cards (portrait, brass XP bar, gold, quest, actions) with the classes to recruit pinned below so a tap never lands on the wrong class; the chosen scenario with its spot on the world map, goal, monsters and rewards; difficulty and the scenario level it gives; Set Out saying what comes next; the open scenarios on the right (`TownTests`)
- [x] Settings in the board's look: sections as panels, brass switches, animation speed and text size as named stops (Fast … Very Slow, Compact … Maximum) instead of sliders, with a text preview (`SettingsStopsTests`)
- [x] Character sheet in the board's look (`docs/mockups/sheet-11in.png`): one page instead of tabs — level and XP bar, health/cards/gold, personal quest with progress, battle goals in groups of three, notes, perks in the rulebook's words with brass checkboxes, owned items; a large dialog over the town instead of the small form sheet (`TownTests`)
- [x] Shop in the board's look (`docs/mockups/shop-11in.png`): item tiles that say what each item does, Spent/Lost badges, Buy / Sell for half (confirmed on the tile) / "n more gold" / Sold out, slot filter as a brass segmented capsule, the buyer switchable between party members, what they own per slot (`TownTests`)
- [x] Item rule text dropped modifier, element-consume, slot and class-word tokens (Iron Helmet read "to be a  instead"); summon items had no text (`testEveryItemSaysWhatItDoes`)
- [x] Campaign in the board's look (`docs/mockups/campaign-11in.png`): prosperity checkmarks with level thresholds, reputation as a centred track with its price effect, achievements as chips, open and won scenarios, the party, the campaign log
- [x] Campaign progress counted the 17 solo scenarios and the random dungeon ("0/113" for Gloomhaven's 95) (`TownDialogTests`)
- [x] World map in the board's look (`docs/mockups/worldmap-11in.png`): a large dialog, stickers only for scenarios the party has found (open in brass, won in green) instead of every scenario, a detail panel beside the map instead of a second sheet
- [x] Hand in the board's look (`docs/mockups/hand-11in.png`): all of the class's cards on one screen, chosen ones ringed in brass, the count as a brass chip
- [x] Table rules, campaigns, credits and the event card in the board's look (`docs/mockups/small-dialogs.png`), as dialogs over the town and menu
- [x] Items loadout in the board's look (`docs/mockups/loadout-11in.png`): owned items as tiles saying what each does, brass switches to bring or leave at home, why one can't be brought
- [x] Enhancer in the board's look (`docs/mockups/enhancer-11in.png`): the class's cards on the left, the chosen card large with each slot and its priced options (unaffordable ones dimmed), gold in the header
- [x] Level-up card choice in the board's look (`docs/mockups/levelup-11in.png`): the new level's cards large, chosen one ringed in brass, Add Card / Later
- [x] Statistics in the board's look (`docs/mockups/statistics-11in.png`): won, lost, kills, exhaustions; per character won, kills, elites, exhausted, XP, gold (from character records); names from labels, not `.capitalized`
- [x] Personal quest, battle goal and sanctuary dialogs in the shared header style (`docs/mockups/pickers.png`), Keep buttons on each choice, sanctuary progress to the next prosperity
- [x] Cancel in a recruit's quest picker takes the recruit back, log entry and all (`testCancellingTheQuestUndoesTheRecruit`)
- [x] Hold Prosperity, Reputation, City Event and Sanctuary in town to learn about them (`docs/mockups/town-hold-*.png`): the board's explanation card under the chip, with How to Play topics for each
- [x] Unlocking looked won scenarios up by number in load order, so a solo scenario sharing the number could unlock nothing (#4 Crypt of the Damned → #5, #6) (`testWinningAScenarioUnlocksWhatItsCampaignCardSays`)
- [x] Event text showed raw `<br><br>` (city event 11 and 13 others): line breaks become paragraphs (`testEventTextHasNoMarkup`)
- [x] Board action panel: a tall empty area above and beside the turn controls on the 11-inch iPad; FlowLayout claimed all the width offered (`testAFlowIsAsWideAsItsRows`)
- [ ] Learning mode, still to write: "Why?" for escorts; FH topics (loot cards, outposts) when FH play comes

Phase I — safety & words (done)
- [x] Autosave at the start of every round, at scenario end and on Save & Quit; Continue resumes the board at the saved round (`SaveAndContinueTests`)
- [x] Exit replaced by a game menu (Save & Quit, Abandon with confirmation); "‹ Menu" no longer wipes the campaign; New Game confirms and tears down the board
- [x] Player-facing names everywhere (`GameText`): no ids, coordinates or enum names in the log, HUD or buttons; coordinates kept as log traces for transcripts (`PlayerTextTests`)
- [x] HUD heading names whose turn it is; no "Round 0"; action buttons read "Attack 3, Range 2"; card selection says Lead / Second
- [x] Board elements are display-only, with a distinct "infused this turn" look
- [x] No `NSSound.beep()` on the Mac; haptics follow their own toggle; launch sting respects the sound setting
- [x] Settings trimmed to what works; Animation Speed drives the board's animations and turn pauses (`SettingsWiringTests`)

Phase II — readable board (done)
- [x] Monster tokens from thumbnails with standee badge and elite rim; HP bar and condition icons on every token (`BoardTokenTests`)
- [x] Initiative rail and an instruction banner for every selecting mode, with Skip This Action (`TurnGuidanceTests`)
- [x] Cancel a target choice: the banner's Cancel (or Escape) takes the ability back while nothing on the board has changed: elements, charges, XP and the log are restored and the ability waits to be performed again (`testCancellingATargetChoiceTakesTheAbilityBack`)
- [x] Multi-hex overlays drawn on every cell (~330 in the scenario maps) (`BoardOverlayTests`)
- [x] Taps resolve to the nearest hex; tapping a hex targets the figure on it; macOS click-vs-drag; iOS threshold in screen points (`BoardTapTests`)
- [x] Content-sized side panels, collapsible log, hide-panels button; HUD fits iPad Pro and iPad mini; party screen rows don't shift (`BoardLayoutTests`)
- [x] `HighlightStyle` per interaction with colour-blind-safe hues and shape cues (`HighlightStyleTests`)

Phase III — game feel
- [x] Effects layer: a ring on the acting figure, attack lines and melee lunges, outlined damage/heal/Miss/Blocked/Prevented text that outlives a killing blow (`BoardEffectsTests`)
- [x] Condition pops: a gained condition floats its name (hindrance purple, boon blue) and its icon pops; "… ends" as it wears off; curse, bless and immunity are announced too (`BoardEffectsTests`)
- [x] Distinct move animations: walks step and ease, jumps arc over (lift and shadow), flyers stay lifted, teleports vanish and reappear with a flash, pushes and pulls shove with a jolt; reduced motion drops the lifting (`MoveAnimationTests`)
- [x] Modifier draws in a docked tray (real card art); monster draws resolve without a modal (setting to draw them by hand); damage choice as a docked sheet with card scans, select-then-confirm and an exhaustion warning (`ModifierDrawTests`, `DamageChoiceTests`)
- [x] Camera: frames the board in the largest gap between the HUD panels (reframes when a panel grows over it, and when a door opens), can't be dragged off the board, zooms where the fingers or pointer are, follows the acting figure; "show whole board" button; trackpad scroll pans (`BoardCameraTests`)
- [x] Room reveal without rebuilding the scene: the new room's tiles, overlays, figures and loot fade in; tokens, effects in flight and the grid offset stay put (`RoomRevealTests`)
- [x] Board sound effects (Kenney CC0 packs, credited in Resources/Sounds/CREDITS.txt): steps, hits, heavy hits, misses, blocks, deaths, heals, loot, doors, traps, teleports, landings, conditions, card draws, a character's turn; silent when headless (`BoardSoundTests`)
- [x] Sound design pass, every sound chosen by ear (docs/sound-design.md): a cue for each base-game condition in place of one pluck for all; cues for exhaustion, partial shield, retaliate, elements, spawns, rests, lost cards, the round beginning, deck shuffles and the player's own taps (card picked, cards locked in, target chosen, End Turn, a tap that isn't a choice); levels mastered into the files (`SoundAssetTests`); cues raised together heard in order, a repeated cue once (`BoardSoundMixerTests`)
- [ ] Sound: the "tap" on the header's element tokens still plays the iOS keyboard click (`SoundPlayer.play(.tap)`) and nothing on the Mac; fold `SoundEffect` into `BoardSound`
- [ ] Sound: a recorded choir for Bless in place of the synthesised one, if a CC0 sample turns up

Phase IV — the game around the board
- [x] Main menu key art (the world map, drifting under a vignette; still under Reduce Motion), Load Game and Credits on the menu (the mascot moved there), jingles for a scenario's start, victory and defeat (`MainMenuTests`)
- [ ] Menu music: needs a looping track (Kenney has no CC0 loops)
- [x] Scenario intro card (goal, how it's lost, special rules — described from the data; reopened from a Goal chip) and a results screen (why it ended, XP gained plus the success bonus, gold, level-ups, rewards, unlocks) (`ScenarioFramingTests`)
- [x] Town between scenarios: finishing (or abandoning) a scenario returns to town; party roster with level, XP to next level and gold; Level Up when the XP is there (no more free level picker); perks limited to those earned; shop through `ItemManager.buy/sell` (one copy each, stock, half-price sales); world map to pick the next scenario; campaign sheet (`TownTests`)
- [x] Level-up ability card choice: a card pool of level 1 and X cards plus one chosen card per level (of that level or lower), chosen in town with the card scans; a hand chosen from the pool; older saves adopt the higher-level cards they carry (`CardPoolTests`)
- [x] City and road events: decks of cards 01–30 (more added by events), saved; a city event after each scenario and a road event on the way to a road scenario; conditions, costs, choices and "outcome A" redirects; effects including damage, conditions, −1 cards and discards carried into the next scenario; options the party can't take greyed out (`EventCardTests`)
- [x] Campaign log on the Campaign sheet, newest first, in plain words (level-ups now logged too); reputation and prosperity there are read-only, no longer +/− steppers (`CampaignLogTests`)
- [x] Deleted the companion leftovers: `GameBoardView` and 69 more views only it reached; the live pieces they held moved out (`UniqueTile`/`MapImageCache`, `RewardChoicesView`, `ActionHex`, `FlowLayout`, `Color(hex:)`)
- [x] Board theme tokens (`BoardTheme`: surfaces, brass, radii, display type) and an 11 pt text floor (31 sizes of 7–10 pt raised; HUD still fits both iPads); every board control has text or a VoiceOver label; tokens on the board are spoken ("Bandit Guard 1, 4 of 6 health, Stun"); source checks guard the floor and the labels (`BoardAccessibilityTests`)
- [x] VoiceOver play on the board, the remaining menus themed, Majalla dropped (see Phase VI)

- [x] Compact turn panel: only the half of the card being played (top or bottom), so the panel is ~40% shorter and the board bigger during a turn (`BoardLayoutTests`)

Phase V — the campaign around the scenarios (done 2026-10-08)
- [x] Town between scenarios, level-up card choice and hands, city and road events, campaign log, scenario rewards, compact turn panel (see the items above)

Phase VI — the rest of Gloomhaven's town rules
- [x] Battle goals: two dealt to each character when setting out, one kept; all 24 judged from tracked stats (traps, doors, treasure, elite kills, overkill, first kill, executions, health, rests, monsters each round) saved with the scenario; shown in the brief and on the results; checkmarks on a success (`BattleGoalPlayTests`, `BattleGoalTests`)
- [x] Items on the board, first batch: the starting shop's on-turn items (Boots of Striding, Winged Shoes, Cloak of Invisibility, Eagle-Eye Goggles, Piercing Bow, War Hammer, Poison Dagger, Minor Healing and Power Potions) appear on the turn panel when their moment comes, apply, are spent or consumed and count for Professional/Purist (`BoardItemTests`)
- [x] Defence items offered mid-attack: Leather Armor (disadvantage, before the draw) and Heater Shield (Shield 1 once the attack would damage); headless play declines them (`BoardItemTests`)
- [x] Minor Stamina Potion: recovers up to two discards, picked when there are more (`BoardItemTests`)
- [x] Hide Armor: Shield 1 against two attacks before it's spent; use slots saved and cleared with the item's refresh (`BoardItemTests`)
- [x] Iron Helmet: an enemy's ×2 against the wearer counts as +0 (always on: the card has no spent or consumed mark)
- [x] Items, second batch: 40 on-turn items (boots, potions, earrings, wands, powders, cure, Lucky Eye, Skull of Hatred, Remote Spider, Black Censer, Smoke Elixir, Ancient Drill, Staff of Xorn…), 13 defence items (every armour and shield, with use slots), and the always-on ones (stronger basic attack/move, flying, immunities, Silent Stiletto) (`BoardItemTests`)
- [x] Items, third batch: element blades, staves, robes and orbs (usable only with their element, which they consume), Hawk Helm and Telescopic Lens (more range while targeting), Bloody Axe and Sacrificial Robes, Giant Remote Spider, Mask of Terror; unmarked items stay usable (`BoardItemTests`)
- [x] Items with a choice: Minor and Major Mana Potions, Staff of Elements, Circlet of Elements (an element picker), Minor Cure Potion (a condition picker) (`BoardItemTests`)
- [x] Always-on items, second batch: Heavy Greaves (no forced movement), Drakescale Helm (muddle becomes strengthen), Chain Hood (Shield 1 beside three monsters), Necklace of Teeth and Imposing Blade (on a kill in your turn) (`BoardItemTests`)
- [x] Movement items: hexes moved on a character's own turn are counted (pushes and pulls aren't); Shoes of Happiness, Endurance Footwraps, Steel Sabatons, Horned Helm; Drakescale Boots and Magma Waders ignore hazardous terrain, the Waders heal on entering it (`BoardItemTests`)
- [x] Attack conversions: Battle-Axe, Long Spear, Reaping Scythe, Volatile Bomb turn a single-target attack into their printed area; the Halberd reaches 2 hexes in melee (`BoardItemTests`)
- [x] Boots of Speed and Quickness: once every card is revealed, the wearer may move their initiative 10 (20) earlier or later (`BoardItemTests`)
- [x] Shadow Armor (no damage from one attack), Sun Shield (consume Light: Shield 3), Helm of the Mountain, Mask of Death, Flea-Bitten Shawl (`BoardItemTests`)
- [x] Empowering Talisman, Pendant of Dark Pacts, Utility Belt (an item picker), Focusing Ray, Volatile Elixir, Curious Gear (`BoardItemTests`)
- [x] Item carry limits (GH p.9): one head, body and legs item, two hands' worth, half the level (rounded up) in small items, Cloak of Pockets +2. Characters own any number; the Items sheet in town brings or leaves each one, an item that doesn't fit stays at home, and the board, −1 cards and passives use only what's brought (`ItemLoadoutTests`)
- [x] Table rules (campaign variants, each off by default): Enhancer open from the start, bring every item, no road event before the first scenario. Set in town ("Table rules" under the difficulty), listed on the scenario brief while on (`TableRulesTests`)
- [x] City and road events have a close button (×, or Escape): the event stays due and setting out waits for it
- [x] Second Skin: two −1 cards set aside for the scenario, back after it (`testSecondSkinSetsAsideTwoMinusOnes`)
- [x] Items with their own choice between the turn's steps: Scroll of Healing, Doomed Compass, Staff of Summoning, Resonant Crystal; Elemental Boots (after moving 5), Thief's Hood (`BoardItemTests`)
- [x] Scroll of Stamina, Robes of Summoning, Pendant of the Plague, Unstable Explosives (area that also hurts allies in it) (`BoardItemTests`)
- [x] Hooked Chain (Pull 2 on a ranged attack), Blinking Cape (Move 4, Jump between steps), Helix Ring (consume Light and Dark: Heal 25), Skullbane Axe (+5 on one attack against the undead), Psychic Knife (+1 on augmented attacks), Phasing Idol (a summon suffers no damage from an attack, the owner asked), Stone Charm (one more obstacle while placing them) (`BoardItemTests`, `testThePsychicKnifeAddsToAugmentedAttacks`)
- [x] Summon items: Falcon Figurine, Mountain Hammer, Ring of Skulls, Power Core place their figure next to the character like a card's summon (not offered with no room) (`ExtraItemTests`)
- [x] More card plays: Ring of Haste and Ring of Brutality play a card from the hand for its bottom or top half at the end of the turn; Staff of Command does the same side right after a Command; Second Chance Ring plays two more cards for another turn this round at a later lead initiative (summons don't act again); Master's Lute gives Attack 2 or Move 2 after a Song; Cloak of the Hunter muddles a Doom's target (`ExtraItemTests`)
- [x] Items on another figure's turn: Scroll of Power adds +1 Attack to the acting character's attack from another character's pack; Heart of the Betrayer turns an adjacent normal enemy's attack on one of its allies within its range (the wearer picks which); Dampening Ring consumes an element before a monster can (`ExtraItemTests`)
- [ ] Doctor's Coat (+1 Heal on an ally's Medical Pack) waits for the Sawbones' Medical Pack cards, which allies can't be given on the board yet
- [x] Personal quests: two dealt on recruiting, one kept; a campaign record per character (wins, kills by monster, elite kills, exhaustions) counts every requirement the game can see, after wins and losses; progress in town and on the sheet; by-hand counting only for map-region, enhancement and Skullbane requirements (`PersonalQuestTests`, `PersonalQuestAutotrackTests`)
- [x] Retirement from town when the quest is complete (unlock, prosperity, log); a new recruit takes the slot
- [x] Sanctuary donation in town: 10 gold once per visit for two blessings in the next scenario; prosperity +1 per 100 gold given; counts for Piety in All Things (`TownTests`)
- [x] Enhancements in town: the Enhancer (after The Power of Enhancement) sells +1, conditions, elements and jump for each card slot at chart prices, paid in the character's gold; enhanced cards play enhanced on the board and show their enhancements on card tiles; heals now apply their own conditions, and moves their printed infusions (`EnhancementTests`)
- [x] Any-element enhancements and printed "infuse any element" (Chromatic Explosion): the player picks the element (`testAnAnyElementEnhancementAsksWhichElement`)
- [x] Hex (area) enhancements: sold where the card's area marks room for a hex (32 areas), priced 200 ÷ hexes targeted; the marked hex becomes a target (`testAHexEnhancementWidensTheArea`). Areas with two marked hexes have a slot for each, and the Enhancer draws the area with that slot's hex lit; a second hex is priced counting the first (`testEachHexSlotFillsItsOwnMarkedHex`)
- [x] Unlocking a class (by retirement or scenario reward) shuffles its unlock event into the city and road decks; retiring adds the class's retirement event (`PersonalQuestTests`)
- [x] VoiceOver play on the board: every pick (move, start hex, summon, push/pull hex, attack/heal/condition/forced-move target, multi-target confirm) is a spoken action on the prompt banner — distance, direction, what's there and who's beside it — doing exactly what the tap does (`BoardAccessibilityTests`); the unused Majalla font is gone
- [x] The remaining menus on the board theme: the default dark theme is the board's palette (warm dark, brass accent, warm text) and controls take the accent app-wide; Frosthaven/Modern/B&B themes keep theirs (`ThemeTests`)
- Open questions for the user: docs/open-questions.md

Found along the way
- [x] Scenario rewards the game never granted: items, character unlocks, collective gold, item designs (feat/scenario-rewards), and events shuffled into the decks (`EventCardTests`); envelopes remain below

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
- [x] Unit tests (1,400+ tests: unit, e2e, rulebook verification, headless scenario simulation)
- [x] **Deterministic simulation** — every shuffle and random draw goes through the seedable `GameRandom`; seeded games replay identically across processes
- [x] **Golden turn logs** — seeded games (GH 1, 2, 4) compared turn by turn against hand-checked transcripts in `Tests/Golden/` (`GOLDEN_RECORD=1` re-records)
- [x] **Full playthroughs** — `ScenarioSimulator` plays scenarios to the end with a tactical policy, checking every attack (LOS, enemies, visibility), every move (adjacency, walls, obstacles, doors, end hex) and the board after each step; outcomes must be a legitimate victory or defeat
- [x] **CI** — `.github/workflows/tests.yml`: the suite on push/PR; nightly, every main GH scenario to the end with 4 seeds

---

## Missing Gloomhaven Rules

The way in is [`docs/rules-work.md`](docs/rules-work.md): where the rules work stands, which document
answers what, how a fix is built, proved and verified, and how to read the scenario book. This
section is its task list. Everything is on `main` as of 2026-10-10 (merge `236fb2d`); as last run by
the audit, the suite had 1,534 tests passing and the four-seed all-scenarios playthrough no rule
violation.

### Open, in order

**1. Tests and checks** — before anything new is built on top
- [x] **Three rules no test catches** (found by `scripts/mutate.py --all`, 2026-10-10; done 2026-10-12 — each of the 36 mutations is now noticed by a test):
  - `lootIgnoresSight` — the old test's hidden token was also out of range (range isn't counted through a wall), so sight never decided anything. `LootRuleTests.testALootAbilityLeavesATokenItCannotSee`: a token three hexes off round a wall hex, in range of Bag of Holding's Loot 3 and out of sight, stays
  - `revealedWaitForTheirPlace` — could not be noticed: the branch it broke did nothing the other branch didn't (every figure still to act is on a higher initiative than the one acting, so "before the first higher initiative" already puts a type whose place has passed right after it). `scheduleRevealedMonsters` is now that one rule, and two mutations that do break it replace the old one: `revealedActLast` and `revealedMissTheirPlace`, both noticed by `RevealRuleTests`
  - `roomForFourAlways` — broke only where the room's monsters stand, not how many: the count of characters was written out in twenty places. It is now `GameState.characterCount` everywhere, the mutation is `exhaustedDontCount` on that one line, and `RevealRuleTests.testARoomIsSetUpForTheCharactersTheScenarioBeganWith` also checks who stands where
- [x] **Mutations for the fixes whose failing-before half was only read** (done 2026-10-12): fifteen more in `scripts/mutate.py` — C8 `alliedMonstersDropMoney`, `bossesDropNoMoney`; E7 `soloChangesNothing`, `soloRaisesGold`; E12 `escapeIsExhaustion`; B7 `stunnedUseItems`; B6 `restGivesUsesBack`, `armourWaitsToBeAsked`; B12 `ownDamageNotNegated`; B11 `chargePerFigureHealed`, `attackBonusMarksNoCharge`; B4 `endedBonusStillActs`; B8 `noItemsOnARestTurn`, `restTurnSkipsBonuses`; start-of-round rules `roundStartRulesWaitForTheCards`. Each is noticed by a test. Three tests had to change for that: the solo test played at a level where solo's gold couldn't be told from the party's (now levels 5 and 6); the escape test never looked at the scenario summary's "exhausted"; the stun tests waited for ever on an offer nobody answered (`ItemUseRuleTests.unasked` now declines it and fails)
- [x] **Mutations for the scenario mechanisms** (done 2026-10-12): 36 in `scripts/mutate.py` (`--scenario` runs just these, against the scenario tests) — the `when` facts (saved, lock, unrevealed, occupied, looted), `lostIfStands`, `lootActionOnly`, `effects` (attack, advantage, disadvantage, shield, `noItems`, `untilLooted`), `water` (the poisoned, the end of a turn, the cleansed), `undamageable`, `reprieve`, `inactive`, `sheltered`, `apart`, `focusFirst`, `cycles` (letters, doors, appearing and leaving), the eggs, `march`, locks (keys, held doors, locked doors as walls), `setUp`, `whenDestroyed`, `specials`. All 36 are noticed by a test; 87 mutations in all
- [x] **Look at the new interface** (N16; looked at 2026-10-13 as rendered screens — `INTERFACE_RENDER_OUT=/tmp/ui swift test --filter testRenderTheAuditsInterface`): the Solo switch sits beside the difficulty with its line of explanation; the damage sheet's "Let Frost Armor Take It" and the long-rest sheet (heal toggle, "Use Minor Healing Potion") read well. One fault: a card in play was a 28-point row with a 32 × 28 button to end its bonus — now 44 points both (`BoardLayoutTests.testCardsInPlayAreFingerSizedAndStillFit`, with a party of four and two cards in play each). The renderer can't draw a system switch or a scrolling list, so those two are still worth a glance on the iPad
- [x] **Look at what the scenario rules draw** (2026-10-13, from rendered maps: `BOARD_RENDER=15 BOARD_RENDER_OUT=/tmp/s15.png swift test --filter testRenderScenarioMap`): pressure plates, padlocks, inactive monsters as hollow rings with their number, and the lines round each tile all show (#15, #61, #79). Found on the way: **a door two hexes wide opened one hex at a time** (#15, #24; three hexes in #78), the other half staying a shut door — a wall to monsters and a room "not revealed" to the scenario's end. All of a wide door now opens together; Harrower Hive's breakable walls stay a hex each. `RevealRuleTests.testADoorTwoHexesWideOpensAsOne`, mutation `wideDoorsOpenByHalves`. Not looked at, because they need a game in progress: the eggs (#46), the Dark Rider coming and going (#48), the bosses' jumps (#51, #2)
- [x] **Read the golden transcripts the audit changed** (2026-10-12, `git diff b4d0647 -- Tests/Golden` with standee numbers masked): every change is one the rules ask for — standee numbers drawn at random; Disadvantage for a ranged attack on an adjacent target (a Guard's Range 2 card, the Archers, Spare Dagger); an attack with no target gives no element, experience or lost card (so a short rest is offered a round sooner); Flamethrower's experience and Fire once it is performed; #2's traps stun and deal no damage (checked against the book's legend, p.4); a long rest declared with two discards and left with one after negating damage loses it and takes back none. "Moves 0 hexes" (Trample, Opposing Strike) is the FAQ's Move 0, and the half counts as performed
- [x] **#36 never ended for the veteran parties** (N19, found and fixed 2026-10-12): a room revealed by a scenario rule as a round starts (#36's gate falls in round 9) left the board in the turn phase with no one to act — `revealRoom` always went back to "turns in progress". It now goes back to the phase it interrupted. On `main` since before the follow-up branch; a player reaching round 9 of #36 with the gate standing met it. `RevealRuleTests.testARoomRevealedWhileCardsAreChosenLeavesThemBeingChosen`, mutation `revealAlwaysResumesTurns`; the veteran playthrough passes again (55 and 59 of 94 won)
- [x] **#9's scouts** (N12; looked into 2026-10-13): a miscount, not a double attack. The Overseer's "All Scouts act again" comes on its own turn (79) and the Scouts' own on 92: two turns, two abilities. The ledger set a standee's first turn aside only when another figure acted in between, so a Scout that was the only one to act on both turns looked like one ability attacking twice. The simulator now starts afresh at every turn line; `PlaythroughTests.testAScoutsExtraTurnIsATurnOfItsOwn` (seeds 2 and 3, failing without it)
- [x] **To check** (N13; checked 2026-10-12, three of the four were wrong): Unending Chant doubled only Curses from attacks — now any Curse a character gives an enemy (`applyCondition(_:to:by:)`; `testUnendingChantDoublesACurseThatIsNoAttack`); Angelic Ascension, Backup Ammunition and Grim Bargain's doubling ("your next Attack actions") and Potent Potables ("Heal actions") marked a charge as the step began even when it found no target — now only once the action is performed (`testAnAttackActionWithNoTargetMarksNoCharge`, `testAHealActionWithNoOneToHealMarksNoCharge`); Frost Armor's text does reach the printed-damage step, with an amount of 0, which does nothing (left as it is). Six mutations
- [ ] The simulator: 31 scenarios neither veteran party wins (#21 since its altar jumps, 2026-10-13: the Prime Demon can only be hurt through an altar that goes round six places and summons a demon at each, and the party reaches it for an attack or two every few rounds — exhausted by round 20 to 26 with the room full of demons; no policy heads for where the altar will be next; #74 since its hold fills, 2026-10-13: half the party carries water to the bailing hexes — tiles are picked up and bailed, a round trip every three or four rounds — but not fast enough to keep ahead of a tile a round; #88 since the current, 2026-10-13: the party is pushed back a hex a round and takes 3 damage against the walls, and is exhausted before the claw reaches the crystal; neither policy looks for shelter; #95 since its door was locked, 2026-10-13: one character goes for the tokens, the boulders are destroyed and the door is opened by round 17 or so, but too few are left standing for the Prime Lieutenant; and #7, #15, #19, #23, #25, #27, #30, #33, #40, #41, #50, #52, #56, #59, #60, #61, #66, #67, #69, #70, #71, #79, #81, #82, #86, #90, #92; recounted 2026-10-13 from both parties at seed 1 — #12 and #85 are won, and #58 by the party of four, since a door first seen from its far side got its hex, N22) — mostly goals `VeteranPolicy` doesn't play for (a Loot-action treasure, pressure plates, escorts, protected objectives, #90's altars); no line-of-sight check independent of the engine's; a character's attack with a custom or special-target line and a boss's attacks aren't range-checked; the first-level `TacticalPolicy` party still never wins

**2. Scenario rules** — 94 printed rules still open in 28 scenarios; each has a row saying what the game does today in `docs/scenario-book/rules-audit.md` ("What is still open" there groups them the same way)
- [x] **A prompt for a choice the player can't make yet** — the first of them is built (2026-10-13): **losing a hand card to spare a captive (#44) or the crystal (#84, twice)** — placements `saves`, `BoardCoordinator+Saves`, `SaveChoiceSheet`, answered by the simulator's policies (`spare`); `testACardFromAnyHandSparesTheCrystalTwice`, `testACaptiveIsSparedAsOftenAsThereAreCards`, `testHeadlessACardGoesOnlyToSaveTheScenario`, five mutations. **Giving up an action to free a captive (#44)** is built too (2026-10-13): placements `forgo`, `BoardCoordinator+Forgo`, a button beside the basic action; #44's loss and Redthorn's +1 Attack for each captive freed are on (`testACharacterBesideACaptiveGivesUpAnActionToFreeIt`, `testACaptiveKilledLosesTribalAssaultAndOneFreedDoesNot`, five mutations). **Cleansing a pump (#26)** uses the same rule with `does` and `bottom`, and the Cistern has its goal (`freed`; `testAPumpIsCleansedForABottomActionAndTheCisternIsWon`). **Looting the treasure beside a character (#52)** is the same rule with `treasure` (`testATreasureBesideACharacterIsLootedForABottomActionGivenUp`). **Digging a grave with movement (#75)** is `dig`: a tap on a grave beside the mover spends a point of the move (`testAGraveIsDugWithMovementSpentBesideIt`). **Which Living Spirit goes (#70)** is asked too (`resolveReprieves`, `testThePlayersChooseWhichLivingSpiritGoes`). **Whose deck Redthorn and the Orchids draw from (#44, #56)** is asked as they attack (`drawsFromACharacter`, `testRedthornDrawsFromTheDeckThePlayersChoose`). Nothing is left of this item but the note below. (The original list, for reference: giving up an action or movement to cleanse a pump (#26: then its goal can be checked), free a captive (#44), loot an adjacent treasure tile (#52), dig a grave (#75); choosing which Living Spirit is banished (#70: the game takes the nearest); choosing whose modifier deck Redthorn and the captives draw from (#44, #56). Then switch on #44's loss (`lostAt` for the captives) and Redthorn's +1 Attack for each captive freed)
- [x] **Things that are carried** (done 2026-10-13) — the mechanism is built (placements `carried`, `BoardCoordinator+Carried`, `CarriedThingTests`, thirty-seven mutations): someone holds it or it lies on a hex; it is chosen at set-up, dropped by a monster or looted from a tile; it passes by a Loot action with the holder in range and lies where an exhausted holder stood; a goal's `reach` can ask for its holder. **Done with it:** #69 the doll, #88 the claw (−2 Move), #58 the Occult Dagger (the Vengeance character only; Pierce 4 against the Harvester), #82 the artifacts (their holder sacrifices one; lost if the holder is exhausted — the item given up isn't chosen or removed yet). #81's Crystal of Zenith and Sphere of Midnight (from the two goal tiles in order; discarded beside the altar for 2×C damage, asked as the holder's turn ends) are done too. #54's Staff of Xorn (the Seeker's; only its holder harms the Infesters; its charge; the goal and the loss) is done as well. **#95's six numbered tokens** are done too (placements `tokens`; shuffled and laid face down on the (a) hexes as the side rooms are revealed, looted like money; lock key `tokens: [1, 2, 3, 4]` on door 1, which can then be opened; a Flame Demon as each odd round ends and an Earth Demon as each even one, by that door, while it is locked — the `when` fact `locked`). Its five boulders have their 3+L hit points as well (objectives standing on the obstacle hexes, which go when they are destroyed): three of the tokens lie behind them, so the locked door needed them. The veteran test parties find all six tokens and open the door but don't yet win the scenario (they are worn down by the demons on the way)
- [x] **A board that moves as the round ends** (done 2026-10-13) — **#71 the wind and #88 the current** (placements `drift`, `BoardCoordinator+Drift`, `DriftTests`, fifteen mutations): as the round's turns are over each character and summon is moved one hex by forced movement — the wind by round (up, right, down, left on our map; two hexes to tap between on up and down, and the choice to stay when one is shut, FAQ), in initiative order; the current in the large room by the Lurkers' card (even up-left, odd up-right; a card is drawn when no Lurker is left), from the top of the map down, with shelter behind an obstacle or wall and 3 damage when in its way. A new board prompt, `chooseHex` (`InteractionMode.choosingHex`), asks for one of a few hexes outside a turn. **#73's boulders** (placements `rolling`, `BoardCoordinator+Rolling`, `RollingBoulderTests`, ten mutations): two to a row, the rows running from (b) to the map's left edge through the party's starting hexes; as a round ends the players choose which row rolls 1, 2 or 3 hexes (`chooseOption`, an answer in words — the gentlest for the party is suggested); a boulder destroys an obstacle in its way, leaves traps and rubble as they were, deals trap damage to whoever it rolls over and pushes whoever it stops on a hex left; from the last hex of its row it comes back in at (b). **#74's rising water** (placements `flood`, `BoardCoordinator+Flood`, `RisingWaterTests`, eleven mutations): the water at (d) removed for three characters; a tile added as every even round ends (every round for three or four) on a dry hex of the hold the players tap; lost when the hold is full and one is due; a tile is picked up by looting (one at a time) and bailed by ending a turn on (e). Readings of ours, where the book and the FAQ are silent: a boulder's row is the whole width of the map; a Lurker card is drawn for the current when no Lurker is left; a figure a boulder can't push left goes to the nearest empty hex. #73's Inox kept from door 1 is under "Monsters that don't act as their cards say"
- [x] **Monsters that don't act as their cards say** (done 2026-10-13) — **#71's Spitting Drakes** asleep until attacked, hurt, given a negative condition or approached (placements `asleep`, `BoardCoordinator+Sleep`, `SleepingMonsterTests`; a woken drake acts that round; summons leave sleepers alone), and **#67's Arcane Golem and #73's Inox of the cave kept from a door** (placements `barred`, `BarredDoorTests`). **#49's Siege Cannon** is done too (placements `battery`, `BoardCoordinator+Battery`, `BatteryTests`): it never acts, the nearest City Archer walks "Move 3" to it and fires it down the (b) hexes, their rows and the G tile, and an archer arrives at (a) when none is left. **#78's carriers** are done as well (placements `carry`, `BoardCoordinator+Carry`, `CarrierTests`): the two Cultists go to the victim, then carry him "Move+0" a turn to the hexes before the altar, opening the doors; he follows as far as he was carried; a Cultist starting a turn beside the altar with the victim beside it loses the scenario. With them the whole group is done
- [x] **Bosses still played from their stat cards** (done 2026-10-13, but for the last clause) — **#21** the altar that is the Prime Demon's hit points and takes its damage, jumps a → f with each special (moving aside who stands there, revealing the room) and summons the demon of where it lands (placements `throne`, `BoardCoordinator+Throne`, `ThroneTests`). **#34** is done too (placements `perch`, `BoardCoordinator+Perch`, `PerchTests`): the Elder Drake on all three hexes of its boulder (`BoardState.bodies` — attacked through any, attacking from any, its area lying as its body does), its Zephyrs (untouchable; "Move 2, Attack C" as its turn starts) and its flight right → left → top. **#79** too (placements `sway`, `BoardCoordinator+Sway`, `SwayTests`): the Betrayer's first special drives each character and summon a "Move 4" as far from it as they can get; its second draws them all to its side and turns the character last to play two cards, and their summons, for the round — a Move 2 and the attacks of the top of their leading card on their own party, both cards discarded. **Still open there:** what that top action prints besides attacks isn't performed under mind control
- [x] **Walls and obstacles with hit points** (done 2026-10-13) — **#76's 23 walls** are broken down by damage (placements `walls`, `BoardCoordinator+Walls`, `WallTests`): each `breakable-wall` connector is shut to everyone and carries an objective with C+L/2 hit points that a character attacks like an enemy and a summon acting by itself leaves alone; destroyed, the hex is a corridor, the room behind it is revealed — both rooms at the corner of three tiles — and the enemies beside it are stunned; the goal needs every room, not every wall. Its **three discarded cards** are chosen by each character before the first round (placements `discardAtStart`, `StartDiscardPicker`, `StartDiscardTests`). **#52's centre-room boulders** stop a jump or a flight as they do a walk and block sight (placements `indestructible.solid`, `HexCell.solid`, `SolidObstacleTests`), and its **starting hexes** are only those of sections that hold monsters (`startAmongMonsters`). Found on the way: a wall first seen from its far side had no hex on the board (`BoardBuilder`). Not built: a summon a character controls directly attacking a wall — there is no such summon yet (N20)
- [x] **Small ones** (done 2026-10-14) — **#38's Orchid** walks toward the Inox Shaman on the D tile, through the doors on the way, and stays once that shaman is dead (placements `seeks`, `OrchidTests`; an escort beside a destination it can't stand on no longer shuffles round it). **#68's tree** takes nothing aimed at allies but a heal, and that only once its tile is revealed (`alliesInRange(healing:)`), and **a poisoned summon** plans its move round the water as round traps (`waterAvoided`, `BoardState.avoidedAsTraps`, `ToxicMoorTests`). **#79's mind-controlled character** plays the whole top action for the monsters' side — moves, attacks, negative conditions on the party, a heal on the most hurt of themselves and the monsters, Shield and Retaliate for the round, Loot, infusions; a bonus or summon that stays with its card isn't, the card being discarded — and the Betrayer's two specials reach only those it sees (FAQ) (`SwayTests`) — and the last pieces of **#82**: the holder on the altar chooses which artifact is removed from the game, or keeps both (`Goal.sacrifices`, `offerSacrifice`), and the escape needs everyone back before being exhausted (`Exit.all`)
- [ ] **#55 Foggy Thicket** has no map: it is a random dungeon from the dungeon deck (room and monster cards, penalties) and can't be started. A project of its own (see "Random dungeon mode" below)
- [ ] An objective drawn over several hexes (a three-hex tree, a two-hex sarcophagus) is one piece on its first hex: it can only be attacked from next to that hex

**3. Engine rules** — ids are rows of `docs/audits/2026-10-09-rules-audit.md`
- [x] **A Push or Pull printed as its own ability** (N17; fixed 2026-10-12): only one card reached the unchecked path — Scroll of Recall's "Pull 1, Range 3, Target 3", whose range line the data has as an action of its own — and there it pulled nothing at all (or, after an attack that turn, the attack's target at any distance). The range line now belongs to its Pull, a chosen Push or Pull takes as many targets as it says through `performPushPull` (immunity, objectives, Heavy Greaves), and the unchecked path is gone. `ForcedMovementTests.testAPullWithItsOwnRangeAndTargetsPullsEachEnemyChosen`; three mutations
- [x] **Element choices** (B13, N7; done 2026-10-14): the player picks the element an "any element" consume takes (a menu beside the bonus; strong first without a pick), may keep the Air Nature's Lift and Foul Wind would consume, and Crackling Air's Air is consumed once as the card is played and remembered for its four attacks (`GameCharacter.elementBonusesPaid`)
- [x] **The player places an area** (A10; done 2026-10-14): aimed at an enemy, the ways the area can lie that cover different figures are offered (`placeArea`), the one hitting the most suggested
- [x] **Negating damage, the rest** (N8, N9, N10; done 2026-10-14): a discardable card in play may be one of the two lost; Warding Strength's and Cold Front's charges wait for the lose-a-card choice; single-use shields come before armour with circles, which then needn't be used
- [x] **Standees that run out** (N11; done 2026-10-14): the places nearest the character who opened the door are filled first
- [x] Low (done 2026-10-14): push and pull count further and nearer around walls (A12); a numbered treasure looted before isn't on the board on a replay (C11)
- [x] **Moving in a loop** (done 2026-10-14): a move that must end where it began (Feedback Loop) is made in legs — after each, the rest of the move is offered — and its muddle lands on the enemies jumped over, out and back
- [ ] Latent (no GH card triggers them today): an action that waits (printed "suffer X damage", a target choice) nested inside a box/concatenation step lets the outer step advance before it; a consume step with two rewards that each wait stops after the first. FH: Wound's deferred damage now lands after Regenerate's heal

**4. Cards**
- [x] **A second ability printed under a Move was never performed** (N18; found and fixed 2026-10-12): the data nests it inside the Move and only the Move was read. `PlayerTurnController.abilitiesUnderMovesAsSteps` makes it the step after the Move for Tuning the Outcome (Curse, Range 3), Power Ballad and Natural Remedy (Strengthen), Warding Dagger, Unending Chant's bottom, Crushing Hammer and Maul (Shield for the round), Forceful Swipe and Lash Out (Push 2); Feedback Loop, Sinister Opportunity and Hook and Chain, whose Move carries text, keep their own code. `MoveThenAbilityTests` (five tests, each card as its scan prints it), mutation `abilitiesUnderMovesSkipped`
- [x] **The Beast Tyrant's bear** (N20; done 2026-10-14): the class's special summon (8 + 2×level hit points, Move 3, Attack 2) is set up beside him as the scenario starts — the player tapping the hex — acts as his summon from the first round, and performs his Command halves (`BoardCoordinator+Companion`, `PlayerTurnController.commandedFigure`): Move, Attack with its targets, Heal and Strengthen "self" meaning the bear, Loot for the Tyrant; his items and bonuses stay his; with the bear dead a Command does nothing. `CompanionTests`. Found on the way: an attack's condition on its own attacker ("Strengthen self") went to the target — it is the attacker's once the attack is over; "Shield and Retaliate, affect all summoned allies" (Earthen Spikes, Patch Fur) went to the character — they are the summons' for the round
- [ ] **The Beast Tyrant, the rest**: three of his cards have no data (Disorienting Roar, Spirit Swap, Primal Blessing are "wip" in the class data: playing them does nothing), and his text bonuses about the bear (Concentrated Rage's forgone action for +3, Blood Hunger's heal after its attacks, Rampage's "any one summoned ally performs", the +1 to Commands) are the players'
- [x] Amputate (Heal 7, Range 1, with Stun on the one healed) is played on a test board (`NestedAbilityCardTests`); Earthen Spikes' Shield 2 and Retaliate 2 go to all summoned allies (`CompanionTests`) (done 2026-10-14)
- [x] **Singing Arrow's Curse has an area** (found 2026-10-12, fixed 2026-10-13): "Curse, Range 3" beside three hexes asked for one target, and the area was a step that did nothing. The area is now the condition's (`attachingConditionArea`), it is aimed like an area attack and every enemy in it is cursed. `ConditionRuleTests.testAConditionPrintedWithAnAreaGoesToEveryEnemyInIt`; mutations `areaLeftOutOfItsCondition`, `areaConditionOnOneEnemy`
- [x] Frightening Curse's doom (done 2026-10-14): each enemy beside where it died makes a Move 1 to the hex the player taps, or stays (`DoomTests.testFrighteningCursesDoomMovesTheEnemiesBesideIt`)
- [x] Traps that do more when sprung (done 2026-10-14): Detonation's trap does 2 damage to the enemies beside it and Flight of Flame's wounds them (`TrapEffect.adjacentDamage`, `adjacentConditions`; `testTrapsThatDoMoreWhenSprung`)
- [x] Impending End's top kills a target left at 2 hit points or fewer, with its XP; Darkened Skies' top attacks every enemy within Range 3, XP for each two (done 2026-10-14; `DoomTests`)

**5. Town and campaign**
- [x] Town and campaign (done 2026-10-14): the party may travel on without returning to Gloomhaven — no shop, levelling, enhancing, sanctuary or city event on the road, and no road event to the linked scenario or a retry (F19, N6; `TravelOnTests`); an event's collective gold and cost are the players' to split (F20; `CollectiveGoldTests`); a summon's stats can be enhanced (F8; `EnhancementTests.testASummonsStatsAreEnhanced`)
- [x] **Scenario reward: envelopes** (GH 58, 60: envelope X; done 2026-10-14) — opening it, by those scenarios or by the two quests that end in it, is recorded and said (`EventState.openedEnvelopes`, the campaign log); what it holds, the Bladeswarm, isn't in the game's data (`EnvelopeTests`)
- [ ] Single-target condition lines can't be enhanced yet (F8); nothing in the data unlocks #72, #73, #76, #77 (N3, a question)

**6. Not Gloomhaven, and tools**
- [ ] **Icy terrain** — no forced-movement mechanic
- [ ] **Plague / Enfeeble** (FH) — no mechanics
- [ ] **Multi-hex obstacles** — one overlay per hex
- [ ] **Random dungeon mode**
- [ ] **Pathfinding visualization** — no debug overlay for monster movement decisions

**Housekeeping**
- [ ] `.claude/worktrees/agent-a31ea4be2e273913f` and `agent-acad29b6285721967` (and their `worktree-agent-…` branches) are leftovers of this audit whose changes are all in commits `8c58c2d` and `ded90f2`; they can be removed. `feat/sound-overhaul` and `feat/scenario-rewards` are other work, untouched
- Also open, outside the rules work: four items under "iPad playthrough 2026-10-09" below (going back a turn, realistic set moves for the playthrough tests, prompts overwritten while one waits, the campaign list's decoding)

### Done: rules audit 2026-10-09 (`docs/audits/2026-10-09-rules-audit.md`)

Each with its tests named in the audit document.

- [x] What comes with performing an action (XP, infusions, the lost icon), active bonuses by half, elements infused and consumed in one turn, push and pull, Retaliate's timing, Advantage with effect cards, random standees, the long rest as a turn
- [x] Trap legends for all 75 scenarios with traps; monster cards (Shield timing, shared decks, element consumption, heals, disarmed and muddled movement); campaign availability and the Enhancer; the scenario rules the re-audit found wrong
- [x] **Walls** (C2, A2–A4; `WallLineTests`): the line between two tiles' full hexes is a wall — no move, push, melee, loot or adjacency across it; range is counted round walls; a sight line touching a wall or a closed door is blocked; the lines are drawn on the board
- [x] Doors (C3, N1; `DoorRuleTests`, `MapRevealTests`): a character who opens a door goes on with the movement left; a room is the same whichever door it is entered by
- [x] Areas (A8, part of A10; `AreaAttackRuleTests`): mirror images, added targets, the in-range hex; Inferno's room (N5; `InfernoTests`)
- [x] Obstacles never placed to divide the map (C9); a jumping monster doesn't land on a trap mid-route (D9); +1 Target and elements never doubled at the Enhancer (N4)
- [x] #90 Demonic Rift (`DemonicRiftTests`) and #35 Gloomhaven Battlements A (`BattlementsTests`) by the book
- [x] Monster places on the maps corrected against the book in 22 rooms (N2; `MapMonsterPlaceTests`)
- [x] Items, bonuses, solo play and round starts (C8, E7, E12, B4, B6, B7, B8, B11, B12, A11, S-gen; `MoneyTokenTests`, `ItemUseRuleTests`, `SetupRulesTests`, `ChargedBonusTests`, `RestRuleTests`)
- [x] Rule tests through real play on a shared fixture (`Tests/Support/RuleBoard.swift`), the weak tests replaced, a simulator that wins (`VeteranPolicy`, `PlayLedger`)

### Done: scenario rules, cards and classes

The state of every printed scenario rule is in `docs/scenario-book/rules-audit.md`; what each data key does, in `docs/scenario-book/README.md`.

- [x] **Scenario reward: add events** (GH 21, 35, 36, 51, 54) — the decks now start as cards 01–30 and scenario rewards shuffle cards in
- [x] **Events from class unlocks and retirements** (Phase VI)
- [x] **Scenario reward: personal quests** (GH 54, 56, 58, 60, 62): the named quest is completed for whoever holds it; Palace of Ice retires the Seeker of Xorn with its own events (`PersonalQuestTests`)
- [x] **Objectives and escorts stand on the board** (2026-10-09) — hexes written from the scenario book into `Resources/ScenarioMaps/placements/gh.json` (`docs/scenario-book/README.md`) for all 22 scenarios with objectives. Each room mention is its own piece (four altars, not one; three kinds of "Water Pump" no longer collapse into one). Things to destroy (altars, totems, barred doors that open when broken down) are attacked by characters and summons, immune to conditions and never moved; escorts fight on the players' side, are attacked by monsters, and walk to the letter their move names (opening doors, heading for the door on the way while the room is unrevealed); captives and a gate under siege are the monsters' to attack and no one's ally (`ScenarioPlacementTests`)
- [x] **Scenario spawn markers** (2026-10-09) — lettered hexes written for the 17 scenarios whose rules spawn at one; a spawn goes to its letter (or beside it when taken), beside the objective that carries the letter (an imp at its pump, an ooze at its tree), or where a just-destroyed objective stood (a corpse from its grave)
- [x] **Scenario-specific goals** (2026-10-09) — 90 of 95 scenarios now end on the goal the scenario book prints, written as data in `placements/gh.json` (`ScenarioPlacements.Goal`, `BoardCoordinator+Goals`): kill the named enemies (bosses, "all demons"), a number of kills, all *revealed* enemies, tiles to reveal, goal treasure to loot (all of it, or one per character), escorts arriving, escaping through an exit (all at once, or leaving one by one), pressure plates held at once, a hex to end a turn on, and either of two ways; lost on a protected figure's death, a character exhausted away from the exit or before looting, or the wrong enemy killed. #62's Hungry Soul now appears after ten Living Bones (a rule the data lacked). `ScenarioGoalTests`; the per-scenario table is in `docs/scenario-book/README.md`
- [x] **Locked doors** (2026-10-09) — doors a scenario rule keeps shut are locked by data (`placements` `locks`, `BoardCoordinator+Locks`): 33 locks in 12 scenarios (#2, #15, #33, #41, #53, #66, #67, #69, #71, #74, #79, #82), opened by a pressure plate, every character on plates, a round passing, treasure looted or elites killed; doors held open only while a plate is stood on shut again (#66, #67); a locked door carries a padlock, says what opens it, and can't be walked into; pressure plates are drawn. The Bandit Commander still opens #2's doors; a rule now opens a room that sits a corridor past its door (#79). `ScenarioLockTests`
- [x] **Special rules found wrong by the rules audit** (2026-10-09, `docs/scenario-book/rules-audit.md`; `ScenarioSpecialRuleTests`, `MonsterSummonTests`): boss summons bring their player count's number and rank; goal treasure that needs a Loot action (#7, #30, #50, #52, #59, #61); #3's guard arrives as the round begins; #22's altars give the demons hit points, attack, movement and range (they had 1 hit point); push/pull immunity is honoured (#47 Sightless Eye, Elder Drake); #51 The Void's 2 damage lands as each turn ends, on summons too; #84's crystal and #86's villagers are protected, not allies (no heals); each grave of #75 lets out its own Living Corpse; #26's imps appear beside their own pump; #35's allied demons attack the gate; #61's demons are enemies again (`allied` in the data made them fight for the party); #41 is won when the rest have left though one was exhausted on the way; #45/#52 add two cards; the Hungry Soul and Bloated Regent round hit points up; #92's guards arrive with room 2 and the scenario is won with them alive; #90's Living Spirits come once every demon is dead, and killing them wins. Found by the four-seed playthrough on the way: Trample, and a condition given to enemies moved through, pass an invisible enemy by (`testEnemiesMovedThroughLeaveOutTheInvisible`)
- [x] **Rules that wait for something** (2026-10-10; `ScenarioSpecialRuleTests`, `testEveryWrittenRuleRefersToThingsInItsScenario`) — rules written in the placements can wait on the board (`when`: a villager saved, a lock released, treasure looted), set up monsters held back (`later`/`setUp`), pick figures by where they stand (`tile`, `near`), and reach monsters and summons as their turns start. With them: #93 everyone starts immobilized; #86 scouts as rounds begin, Lurkers after the first rescue; #83 the altar's damage and healing, Flame Demons after the Cultists, then 2 damage a turn and Fire strong; #47 3+L damage a round on the first tile once door 1 is open; #45 totems heal monsters within 2; #84 the cave walls come down as rounds 4, 6 and 9 begin; #36 the Prime Demon arrives when the gate falls, which it does after eight rounds; #33 the Icestorm after the last treasure; #41 the middle room's golems and artilleries wake with the plate
- [x] **Standing effects and the brief** (2026-10-10; `ScenarioSpecialRuleTests`, `testTheBriefSaysTheWrittenRules`) — `effects` in the placements change attacks and Shields while something holds (`BoardCoordinator+Effects`), shown in the attack preview too: #42 each vocal chord's penalty (+1 Attack and Advantage for monsters, heal 1 a turn; 1 damage a turn, Disadvantage and −1 Attack for the party); #62 the Hungry Soul's Shield (5 above an elite Living Bones' own, −1 for each other Living Bones); #58 the Harvester's Shield and healing for each bone pile; #87 the Giant Ooze's four Shield tokens. The scenario brief lists the special rules the game enforces in words (`notes`, 30 scenarios), says which treasure needs a Loot action, and no longer calls a protected crystal or villager an ally
- [x] **Three sides, sheltered allies, water** (2026-10-10; `ScenarioSpecialRuleTests`) — `apart` monsters are a third side against the party and every other monster type (#85 Sun Demons, #91 Living Spirits, #92 the city's men, who no longer side with the bandits); #80 Disadvantage and no items until a character has looted a treasure tile; #68 the tree is `sheltered` (no monster attacks it, the party may heal it), suffers its 2 damage only while a Rending Drake is on its tile once revealed, and loses the scenario when it falls; #68 a poisoned character or summon walking into water suffers trap damage; #95 ending a turn in water costs 1+L
- [x] **Monsters that sit a round out** (2026-10-10; `ScenarioSpecialRuleTests`) — `inactive` monster types don't act, can't be attacked or affected, and are moved through but not stopped on (drawn hollow): #61's Oozes and Vipers act in odd rounds, its demons in even ones; #79's Stone Golems are inactive until every pressure plate in play has a figure on it as a turn ends (the plates are written and drawn; (b) and (c) come into play for three and four characters). Fish takes his turn: back to his plate if moved off, then Attack 3 on every adjacent enemy; his death loses #79
- [x] **Boss specials by scenario** (2026-10-10; `ScenarioSpecialRuleTests`, `MonsterSummonTests`) — bosses that go round marked places (`cycles`, `BoardCoordinator+Bosses`): #2 the Bandit Commander jumps to the next locked door in order, however far away, and opens it; #51 the Gloom jumps to the next of three marked hexes before its second special's attack; #48 the Dark Rider isn't set up, appears on the next of six marked hexes as its turn starts, and vanishes after any melee attack. A scenario's own specials replace the stat card's (`specials`: #36 "Move +0, Attack +0"). The Betrayer (#79) summons one elite Giant Viper for two characters, a normal and an elite for three, two elite for four
- [x] **Two starting rooms, and two small ones** (2026-10-10; `ScenarioSpecialRuleTests`) — #50, #58, #85: no more than half the party (rounded up) may start in the same starting room (`splitStart`; the full room's hexes aren't offered); #57 the Infiltrator appears where the marked City Guard fell (a rule's spawn at a letter a dying monster carried goes to its hex); #81 the Colorless pays Dark for its Night Demon and Light for its Sun Demon (a special's own element costs are now paid); #35/#36/#84 a monster that can get within range of the gate or the crystal this turn focuses on it (`focusFirst`)
- [x] **Spirits, cleansing water and eggs** (2026-10-10; `ScenarioSpecialRuleTests`) — #70 Living Spirits can't be damaged in any way (conditions still apply) and one is banished each time a demon dies (the nearest to the killer: the book lets the players pick); #87 a character ending a turn on a water hex of the main room is cleansed once — the tile goes, Shield 2 against Ooze attacks, no more Poison; #46 the Winged Horror lays an egg for each character (2+L/2 hit points, attackable) and, with its other special, hatches every egg into a normal Night Demon
- [x] **Vault of Secrets** (2026-10-10; `ScenarioSpecialRuleTests`) — #77's City Guards march: "Move 2" toward the nearest pressure plate each turn in place of their card's movement (`march`, `BoardCoordinator+March`), opening door 1 by walking into it, then the rest of their card; a guard on a plate loses the scenario (`lostIfStands`); a guard arrives at (b) or (c) when the left or right treasure tile is looted
- [x] The scenario book is linked from `docs/scenario-book/README.md` (2026-10-10) rather than stored: the PDF is 319 MB, over GitHub's limit
- [x] **Conditions that fell back on the character**: a target printed beside a condition (Crippling Offensive, Airborne Toxin, Mass Extinction) or only in its text (Negative Energy, Virulent Strain, Rock Tunnel) now reaches the right figures; a negative condition with no target never lands on the character (`BoardRulesRegressionTests`)
- [x] **Locked classes' card text and item text**: the spoiler labels weren't loaded, so those texts were missing (`LabelTests`)
- [x] **"Enemies moved through" attacks** (Trample, two Mindthief cards) attack every enemy passed over in the half's move (`testTrampleAttacksEveryEnemyJumpedOver`)
- [x] **Printed attack bonuses and round bonuses**: per-target text bonuses (Backstab, Flanking Strike, Single Out, Sinister Opportunity, Trickster's Reversal, Submissive Affliction, Perverse Edge, XP for each enemy targeted) and this round's bonuses (Wall of Doom, Heaving Swing, Forceful Storm, Enhancement Field, Eye for an Eye, Trickster's Reversal's negation) (`ChargedBonusTests`)
- [x] **Mindthief augments**: an augment is no longer performed when played; while its card is active it shapes every melee attack (+2, conditions, Shield/Retaliate for the round, Heal 2 self, Frozen Mind's ice), and a new augment discards the old (`BoardRulesRegressionTests`); Silent Scream's targeted heal and Phantasmal Killer's kill still need doing
- [x] **Halves played as steps**: groupings and text that wraps actions are opened into separate steps, so a move or a target choice inside them is performed and waited for (Crater's Move 4 and Unstable Upheaval's Shield 2 were never performed; a grouping with a move skipped the next action). Printed text the board now performs: recover all lost cards (Reviving Ether), disarm an adjacent trap (Thief's Knack), damage around the character, after a move or around the target (Crater, Rumbling Advance, Unstable Upheaval, Massive Boulder), loot every hex entered (Swift Bow), Shield for all allies (`BoardRulesRegressionTests`)
- [x] **Traps and obstacles from cards**: Proximity Mine (with its XP when an enemy springs it), Volatile Concoction's poison trap, Avalanche's two obstacles, placed hex by hex with VoiceOver choices (`BoardRulesRegressionTests`)
- [x] **Cards' X values** were played as 0: hexes moved and damage inflicted this turn (Balanced Measure), hexes moved by the action (Hook and Chain), missing hit points (Resolute Stand, From the Brink), cards lost (Growing Rage, Final Fight), current hit points (Glass Hammer, which then drops to 1), summoned allies (Strength in Numbers) (`testBalancedMeasureCountsTheTurn`, `testTheBerserkersXValues`); the Berserker's "you may suffer up to N damage" asks how much, and X is what was suffered (`testFlurryOfAxesAttacksWithTheDamageSuffered`)
- [x] **Allies recovering cards**: Reinvigorating Elixir, Volatile Concoction (with Ice: two), with an ally picker and the discard picker (`BoardRulesRegressionTests`)
- [x] **Impaling Eruption** attacks every enemy on the straight line to its target (`testImpalingEruptionHitsEveryEnemyOnTheWay`)
- [x] **Element bonuses printed as text** (Earthen Clod's Immobilize, Crater's Push 2, Unstable Upheaval's "all enemies up to two hexes away", XP): read into the attack when the element is consumed (`testEarthenClodsEarthImmobilizes`)
- [x] **Provoking Roar**: enemies attacking an ally beside the Brute this round attack the Brute instead (`ChargedBonusTests`)
- [x] **Actions performed by another figure**: Possession (an ally attacks or moves) and Parasitic Influence (an enemy moves) let the player choose who and control it (`testPossessionLetsAnAllyAttack`, `testParasiticInfluenceMovesAnEnemy`); such actions are never mistaken for the character's own; Sinister Opportunity's Move 3 no longer absorbs the enemy's Move 1
- [x] Forced enemy attacks (Submissive Affliction): by the Mindthief FAQ a flat Attack 2 at the monster's base range +0, from the monster deck with its stat-card effects; the Mindthief picks another enemy as the target (`testSubmissiveAfflictionMakesAnEnemyAttackAnother`). Sinister Opportunity's forced move now happens after the Scoundrel's move, ending beside them (`testSinisterOpportunityMovesAnEnemyBesideTheScoundrel`)
- [x] **Dirt Tornado** muddles every figure in its area, allies included (`testDirtTornadoMuddlesEveryoneInTheArea`)
- [x] **Destroying an adjacent obstacle** (Rock Tunnel, Explosive Punch), the player picking which (`testRockTunnelDestroysAnAdjacentObstacle`)
- [x] **Crackling Air**: +1, or +2 by consuming Air (`testCracklingAirAddsTwoByConsumingAir`)
- [x] **Heaving Swing** pushes into obstacles: destroyed, 2 damage, XP +1 (`testHeavingSwingPushesIntoAnObstacle`)
- [x] **One-ally condition targets** ("allyAffectAdjacent", "allyAffectRange:3") ask which ally; "selfAlliesAffectRange:4" keeps its range (`testAOneAllyConditionAsksWhichAlly`)
- [x] **Heals, shields and retaliates for allies** ("all adjacent allies", "self and all allies within range 4", "one adjacent ally") reach the allies instead of only the character (`testHealsReachTheAllies`)
- [x] **Element consumes printed as their own step**: an independent reward (Wretched Creature's curse, Armor of the Night's heal) happens when paid; a modifier of the action before it (Natural Remedy's +1 Heal, +1 Range; Concealed Dominance's area) rides on that action (`testAConsumeStepGivesWhatItPrints`, `testAModifierConsumeBelongsToTheActionBeforeIt`). Approximate: Smoke Step and Stone Fists, whose reward modifies two actions, give it as separate actions
- [x] **The Doomstalker's dooms**: a doom half asks for an enemy and puts the character's token on it (a marker on the monster, saved with the game, shown on its token); every doom's effect while it lasts (+Attack for whom the card says, Pierce, advantage, Curse, Predator and Prey's range gap, Crippling Noose's −1 Attack/Move/Range, Race to the Grave, Sap Life, Inescapable Fate's countdown) and on death (Felling Swoop, Vital Charge, Detonation, Darkened Skies, Nature's Hunger, Rising Momentum); one doom at a time, two on one target with Inescapable Fate; Rain of Arrows' and Frightening Curse's tops, Expose, Relentless Offensive, Impending End, Swift Trickery, Press the Attack, Wild Command, Lead to Slaughter (`DoomTests`)
- [x] **Persistent bonus charges**: the starting classes' charged cards (Warding Strength, Juggernaut, Opposing Strike, Backup Ammunition, Single Out, Smoke Bomb, Cull the Weak, Spring the Trap, Frost Armor, Crackling Air, Engulfed in Flames, Cold Front, Potent Potables) mark a charge per use, give their slot XP and leave the active area when used up (`ChargedBonusTests`)
- [x] Locked classes' charged cards: Immortality, Purifying Aura, Angelic Ascension, Voice of the Night, Cauterize, Master Physician, Defiance of Death, Nightfall, Beacon of Light, Fortified Position (`ChargedBonusTests`)
- [x] **Start- and end-of-turn bonuses**: Lumbering Bash and Triage (a heal at the start of the turn), Auto Turret (an attack at the end), Gas Canister (an ally recovers a card at the end), as steps of the turn (`ChargedBonusTests`)
- [x] Nature's Lift and Foul Wind: consume Air (when there) for +2 Range on ranged attacks / +1 Attack, a charge each time (`testNaturesLiftConsumesAirForRange`)
- [x] Intervening Apparitions, Unending Chant, Blood Hunger (`ChargedBonusTests`)
- [x] Stone Pummel: a melee attack with an obstacle beside the Cragheart destroys it for +3, a charge each time (`testStonePummelDestroysAnObstacleForThree`)
- [x] **Charged cards needing a choice**: Vengeful Barrage (Attack 3 back on each source of damage; its round half +1 Attack), Grim Bargain (Curse an ally within Range 2 for two more targets, declinable; its round half doubles the next attack), Wings of the Night (Move 2 before each attack), Black Knives and Claws of the Night (an attack after an attack or move while invisible), Eyes of the Night (advantage, see invisible), Dancing Shadows and Terror Blade (attackers have disadvantage this round) (`ChargedBonusTests`)
- [x] **Items during board turns** (Phase VI: about 110 of 150 items play on the board)
- [x] **Monster ability text**: traps (Archers, Flame Demon), damage around the monster or its target (Ancient Artillery, Night Demon, Flame Demon, Savvas Lavaflow), +2 against a flanked target (Hound, Giant Viper), disadvantage against the Giant Viper this round, the Harrower's heal per target damaged (`MonsterTextTests`)
- [x] **Cultists' "on death" attack**: made from where the Cultist fell, right after the attack that killed it, never on its own turn (`testACultistAttacksAsItDies`)
- [x] Element bonuses inside a monster's Shield/Retaliate: the Lurker's "consume Ice: Shield 2 instead" (`testALurkersIceShieldReplacesItsShield`)
- [x] **The Ooze splits** with its current hit points (`testAnOozeSplitsWithItsHitPoints`)
- [x] The Deep Terror's attack summons another beside the target (`testADeepTerrorSummonsBesideItsTarget`)
- [x] **Boss specials printed as text**: the Bandit Commander's "move to next door and reveal room" (Barrow Lair), the Captain of the Guard's +1 Attack for all monsters this round, the Merciless Overseer's "all Scouts act again" (`testTheBanditCommanderHeadsForTheNextDoor`); the rest (Elder Drake's perch, Prime Demon's throne, the Betrayer's mind control) are still the players'
- [x] **"+1 Target" on attack modifier cards** (6 perk cards): when the character's attack ability ends, another enemy in range it hasn't attacked is offered (its own draw; Skip declines); not for area attacks (`testAPlusOneTargetCardAddsATarget`)
- [x] **Scenario-rule damage** (Scenario 51's summoners, 60's late rounds) goes through the lose-cards choice on the board, before play continues (`testScenarioRuleDamageCanBeNegated`)
- [x] **Battle goals are dealt again** if the app quits between dealing and setting out: dealt goals are saved and kept until the scenario ends (`testDealtBattleGoalsSurviveARelaunch`)
- [x] **Rule question settled**: a ranged multi-target monster first attacks its focus without disadvantage, then maximizes targets, then avoids disadvantage on the others, then moves least (GH 1st edition order; Jaws of the Lion / 2nd edition put more targets first). Base Gloomhaven is followed

### Rules audit 2026-10-08 — fixed

Combat & attack modifiers
- [x] **Null/curse draws still apply added effects** (conditions, push/pull); a killed target gets none
- [x] **Advantage/disadvantage with rolling cards** — advantage adds a rolling card to the other card (both rolling → keep drawing); disadvantage ignores rolling cards; advantage + disadvantage = one normal draw (`CombatResolver.drawModifiers/selectModifierCards`)
- [x] **Perk cards had value 0** — edition-data cards now decode with their printed value (`AttackModifier.standard`), so "+3" perks and "remove two -1" perks work
- [x] **Empty modifier deck reshuffles** instead of returning nothing (previously softlocked the draw overlay)
- [x] **Bless/Curse** — real ×2/null cards shuffled into the deck (not entity tokens), never trigger the end-of-round reshuffle, max 10 undrawn; curse/bless from attacks and abilities route to the right deck
- [x] **Scenario `amAdd` cards** shuffled in (were appended to the bottom), with real values; scenario −1s survive reshuffles; all scenario cards removed when the scenario ends
- [x] **Pierce/push/pull on modifier cards** applied
- [x] **Retaliate** — per-source range, no longer accumulates each round on monsters; only if the target survives
- [x] **Shield/retaliate stack** for characters; persistent vs round bonuses
- [x] **Damage negation (lose cards)** offered for every damage source, not just monster attacks
- [x] **Item −1 penalties** (e.g. Hide Armor) add −1 cards for the scenario; "ignore negative item / scenario effects" perks honoured

Monsters
- [x] **Ability deck never advanced** — every type revealed the same card every round, and the executor ran a different card than the one shown; shuffle icon now reshuffles at end of round
- [x] **Card attack/move values, conditions, pierce, target, area** now applied; cards without Move/Attack don't move/attack; Attack 0 still attacks
- [x] **Stat-card effects** (poison, pierce, target, advantage) apply to every attack; `baseStat` merged (boss immunities, imp movement, etc.); expression stats (`1+C`, `8xC`) evaluated without crashing
- [x] **Monster heal, self/ally/enemy conditions by specialTarget, push, sufferDamage, loot, summon (doesn't act that round, no money token), element consume bonuses, boss special structured actions**
- [x] **Focus**: invisible figures block movement but can't be focused; summons win focus ties over their summoner; traps/hazards avoided unless the only route; ranged monsters avoid disadvantage first and multi-target/area attacks seek extra targets
- [x] **Flying and jumping monsters**; closed doors block monsters and summons
- [x] **Area-of-effect patterns** decoded in the board's odd-row grid (card previews too); ranged patterns placed within range; invisible figures never hit
- [x] **Allied monsters** fight hostile monsters (factions)
- [x] **Revealed/spawned monsters act in the round they appear** (after the revealing turn if their initiative already passed)

Line of sight & movement
- [x] **LOS**: only walls and off-map hexes block (obstacles do not); pointy-top geometry
- [x] **Jump** passes obstacles/figures/terrain except the last hex; **fly** ignores terrain; characters may enter traps
- [x] **Traps/hazards trigger on every hex entered** (moves and push/pull), trap damage **2 + L**, hazard **½ trap damage (GH)**, no start-of-turn hazard damage
- [x] **Doors** open when a character enters the door hex at any point of a move; no tap-to-open shortcut; corridor connectors are part of the same room (not doors)

Turns, rests & conditions
- [x] **Stun / immobilize / disarm enforced for characters**, summons and escorts
- [x] **Long rest** heals 2 once (poison rules), refreshes spent items; summons of a resting character still act
- [x] **Heal** removes poison (blocking the heal) and wound
- [x] **Summon/escort/monster conditions** tick exactly once per figure turn, at that figure's own turn (wound was doubled for summons, escort conditions never progressed, monsters ticked as a group)
- [x] **Reapplying a condition refreshes its duration**
- [x] **Exhaustion** (0 HP or cards) removes the figure and its summons; exhausted characters skip their turn
- [x] **Short rest** commits before revealing the lost card; re-pick costs 1 damage
- [x] **Element** consumes need every listed element; infusing a waning element renews it; monsters consume once per type
- [x] **Card routing** — persistent/round bonuses to the active area (round bonuses leave at end of round), lost-icon halves to the lost pile, default Attack 2 / Move 2 cards always discarded; either card may be the top half and either half may go first
- [x] **Attack conditions no longer applied to the attacker**; failed attacks/summons don't block the rest of the card half
- [x] **Player area attacks and "attack all adjacent enemies"** resolve each target separately
- [x] **Initiative ties**: characters before monsters (incl. long rest at 99); character ties use the second card

Scenario
- [x] **Scenario level applied at scenario start** (was never applied — every monster was level 1) and rounds **up**; gold conversion table incl. L7 = 6
- [x] **Scenario rule engine**: `%` expressions crashed 8 scenarios; rules no longer re-fire on every kill; `start` rules run at round start, others at round end; C/F substitution; `all` identifier
- [x] **Monsters come from the scenario data, positions from the map** — bosses are bosses, every starting monster gets a piece; rule spawns are placed on the board; standee limits enforced; level-modified names (`living-corpse:+2`)
- [x] **Map coins and treasure chests** can be looted (end of turn and Loot X with LOS), money tokens worth the gold conversion; treasure rewards go to the looter; no looting by just walking through
- [x] **Victory resolves at the end of the round**; allies don't block "kill all enemies"; defeat when all characters are exhausted
- [x] **Scenario end**: exhausted characters still get bonus XP, rewards and battle goals on a success; gold and XP kept on a failure; lost cards recovered
- [x] Revealed rooms update `scenario.revealedRooms` (room-gated rules now fire); rooms opened by scenario rules open on the board
- [x] **Doors reveal their own room** (map files repeat tile names; the first copy was often an empty stub — 33 doors in 22 maps); re-entering a revealed room doesn't respawn monsters or re-arm traps
- [x] **Starting room** from the scenario data when the map is rooted elsewhere (GH 12); starting hexes padded when a map has fewer than the party size

Found by the scenario simulator (2026-10-08)
- [x] **Split starting areas** (GH 36, 50, 58, 85): every tile with starting hexes is revealed at setup — the party, and room 1's monsters, were squeezed into one tile with monsters standing on starting hexes; setup never puts a monster on a starting hex
- [x] **Turn engine ran off the main actor** — player attacks and every async turn function (monster/summon/escort turns, attacks, moves) now run on the main actor; they raced the UI and made games non-deterministic
- [x] **Damage negation could lose a card played this round** (duplicating it at the end of the turn); only hand cards not played this round can be lost (p.22)
- [x] **Exhausted during its own turn** (e.g. by retaliate) ends the character's turn instead of wedging it on a default action
- [x] **Infusions and XP printed on an attack** (Crushing Grasp's earth, Thief's Knack's XP) were never applied; XP inside other actions (Hook Gun's loot) too; block infusions were applied twice
- [x] **Immobilize gained mid-move** (bear trap) ends the move; pushes continue
- [x] Fixed iteration order wherever figures or hexes are visited one by one (focus ties, heal targets, death sweeps, revealed monsters, area targets), so equal choices don't depend on dictionary order

Monsters (review pass)
- [x] Boss special abilities drive movement/attacks; element-consume blocks apply heal/self-damage/retaliate/infusions; consumption only when a monster acts
- [x] "Attack all adjacent enemies" / "all attacks on one enemy"; melee area reach; Dark Rider X / Overseer V stats; scenario stat-effect attack actions; "attackers gain disadvantage"; monster initiative in focus tie-breaks
- [x] One ability card per type per round (round-start spawns drew two)

Turn flow (review pass)
- [x] Moves/teleports finish before the next action; default Move/Attack can't wedge the turn; standalone push/pull pick their own targets; leaving the board stops in-flight turns; multi-figure summons

Scenario rewards (2026-10-08)
- [x] **Item rewards** (26 GH scenarios incl. solo): each copy goes to one participating character of the players' choice who doesn't already own one (picked on the conclusion sheet); several copies go to different characters; a copy no one can take goes to the city's supply
- [x] **Item designs** (GH 11, 12, 65) add the item to the city's supply
- [x] **Collective gold** (GH 55, 83, 89) split however the players choose on the conclusion sheet (even split by default)
- [x] **Battle goal checkmarks** (GH 41, 91) for every participating character
- [x] **Character unlocks** (GH 44, 54, 56, 62) unlock the class
- [x] **Choose a location** (GH 13: one of 15, 17, 20) unlocks only the chosen scenario
- [x] **Shop stocked reward items from the start** — items 96–150 (scenario rewards, treasures, solo items) had no prosperity level and were for sale at prosperity 1; the shop ignored unlocked items (designs, random draws) and sold more copies than exist. It now offers prosperity items up to the prosperity level plus unlocked items, with stock limited to the item's copies

### Full audit 2026-10-09 — fixed (gameplay, rules, UI, performance)

Combat & conditions
- [x] Attack modifier cards' self effects reach the attacker: a positive condition (the Scoundrel's Invisible) goes to the attacker, not the target; "Heal X, self", "Shield X, self" (for the round), element infusions and "refresh an item" are applied (`CombatEffectsTests`)
- [x] Advantage/disadvantage compare the attacks the two cards make (on Attack 1, +2 beats ×2); a null is always the worst (`testAdvantageComparesTheAttacksTheCardsMake`)
- [x] Wound damage at the start of a turn, and damage printed outside attacks (Flame Demon, Massive Boulder, Crater, Unstable Explosives), can be negated by losing cards like any damage (p.22)
- [x] A monster entering play no longer wipes the round bonuses (a consumed element's Shield/Retaliate) of the others of its type
- [x] The ten Bless cards are shared by every deck, the ten player Curses by the players' decks (p.23)

Turns & rounds
- [x] Skipping or taking back a summon's placement leaves no phantom summon (counted for X, kept the card active, hid Cancel for the rest of the scenario)
- [x] A basic Attack 2 / Move 2 keeps the turn's start/end bonuses (Lumbering Bash's heal, Auto Turret's attack); the button only shows while usable, with its real value (Versatile Dagger)
- [x] Round bonuses end before the short rest, so those cards can be recovered (p.30)
- [x] Stunned and resting characters still loot at the end of their turn; a skipped target choice drops the item condition that rode on it
- [x] An enemy within the Halberd's reach counts as the attack's target (its augments, XP and infusions are paid)
- [x] Two chosen cards can still be changed before confirming (a third card replaces the second)

Monster & summon AI
- [x] Melee areas reaching further than 1 hex focus on enemies their pattern can cover (Harrower Infester, Deep Terror, Earth/Wind Demons, Savvas)
- [x] Flying monsters may attack from over obstacles; an ally where a route runs out no longer shortens the move; a summon stopped by a trap attacks only what it reaches; the Bandit Commander's door run respects Immobilize and difficult terrain (`AIRulesTests`, `MonsterTextTests`)

Campaign, town & saves
- [x] New Campaign starts from nothing (prosperity, reputation, unlocks, looted treasures, log, events all carried over before) (`testANewCampaignCarriesNothingOver`)
- [x] Prosperity level 8 at 50 checkmarks; battle goal checks capped at 18; scenario reputation capped at ±20
- [x] Shop prices follow reputation (p.48); selling asks first and shows the half price; recruits start with 15 × (L + 1) gold and their level's XP, at most the prosperity level; dismissing a veteran asks first
- [x] Random item design and random side scenario treasures are drawn (20 of the 75 GH treasures did nothing)
- [x] Difficulty, monster initiatives, placed traps and a decided outcome are saved; a failed save is reported; saves missing fields still load
- [x] Undo stays in town: on the board it stranded turns (a half-finished move never completed) and it could undo a finished scenario
- [x] Quitting while placing characters sets out again from town without applying the setup twice; a resolved city/road event isn't owed again after a relaunch

Performance & robustness
- [x] Leaving or restarting the board resumes every waiting prompt and animation and stops stale turn tasks (they hung forever, or woke up and played on the next board) (`BoardTeardownTests`)
- [x] Token portraits keyed by name (a freed image's address was reused, so a new monster could wear a dead one's face); decoded images, map tiles, the scenario brief and sound files are cached within bounds; no snapshot is encoded on every change during play
- [x] UI: Return in the damage choice confirms the chosen card and never exhausts by itself; Escape closes a card preview rather than cancelling the choice under it; a placed character can move before the scenario begins; names come from labels; tappable cards are buttons to VoiceOver (`testTappableViewsAreButtons`)

### iPad playthrough 2026-10-09 (`docs/playthroughs/2026-10-09-ipad/`)

- [x] Skipping a persistent half still puts the card in the active area (Backup Ammunition)
- [x] Skipping a loss half still loses the card (Crater's bottom)
- [x] Event discards before the first scenario: no hand to pick from, nothing discarded, result says otherwise
- [x] Event-unlocked scenarios (`manualScenarios`) missing from the town list
- [x] A completed initial scenario is still listed as open
- [x] The last-draw panel carries over into the next scenario
- [x] Short-rest re-pick offered more than once — it was already disabled after one use, just not visibly (restyle below)
- [x] Element consumption is the player's choice: each element bonus on a step is a toggle, taken unless turned down
- [x] Move 0 with a rider (Rumbling Advance): tap the character to stay
- [x] A new campaign is saved once a recruit keeps a quest (it was already saved on leaving the app and at each round's start)
- [x] Verify #2's "3 Curses each" start rule (`testScenario2CursesAddedOnceNotPerKill`)
- [x] Learning tips that come up together are numbered ("2 of 4") with Next, so the next one isn't a surprise
- [x] Resting tip comes with the first rest offer (short rest, or long rest at card choice)
- [x] No rest prompts once the scenario is won
- [x] "Special Effect" buttons should name what the half does
- [x] Warn when a move's path opens a door
- [x] Heal log on a poisoned figure ("for 0" → "removes Poison")
- [x] Town header says "In town" as soon as a recruit joins
- [x] Easy hint repeats itself
- [x] Envelope quest rewards; −1 cards on item tiles
- [x] Road Event header icon
- [x] Short/Long Rest and gold-sharing dialogs in the board's look
- [x] Hold "Unlocks the …" (or "Opens Envelope X") in the quest picker to learn about it
- [ ] Game option: go back to the start of the previous turn
- [x] The last scenario's elements stayed lit when the next one began
- [x] Disabled board buttons looked as ready as any other (now dimmed)
- [x] A quest's requirement showed the data's shorthand "(scenario number > 51)"
- [ ] Playthrough tests (ScenarioSimulator policies) make moves no player would; give some scenarios set, realistic moves and actions that replicate a real playthrough (user, 2026-10-09)
- [x] Performance and memory-leak testing (user report: buttons unresponsive after the app is open a while, 2026-10-09). A soak run (`SIMCTL_CHILD_GLAVEN_SOAK=1`, `SoakDriver`) played GH #1–4 for hours on the iPad simulator; `leaks` found none and memory, node and object counts stayed flat; finished boards are freed back in town and town relayout is ~4 ms. Fixed: the board view kept drawing the first scenario's scene (moves not shown, a second scene alive); a move whose animation never reports back left the turn and every board button waiting forever (now ends once overdue); a push whose target left the board mid-choice never resumed the attack; a monster's push dropped Pause and fast-forward for the rest of its turn
- [ ] Prompts (`pendingModifierDraw`, `pendingDamage`, `pendingItemUse`, `pendingFigureChoice`) are overwritten, not resumed, if a second one is asked while one waits — the first task would hang. Not seen in play or the all-scenarios run; resume the old one with its default if it ever is
- [ ] `refreshCampaigns` decodes every campaign file on each save (~0.5 ms a campaign); cache entries by modification date if campaign lists grow large
