extends BotScenario
## M9 host: the ready button (no countdown), the reward cards between rounds, weapon buffs and their effects,
## endless rounds, armor / second wind, the compact team health bars, and what a spectator sees.

const Hit := PlayerWeapons.Hit


func _clear_wave(wm: WaveManager, timeout: float) -> bool:
	var t := 0.0
	while t < timeout and wm.state != WaveManager.State.BREAK:
		for z in enemies():
			z.srv_hit(100000, Vector3.ZERO, 0.0, player)
		await wait(0.25)
		t += 0.25
	return wm.state == WaveManager.State.BREAK


func _hit(z: Zombie, weapon: int = 0) -> void:
	var eye := player.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0)
	player.weapons._srv_hits(weapon, eye, [[Hit.ENEMY, z.net_id, 1, z.global_position + Vector3(0, 1.0, 0), 0]])


func _total_mods(p: Player) -> int:
	var n := 0
	for d in p.weapons.mods:
		for k in d:
			n += int(d[k])
	return n


func run() -> void:
	var wm := wave_manager()
	var main := get_tree().root.get_node("Main")
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	var client := other_player()
	await wait(1.5)

	# --- A: the ready button replaces the countdown ---
	await wait(3.0)
	report("A: the first break just waits (no countdown)", wm.state == WaveManager.State.BREAK and wm.wave == 0)
	wm.press_ready(true)
	await wait(0.8)
	report("A: one ready player does not start the wave", wm.state == WaveManager.State.BREAK and wm.ready_ids.has(1) and wm.ready_ids.size() == 1)
	signal_peers("A_client_ready")
	var started := await wait_until(func() -> bool: return wm.state == WaveManager.State.ACTIVE, 6.0)
	report("A: the wave starts once everybody is ready", started and wm.wave == 1 and wm.ready_ids.is_empty(), "wave=%d" % wm.wave)

	# --- B: clearing it hands out three reward cards each ---
	var ended := await _clear_wave(wm, 90.0)
	report("B: clearing a wave starts a break, not a victory", ended)
	await wait(0.8)
	report("B: the cards do not pop up the instant the wave ends", not main.cards.visible and not Net.ui_blocking)
	await wait(2.4) # CARDS_DELAY
	report("B: the host holds three cards", wm.my_offers.size() == 3, "n=%d" % wm.my_offers.size())
	report("B: the card screen is open and holds the player still", main.cards.visible and Net.ui_blocking)
	var seen := {}
	var valid := true
	for o in wm.my_offers:
		seen[int(o["w"])] = true
		var new_card: bool = String(o["mod"]) == ""
		valid = valid and (new_card != player.weapons.owned[int(o["w"])]) # new weapons only for ones we lack, buffs only for ones we own
	report("B: three different weapons, new ones or buffs for owned ones", seen.size() == 3 and valid)
	signal_peers("B_cards")
	var offer: Dictionary = wm.my_offers[0]
	var owned_before := player.weapons.owned.count(true)
	var mods_before := _total_mods(player)
	wm.request_pick(0)
	await wait(0.6)
	var gained := (player.weapons.owned.count(true) == owned_before + 1) if String(offer["mod"]) == "" else (_total_mods(player) == mods_before + 1)
	report("B: taking a card gives the weapon or the buff", gained, "%s" % str(offer))
	report("B: ...and the cards go away", wm.my_offers.is_empty() and not main.cards.visible and not Net.ui_blocking)
	var snapshot := "%d/%d" % [player.weapons.owned.count(true), _total_mods(player)]
	wm.request_pick(1)
	await wait(0.4)
	report("B: a second pick does nothing", snapshot == "%d/%d" % [player.weapons.owned.count(true), _total_mods(player)])
	signal_peers("B_picked")
	await wait_signal("B_client_picked", 20.0)
	await wait(0.4)
	report("B: the client's pick shows up on the host", client.weapons.owned.count(true) + _total_mods(client) == 2, "owned=%d mods=%d" % [client.weapons.owned.count(true), _total_mods(client)])
	# the next wave: endless rounds
	wm.press_ready(true)
	signal_peers("READY2")
	var second := await wait_until(func() -> bool: return wm.state == WaveManager.State.ACTIVE and wm.wave == 2, 8.0)
	report("B: the second wave starts when both are ready", second)
	wm.hold = true # from here on the test stages everything itself
	for e in enemies():
		e.free()
	wm.to_spawn = 0
	wm.state = WaveManager.State.BREAK
	await wait(0.5)

	# --- C: buffs change the numbers ---
	var w := player.weapons
	var dmg0 := w.damage_mult(0)
	var mag0 := w.mag_size_of(0)
	var rate0 := w.interval_of(0)
	var knock0 := w.knock_mult(0)
	w.apply_mod.rpc(0, &"dmg")
	w.apply_mod.rpc(0, &"mag")
	w.apply_mod.rpc(0, &"rate")
	w.apply_mod.rpc(0, &"knock")
	await wait(0.3)
	report("C: Heavy Hitter adds 20% damage", is_equal_approx(w.damage_mult(0), dmg0 + 0.2))
	report("C: Extended Mag grows the magazine and refills it", w.mag_size_of(0) > mag0 and w.ammo[0] == w.mag_size_of(0), "mag %d -> %d" % [mag0, w.mag_size_of(0)])
	report("C: Hair Trigger speeds up fire", w.interval_of(0) < rate0 - 0.01)
	report("C: Heavy Rounds add knockback", w.knock_mult(0) > knock0)

	# --- D: the special effects, on a dummy zombie that stands still ---
	var a := wm.spawn_at(Vector3(-2.0, 0, -4.0), 0, 5000, 0.0)
	var b := wm.spawn_at(Vector3(-0.2, 0, -4.0), 0, 5000, 0.0)
	await wait(0.6)
	w.apply_mod.rpc(0, &"bleed")
	w.apply_mod.rpc(0, &"freeze")
	w.apply_mod.rpc(0, &"life")
	w.apply_mod.rpc(0, &"life")
	w.apply_mod.rpc(0, &"life")
	await wait(0.3)
	player.hp = 50
	_hit(a)
	await wait(0.3)
	report("D: Bleeding makes the zombie bleed", a._bleed_left > 2.0 and a._bleed_dps >= 6.0, "left=%.1f" % a._bleed_left)
	report("D: Frostbite slows it down", a._freeze_left > 1.0 and a._freeze_mult < 1.0, "mult=%.2f" % a._freeze_mult)
	report("D: Vampiric heals the shooter", player.hp > 50, "hp=%d" % player.hp)
	var hp_a := a.hp
	await wait(2.0)
	report("D: the wound keeps costing it health", a.hp < hp_a - 6, "%d -> %d" % [hp_a, a.hp])
	for lvl in 3: # Spark: 20% per level, so up to 60% per hit
		w.apply_mod.rpc(0, &"spark")
	var chained := false
	for i in 25:
		await wait(0.25)
		_hit(a)
		if b.hp < b.max_hp:
			chained = true
			break
	report("D: Static Spark arcs lightning to a neighbour", chained)
	for lvl in 3:
		w.apply_mod.rpc(0, &"boing")
		w.apply_mod.rpc(0, &"disco")
		w.apply_mod.rpc(0, &"blast")
	var boinged := false
	var danced := false
	var blasted := false
	var b_hp := b.hp
	for i in 40:
		await wait(0.25)
		_hit(a)
		boinged = boinged or a.velocity.y > 4.0 or a.is_fallen()
		danced = danced or a.state == Zombie.State.DANCE
		blasted = blasted or b.hp < b_hp - 12 # a burst does half the hit (15+); a spark only 7
		b_hp = b.hp
		if boinged and danced and blasted:
			break
	report("D: Springy boings a zombie into the air", boinged)
	report("D: Disco Fever makes a zombie dance", danced)
	report("D: Boom Rounds burst around the zombie that was hit", blasted)
	a.free()
	b.free()
	await wait(0.3)

	# --- E: the run never ends on its own ---
	var c10 := GameConfig.wave_cfg(10)
	var c30 := GameConfig.wave_cfg(30)
	report("E: waves keep growing past the table", int(c30["count"]) > int(c10["count"]) and int(c30["hp"]) > int(c10["hp"]) and int(c30["max_alive"]) <= 30, "count %d -> %d" % [c10["count"], c30["count"]])
	report("E: crawlers join from wave 4", int(GameConfig.wave_cfg(3)["crawlers"]) == 0 and int(GameConfig.wave_cfg(4)["crawlers"]) >= 1)
	wm.wave = 10
	wm.state = WaveManager.State.ACTIVE
	wm.to_spawn = 0
	wm._end_wave()
	report("E: finishing wave 10 is just another break", wm.state == WaveManager.State.BREAK and wm.my_offers.size() == 3)
	wm.press_ready(true)
	signal_peers("READY3")
	wm.hold = false
	var eleven := await wait_until(func() -> bool: return wm.state == WaveManager.State.ACTIVE and wm.wave == 11, 8.0)
	report("E: wave 11 starts", eleven and wm.to_spawn > 0, "wave=%d" % wm.wave)
	wm.hold = true
	for e in enemies():
		e.free()
	wm.to_spawn = 0
	wm.state = WaveManager.State.BREAK

	# --- F: armor, second wind, adrenaline ---
	player._invuln = 0.0
	player.hp = 100
	player.armor = 50
	player.srv_take_damage(20)
	report("F: armor soaks 60% of a hit", player.armor == 38 and player.hp == 92, "armor=%d hp=%d" % [player.armor, player.hp])
	player.srv_take_damage(300)
	report("F: a broken vest lets the rest through", player.armor == 0 and player.status == Player.Status.DOWNED, "armor=%d hp=%d" % [player.armor, player.hp])
	player.srv_restore(player.global_position, false)
	player._invuln = 0.0
	player.second_wind = true
	player.hp = 10
	player.srv_take_damage(50)
	report("F: Second Wind gets you back up instead of going down", player.status == Player.Status.ALIVE and player.hp == GameConfig.SECOND_WIND_HP and not player.second_wind, "hp=%d" % player.hp)
	player._invuln = 0.0
	player.srv_give_boost(5.0)
	report("F: Adrenaline makes you faster", is_equal_approx(player._speed_multiplier(), GameConfig.ADRENALINE_SPEED))
	player.boost_left = 0.0
	report("F: the armor item stops at the cap", player.srv_add_armor(500) and player.armor == GameConfig.ARMOR_MAX and not player.srv_add_armor(1))
	player.armor = 0

	# --- G: the team bars ---
	await wait(0.6)
	report("G: the HUD shows a health bar for every player", main.hud._team_rows.size() == 2, "rows=%d" % main.hud._team_rows.size())

	# --- H: spectating ---
	signal_peers("H_start")
	client._srv_eliminate()
	await wait(1.0)
	signal_peers("H_out")
	await wait_signal("H_checked", 20.0)
	client.srv_restore(client.global_position, false)
	signal_peers("H_back")
	await wait_signal("M9_done", 20.0)
	finish()
