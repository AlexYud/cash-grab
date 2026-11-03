# CashGrab - Co-op Wave Survival (prototype 0.1)

Comedy-first, round-based FPS for 1-4 players, built from the GDD (v0.1). A saloon with five barricaded windows plus two
lockable rooms behind it (annex and hall, two windows each), eleven weapons with roguelike reward cards, six zombie
types, endless waves, a shared cash pot. Godot **4.7** +
GDScript, Jolt Physics.

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
| Mouse / LMB / **RMB** (hold) | look / fire / aim down sights (tighter spread, slower, zoomed) | **G** (hold) | grab a nearby teammate and pull / drag them |
| R | reload | **E** (hold) | repair barricade, revive a teammate, pull levers, use the mystery box and health shops |
| 1-6 / wheel | pistol, shotgun, Yank Gun, Disco Blaster, Tesla Gun, Boing Gun (only the ones you own) | **V** (hold) / **M** | push-to-talk (if enabled) / mute mic |
| Esc | pause menu (mic mode, master + voice + per-teammate volume, sensitivity) | | |

## What is in v0.1 (GDD feature rules)

| GDD | Where | Notes |
|---|---|---|
| Co-op 1-4, lobby/host/join/disconnect | `autoload/net.gd`, `ui/` | listen-server over ENet; late join; full game turns a 5th player away; leaving cleans up grabs |
| Gunplay, 11 weapons | `player/player_weapons.gd`, `resources/weapons/*.tres` | hitscan, falloff, recoil, reload, hit/kill markers; edit the `.tres` files to balance. **You start with only the pistol**; new weapons and buffs come from the reward cards between waves (see below). **Headshots do 2x damage** (gold hit marker, not an instakill). Holding **RMB** aims down the sights. **Yank Gun** reels what it hits (zombie or teammate) in to you; **Disco Blaster** makes zombies dance for 3 s instead of attacking; **Tesla Gun** arcs lightning from the zombie it hits to the three nearest zombies (60/40/25% of the damage, blue bolts + flash); **Boing Gun** bounces zombies into the air and trips them |
| Shared cash | `world/wave_manager.gd` (`cash`), `ui/hud.gd` | one pot for the whole party, shown top-left: +$10 per kill ($25 for specials, +$5 for a headshot kill), +$5 per repaired board. Everything below is paid from it |
| Annex (new area) | `world/annex.gd`, `world/interactable.gd`, `tools/build_scenes.gd` | a bigger room east of the saloon (more cover, 2 more barricaded windows, lamps) behind a gate. Two **levers** in the saloon cost $250 each (hold **E** 1.5 s). The first latches for 20 s: pull the second in time (one player can do both) and a 4 s door animation opens the gate. **Hold E on a latched lever to put it back for a refund**; if the 20 s run out it refunds itself. Annex windows only spawn zombies once it is open |
| Mystery box / health shops | `world/interactable.gd` | in the hall: **mystery box** ($400) gives a random **support item**: bandages, a full medkit, an armor vest (+50, absorbs 60% of every hit), adrenaline (30 s of speed) or Second Wind (one free self-revive). In the annex: **medkit** ($250, full heal). In the saloon: **bandages** ($75, +25 HP). Shops have a 30 s cooldown per player. They are the only healing besides snacks |
| Invisible walls | `world/barricade.gd`, `scenes/world/barricade.tscn` (`PlayerWall`) | every window has a wall only players collide with, so nobody can leave the building even when all boards are gone (zombies still climb in) |
| Stumble | `player/player.gd` (`_srv_stumble`) | running or walking into a zombie lying on the floor trips you for about a second; jumping over it is safe |
| Saved settings | `ui/pause_menu.gd`, `ui/ui_kit.gd` | master volume and mouse sensitivity are saved to `user://settings.cfg` (voice and per-player volumes already were) |
| Waves | `world/wave_manager.gd`, `game_config.gd` (`wave_cfg`) | **endless**: the table covers ten waves, then every wave is bigger, tougher and faster (capped); scales with player count. Between waves nothing counts down: the next wave starts when **every player has pressed ready** ([Enter] or the button) |
| Reward cards | `weapons/weapon_cards.gd`, `ui/card_screen.gd`, `world/wave_manager.gd` | every time a wave is cleared each player gets **three personal cards** (random weapons, rolled on the host): a weapon you do not have shows as **NEW** with a rotating 3D model, name and a one-line description; one you already own becomes an **UPGRADE** card. Click a card or press [1] [2] [3]; [Tab] hides the screen so you can walk around, [Enter] (or the button) is ready. Upgrades stack: damage, bigger magazine, fire rate, knockback, and effects: **Bleeding**, **Vampiric** (lifesteal), **Frostbite** (slow), **Static Spark** (lightning to two more zombies), **Boom Rounds** (area burst), **Springy** (boing) and **Disco Fever** |
| New weapons | `weapons/gun_models.gd`, `resources/weapons/*.tres` | **Assault Rifle** (hold to fire, 30 rounds), **Sniper Rifle** (RMB zooms far in, one shot kills most zombies), and three melee weapons that need no ammo: **Baseball Bat** (huge knockback, sometimes flattens them), **Katana** (fast, hits up to 3), **Axe** (slow, cleaves up to 5). Number keys pick the Nth weapon you own |
| The hall (part 3) | `world/annex.gd` (`stage`), `tools/build_scenes.gd` | a third room behind the annex's east wall, opened by its own pair of levers on that wall at **$500 each** (same latch / refund rules as the annex). It has two more windows, the mystery box and plenty of cover |
| Crawler | `enemy/zombie.gd` (`_tick_crawl`), `characters/zombie_rig.gd` | climbs out of a wall vent, runs up the wall and **walks the ceiling upside down** towards the nearest player, then drops on them (damage + a shove) and fights on the ground. It can be shot on the ceiling. Vents exist in every room and only open with that room. Appears from wave 4 |
| Team bars | `ui/hud.gd` | everybody's health (and armor) as a thin bar with a name in the top-left corner, DOWN / OUT states included |
| Barricades | `world/barricade.gd` | 5 boards, zombies break them, hold **E** to rebuild, blocked while something stands in the gap |
| Grab friends | `player/player.gd` (`_srv_grab`, `_srv_throw`) | pull a teammate to you. **Grab a downed teammate and you carry them** (your weapons lock): **Fire** throws them. Any player flying fast (thrown, shoved, blown up) is a bowling ball and knocks zombies over |
| Shove | `player/player.gd` (`_srv_shove`) | cone in front of you; launches teammates, staggers zombies (half the time it knocks them limp into a ragdoll; Huggers always) |
| Downed + revive | `player/player.gd` | crawl, pistol only, 45 s bleed-out, 3.5 s hold-to-revive |
| Knockback | shove, shotgun (friendly fire = knockback, no HP), `world/explosive_barrel.gd` | host validates, owning client applies the launch |
| Zombie body + ragdolls | `characters/zombie_rig.gd`, `autoload/fx.gd` | zombies use the rigged model in `assets/`: bones are posed by code per state and kind (shamble, swing, brute stomp / charge, leaper crouch + pounce, hugger cling, dance, reel). When a zombie trips, is shoved over, blown up or killed, the skeleton is handed to `PhysicalBone3D` bodies: nobody steers the limbs. Getting up blends from the ragdoll back into the animated pose. Every peer runs its own ragdoll (a tether keeps it near the host-authoritative hit shape); corpses are capped at 10. A limp zombie sliding fast bowls over whoever it hits. Players never ragdoll: they get knocked back and stagger (`characters/puppet.gd`, boxes) |
| Enemy AI | `enemy/zombie.gd` | walks to its entrance, breaks boards, then chases on a runtime-baked navmesh (it only swings or latches with a clear line to its target, so no hitting through walls: it goes around). Specials arrive from wave 3: **Brute** (big, charges in a line, launches what it hits, bonks into walls), **Hugger** (clings to a player: slows them and drains a little HP until shoved or shot off), **Leaper** (pounces, then faceplants), **Bloater** (bursts into goo when killed, knocking everyone nearby over). Health no longer regenerates: snacks are the only healing. All zombies are clumsy: they trip over junk on the ground, over fallen zombies and each other, and lie on the floor for a moment. About 8% of kills (more for specials) drop a **snack** that heals 15 HP |
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
- **Entrances** are floor-level doorways (no window vaulting): south x2, west x2, north in the saloon, plus north and
  south in the annex (9 in total, `Barricades/*` indexed 0-8 with matching `EnemySpawns/E0-E8`; 5 saloon, 2 annex, 2 hall).
