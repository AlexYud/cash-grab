extends BotScenario
## Whole-run soak bot, used by every player in the soak tests. Plays like a (slightly lazy) human team-mate:
## shoots the nearest zombie, revives downed friends, repairs boards between fights, picks a reward card and presses
## ready between waves. Rounds are endless, so the host ends the run once SOAK_WAVES waves are cleared.

const REPORT_EVERY := 3.0
const SOAK_WAVES := 8

const STALL_LIMIT := 150.0 # game seconds without a spawn or a kill

var _progress := ""
var _progress_t := 0.0
var _tick := 0
var _next_report := REPORT_EVERY
var _t := 0.0
var _break_t := 0.0
var _picked := false
var _long_gun := 0 ## the ranged weapon this wave (pistol, assault rifle or sniper: whatever the upgrades left us)
var _dealt := false ## host: this break's upgrade cards were handed out


func run() -> void:
	var is_host := multiplayer.is_server()
	if is_host:
		var wm := wave_manager()
		wm.hold = false
	while not h.signals_seen.has("SOAK_DONE") and is_instance_valid(player):
		_tick += 1
		_t += get_physics_process_delta_time()
		_between_waves()
		_act()
		if is_host:
			_host_watch()
		await get_tree().physics_frame
	if not is_instance_valid(player):
		finish() # the host went away first (time limit): nothing left to report
		return
	stop()
	if is_host:
		await wait(2.0)
	report("%s finished without disconnecting" % player.player_name, Net.phase == Net.Phase.PLAYING)
	finish()


## The real UI path without the clicks: take an upgrade card if one is waiting, then press ready, like a player would.
func _between_waves() -> void:
	var wm := wave_manager()
	if wm.state != WaveManager.State.BREAK:
		_break_t = 0.0
		_picked = false
		return
	_break_t += get_physics_process_delta_time()
	if not _picked and not wm.my_offers.is_empty() and _break_t > 1.0:
		_picked = true
		wm.request_pick(randi() % wm.my_offers.size())
		_long_gun = [0, 6, 7].pick_random() # rotate the ranged weapon so the cards' guns (and their buffs) get used
	if _break_t > 3.0 and not wm.is_ready(player.peer_id):
		wm.press_ready(true)


func _act() -> void:
	var inp := player.input
	inp.interact_held = false
	if player.status != Player.Status.ALIVE:
		inp.move = Vector2.ZERO
		shoot_nearest(_tick, 5) # downed players can still fire the pistol
		return
	var z := nearest_enemy()
	var zd := 999.0
	if z != null:
		zd = z.global_position.distance_to(player.global_position)
	# weapon choice: shotgun up close, pistol at range
	var owned := player.weapons.owned
	var want := _long_gun if (owned[_long_gun] and zd >= 6.0) else 0
	if zd < 6.0:
		want = 1 if owned[1] else 0
	if zd < 2.3 and owned[9]:
		want = 9 # the katana when they get close
	if want != player.weapons.current and player.weapons.is_reloading() == false:
		inp.weapon_slot = want
	# revive duty
	for p in Net.all_players():
		if p != player and p.status == Player.Status.DOWNED and (z == null or zd > 4.0):
			var near := steer_to(p.global_position, 1.6)
			face_point(p.global_position)
			if near:
				inp.interact_held = true
			return
	if z != null:
		shoot_nearest(_tick, 5)
		inp.move = Vector2.ZERO
		return
	inp.fire_held = false
	# repair duty between fights
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var best: Barricade = null
	var best_d := INF
	for b in level.barricades:
		if b.boards < Barricade.MAX_BOARDS:
			var d := b.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = b
	if best != null:
		var spot := best.global_position - best.outward_dir() * 1.7
		face_point(best.global_position)
		if steer_to(spot, 0.5):
			inp.interact_held = true
	else:
		inp.move = Vector2.ZERO


