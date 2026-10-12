# Picket Line

A first-person station shooter in Godot 4.7 (GDScript). You hold a picket station in the sky and shoot an alien fleet
that comes in from 350 to 900 metres away. Brute force (spray the pulse cannon, let heat be your limit) and skill
(scope in, time your lance charge, hit the weak core when the plating opens, use focus to slow time) both win.

Six sectors, bosses at the end of sectors 2, 4 and 6, and an upgrade card after each sector cleared.
Combo chains, SNAP kills (shoot a fresh arrival within a second of it coming into view) and clean-sector bonuses.

## Play

Requires Godot 4.7 (standard build).

Picket Line lives in the combined PointBlank Arcade project (`godot/`). Open the start menu and pick it, or go straight in:

```
godot --path godot                           # start menu, choose Picket Line
godot --path godot -- --game=picket_line     # straight into Picket Line
```

| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Aim | Mouse | Right stick |
| Fire | Left mouse | Right trigger |
| Scope (slow aim, shows weak points) | Right mouse | Left trigger |
| Move along the rail | A / D (W / S for height) | Left stick |
| Focus (slow time, uses focus meter) | Q (hold) | Left bumper |
| Quick dodge with i-frames | Shift (or double-tap A / D, option) | Right bumper |
| Weapons | 1 to 4, mouse wheel, E / R | D-pad left / right |
| Pause | Escape | Start |

Weapons: **Pulse** (fast spray, heat-limited), **Lance** (hold to charge, release for a heavy shot, crits weak points),
**Flak** (proximity burst with splash), **Swarm** (homing pods, lock on with the aim cone).

## Generated audio

Music and sound effects are synthesised by `scripts/gen_audio.py` (numpy and ffmpeg with libvorbis). The output is
original and project-owned, so nothing is downloaded. Run it once before playing to hear sound:

```
python3 godot/games/picket_line/scripts/gen_audio.py
```

Output goes to `godot/games/picket_line/assets/audio/`, which is git-ignored. The game runs without it, silently.

## Tests

The core rules are engine-free and tested headless:

```
godot --headless --path godot -s res://games/picket_line/tests/core_tests.gd
```

A headless smoke run drives the real scene: a run starts, a scripted pilot flies sectors with the world, HUD and
menus live, and the pause, options, upgrade and debrief screens are exercised.

```
godot --headless --path godot -s res://games/picket_line/tests/smoke_test.gd
```

## Layout

```
core/       Engine-free rules and simulation (balance, enemies and AI, weapons, projectiles, station, sectors, scoring, runs, saves)
game/       Engine layer (main flow, input, world, sky, enemy view, effects, HUD, menus, audio, saves)
shaders/    Sky, enemy, beam and effect shaders
scenes/     main.tscn, the single entry scene
tests/      core_tests.gd
scripts/    gen_audio.py (procedural music and sound effects)
docs/       DESIGN.md (module contract and tuning intent)
```

## Licence

Copyright (C) 2026 tigo.robotics@gmail.com. Picket Line is free software under the GNU General Public License v3 or
later. See the repository LICENSE.