- **Cash amounts** (`CASH_*`, `LEVER_COST`, `BOX_COST`, `BANDAGE_COST`, `MEDKIT_COST` in `game_config.gd`) are first guesses.
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
.\tests\run_tests.ps1 -Test all          # or one of: m0 m1 m2 m3a m3b m4a m4b m4c m4d m5 m6 m7 m8 m9 m10 nav soak2 soak4 hard2 hard4
```

| Test | Covers |
|---|---|
| m0 | movement sync, shove launch, grab pull and release (the GDD's "grab + launch" spike) |
| m1 | pistol kills, kill confirm, friendly-fire shotgun knockback with no HP loss, reload, zombie bites, no health regeneration |
| m2 | zombies break a barricade and walk in, repair prompt, holding E rebuilds boards |
| m3a | downed: crawl, pistol-only, revive, drag, bleed-out, wave-clear restore |
| m3b | shove ragdolls seen by observers, ragdoll cap, barrel explosion, game over + restart |
| m4a | joining mid-run sees the current world; a player leaving mid-grab is cleaned up |
| m4b | voice path with a test tone: encode, relay, decode, range culling (the GDD's "voice" spike, minus real audio hardware) |
| m4c | fifth player is refused; four distinct colours |
| m4d | host sends everyone back to the lobby and starts a second run from a clean world |
| m5 | clumsy zombies trip and lie down, brute charge, snack drop + healing, hugger latch + shove-off, friendly fire without the death ragdoll |
| m6 | carry and throw a downed teammate (bowling), Yank Gun, Disco Blaster, Leaper pounce, Bloater burst |
| m7 | (pistol-only start) shared cash from kills / headshot kills / specials / board repair, headshot = 2x damage, invisible walls at open windows, bandage stand + per-player cooldown, annex: price check, pull, cancel + refund, timeout refund, single-player two-lever flow, closed gate blocks, door animation, annex windows activate, mystery box, medkit, Tesla chain + lightning, Boing launch, stumble over a fallen zombie, ADS |
| m9 | the ready button (no countdown, waits for everybody), three reward cards per player, picking, a second pick doing nothing, buff numbers, every card effect (bleed, freeze, lifesteal, spark, boing, disco, blast), endless waves (wave 10 -> 11), armor, Second Wind, adrenaline, team bars, a spectator has no gun |
| m10 | assault rifle auto-fire, sniper zoom + one-shot, bat / katana / axe cones, the crawler (wall -> ceiling -> upside down on both peers -> shot -> drop -> lands), vents in all rooms |
| m8 | rigged zombies: every kind builds a 25-bone rig with its feet on the floor, poses differ per state (cling, charge, dance, swing, walk cycle), a trip hands the skeleton to physics (host and client), the limp body lies down near its hit shape and gets back up, a blast flings the ragdoll, a flying ragdoll bowls over a neighbour, a zombie killed while limp leaves a corpse in that pose, corpse cap |
| nav | every window has a navmesh route from outside to the players, and the shop / lever spots are reachable |
| soak2 / soak4 | an eight-wave run with 2 / 4 scripted players at 3x speed in god mode (so unskilled bots always finish): they pick cards and press ready between waves, rotate weapons, and the host opens the annex from wave 3 and the hall from wave 5 so every window and vent is exercised |
| hard2 / hard4 | the same bots without god mode, as a difficulty probe; not part of `all` and allowed to fail |

Other bots: `shots` / `shots2_host` + `shots2_client` (screenshots; these need real windows, not `--headless`).
Every test except the weapon-shop rules (`m7`, `Plain = $true`) runs with `--all-weapons`, so bots start with every gun.

Useful command-line flags (after `--`), see `scripts/debug/dev_harness.gd`: `--solo`, `--host[=PORT]`,
`--join=IP[:PORT]`, `--autostart=N`, `--bot=NAME`, `--hold-waves`, `--god`, `--all-weapons`, `--time-scale=N`, `--shot=PATH`.
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

Players are procedural boxes (`characters/puppet.gd`; zombies use the rigged model, see above), sounds are synthesized at boot (`autoload/sfx.gd`), the
level is a blockout. Entrances are floor-level doorways (no window vaulting). The map can be replaced as long as
`saloon_level.gd`'s node names are kept (`Nav`, `Barricades`, `Barrels`, `PlayerSpawns`, `EnemySpawns`, plus `Annex` and
`Interactables` for the gate, levers and shops); the navmesh is baked at runtime from the level's static colliders
(the gate sits outside `Nav` on purpose), so edits are picked up automatically.
