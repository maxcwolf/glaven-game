# Open questions

Decisions I made a default for while working alone, and things I need from you. Each says what
the game does now; change any of them and I'll follow.

1. **Road event before the first scenario.** Black Barrow is marked as reached by road, so the
   campaign's very first scenario draws a road event. Gloomhaven players often skip it. Now: drawn.
2. **Menu music.** Kenney has no CC0 music loops. OK to use another CC0 source (for example
   OpenGameArt.org, which needs per-track license checks)? Now: no music, jingles only.
3. **Envelopes** (GH 58, 60 rewards). The sealed content isn't in the game data. Skip, or should
   I model "envelope opened" as an achievement and show the rulebook text? Now: ignored.
4. **Who pays collective costs.** Event and reward costs paid "collectively" are taken from the
   richest character first. Want a screen to split them by hand, like reward gold? Now: richest first.
5. **Merging `ui-overhaul` into `main`.** It's pushed and every commit passes the suite. Open a
   PR, or keep building on the branch? Now: building on the branch.
6. **Phase VI scope** (TODO.md): the remaining town rules — battle goals, personal quests,
   retirement, sanctuary, enhancements, class events — then VoiceOver hexes. Anything to add,
   drop or reorder?
7. **Straggler and Scrambler with no rests.** "Take only long (short) rests" — does a scenario
   with no rest at all meet it? Now: at least one rest of that kind is needed.
8. **Quests about map regions** (Take Back the Trees, Vengeance, The Fall of Man, Elemental
   Samples) need to know which region each scenario is in; the data doesn't say. Now: counted by
   hand on the character sheet. I can add a region table for the 95 scenarios if you want it.
9. **"Exhausted party members"** (A Study of Anatomy): does the character's own exhaustion count?
   Now: yes, every exhaustion in the party in scenarios they played.
10. **Sanctuary and prosperity.** Every 100 gold the party donates raises prosperity by one. Is
    that the threshold you play with? Now: 100.

Answered on 2026-10-08: the Enhancer stays gated by Frozen Hollow (GH scenario 14); old
companion enhancements aren't migrated (nothing released); Iron Helmet is always on (no spent
mark); carry limits follow the rules with a loadout choice; the hex-enhancement player picks the
marked hex; Submissive Affliction is a flat Attack 2 (Mindthief FAQ). Built since: Table Rules
(Enhancer from the start, bring every item, no road event before the first scenario), set in
town and listed on the scenario brief; several campaigns, each saved to its own file.
