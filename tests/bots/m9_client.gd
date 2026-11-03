extends BotScenario
## M9 client: presses ready, sees its own cards, picks one, checks the replicated ready list, and spectates.


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

	await wait_signal("B_cards", 120.0)
	var got := await wait_until(func() -> bool: return wm.my_offers.size() == 3, 3.0)
	report("B: the client got its own three cards", got, "n=%d" % wm.my_offers.size())
	var opened := await wait_until(func() -> bool: return main.cards.visible and Net.ui_blocking, 5.0)
	report("B: ...and the card screen opened for it after a moment", opened)
	await wait_signal("B_picked", 30.0)
	wm.request_pick(1)
	await wait(0.6)
	report("B: the client's cards go away after picking", wm.my_offers.is_empty() and not main.cards.visible)
	signal_peers("B_client_picked")

	await wait_signal("READY2", 30.0)
	wm.press_ready(true)
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
