# Open questions

Decisions I made a default for while working alone, and things I need from you. Each says what
the game does now; change any of them and I'll follow.

1. **Road event before the first scenario.** Black Barrow is marked as reached by road, so the
   campaign's very first scenario draws a road event. Gloomhaven players often skip it. Now: drawn,
   unless the Table Rules turn it off.
2. **Menu music.** Kenney has no CC0 music loops. OK to use another CC0 source (for example
   OpenGameArt.org, which needs per-track license checks)? Now: no music, jingles only.
3. **Straggler and Scrambler with no rests.** "Take only long (short) rests" — does a scenario
   with no rest at all meet it? Now: at least one rest of that kind is needed.
4. **Quests about map regions** (Take Back the Trees, Vengeance, The Fall of Man, Elemental
   Samples) need to know which region each scenario is in; the data doesn't say. Now: counted by
   hand on the character sheet. I can add a region table for the 95 scenarios if you want it.
5. **"Exhausted party members"** (A Study of Anatomy): does the character's own exhaustion count?
   Now: yes, every exhaustion in the party in scenarios they played.
6. **Sanctuary and prosperity.** Every 100 gold the party donates raises prosperity by one. Is
   that the threshold you play with? Now: 100.
7. **Scenarios nothing unlocks** (N3 in the rules audit): no scenario, event or quest in the data
   unlocks #72, #73, #76 or #77. Are they meant to come from somewhere the data leaves out, or
   added by hand? Now: they appear only when added by hand (`testEveryScenarioCanBeUnlocked`
   pins the four).

Answered on 2026-10-08: the Enhancer stays gated by Frozen Hollow (GH scenario 14); old
companion enhancements aren't migrated (nothing released); Iron Helmet is always on (no spent
mark); carry limits follow the rules with a loadout choice; the hex-enhancement player picks the
marked hex; Submissive Affliction is a flat Attack 2 (Mindthief FAQ). Built since: Table Rules
(Enhancer from the start, bring every item, no road event before the first scenario), set in
town and listed on the scenario brief; several campaigns, each saved to its own file.

Settled since: envelope X is recorded when opened — by #58, #60 or the two quests that end in
it — and said in the campaign log (its sealed content, the Bladeswarm, isn't in the data);
gold an event or reward takes or gives "collectively" is split by the players, evenly or the
richest first (2026-10-14). `ui-overhaul` and Phase VI are merged into `main`.
