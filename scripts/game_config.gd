class_name GameConfig
extends RefCounted
## Central tuning values. Change numbers here while playtesting; nothing else needs to move.

# --- Physics layers (names are registered in project.godot by tools/setup_project.gd) ---
const L_WORLD := 1
const L_PLAYERS := 2
const L_ENEMIES := 4
const L_BARRICADES := 8
const L_RAGDOLLS := 16
const L_PROPS := 32

# Players do not collide with each other (no body blocking in doorways); zombies do not
# collide with each other (soft separation instead) so queues at barricades never jam.
const MASK_PLAYER_BODY := L_WORLD | L_ENEMIES | L_BARRICADES | L_PROPS
const MASK_ENEMY_BODY := L_WORLD | L_PLAYERS | L_BARRICADES | L_PROPS
const MASK_HITSCAN := L_WORLD | L_PLAYERS | L_ENEMIES | L_PROPS
const MASK_RAGDOLL := L_WORLD | L_PROPS

# --- Player movement ---
const PLAYER_MAX_HP := 100
const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.4
const CRAWL_SPEED := 1.5
const GRAVITY := 16.0
const JUMP_VELOCITY := 5.3
const GROUND_ACCEL := 48.0
const AIR_ACCEL := 9.0
const STAGGER_GROUND_ACCEL := 7.0
const STAGGER_AIR_ACCEL := 1.5
const STAGGER_CONTROL := 0.35 # fraction of normal input authority while staggered
const MAX_LAUNCH_SPEED := 18.0
const EYE_HEIGHT := 1.62
const EYE_HEIGHT_DOWNED := 0.5
const MOUSE_SENS := 0.0022
const REMOTE_SMOOTHING := 18.0 # higher = snappier remote players / enemies
const REMOTE_SNAP_DISTANCE := 4.0

# --- Shove ---
const SHOVE_COOLDOWN := 1.2
const SHOVE_RANGE := 2.4
const SHOVE_HALF_ANGLE_DEG := 50.0
const SHOVE_PLAYER_H := 8.5
const SHOVE_PLAYER_V := 4.0
const SHOVE_ENEMY_H := 6.5
const SHOVE_ENEMY_STAGGER := 0.9
const SHOVE_ENEMY_DAMAGE := 8

# --- Grab / drag ---
const GRAB_REACH := 2.8
const GRAB_BREAK_DISTANCE := 5.5
const GRAB_PULL_SPEED := 6.5
const GRAB_PULL_GAIN := 5.0
const GRAB_HOLD_DISTANCE := 1.3
const GRAB_TARGET_INPUT := 0.35 # how much a grabbed player can still steer
const GRAB_SLOW := 0.75
const DRAG_SLOW := 0.55

# --- Downed / revive ---
const BLEED_OUT_TIME := 45.0
const REVIVE_TIME := 3.5
const REVIVE_REACH := 2.4
const REVIVE_HP := 50
const INVULN_AFTER_REVIVE := 2.0
const HP_REGEN_DELAY := 5.0
const HP_REGEN_RATE := 15.0
## When a wave is cleared, downed and eliminated players come back (so nobody sits out a whole test).
const RESTORE_ON_WAVE_CLEAR := true

# --- Interaction ---
const REPAIR_TIME_PER_BOARD := 1.2 # seconds of one player's work
const INTERACT_REACH := 2.6

# --- Zombies ---
const ZOMBIE_DAMAGE := 15
const ZOMBIE_ATTACK_RANGE := 1.5
const ZOMBIE_WINDUP := 0.5
const ZOMBIE_ATTACK_COOLDOWN := 1.3
const ZOMBIE_BOARD_DAMAGE := 20.0
const ZOMBIE_BOARD_INTERVAL := 1.4
const BOARD_HP := 60.0

# --- Waves: count/alive-cap/spawn-interval/hp/speed per wave (five test waves) ---
const WAVES: Array[Dictionary] = [
	{"count": 6, "max_alive": 6, "interval": 1.8, "hp": 100, "speed": 2.2},
	{"count": 10, "max_alive": 8, "interval": 1.5, "hp": 110, "speed": 2.4},
	{"count": 14, "max_alive": 10, "interval": 1.3, "hp": 120, "speed": 2.6},
	{"count": 18, "max_alive": 12, "interval": 1.1, "hp": 135, "speed": 2.8},
	{"count": 24, "max_alive": 14, "interval": 0.9, "hp": 150, "speed": 3.0},
]
## Spawn budget is scaled by the number of players (index = players - 1).
const PLAYER_COUNT_SCALE: Array[float] = [0.7, 1.0, 1.25, 1.5]
const FIRST_BREAK := 10.0
const BREAK_TIME := 14.0

# --- Explosions ---
const EXPLOSION_RADIUS := 6.0
const EXPLOSION_FORCE := 15.0
const EXPLOSION_UP := 7.0
const EXPLOSION_ENEMY_DAMAGE := 160
const EXPLOSION_PLAYER_DAMAGE := 15 # set to 0 for knockback-only explosions

# --- Effects ---
const MAX_RAGDOLLS := 10
const MAX_DEBRIS := 14
