extends BotScenario
## M3b host side: shove ragdoll for observers, capped ragdolls, the barrel explosion, game over and restart.


func _valid_ragdolls() -> int:
	var n := 0
	for r in Fx._ragdolls:
		if is_instance_valid(r):
			n += 1
	return n


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	await wait(2.0)

	# --- P: the client shoves the host; the client checks the ragdoll swap. Host only waits. ---
	signal_peers("P_start")
	await wait_signal("P_done", 40.0)
	await wait(1.0)

	# --- R: fifteen deaths at once; only MAX_RAGDOLLS bodies may exist ---
	var zs: Array = []
	for i in 15:
		zs.append(wm.spawn_at(Vector3(-4.0 + (i % 5) * 2.0, 0.0, -3.0 - (i / 5) * 1.5), 0, 10, 0.0))
	await wait(0.4)
	for z in zs:
		z.srv_hit(100, Vector3(2, 0, 0), 0.0, player)
	await wait(1.2)
	var n := _valid_ragdolls()
	report("R: ragdoll count is capped on the host", n > 0 and n <= GameConfig.MAX_RAGDOLLS, "n=%d cap=%d" % [n, GameConfig.MAX_RAGDOLLS])
	report("R: all fifteen kills credited", player.kills == 15, "kills=%d" % player.kills)
	signal_peers("R_done")
	await wait(1.0)

	# --- X: the barrel ---
	var barrel := level.barrels[0]
	var za := wm.spawn_at(barrel.global_position + Vector3(-1.2, 0, -0.8), 1, 60, 0.0) # north of the barrel, away from the shooter
	var zb := wm.spawn_at(barrel.global_position + Vector3(-0.3, 0, -1.5), 1, 60, 0.0)
	await wait(0.5)
	signal_peers("X_start")
	var boom := await wait_until(func() -> bool: return not barrel.alive, 25.0)
	report("X: shooting the barrel detonates it", boom)
	await wait(0.6)
	report("X: zombies next to it were killed", (not is_instance_valid(za) or za.is_dead()) and (not is_instance_valid(zb) or zb.is_dead()))
	report("X: the shooter was blown back (until the south wall stopped it)", client.global_position.distance_to(Vector3(-8.0, 0, 6.0)) > 1.0, "d=%.1f" % client.global_position.distance_to(Vector3(-8.0, 0, 6.0)))
	report("X: explosion damage to players is limited", client.hp >= GameConfig.PLAYER_MAX_HP - GameConfig.EXPLOSION_PLAYER_DAMAGE, "hp=%d" % client.hp)
	signal_peers("X_done")
	await wait(2.0)

	# --- O: everyone down = game over; restart brings the run back ---
	wm.hold = false
	wm.wave = 2
	wm.break_left = 500.0
	wm.state = WaveManager.State.BREAK
	await wait(0.3)
	for p in Net.all_players():
		p.srv_take_damage(999)
	var over := await wait_until(func() -> bool: return wm.state == WaveManager.State.GAME_OVER, 4.0)
	report("O: everyone downed ends the run", over)
	signal_peers("O_over")
	await wait(2.0)
	wm.restart_run()
	await wait(1.0)
	var again := wm.state == WaveManager.State.BREAK and wm.wave == 0
	for p in Net.all_players():
		again = again and p.status == Player.Status.ALIVE and p.hp == GameConfig.PLAYER_MAX_HP
	report("O: restart resets the wave and revives everyone", again, "state=%d wave=%d" % [wm.state, wm.wave])
	signal_peers("O_done")
	await wait_signal("M3B_done", 15.0)
	finish()
