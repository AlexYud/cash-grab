extends BotScenario
## M6 host: carry + throw a downed teammate (human bowling), Yank Gun, Disco Blaster, Leaper, Bloater.


func _state_seen(zs: Array, st: int) -> bool:
	for z in zs:
		if is_instance_valid(z) and z.state == st:
			return true
	return false


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	var wm := wave_manager()
	Net.debug_snack_chance = 0.0
	await wait(2.0)

	# --- K: carry a downed teammate and throw them into a group of zombies ---
	client.srv_take_damage(999)
	await wait(0.6)
	signal_peers("K_start")
	await walk_to(client.global_position + Vector3(0, 0, -1.1), 0.4, 6.0)
	face_point(client.global_position)
	await wait(0.4)
	player.input.grab_held = true
	var carrying := await wait_until(func() -> bool: return player.is_carrying(), 3.0)
	report("K: grabbing a downed teammate picks them up", carrying)
	player.input.aim_yaw = 0.0
	await wait(0.6)
	await wait_until(func() -> bool: return client.global_position.y > 0.6, 3.0)
	var hands := client.global_position - player.global_position
	report("K: the carried player is held up in the carrier's arms", client.global_position.y > 0.6 and Vector2(hands.x, hands.z).length() < 1.4, "dy=%.1f d=%.1f" % [client.global_position.y, Vector2(hands.x, hands.z).length()])
	report("K: the carrier's weapons are locked", player.weapons.locked)
	var zs: Array = []
	for off in [Vector3(0, 0, -4.0), Vector3(0.5, 0, -5.4), Vector3(-0.5, 0, -6.6)]:
		zs.append(wm.spawn_at(player.global_position + off, 0, 100000, 0.0))
	await wait(0.5)
	var start := client.global_position
	player.input.fire_pressed = true # fire = throw while carrying
	var bowled := await wait_until(func() -> bool: return _state_seen(zs, Zombie.State.FALLEN), 3.0)
	report("K: the thrown player bowls zombies over", bowled)
	await wait(0.8)
	report("K: the carrier let go", player.grabbing == 0 and client.grabbed_by == 0)
	report("K: the thrown player flew a good distance", client.global_position.distance_to(start) > 3.0, "d=%.1f" % client.global_position.distance_to(start))
	player.input.grab_held = false
	for e in enemies():
		e.srv_hit(1000000, Vector3.ZERO, 0.0, null)
	await wait(0.8)
	client.srv_restore(client.global_position, false)
	await wait(2.7)

	# --- Y: Yank Gun reels a zombie in ---
	player._apply_teleport(Vector3(0, 0.1, 3))
	await wait(0.6)
	var yz := wm.spawn_at(Vector3(0, 0, -5), 0, 100000, 0.0)
	player.input.weapon_slot = 2
	await wait(0.9)
	aim_at(yz.global_position + Vector3(0, 1.0, 0))
	await wait(0.3)
	var d0 := yz.global_position.distance_to(player.global_position)
	await fire()
	var fell := await wait_until(func() -> bool: return yz.state == Zombie.State.FALLEN, 2.0)
	await wait(1.2)
	var d1 := yz.global_position.distance_to(player.global_position)
	report("Y: the Yank Gun reels a zombie toward the shooter", d1 < d0 - 3.0, "d %.1f -> %.1f" % [d0, d1])
	report("Y: ...and trips it", fell)
	yz.srv_hit(1000000, Vector3.ZERO, 0.0, null)
	await wait(0.6)

	# --- D: Disco Blaster makes a zombie dance ---
	var dz := wm.spawn_at(Vector3(0, 0, -2), 0, 100000, 2.0)
	player.input.weapon_slot = 3
	await wait(0.9)
	aim_at(dz.global_position + Vector3(0, 1.0, 0))
	await wait(0.2)
	await fire()
	var dancing := await wait_until(func() -> bool: return dz.state == Zombie.State.DANCE, 1.5)
	report("D: the Disco Blaster makes a zombie dance", dancing)
	var p0 := dz.global_position
	await wait(1.5)
	report("D: dancing zombies do not walk or attack", dz.global_position.distance_to(p0) < 0.8, "moved=%.1f" % dz.global_position.distance_to(p0))
	dz.srv_hit(1000000, Vector3.ZERO, 0.0, null)
	player.input.weapon_slot = 0
	await wait(0.8)

	# --- L: leaper pounces ---
	player._apply_teleport(Vector3(0, 0.1, 3))
	client.cl_teleport.rpc_id(client.peer_id, Vector3(3, 0.1, 3))
	await wait(1.0)
	var lz := wm.spawn_at(Vector3(0, 0, -4), 0, GameConfig.LEAPER_HP, GameConfig.LEAPER_SPEED, Zombie.Kind.LEAPER)
	lz._leap_cd = 0.0
	signal_peers("L_start")
	var leapt := await wait_until(func() -> bool: return lz.state == Zombie.State.LEAP, 8.0)
	report("L: the leaper jumps at a player", leapt)
	var landed := await wait_until(func() -> bool: return lz.state == Zombie.State.FALLEN, 4.0)
	report("L: and lands in a heap", landed)
	lz.srv_hit(1000000, Vector3.ZERO, 0.0, null)
	await wait(0.6)

	# --- B: bloater bursts and knocks its neighbours over ---
	var bz := wm.spawn_at(Vector3(0, 0, -3), 0, 100000, 0.0, Zombie.Kind.BLOATER)
	var n1 := wm.spawn_at(Vector3(1.4, 0, -3), 0, 100000, 0.0)
	var n2 := wm.spawn_at(Vector3(-1.4, 0, -3), 0, 100000, 0.0)
	await wait(0.5)
	signal_peers("B_start")
	await wait(1.2) # let the client look at it first
	bz.srv_hit(1000000, Vector3.ZERO, 0.0, player)
	var popped := await wait_until(func() -> bool: return _state_seen([n1, n2], Zombie.State.FALLEN), 1.5)
	report("B: a bursting bloater knocks the zombies around it over", popped)
	signal_peers("M6_done")
	await wait(0.6)
	finish()
