class_name BotScenario
extends Node
## Base class for scripted test players. A bot writes into player.input exactly like the keyboard would;
## subclasses override run() and use the awaitable helpers below. See tests/bots/*.gd.

var h: DevHarness
var player: Player


func attach(harness: DevHarness, p: Player) -> void:
	h = harness
	player = p


func run() -> void:
	pass


# --- timing --------------------------------------------------------------------------------------------------

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## Polls `cond` every physics frame. Returns true if it became true before `timeout` seconds.
func wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


# --- world queries ---------------------------------------------------------------------------------------------

func other_player() -> Player:
	for p in Net.all_players():
		if p != player:
			return p
	return null


func yaw_for(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func face_point(point: Vector3) -> void:
	var to := point - player.global_position
	to.y = 0.0
	if to.length() > 0.01:
		player.input.aim_yaw = yaw_for(to)


## Points the camera at a world position (yaw and pitch), like moving the mouse.
func aim_at(point: Vector3) -> void:
	var d := point - (player.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0))
	player.input.aim_yaw = atan2(-d.x, -d.z)
	player.input.aim_pitch = atan2(d.y, Vector2(d.x, d.z).length())


func wave_manager() -> WaveManager:
	return get_tree().root.get_node("Main/World/WaveManager") as WaveManager


func enemies() -> Array[Zombie]:
	var out: Array[Zombie] = []
	for n in get_tree().get_nodes_in_group("enemies"):
		var z := n as Zombie
		if z != null and not z.is_dead() and not z.is_queued_for_deletion():
			out.append(z)
	return out


func nearest_enemy() -> Zombie:
	var best: Zombie = null
	var best_d := INF
	for z in enemies():
		var d := z.global_position.distance_squared_to(player.global_position)
		if d < best_d:
			best_d = d
			best = z
	return best


## Cross-process barriers (see DevHarness.send_signal).
func signal_peers(tag: String) -> void:
	h.send_signal(tag)


func wait_signal(tag: String, timeout: float) -> bool:
	return await wait_until(func() -> bool: return h.signals_seen.has(tag), timeout)


## Aimbot step: aim at the nearest zombie's chest and tap fire. Returns true if there was a target.
func shoot_nearest(tick: int, every: int = 4) -> bool:
	var z := nearest_enemy()
	if z == null:
		player.input.fire_held = false
		return false
	aim_at(z.global_position + Vector3(0, 1.1, 0))
	if tick % every == 0:
		player.input.fire_pressed = true
	return true


# --- actions -------------------------------------------------------------------------------------------------------

## Walks toward `point` (flat). Returns true when within `tolerance`.
func walk_to(point: Vector3, tolerance: float = 0.6, timeout: float = 8.0) -> bool:
	var t := 0.0
	while t < timeout:
		var to := point - player.global_position
		to.y = 0.0
		if to.length() <= tolerance:
			player.input.move = Vector2.ZERO
			return true
		player.input.aim_yaw = yaw_for(to)
		player.input.move = Vector2(0, -1)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	player.input.move = Vector2.ZERO
	return false


## Per-tick steering for bots that also aim/shoot: moves toward `point` without touching the aim.
## Returns true once within `tol`.
func steer_to(point: Vector3, tol: float = 0.5) -> bool:
	var to := point - player.global_position
	to.y = 0.0
	if to.length() <= tol:
		player.input.move = Vector2.ZERO
		return true
	var local := Basis(Vector3.UP, player.yaw).inverse() * to.normalized()
	player.input.move = Vector2(local.x, local.z).limit_length(1.0)
	return false


func stop() -> void:
	player.input.move = Vector2.ZERO
	player.input.fire_held = false
	player.input.grab_held = false
	player.input.interact_held = false
	player.input.sprint = false


func shove() -> void:
	player.input.shove = true
	await get_tree().physics_frame


func fire() -> void:
	player.input.fire_pressed = true
	await get_tree().physics_frame


func report(test: String, ok: bool, detail: String = "") -> void:
	h.report(test, ok, detail)


func finish() -> void:
	h.finish()
