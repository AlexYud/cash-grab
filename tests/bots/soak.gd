extends BotScenario
## Whole-run soak bot, used by every player in the soak tests. Plays like a (slightly lazy) human team-mate:
## shoots the nearest zombie, revives downed friends, repairs boards between fights. The host reports the outcome.

const REPORT_EVERY := 3.0

var _tick := 0
var _next_report := REPORT_EVERY
var _t := 0.0


func run() -> void:
	var is_host := multiplayer.is_server()
	if is_host:
		var wm := wave_manager()
		wm.hold = false
		wm.break_left = 2.0
	while not h.signals_seen.has("SOAK_DONE") and is_instance_valid(player):
		_tick += 1
		_t += get_physics_process_delta_time()
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
	var want := 1 if zd < 6.0 else 0
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
	var annex := get_tree().get_first_node_in_group("annex") as Annex
	if annex != null and wm.wave >= 3 and not annex.lever1 and not annex.is_open:
		wm.srv_add_cash(2 * GameConfig.LEVER_COST) # the run opens the annex from wave 3 on, so the soak covers its windows too
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
	if wm.state == WaveManager.State.VICTORY:
		report("soak: survived all %d waves" % wm.total_waves, true, "t=%ds" % _t)
		signal_peers("SOAK_DONE")
	elif wm.state == WaveManager.State.GAME_OVER:
		report("soak: survived all waves", false, "game over on wave %d at t=%ds" % [wm.wave, _t])
		signal_peers("SOAK_DONE")
