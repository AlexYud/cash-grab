extends BotScenario
## M2 client side: watches the boards disappear (replicated), then holds E to rebuild them.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return
	if not await wait_signal("S1_start", 30.0):
		report("client: S1_start barrier", false)
		finish()
		return
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var bar := level.barricades[0]
	var saw_break := await wait_until(func() -> bool: return bar.boards == 0, 60.0)
	report("client sees the boards disappear (replicated)", saw_break, "boards=%d" % bar.boards)
	await wait_signal("S1_done", 60.0)
	await wait(1.0)

	await walk_to(Vector3(0, 0, 6.4), 0.5, 10.0)
	face_point(bar.global_position)
	await wait(0.6)
	report("repair prompt shown near the breach", player.prompt_text.contains("repair"), "'%s'" % player.prompt_text)
	player.input.interact_held = true
	var rebuilt := await wait_until(func() -> bool: return bar.boards >= 4, 14.0)
	report("holding E rebuilds boards (replicated back to the client)", rebuilt, "boards=%d" % bar.boards)
	player.input.interact_held = false
	signal_peers("S2_done")
	await wait_signal("M2_done", 20.0)
	finish()
