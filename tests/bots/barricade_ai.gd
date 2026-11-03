extends BotScenario
## Single-player: crowds of zombies at every window. They must break boards only where a window with boards
## actually is, walk in once it is open, and never stand stuck against a wall or a boarded window.
## Phase 2 puts zombies outside the WRONG building side (as if thrown or blasted there): they still have to find in.

const PER_ENTRANCE := 6
const STUCK_SECONDS := 3.5

var _wall_swings := PackedStringArray()
var _stuck := PackedStringArray()


func _indoors(p: Vector3) -> bool:
	if p.x < 11.2:
		return p.x > -10.8 and absf(p.z) < 8.9
	return p.x < 60.6 and absf(p.z) < 9.9


func _indoor_count(zs: Array[Zombie]) -> int:
	var n := 0
	for z in zs:
		if is_instance_valid(z) and not z.is_dead() and _indoors(z.global_position):
			n += 1
	return n


func _watch(zs: Array[Zombie], level: SaloonLevel, seconds: float, tag: String) -> void:
	var last := {}
	var still := {}
	var swinging := {}
	var t := 0.0
	while t < seconds:
		await wait(0.25)
		t += 0.25
		for z in zs:
			if not is_instance_valid(z) or z.is_dead():
				continue
			var key := z.get_instance_id()
			var bar := level.barricades[z.entrance_idx]
			var tgt := z._board_target
			var bad_swing := z._swing == Zombie.Swing.BOARD and (tgt == null or tgt.boards <= 0 or absf(tgt.lateral(z.global_position)) > 1.9)
			if bad_swing:
				swinging[key] = int(swinging.get(key, 0)) + 1
				if int(swinging[key]) == 2: # one tick of an already started swing is fine, two in a row is not
					_wall_swings.append("%s e%d boards=%d lat=%.2f dist=%.2f" % [tag, z.entrance_idx, bar.boards, bar.lateral(z.global_position), bar.distance_outside(z.global_position)])
			else:
				swinging[key] = 0
			var moved := 99.0
			if last.has(key):
				moved = (z.global_position - last[key]).length()
			last[key] = z.global_position
			var busy := z.is_fallen() or z._swing_left > 0.0 or z._windup > 0.0 or z.state in [Zombie.State.ATTACK, Zombie.State.LATCHED, Zombie.State.STAGGER, Zombie.State.FALLEN, Zombie.State.BARRICADE]
			var near_target := false
			for p in Net.all_players():
				if p.global_position.distance_to(z.global_position) < 2.2:
					near_target = true
			if moved < 0.04 and not busy and not near_target:
				still[key] = float(still.get(key, 0.0)) + 0.25
				if float(still[key]) >= STUCK_SECONDS and float(still[key]) < STUCK_SECONDS + 0.3:
					var wall := z._wall_ahead()
					_stuck.append("%s e%d kind=%d state=%d boards=%d lat=%.2f dist=%.2f pos=%s stall=%.2f walk=%s entered=%s unstick=%.1f wall=%s" % [tag, z.entrance_idx, z.kind, z.state, bar.boards, bar.lateral(z.global_position), bar.distance_outside(z.global_position), str(z.global_position), z._stall, str(z._walk_dir), str(z._entered), z._unstick_left, str(wall.name) if wall != null else "none"])
			else:
				still[key] = 0.0


func _crowd(wm: WaveManager, level: SaloonLevel, from_side: Callable) -> Array[Zombie]:
	var zs: Array[Zombie] = []
	for e in level.barricades.size():
		var bar := level.barricades[e]
		var src: int = from_side.call(e)
		var base := level.enemy_spawn_point(src)
		var sbar := level.barricades[src]
		for i in PER_ENTRANCE:
			var lateral := sbar.global_basis.x.normalized() * randf_range(-2.0, 2.0)
			var back := sbar.outward_dir() * randf_range(0.0, 3.0)
			var kind := Zombie.Kind.NORMAL
			if i == 4:
				kind = Zombie.Kind.HUGGER
			elif i == 5 and e % 3 == 0:
				kind = Zombie.Kind.BRUTE
			zs.append(wm.spawn_at(base + lateral + back, e, 100000, randf_range(2.0, 3.4), kind))
	return zs


func _clear(zs: Array[Zombie]) -> void:
	for z in zs:
		if is_instance_valid(z) and not z.is_dead():
			z.srv_hit(1000000, Vector3.ZERO, 0.0, null)


func run() -> void:
	var wm := wave_manager()
	await wait(1.5)
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	Net.debug_god = true
	for stage in [1, 2]:
		var annex := Annex.find_stage(get_tree(), stage)
		if annex != null and not annex.is_open:
			wm.srv_add_cash(2 * annex.lever_cost())
			annex.srv_pull(0)
			annex.srv_pull(1)
	await wait(2.5)

	var zs := _crowd(wm, level, func(e: int) -> int: return e)
	await _watch(zs, level, 70.0, "own")
	var in1 := _indoor_count(zs)
	report("zombies got in through their own windows", in1 > zs.size() * 9 / 10, "%d of %d indoors" % [in1, zs.size()])
	_clear(zs)
	await wait(1.5)
	for b in level.barricades:
		b.srv_reset()
	await wait(0.5)

	var zs2 := _crowd(wm, level, func(e: int) -> int: return (e + 4) % 9) # assigned to one window, standing at another
	await _watch(zs2, level, 90.0, "wrong")
	var in2 := _indoor_count(zs2)
	for z in zs2:
		if is_instance_valid(z) and not z.is_dead() and not _indoors(z.global_position):
			var b := level.barricades[z.entrance_idx]
			print("[OUTSIDE] e%d kind=%d state=%d boards=%d entered=%s stall=%.1f pos=%s lat=%.2f dist=%.2f speed=%.1f" % [z.entrance_idx, z.kind, z.state, b.boards, str(z._entered), z._stall, str(z.global_position), b.lateral(z.global_position), b.distance_outside(z.global_position), z.move_speed])
	report("zombies dropped at the wrong side still find a way in", in2 > zs2.size() * 9 / 10, "%d of %d indoors" % [in2, zs2.size()])

	for s in _wall_swings:
		print("[WALLSWING] ", s)
	for s in _stuck:
		print("[STUCK] ", s)
	report("no zombie keeps swinging at a wall or at a window with no boards", _wall_swings.is_empty(), "%d cases" % _wall_swings.size())
	report("no zombie stands stuck against a wall or a boarded window", _stuck.is_empty(), "%d cases" % _stuck.size())
	finish()
