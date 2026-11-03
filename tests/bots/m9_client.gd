extends BotScenario
## M9 client: presses ready, buys a weapon off the wall, sees its own upgrade cards (and nobody else's), spectates.


func run() -> void:
	var wm := wave_manager()
	var main := get_tree().root.get_node("Main")
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)

	await wait_signal("A_client_ready", 40.0)
	var sees := await wait_until(func() -> bool: return wm.ready_ids.has(1), 3.0)
	report("A: the client sees that the host is ready", sees)
	wm.press_ready(true)
	var started := await wait_until(func() -> bool: return wm.state == WaveManager.State.ACTIVE, 6.0)
	report("A: the wave started on the client too", started)

	await wait_signal("B_ready_check", 120.0)
	report("B: the client got no reward cards either", wm.my_offers.is_empty() and not main.cards.visible)
	await wait_signal("READY2", 30.0)
	wm.press_ready(true)

	await wait_signal("W_done", 120.0)
	var host_p := other_player()
	report("W: the client sees what the host bought on the wall", host_p.weapons.owned.count(true) >= 2 and host_p.armor >= 0)

	await wait_signal("U_inside", 120.0)
	var mach := Interactable.find_by_index(get_tree(), 20)
	var shown := await wait_until(func() -> bool: return mach._slot_view.has(1) and mach._status.visible and mach._status.text.contains("Shotgun"), 3.0)
	report("U: the client sees whose weapon is inside the machine, on its sign", shown, mach._status.text)
	await wait_signal("U_cards", 120.0)
	report("U: the host's upgrade cards did not show up here", wm.my_offers.is_empty() and not main.cards.visible)
	await wait_signal("G_cards", 120.0)
	report("G: ...nor the gear cards", wm.my_offers.is_empty())
	await wait_signal("G_done", 120.0)

	await wait_signal("READY3", 120.0)
	wm.press_ready(true)

	await wait_signal("H_start", 60.0)
	var out := await wait_until(func() -> bool: return player.status == Player.Status.ELIMINATED, 5.0)
	report("H: the client is out", out)
	await wait_signal("H_out", 20.0)
	await wait(0.3)
	report("H: a spectator has no gun in front of the camera", not player.weapons._viewmodel.visible)
	signal_peers("H_checked")
	await wait_signal("H_back", 20.0)
	var back := await wait_until(func() -> bool: return player.status == Player.Status.ALIVE, 5.0)
	report("H: back in the game, the gun is back", back and player.weapons._viewmodel.visible)
	signal_peers("M9_done")
	await wait(0.5)
	finish()
