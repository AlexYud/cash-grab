extends BotScenario
## M10 host: the new weapons (assault rifle, sniper, bat, katana, axe) and the ceiling crawler.


func _equip(idx: int) -> void:
	player.weapons.give_weapon.rpc(idx)
	await wait(0.3)
	player.input.weapon_slot = idx
	await wait(0.9)


func _dummy(pos: Vector3, hp: int = 3000) -> Zombie:
	return wave_manager().spawn_at(pos, 0, hp, 0.0)


func _ring(n: int, dist: float) -> Array:
	var out: Array = []
	for i in n: # a fan in front of the player (who looks towards -Z)
		var a := deg_to_rad(-40.0 + 80.0 * float(i) / maxf(n - 1.0, 1.0))
		out.append(_dummy(player.global_position + Vector3(sin(a) * dist, 0.0, -cos(a) * dist)))
	return out


func run() -> void:
	var wm := wave_manager()
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	Net.debug_god = true # the dummies bite
	await wait(1.5)
	player._apply_teleport(Vector3(0.5, 0.1, 0.5))
	player.input.aim_yaw = 0.0
	player.input.aim_pitch = 0.0
	await wait(0.6)

	# --- W: assault rifle: hold the trigger ---
	await _equip(6)
	var a := _dummy(Vector3(0.5, 0, -6.0))
	await wait(0.5)
	var ammo0 := player.weapons.ammo[6]
	var hp0 := a.hp
	player.input.fire_held = true
	var t := 0.0
	while t < 1.2:
		aim_at(a.global_position + Vector3(0, 1.1, 0))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	player.input.fire_held = false
	var shots := ammo0 - player.weapons.ammo[6]
	report("W: holding fire keeps shooting the assault rifle", shots >= 8, "shots=%d in 1.2 s" % shots)
	report("W: ...and the rounds land", hp0 - a.hp >= 8 * 12, "damage=%d" % (hp0 - a.hp))
	a.free()

	# --- S: sniper: zoom and one shot ---
	player._apply_teleport(Vector3(0.5, 0.1, 6.0))
	player.input.aim_yaw = 0.0
	await _equip(7)
	var b := _dummy(Vector3(0.5, 0, -6.0), 120)
	await wait(0.5)
	player.input.ads = true
	await wait(0.9)
	report("S: the sniper zooms in much further than the other guns", player.camera.fov < 30.0, "fov=%.0f" % player.camera.fov)
	for i in 8:
		aim_at(b.global_position + Vector3(0, 1.3, 0))
		await get_tree().physics_frame
	player.input.fire_pressed = true
	await wait(0.6)
	report("S: one sniper shot kills a zombie", not is_instance_valid(b) or b.is_dead())
	player.input.ads = false
	await wait(0.6)

	# --- B / K / X: the melee weapons ---
	player.input.aim_pitch = 0.0
	await _equip(8)
	var c := _dummy(player.global_position + Vector3(0, 0, -1.7))
	await wait(0.4)
	var hpc := c.hp
	var ammo_bat := player.weapons.ammo[8]
	aim_at(c.global_position + Vector3(0, 1.0, 0))
	await wait(0.2)
	player.input.fire_pressed = true
	await wait(0.4)
	report("B: the bat hits the zombie in front of you", hpc - c.hp >= 40, "damage=%d" % (hpc - c.hp))
	report("B: ...and swinging uses no ammo", player.weapons.ammo[8] == ammo_bat)
	report("B: ...and the swing leaves the zombie reeling", c.state == Zombie.State.STAGGER or c.is_fallen() or c._knock.length() > 0.5 or c.global_position.z < -2.0)
	c.free()
	await wait(0.3)

	await _equip(9)
	var kat := _ring(5, 1.9)
	await wait(0.5)
	for z in kat:
		z.set_physics_process(false)
	aim_at(player.global_position + Vector3(0, 1.0, -1.9))
	player.input.aim_yaw = 0.0
	await wait(0.3)
	player.input.fire_pressed = true
	await wait(0.4)
	var hit_k := 0
	for z in kat:
		if z.hp < 3000:
			hit_k += 1
	report("K: the katana cuts up to three zombies in one swing", hit_k == 3, "hit=%d of 5" % hit_k)
	for z in kat:
		z.free()
	await wait(0.3)

	await _equip(10)
	var axe := _ring(7, 1.9)
	await wait(0.5)
	for z in axe:
		z.set_physics_process(false)
	player.input.aim_yaw = 0.0
	await wait(0.3)
	player.input.fire_pressed = true
	await wait(0.4)
	var hit_x := 0
	for z in axe:
		if z.hp < 3000:
			hit_x += 1
	report("X: the axe cleaves up to five zombies in one swing", hit_x == 5, "hit=%d of 7" % hit_x)
	for z in axe:
		z.free()
	player.input.weapon_slot = 0
	await wait(0.5)

	# --- C: the crawler ---
	player._apply_teleport(Vector3(4.0, 0.1, 5.5))
	await wait(0.6)
	var cr := wm.spawn_at(Vector3(-10.8, 1.2, 3.0), -1, 400, GameConfig.CRAWLER_SPEED, Zombie.Kind.CRAWLER, PI / 2.0)
	await wait(0.4)
	report("C: a crawler starts out climbing the wall", cr.state == Zombie.State.CLIMB and cr.kind == Zombie.Kind.CRAWLER)
	signal_peers("C_start")
	var up := await wait_until(func() -> bool: return cr.state == Zombie.State.CEILING, 5.0)
	report("C: ...up to the ceiling", up and absf(cr.global_position.y - GameConfig.CEILING_Y) < 0.2, "y=%.2f" % cr.global_position.y)
	await wait(1.2)
	report("C: it walks upside down", absf(absf(cr.puppet.rotation.z) - PI) < 0.4, "roll=%.2f" % cr.puppet.rotation.z)
	report("C: its hit shape hangs below the ceiling", cr.body_shape.position.y < -0.4, "shape_y=%.2f" % cr.body_shape.position.y)
	signal_peers("C_ceiling")
	# shoot it where it really is: the pistol hits the upside-down body
	var hp_cr := cr.hp
	var t2 := 0.0
	while t2 < 2.0 and is_instance_valid(cr) and cr.state == Zombie.State.CEILING:
		aim_at(cr.global_position + Vector3(0, -0.8, 0))
		player.input.fire_pressed = t2 > 0.2 and int(t2 * 10.0) % 3 == 0
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
	report("C: a ceiling crawler can be shot", cr.hp < hp_cr, "hp %d -> %d" % [hp_cr, cr.hp])
	var dropped := await wait_until(func() -> bool: return cr.state == Zombie.State.DROP or cr._crawl_phase >= 2, 12.0)
	report("C: it drops on the player when it is above them", dropped)
	var landed := await wait_until(func() -> bool: return cr._crawl_phase == 3, 4.0)
	report("C: ...lands and fights on the ground like a normal zombie", landed and cr.global_position.y < 0.6, "y=%.2f" % cr.global_position.y)
	await wait(1.0)
	report("C: ...right way up again", absf(cr.puppet.rotation.z) < 0.5 and cr.puppet.rotation.x < 0.5, "roll=%.2f" % cr.puppet.rotation.z)
	# the spawner picks vents from rooms that are open
	Net.debug_god = false
	var n_before := enemies().size()
	var spawned := wm._spawn_crawler()
	await wait(0.4)
	report("C: the wave manager can place a crawler at an open vent", spawned and enemies().size() == n_before + 1)
	var kinds := {}
	for v in wave_manager().level.vents:
		kinds[int(v.get_meta("stage", 0))] = true
	report("C: there are vents in all three rooms", kinds.has(0) and kinds.has(1) and kinds.has(2), str(kinds.keys()))
	signal_peers("M10_done")
	await wait(0.6)
	finish()
