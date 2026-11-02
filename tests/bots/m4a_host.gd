extends BotScenario
## M4a host: stages some world state, lets a third player join mid-run, then watches a player disconnect
## while holding on to the host.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: first client present", ok)
	if not ok:
		finish()
		return
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	await wait(1.0)

	# world state a late joiner has to inherit
	level.barricades[2].srv_damage(GameConfig.BOARD_HP * 2.0)
	wm.spawn_at(Vector3(0, 0, -5), 0, 100000, 0.0)
	wm.spawn_at(Vector3(3, 0, -5), 0, 100000, 0.0)
	report("host: staged damage and zombies", level.barricades[2].boards == 3 and enemies().size() == 2)

	var joined := await wait_until(func() -> bool: return Net.all_players().size() == 3 and Net.roster.size() == 3, 45.0)
	report("host: mid-run joiner has a roster entry and a player node", joined, "players=%d roster=%d" % [Net.all_players().size(), Net.roster.size()])
	var colors := {}
	for r in Net.roster.values():
		colors[r["color"]] = true
	report("host: every player got a distinct colour", colors.size() == Net.roster.size())
	signal_peers("L_joined")

	await wait_signal("LEAVER_GRABBING", 40.0)
	var grabbed := await wait_until(func() -> bool: return player.grabbed_by != 0, 4.0)
	report("host: is being held by the player who is about to leave", grabbed)
	var cleaned := await wait_until(func() -> bool: return Net.all_players().size() == 2 and player.grabbed_by == 0, 12.0)
	report("host: after the disconnect the player is gone and the grab is released", cleaned, "players=%d grabbed_by=%d" % [Net.all_players().size(), player.grabbed_by])
	report("host: roster shrank", Net.roster.size() == 2, "roster=%d" % Net.roster.size())
	await wait(1.5)
	report("host: run goes on with the remaining players", Net.phase == Net.Phase.PLAYING and Net.all_players().size() == 2)
	signal_peers("M4A_done")
	await wait(0.8)
	finish()
