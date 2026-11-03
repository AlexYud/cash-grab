extends BotScenario
## M9 host: the ready button (no countdown, no round cards), COD-style wall buys, the weapon upgrader and the armor
## upgrader (three cards, endless pools), every weapon effect, the gear effects, endless waves, the team bars, spectating.

const Hit := PlayerWeapons.Hit


func _clear_wave(wm: WaveManager, timeout: float) -> bool:
	var t := 0.0
	while t < timeout and wm.state != WaveManager.State.BREAK:
		for z in enemies():
			z.srv_hit(100000, Vector3.ZERO, 0.0, player)
		await wait(0.25)
		t += 0.25
	return wm.state == WaveManager.State.BREAK


func _hit(z: Zombie, head: int = 0, weapon: int = 0) -> void:
	var eye := player.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0)
	player.weapons._srv_hits(weapon, eye, [[Hit.ENEMY, z.net_id, 1, z.global_position + Vector3(0, 1.0, 0), head]])


func _hold_e(sec: float) -> void:
	player.input.interact_held = true
	await wait(sec)
	player.input.interact_held = false
	await wait(0.3)


func _goto(pos: Vector3) -> void:
	player._apply_teleport(pos)
	await wait(0.7)


func _gear(key: StringName, times: int = 1) -> void:
	for i in times:
		player.srv_apply_gear(key)


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

	# --- B: clearing a wave deals no cards any more; Tab opens a plain ready panel ---
	var ended := await _clear_wave(wm, 90.0)
	report("B: clearing a wave starts a break, not a victory", ended)
	var cheapest := 99999
	for price in GameConfig.WEAPON_PRICES.values():
		cheapest = mini(cheapest, int(price))
	report("B: the very first wave already pays for a wall buy (clear bonus included)", wm.cash >= GameConfig.CASH_WAVE_CLEAR_BASE and wm.cash >= cheapest, "cash=%d cheapest=%d" % [wm.cash, cheapest])
	await wait(1.0)
	report("B: ...and deals no reward cards", wm.my_offers.is_empty() and not main.cards.visible and not Net.ui_blocking)
	main._break_panel = true
	await wait(0.5)
	report("B: the ready panel opens on demand", main.cards.visible and Net.ui_blocking)
	main._break_panel = false
	await wait(0.5)
	signal_peers("B_ready_check")
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

	# --- W: wall buys, one spot per weapon ---
	var seen := {}
	var dupes := false
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it.kind == Interactable.Kind.WALL_WEAPON:
			dupes = dupes or seen.has(it.item)
			seen[it.item] = it
	report("W: every weapon except the pistol has exactly one wall spot", seen.size() == 10 and not dupes and not seen.has(&"pistol"), "spots=%d" % seen.size())
	var rooms := {}
	for it in seen.values():
		var x: float = it.global_position.x
		rooms[0 if x < 11.0 else (1 if x < 36.0 else 2)] = true
	report("W: ...spread through all three rooms", rooms.size() == 3)
	wm.cash = 1000
	await _goto(Vector3(-3.5, 0.1, 6.9))
	report("W: the shotgun spot shows its price", player.prompt_text.contains("$%d" % GameConfig.WEAPON_PRICES[&"shotgun"]), player.prompt_text)
	await _hold_e(1.5)
	var gi := -1
	for i in player.weapons.list.size():
		if player.weapons.list[i].id == &"shotgun":
			gi = i
	report("W: holding E buys the weapon", player.weapons.owned[gi] and wm.cash == 1000 - GameConfig.WEAPON_PRICES[&"shotgun"], "cash=%d" % wm.cash)
	await _hold_e(1.5)
	report("W: buying it again costs nothing", wm.cash == 1000 - GameConfig.WEAPON_PRICES[&"shotgun"])
	wm.cash = 100
	await _goto(Vector3(3.0, 0.1, -6.9))
	await _hold_e(1.5)
	report("W: too poor for the katana", player.weapons.owned.count(true) == 2 and wm.cash == 100)
	wm.cash = 1000
	await _goto(Vector3(13.0, 0.1, 7.9))
	await _hold_e(1.5)
	report("W: the armor vest is for sale on the wall", player.armor == GameConfig.ARMOR_ITEM and wm.cash == 1000 - GameConfig.ARMOR_BUY_COST, "armor=%d" % player.armor)
	await _goto(Vector3(32.5, 0.1, 7.9))
	await _hold_e(1.5)
	report("W: so is adrenaline", player.boost_left > 20.0 and wm.cash == 500 - GameConfig.ADRENALINE_COST, "boost=%.0f" % player.boost_left)
	player.boost_left = 0.0
	signal_peers("W_done")

	# --- U: the weapon upgrader (annex): hand the weapon in and pay, wait 5 s, collect it and pick an upgrade ---
	var w := player.weapons
	var machine := Interactable.find_by_index(get_tree(), 20)
	var gun := w.current # the shotgun bought above
	wm.cash = 5000
	await _goto(Vector3(13.4, 0.1, -5.5))
	report("U: the machine says what it does and what it costs", player.prompt_text.contains("put your") and player.prompt_text.contains("$%d" % GameConfig.UPGRADE_BASE), player.prompt_text)
	await _hold_e(1.2)
	report("U: holding E takes the weapon out of your hands and charges for it", not w.owned[gun] and wm.cash == 5000 - GameConfig.UPGRADE_BASE and w.owned[0], "cash=%d" % wm.cash)
	report("U: the machine keeps it as yours", machine._slots.has(1) and int(machine._slots[1]["w"]) == gun)
	signal_peers("U_inside")
	await wait(1.0)
	report("U: it says it is busy and how long is left", player.prompt_text.contains("Upgrading") , player.prompt_text)
	await _hold_e(0.8)
	report("U: it cannot be collected before the 5 seconds are up", wm.my_offers.is_empty() and not w.owned[gun])
	await wait(4.0)
	report("U: when it is done it says so", player.prompt_text.contains("collect"), player.prompt_text)
	await _hold_e(1.2)
	var cards: Array = wm.my_offers.duplicate()
	var keys := {}
	var all_new := true
	for c in cards:
		keys[c["mod"]] = true
		all_new = all_new and int(c["lvl"]) == 1 and WeaponCards.MODS[StringName(c["mod"])]["kind"] == "fx"
	report("U: collecting it deals three different new effects first", cards.size() == 3 and keys.size() == 3 and all_new, str(keys.keys()))
	await wait(1.2)
	report("U: the card screen is open and the weapon is still in the machine", main.cards.visible and Net.ui_blocking and not w.owned[gun])
	main._cards_hidden = true # close it without choosing
	main._refresh_ui()
	await wait(0.4)
	report("U: walking away without choosing leaves the weapon in the machine", not w.owned[gun] and machine._slots.has(1))
	main._cards_hidden = false
	await _hold_e(1.2) # use the machine again: the same cards come back
	report("U: using the machine again brings the same cards back", wm.my_offers.size() == 3 and wm.my_offers[0]["mod"] == cards[0]["mod"] and main.cards.visible)
	signal_peers("U_cards")
	var key := StringName(cards[0]["mod"])
	var cash0 := wm.cash
	wm.request_pick(0)
	await wait(0.7)
	report("U: choosing a card gives the weapon back with that effect", w.owned[gun] and w.mod_level(gun, key) == 1 and w.current == gun, str(cards[0]))
	report("U: ...no further charge, the cards go away and the machine is empty", wm.cash == cash0 and wm.my_offers.is_empty() and not main.cards.visible and machine._slots.is_empty())
	await _hold_e(1.2)
	report("U: the next upgrade of that weapon costs more", wm.cash == cash0 - (GameConfig.UPGRADE_BASE + GameConfig.UPGRADE_STEP), "cash=%d" % wm.cash)
	await wait(5.4)
	for k in WeaponCards.MODS: # learn every effect once: the pool must switch to buffs and keep going
		if WeaponCards.MODS[k]["kind"] == "fx" and w.mod_level(gun, k) == 0:
			w.apply_mod.rpc(gun, k)
	await wait(0.4)
	await _hold_e(1.2)
	var all_buffs := wm.my_offers.size() == 3
	for c in wm.my_offers:
		all_buffs = all_buffs and not (WeaponCards.MODS[StringName(c["mod"])]["kind"] == "fx" and int(c["lvl"]) == 1)
	report("U: once every effect is learned the cards become effect levels and stat buffs", all_buffs, str(wm.my_offers))
	wm.request_pick(1)
	await wait(0.6)
	for i in 12:
		w.apply_mod.rpc(gun, &"dmg")
	await wait(0.3)
	report("U: upgrades never run out (level 12 and counting)", w.mod_level(gun, &"dmg") >= 12 and w.damage_mult(gun) > 3.0 and w.owned[gun])
	w.mods[gun].clear() # back to a plain weapon for the effect tests below
	w.current = 0

	# --- D: the weapon effects, on dummy zombies that stand still ---
	w.current = 0
	var a := wm.spawn_at(Vector3(-2.0, 0, -4.0), 0, 90000, 0.0)
	var b := wm.spawn_at(Vector3(-0.8, 0, -4.0), 0, 90000, 0.0)
	var c3 := wm.spawn_at(Vector3(2.6, 0, -4.0), 0, 90000, 0.0)
	await _goto(Vector3(-2.0, 0.1, 0.0))
	player.hp = 50
	for k in [&"bleed", &"freeze", &"life", &"life", &"life", &"ignite", &"headhunter", &"headhunter"]:
		w.apply_mod.rpc(0, k)
	await wait(0.3)
	_hit(a)
	await wait(0.3)
	report("D: Bleeding makes the zombie bleed", a._bleed_left > 2.0 and a._bleed_dps >= 6.0)
	report("D: Frostbite slows it down", a._freeze_left > 1.0 and a._freeze_mult < 1.0)
	report("D: Vampiric heals the shooter", player.hp > 50, "hp=%d" % player.hp)
	report("D: Burning sets it on fire", a._burn_left > 2.0)
	await wait(1.6)
	report("D: ...and the fire spreads to a neighbour", b._burn_left > 0.0)
	var h0 := a.hp
	_hit(a, 0)
	var plain := h0 - a.hp
	await wait(0.35)
	h0 = a.hp
	_hit(a, 1)
	var head := h0 - a.hp
	report("D: Headhunter makes headshots hit harder than the usual double", head > plain * 2.3, "plain=%d head=%d" % [plain, head])
	var pulled := false
	var d0 := c3.global_position.distance_to(a.global_position)
	for lvl in 8:
		w.apply_mod.rpc(0, &"vortex")
	for i in 30:
		await wait(0.25)
		_hit(a)
		if c3.global_position.distance_to(a.global_position) < d0 - 0.6:
			pulled = true
			break
	report("D: Black Hole sucks in the zombies around it", pulled)
	for lvl in 3:
		w.apply_mod.rpc(0, &"spark")
	var bolts := Fx.lightning_count
	var chained := false
	for i in 25:
		await wait(0.25)
		_hit(a)
		if Fx.lightning_count > bolts:
			chained = true
			break
	report("D: Static Spark arcs lightning to the zombies around", chained)
	for lvl in 3:
		w.apply_mod.rpc(0, &"boing")
		w.apply_mod.rpc(0, &"disco")
	var boinged := false
	var danced := false
	for i in 40:
		await wait(0.25)
		_hit(a)
		boinged = boinged or a.velocity.y > 4.0 or a.is_fallen()
		danced = danced or a.state == Zombie.State.DANCE
		if boinged and danced:
			break
	report("D: Springy boings a zombie into the air", boinged)
	report("D: Disco Fever makes a zombie dance", danced)
	for lvl in 4:
		w.apply_mod.rpc(0, &"pinata")
	var cash_before := wm.cash
	var rich := false
	for i in 8:
		var k := wm.spawn_at(Vector3(2.0, 0, -4.0 - i * 0.01), 0, 5, 0.0)
		await wait(0.3)
		_hit(k)
		await wait(0.2)
		if wm.cash - cash_before > GameConfig.CASH_KILL + GameConfig.CASH_HEADSHOT_BONUS:
			rich = true
			break
		cash_before = wm.cash
	report("D: Pinata pays extra cash for a kill", rich)
	for z in [a, b, c3]:
		z.free()
	await wait(0.3)

	# --- G: the armor upgrader (hall): hand the gear in, wait, collect it with an upgrade; then the gear effects ---
	wm.cash = 5000
	player.hp = 100
	player.armor = 30
	var gmachine := Interactable.find_by_index(get_tree(), 21)
	await _goto(Vector3(38.3, 0.1, -7.0))
	await _hold_e(1.2)
	report("G: handing the gear in takes its armor and effects away and charges for it", player.gear_away and player.armor == 0 and wm.cash == 5000 - GameConfig.GEAR_BASE, "armor=%d cash=%d" % [player.armor, wm.cash])
	await wait(5.5)
	await _hold_e(1.2)
	var gc: Array = wm.my_offers.duplicate()
	var gkeys := {}
	var gear_ok := true
	for c in gc:
		gkeys[c["mod"]] = true
		gear_ok = gear_ok and bool(c.get("gear", false)) and int(c["lvl"]) == 1
	report("G: collecting deals three different gear effects", gc.size() == 3 and gkeys.size() == 3 and gear_ok, str(gkeys.keys()))
	signal_peers("G_cards")
	wm.request_pick(2)
	await wait(0.6)
	report("G: choosing one gives the gear back upgraded, armor included", not player.gear_away and player.gear_lvl(StringName(gc[2]["mod"])) >= 1 and player.armor >= 30 and gmachine._slots.is_empty(), "armor=%d" % player.armor)
	await _hold_e(1.2)
	report("G: the next gear upgrade costs more", wm.cash == 5000 - GameConfig.GEAR_BASE - (GameConfig.GEAR_BASE + GameConfig.GEAR_STEP), "cash=%d" % wm.cash)
	await wait(5.5)
	wm._offers.erase(1)
	wm._send_offers(1, [])
	await _hold_e(1.2)
	wm.request_pick(0)
	await wait(0.6)
	player.gear_levels = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	player._invuln = 0.0
	player.armor = 0
	# knockback first, without Lead Boots
	player.velocity = Vector3.ZERO
	player.stagger_time = 0.0
	player.srv_launch(Vector3(12, 0, 0), 0.4) # (read straight away: the player's own movement tick soon takes over the velocity)
	var free_speed := player.velocity.length()
	var free_stagger := player.stagger_time
	player.velocity = Vector3.ZERO
	player.stagger_time = 0.0
	_gear(&"anchor", 1)
	player.srv_launch(Vector3(12, 0, 0), 0.4)
	var half_speed := player.velocity.length()
	player.velocity = Vector3.ZERO
	_gear(&"anchor", 2)
	player.srv_launch(Vector3(12, 0, 0), 0.4)
	report("G: Lead Boots take the sting out of knockback (level 3: none at all)", free_speed > 10.0 and free_stagger > 0.3 and half_speed < free_speed * 0.7 and half_speed > 1.0 and player.velocity.length() < 0.5, "free=%.1f level1=%.1f level3=%.1f" % [free_speed, half_speed, player.velocity.length()])
	player.gear_levels = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	await _goto(Vector3(13.3, 0.1, 5.5))
	var t := wm.spawn_at(Vector3(15.0, 0, 5.5), 0, 5000, 0.0)
	await wait(0.4)
	_gear(&"thorns", 2)
	var th0 := t.hp
	player.srv_take_damage(5, t.global_position)
	report("G: Thorns hurt whoever hits you", th0 - t.hp >= 24, "damage=%d" % (th0 - t.hp))
	_gear(&"shock")
	_gear(&"funky")
	t.hp = 5000
	player._invuln = 0.0
	player.srv_take_damage(5, t.global_position + Vector3(0, 0, 50))
	await wait(0.2)
	report("G: Static Cling zaps and Funky Fresh makes nearby zombies dance", t.hp < 5000 and t.state == Zombie.State.DANCE, "hp=%d state=%d dist=%.1f away=%s lvl=%d/%d" % [t.hp, t.state, t.global_position.distance_to(player.global_position), str(player.gear_away), player.gear_lvl(&"shock"), player.gear_lvl(&"funky")])
	_gear(&"springy", 4)
	var up := false
	for i in 8:
		player._invuln = 0.0
		player.srv_take_damage(1, t.global_position)
		await wait(0.15)
		up = up or t.velocity.y > 4.0 or t.is_fallen()
	report("G: Bouncy Castle boings the attacker", up)
	t.global_position = player.global_position + Vector3(1.7, 0, 0) # (the earlier hits threw it around)
	t._fall_left = 0.0
	_gear(&"stink", 3)
	await wait(0.9)
	report("G: Stink Cloud slows zombies near you", t._freeze_mult < 0.8, "mult=%.2f" % t._freeze_mult)
	_gear(&"rage", 2)
	player._invuln = 0.0
	player.srv_take_damage(1, t.global_position)
	report("G: Hot Head boosts your damage after a hit", player.rage_mult() > 1.5, "x%.1f" % player.rage_mult())
	_gear(&"mend", 4)
	player.hp = 50
	await wait(2.4)
	report("G: Slurpee slowly heals you", player.hp >= 54, "hp=%d" % player.hp)
	_gear(&"plate", 2)
	_gear(&"pad", 2)
	report("G: Plating and Padding raise the vest's cap and soak", player.armor_cap() == GameConfig.ARMOR_MAX + 50 and absf(player.absorb_fraction() - 0.7) < 0.01 and player.armor == player.armor_cap())
	_gear(&"ghost", 8)
	player.armor = 0
	player.hp = 100
	var dodged := 0
	for i in 40:
		player._invuln = 0.0
		var before := player.hp
		player.srv_take_damage(1, Vector3.ZERO)
		if player.hp == before:
			dodged += 1
	report("G: Slippery dodges a good share of hits", dodged >= 8, "dodged %d of 40" % dodged)
	t.free()
	player.srv_reset_support()
	player.hp = 100
	signal_peers("G_done")

	# --- E: the run never ends on its own ---
	var c10 := GameConfig.wave_cfg(10)
	var c30 := GameConfig.wave_cfg(30)
	report("E: waves keep growing past the table", int(c30["count"]) > int(c10["count"]) and int(c30["hp"]) > int(c10["hp"]) and int(c30["max_alive"]) <= 30, "count %d -> %d" % [c10["count"], c30["count"]])
	report("E: crawlers join from wave 4", int(GameConfig.wave_cfg(3)["crawlers"]) == 0 and int(GameConfig.wave_cfg(4)["crawlers"]) >= 1)
	wm.wave = 10
	wm.state = WaveManager.State.ACTIVE
	wm.to_spawn = 0
	wm._end_wave()
	report("E: finishing wave 10 is just another break", wm.state == WaveManager.State.BREAK and wm.my_offers.is_empty())
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

	# --- H: the team bars, then spectating ---
	await wait(0.6)
	report("H: the HUD shows a health bar for every player", main.hud._team_rows.size() == 2, "rows=%d" % main.hud._team_rows.size())
	signal_peers("H_start")
	client._srv_eliminate()
	await wait(1.0)
	signal_peers("H_out")
	await wait_signal("H_checked", 20.0)
	client.srv_restore(client.global_position, false)
	signal_peers("H_back")
	await wait_signal("M9_done", 20.0)
	finish()
