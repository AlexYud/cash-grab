extends BotScenario
## M1 host side: stages the scenarios. A) the client kills a zombie with the pistol, B) the client
## shotguns the host (knockback, no damage), C) a zombie bites the host, who shoots back with the direct path.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	await wait(2.0)
	var wm := wave_manager()

	# --- A: pistol kill by the client ---
	var zid := wm.spawn_at(client.global_position + Vector3(0, 0, -9.0), 0, 100, 2.0).net_id
	signal_peers("A_start")
	# look the zombie up by id: a lambda must not capture the node itself, it is freed when it dies
	var killed := await wait_until(func() -> bool: return Zombie.find_by_id(get_tree(), zid) == null, 25.0)
	report("A: zombie killed by the client's pistol", killed)
	await wait(0.5)
	report("A: kill credited to the client on the host", client.kills == 1, "kills=%d" % client.kills)
	signal_peers("A_done")

	# --- B: friendly shotgun = launch, never damage ---
	signal_peers("B_start")
	var launched := false
	var max_speed := 0.0
	var t := 0.0
	while t < 14.0 and not h.signals_seen.has("B_done"):
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		max_speed = maxf(max_speed, spd)
		if spd > 4.0 and player.stagger_time > 0.0:
			launched = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	report("B: shotgun hit launched the teammate", launched, "max_speed=%.1f" % max_speed)
	report("B: friendly fire did no HP damage", player.hp == GameConfig.PLAYER_MAX_HP, "hp=%d" % player.hp)
	await wait(2.5)

	# --- C: zombie bites the host; host shoots it with the host-side direct path ---
	var kills_before := player.kills
	var z2 := wm.spawn_at(player.global_position + Vector3(0, 0, -3.5), 0, 100, 2.2)
	signal_peers("C_start")
	var bitten := await wait_until(func() -> bool: return player.hp < GameConfig.PLAYER_MAX_HP, 10.0)
	report("C: zombie damaged the host player", bitten, "hp=%d" % player.hp)
	var tick := 0
	t = 0.0
	while is_instance_valid(z2) and not z2.is_dead() and t < 15.0:
		shoot_nearest(tick, 5)
		tick += 1
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	player.input.fire_held = false
	report("C: host killed the zombie with its own gun", player.kills == kills_before + 1, "kills=%d" % player.kills)
	var regen := await wait_until(func() -> bool: return player.hp == GameConfig.PLAYER_MAX_HP, 12.0)
	report("C: health regenerates out of combat", regen, "hp=%d" % player.hp)
	signal_peers("C_done")
	await wait_signal("M1_done", 20.0)
	finish()
