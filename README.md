# CashGrab - Co-op Wave Survival (prototype 0.1)

Comedy-first, round-based FPS for 1-4 players, built from the GDD (v0.1). One saloon-sized arena, three barricaded
entrances, a pistol and a shotgun, one zombie type, five waves. Godot **4.7** + GDScript, Jolt Physics.

## Run it

1. Open the project in Godot 4.7 and press **F5**. (If the editor was already open on this project when it was set
   up, use **Project > Reload Current Project** once: `project.godot` gained autoloads, an input map and the mic setting.)
2. **Play solo**, or **Host a game** and have friends **Join** your IP (default port `24567`, UDP).
   - Same machine: run two instances (**Debug > Customize Run Instances**), host in one, join `127.0.0.1` in the other.
   - LAN: the lobby lists your local IPs. Internet: forward UDP `24567` on the router and share your public IP.
   - Windows will ask about the firewall the first time you host; allow it on private networks.
3. The host presses **Start game**. Players can also join while a run is in progress.

| Key | Action | Key | Action |
|---|---|---|---|
| WASD / Space / Shift | move / jump / sprint | **F** | shove (1.2 s cooldown) |
| Mouse / LMB | look / fire | **G** (hold) | grab a nearby teammate and pull / drag them |
| R | reload | **E** (hold) | repair barricade, or revive a downed teammate |
| 1, 2 / wheel | pistol, shotgun | **V** (hold) / **M** | push-to-talk (if enabled) / mute mic |
| Esc | pause menu (mic mode, master + voice + per-teammate volume, sensitivity) | | |

## What is in v0.1 (GDD feature rules)

| GDD | Where | Notes |
|---|---|---|
| Co-op 1-4, lobby/host/join/disconnect | `autoload/net.gd`, `ui/` | listen-server over ENet; late join; full game turns a 5th player away; leaving cleans up grabs |
| Gunplay, 2 guns | `player/player_weapons.gd`, `resources/weapons/*.tres` | hitscan, falloff, recoil, reload, hit/kill markers; edit the `.tres` files to balance |
| Waves | `world/wave_manager.gd`, `game_config.gd` | 5 escalating waves, break between them, scales with player count |
| Barricades | `world/barricade.gd` | 5 boards, zombies break them, hold **E** to rebuild, blocked while something stands in the gap |
| Grab friends | `player/player.gd` (`_srv_grab`) | pull a teammate to you; dragging a downed one is slower for you and sets them behind you |
| Shove | `player/player.gd` (`_srv_shove`) | cone in front of you; launches teammates, staggers zombies |
| Downed + revive | `player/player.gd` | crawl, pistol only, 45 s bleed-out, 3.5 s hold-to-revive |
| Knockback | shove, shotgun (friendly fire = knockback, no HP), `world/explosive_barrel.gd` | host validates, owning client applies the launch |
| Ragdolls | `characters/puppet.gd`, `fx/ragdoll.gd`, `autoload/fx.gd` | local, short, pin-jointed primitives; capped at 10; players return to a normal body |
| Enemy AI | `enemy/zombie.gd` | walks to its entrance, breaks boards, then chases on a runtime-baked navmesh. From wave 3 a **Brute** (big, charges in a line, launches what it hits, bonks into walls) and from wave 4 **Huggers** (cling to a player: slow + a little drain until shoved or shot off). All zombies are clumsy: they trip over junk on the ground, over fallen zombies and each other, and lie on the floor for a moment. About 8% of kills (more for specials) drop a **snack** that heals 15 HP |
| Proximity voice | `autoload/voice.gd` | pure GDScript (mic capture, mu-law, host relay, per-speaker 3D playback) |

## Network model (host-authoritative)

| Thing | Authority | How it travels |
|---|---|---|
| Player position, aim, weapon | the owning peer | `TransformSync` ~30 Hz, remote players are smoothed |
| HP, downed/revive, bleed-out, grabs, kills | host | `StateSync` 10 Hz, plus an instant RPC to the owner |
| Shooting | shooter raycasts against what it sees, **host validates** (rate, range, plausibility) and applies damage | `srv_hits` RPC |
| Shove / grab / revive / repair | clients *request*, host decides | `srv_*` RPCs |
| Launch impulses | host computes, the victim's own client applies | `cl_launch` RPC (no bone replication) |
| Zombies, waves, boards, barrels | host | synchronizers; clients only render |
| Ragdolls, tracers, explosions | nobody: each peer renders its own from a tiny event | `Fx` RPCs |
| Voice | speaker -> host -> listeners within 28 m | unreliable, ENet channel 3 |

Player movement and hit detection are client-authoritative on purpose (responsive, simple, fine for friends; not
cheat-proof). Everything that changes the game state is decided on the host.

## Tuning

All numbers live in `scripts/game_config.gd` (speeds, damage, wave table, revive/bleed times, explosion strength...)
and `resources/weapons/*.tres`.

## Choices I made where the GDD was silent (easy to change)

- **Keys**: F shove, G grab, E repair/revive, V push-to-talk, M mute. Edit them in Project > Project Settings > Input Map.
- **Entrances** are three floor-level doorways (south, west, north); there is no window vaulting.
- **Downed players** are ignored by zombies and bleed out after 45 s; **eliminated** players come back at full health
  when the wave is cleared (`RESTORE_ON_WAVE_CLEAR`), so nobody sits out a whole test.
