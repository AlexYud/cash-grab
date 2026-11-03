extends BotScenario
## M4d client: follows the host out to the lobby and back into a second run.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not await wait_signal("C_start", 40.0):
		report("client: C_start barrier", false)
		finish()
		return
	var lobby := await wait_until(func() -> bool: return Net.phase == Net.Phase.LOBBY, 6.0)
	report("client: dropped back to the lobby with the host", lobby)
	await wait(0.8)
	report("client: its copies of players and zombies were despawned", Net.all_players().is_empty() and enemies().is_empty() and Net.local_player == null, "players=%d enemies=%d" % [Net.all_players().size(), enemies().size()])
	signal_peers("C_lobby_ok")
	var back := await wait_until(func() -> bool: return Net.phase == Net.Phase.PLAYING and Net.all_players().size() == 2 and Net.local_player != null, 12.0)
	report("client: second run starts and the player spawns again", back)
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	# the host's reset reaches this peer through the synchronizers, which tick every 0.1-0.2 s: poll instead of guessing a delay
	var t0 := Time.get_ticks_msec()
	var fresh := await wait_until(func() -> bool: return level.barricades[1].boards == Barricade.MAX_BOARDS and level.barrels[0].alive and wm.state == WaveManager.State.BREAK, 6.0)
	report("client: world state is fresh (boards, barrel, wave)", fresh, "boards=%d barrel=%s state=%d after=%.1fs" % [level.barricades[1].boards, level.barrels[0].alive, wm.state, (Time.get_ticks_msec() - t0) / 1000.0])
	var lp := Net.local_player
	var start := lp.global_position
	lp.input.move = Vector2(0, -1)
	lp.bot_controlled = true
	await wait(0.8)
	lp.input.move = Vector2.ZERO
	report("client: the respawned player is controllable", lp.global_position.distance_to(start) > 1.0)
	await wait_signal("C_start2", 20.0)
	signal_peers("M4D_done")
	await wait(0.5)
	finish()
