extends BotScenario
## M8 client side: every peer runs its own ragdolls, driven by the replicated state. Checks that what the host
## makes limp is limp here too, that it gets up, that a blast flings it, and that corpses appear.


func _hips_y(z: Zombie) -> float:
	return z.puppet.hips_position().y


func _any_limp() -> Zombie:
	for z in enemies():
		if z.puppet.is_ragdolling():
			return z
	return null


func run() -> void:
	if not await wait_signal("hello", 30.0):
		report("client: hello barrier", false)
		finish()
		return
	player.global_position = player.global_position # stay put

	# --- C ---
	await wait_signal("C_start", 30.0)
	var got := await wait_until(func() -> bool: return _any_limp() != null, 4.0)
	report("C: the client's copy of a tripped zombie goes limp", got)
	var z := _any_limp()
	if z != null:
		await wait(1.2)
		report("C: ...and lies on the floor here too", z.puppet.is_ragdolling() and _hips_y(z) < 0.5,"hips_y=%.2f" % _hips_y(z))
	await wait_signal("C_done", 15.0)
	var upright := await wait_until(func() -> bool: return _any_limp() == null, 2.0)
	report("C: no zombie is left limp after it got up", upright)

	# --- D ---
	await wait_signal("D_start", 30.0)
	var peak := 0.0
	for i in 70:
		for e in enemies():
			if e.puppet.is_ragdolling():
				peak = maxf(peak, _hips_y(e))
		await get_tree().physics_frame
	report("D: the blast throws the client's ragdoll into the air too", peak > 0.7, "peak=%.2f" % peak)
	await wait_signal("D_done", 15.0)

	# --- F ---
	await wait_signal("F_done", 30.0)
	var corpses := 0
	var limp := true
	for r in Fx._ragdolls:
		if is_instance_valid(r) and r is ZombieRig:
			corpses += 1
			limp = limp and r.is_ragdolling()
	report("F: a corpse ragdoll shows up on the client", corpses > 0 and limp, "corpses=%d" % corpses)
	await wait(3.0)
	finish()
