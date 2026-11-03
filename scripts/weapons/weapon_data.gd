class_name WeaponData
extends Resource
## Data-only description of a gun. Edit the .tres files in resources/weapons/ to balance.

@export var id: StringName = &"pistol"
@export var display_name := "Pistol"
@export var damage := 25.0 ## per pellet, before distance falloff
@export var pellets := 1
@export var spread_deg := 0.4
@export var fire_interval := 0.22
@export var mag_size := 12
@export var reload_time := 1.2
@export var max_range := 70.0
@export var falloff_start := 15.0
@export var falloff_end := 45.0
@export var min_damage_frac := 0.4
@export var enemy_knockback := 1.2 ## horizontal m/s given to a zombie per pellet that hits
@export var enemy_stagger := 0.0 ## seconds of flinch per hit
@export var player_knockback := 1.8 ## launch m/s given to a teammate per pellet that hits
@export var player_stagger := 0.0
@export var recoil_deg := 1.4 ## camera kick per shot
@export var switch_time := 0.35
@export var special: StringName = &"" ## "yank" pulls what it hits toward the shooter; "disco" makes zombies dance; "bonk" (bat) sometimes knocks them over
@export var auto := false ## holding fire keeps shooting
@export var ads_fov := 0.0 ## field of view while aiming down sights (0 = the default)
@export var melee := false ## swings instead of shooting: hits every zombie in a cone in front, no ammo
@export var melee_range := 2.6
@export var melee_half_arc_deg := 55.0
@export var melee_targets := 2 ## how many zombies one swing can hit


func damage_at(distance: float) -> float:
	var t := clampf((distance - falloff_start) / maxf(falloff_end - falloff_start, 0.01), 0.0, 1.0)
	return damage * lerpf(1.0, min_damage_frac, t)
