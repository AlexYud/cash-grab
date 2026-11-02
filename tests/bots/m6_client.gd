extends BotScenario
## M6 client: gets carried and thrown, then watches the Leaper and the Bloater.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return

	# --- K ---
	await wait_signal("K_start", 30.0)
	var down := await wait_until(func() -> bool: return player.status == Player.Status.DOWNED, 3.0)
	report("K: the client is downed", down)
	var held := await wait_until(func() -> bool: return player.grabbed_by != 0 and player.global_position.y > 0.6, 8.0)
	report("K: the client is lifted into the carrier's arms", held, "y=%.1f" % player.global_position.y)
	var top := 0.0
	var t := 0.0
	while t < 8.0 and (player.grabbed_by != 0 or t < 1.0):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for i in 40:
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
	report("K: and then thrown (the client flew at speed)", top > 8.0 or t < 8.0, "top=%.1f" % top)

	# --- L ---
	await wait_signal("L_start", 40.0)
	var saw_leap := await wait_until(func() -> bool:
		for z in enemies():
			if z.kind == Zombie.Kind.LEAPER and z.state == Zombie.State.LEAP:
				return true
		return false, 10.0)
	report("L: the client sees the leaper in mid-air", saw_leap)

	# --- B ---
	await wait_signal("B_start", 30.0)
	var bloat := false
	for z in enemies():
		if z.kind == Zombie.Kind.BLOATER and z.puppet.scale.x > 1.1:
			bloat = true
	report("B: the bloater is a big one on this peer", bloat)
	await wait_signal("M6_done", 30.0)
	finish()
