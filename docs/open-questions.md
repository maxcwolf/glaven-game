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
11. **When the Enhancer opens.** By the rulebook, Gloomhaven's enhancements need The Power of
    Enhancement (won in Frozen Hollow, scenario 14), so the Enhance button is hidden until then.
    Many groups house-rule it open from the start — want a setting? Now: by the rulebook.
12. **Enhancements saved by the old companion sheet** addressed a sub-action's slot in a way that
    could clash with the next action's slot; the new address is `(index + 1) × 100 + sub`. Any
    old saves with enhancements would read them on the wrong line. I assumed there are none worth
    migrating. Now: no migration.
13. **Iron Helmet.** The game data gives it neither the spent nor the consumed mark, so it's
    always on: every enemy ×2 against the wearer counts as +0. If your copy of the card has a
    spent mark, it should be offered once per rest like Leather Armor. Now: always on.
14. **Item carry limits.** By the rules a character brings at most one head, body and legs item,
    two hands' worth, and half their level (rounded up) in small items. Today every item they own
    is carried, and all of them work on the board. Should I add a loadout choice in town (with
    the shop refusing nothing, just what's brought), or enforce it at purchase? Now: no limit.
