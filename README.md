# PointBlank Swarm

A VR tower-defence / swarm shooter for the **HTC VIVE XR Elite** (Android standalone, OpenXR).
Built in Godot 4.7 with GDScript. Hold the line against thousands of polygon drones across six themed chapters.

## Target

- Android APK on the XR Elite, deployed over adb. The headset is standalone, so there is no PC VR path.
- Desktop preview runs from the same project (`--desktop`) so you can test without the headset.
- Passthrough uses the HTC layer from the godot_openxr_vendors plugin (v3.0.0 or later; this build pins 5.1.0-stable).

## Features

- **Swarm combat**: up to 2,500 enemies alive by default. The on-device benchmark sets the real cap.
- **Tower defence**: five towers (Turret, Tesla, Frost, Mortar, Sniper), three upgrade levels each, sell refunds 60%.
- **Held weapons**: Blaster, Scatter, Rail, Chain Arc, Nova Grenade, with aim assist.
- **Early wave bonus**: call a wave early; the remaining prep time converts to credits.
- **Overkill credits**: damage beyond an enemy's remaining HP converts into credits.
- **Six chapters**: Space Opera, Superhero Metropolis, Noir Harbor, Ancient Egypt, Iron Pantheon, Neon Future. Original characters, inspired by those genres.
- **Story**: prologue, per-chapter intro and outro, a branching choice (the Sun Gate), two endings.
- **Speech**: Android uses the device text-to-speech engine (`DisplayServer.tts_speak`). Desktop preview uses the Piper CLI when installed. Subtitles always show.
- **Upgrades**: eight levelled upgrades and eight one-time unlocks, bought in the hub.
- **Cheat codes**: each chapter clear reveals a four-digit code; redeem it on the keypad in CODES.
- **Leaderboard**: top ten local scores with generated callsigns.
- **Graphics**: MultiMesh instancing, billboard glow sprites beyond 3 m, bloom and fog per theme, adaptive resolution.

## Layout

```
godot/                   Godot project (open this folder)
  core/                  Engine-free simulation and rules (GDScript)
  game/                  Engine layer: rendering, input, UI, hub, story, boot
  tests/core_checks.gd   Core rule tests (run headless)
  scenes/main.tscn       Entry scene
  project.godot          Renderer mobile, OpenXR enabled, TTS enabled
  export_presets.cfg     Android preset: arm64, Gradle build, OpenXR, HTC vendor features
  openxr_action_map.tres OpenXR bindings, including the VIVE Focus 3 / XR Elite profile
scripts/
  fetch_openxr_vendors.sh  Installs godot_openxr_vendors 5.1.0-stable into godot/addons
  fetch_voice.py           Installs the Piper CLI and voice model (desktop preview only)
  deploy_android.sh        Builds the APK, installs it over adb, launches it
  benchmark_pull.sh        Pulls the on-device swarm benchmark from logcat into a CSV
```

## Set up (on your machine)

You need Godot 4.7 (standard build, not .NET), its Android export templates, JDK 17, and the Android SDK
(platform-tools, build-tools, platform 35) with `ANDROID_HOME` set. Put `adb` on your PATH.

1. Install the vendor plugin (HTC passthrough and the export options):
   ```
   scripts/fetch_openxr_vendors.sh
   ```
2. Install the Gradle Android build template (the deploy script does this on first run if it is missing):
   ```
   godot --headless --path godot --install-android-build-template
   ```
3. On the XR Elite: enable developer mode and USB debugging, then connect it with USB and accept the prompt.

## Build, deploy and benchmark

```
GODOT=/path/to/godot scripts/deploy_android.sh          # debug APK, install, launch
```

Then on the headset: **Hub > OPTIONS > SWARM BENCHMARK**. The benchmark ramps the swarm until frames stop holding
90 Hz. When it finishes, pull the results to your machine:

```
scripts/benchmark_pull.sh results.csv
```

The CSV has one row every 2 s (elapsed, alive, visible, average frame time, graphics tier) and a `RESULT` row with the
sustained alive count, visible count and tier at the last in-budget frame. The battle spawn cap is set from that result on
the next launch. Re-run the benchmark after changing graphics tiers.

To run the desktop preview instead:

```
godot --path godot -- --desktop
```

### Controls (VIVE XR Elite)

| Action | Control |
|---|---|
| Fire held weapon / click UI | Right trigger |
| Place tower on pad, or click UI with the left hand | Left trigger (aim at a pad) |
| Sell tower | Left grip + place |
| Upgrade tower | Right B/Y |
| Call next wave early | Left B/Y |
| Cycle tower type / weapon | Left stick X / Right stick X |
| Advance dialogue | Right A/X |
| Retreat / menu | Left menu |

Desktop: left mouse fires and clicks UI, middle mouse places, Shift + middle sells, right mouse upgrades, G calls a wave,
Space or Enter advances, Escape retreats, Q/E and R/F cycle towers and weapons.

## Verification status

| Check | Result |
|---|---|
| All GDScript parses (core, game, tests) | Pass (37 files, Godot 4.7.2 check-only) |
| Core rule tests (`godot --headless -s res://tests/core_checks.gd`) | 73 of 73 pass |
| Headless smoke (`godot --headless --path godot -- --smoke`) | Pass: hub tabs build, JSON round-trip, dialogue, scripted battle to an outcome, benchmark stop |
| Focus 3 action profile | Added from Godot 4.5 default bindings (`/interaction_profiles/htc/vive_focus3_controller`); parses in Godot |
| Android APK build | **Not built here.** The Android SDK comes from dl.google.com, which this sandbox cannot reach |
| On-device benchmark (enemy cap) | **Not run.** Needs the headset; use the steps above |
| Passthrough, controller clicks, speech on device | **Not verified** on hardware |

The headless benchmark numbers (about 5,400 alive and visible) measure what the simulation culls, not GPU frame time.

## Review fixes applied

- Controls: an untracked controller produces no pointer, so it cannot hover or click.
- Click-swallow on Focus 3: each hand has its own trigger edges with hysteresis, and the Focus 3 profile is bound (the generated map had none).
- Benchmark: samples per frame (no 2-second averaging), uses the saved graphics tier, and reports an aborted run as ABORTED.
- Rules: starting credits no longer count toward the bank payout; the Logistics discount applies to upgrades; rail and nova ignore shots behind the controller; the wave director keeps spawns it cannot place; only one ending flag can be set.
- Saves: an unreadable save is backed up before a fresh profile starts; quality values from a hand-edited save are clamped; choices are saved immediately.

## Known gaps and risks

- **Not yet built or run on the headset.** The APK, controller bindings, passthrough, speech and the enemy cap all need an on-device check.
- **Passthrough**: the plugin's HTC wrapper exposes only `is_passthrough_supported` and `is_passthrough_started`. Passthrough is switched on by setting the blend mode to alpha. Whether the XR Elite shows the layer is unverified.
- **Speech**: on Android this is the device's text-to-speech engine, not a bundled neural model, so voices depend on what the device has installed. Piper runs on desktop only. Every speaker uses one voice; per-speaker voices need a multi-speaker model and the CLI's speaker flag.
- **Performance**: the simulation and renderer are GDScript, which is much slower than C#. The enemy ceiling on the headset depends on that cost, which is why the benchmark measures it rather than assuming a number.
- **Vendor plugin**: GitHub access to the GodotVR repository is blocked from the build sandbox. Install it with `scripts/fetch_openxr_vendors.sh` on your machine.
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
