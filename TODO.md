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
- [x] Unit tests (480+ tests: unit, e2e, rulebook verification, headless scenario simulation)
- [x] **Deterministic simulation** — every shuffle and random draw goes through the seedable `GameRandom`; seeded games replay identically across processes
- [x] **Golden turn logs** — seeded games (GH 1, 2, 4) compared turn by turn against hand-checked transcripts in `Tests/Golden/` (`GOLDEN_RECORD=1` re-records)
- [x] **Full playthroughs** — `ScenarioSimulator` plays scenarios to the end with a tactical policy, checking every attack (LOS, enemies, visibility), every move (adjacency, walls, obstacles, doors, end hex) and the board after each step; outcomes must be a legitimate victory or defeat
- [x] **CI** — `.github/workflows/tests.yml`: the suite on push/PR; nightly, every main GH scenario to the end with 4 seeds

---

## Missing Gloomhaven Rules

Full rules audit against the official Gloomhaven v1 rulebook and the 95 main GH scenarios. Last updated 2026-10-08.

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

### Remaining gaps

- [x] **Scenario reward: add events** (GH 21, 35, 36, 51, 54) — the decks now start as cards 01–30 and scenario rewards shuffle cards in
- [x] **Events from class unlocks and retirements** (Phase VI)
- [ ] **Scenario reward: envelopes** (GH 58, 60: envelope X) — there's no envelope or sealed-content state to open
- [x] **Scenario reward: personal quests** (GH 54, 56, 58, 60, 62): the named quest is completed for whoever holds it; Palace of Ice retires the Seeker of Xorn with its own events (`PersonalQuestTests`)

