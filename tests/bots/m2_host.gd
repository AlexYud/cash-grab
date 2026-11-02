extends BotScenario
## M2 host side: four tough zombies chew through the front barricade, walk in and bite; then the client rebuilds it.


func _any_inside(zs: Array, bar: Barricade) -> bool:
	for z in zs:
		if is_instance_valid(z) and bar.is_inside(z.global_position):
			return true
	return false


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: client's player exists", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	await wait(1.5)
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var bar := level.barricades[0]
	report("barricade starts fully boarded", bar.boards == Barricade.MAX_BOARDS)

	var zs: Array = []
	for i in 4:
		zs.append(wm.spawn_at(Vector3(-1.5 + i, 0, 13.5), 0, 100000, 2.4))
	signal_peers("S1_start")
	var broke := await wait_until(func() -> bool: return bar.boards == 0, 60.0)
	report("zombies broke the barricade (host)", broke, "boards=%d" % bar.boards)
	var entered := await wait_until(func() -> bool: return _any_inside(zs, bar), 20.0)
	report("zombies walked through the breach", entered)
	var hurt := await wait_until(func() -> bool: return player.hp < GameConfig.PLAYER_MAX_HP or client.hp < GameConfig.PLAYER_MAX_HP, 20.0)
	report("zombies that got in attack the players", hurt)

	for z in enemies():
		z.srv_hit(100000, Vector3.ZERO, 0.0, null)
	await wait(1.0)
	for p in Net.all_players():
		p.srv_restore(p.global_position, false)
	signal_peers("S1_done")

	await wait_signal("S2_done", 60.0)
	await wait(0.6)
	report("repair rebuilt boards (host's authoritative count)", bar.boards >= 4, "boards=%d" % bar.boards)
	signal_peers("M2_done")
	await wait(0.5)
	finish()
