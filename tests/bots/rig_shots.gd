extends BotScenario
## Visual check of the zombie rig. Needs a real window (not --headless). Saves PNGs into --shotdir=DIR.
## Lines up one zombie of every kind in a row per pose, then trips them to look at the ragdolls.

const KINDS := [0, 1, 2, 3, 4]


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d" % [path, img.save_png(path)])


func _row(wm: WaveManager, z0: float, state: int, speed: float) -> Array:
	var zs: Array = []
	for i in KINDS.size():
		var z := wm.spawn_at(Vector3(-4.0 + i * 2.0, 0.0, z0), 0, 100000, 0.0, KINDS[i])
		z.set_physics_process(false)
		z.rotation.y = PI # face the camera at +z
		z.sync_yaw = PI
		z.sync_speed = speed
		z.state = state
		zs.append(z)
	return zs


func run() -> void:
	var wm := wave_manager()
	await wait(2.0)
	player.global_position = Vector3(30, 5, 30) # out of the way
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	var roof := level.get_node_or_null("Decor/Roof") as Node3D
	if roof != null:
		roof.visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	get_tree().root.add_child(cam)
	cam.make_current()

	var rows := {
		"walk": [Zombie.State.CHASE, 2.4],
		"idle": [Zombie.State.IDLE, 0.0],
		"attack": [Zombie.State.ATTACK, 0.0],
		"stagger": [Zombie.State.STAGGER, 0.0],
		"leap": [Zombie.State.LEAP, 0.0],
		"latched": [Zombie.State.LATCHED, 0.0],
		"dance": [Zombie.State.DANCE, 0.0],
		"charge": [Zombie.State.CHARGE, 6.0],
	}
	var all: Array = []
	var z0 := -2.0
	for key in rows:
		var zs := _row(wm, z0, rows[key][0], rows[key][1])
		all.append(zs)
		z0 += 0.0
		cam.global_position = Vector3(0, 1.5, z0 + 6.5)
		cam.look_at(Vector3(0, 0.9, z0))
		await wait(0.7)
		if key == "attack":
			for z in zs:
				z.fx_attack()
			await wait(0.18)
		await _snap("pose_" + key)
		for z in zs:
			z.queue_free()
		await wait(0.2)

	# ragdoll: trip the whole row, then watch it fall and get up
	var zs := _row(wm, z0, Zombie.State.CHASE, 2.4)
	await wait(0.5)
	for z in zs:
		z.set_physics_process(true) # real AI again
		z.srv_trip(Vector3(0, 0, -3.0))
	for t in 4:
		await wait(0.35)
		await _snap("fall_%d" % t)
	await wait(2.0)
	await _snap("getup_a")
	await wait(0.4)
	await _snap("getup_b")
	finish()
