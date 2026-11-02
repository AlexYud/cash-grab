extends BotScenario
## M0 host side. Walks north, then stands still and records what the client does to it:
## movement replicated to the host, launched by a shove, pulled by a grab, released.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists on host", ok)
	if not ok:
		finish()
		return
	var other := other_player()
	var other_start := other.global_position
	await wait(1.0)

	var start := player.global_position
	await walk_to(start + Vector3(0, 0, -4.0), 0.4, 6.0)
	report("host: own movement works", player.global_position.distance_to(start) > 3.0)

	var max_speed := 0.0
	var launched := false
	var grabbed_by_client := false
	var released := false
	var closest := 99.0
	var client_moved := false
	var t := 0.0
	while t < 45.0 and other_player() != null:
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		max_speed = maxf(max_speed, spd)
		if spd > 5.0 and player.stagger_time > 0.0:
			launched = true
		if other.global_position.distance_to(other_start) > 2.0:
			client_moved = true
		if player.grabbed_by == other.peer_id:
			grabbed_by_client = true
			var flat := other.global_position - player.global_position
			flat.y = 0.0
			closest = minf(closest, flat.length())
		elif grabbed_by_client and player.grabbed_by == 0:
			released = true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	report("host: client movement replicated to host", client_moved)
	report("host: launched by the client's shove", launched, "max_speed=%.1f" % max_speed)
	report("host: grab state reached the host player", grabbed_by_client)
	report("host: pulled toward the grabber", closest < 1.9, "closest=%.2f" % closest)
	report("host: released after the grab", released)
	finish()
