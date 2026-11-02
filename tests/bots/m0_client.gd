extends BotScenario
## M0 client side. Observes the host walking, then walks up to it, shoves it, grabs it and lets go.
## Everything it asserts is read from its own replicated copy of the host, i.e. what a human client would see.


func _flat_dist(a: Player, b: Player) -> float:
	var d := a.global_position - b.global_position
	d.y = 0.0
	return d.length()


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists on client", ok)
	if not ok:
		finish()
		return
	var host := other_player()
	var host_start := host.global_position
	var moved := await wait_until(func() -> bool: return host.global_position.distance_to(host_start) > 2.5, 15.0)
	report("client: host movement replicated", moved, "d=%.1f" % host.global_position.distance_to(host_start))
	await wait(1.0)

	# --- shove ---
	await walk_to(host.global_position + Vector3(0, 0, 1.6), 0.3, 8.0)
	face_point(host.global_position)
	await wait(0.5)
	var before := host.global_position
	await shove()
	var shoved := await wait_until(func() -> bool: return host.global_position.distance_to(before) > 2.0, 3.0)
	report("client: shove visibly launched the host", shoved, "d=%.1f" % host.global_position.distance_to(before))
	await wait(2.5)

	# --- grab ---
	await walk_to(host.global_position + Vector3(0, 0, 2.3), 0.3, 6.0)
	face_point(host.global_position)
	await wait(0.4)
	var d0 := _flat_dist(player, host)
	player.input.grab_held = true
	var grabbed := await wait_until(func() -> bool: return player.grabbing == host.peer_id and host.grabbed_by == player.peer_id, 3.0)
	report("client: grab accepted by the host and replicated back", grabbed)
	await wait(1.6)
	var d1 := _flat_dist(player, host)
	report("client: grabbed host was pulled closer", d1 < d0 - 0.4, "d0=%.2f d1=%.2f" % [d0, d1])
	player.input.grab_held = false
	var released := await wait_until(func() -> bool: return player.grabbing == 0 and host.grabbed_by == 0, 3.0)
	report("client: grab released", released)
	await wait(1.0)
	finish()
