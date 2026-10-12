# Picket Line: design and module contract

Picket Line is a first-person station shooter in Godot 4.7 (GDScript). You hold a picket station at the centre of the sky
and shoot aliens that come in from 350 to 900 m away. Brute force (spray and pulse, heat as the limit) and skill (scope,
lance charge, weak core timing, focus time-slow, SNAP reaction bonus) both score. Desktop first (keyboard, mouse, gamepad).

## Loop

- Aliens approach along straight lines. Gunships, carriers and the dreadnought hold at range and fire telegraphed shots.
- Shells (gunship, dreadnought) fly for a while and hit only if the rail is still on the aim point. Beams (carrier) land
  at the end of their telegraph, so the player dodges by moving the rail or by a quick dodge (i-frames).
- Six sectors per run. Bosses end sectors 2, 4 and 6 (indices 1, 3 and 5). A win gives three upgrade cards, pick one.

## Coordinates

Metres, seconds, radians. Station at the origin, looking down -Z, Y up. `Balance.aim_dir(yaw, pitch)` gives the forward
vector; `Balance.aim_yaw_pitch(v)` is its inverse. The rail moves the muzzle in X (+-8 m) and Y (+-2.5 m).

## Core (engine-free, `core/`, tested by `tests/core_tests.gd`)

| File | Role |
|---|---|
| `rng.gd` (Rng) | xorshift64. `next()`, `range_f`, `range_i` (inclusive), `chance`, `pick`. |
| `balance.gd` (Balance) | All tuning. `ENEMY_DEFS`, `WEAPON_DEFS`, `DIFFICULTY`, `aim_dir`, `aim_yaw_pitch`. |
| `enemy.gd` (Enemy) | Plain data for one alien. |
| `enemy_ai.gd` (EnemyAI) | `step(e, dt, ctx, rng, out)`. ctx: `rail` (aim point), `fire_mult`. Appends events. |
| `station.gd` (Station) | Hull, shield, energy, heat, focus, rail, aim, dodge, `take_damage`. Real-time timers. |
| `weapons.gd` (Weapons) | Cooldowns, heat, energy, lance charge, swarm pods and lock cone. `try_fire(dt, cmd, station, muzzle, dir, projectiles, enemies, rng)`. |
| `projectiles.gd` (Projectiles) | Swept player shots (weak core first), flak detonation and falloff, enemy shells. `step(dt, enemies, station)`. |
| `sectors.gd` (Sectors) | Six sector themes and deterministic spawn schedules. |
| `scoring.gd` (Scoring) | Combo multiplier (1 + chain/3, max 8), kill points (weak x1.5, SNAP +50), sector bonus. |
| `upgrades.gd` (Upgrades) | Nine cards. `mods_for(ids)`, `with_defaults`, `offer(rng, owned, n)`. |
| `sim.gd` (Sim) | One sector. `step(dt, cmd) -> Array` of events, plus read-only state. |
| `run.gd` (Run) | Six sectors, upgrades, totals and the end of the run. |
| `save_data.gd` (SaveData) | Default settings and the top-ten table (`add_highscore`). |

### Sim command (`cmd` dictionary, all keys optional)

`aim` (Vector2 yaw and pitch delta, rad), `move_x`, `move_y` (-1..1), `scope`, `focus_held`, `fire_held`,
`fire_pressed`, `fire_released`, `dodge_pressed`, `dodge_dir` (+-1), `select` (weapon index or -1), `cycle` (-1/0/+1).

Focus slows enemies and projectiles to `FOCUS_TIME_SCALE` while held (and focus lasts). The station and the weapon
timers run on real time, so aim and dodge stay responsive.

### Sim events (`type` key)

`shot` {weapon, count, pos, charge?}, `lock` {ids}, `dry` {reason}, `overheat`, `charge_start`, `weapon` {weapon},
`dodge` {dir}, `hit` {enemy_id, damage, crit, weapon, pos, kind}, `detonate` {pos, radius, weapon},
`shot_expired` {pos}, `shell_miss` {pos}, `player_hit` {kind, damage, applied_hull, applied_shield, blocked, pos},
`enemy_fire` {kind, mode, from, to, hit?}, `telegraph` {enemy_id, kind, pos, time}, `crash` {kind, pos},
`launch` {kind, count, pos}, `boss_phase` {enemy_id, phase, pos}, `boss_warning` {kind}, `boss_spawn` {enemy_id, kind},
`wave_start` {wave}, `kill` {enemy_id, kind, points, weak, snap, boss, pos}, `combo` {mult, chain},
`snap` {enemy_id, pos}, `weak_hit` {enemy_id, pos}, `game_over` {score}, `sector_clear` {bonus, clean}.

