extends BotScenario
## Visual check of this stage's additions. Needs a real window (not --headless). Saves PNGs into --shotdir=DIR.
## Run with --all-weapons --hold-waves.


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d" % [path, img.save_png(path)])


func run() -> void:
	var wm := wave_manager()
	var main := get_tree().root.get_node("Main")
	await wait(2.0)

	# first-person models of the new weapons
	for idx in [6, 7, 8, 9, 10]:
		player.input.weapon_slot = idx
		await wait(1.0)
		await _snap("weapon_%d" % idx)
	player.input.weapon_slot = 0
	await wait(0.6)

	# the reward cards (and the team list top-left)
	wm.wave = 3
	wm.state = WaveManager.State.ACTIVE
	wm._end_wave()
	await wait(1.2)
	await _snap("cards")
	wm.request_pick(0)
	await wait(0.8)
	await _snap("after_pick")

	# a crawler on the ceiling, seen from below
	player._apply_teleport(Vector3(0.0, 0.1, 3.0))
	var cr := wm.spawn_at(Vector3(-10.8, 1.2, 3.0), -1, 4000, 0.0, Zombie.Kind.CRAWLER, PI / 2.0)
	await wait(3.5)
	player.input.aim_yaw = PI / 2.0
	player.input.aim_pitch = 0.45
	await wait(0.5)
	await _snap("crawler_ceiling")
	cr.free()

	# the hall from above: both gates open
	for a in get_tree().get_nodes_in_group("annex"):
		(a as Annex).is_open = true
	var level := get_tree().get_first_node_in_group("level") as SaloonLevel
	for n in ["Roof", "AnnexRoof", "HallRoof"]:
		var r := level.get_node_or_null("Decor/" + n) as Node3D
		if r != null:
			r.visible = false
	var cam := Camera3D.new()
	cam.fov = 60.0
	get_tree().root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(44.0, 24.0, 20.0)
	cam.look_at(Vector3(44.0, 0.0, 0.0))
	await wait(0.8)
	await _snap("hall_overview")
	cam.global_position = Vector3(38.0, 2.2, 0.0)
	cam.look_at(Vector3(56.0, 1.0, -3.0))
	await wait(0.5)
	await _snap("hall_inside")
	finish()
