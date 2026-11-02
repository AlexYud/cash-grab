extends BotScenario
## M1 client side. Everything it asserts comes from its own replicated view of the world.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return
	var host := other_player()

	# --- A: aimbot kills the zombie ---
	if not await wait_signal("A_start", 30.0):
		report("client: A_start barrier", false)
		finish()
		return
	await wait_until(func() -> bool: return not enemies().is_empty(), 5.0)
	var min_hp := 9999
	var max_kill_marker := 0.0
	var max_hit_marker := 0.0
	var tick := 0
	var t := 0.0
	while t < 20.0 and (not enemies().is_empty()):
		var z := nearest_enemy()
		if z != null:
			min_hp = mini(min_hp, z.hp)
		shoot_nearest(tick, 4)
		max_kill_marker = maxf(max_kill_marker, player.weapons.kill_marker)
		max_hit_marker = maxf(max_hit_marker, player.weapons.hit_marker)
		tick += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await wait(0.3)
	max_kill_marker = maxf(max_kill_marker, player.weapons.kill_marker)
	report("A: zombie hp drop replicated to the shooter", min_hp < 100, "min_hp=%d" % min_hp)
	report("A: zombie despawned on the client after dying", enemies().is_empty())
	report("A: hit marker shown", max_hit_marker > 0.0)
	report("A: kill confirm reached the shooter", max_kill_marker > 0.0)
	report("A: ammo was consumed", player.weapons.ammo[0] < 12, "ammo=%d" % player.weapons.ammo[0])
	await wait_signal("A_done", 10.0)

	# --- B: shotgun the host ---
	if not await wait_signal("B_start", 15.0):
		report("client: B_start barrier", false)
		finish()
		return
	await walk_to(host.global_position + Vector3(0, 0, 3.0), 0.4, 8.0)
	face_point(host.global_position)
	player.input.weapon_slot = 1
	await wait(0.8)
	aim_at(host.global_position + Vector3(0, 1.0, 0))
	await wait(0.2)
	await fire()
	await wait(0.5)
	report("B: shotgun fired", player.weapons.ammo[1] == 5, "ammo=%d" % player.weapons.ammo[1])
	player.input.reload = true
	await wait(0.1)
	report("B: reload started", player.weapons.is_reloading())
	await wait(2.6)
	report("B: reload finished", player.weapons.ammo[1] == 6 and not player.weapons.is_reloading(), "ammo=%d" % player.weapons.ammo[1])
	player.input.weapon_slot = 0
	signal_peers("B_done")

	# --- C: watch the host get bitten and recover ---
	if not await wait_signal("C_start", 20.0):
		report("client: C_start barrier", false)
		finish()
		return
	var saw_damage := await wait_until(func() -> bool: return host.hp < GameConfig.PLAYER_MAX_HP, 12.0)
	report("C: host's damage replicated to the client", saw_damage, "hp=%d" % host.hp)
	await wait_signal("C_done", 30.0)
	report("C: host's health regeneration replicated", host.hp == GameConfig.PLAYER_MAX_HP, "hp=%d" % host.hp)
	signal_peers("M1_done")
	await wait(0.5)
	finish()
