extends BotScenario
## M3a host side: down the client, revive it, drag it, let it bleed out, restore it at wave clear.


func _flat_dist(a: Player, b: Player) -> float:
	var d := a.global_position - b.global_position
	d.y = 0.0
	return d.length()


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	var wm := wave_manager()
	await wait(2.0)

	# --- D: downed + revive ---
	client.srv_take_damage(999)
	await wait(0.5)
	report("D: client is downed (host state)", client.status == Player.Status.DOWNED and client.hp == 0 and client.bleed_left > 0.0, "status=%d bleed=%.1f" % [client.status, client.bleed_left])
	signal_peers("D_start")
	await wait(3.0) # the client crawls and fires for a moment
	await walk_to(client.global_position + Vector3(0, 0, 0.9), 0.5, 8.0)
	face_point(client.global_position)
	await wait(0.4)
	player.input.interact_held = true
	var revived := await wait_until(func() -> bool: return client.status == Player.Status.ALIVE, 8.0)
	player.input.interact_held = false
	report("D: holding E revived the downed player", revived, "status=%d progress=%.2f" % [client.status, client.revive_progress])
	report("D: revived with half health", client.hp == GameConfig.REVIVE_HP, "hp=%d" % client.hp)
	signal_peers("D_done")
	await wait(2.6) # revive invulnerability ends

	# --- G: drag a downed player ---
	client.srv_take_damage(999)
	await wait(0.6)
	signal_peers("G_start")
	var start := client.global_position
	await walk_to(client.global_position + Vector3(0, 0, -1.1), 0.4, 6.0)
	face_point(client.global_position)
	await wait(0.4)
	player.input.grab_held = true
	var grabbed := await wait_until(func() -> bool: return player.grabbing == client.peer_id, 3.0)
	report("G: grab on a downed player accepted", grabbed)
	player.input.aim_yaw = 0.0 # face north; the downed player trails behind us
	await wait(0.4)
	await walk_to(player.global_position + Vector3(0, 0, -6.0), 0.5, 10.0)
	await wait(1.2)
	report("G: downed player was dragged along", client.global_position.distance_to(start) > 4.0 and _flat_dist(player, client) < 2.8, "moved=%.1f gap=%.1f" % [client.global_position.distance_to(start), _flat_dist(player, client)])
	player.input.grab_held = false
	await wait(0.6)
	report("G: drag released", client.grabbed_by == 0 and player.grabbing == 0)

	# --- B: nobody comes: the client bleeds out, then the wave ends and everyone is back ---
	signal_peers("B_start")
	var elim := await wait_until(func() -> bool: return client.status == Player.Status.ELIMINATED, 20.0)
	report("B: an unattended downed player bleeds out", elim)
	wm.hold = false
	wm.wave = 1
	wm.to_spawn = 0
	wm.state = WaveManager.State.ACTIVE
	var back := await wait_until(func() -> bool: return client.status == Player.Status.ALIVE, 6.0)
	report("B: clearing the wave brings them back at full health", back and client.hp == GameConfig.PLAYER_MAX_HP, "status=%d hp=%d" % [client.status, client.hp])
	signal_peers("M3A_done")
	await wait(0.5)
	finish()
