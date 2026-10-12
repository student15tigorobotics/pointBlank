# PointBlank Swarm

A VR tower-defence / swarm shooter for the **HTC VIVE XR Elite** (Android standalone, OpenXR).
Built in Godot 4.7 with GDScript. Hold the line against thousands of polygon drones across twelve themed chapters.

**Enjoying the game?** [♥ Support development via Stripe](https://buy.stripe.com/aFafZjeahanSe1f3CE9k400) — also reachable from the in-game OPTIONS tab.

## Target

- Android APK on the XR Elite, deployed over adb. The headset is standalone, so there is no PC VR path.
- Desktop preview runs from the same project (`--desktop`) so you can test without the headset.
- Passthrough uses the HTC layer from the godot_openxr_vendors plugin (v3.0.0 or later; this build pins 5.1.0-stable).

## Features

- **Swarm combat**: the enemy cap starts at 1,200, 2,000 or 2,500 alive for the low, medium (default) or high graphics tier. The frame-time governor moves it, and the on-device benchmark sets the saved cap. The hard limit is 6,000.
- **Tower defence**: six towers. Turret is free; Tesla, Frost, Mortar, Sniper and Vortex are unlocked in the hub. Each tower goes up to three levels, and selling refunds 60%.
- **Held weapons**: one per hand. Blaster is free; Scatter, Rail, Chain Arc, Nova Grenade, Plasma Saber and Kinetic Boulder are unlocked in the hub. Aim assist is built in.
- **Ally Squad**: an unlock that gives the right hand a lemming tool. B releases a squad from the core end; A detonates every lemming on the field.
- **Early wave bonus**: call a wave early; the remaining prep time converts to credits at 10 per second.
- **Overkill credits**: damage beyond an enemy's remaining HP converts into credits.
- **Twelve chapters in seven themes**: chapters 1 to 6 are Space Opera, Superhero Metropolis, Noir Harbor, Ancient Egypt, Iron Pantheon and Neon Future; chapters 7 to 12 are a Japanese-cyberpunk arc (Neo-Kyoto). Original characters, inspired by those genres.
- **Story**: a prologue, and intro and outro dialogue for chapters 1 to 6; a branching choice at the Sun Gate (chapter 4); two endings, decided in chapter 6.
- **Speech**: Android uses the device text-to-speech engine (`DisplayServer.tts_speak`). Desktop preview uses the Piper CLI when installed. Dialogue text always shows on the panel; the voice can be turned off in OPTIONS.
- **Upgrades**: eight levelled upgrades and twelve one-time unlocks (seven weapons, five towers), bought in the hub's SHOP tab.
- **Cheat codes**: chapters 1 to 6 each reveal a four-digit code; redeem it on the keypad in the CODES tab.
- **Leaderboard**: top ten local scores with generated callsigns.
- **Graphics**: MultiMesh instancing. Enemies beyond 6 m, or over the mesh budget, are drawn as additive billboard glows. Fog per theme, bloom off, adaptive render scale.

## Layout

```
godot/                   Godot project (open this folder)
  core/                  Engine-free simulation and rules (GDScript)
  game/                  Engine layer: rendering, input, UI, hub, story, boot
  assets/                Third-party audio, manifest.json (URLs, checksums, licences), CREDITS.md
  tests/core_checks.gd   Core rule tests (run headless)
  scenes/main.tscn       Entry scene
  project.godot          Renderer mobile, OpenXR enabled
  export_presets.cfg     Android preset: arm64, Gradle build, OpenXR, HTC vendor features
  openxr_action_map.tres OpenXR bindings, including the VIVE Focus 3 / XR Elite profile
scripts/
  fetch_assets.py          Downloads the manifest assets and builds the generated menu ambience
  gen_menu_ambience.py     Writes godot/assets/audio/amb.menu.wav (run by fetch_assets.py; needs numpy)
  fetch_openxr_vendors.sh  Installs godot_openxr_vendors 5.1.0-stable into godot/addons
  fetch_voice.py           Installs the Piper CLI and voice model (desktop preview only)
  deploy_android.sh        Builds the APK, installs it over adb, launches it
  benchmark_pull.sh        Pulls the on-device swarm benchmark from logcat into two CSV files
```

## Set up (on your machine)

You need Godot 4.7 (standard build, not .NET), its Android export templates, JDK 17, and the Android SDK
(platform-tools, build-tools, platform 35) with `ANDROID_HOME` set. Put `adb` on your PATH. The asset script needs
Python 3, and the menu ambience generator needs numpy (`pip install numpy`).

1. Install the vendor plugin (HTC passthrough and the export options):
   ```
   scripts/fetch_openxr_vendors.sh
   ```
2. Fetch the third-party audio and build the menu ambience. This downloads the files listed in
   `godot/assets/manifest.json`, checks each download against its SHA-256, and rewrites `godot/assets/CREDITS.md`:
   ```
   python3 scripts/fetch_assets.py
   ```
   `amb.menu.wav` is not downloaded. When it is missing, the script runs `scripts/gen_menu_ambience.py` to write it.
   Add `--dry-run` to see what would be fetched.
3. Install the Gradle Android build template (the deploy script does this on first run if it is missing):
   ```
   godot --headless --path godot --install-android-build-template
   ```
4. On the XR Elite: enable developer mode and USB debugging, then connect it with USB and accept the prompt.

## Build, deploy and benchmark

```
GODOT=/path/to/godot scripts/deploy_android.sh          # debug APK, install, launch
```

Then on the headset: **Hub > OPTIONS > SWARM BENCHMARK**. The benchmark ramps the swarm until frames stop holding
90 Hz. When it finishes, pull the results to your machine:

```
scripts/benchmark_pull.sh results.csv
```

This writes two files. `results.csv` has one row every 2 s, with the header `elapsed_s,alive,visible,avg_frame_ms,graphics_tier`;
`avg_frame_ms` is the mean frame time over that window. `results.result.csv` has the device, then one row with the
alive and visible counts and the graphics tier at the last frame that met the 90 Hz budget (only frames with at least 400
alive count), the `budget_ms` (11.11), and a `stop_code`: 0 frames stayed over budget, 1 the enemy cap was reached,
2 the 90 s time limit ran out, 3 the run was aborted (shown as ABORTED and not stored). If the run has not finished,
that file holds only its header.

The battle spawn cap is set from the saved result at the next battle. Re-run the benchmark after changing graphics tiers.

To run the desktop preview instead:

```
godot --path godot -- --desktop
```

### Controls (VIVE XR Elite)

| Action | Control |
|---|---|
| Fire the right-hand weapon; click UI with the right hand | Right trigger |
| Fire the left-hand weapon; click UI with the left hand | Left trigger |
| Place tower on a pad (aim the left controller) | Left X |
| Sell tower (aim the left controller) | Left grip + left X |
| Upgrade tower (aim the left controller) | Left Y |
| Call next wave early | CALL WAVE button on the HUD (aim and pull a trigger) |
| Cycle tower type | Left stick Y |
| Cycle left-hand weapon / right-hand weapon | Left stick X / Right stick X |
| Advance dialogue; detonate deployed lemmings | Right A |
| Deploy a lemming squad (needs Ally Squad) | Right B |
| Grab and move the world | Hold both grips |
| Retreat from a battle | Left menu |

Desktop: left mouse fires and clicks UI, middle mouse places, Shift + middle sells, right mouse upgrades, G calls a wave,
Space or Enter advances, Escape retreats, Q/E cycle towers, and F/R cycle the weapon the mouse fires (the right-hand weapon).

## Verification status

Results below are from the last recorded runs. Nothing here was re-run for this update, because no Godot binary is
available in the build sandbox.

| Check | Result |
|---|---|
| All GDScript parses (core, game, tests) | Pass in the last recorded check (37 files, Godot 4.7.2 check-only). The tree now has 44 `.gd` files, so re-run it |
| Core rule tests (`godot --headless -s res://tests/core_checks.gd`) | 73 of 73 pass in the last recorded run |
| Headless smoke (`godot --headless --path godot -- --smoke`) | Pass in the last recorded run: hub tabs build, JSON round-trip, dialogue, scripted battle to an outcome, benchmark stop |
| Focus 3 action profile | Added from Godot 4.5 default bindings (`/interaction_profiles/htc/vive_focus3_controller`); parses in Godot |
| Android APK build | **Not built here.** The Android SDK comes from dl.google.com, which this sandbox cannot reach |
| On-device benchmark (enemy cap) | **Not run.** Needs the headset; use the steps above |
| Passthrough, controller clicks, speech on device | **Not verified** on hardware |

An earlier headless run reached about 5,400 alive and visible. That count measures what the simulation culls, not GPU
frame time, and it was not re-run for this update.

## Review fixes applied

- Controls: an untracked controller produces no pointer, so it cannot hover or click.
- Click-swallow on Focus 3: each hand has its own trigger edges with hysteresis, and the Focus 3 profile is bound (the generated map had none).
- Benchmark: the stop decision and the RESULT row use each frame, while the CSV's `avg_frame_ms` averages each 2 s window. It uses the saved graphics tier and reports an aborted run as ABORTED.
- Rules: starting credits no longer count toward the bank payout; the Logistics discount applies to upgrades; rail and nova ignore shots behind the controller; the wave director keeps spawns it cannot place; only one ending flag can be set.
- Saves: an unreadable save is backed up before a fresh profile starts; quality values from a hand-edited save are clamped; choices are saved immediately.

## Known gaps and risks

- **Not yet built or run on the headset.** The APK, controller bindings, passthrough, speech and the enemy cap all need an on-device check.
- **Passthrough**: the plugin's HTC wrapper exposes only `is_passthrough_supported` and `is_passthrough_started`. Passthrough is switched on by setting the blend mode to alpha. Whether the XR Elite shows the layer is unverified.
- **Speech**: on Android this is the device's text-to-speech engine, not a bundled neural model, so voices depend on what the device has installed. Piper runs on desktop only. Every speaker uses one voice; per-speaker voices need a multi-speaker model and the CLI's speaker flag.
- **Performance**: the simulation and renderer are GDScript, which is much slower than C#. The enemy ceiling on the headset depends on that cost, which is why the benchmark measures it rather than assuming a number.
- **Vendor plugin**: GitHub access to the GodotVR repository is blocked from the build sandbox. Install it with `scripts/fetch_openxr_vendors.sh` on your machine.
- **Story gap**: chapters 7 to 12 have no intro or outro dialogue yet, so they start and end without a story beat.
- **Licence gap, `sfx.shot.arc`** (the electric arc sound): its CC0-1.0 licence comes only from the README of the ctoth/claudio-soundpack-retro-arcade mirror, which has no LICENSE file. The entry stays in `godot/assets/manifest.json` and is marked as unconfirmed. Check it against Kenney's own page, or replace the file, before release.
- **Music files**: the battle and hub tracks are Kevin MacLeod tracks (CC-BY-4.0) in the manifest. A local copy made before that change still has the older files. Re-fetch them with `python3 scripts/fetch_assets.py --force --only music.battle --only music.hub` on a machine that can reach incompetech.com.
- Balance (wave sizes, costs, damage) is a first pass and has not been playtested.
- Leaderboard is local. There is no online service.

## License

Copyright (C) 2026 tigo.robotics@gmail.com

PointBlank Swarm is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
[GNU General Public License](LICENSE) for details.
