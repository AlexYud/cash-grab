extends BotScenario
## Visual check of the melee swings: several frames of each weapon's swing. Needs a real window.
## Saves PNGs into --shotdir=DIR. Run with --hold-waves.


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d" % [path, img.save_png(path)])


func _swing(weapon: int, label: String, steps: int, gap: float) -> void:
	player.weapons.give_weapon.rpc(weapon)
	await wait(0.4)
	player.input.weapon_slot = weapon
	await wait(1.0)
	for s in steps:
		player.input.fire_pressed = true
		var t := 0.0
		await wait(0.12)
		var tn := player.weapons._trail_node
		print("[TRAIL] samples=%d node=%s visible=%s surfaces=%d aabb=%s pos=%s" % [player.weapons._trail.size(), str(tn != null), str(tn.is_visible_in_tree()) if tn != null else "-", player.weapons._trail_mesh.get_surface_count() if player.weapons._trail_mesh != null else -1, str(tn.get_aabb()) if tn != null else "-", str(player.weapons._trail[0][1]) if not player.weapons._trail.is_empty() else "-"])
		for f in 5:
			await wait(gap)
			await _snap("%s_s%d_f%d" % [label, s, f])
		await wait(0.6)


func run() -> void:
	var wm := wave_manager()
	await wait(2.0)
	player._apply_teleport(Vector3(0.5, 0.1, 0.5))
	player.input.aim_yaw = 0.0
	player.input.aim_pitch = 0.0
	for i in 3: # a few zombies to hit
		var z := wm.spawn_at(Vector3(-0.8 + i * 0.9, 0, -1.4), 0, 99999, 0.0)
		z.set_physics_process(false)
	Net.debug_god = true
	await wait(0.8)
	await _swing(9, "katana", 1, 0.045)
	await _swing(8, "bat", 1, 0.1)
	await _swing(10, "axe", 1, 0.15)
	finish()
