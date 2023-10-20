### `|move|` (`0x03`)

In Generation IV, the lowest 3 ("slot") bits of `Target` may be `0b000`, in which case the move
either targets a side (in the case of Future Sight, Doom Desire, or Stealth Rock) or there was
`|[notarget]`.

```zig
// TODO: Generation IV test for Future Sight and |[notarget]
```

### `|switch|` (`0x04`)

#### Generation IV

<details><summary>Reason</summary>

| Raw    | Description           |
| ------ | --------------------- |
| `0x00` | None                  |
| `0x01` | `\|[from] Baton Pass` |
| `0x01` | `\|[from] U-turn`     |
</details>

### `|cant|` (`0x05`)


<details><summary>Reason</summary>

| Raw    | Description                | Move? |
| ------ | -------------------------- | ----- |
| `0x00` | `slp`                      | No    |
| `0x01` | `frz`                      | No    |
| `0x02` | `par`                      | No    |
| `0x04` | `flinch`                   | No    |
| `0x05` | `recharge`                 | No    |
| `0x06` | `Attract`                  | No    |
| `0x07` | `ability: Truant`          | No    |
| `0x08` | `Focus Punch\|Focus Punch` | No    |
| `0x09` | `Disable`                  | Yes   |
| `0x0A` | `nopp`                     | Yes   |
| `0x0B` | `move: Taunt`              | Yes   |
| `0x0C` | `move: Imprison`           | Yes   |
| `0x0D` | `move: Heal Block`         | Yes   |
| `0x0E` | `move: Gravity`            | Yes   |
| `0x0F` | `ability: Damp`  TODO      | Yes   |
</details>

```zig
// TODO: Generaiton III/IV support Damp [of]
```

### `|-damage|` (`0x0A`)

- probably don't need `[of]` because ident should always be directly inferrable\
- NB: upper case and lower case Recoil vs. recoil
- binding means we need to save the full u8 move in Bind reason - technically shouldnt
  need bind reason either (unless multiple pokeomon can bind same one in doubles?)

```zig
fn damageItem
fn damageAbility
```

### `|-heal|` (`0x0B`)

- might need `[wisher]` ie `Wish` for `Heal`

```zig
fn healAbility
fn healMove
```

---

Switch
======

## 1

- None

## 2

- None
- [from] Baton Pass

## 3

- None
- [from] Baton Pass

## 4

- None
- [from] Baton Pass
- [from] U-turn

Drag
====

## 2 / 3 / 4

None

Faint
=====

None

Move
====

## 1

- [from]Metronome
- [from]Mirror Move

(- [from]Wrap
- [from]Whirlwind
- [from]Thrash
- [from]Petal Dance
- [from]Solar Beam
- [from]Sky Attack
- [from]Skull Bash
- [from]Razor Wind
- [from]*)

## 2

- [from]Metronome
- [from]Mirror Move
- [from]Sleep Talk

## 3

- [from]Metronome
- [from]Mirror Move
- [from]Sleep Talk
- [from]Snatch
- [from]Assist
- [from]Magic Coat
- [from]lockedmove
- [from]Nature Power

## 4

Any can also be notarget!

None
NoTarget
From
FromNoTarget

- [notarget]
- [from]move: Metronome
- [from]move: Mirror Move
- [from]move: SleepTalk
- [from]Snatch
- [from]move: Assist
- [from]move: Copycat
- [from]Magic Coat
- [from]lockedmove    # NB: use thrash or some other sentinal move for locked!
- [from]move: Me First
- [from]lockedmove|[notarget]
- [from]from: Nature Power

Activate
=======

## 1

- Bide
- Substitute|[damage]
- confusion
- move: Haze
- move: Mist

## 2

- move: Bide
- Substitute|[damage]
- confusion
- move: Mist
- move: Safeguard
- move: Destiny Bond
- move: Endure
- item: Focus Band
- Protect
- trapped
- (Rage)

- move: Attract + |[of] <ident>
- move: Beat Up + |[of] <ident>
- move: Mind Reader + |[of] <ident>
- move: Lock On + |[of] <ident>

- move: Bind + |[of] <ident>
- move: Clamp + |[of] <ident>
- move: Fire Spin + |[of] <ident>
- move: Whirlpool + |[of] <ident>
- move: Wrap + |[of] <ident>

- item: Mystery Berry + |<Move>
- Substitute|[block] + |<Move>
- move: Mimic + |<Move>

- move: Magnitude + |<num>

- move: Spite + |<id> + |<num>