func _host_watch() -> void:
	var wm := wave_manager()
	if wm.state == WaveManager.State.BREAK and wm.wave >= 1 and not _dealt: # stand-in for the upgrader machines: everyone gets cash and a hand of upgrade cards
		_dealt = true
		wm.srv_add_cash(4000)
		for p in Net.all_players():
			wm.srv_open_collect(p, wm.wave % 2 == 0, p.weapons.current, -1) # (no machine: nothing to give back)
	elif wm.state != WaveManager.State.BREAK:
		_dealt = false
	# the run opens the annex from wave 3 and the hall from wave 5, so their windows (and the crawler vents) get used
	for stage in [1, 2]:
		var annex := Annex.find_stage(get_tree(), stage)
		if annex != null and wm.wave >= (3 if stage == 1 else 5) and not annex.lever1 and not annex.is_open:
			wm.srv_add_cash(2 * annex.lever_cost())
			annex.srv_pull(0)
			annex.srv_pull(1)
	if _t >= _next_report:
		_next_report += REPORT_EVERY
		var states := []
		var in_melee := 0
		for p in Net.all_players():
			states.append("%s:hp%d/st%d/k%d" % [p.player_name, p.hp, p.status, p.kills])
			for z in enemies():
				if z.global_position.distance_to(p.global_position) < 2.2:
					in_melee += 1
		var level := get_tree().get_first_node_in_group("level") as SaloonLevel
		var boards := []
		for b in level.barricades:
			boards.append(b.boards)
		print("[SOAK] t=%ds wave=%d state=%d alive=%d to_spawn=%d melee=%d boards=%s players=%s" % [_t, wm.wave, wm.state, wm.enemies_alive, wm.to_spawn, in_melee, boards, ", ".join(states)])
		if _t - _progress_t > 60.0: # no kill or spawn for a minute: say what each player is looking at
			for p in Net.all_players():
				var best: Zombie = null
				var best_d := INF
				for z in enemies():
					var d := z.global_position.distance_squared_to(p.global_position)
					if d < best_d:
						best_d = d
						best = z
				if best == null:
					continue
				var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0), best.global_position + Vector3(0, 1.1, 0), GameConfig.MASK_HITSCAN, [p.get_rid()])
				var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
				print("[SOAK] stuck? %s st=%d w=%d ammo=%d reload=%s nearest=%s kind=%d state=%d dist=%.1f hp=%d pos=%s ray=%s" % [p.player_name, p.status, p.weapons.current, p.weapons.ammo[p.weapons.current], str(p.weapons.is_reloading()), best.name, best.kind, best.state, sqrt(best_d), best.hp, str(best.global_position), str(hit["collider"].get_path()) if not hit.is_empty() else "clear"])
		if wm.enemies_alive > 0 and wm.enemies_alive <= 2 and wm.to_spawn == 0:
			for z in enemies(): # a lone survivor that never dies: say where it is and what it is doing
				print("[SOAK] straggler %s kind=%d state=%d hp=%d pos=%s entrance=%d floor=%s" % [z.name, z.kind, z.state, z.hp, str(z.global_position), z.entrance_idx, str(z.is_on_floor())])
				for p in Net.all_players(): # what would a shot from each player hit?
					var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, GameConfig.EYE_HEIGHT, 0), z.global_position + Vector3(0, 1.0, 0), GameConfig.MASK_HITSCAN, [p.get_rid()])
					var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
					print("[SOAK]   %s at %s dist=%.1f shot hits %s" % [p.player_name, str(p.global_position), p.global_position.distance_to(z.global_position), str(hit["collider"].get_path()) if not hit.is_empty() else "nothing"])
	var progress := "%d/%d/%d" % [wm.wave, wm.enemies_alive, wm.to_spawn]
	if progress != _progress:
		_progress = progress
		_progress_t = _t
	elif wm.state == WaveManager.State.ACTIVE and _t - _progress_t > STALL_LIMIT: # nobody died and nothing spawned for ages: a stuck zombie
		report("soak: waves keep moving", false, "stalled on wave %d with %d zombies alive since t=%ds" % [wm.wave, wm.enemies_alive, _progress_t])
		signal_peers("SOAK_DONE")
	if wm.wave >= SOAK_WAVES and wm.state == WaveManager.State.BREAK:
		report("soak: survived %d waves" % (wm.wave), true, "t=%ds" % _t)
		signal_peers("SOAK_DONE")
	elif wm.state == WaveManager.State.GAME_OVER:
		report("soak: survived all waves", false, "game over on wave %d at t=%ds" % [wm.wave, _t])
		signal_peers("SOAK_DONE")
