extends BotScenario
## M4a first client: waits for the late joiner, grabs the host, then drops off the network mid-grab.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("leaver: host's player exists", ok)
	if not ok:
		finish()
		return
	var host := other_player()
	if not await wait_signal("L_joined", 60.0):
		report("leaver: L_joined barrier", false)
		finish()
		return
	await walk_to(host.global_position + Vector3(0, 0, 2.0), 0.4, 8.0)
	face_point(host.global_position)
	await wait(0.4)
	player.input.grab_held = true
	var g := await wait_until(func() -> bool: return player.grabbing == host.peer_id, 3.0)
	report("leaver: holding the host", g)
	signal_peers("LEAVER_GRABBING")
	await wait(1.0)
	Net.leave("test: leaving while grabbing")
	report("leaver: back at the main menu after leaving", Net.phase == Net.Phase.MENU)
	finish()
