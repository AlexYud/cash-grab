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
const L_HUG := 64 ## a Hugger clinging to a player: shootable, but does not push the player around
const L_PLAYER_WALL := 128 ## invisible wall that only players collide with (keeps them inside, zombies pass)

# Players do not collide with each other (no body blocking in doorways); zombies do not
# collide with each other (soft separation instead) so queues at barricades never jam.
const MASK_PLAYER_BODY := L_WORLD | L_ENEMIES | L_BARRICADES | L_PROPS | L_PLAYER_WALL
const MASK_ENEMY_BODY := L_WORLD | L_PLAYERS | L_BARRICADES | L_PROPS
const MASK_HITSCAN := L_WORLD | L_PLAYERS | L_ENEMIES | L_PROPS | L_HUG
const MASK_RAGDOLL := L_WORLD | L_PROPS
const MASK_ZOMBIE_RAGDOLL := L_WORLD | L_PROPS | L_BARRICADES | L_PLAYERS | L_RAGDOLLS ## limp zombies pile up and players can bump them around

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
const SHOVE_TRIP_CHANCE := 0.5 ## chance that a shoved zombie (other than the brute) goes limp instead of just reeling

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
	{"count": 14, "max_alive": 10, "interval": 1.3, "hp": 120, "speed": 2.6, "brutes": 1},
	{"count": 18, "max_alive": 12, "interval": 1.1, "hp": 135, "speed": 2.8, "brutes": 1, "huggers": 2, "leapers": 2},
	{"count": 24, "max_alive": 14, "interval": 0.9, "hp": 150, "speed": 3.0, "brutes": 2, "huggers": 3, "leapers": 3, "bloaters": 1},
	{"count": 28, "max_alive": 15, "interval": 0.85, "hp": 160, "speed": 3.1, "brutes": 2, "huggers": 3, "leapers": 3, "bloaters": 2},
	{"count": 32, "max_alive": 16, "interval": 0.8, "hp": 170, "speed": 3.2, "brutes": 3, "huggers": 4, "leapers": 4, "bloaters": 2},
	{"count": 36, "max_alive": 18, "interval": 0.75, "hp": 180, "speed": 3.3, "brutes": 3, "huggers": 4, "leapers": 5, "bloaters": 3},
	{"count": 40, "max_alive": 20, "interval": 0.7, "hp": 195, "speed": 3.4, "brutes": 4, "huggers": 5, "leapers": 5, "bloaters": 3},
	{"count": 46, "max_alive": 22, "interval": 0.6, "hp": 210, "speed": 3.5, "brutes": 5, "huggers": 6, "leapers": 6, "bloaters": 4},
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
const EXPLOSION_PLAYER_DAMAGE := 50 # at the centre, falling off with distance (50 = half a health bar); 0 for knockback only

# --- Effects ---
const MAX_RAGDOLLS := 10
const MAX_DEBRIS := 14

# --- Special zombies (waves list "brutes"/"huggers" = extra spawns on top of "count", scaled by player count) ---
const BRUTE_HP_MULT := 4.0
const BRUTE_SPEED := 1.9
const BRUTE_DAMAGE := 30
const BRUTE_BOARD_MULT := 3.0
const BRUTE_CHARGE_COOLDOWN := 7.0
const BRUTE_CHARGE_WINDUP := 0.8
const BRUTE_CHARGE_TIME := 1.1
const BRUTE_CHARGE_SPEED := 9.5
const BRUTE_CHARGE_MIN := 4.0
const BRUTE_CHARGE_MAX := 12.0
const HUGGER_HP := 70
const HUGGER_SPEED := 4.0
const HUGGER_DPS := 4.0 ## damage per second to the player it clings to
const HUGGER_SLOW := 0.4 ## the hugged player's movement multiplier

# --- Clumsy zombies (procedural stumbles; fallen zombies are slowed down, not easier to damage) ---
const TRIP_CHANCE := 0.7 ## when passing over junk on the ground or over a fallen zombie
const TRIP_COOLDOWN := 5.0
const TRIP_RANDOM_PER_SEC := 0.03 ## plain stumbling for no reason
const FALL_MIN := 1.9 ## a limp zombie lies there for about two seconds, then gets up
const FALL_MAX := 2.1
const FALL_SLIDE_DECAY := 6.0 ## a limp body slides much farther than a walking one is pushed (m/s^2)
const CLUMSY_HIT_CHANCE := 0.35 ## an attacking zombie's wild swing catches a neighbour standing in front of it
const CLUMSY_TRIP_CHANCE := 0.5 ## ...who then goes limp instead of just reeling
const CLUMSY_SELF_TRIP := 0.07 ## ...and now and then the swing throws the attacker off balance too
const BRUTE_THROW_SPEED := 8.5 ## the giant flings anything it walks into
const BRUTE_THROW_LIFT := 4.5
const BRUTE_PLOW_RADIUS := 1.5
const GETUP_TIME := 0.8

# --- Snacks: rare healing drops ---
const SNACK_CHANCE := 0.08
const SNACK_CHANCE_HUGGER := 0.25
const SNACK_CHANCE_BRUTE := 0.6
const SNACK_HEAL := 15
const SNACK_LIFETIME := 20.0

