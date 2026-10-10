# Gloomhaven rules, as a checklist

Notes on the rules of Gloomhaven (first edition, second printing rulebook, 52 pages) and the
official FAQ, in our own words, one rule per line with an id. The audit in
[the rules audit](../audits/2026-10-09-rules-audit.md) says, rule by rule, where the game enforces it and which test
proves it. Scenario-specific rules are in `docs/scenario-book/`.

Sources: the printed rulebook (page numbers are its pages); the official FAQ
(<https://boardgamegeek.com/wiki/page/thing:174430:Official_FAQ>, mirrored at
<https://mahmati.kapsi.fi/bg/gloomhaven/gloomhaven_official_faq.html>). Where the FAQ corrects or
sharpens the book, the line says "FAQ".

## SET — Scenario setup and level (pp. 12–15)

- SET-1 Monsters are placed for the number of characters (2, 3 or 4): none, normal or elite per place. Only the first room is set up; other rooms when revealed. A room revealed later is still set up for the number of characters the scenario began with (FAQ).
- SET-2 Standee numbers are random within the type; a type has a limited number of standees; when none is left the monster isn't placed (elites first when choosing which to place).
- SET-3 Recommended scenario level = average character level ÷ 2, rounded up. Easy −1, Hard +1, Very Hard +2; never below 0 or above 7. Solo play: +1 to the result.
- SET-4 By level L (0–7): monster level L; gold per money token 2,2,3,3,4,4,5,6; trap damage 2+L; bonus experience 4+2L.
- SET-5 Each player is dealt two battle goals and keeps one, secretly.
- SET-6 A hand is the class's hand size, chosen from the character's card pool; equipped items add their −1 cards to the modifier deck at the start.
- SET-7 Characters start on any empty starting hex of the first room.
- SET-8 Scenario effects ("add 3 Curse", "all start poisoned") apply at the start; a perk can ignore negative scenario effects (not event effects; a character's summons are not covered) (FAQ).
- SET-9 Each attack modifier deck is shuffled at the start; the monsters share one deck (20 standard cards); allies and summons of characters use decks as the rules say (summons: the owner's).

## RND — The round (pp. 16–18, 32)

- RND-1 Each round every character plays two cards from hand (one chosen as the lead, for initiative) or declares a long rest. Two cards in hand are needed to play; two in the discard pile to rest.
- RND-2 A character who at the start of a round can neither play two cards nor rest is exhausted.
- RND-3 Short rest (end of round, needs two discards): shuffle the discard pile, lose one at random, the rest return to hand. Once per rest the player may suffer 1 damage to lose a different random card instead (the first goes back to hand); that damage can be negated like any other (FAQ). A short rest may be taken in a scenario's last round (FAQ).
- RND-4 Long rest (declared at card selection, needs two discards): initiative 99; on that turn lose one discard of the player's choice, the rest return, Heal 2 self (optional, FAQ), refresh all spent items. It is a turn: items can be used; start-of-turn Wound applies first (FAQ).
- RND-5 One ability card is revealed for each monster ability deck with a figure on the board; all monsters using the deck, normal and elite, act on its initiative. Types that share a deck (Bandit, City and Inox Guards use the Guard deck) act on the same card, one type at a time (FAQ).
- RND-6 Initiative order is ascending. Ties: a character before a monster; between characters the second card decides (lower first), then the players; between monster types the players decide. A long-resting character goes after others at 99 (FAQ).
- RND-7 Within a monster type: elites first in ascending standee number, then normals in ascending standee number.
- RND-8 A summon takes its turn immediately before its owner's, each a separate turn; several summons act in the order they were summoned. A summon does not act in the round it was summoned.
- RND-9 End of round, in this order: decks that drew a ×2 or Null are reshuffled with their discards; monster ability decks that drew a shuffle card (or have no cards left) are reshuffled; round bonuses end and their cards go to discard or lost; characters may short rest; every element steps down (strong → waning → inert).
- RND-10 Curse and Bless cards are removed when drawn and never cause a reshuffle.

## TRN — A character's turn (pp. 18–19, 28)

- TRN-1 The top action of one played card and the bottom action of the other, in either order; each action is completed before the other starts.
- TRN-2 Any card may instead give a basic Attack 2 (as a top) or Move 2 (as a bottom); a card played this way is discarded, never lost, whatever it prints.
- TRN-3 Abilities within an action happen in printed order. Any part may be skipped except what harms the character or their allies (damage, lost cards, negative conditions) (FAQ: also XP, standalone infusions and the area's individual targets can't be skipped separately).
- TRN-4 A played card goes to discard; to lost if a lost-icon action on it was performed; to the active area if it has a persistent or round bonus that was performed.
- TRN-5 At the end of the turn a character must loot money tokens and treasure in their own hex (also when stunned or resting). Summons and monsters never do.
- TRN-6 Experience: an action's XP is gained when any part of the action is performed; XP beside an attack/effect is gained with it; a persistent bonus's slot XP as the charge is used. No XP for kills. A card can't be played for XP alone if nothing on it can be done (FAQ).
- TRN-7 Items may be used at any time on the owner's turn, a long-rest turn included (not in the middle of another ability, FAQ) or when their text says; an item that changes an attack is used before the modifier is drawn. An item with several uses is used whenever its trigger applies, like a persistent bonus (FAQ).

## MOV — Movement and the map (pp. 14–15, 19)

- MOV-1 Move X: up to X hexes (0 is allowed, FAQ). Through allies; not through enemies or obstacles; never through walls; cannot end on a hex with another figure. The edge of a map tile is a wall — also the line between two tiles' full hexes that touch beside a door: those hexes are not adjacent (FAQ).
- MOV-2 Difficult terrain costs 2 movement to enter. Not for flying, jumping (except a jump's last hex, FAQ) or forced movement.
- MOV-3 Jump ignores figures and terrain on the way; the last hex is a normal move (trap springs, hazard hurts, must be free, difficult terrain costs 2).
- MOV-4 Flying ignores figures and terrain everywhere, but must end on a hex with no figure. A figure that loses flying while on an obstacle suffers trap damage and moves to the nearest empty hex.
- MOV-5 Traps: sprung when a figure enters by normal or forced movement (not flying, not jumping over); effect applied, trap removed. A damage trap does 2+L. Other traps apply their conditions (and damage if printed).
- MOV-6 Hazardous terrain: half trap damage, rounded down, each time a hex is entered by normal or forced movement; never removed; no damage for starting or ending a turn there (FAQ).
- MOV-7 Obstacles block movement (not flying/jumping), never block line of sight or ranged attacks. Obstacles may not be placed so as to cut off part of the map (FAQ).
- MOV-8 Doors: a closed door is a wall for monsters and summons; a character moving onto it opens it and the room beyond is revealed at once, mid-move, and the character goes on with the movement left. Open doors don't hinder anyone. Corridors join tiles into one room.
- MOV-9 Reveal: the new room's monsters, overlays and money are placed for the character count; a monster type with no card drawn this round draws one now. When the revealing character's turn ends, every revealed monster type whose initiative is lower than that character's acts at once (in initiative order); the others act at their place in the order.
- MOV-10 Treasure tiles: numbered ones are looted once per campaign; goal treasure resets. Money tokens are worth the level's gold each at the end, lost if not looted.

## LOS — Line of sight and range (p. 19, FAQ)

- LOS-1 A figure has line of sight to a hex if a straight line can be drawn from any corner of its hex to any corner of the other without touching a wall. Only walls (and closed doors) block; figures and obstacles don't. A line that only touches a wall's corner or edge is blocked (FAQ).
- LOS-2 Any ability with a target or a range needs line of sight, including Loot X and heals.
- LOS-3 Range is counted in hexes, never through walls: two hexes with a wall line between them aren't adjacent.
- LOS-4 A melee attack is range 1; hexes of a melee area further away still count as melee.

## ATK — Attacks (pp. 19–22)

- ATK-1 Attack X does X damage to one enemy in range and line of sight. A ranged attack on an adjacent enemy has Disadvantage.
- ATK-2 Order of modification for each target: the attacker's bonuses and penalties (+X from cards, items, +1 against Poison); then the modifier card(s); then the defender's Shield (less Pierce). Damage is never below 0.
- ATK-3 One modifier draw per target of every attack. Only attacks draw: traps, hazards, Retaliate, Wound and "suffer damage" never do, and Shield doesn't reduce them.
- ATK-4 Null: no damage. ×2: doubles the attack value after other bonuses. Rolling cards: keep drawing until a non-rolling card; all are added.
- ATK-5 Advantage: draw two, use the better; one rolling → both add; both rolling → keep drawing to a non-rolling card and add all. Disadvantage: draw two, use the worse; rolling cards are ignored (both rolling → keep drawing, only the last, non-rolling card counts). They don't stack; one of each cancels. An effect on a card (a condition, an element, a heal) is worth something, but how much is undefined: "+1 Stun" beats "+1"; "+0 Stun" against "+2" is ambiguous. Poison's +1 and item bonuses aren't counted. Ambiguous comparisons use the card drawn first (FAQ).
- ATK-6 Effects of an attack (conditions, push, pull, and those on modifier cards) apply after damage, whether or not any damage was done (Null included), but not when the target dies or is exhausted by it.
- ATK-7 Push X / Pull X: the attacker's side chooses each hex; every hex must be further from (closer to) the attacker than the last; stops when no such hex is free. Through allies of the mover is fine, never to end on a figure; not through walls or obstacles (flying targets ignore obstacles and don't spring traps); ignores difficult terrain; springs traps and hazards. Optional, but all or nothing short of being blocked (FAQ). Works on immobilized and stunned figures.
- ATK-8 Pierce X ignores X of the target's Shield for this attack.
- ATK-9 Add Target: one more enemy within the attack's range, not already a target — in addition to an area's targets, and at range 1 for a melee area (FAQ). Target X: up to X different enemies in range. No enemy is attacked twice by one attack ability.
- ATK-10 Area attacks: the pattern may be turned and mirrored; a melee pattern has a grey hex for the attacker; a ranged pattern needs one of its hexes within range; every target hex needs line of sight from the attacker; each enemy in it is a separate attack with its own draw; allies are never hit unless the card says.
- ATK-11 A monster at 0 hit points dies at once and drops a money token on its hex, unless it was summoned or spawned; allied monsters drop none (FAQ). Damage past 0 still counts as inflicted (FAQ).
- ATK-12 Shield X reduces each attack's damage by X; several Shields add; only attacks.
- ATK-13 Retaliate X (Range Y): after each attack on the figure by an attacker within range (adjacent if none printed), that attacker suffers X — not an attack, no draw, no Shield. Not if the retaliating figure was killed or exhausted by the attack; checked where figures stand after the attack's push/pull (FAQ). Several add.
- ATK-14 When a character suffers damage from any source, the player takes it or negates it all by losing one card from hand or two from the discard pile; other effects still land.
- ATK-15 A character at 0 hit points, or unable to play or rest, is exhausted: all cards lost, figure and summons removed, no further part; the scenario is lost when all are exhausted.

## CND — Conditions (pp. 22–23)

- CND-1 One of each condition per figure; reapplying resets its duration.
- CND-2 Poison: every enemy attack on the figure gets +1 Attack. A heal removes it and heals nothing.
- CND-3 Wound: 1 damage at the start of each of the figure's turns. A heal removes it and still heals. With both: the heal removes both and heals nothing.
- CND-4 Immobilize: no move abilities. Disarm: no attack abilities. Stun: no abilities and no items (a stunned character still plays two cards or long rests, and they are discarded). Muddle: Disadvantage on all its attacks. Each ends at the end of the figure's next turn — a condition gained during its own turn lasts through the following turn (FAQ).
- CND-5 Invisible: can't be focused or targeted by enemies; monsters treat the figure as an obstacle. Strengthen: Advantage on all its attacks. Both end at the end of the next turn. Positive conditions can't be dropped early.
- CND-6 Curse: a Curse (Null, removed when drawn) goes into the figure's deck — the monster deck for any monster, the owner's for a summon. Ten for the monsters, ten shared by the characters; none added when none is left. Bless: a ×2 removed when drawn; ten in all.
- CND-7 Immunity: a figure immune to a condition never gains it. Objectives with hit points are immune to all negative conditions and to forced movement.
- CND-8 Non-attack damage (traps, hazards, Wound, Retaliate, "suffer damage") is not reduced by Shield and not raised by Poison.

## ELE — Elements (p. 23–24)

- ELE-1 An ability that infuses an element makes it strong at the end of that figure's turn (only if some part of the action was performed).
- ELE-2 A strong or waning element can be consumed for a printed bonus; it becomes inert. An element can't be consumed in the turn it was made (it isn't strong yet) — an element already there can be consumed and made again in either order, and ends the turn strong (FAQ).
- ELE-3 Each element steps down at the end of every round.
- ELE-4 Monsters always consume when they can; the first monster of the type to act consumes and every monster of the type acting that round gets the bonus. Monster infusions happen at the end of the first acting monster's turn. No consumption if the ability it belongs to isn't performed (FAQ).

## ACT — Active bonuses, shield, heal, summons (pp. 24–27)

- ACT-1 Persistent bonus: lasts until its conditions are met; with charge slots, a charge is used every time the trigger happens (not optional), left to right, and the card is lost after the last. Round bonus: until the end of the round.
- ACT-2 A player may at any time move an active card to its pile to end the bonus.
- ACT-3 Heal X: self, or an ally (or self) within the printed range and line of sight; never above maximum.
- ACT-4 Summon: placed on an empty hex adjacent to the summoner; none free → the summon can't be made. Its card stays active; the summon is removed at 0 hit points, when the card leaves play, or when the owner is exhausted; when the summon dies its card leaves the active area (to the lost pile, as its action is marked).
- ACT-5 A summon acts by the monster rules with "Move +0, Attack +0" using its own stats, draws from its owner's deck, and its kills earn nothing extra. A summon with "–" for move or attack doesn't do that.
- ACT-6 Recover returns cards; cards with the no-recover mark can't be. Refresh restores items.
- ACT-7 Loot X: every money token and treasure tile within X hexes in line of sight, whatever is in the way.
- ACT-8 Items: one head, one body, one legs, two one-hand or one two-hand, small items up to half the level rounded up. Spent items refresh on a long rest; consumed ones only by an ability; all between scenarios. An item with uses left isn't spent, and a rest doesn't give its uses back (FAQ).

## MON — Monsters (pp. 29–32, FAQ)

- MON-1 A monster does what its card lists, in order, with its stat card's base values (elite or normal, at the monster level) plus the card's modifiers. No Move on the card → no move; no Attack → no attack.
- MON-2 Focus: the enemy it can attack using the fewest movement points (to a hex from which the attack is possible: free, in range, in line of sight), counting as if it had unlimited movement. Ties: fewer hexes away (through anything but walls), then earlier in initiative order (a summon before its owner; an objective counts as 99).
- MON-3 Traps and hazardous terrain count as obstacles when finding a focus, unless no other path exists — then the path with the fewest of them. Flying and jumping monsters ignore them (a jumper not on its last hex).
- MON-4 No focus (no enemy, no path, all invisible): the monster doesn't move or attack but does its other abilities.
- MON-5 With no attack on the card (or disarmed) a monster moves as if for a melee attack: toward its focus as near as it can.
- MON-6 Movement: the least movement that lets it attack its focus this turn; if several attack hexes: first no Disadvantage against the focus, then the most additional targets, then least Disadvantage on those, then fewest movement points. If it can't attack this turn it moves as far along the shortest path toward the attack hex as it can, ending nearer its focus; it never moves if that brings it no nearer. Monsters don't retreat except a ranged one stepping out of adjacency to lose Disadvantage (not when muddled anyway).
- MON-7 Attacks: the focus, then for Target X / Add Target / areas as many more enemies as possible. Each separate Attack line is its own attack and may hit the focus again. Monsters draw from the monster deck (allied monsters from the ally deck).
- MON-8 Shield/Retaliate on an ability card start when the monster acts and last to the end of the round (not gained while stunned); on the stat card they are always on. They add.
- MON-9 Monster Heal: self, or the ally within range missing the most (as printed; "affect all allies" heals each of them). Monster Loot X: money tokens only, lost with the monster. Monster Summon: adjacent to the summoner and as near an enemy as possible; needs a free standee; never acts in the round it arrives; drops no money.
- MON-10 An ability deck reshuffles at the end of a round in which its shuffle card was drawn, or when it runs out.
- MON-11 Bosses are neither normal nor elite; immune to the conditions on their card; hit points and specials use C (characters at the start). Special 1 / Special 2 only when the boss deck calls them. Order on a boss card: move, attack, then others as printed.
- MON-12 A monster summoned or spawned mid-round whose type has no card draws one for the round (FAQ).
- MON-13 Monster stat effects (Poison, Wound, Pierce, Target, Advantage, attackers gain Disadvantage, Flying, Shield, Retaliate) apply to all its attacks or always, as printed.
- MON-14 Invisible characters: not focused, not targeted, block the monster's movement like an obstacle (not flyers/jumpers); untargeted effects still reach them.

## END — Ending a scenario (pp. 33, 49)

- END-1 When the goal is met or failed the rest of the round is played; a goal met in the round the last character is exhausted is a loss (FAQ).
- END-2 Either way: characters keep experience earned and money looted (tokens × the level's gold); all cards and items return; hit points reset; Curse, Bless and scenario −1 cards leave the decks.
- END-3 Success only: battle goal checkmarks (exhausted characters too), 4+2L bonus experience each, the scenario's rewards.
- END-4 Three checkmarks give a perk; at most 18 checkmarks.

## CMP — Campaign and town (pp. 34–48)

- CMP-1 Reputation runs −20…+20. Shop prices: −5 at 19–20, −4 at 15–18, −3 at 11–14, −2 at 7–10, −1 at 3–6, 0 at −2…2, +1 at −3…−6, +2 at −7…−10, +3 at −11…−14, +4 at −15…−18, +5 at −19…−20.
- CMP-2 Items sell for half price rounded down and return to the city's supply; one copy of an item per character (a duplicate from a treasure pays its sale price, FAQ); stock is the item's printed copies.
- CMP-3 Experience for levels 2–9: 45, 95, 150, 210, 275, 345, 420, 500. Levelling up (in town only): one new card of that level or lower, one perk, more hit points.
- CMP-4 Prosperity levels 2–9 at 4, 9, 15, 22, 30, 39, 50, 64 checkmarks; a loss never takes the city below a level reached, nor a character below a perk earned (FAQ). New characters may start at any level up to it, with 15×(L+1) gold.
- CMP-5 Sanctuary: once per visit per character, 10 gold for two Blesses in the next scenario.
- CMP-6 Enhancements: base cost by sticker (×2 when the ability targets several, not for hexes or for moves' own targets), +25 per card level above 1, +75 per sticker already on that action; hex: 200 ÷ hexes now targeted, rounded down; enhanced cards per class at most the prosperity level.
- CMP-7 Retirement when the personal quest is done: prosperity +1, the reward (usually a class) unlocked, the player's next characters get one more perk each time.
- CMP-8 A road event before a scenario reached by road (not when replaying at once or linked); one city event per visit.
- CMP-9 A scenario can be played in campaign mode only if it has been unlocked (its sticker is on the map), its requirements are met and it isn't completed. Achievements of one type (City Rule, Artifact) replace one another; others can be earned several times and are counted.
- CMP-10 Reputation: at +10 and −10 a class box is opened, at +20 and −20 events are added (p.49).
