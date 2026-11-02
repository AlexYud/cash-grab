extends BotScenario
## M5 client: watches the clumsy zombies, takes a brute charge, eats a snack, gets hugged and shoves it off.


func _fallen() -> Array:
	var out: Array = []
	for z in enemies():
		if z.state == Zombie.State.FALLEN:
			out.append(z)
	return out


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return

	# --- T ---
	await wait_signal("T_start", 30.0)
	var fell := await wait_until(func() -> bool: return not _fallen().is_empty(), 10.0)
	report("T: the client sees zombies lying on the floor", fell)
	await wait(0.3)
	var lying := _fallen()
	var zid := 0
	if not lying.is_empty():
		var z: Zombie = lying[0]
		zid = z.net_id
		report("T: the lying zombie has the low hit shape on this peer too", not z.fallen_shape.disabled and z.body_shape.disabled)
	var up := await wait_until(func() -> bool:
		var q := Zombie.find_by_id(get_tree(), zid)
		return q != null and q.state != Zombie.State.FALLEN, 8.0)
	report("T: it gets back up (replicated)", up)

	# --- B ---
	await wait_signal("B_start", 40.0)
	await wait(0.2)
	var brute: Zombie = null
	for z in enemies():
		if z.kind == Zombie.Kind.BRUTE:
			brute = z
	report("B: the brute is bigger and a different kind on this peer", brute != null and brute.puppet.scale.x > 1.2)
	var max_speed := 0.0
	var t := 0.0
	var brute_id := brute.net_id if brute != null else -1
	while t < 14.0 and not h.signals_seen.has("B_done"):
		max_speed = maxf(max_speed, Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	report("B: the charge launched this player", max_speed > 8.0, "max_speed=%.1f" % max_speed)
	await wait(0.4)
	report("B: the snack is visible on this peer", Fx._snack_nodes.size() == 1, "snacks=%d" % Fx._snack_nodes.size())

	# --- S: walk onto the snack ---
	if not Fx._snack_nodes.is_empty():
		var sn: Node3D = Fx._snack_nodes.values()[0]
		await walk_to(sn.global_position, 0.5, 8.0)
	await wait(0.5)
	report("S: the snack disappeared after eating it", Fx._snack_nodes.is_empty())
	signal_peers("S_done")

	# --- H ---
	await wait_signal("H_start", 30.0)
	var hugged := await wait_until(func() -> bool: return player.hugged > 0, 8.0)
	report("H: this player sees it is being hugged", hugged)
	await wait(0.2) # let one physics tick refresh the prompt
	report("H: and gets a hint to shove it off", player.prompt_text.contains("Hugger"), "'%s'" % player.prompt_text)
	var start := player.global_position
	player.input.move = Vector2(0, -1)
	var top := 0.0
	for i in 60:
		top = maxf(top, Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
	player.input.move = Vector2.ZERO
	report("H: a hugged player is slowed down", top < GameConfig.WALK_SPEED * 0.6, "top=%.1f" % top)
	var hz: Zombie = null
	for z in enemies():
		if z.kind == Zombie.Kind.HUGGER:
			hz = z
	if hz != null:
		aim_at(hz.global_position + Vector3(0, 0.9, 0))
		await wait(0.3)
	await shove()
	var off := await wait_until(func() -> bool: return player.hugged == 0, 3.0)
	report("H: shoving gets the hugger off", off)
	signal_peers("H_shoved")

	await wait_signal("M5_done", 30.0)
	finish()