Boost
=====

# 1

- atk
- def
- evasion
- spa
- spd
- spe

- atk + |[from] Rage

# 2

- atk
- def
- evasion
- spa
- spd
- spe

- atk + |[from] item: Berserk Gene
- atk + |[silent]

# 3/4

- atk
- def
- evasion
- spa
- spd
- spe

- <stat> + |[from] item: <berry>

ClearAllBoost
============

## 1 

- clearallboost|[silent]

## 2/3/4

- clearallboost

CopyBoost
=========

## 2/3/4

- [from] move: Psych Up

Swapboost
========

ident|ident|[from] move: Heart Swap
ident|ident|atk, spa|[from] move: Power Swap
ident|ident|def, spd|[from] move: Guard Swap


Boost/Unboost
=======

## 1/2/3/4

accuracy|X
atk|X
def|X
spa|X
spd|X
spe|X
evasion|X

Setboost
=======

## 2 / 3

atk|X|[from] move: Belly Drum

## 4

atk|X|[from] ability: Anger Point

ClearNegativeBoost
=================

## 3/4

- [silent]

Crit/Resisted/Supereffective/Ohko/Nothing/mustrecharge/notarget
====

## 1/2/3/4

None

Miss
====

## 1

ident

### 2 / 3 / 4

ident
side ident
ident ident

Immune
======

## 1

None
|ohko

## 2

None

## 3

None
[from] ability: <Ability>
confusion|[from] ability: Own Tempo

## 4

[from] Oblivious

Hitcount
=======

## 1/2/3

ident|X

## 4

ident|X
side|X


CureStatus
===========

## 1

- brn|[silent]
- frz|[silent]
- par|[silent]
- psn|[silent]
- slp|[silent]
- tox|[silent]

- slp|[msg]
- frz|[msg]

## 2

- brn|[msg]
- frz|[msg]
- par|[msg]
- psn|[msg]
- slp|[msg]
- tox|[msg]

## 3 

- tox***|[silent]
- tox|[msg]
- tox|[silent]
- tox|[from] ability: Natural Cure
- brn|[msg]
- brn|[silent]
- brn|[from] ability: Natural Cure
- psn|[msg]
- psn|[silent]
- psn|[from] ability: Natural Cure
- par|[msg]
- par|[silent]
- par|[from] ability: Natural Cure
- slp|[msg]
- frz|[msg]
- frz|[from] move: Flame Wheel
- frz|[from] move: Sacred Fire

## 4

- brn***|[silent]
- tox|[msg]
- tox|[silent]
- brn|[msg]
- brn|[from] ability: Natural Cure
- psn|[msg]
- psn|[silent]
- par|[msg]
- par|[silent]
- par|[from] ability: Natural Cure
- slp|[msg]
- frz|[msg]
- frz|[from] move: Flame Wheel
- frz|[from] move: Flare Blitz
- frz|[from] move: Sacred Fire

CureTeam
=======

## 2/3/4

[from] <Move>

Cant
====

## 1

Disable|<Move>
flinch
frz
par
partiallytrapped
recharge
slp

## 2

Attract
nopp|<Move>

## 3

move: Taunt|<Move>
move: Imprison|<Move>
ability: Truant
ability: Damp|<Move>|[of] pXa: A
Focus Punch|Focus Punch

## 4

move: Heal Block|<Move>
move: Gravity|<Move>


## 4

Weather
======

## 2

None
<Weather>
<Weather>|[upkeep]

## 3 / 4

<Weather>|[from] ability: <Ability>|[of] pXa: A

Transform
========

ident|ident

Fieldactivate
============

## 1

move: Pay Day

## 2/3/4

move: Pay Day
move: Perish Song

Fieldstart
==========

### 4

move: Gravity
move: Trick Room|[of] pXa: A

Fieldend
========

### 4

move: Gravity
move: Trick Room


Enditem
======

## 2

<Item>
<Item>|[eat]

## 3

<Item>|[from] move: Knock Off
<Item>|[silent]|[from] move: Thief|[of] pXa: A
<Item>|[silent]|[from] move: Trick|[of] pXa: A

## 4

<Item>|[from] move: Fling
<Item>|[silent]|[from] move: Trick
<Item>|[silent]|[from] move: Switcheroo
<Item>|[from] stealeat|[move] <Move>|[of] pXa: A
<Item>|[weaken]

Status
======

## 1

brn
frz
par
psn
tox
slp|[from] move: <Move>

## 2

+
psn|[silent]

