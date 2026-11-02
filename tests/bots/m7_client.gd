extends BotScenario
## M7 client: sees the shared cash, uses the bandage stand with its own cooldown, watches the levers, the gate
## and the mystery box purchase from the other side of the network.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return
	var wm := wave_manager()
	var annex := get_tree().get_first_node_in_group("annex") as Annex
	var host_player := other_player()

	await wait_signal("CASH_260", 60.0)
	var cash := await wait_until(func() -> bool: return wm.cash == 260, 3.0)
	report("C: the shared cash shows up on this peer", cash, "cash=%d" % wm.cash)
	report("P: this client starts with just the pistol", player.weapons.owned.count(true) == 1)

	await wait_signal("D_client", 60.0)
	player._apply_teleport(Vector3(-9.0, 0.1, 6.4))
	await wait(1.0)
	report("D: the prompt offers bandages", player.prompt_text.contains("andage"), player.prompt_text)
	player.input.interact_held = true
	var healed := await wait_until(func() -> bool: return player.hp >= 75, 4.0)
	player.input.interact_held = false
	report("D: the client heals at the stand", healed, "hp=%d" % player.hp)
	signal_peers("D_client_done")

	await wait_signal("LEVER_PULLED", 90.0)
	var pulled := await wait_until(func() -> bool: return annex.lever1, 3.0)
	report("L: the client sees the lever pulled", pulled)
	await wait_signal("DOOR_OPEN", 60.0)
	var open := await wait_until(func() -> bool: return annex.is_open and annex.gate.collision_layer == 0, 3.0)
	report("L: the client sees the gate open (and no longer solid)", open)

	await wait_signal("BOX_DONE", 60.0)
	var got := await wait_until(func() -> bool: return host_player.weapons.owned.count(true) == 2, 3.0)
	report("M: the client sees the host's new weapon", got, "owned=%d" % host_player.weapons.owned.count(true))
	await wait_signal("TESLA_DONE", 60.0)
	report("T: the client saw the lightning", Fx.lightning_count > 0, "n=%d" % Fx.lightning_count)
	await wait_signal("M7_done", 60.0)
	finish()