# --- More specials ---
const LEAPER_HP := 80
const LEAPER_SPEED := 3.6
const LEAPER_DAMAGE := 12
const LEAPER_COOLDOWN := 4.5
const LEAPER_WINDUP := 0.55
const LEAPER_MIN := 3.2
const LEAPER_MAX := 8.5
const BLOATER_HP := 160
const BLOATER_SPEED := 1.6
const BLOATER_DAMAGE := 10
const BLOATER_BURST_RADIUS := 3.6
const SNACK_CHANCE_LEAPER := 0.15
const SNACK_CHANCE_BLOATER := 0.2

# --- Carrying / throwing downed teammates, and "human bowling" ---
const THROW_SPEED := 15.0
const THROW_UP := 5.5
const BOWLING_MIN_SPEED := 6.5 ## a flying player faster than this knocks zombies over
const BOWLING_DAMAGE := 25

# --- Headshots, aiming down sights, stumbling on fallen zombies ---
const HEADSHOT_MULT := 2.0 ## critical damage, not an instant kill
const HEAD_BAND := 0.15 ## metres (scaled with the zombie's size) below the middle of the animated head where a headshot still counts
const ADS_FOV := 52.0
const ADS_SPREAD_MULT := 0.35
const ADS_SPEED_MULT := 0.65
const STUMBLE_RANGE := 1.7 ## a fallen zombie's body stops you at ~1.25 m head-on, so the trip must fire before contact
const STUMBLE_MIN_SPEED := 2.0
const STUMBLE_STAGGER := 1.0
const STUMBLE_COOLDOWN := 2.5

# --- Shared cash: one pot for the whole team ---
const CASH_KILL := 20
const CASH_KILL_SPECIAL := 50
const CASH_HEADSHOT_BONUS := 10
const CASH_PER_BOARD := 10
## Clearing a wave pays a bonus that grows with the wave, so even a quiet round affords at least one purchase.
const CASH_WAVE_CLEAR_BASE := 100
const CASH_WAVE_CLEAR_STEP := 40

# --- The annex (levers, door, shops) ---
const LEVER_COST := 150
const LEVER_HOLD := 1.5
const LEVER_CANCEL_HOLD := 0.5 ## hold time to put a latched lever back
const LEVER_WINDOW := 20.0 ## after the first lever is pulled, this long to pull the other one (else refunded)
const DOOR_TIME := 4.0
const BOX_COST := 250
const BOX_HOLD := 1.0
const BANDAGE_COST := 50
const BANDAGE_HEAL := 25
const MEDKIT_COST := 150
const SHOP_HOLD := 0.8
const SHOP_COOLDOWN := 30.0

# --- Tesla gun ---
const TESLA_RANGE := 5.5
const TESLA_FALLOFF: Array[float] = [0.6, 0.4, 0.25] ## damage fraction on each chained zombie

# --- Part 3 (the hall), crawlers, support items, rewards ---
const LEVER_COST_STAGE2 := 300## the second pair of levers costs more
const CRAWLER_HP := 90
const CRAWLER_SPEED := 2.9
const CRAWLER_DAMAGE := 14
const CEILING_Y := 4.0 ## underside of the roof: where crawlers walk upside down
const CRAWLER_CLIMB_SPEED := 2.6
const CRAWLER_DROP_RANGE := 2.2
const SNACK_CHANCE_CRAWLER := 0.15
const ARMOR_ABSORB := 0.6 ## share of every hit the vest soaks up
const ARMOR_MAX := 100
const ARMOR_ITEM := 50
const ADRENALINE_TIME := 30.0
const ADRENALINE_SPEED := 1.35
const SECOND_WIND_HP := 50


## Settings for wave n (1-based). The table covers the first ten; after that every wave is a bit bigger, tougher and
## faster than the last (with caps so it stays playable), so there is no final round. Crawlers show up from wave 4.
static func wave_cfg(n: int) -> Dictionary:
	var cfg: Dictionary
	if n <= WAVES.size():
		cfg = WAVES[n - 1].duplicate()
	else:
		var extra := n - WAVES.size()
		cfg = WAVES[WAVES.size() - 1].duplicate()
		cfg["count"] = int(cfg["count"]) + 5 * extra
		cfg["max_alive"] = mini(int(cfg["max_alive"]) + extra, 30)
		cfg["interval"] = maxf(float(cfg["interval"]) - 0.015 * extra, 0.35)
		cfg["hp"] = int(cfg["hp"]) + 16 * extra
		cfg["speed"] = minf(float(cfg["speed"]) + 0.04 * extra, 4.1)
		for k in ["brutes", "huggers", "leapers", "bloaters"]:
			cfg[k] = int(cfg[k]) + (extra + 1) / 2
	cfg["crawlers"] = 0 if n < 4 else 1 + (n - 4) / 2
	return cfg


# --- Wall buys (COD style: one spot per item, spread over the rooms) and the upgrader machines ---
const WEAPON_PRICES := {&"bat": 100, &"yank": 150, &"shotgun": 200, &"boing": 250, &"katana": 250, &"disco": 300, &"axe": 300,
		&"assault_rifle": 400, &"sniper": 450, &"tesla": 500}
const ARMOR_BUY_COST := 300
const ADRENALINE_COST := 200
const SECOND_WIND_COST := 500
const UPGRADE_BASE := 300## weapon upgrader: base price, plus UPGRADE_STEP for every upgrade that weapon already has
const UPGRADE_STEP := 150
const GEAR_BASE := 250## armor upgrader
const GEAR_STEP := 125
const UPGRADE_HOLD := 0.6
const UPGRADE_TIME := 5.0 ## seconds a weapon or gear spends in an upgrader machine
