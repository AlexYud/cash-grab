extends BotScenario
## M5 host: clumsy zombies, brute, snacks, hugger, and friendly gunfire without the death ragdoll.


func _fallen_ids(zs: Array) -> Array:
	var out: Array = []
	for z in zs:
		if is_instance_valid(z) and z.state == Zombie.State.FALLEN:
			out.append(z.net_id)
	return out


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	Net.debug_snack_chance = 0.0
	await wait(2.0)

	# --- T: clumsy zombies trip over junk, lie down with a low hit shape, and get back up ---
	var spot := level.get_node("TripSpots/T0") as Node3D
	var zs: Array = []
	for i in 6:
		var z := wm.spawn_at(spot.global_position + Vector3(0.4 + i * 0.05, 0, 0.2), 0, 100000, 2.0)
		z._trip_cd = 0.0
		zs.append(z)
	signal_peers("T_start")
	var fell := await wait_until(func() -> bool: return not _fallen_ids(zs).is_empty(), 8.0)
	report("T: zombies trip over junk on the ground", fell)
	var first: int = _fallen_ids(zs)[0] if fell else 0
	await wait(0.3)
	var zf := Zombie.find_by_id(get_tree(), first)
	report("T: a fallen zombie swaps to the low hit shape", zf != null and not zf.fallen_shape.disabled and zf.body_shape.disabled)
	var up := await wait_until(func() -> bool:
		var q := Zombie.find_by_id(get_tree(), first)
		return q != null and q.state != Zombie.State.FALLEN, 8.0)
	report("T: and gets back up again", up)
	await wait(2.0)
	for e in enemies():
		e.srv_hit(1000000, Vector3.ZERO, 0.0, null)
	await wait(1.0)
	player.srv_restore(player.global_position, false)
	client.srv_restore(client.global_position, false)
	await wait(2.6) # revive invulnerability would swallow the brute's damage

	# --- B: brute charge, then a snack drops ---
	var bz := wm.spawn_at(client.global_position + Vector3(0, 0, -9.0), 0, 100000, 1.9, Zombie.Kind.BRUTE)
	bz._charge_cd = 0.0
	signal_peers("B_start")
	var charged := await wait_until(func() -> bool: return bz.state == Zombie.State.CHARGE, 12.0)
	report("B: the brute winds up and charges", charged)
	var hurt := await wait_until(func() -> bool: return client.hp < GameConfig.PLAYER_MAX_HP, 6.0)
	report("B: the charge hurts the target", hurt, "hp=%d" % client.hp)
	Net.debug_snack_chance = 1.0
	bz.srv_hit(1000000, Vector3.ZERO, 0.0, player)
	await wait(0.6)
	report("B: killing it drops a snack", Fx._snack_info.size() == 1, "snacks=%d" % Fx._snack_info.size())
	signal_peers("B_done")
	Net.debug_snack_chance = 0.0

	# --- S: the client walks over the snack and heals ---
	var hp_before := client.hp
	await wait_signal("S_done", 30.0)
	await wait(0.4)
	report("S: eating the snack heals the player", client.hp >= mini(hp_before + GameConfig.SNACK_HEAL, GameConfig.PLAYER_MAX_HP) - 1, "hp %d -> %d" % [hp_before, client.hp])
	report("S: the snack is gone", Fx._snack_info.is_empty())

	# --- H: hugger ---
	client.srv_restore(client.global_position, false)
	await wait(2.6)
	var hz := wm.spawn_at(client.global_position + Vector3(0, 0, -3.5), 0, GameConfig.HUGGER_HP, GameConfig.HUGGER_SPEED, Zombie.Kind.HUGGER)
	signal_peers("H_start")
	var latched := await wait_until(func() -> bool: return client.hugged == 1, 8.0)
	report("H: the hugger latches onto a player", latched)
	var hp0 := client.hp
	await wait(2.0)
	report("H: hugging drains a little health", client.hp < hp0, "hp %d -> %d" % [hp0, client.hp])
	await wait_signal("H_shoved", 20.0)
	await wait(0.4)
	report("H: a shove knocks the hugger off", client.hugged == 0 and hz.state != Zombie.State.LATCHED, "hugged=%d" % client.hugged)
	hz.srv_hit(1000000, Vector3.ZERO, 0.0, player)
	await wait(0.6)

	# --- F: friendly shotgun = knockback, never the death ragdoll ---
	client.cl_teleport.rpc_id(client.peer_id, Vector3(0, 0.1, 2))
	player._apply_teleport(Vector3(3, 0.1, 2))
	await wait(1.0)
	player.input.weapon_slot = 1
	await wait(0.9)
	aim_at(client.global_position + Vector3(0, 1.0, 0))
	await wait(0.3)
	var start := client.global_position
	await fire()
	var ragdolled := false
	var moved := 0.0
	for i in 90:
		if client.puppet.is_ragdolling():
			ragdolled = true
		moved = maxf(moved, client.global_position.distance_to(start))
		await get_tree().physics_frame
	report("F: shotgun friendly fire knocks the teammate back", moved > 1.0, "moved=%.1f" % moved)
	report("F: ...without the death ragdoll", not ragdolled)
	signal_peers("M5_done")
	await wait(0.6)
	finish()
