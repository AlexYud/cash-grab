extends BotScenario
## M3b client side: does the shoving and shooting, and checks what observers see.


func _valid_ragdolls() -> int:
	var n := 0
	for r in Fx._ragdolls:
		if is_instance_valid(r):
			n += 1
	return n


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return
	var host := other_player()
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel

	# --- P ---
	if not await wait_signal("P_start", 30.0):
		report("client: P_start barrier", false)
		finish()
		return
	await walk_to(host.global_position + Vector3(0, 0, 1.6), 0.3, 8.0)
	face_point(host.global_position)
	await wait(0.5)
	await shove()
	var rag := await wait_until(func() -> bool: return host.puppet.is_ragdolling(), 2.0)
	report("P: observers see the shoved player ragdoll", rag)
	report("P: the live body is hidden while the ragdoll plays", rag and not host.puppet.body.visible)
	var recovered := await wait_until(func() -> bool: return not host.puppet.is_ragdolling() and host.puppet.body.visible, 4.0)
	report("P: the player returns to a controlled body afterwards", recovered)
	signal_peers("P_done")

	# --- R ---
	await wait_signal("R_done", 30.0)
	var n := _valid_ragdolls()
	report("R: ragdoll count is capped on the client too", n > 0 and n <= GameConfig.MAX_RAGDOLLS, "n=%d" % n)

	# --- X ---
	if not await wait_signal("X_start", 30.0):
		report("client: X_start barrier", false)
		finish()
		return
	var barrel := level.barrels[0]
	await walk_to(Vector3(-8.0, 0, 6.0), 0.4, 12.0) # clear line of sight: Table1 blocks the east side
	await wait(0.3)
	var max_speed := 0.0
	var tick := 0
	var t := 0.0
	while barrel.alive and t < 12.0:
		aim_at(barrel.global_position + Vector3(0, 0.5, 0))
		if tick % 8 == 0:
			player.input.fire_pressed = true
		max_speed = maxf(max_speed, Vector2(player.velocity.x, player.velocity.z).length())
		tick += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for i in 40:
		max_speed = maxf(max_speed, Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
	report("X: barrel is gone for the client too (replicated)", not barrel.alive)
	report("X: explosion launched the shooter", max_speed > 8.0, "max_speed=%.1f" % max_speed)
	await wait_signal("X_done", 15.0)

	# --- O ---
	var over := await wait_until(func() -> bool: return wm.state == WaveManager.State.GAME_OVER, 15.0)
	report("O: client sees the game-over state", over)
	await wait_signal("O_done", 20.0)
	await wait(0.6)
	report("O: client sees the restarted run", wm.state == WaveManager.State.BREAK and player.status == Player.Status.ALIVE and player.hp == GameConfig.PLAYER_MAX_HP, "state=%d status=%d" % [wm.state, player.status])
	signal_peers("M3B_done")
	finish()
