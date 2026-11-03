extends BotScenario
## M8 host side: rigged zombies. Feet on the ground, poses that differ per state, going limp when tripped / blown
## up / killed, the tether, getting back up, a limp zombie bowling over a neighbour, corpses that keep the pose.

const KINDS := [0, 1, 2, 3, 4]


func _world(z: Zombie, bone: String) -> Vector3:
	var sk := z.puppet.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _foot_low(z: Zombie) -> float:
	return minf(_world(z, "mixamorig_LeftFoot").y, _world(z, "mixamorig_RightFoot").y)


func _fwd(z: Zombie) -> Vector3:
	return -z.global_transform.basis.z


func _spawn(pos: Vector3, kind: int = 0, speed: float = 0.0) -> Zombie:
	return wave_manager().spawn_at(pos, 0, 100000, speed, kind)


func run() -> void:
	var wm := wave_manager()
	await wait(2.0)
	signal_peers("hello")

	# --- A: every kind has a rig, scaled to its kind, standing on the floor ---
	var rig_ok := true
	var planted := true
	var scales_ok := true
	var detail := ""
	var row: Array = []
	for i in KINDS.size():
		row.append(_spawn(Vector3(-8.0 + i * 1.6, 0, -6.0), KINDS[i]))
	await wait(1.2)
	for z in row:
		var st := Zombie.style(z.kind)
		rig_ok = rig_ok and z.puppet.skeleton != null and z.puppet.skeleton.get_bone_count() == 25
		scales_ok = scales_ok and is_equal_approx(z.puppet.scale.x, st["scale"])
		var low := _foot_low(z)
		var expect: float = 0.085 * ZombieRig.MODEL_SCALE * float(st["scale"])
		if absf(low - expect) > 0.09:
			planted = false
			detail += " kind%d:%.2f(want %.2f)" % [z.kind, low, expect]
	report("A: every kind builds a 25-bone rig", rig_ok)
	report("A: ...scaled to its kind", scales_ok)
	report("A: ...with the feet on the floor", planted, detail)
	for z in row:
		z.queue_free()
	await wait(0.3)

	# --- B: poses follow the state ---
	var zb := _spawn(Vector3(-4.0, 0, -6.0))
	zb.set_physics_process(false)
	await wait(0.5)
	var scale: float = zb.puppet.scale.x
	zb.state = Zombie.State.IDLE
	await wait(0.4)
	var idle_reach := (_world(zb, "mixamorig_LeftHand") - _world(zb, "mixamorig_Spine2")).dot(_fwd(zb))
	zb.state = Zombie.State.LATCHED
	await wait(0.5)
	var latch_reach := (_world(zb, "mixamorig_LeftHand") - _world(zb, "mixamorig_Spine2")).dot(_fwd(zb))
	report("B: a clinging zombie holds its arms out in front", latch_reach > 0.25 * scale, "reach=%.2f" % latch_reach)
	zb.state = Zombie.State.CHARGE
	await wait(0.5)
	var charge_reach := (_world(zb, "mixamorig_LeftHand") - _world(zb, "mixamorig_Spine2")).dot(_fwd(zb))
	report("B: a charging zombie swings its arms back instead", charge_reach < idle_reach - 0.3, "idle=%.2f charge=%.2f" % [idle_reach, charge_reach])
	zb.state = Zombie.State.DANCE
	await wait(0.4)
	var dance_h := _world(zb, "mixamorig_LeftHand").y - _world(zb, "mixamorig_Spine2").y
	report("B: dancing throws the hands above the chest", dance_h > 0.15 * scale, "h=%.2f" % dance_h)
	zb.state = Zombie.State.IDLE
	await wait(0.3)
	zb.fx_attack()
	await wait(0.12)
	var swing_h := _world(zb, "mixamorig_LeftHand").y - _world(zb, "mixamorig_Spine2").y
	report("B: a swing starts with the arms hauled up", swing_h > 0.3 * scale, "h=%.2f" % swing_h)
	await wait(0.5)
	zb.state = Zombie.State.CHASE
	zb.sync_speed = 2.4
	var lows: Array[float] = []
	for i in 40:
		lows.append(_world(zb, "mixamorig_LeftFoot").y)
		await get_tree().physics_frame
	var lo: float = lows.min()
	var hi: float = lows.max()
	report("B: walking swings the feet up and down", hi - lo > 0.08 * scale, "range=%.2f" % (hi - lo))
	zb.queue_free()
	await wait(0.3)

	# --- C: a trip goes limp, stays near its hit shape, and gets back up ---
	signal_peers("C_start")
	var zc := _spawn(Vector3(-2.0, 0, -6.0))
	await wait(0.5)
	zc.srv_trip(Vector3(0, 0, -2.0))
	var went := await wait_until(func() -> bool: return zc.puppet.is_ragdolling(), 0.5)
	report("C: tripping hands the skeleton to physics", went and zc.state == Zombie.State.FALLEN)
	await wait(1.2)
	var hips := zc.puppet.hips_position()
	report("C: the limp body lies on the floor", hips.y < 0.5 * scale, "hips_y=%.2f" % hips.y)
	var away := Vector2(hips.x - zc.global_position.x, hips.z - zc.global_position.z).length()
	report("C: ...close to its gameplay body (tether)", away < 1.5, "away=%.2f" % away)
	var shape_ok: bool = (not zc.fallen_shape.disabled) and zc.body_shape.disabled
	report("C: while down the low hit shape is used", shape_ok)
	var up := await wait_until(func() -> bool: return zc.state != Zombie.State.FALLEN, 4.0)
	report("C: it gets up again", up and not zc.puppet.is_ragdolling())
	await wait(1.4)
	var head_y := _world(zc, "mixamorig_Head").y
	report("C: ...and is standing after the blend", head_y > 1.2 * scale, "head_y=%.2f" % head_y)
	signal_peers("C_done")
	await wait(0.4)
	zc.queue_free()

	# --- D: an explosion flings the limp body ---
	signal_peers("D_start")
	var zd := _spawn(Vector3(-6.0, 0, -3.0))
	await wait(0.5)
	var start := zd.puppet.hips_position()
	zd.srv_explode(5, Vector3(8.0, 7.0, 0.0), player)
	var best_y := 0.0
	var best_d := 0.0
	for i in 70:
		var hp := zd.puppet.hips_position()
		best_y = maxf(best_y, hp.y)
		best_d = maxf(best_d, hp.distance_to(start))
		await get_tree().physics_frame
	report("D: a blast throws the ragdoll into the air", best_y > 0.9, "peak_y=%.2f" % best_y)
	report("D: ...and across the room", best_d > 1.5, "travel=%.2f" % best_d)
	signal_peers("D_done")
	await wait(0.5)
	zd.queue_free()
	await wait(0.3)

	# --- E: a limp zombie sliding into a neighbour knocks it down too ---
	var za := _spawn(Vector3(3.0, 0, -6.0))
	var zn := _spawn(Vector3(4.0, 0, -6.0))
	await wait(0.6)
	za.srv_trip(Vector3(9.0, 0, 0.0))
	var domino := await wait_until(func() -> bool: return zn.is_fallen(), 1.5)
	report("E: a flying ragdoll bowls over the zombie in its way", domino)
	await wait(0.2)
	report("E: ...and the neighbour goes limp too", zn.puppet.is_ragdolling())
	await wait(4.0)
	za.queue_free()
	zn.queue_free()
	await wait(0.3)

	# --- F: killed while limp: the corpse carries on from that pose ---
	var zf := _spawn(Vector3(0.0, 0, -6.0))
	await wait(0.5)
	zf.srv_trip(Vector3(0, 0, -3.0))
	await wait(0.7)
	var before := zf.puppet.hips_position()
	var kills := player.kills
	zf.srv_hit(100000, Vector3(1.0, 0, 0), 0.0, player)
	await wait(0.15)
	report("F: the kill is credited", player.kills == kills + 1)
	var corpse: ZombieRig = null
	for r in Fx._ragdolls:
		if is_instance_valid(r) and r is ZombieRig:
			corpse = r
	report("F: a corpse ragdoll exists", corpse != null and corpse.is_ragdolling())
	if corpse != null:
		var ch := corpse.hips_position()
		report("F: ...at the pose where the zombie fell (not reset upright)", ch.distance_to(before) < 1.0 and ch.y < 0.5, "moved=%.2f y=%.2f" % [ch.distance_to(before), ch.y])
	signal_peers("F_done")
	await wait(1.0)

	# --- G: the cap on corpses still holds with the new bodies ---
	var many: Array = []
	for i in 14:
		many.append(_spawn(Vector3(-5.0 + (i % 7) * 1.5, 0, -8.5 - (i / 7) * 1.5)))
	await wait(0.4)
	for z in many:
		z.srv_hit(100000, Vector3(1.0, 0, 0.0), 0.0, player)
	await wait(1.0)
	var n := 0
	for r in Fx._ragdolls:
		if is_instance_valid(r):
			n += 1
	report("G: corpse count is capped", n > 0 and n <= GameConfig.MAX_RAGDOLLS, "n=%d cap=%d" % [n, GameConfig.MAX_RAGDOLLS])
	await wait(1.0)
	finish()