- **Ammo**: reserve is unlimited, only reloading limits you.
- **Friendly fire** never costs HP and never ragdolls the victim (just a knock-back and stumble). **Explosions** launch everyone nearby and do up to 50 HP to players (half a bar, less with distance)
  (`EXPLOSION_PLAYER_DAMAGE = 0` for knockback only). The level has **two** explosive barrels; the GDD says "one test
  explosion", so delete `Barrels/Barrel1` in `scenes/world/saloon.tscn` if you want exactly one.
- **Difficulty** is a first guess. The spawn budget scales with player count (x0.7 / 1.0 / 1.25 / 1.5). As a floor, I
  measured scripted bots that only stand still and shoot (`hard2` / `hard4`, no god mode): a pair lost around wave 3-4
  (the two runs I did ended on wave 4, then wave 3) and a team of four lost on wave 5 with 7 of its 36 zombies still to
  spawn. Players who move, shove and use the barricades should do clearly better; retune `WAVES`, `PLAYER_COUNT_SCALE`
  and `ZOMBIE_DAMAGE` in `game_config.gd` after real playtests.

## Tests

Real, separate game instances talk over ENet on localhost, each driven by a scripted bot (`tests/bots/`). Nothing
needs a window.

```powershell
$env:GODOT_BIN = "C:\path\to\Godot_v4.7-stable_win64_console.exe"   # the console exe must sit next to the main exe
.\tests\run_tests.ps1 -Test all          # or one of: m0 m1 m2 m3a m3b m4a m4b m4c m4d m5 soak2 soak4 hard2 hard4
```

| Test | Covers |
|---|---|
| m0 | movement sync, shove launch, grab pull and release (the GDD's "grab + launch" spike) |
| m1 | pistol kills, kill confirm, friendly-fire shotgun knockback with no HP loss, reload, zombie bites, HP regen |
| m2 | zombies break a barricade and walk in, repair prompt, holding E rebuilds boards |
| m3a | downed: crawl, pistol-only, revive, drag, bleed-out, wave-clear restore |
| m3b | shove ragdolls seen by observers, ragdoll cap, barrel explosion, game over + restart |
| m4a | joining mid-run sees the current world; a player leaving mid-grab is cleaned up |
| m4b | voice path with a test tone: encode, relay, decode, range culling (the GDD's "voice" spike, minus real audio hardware) |
| m4c | fifth player is refused; four distinct colours |
| m4d | host sends everyone back to the lobby and starts a second run from a clean world |
| m5 | clumsy zombies trip and lie down, brute charge, snack drop + healing, hugger latch + shove-off, friendly fire without the death ragdoll |
| soak2 / soak4 | a whole five-wave run with 2 / 4 scripted players at 3x speed in god mode (so unskilled bots always finish) |
| hard2 / hard4 | the same bots without god mode, as a difficulty probe; not part of `all` and allowed to fail |

Other bots: `nav_check` (every entrance has a navmesh path to the players:
`godot --headless --path . -- --solo --bot=nav_check --quit-after=15`), and `shots` / `shots2_host` + `shots2_client`
(screenshots; these need real windows, not `--headless`).

Useful command-line flags (after `--`), see `scripts/debug/dev_harness.gd`: `--solo`, `--host[=PORT]`,
`--join=IP[:PORT]`, `--autostart=N`, `--bot=NAME`, `--hold-waves`, `--god`, `--time-scale=N`, `--shot=PATH`.
`tools/setup_project.gd` and `tools/build_scenes.tscn` regenerate the project settings / all `.tscn` files
(re-running the latter overwrites manual scene edits).

One engine log line is expected when several clients quit at the same moment ("Unable to send packet on channel 0,
max channels: 0"): the engine sending a sync packet to a peer that is already disconnecting. It is harmless.

## Not verified by automated tests (needs a human)

- **Real microphone and speakers.** The voice path is tested end to end with a synthetic tone, but nobody has talked
  into it yet. If voice does not work for you, `v0.1` is marked incomplete by the GDD; start with the pause menu's
  mic meter. Needs the Windows microphone privacy setting to allow desktop apps. Audio quality is deliberately plain
  (12 kHz mu-law, ~12 KB/s per speaker); swap in Opus later if it matters.
- **Feel**: movement, recoil, knockback strength, difficulty, and how the procedural sounds sound (nobody has listened
  to them yet).
- Visuals were checked with screenshots from real windowed runs (solo, plus two windows for remote players, shove
  ragdoll, grab line, downed/revive prompt), not by playing.
- Real internet play: tests only use localhost. Latency-related feel (interpolation, hit registration) is untested.

## Placeholders

Characters are procedural boxes (`characters/puppet.gd`), sounds are synthesized at boot (`autoload/sfx.gd`), the
level is a blockout. Entrances are floor-level doorways (no window vaulting). The map can be replaced as long as
`saloon_level.gd`'s node names are kept (`Nav`, `Barricades`, `Barrels`, `PlayerSpawns`, `EnemySpawns`); the navmesh
is baked at runtime from the level's static colliders, so edits are picked up automatically.
