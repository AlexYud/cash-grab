extends BotScenario
## M4a late joiner: arrives after the run started and must see the world exactly as it is now.


func run() -> void:
	report("late: got its own player after joining mid-run", player != null and player.is_local())
	await wait(2.0)
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var wm := wave_manager()
	report("late: sees all three players", Net.all_players().size() == 3, "n=%d" % Net.all_players().size())
	report("late: zombies that were already in the arena are replicated to it", enemies().size() == 2, "n=%d" % enemies().size())
	var boards := await wait_until(func() -> bool: return level.barricades[2].boards == 3, 5.0)
	report("late: barricade damage from before it joined is visible", boards, "boards=%d" % level.barricades[2].boards)
	var wave_ok := await wait_until(func() -> bool: return wm.state == WaveManager.State.BREAK, 5.0)
	report("late: wave state matches the host's", wave_ok, "state=%d" % wm.state)
	var start := player.global_position
	await walk_to(start + Vector3(-4.0, 0, 0), 0.4, 6.0)
	report("late: the new player can move", player.global_position.distance_to(start) > 2.5)
	await wait_signal("M4A_done", 50.0)
	finish()
