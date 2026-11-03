extends BotScenario
## M7 host: pistol-only start, shared cash (kills, headshots, board repair), invisible walls, health shops,
## the two-lever annex door (cancel, timeout refund, one-player flow), mystery box, medkit, Tesla chain, Boing,
## stumbling over a fallen zombie, ADS. Run without --all-weapons (tests/run_tests.ps1: Plain).


func _hold_e(sec: float) -> void:
	player.input.interact_held = true
	await wait(sec)
	player.input.interact_held = false
	await wait(0.3)


func _kill_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await wait(0.4)


func _entrances(count: int) -> Array:
	var wm := wave_manager()
	var seen := []
	wm.to_spawn = 1000
	for i in count:
		wm._spawn_one(GameConfig.WAVES[0])
	for z in enemies():
		if not seen.has(z.entrance_idx):
			seen.append(z.entrance_idx)
	await _kill_all()
	return seen


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var annex := get_tree().get_first_node_in_group("annex") as Annex
	Net.debug_snack_chance = 0.0
	await wait(2.0)

	# --- P: everyone starts with only the pistol ---
	report("P: players start with just the pistol", player.weapons.owned.count(true) == 1 and client.weapons.owned.count(true) == 1 and player.weapons.owned[0])
	player.input.weapon_slot = 1
	await wait(0.6)
	report("P: a weapon you do not own cannot be equipped", player.weapons.current == 0)

	# --- C: shared cash from kills (headshot bonus, specials) ---
	report("C: the run starts with no cash", wm.cash == 0, "cash=%d" % wm.cash)
	player._apply_teleport(Vector3(0, 0.1, 2))
	await wait(0.6)
	var z1 := wm.spawn_at(Vector3(0, 0, -5), 0, 1000, 0.0)
	await wait(0.5)
	var s := z1.puppet.scale.x
	var hp0 := z1.hp
	aim_at(z1.global_position + Vector3(0, 0.9 * s, 0))
	await wait(0.3)
	await fire()
	await wait(0.6)
	var body_dmg := hp0 - z1.hp
	hp0 = z1.hp
	aim_at(z1.global_position + Vector3(0, 1.58 * s, 0))
	await wait(0.3)
	await fire()
	await wait(0.6)
	var head_dmg := hp0 - z1.hp
	report("H: a body shot does normal damage", body_dmg >= 22 and body_dmg <= 26, "dmg=%d" % body_dmg)
	report("H: a headshot does double damage", head_dmg >= 2 * body_dmg - 3 and head_dmg <= 2 * body_dmg + 3, "dmg=%d" % head_dmg)
	var c0 := wm.cash
	z1.srv_hit(1000000, Vector3.ZERO, 0.0, player)
	await wait(0.4)
	report("C: killing a zombie pays $%d to the shared pot" % GameConfig.CASH_KILL, wm.cash - c0 == GameConfig.CASH_KILL, "delta=%d" % (wm.cash - c0))
	var z2 := wm.spawn_at(Vector3(0, 0, -5), 0, 30, 0.0)
	await wait(0.5)
	c0 = wm.cash
	aim_at(z2.global_position + Vector3(0, 1.58 * z2.puppet.scale.x, 0))
	await wait(0.3)
	await fire()
	await wait(0.8)
	report("C: a headshot kill pays a bonus", wm.cash - c0 == GameConfig.CASH_KILL + GameConfig.CASH_HEADSHOT_BONUS, "delta=%d" % (wm.cash - c0))
	var lz := wm.spawn_at(Vector3(0, 0, -5), 0, GameConfig.LEAPER_HP, 0.0, Zombie.Kind.LEAPER)
	await wait(0.4)
	c0 = wm.cash
	lz.srv_hit(1000000, Vector3.ZERO, 0.0, player)
	await wait(0.4)
	report("C: a special zombie pays more", wm.cash - c0 == GameConfig.CASH_KILL_SPECIAL, "delta=%d" % (wm.cash - c0))
	await _kill_all()

	# repairing a board pays too
	var bar := level.barricades[0]
	bar.srv_damage(GameConfig.BOARD_HP)
	player._apply_teleport(bar.global_position - bar.outward_dir() * 1.7)
	face_point(bar.global_position)
	await wait(0.6)
	c0 = wm.cash
	player.input.interact_held = true
	var fixed := await wait_until(func() -> bool: return bar.boards == Barricade.MAX_BOARDS, 6.0)
	player.input.interact_held = false
	await wait(0.3)
	report("C: repairing a board pays $%d" % GameConfig.CASH_PER_BOARD, fixed and wm.cash - c0 == GameConfig.CASH_PER_BOARD, "delta=%d" % (wm.cash - c0))
	wm.cash = 0
	wm.srv_add_cash(260)
	signal_peers("CASH_260")

	# --- W: the invisible wall keeps players inside even when the windows are wide open ---
	var wall_cases := [
		[0, Vector3(0, 0.1, 5.5), Vector3(0, 0, 13), "z", 8.2, true],
		[3, Vector3(-8.0, 0.1, -5.5), Vector3(-14, 0, -5.5), "x", -11.2, false],
		[4, Vector3(-7.0, 0.1, 5.5), Vector3(-7, 0, 13), "z", 8.2, true],
	]
	for wc in wall_cases:
		var b := level.barricades[wc[0]]
		b.srv_damage(GameConfig.BOARD_HP * 6.0)
		player._apply_teleport(wc[1])
		await wait(0.5)
		var got_out := await walk_to(wc[2], 0.5, 2.5)
		var coord: float = player.global_position.z if wc[3] == "z" else player.global_position.x
		var inside: bool = coord < wc[4] if wc[5] else coord > wc[4]
		report("W: window %d is open (no boards) but the player cannot walk out" % wc[0], b.boards == 0 and not got_out and inside, "pos=%s" % str(player.global_position))
		b.srv_reset()
	level.barricades[0].srv_reset()

	# --- D: bandage stand (saloon) ---
	wm.cash = 300
	player.hp = 100
	player._apply_teleport(Vector3(-9.0, 0.1, 6.4))
	await wait(0.8)
	report("D: at full health the stand says so", player.prompt_text.contains("full health"), player.prompt_text)
	player.hp = 40
	await wait(0.4)
	await _hold_e(1.4)
	report("D: bandages heal 25 HP for $%d" % GameConfig.BANDAGE_COST, player.hp == 40 + GameConfig.BANDAGE_HEAL and wm.cash == 300 - GameConfig.BANDAGE_COST, "hp=%d cash=%d" % [player.hp, wm.cash])
	player.hp = 40
	await wait(0.3)
	await _hold_e(1.4)
	report("D: the stand has a per-player cooldown", player.hp == 40 and wm.cash == 300 - GameConfig.BANDAGE_COST, "hp=%d cash=%d" % [player.hp, wm.cash])
	client.hp = 50
	signal_peers("D_client")
	await wait_signal("D_client_done", 30.0)
	report("D: the other player has their own cooldown", client.hp == 50 + GameConfig.BANDAGE_HEAL and wm.cash == 300 - 2 * GameConfig.BANDAGE_COST, "hp=%d cash=%d" % [client.hp, wm.cash])
	player.hp = 100

	# --- E: annex entrances are inactive while it is closed ---
	var closed_set := await _entrances(40)
	report("E: the two new saloon windows get zombies", closed_set.has(3) or closed_set.has(4), str(closed_set))
	report("E: the annex windows stay quiet while the annex is closed", not closed_set.has(5) and not closed_set.has(6), str(closed_set))

	# --- L: levers ---
	wm.cash = 100
	player._apply_teleport(Vector3(10.2, 0.1, -4.8))
	await wait(0.8)
	report("L: the lever shows its price", player.prompt_text.contains("$250"), player.prompt_text)
	await _hold_e(2.0)
	report("L: a lever you cannot afford does nothing", not annex.lever1 and wm.cash == 100, "cash=%d" % wm.cash)
	wm.cash = 600
	await wait(0.4)
	report("L: the prompt offers to pull it", player.prompt_text.contains("Hold [E]"), player.prompt_text)
	player.input.interact_held = true
	await wait(2.2) # keeps holding past the hold time: it must not cancel itself
	player.input.interact_held = false
	await wait(0.3)
	report("L: holding E pulls the lever and takes $250", annex.lever1 and wm.cash == 350, "lever=%s cash=%d" % [annex.lever1, wm.cash])
	signal_peers("LEVER_PULLED")
	await wait(0.4)
	report("L: a pulled lever offers a cancel", player.prompt_text.contains("back"), player.prompt_text)
	await _hold_e(1.0)
	report("L: cancelling puts the lever back and refunds", not annex.lever1 and wm.cash == 600, "lever=%s cash=%d" % [annex.lever1, wm.cash])
	await _hold_e(2.0)
	report("L: pull it again", annex.lever1 and wm.cash == 350)
	annex.latch_left = 0.6
	var slipped := await wait_until(func() -> bool: return not annex.lever1, 3.0)
	report("L: letting the window run out refunds the lever", slipped and wm.cash == 600, "cash=%d" % wm.cash)

	player._apply_teleport(Vector3(9.0, 0.1, 0))
	await wait(0.5)
	var through := await walk_to(Vector3(14, 0, 0), 0.5, 2.5)
	report("L: the gate blocks the doorway while closed", not through and player.global_position.x < 11.2, "x=%.1f" % player.global_position.x)

	# one player, both levers: pull one, run to the other
	player._apply_teleport(Vector3(10.2, 0.1, -4.8))
	await wait(0.6)
	await _hold_e(2.0)
	var first := annex.lever1
	var ran := await walk_to(Vector3(10.2, 0, 3.8), 0.4, 6.0)
	await wait(0.4)
	report("L: one player can walk from the first lever to the second", first and ran and annex.latch_left > 0.0, "t=%.1f" % annex.latch_left)
	report("L: the second lever prompt is shown", player.prompt_text.contains("second lever"), player.prompt_text)
	await _hold_e(2.0)
	report("L: both levers are down and the door starts", annex.lever1 and annex.lever2 and wm.cash == 100, "cash=%d" % wm.cash)
	await wait(1.0)
	report("L: the door animation is running", annex.door_t > 0.1 and not annex.is_open, "t=%.2f" % annex.door_t)
	var opened := await wait_until(func() -> bool: return annex.is_open, 7.0)
	report("L: the gate opens after the animation", opened and annex.gate.collision_layer == 0)
	signal_peers("DOOR_OPEN")
	player._apply_teleport(Vector3(9.0, 0.1, 0))
	await wait(0.5)
	through = await walk_to(Vector3(14, 0, 0), 0.5, 3.0)
	report("L: players can walk into the annex", through and player.global_position.x > 13.0, "x=%.1f" % player.global_position.x)

	# --- A: annex windows now take zombies ---
	var open_set := await _entrances(40)
	report("A: zombies now also come through the annex windows", open_set.has(5) or open_set.has(6), str(open_set))

	# --- K: medkit ---
	wm.cash = 1000
	player.hp = 30
	player._apply_teleport(Vector3(34.2, 0.1, 6.6))
	await wait(0.8)
	await _hold_e(1.4)
	report("K: the medkit heals fully for $%d" % GameConfig.MEDKIT_COST, player.hp == GameConfig.PLAYER_MAX_HP and wm.cash == 1000 - GameConfig.MEDKIT_COST, "hp=%d cash=%d" % [player.hp, wm.cash])
	player.hp = 50
	await wait(0.3)
	await _hold_e(1.4)
	report("K: ...and has a cooldown", player.hp == 50 and wm.cash == 1000 - GameConfig.MEDKIT_COST, "hp=%d" % player.hp)
	player.hp = 100

	# --- H: the hall behind the annex has its own, dearer pair of levers ---
	var hall := Annex.find_stage(get_tree(), 2)
	wm.cash = 1000
	player._apply_teleport(Vector3(34.6, 0.1, -6.8))
	await wait(0.8)
	report("H: the hall lever shows its price", player.prompt_text.contains("$%d" % GameConfig.LEVER_COST_STAGE2), player.prompt_text)
	await _hold_e(2.0)
	report("H: pulling it costs $%d and latches it" % GameConfig.LEVER_COST_STAGE2, hall.lever1 and wm.cash == 1000 - GameConfig.LEVER_COST_STAGE2, "cash=%d" % wm.cash)
	report("H: the hall stays closed meanwhile", not hall.is_open and hall.gate.collision_layer != 0)
	player._apply_teleport(Vector3(34.6, 0.1, 3.4))
	await wait(0.8)
	await _hold_e(2.0)
	report("H: the second lever starts the door", hall.lever2 and wm.cash == 0, "cash=%d" % wm.cash)
	var hall_open := await wait_until(func() -> bool: return hall.is_open, 7.0)
	report("H: the hall gate opens after the animation", hall_open and hall.gate.collision_layer == 0)
	player._apply_teleport(Vector3(34.5, 0.1, 0.0))
	await wait(0.4)
	var into_hall := await walk_to(Vector3(40, 0, 0), 0.5, 3.5)
	report("H: players can walk into the hall", into_hall and player.global_position.x > 38.0, "x=%.1f" % player.global_position.x)
	var hall_set := await _entrances(40)
	report("H: zombies now also come through the hall windows", hall_set.has(7) or hall_set.has(8), str(hall_set))

	# --- M: mystery box (in the hall) sells support items ---
	player._apply_teleport(Vector3(58.2, 0.1, -5.0))
	wm.cash = 100
	await wait(0.8)
	report("M: the box shows its price", player.prompt_text.contains("$400"), player.prompt_text)
	await _hold_e(1.6)
	report("M: too poor for the box", wm.cash == 100)
	wm.cash = 1000
	player.hp = 40
	await wait(0.4)
	var before := _support_state(player)
	await _hold_e(1.8)
	report("M: the box sells a random support item for $%d" % GameConfig.BOX_COST, wm.cash == 1000 - GameConfig.BOX_COST and _support_state(player) != before, "%s -> %s" % [before, _support_state(player)])
	player.hp = 100
	signal_peers("BOX_DONE")

	# --- T: Tesla gun chains through three nearby zombies ---
	player._apply_teleport(Vector3(0, 0.1, 2))
	player.weapons.give_weapon.rpc(4)
	player.weapons.give_weapon.rpc(5)
	await wait(0.8)
	var zs: Array = []
	for off in [Vector3(0, 0, -4), Vector3(1.4, 0, -4), Vector3(-1.4, 0, -4), Vector3(0, 0, -5.4), Vector3(9.0, 0, -3.5)]:
		zs.append(wm.spawn_at(off, 0, 1000, 0.0))
	await wait(0.6)
	player.input.weapon_slot = 4
	await wait(0.9)
	var l0 := Fx.lightning_count
	aim_at(zs[0].global_position + Vector3(0, 1.0, 0))
	await wait(0.3)
	await fire()
	await wait(0.8)
	report("T: the Tesla gun hurts the zombie it hits", zs[0].hp < 1000, "hp=%d" % zs[0].hp)
	report("T: ...and arcs to the three zombies next to it", zs[1].hp < 1000 and zs[2].hp < 1000 and zs[3].hp < 1000, "hp=%d,%d,%d" % [zs[1].hp, zs[2].hp, zs[3].hp])
	report("T: ...but not to one far away", zs[4].hp == 1000, "hp=%d" % zs[4].hp)
	report("T: the lightning effect was spawned", Fx.lightning_count > l0)
	signal_peers("TESLA_DONE")

	# --- B: Boing gun launches a zombie ---
	player.input.weapon_slot = 5
	await wait(0.9)
	var bz: Zombie = zs[0]
	aim_at(bz.global_position + Vector3(0, 1.0, 0))
	await wait(0.3)
	await fire()
	var flew := await wait_until(func() -> bool: return bz.global_position.y > 1.2, 1.5)
	report("B: the Boing gun sends a zombie flying", flew, "y=%.1f" % bz.global_position.y)
	await _kill_all()

	# --- S: stumbling over a fallen zombie ---
	player.input.weapon_slot = 0
	var sz := wm.spawn_at(Vector3(0, 0, -3), 0, 1000, 0.0)
	await wait(0.5)
	sz.srv_trip()
	player._apply_teleport(Vector3(0, 0.1, 1.0))
	await wait(0.4)
	player.input.aim_yaw = 0.0
	player.input.move = Vector2(0, -1)
	var tripped := await wait_until(func() -> bool: return (player.sync_flags & Player.FLAG_STAGGER) != 0 or player.stagger_time > 0.0, 2.5)
	player.input.move = Vector2.ZERO
	report("S: walking into a fallen zombie trips you", tripped)
	await _kill_all()
	await wait(1.5)

	# --- R: right mouse button aims down the sights ---
	player.input.weapon_slot = 0
	await wait(0.6)
	player.input.ads = true
	await wait(0.8)
	report("R: holding the right mouse button aims down the sights", player.ads and player.camera.fov < 60.0, "fov=%.0f" % player.camera.fov)
	player.input.ads = false
	await wait(0.8)
	report("R: releasing it zooms back out", not player.ads and player.camera.fov > 70.0, "fov=%.0f" % player.camera.fov)

	signal_peers("M7_done")
	await wait(0.6)
	finish()


func _support_state(p: Player) -> String:
	return "%d/%d/%.0f/%s" % [p.hp, p.armor, p.boost_left, str(p.second_wind)]
