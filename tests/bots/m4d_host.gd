extends BotScenario
## M4d host: lobby cycle. Dirty the world, send everybody back to the lobby, start a second run, and make
## sure nothing from the first run leaks into it.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	await wait(1.5)
	level.barricades[1].srv_damage(GameConfig.BOARD_HP * 3.0)
	wm.spawn_at(Vector3(0, 0, -5), 0, 100000, 0.0)
	level.barrels[0].srv_damage(999, player)
	await wait(0.8)
	signal_peers("C_start")
	Net.return_to_lobby()
	await wait(1.2)
	report("host: back in the lobby with no players or enemies left", Net.phase == Net.Phase.LOBBY and Net.all_players().is_empty() and enemies().is_empty(), "players=%d enemies=%d" % [Net.all_players().size(), enemies().size()])
	await wait_signal("C_lobby_ok", 15.0)
	Net.start_game()
	var again := await wait_until(func() -> bool: return Net.all_players().size() == 2 and Net.local_player != null, 8.0)
	report("host: the second run spawns both players again", again)
	await wait(0.8)
	var fresh := level.barricades[1].boards == Barricade.MAX_BOARDS and level.barrels[0].alive and enemies().is_empty() and wm.state == WaveManager.State.BREAK and wm.wave == 0
	report("host: the second run starts from a clean world", fresh, "boards=%d barrel=%s enemies=%d state=%d" % [level.barricades[1].boards, level.barrels[0].alive, enemies().size(), wm.state])
	signal_peers("C_start2")
	await wait_signal("M4D_done", 20.0)
	finish()
