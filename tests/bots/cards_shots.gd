extends BotScenario
## Visual check of the wall buys, the upgrader machines and their cards. Needs a real window (not --headless).
## Saves PNGs into --shotdir=DIR. Run with --hold-waves.


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d" % [path, img.save_png(path)])


func _look(pos: Vector3, yaw: float) -> void:
	player._apply_teleport(pos)
	player.input.aim_yaw = yaw
	player.input.aim_pitch = 0.0
	await wait(0.9)


func _use(sec: float) -> void:
	player.input.interact_held = true
	await wait(sec)
	player.input.interact_held = false
	await wait(0.4)


func run() -> void:
	var wm := wave_manager()
	await wait(2.0)
	wm.cash = 9000
	# wall buys (the player looks at the wall)
	await _look(Vector3(-3.5, 0.1, 6.2), PI) # south wall: shotgun
	await _snap("wall_shotgun")
	await _look(Vector3(3.0, 0.1, -6.2), 0.0) # north wall: katana
	await _snap("wall_katana")
	await _look(Vector3(13.0, 0.1, 7.2), PI) # annex: armor vest
	await _snap("wall_armor")
	await _look(Vector3(37.5, 0.1, -3.6), PI / 2.0) # hall: assault rifle (west wall, looking... west is +x? yaw 90 faces -x)
	await _snap("wall_rifle")
	# the weapon upgrader and its cards
	await _look(Vector3(-8.2, 0.1, -2.75), PI / 2.0)
	await _snap("machine_weapon")
	await _use(1.4)
	await wait(1.4)
	await _snap("cards_weapon")
	wm.request_pick(0)
	await wait(0.8)
	await _use(1.4)
	await wait(1.4)
	await _snap("cards_weapon_2")
	wm.request_pick(1)
	await wait(0.6)
	# the armor upgrader and its cards
	await _look(Vector3(14.0, 0.1, 5.5), -PI / 2.0)
	await _snap("machine_armor")
	await _use(1.4)
	await wait(1.4)
	await _snap("cards_gear")
	finish()