### Enemies

| Kind | Behaviour | Notes |
|---|---|---|
| Scout | Dives; crashes for 6 hull at 20 m | Fast, 30 hp |
| Drone | Weaves in; crashes for 4 | 55 hp |
| Gunship | Holds at 140 m, shell every 2.6 s (0.9 s telegraph) | Weak nose at 3.4 m, always open |
| Bomber | Dives; detonates for 25 at 60 m | 80 hp |
| Carrier | Holds at 170 m; beam every 3.6 s; launches 4 scouts every 6 s | Weak core open 1.5 s of every 4 s |
| Dreadnought | Holds at 230 m; shells; three phases at 66% and 33% hp, each launches 5 drones | Weak core open 1.5 s of every 4 s |

### Weapons

| Weapon | Input | Notes |
|---|---|---|
| Pulse | Hold fire | 480 m/s, spread 2.4 deg (0.5 when scoped), heat 2.3 per shot |
| Lance | Hold to charge (0.15 s min, 1.2 s full), release | Damage 40 to 220, 1500 m/s, energy 24 |
| Flak | Hold fire, 1.2 s cooldown | Fuse 2.6 s or proximity 6 m, splash 8.5 m with falloff (min 15%) |
| Swarm | Hold fire | Up to 4 pods (+2 with card), lock within a 7 deg cone, homing, 1.1 s per pod |

Heat at 100 locks the weapons until it falls below 25. Energy regenerates at 16/s. Weak-point hits deal 2.2x.

### Scoring

Combo chain: a kill within 2.5 s of the previous one extends the chain. Multiplier = 1 + chain/3 (max 8).
Weak-point kills x1.5. SNAP = kill within 1 s of the alien first coming within 260 m, +50. Sector clear =
1000 x (sector number) + 2000 if no hull damage was taken.

### Sectors

| # | Name | Boss |
|---|---|---|
| 1 | Outer Picket | none |
| 2 | Debris Field | Carrier |
| 3 | Ion Storm | none |
| 4 | Carrier Lane | Carrier (1.4x hp) |
| 5 | Shattered Ring | none |
| 6 | Dreadnought Gate | Dreadnought |

## Engine layer (`game/`)

| File | Class | Role |
|---|---|---|
| `main.gd` | (scene root, `scenes/main.tscn`) | Flow: title, briefing, play, pause, sector result, upgrades, debrief. Owns Run and Sim. |
| `game_input.gd` | GameInput | `install()` registers actions in code. `poll(dt, settings) -> cmd`. Double-tap or Shift dodge. |
| `world.gd` | World | Environment, camera (follows the rail, scope FOV), cockpit, trauma shake. `build`, `set_sector`, `render`, `handle_events`. |
| `sky.gd` | Sky | Sphere with the sky shader, planet and ring, sun glare. |
| `enemy_view.gd` | EnemyView | One node per alien, flash, death shrink, weak-point markers, telegraph beams. |
| `fx.gd` | Fx | Pooled explosions, sparks, flashes and beams. Projectile rendering. |
| `hud.gd` | Hud | Crosshair, scope reticle, bars, weapon strip, score and combo, banners, popups, threat arrows. |
| `menus.gd` | Menus | Procedural screens. Emits `action(id, payload)`. |
| `audio.gd` | GameAudio | Crossfading music and a 16-voice SFX pool. Maps events to sounds. |
| `save.gd` | Save | Settings and scores in user://, atomic write. |

## Assets

- `scripts/gen_audio.py` writes `assets/audio/music_*.ogg` and `sfx_*.ogg` from numpy and ffmpeg (libvorbis).
  Project-owned output, so no third-party licences. The folder is git-ignored; run the script to generate it.
- Music: menu, calm, combat, boss (loop), victory and defeat (one-shot).
- Shaders: `shaders/sky.gdshader`, `enemy.gdshader`, `beam.gdshader`.

## Quality bar

- 60 fps target on a mid desktop GPU at 1080p with up to 120 aliens and 60 projectiles on screen.
- Every effect has a pool and a cap. No node creation in the hot path.
- Core rules stay deterministic: same seed and same commands give the same result (tested).
