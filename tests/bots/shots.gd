extends BotScenario
## Visual check. Needs a real window (not --headless). Saves PNGs into --shotdir=DIR.


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d size=%s" % [path, img.save_png(path), img.get_size()])


func run() -> void:
	var wm := wave_manager()
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	await wait(2.5)
	await _snap("01_spawn_view")

	# turn to the front door (barricade, sign, barrel)
	player.input.aim_yaw = PI
	await wait(0.6)
	await _snap("02_front_door")

	# a few zombies in the room, then fire the pistol at them
	player.input.aim_yaw = 0.0
	await wait(0.3)
	for i in 4:
		wm.spawn_at(Vector3(-3.0 + i * 2.0, 0.0, -3.0 + (i % 2) * 1.5), 0, 100000, 0.0)
	await wait(1.0)
	await _snap("03_zombies_ahead")
	var tick := 0
	for i in 12:
		shoot_nearest(tick, 3)
		tick += 1
		await get_tree().physics_frame
	await _snap("04_firing")
	player.input.fire_held = false

	# hurt the player and go down to see the overlays
	player.srv_take_damage(60)
	await wait(0.4)
	await _snap("05_hurt")
	player.srv_take_damage(60)
	await wait(1.0)
	await _snap("06_downed")
	player.srv_restore(player.global_position, false)
	for e in enemies():
		e.srv_hit(100000, Vector3.ZERO, 0.0, null)
	await wait(1.0)

	# pause menu and end-of-run screen
	var main := get_tree().root.get_node("Main")
	main._set_paused(true)
	await wait(0.4)
	await _snap("06b_pause_menu")
	main._set_paused(false)
	wm.wave = 5
	wm.state = WaveManager.State.VICTORY # the real trigger: Main shows the end screen a moment after the run is over
	await wait(3.2)
	await _snap("06c_end_screen")
	wm.wave = 0
	wm.state = WaveManager.State.BREAK
	await wait(0.5)

	# overview from outside, roof removed so the layout is visible
	var roof := level.get_node_or_null("Decor/Roof") as Node3D
	if roof != null:
		roof.visible = false
	var cam := Camera3D.new()
	cam.fov = 60.0
	get_tree().root.add_child(cam)
	cam.global_position = Vector3(0, 26, 24)
	cam.look_at(Vector3(0, 0, 1))
	cam.make_current()
	for p in Net.all_players():
		p.puppet.visible = true
	await wait(0.6)
	await _snap("07_overview")
	cam.global_position = Vector3(14, 3.5, 20)
	cam.look_at(Vector3(-2, 1.5, 6))
	await wait(0.3)
	await _snap("08_front_exterior")
	finish()
