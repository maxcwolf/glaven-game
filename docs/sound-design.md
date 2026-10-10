# Sound design

What the board's sounds are, where each came from, and the rules that keep the mix in place.
The code is `GlavenGame/Utilities/BoardSound.swift`; the audio is `GlavenGame/Resources/Sounds/<cue>-<n>.m4a`.

Every sound was chosen by ear over three audition rounds in October 2026 (the first pass had one
plucked-string note for every hindering condition, a chime louder than a heavy hit for every boon,
and no sound for most of the player's own actions).

## The cues

Sources are files from Kenney's CC0 packs (`rpg` = RPG Audio, `impact` = Impact Sounds,
`interface` = Interface Sounds, `jingles` = Music Jingles, `casino` = Casino Audio). "st" is
semitones; "room" is a short synthetic reverb. Level is how loud the cue plays, measured as
`SoundAssetTests` measures it (dB, higher is louder).

### Combat

| Cue | When | Source | Level |
|---|---|---|---|
| `hit` ×3 | 1–3 damage | impact `impactPunch_medium` | −12.5 |
| `hit-heavy` ×2 | 4+ damage | impact `impactPunch_heavy`, limited | −10.5 |
| `miss` ×2 | a miss is drawn | rpg `cloth1`, `cloth2` | −17 |
| `blocked` ×2 | shield takes the whole attack | impact `impactPlate_heavy` | −14.5 |
| `shield` ×2 | shield takes part of an attack that still damages | impact `impactPlate_light` | −16.5 |
| `retaliate` | a figure retaliates | rpg `knifeSlice2` | −15.5 |
| `death` ×2 | a monster or summon dies | impact `impactSoft_heavy` | −14.5 |
| `exhaust` | a character is exhausted | impact `impactSoft_heavy` + `impactBell_heavy_001` −5 st | −11 |
| `trap` | a trap springs | rpg `metalLatch` + impact `impactPlate_heavy` | −12 |
| `heal` | hit points regained | interface `maximize_006` | −16 |

### Conditions

Each of the base game's conditions has its own cue (`BoardSound.condition(_:)`); any other
hindrance plays `harm`, any other boon `boon`.

| Cue | Source | Level |
|---|---|---|
| `harm` ×2 | rpg `cloth` + impact `impactSoft_medium` | −17 |
| `boon` | interface `maximize_008` +4 st, room | −17 |
| `wound` ×2 | rpg `knifeSlice`, `knifeSlice2` | −17.5 |
| `poison` | interface `scratch_005` −12 st | −17 |
| `stun` ×2 | impact `impactPlate_heavy` | −16 |
| `immobilize` | rpg `metalLatch` | −17.5 |
| `disarm` | impact `impactMetal_medium` ×2, −7 st | −17 |
| `muddle` | interface `minimize_008` | −18 |
| `curse` | impact `impactBell_heavy_001` −7 st | −16 |
| `strengthen` | rpg `clothBelt` | −17.5 |
| `bless` | interface `maximize_006` +7 st into a synthesised choir, room | −17 |

The choir is synthesised (additive voices shaped by the formants of a sung "ah"); Kenney's packs
have no voices.

### Movement and the board

| Cue | When | Source | Level |
|---|---|---|---|
| `step` ×5 | each hex walked or shoved | first sound pass | −29.5 |
| `land` | a jump lands | impact `impactSoft_medium` | −17.5 |
| `teleport` | a teleport | interface `maximize_006` +5 st, room | −12 |
| `door` ×2 | a room is revealed | rpg `doorOpen` | −11 |
| `loot` ×2 | gold picked up, bought or sold | rpg `handleCoins` | −17.5 |
| `summon` | a summon placed; a monster spawned or summoned mid-scenario | casino `chip-lay-3` | −17 |
| `infuse` | an element is infused | interface `maximize_008`, stretched ×1.6 | −18 |
| `consume` | an element is consumed | interface `minimize_006` | −19 |

### Rounds, cards and the player's own taps

| Cue | When | Source | Level |
|---|---|---|---|
| `card-pick` ×2 | a card tapped in hand | casino `card-slide` | −23 |
| `card-confirm` | the round's cards locked in | casino `card-place` ×2 | −19.5 |
| `round` | the round's cards are revealed | impact `impactPlank_medium` ×2, room | −16 |
| `turn` | a character's turn begins | impact `impactBell_heavy_001`, low-passed, room | −16 |
| `target` ×2 | an attack target chosen | rpg `drawKnife` | −21 |
| `end-turn` | End Turn | impact `impactWood_medium` | −21 |
| `invalid` | a tap that isn't one of the choices | impact `impactWood_light`, low-passed | −26 |
| `card` ×3 | a modifier drawn | casino `card-slide` | −20 |
| `shuffle` | a modifier deck reshuffled at round end | casino `card-fan-1` | −21 |
| `rest` | a short or long rest | rpg `cloth3` + `cloth4` | −20 |
| `lose` | a card goes to the lost pile | interface `scratch_004` | −20.5 |

### Jingles

| Cue | Source | Level |
|---|---|---|
| `start` | jingles `PIZZI13` (E E F) + G# A from its own last pluck, room | −12 |
| `victory` | jingles `PIZZI02` + two plucks from its own last note, room | −12 |
| `defeat` | jingles `PIZZI07` | −12 |

## The mix

- **Loudness lives in the files.** Every cue plays at full volume except footsteps (0.44). A new
  or replaced file is rendered at its category's level: blows loudest, conditions under the blow
  that carries them, the player's own taps quietest, footsteps under everything.
- **Variants match.** The variants of a cue play within 3 dB of each other, and take turns rather
  than being picked at random (so sound never draws on the game's seeded randomness).
- **Cues raised together are heard in order** (`BoardSoundMixer`):
  - a hit follows a trap or a shield knock by 0.10 s
  - a condition follows the blow that carried it, and any other condition, by 0.15 s
  - retaliate follows the hit by 0.15 s, and the damage it does follows by 0.12 s
  - a character's fall follows the blow by 0.10 s
  - the round's drum follows the cards by 0.35 s, and the turn bell follows the drum by 0.70 s
  - the turn bell follows End Turn by 0.35 s
  - a lost card follows a rest by 0.40 s, or End Turn by 0.30 s
- **The same cue in the same instant sounds once** (within 0.08 s): at full speed the targets of
  an area attack are hit together, and a scenario rule may spawn several monsters at once.
- A headless board (the simulator, tests) raises no cues, and nothing plays under the test runner.

`SoundAssetTests` holds the levels, `BoardSoundMixerTests` the ordering, `BoardSoundTests` the
triggers. `SOUND_LEVELS=1 swift test --filter testPrintTheMix` prints every file's level.

## Adding or replacing a sound

1. Render it mono at 44.1 kHz at its category's level and encode it AAC:
   `afconvert -f m4af -d aac -b 96000 -c 1 in.wav GlavenGame/Resources/Sounds/<cue>-<n>.m4a`.
2. A new cue is a new `BoardSound` case whose raw value is the file prefix; say when it waits for
   other cues in `BoardSoundMixer.follows`.
3. Raise it with `boardScene?.play(_:)` from the turn engine (silent when no view shows the
   board), or `BoardSoundPlayer.play(_:)` from a view.
4. Run the three test suites above, and add the cue to this file and to `CREDITS.txt`.