## 3

+
psn|[from]: ability: <Ability>|[of] ident
par|[from]: ability: <Ability>|[of] ident
brn|[from]: ability: <Ability>|[of] ident


### 4

+
brn|[from]: item: <Item>|[of] ident
brn|[from]: ability: <Ability>|[of] ident

Prepare
=====

## 1/2/3/4

ident|<Move>


Damage
=====

## 1

None
|[from] Leech Seed|[of] ident
|[from] Recoil|[of] ident
|[from] brn
|[from] psn
|[from] confusion

## 2

|[from] Curse
|[from] Curse|[of] ident
|[from] Nightmare 
|[from] Nightmare|[of] ident
|[from] Sandstorm
|[from] Spikes
|[from] brn|[of] side
|[from] brn|[of] ident
|[from] move: <Binding>|[partiallytrapped]
|[from] psn|[of] side
|[from] psn|[of] ident

## 3

|[from] Hail
|[from] ability: Liquid Ooze|[of] ident
|[from] ability: Rough Skin|[of] ident

## 4

|[from] Stealth Rock
|[from] ability: <Ability>|[of] ident
|[from] item: <Item>
|[from] item: <Item>|[of] ident
|[from] Recoil
|[from] recoil

Heal
====

## 1

|[from] drain|[of] ident
|[silent]

## 2

|[from] item: <Item>

## 3

|[from] Ingrain
|[from] ability: Rain Dish
|[from] ability: Water Absorb|[of] ident
|[from] ability: Volt Absorb|[of] ident
|[from] move: Wish|[wisher] <Species>
|[from] item: Shell Bell|[of] ident

## 4

|[from] ability: Dry Skin
|[from] ability: Ice Body
|[from] ability: Rain Dish
|[from] item: Shell Bell|[of] side
|[from] move: Healing Wish
|[from] move: Lunar Dance

Endability
=========

## 3

|[from] move: Role Play
|[from] move: Skill Swap

## 4

None
|[from] move: Worry Seed

Formechange
==========

## 3

|[msg]|[from] ability: Forecast


## 4

|
|[msg]|[from] ability: Forecast
|[msg]|[from] ability: Flower Gift

Fail
====

## 1/2

None
move: Substitute
move: Subsitute|[weak]
par
psn
slp
tox

## 2

|[from] ability: Insomnia|[of]: ident
|[from] ability: Vital Spirit|[of]: ident
heal
slp|[from] Uproar
slp|[from] Uproar|[msg]

## 3 / 4

unboost|Attack|[from] ability: Hyper Cutter|[of] ident
unboost|accuracy|[from] ability: Keen Eye|[of] ident
unboost|[from] ability: Clear Body|[of] ident
unboost|[from] ability: White Smoke|[of] ident

Item
====

## 2

|[from] move: Thief|[of] ident

## 3

|[from] move: Recycle
|[from] move: Trick
|[from] move: Covet|[of] ident

## 4

|[from] ability: Frisk|[of] ident|[identify]
|[from] move: Switcheroo

Sethp
=====

## 2/3/4

|[from] move: Pain Split
|[from] move: Pain Split|[silent]

Singlemove
=========

## 2

Desiny Bond
Rage

## 3/4

Grudge

Singleturn
==========

## 2

Protect
move: Endure

## 3

Snatch
move: Focus Punch

## 4

move: Roost

Sidestart
========

## 2

Reflect
Safeguard
Spikes
move: Light Screen

## 3

Mist
Light Screen

## 4

move: Lucky Chant
move: Stealth Rock
move: Tailwind
move: Toxic Spikes

Sideend
========

## 2

Reflect
Safeguard
Spikes|[from] move: Rapid Spin|[of] ident
move: Light Screen

## 3

Mist
Light Screen

## 4

Light Screen|[from] move: Defog|[of] ident
Mist|[from] move: Defog|[of] ident
Reflect|[from] move: Defog|[of] ident
Safeguard|[from] move: Defog|[of] ident
Spikes|[from] move: Defog|[of] ident
Stealth Rock|[from] move: Defog|[of] ident
Stealth Rock|[from] move: Rapid Spin|[of] ident
move: Lucky Chant
move: ailwind
move: Toxic Spikes|[of] ident

Ability
======

## 3 

|[from] ability: Trace|[of] ident
|[from] ability: Roleplay|[of] ident
|boost
|[silent]

## 4

None

End
===

## 1
## 2
## 3
## 4

Start
=====

## 1
## 2
## 3
## 4
◊