- [x] **Objectives and escorts stand on the board** (2026-10-09) — hexes written from the scenario book into `Resources/ScenarioMaps/placements/gh.json` (`docs/scenario-book/README.md`) for all 22 scenarios with objectives. Each room mention is its own piece (four altars, not one; three kinds of "Water Pump" no longer collapse into one). Things to destroy (altars, totems, barred doors that open when broken down) are attacked by characters and summons, immune to conditions and never moved; escorts fight on the players' side, are attacked by monsters, and walk to the letter their move names (opening doors, heading for the door on the way while the room is unrevealed); captives and a gate under siege are the monsters' to attack and no one's ally (`ScenarioPlacementTests`)
- [x] **Scenario spawn markers** (2026-10-09) — lettered hexes written for the 17 scenarios whose rules spawn at one; a spawn goes to its letter (or beside it when taken), beside the objective that carries the letter (an imp at its pump, an ooze at its tree), or where a just-destroyed objective stood (a corpse from its grave)
- [x] **Scenario-specific goals** (2026-10-09) — 90 of 95 scenarios now end on the goal the scenario book prints, written as data in `placements/gh.json` (`ScenarioPlacements.Goal`, `BoardCoordinator+Goals`): kill the named enemies (bosses, "all demons"), a number of kills, all *revealed* enemies, tiles to reveal, goal treasure to loot (all of it, or one per character), escorts arriving, escaping through an exit (all at once, or leaving one by one), pressure plates held at once, a hex to end a turn on, and either of two ways; lost on a protected figure's death, a character exhausted away from the exit or before looting, or the wrong enemy killed. #62's Hungry Soul now appears after ten Living Bones (a rule the data lacked). `ScenarioGoalTests`; the per-scenario table is in `docs/scenario-book/README.md`
- [ ] Goals not checked yet, each needing a mechanic first: #26 cleansing a water pump, #54 charging the Staff of Xorn, #76 destructible walls, #90 the altar crossing and the rift, #55 (random dungeon, no map). Checked without a prop the book uses: #69 the doll, #88 the claw, #82 removing an artifact
- [ ] Losses not checked yet: #44 a captive's death, #68 the tree's, #74 the ship filling with water, #77 a City Guard on a pressure plate, #78 the sacrifice, #79 Fish's death, #54, #90
- [x] **Locked doors** (2026-10-09) — doors a scenario rule keeps shut are locked by data (`placements` `locks`, `BoardCoordinator+Locks`): 33 locks in 12 scenarios (#2, #15, #33, #41, #53, #66, #67, #69, #71, #74, #79, #82), opened by a pressure plate, every character on plates, a round passing, treasure looted or elites killed; doors held open only while a plate is stood on shut again (#66, #67); a locked door carries a padlock, says what opens it, and can't be walked into; pressure plates are drawn. The Bandit Commander still opens #2's doors; a rule now opens a room that sits a corridor past its door (#79). `ScenarioLockTests`
- [x] **Special rules found wrong by the rules audit** (2026-10-09, `docs/scenario-book/rules-audit.md`; `ScenarioSpecialRuleTests`, `MonsterSummonTests`): boss summons bring their player count's number and rank; goal treasure that needs a Loot action (#7, #30, #50, #52, #59, #61); #3's guard arrives as the round begins; #22's altars give the demons hit points, attack, movement and range (they had 1 hit point); push/pull immunity is honoured (#47 Sightless Eye, Elder Drake); #51 The Void's 2 damage lands as each turn ends, on summons too; #84's crystal and #86's villagers are protected, not allies (no heals); each grave of #75 lets out its own Living Corpse; #26's imps appear beside their own pump; #35's allied demons attack the gate; #61's demons are enemies again (`allied` in the data made them fight for the party); #41 is won when the rest have left though one was exhausted on the way; #45/#52 add two cards; the Hungry Soul and Bloated Regent round hit points up; #92's guards arrive with room 2 and the scenario is won with them alive; #90's Living Spirits come once every demon is dead, and killing them wins. Found by the four-seed playthrough on the way: Trample, and a condition given to enemies moved through, pass an invisible enemy by (`testEnemiesMovedThroughLeaveOutTheInvisible`)
- [ ] #95's door 1 isn't locked: its key is the six numbered tokens, which aren't modelled
- [ ] **Scenario special rules** beyond goals, not built (the notes in `docs/scenario-book/gh-scenario-rules.md` list every one): the wind (#71), rolling boulders (#73), rising water (#74), the current (#88), sleeping drakes (#71), monsters not set up until a trigger (#35, #36, #41, #83, #86), monster groups that act on alternate rounds (#61), several boss specials; a monster that replaces a dead one (#57) should appear where it fell
- [ ] Objective rules still approximate (each noted in `docs/scenario-book/README.md`): #44 losing a card to save a captive and freeing one (so a captive's death doesn't lose yet); #68 the tree's damage stopping once no Rending Drake is on the M tile (so its death doesn't lose yet); #75 graves are attacked, not dug up with movement; #38 the Orchid heads for the nearest enemy, not the shaman on the D tile; #36 the Prime Demon's arrival and the gate's eight-round timer; #26 cleansing a pump; #79 Fish's turn and fate; #84 losing a card to spare the crystal and its timed corridors; #86 Lurkers are set up from the start; #35/#36/#84 monsters should prefer the door/crystal when they can reach it
- [ ] An objective drawn over several hexes (a three-hex tree, a two-hex sarcophagus) is one piece on its first hex: it can only be attacked from next to that hex
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
- [ ] **Moving in a loop**: moves pick a destination, so a move can't end where it started; Feedback Loop's muddle (which needs that) can't happen yet
- [x] **Heaving Swing** pushes into obstacles: destroyed, 2 damage, XP +1 (`testHeavingSwingPushesIntoAnObstacle`)
- [x] **One-ally condition targets** ("allyAffectAdjacent", "allyAffectRange:3") ask which ally; "selfAlliesAffectRange:4" keeps its range (`testAOneAllyConditionAsksWhichAlly`)
- [x] **Heals, shields and retaliates for allies** ("all adjacent allies", "self and all allies within range 4", "one adjacent ally") reach the allies instead of only the character (`testHealsReachTheAllies`)
- [x] **Element consumes printed as their own step**: an independent reward (Wretched Creature's curse, Armor of the Night's heal) happens when paid; a modifier of the action before it (Natural Remedy's +1 Heal, +1 Range; Concealed Dominance's area) rides on that action (`testAConsumeStepGivesWhatItPrints`, `testAModifierConsumeBelongsToTheActionBeforeIt`). Approximate: Smoke Step and Stone Fists, whose reward modifies two actions, give it as separate actions
- [x] **The Doomstalker's dooms**: a doom half asks for an enemy and puts the character's token on it (a marker on the monster, saved with the game, shown on its token); every doom's effect while it lasts (+Attack for whom the card says, Pierce, advantage, Curse, Predator and Prey's range gap, Crippling Noose's −1 Attack/Move/Range, Race to the Grave, Sap Life, Inescapable Fate's countdown) and on death (Felling Swoop, Vital Charge, Detonation, Darkened Skies, Nature's Hunger, Rising Momentum); one doom at a time, two on one target with Inescapable Fate; Rain of Arrows' and Frightening Curse's tops, Expose, Relentless Offensive, Impending End, Swift Trickery, Press the Attack, Wild Command, Lead to Slaughter (`DoomTests`)
- [ ] Frightening Curse's doom: the adjacent enemies' Move 1 "with you controlling" is a push away from where it died, not a chosen hex
- [ ] Traps that do more when sprung (Detonation: 2 damage to enemies beside it; Flight of Flame: Wound them) are placed as plain traps
- [ ] Impending End's top ("kill the target if it has 2 hit points or fewer after the attack") and Darkened Skies' top (Attack 3 on all enemies within Range 3, XP per two) are still the players'
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
- [x] **Boss specials printed as text**: the Bandit Commander's "move to next door and reveal room" (Barrow Lair), the Captain of the Guard's +1 Attack for all monsters this round, the Merciless Overseer's "all Scouts act again" (`testTheBanditCommanderHeadsForTheNextDoor`); the rest (Elder Drake's perch, Prime Demon's throne, the Betrayer's mind control, Winged Horror's eggs) are still the players'
- [ ] **Icy terrain** — no forced-movement mechanic
- [ ] **Plague / Enfeeble** (FH) — no mechanics
- [ ] **Multi-hex obstacles** — one overlay per hex
- [ ] **Random dungeon mode**
- [ ] **Pathfinding visualization** — no debug overlay for monster movement decisions
- [x] **"+1 Target" on attack modifier cards** (6 perk cards): when the character's attack ability ends, another enemy in range it hasn't attacked is offered (its own draw; Skip declines); not for area attacks (`testAPlusOneTargetCardAddsATarget`)
- [x] **Scenario-rule damage** (Scenario 51's summoners, 60's late rounds) goes through the lose-cards choice on the board, before play continues (`testScenarioRuleDamageCanBeNegated`)
- [x] **Battle goals are dealt again** if the app quits between dealing and setting out: dealt goals are saved and kept until the scenario ends (`testDealtBattleGoalsSurviveARelaunch`)
- [ ] Latent (no GH card triggers them today): an action that waits (printed "suffer X damage", a target choice) nested inside a box/concatenation step lets the outer step advance before it; a consume step with two rewards that each wait stops after the first. FH: Wound's deferred damage now lands after Regenerate's heal
- [x] **Rule question settled**: a ranged multi-target monster first attacks its focus without disadvantage, then maximizes targets, then avoids disadvantage on the others, then moves least (GH 1st edition order; Jaws of the Lion / 2nd edition put more targets first). Base Gloomhaven is followed
- [ ] **Simulator party rarely wins** — the tactical test policy wins ~2% of full playthroughs (mostly on Easy), so victory paths in late rooms and boss fights get little realistic coverage; a stronger policy (coordinated focus fire, card planning) would exercise them
