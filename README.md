# PointBlank Swarm

A VR tower-defence / swarm shooter for a **Linux laptop driving an HTC VIVE XR Elite over OpenXR**.
Built in Godot 4.7 (.NET). Hold the line against thousands of polygon drones across six themed chapters.

## Features

- **Swarm combat**: up to 2,500 enemies alive at once by default, adapting to the headset's frame budget (see *Performance*).
- **Tower defence**: five towers (Turret, Tesla, Frost, Mortar, Sniper), three upgrade levels each, sell refunds 60%.
- **Held weapons**: Blaster, Scatter, Rail, Chain Arc, Nova Grenade, with built-in aim assist.
- **Early wave bonus**: call a wave early; the remaining prep time converts to credits.
- **Overkill credits**: damage beyond an enemy's remaining HP converts into credits.
- **Six chapters**: Space Opera, Superhero Metropolis, Noir Harbor, Ancient Egypt, Iron Pantheon, Neon Future. Original characters and names, inspired by those genres.
- **Story**: prologue, per-chapter intro and outro, branching choice (Sun Gate), two endings.
- **Offline voice**: Piper TTS (local VITS model) reads each line when installed; subtitles always show.
- **Upgrades**: eight levelled upgrades and eight one-time unlocks, bought in the hub between chapters.
- **Cheat codes**: each chapter clear reveals a four-digit code; redeem it on the keypad in CODES.
- **Leaderboard**: top ten local scores with generated callsigns.
- **Graphics**: MultiMesh instancing, billboard glow sprites beyond 3 m, bloom and fog per theme, adaptive resolution.

## Layout

```
godot/                 Godot project (open this folder)
  Core/                Engine-free simulation and rules (compiled by the tests too)
  Game/                Godot layer: rendering, input, UI, hub, story, flow
  scenes/Main.tscn     Entry scene (boots everything in code)
tests/CoreChecks/      Console tests for Core (57 checks)
scripts/fetch_voice.py Installs the Piper CLI and the offline voice model
```

## Run it

Requirements: Godot 4.7 **.NET** edition, and a .NET 8 SDK.

1. Install the voice (optional, but the story is written for it):
   ```
   python3 scripts/fetch_voice.py
   ```
2. Open `godot/` in the Godot editor (or `godot --path godot`). Press Play.
3. For the headset, make sure an OpenXR runtime is running and the XR Elite is connected. In
   *Project Settings > XR > OpenXR*, enable the **HTC VIVE Focus 3 controller** interaction profile
   (the XR Elite uses the same controller profile).
4. Without a headset the game starts in desktop preview. Force it with `godot --path godot -- --desktop`.

### Controls

| Action | VIVE XR Elite | Desktop |
|---|---|---|
| Fire held weapon / click UI | Right trigger | Left mouse |
| Place tower on pad | Left trigger (aim at a pad) | Middle mouse |
| Sell tower | Left grip + place | Shift + middle mouse |
| Upgrade tower | Right B/Y | Right mouse |
| Call next wave early | Left B/Y (or the CALL WAVE button) | G |
| Cycle tower type | Left stick X | Q / E |
| Cycle weapon | Right stick X | R / F |
| Advance dialogue | Right A/X | Space / Enter |
| Retreat / menu | Left menu | Escape |

## Performance and the enemy ceiling

The on-screen ceiling is **not yet measured on hardware**. What the code does:

- Enemies are simulated in flat arrays (`Core/Swarm.cs`). The simulation step for 5,000 enemies takes about 1 ms per frame on the development host (.NET, not the headset).
- Rendering uses MultiMeshes: one draw per low-poly shape plus one for glow sprites. Enemies outside the view cone are culled before any transform is written.
- Enemies within 3 m use low-poly meshes up to a mesh budget. Everything else becomes a billboard sprite.
- `Quality.cs` watches frame time against 90 Hz and lowers render scale, mesh budget and spawn cap when it falls behind, then recovers.
- **To find your headset's real maximum**: *Hub > OPTIONS > SWARM BENCHMARK*. It ramps the swarm and saves the highest visible count that held frame time. The result shows on the OPTIONS page.

## Verification status

| Check | Result |
|---|---|
| Core rules and simulation (`tests/CoreChecks`) | 57 of 57 pass |
| Godot C# build (Godot 4.7 .NET) | builds with 0 errors |
| Headless smoke (`godot --headless --path godot -- --smoke`) | passes: all hub tabs build, JSON saves round-trip, dialogue plays, scripted 8-wave battle reaches a result, benchmark completes |
| Piper CLI (`piper --help`) | confirms `--model` and `--output_file` |
| Voice model download | **not verified here**: this sandbox's proxy refused huggingface.co |
| Rendering, XR tracking, controller buttons | **not verified**: no display or headset in the build environment |

## Known gaps

- Controller input uses the action names in `godot/openxr_action_map.tres` (`trigger`, `grip`, `primary`, `ax_button`, `by_button`, `menu_button`), which Godot generated on import. They are not yet tested on the headset. If a button does nothing, check its binding in that file and in `Game/Controls.cs`.
- Linux OpenXR support for the XR Elite is unconfirmed. VIVE documents PC VR for the XR Elite through Windows (VIVE Streaming), and only mentions Linux in an experimental Steam Link VR note. If no Linux OpenXR runtime sees the headset, the desktop preview still runs.
- Balance numbers (wave sizes, costs, damage) are first-pass estimates. They have not been playtested.
- Every speaker uses the same Piper voice. `Story.Speakers` stores a `VoiceSid` and `Speed` per character, but `Game/Voice.cs` does not pass them to Piper yet. Wiring them up needs a multi-speaker model and the CLI's speaker flag.
- Leaderboard is local. There is no online service.

## License

Copyright (C) 2026 tigo.robotics@gmail.com

PointBlank Swarm is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
[GNU General Public License](LICENSE) for details.
