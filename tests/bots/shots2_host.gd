extends BotScenario
## Two-window visual check, host side (run together with shots2_client in real windows, not --headless).


func _snap(snap_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [str(h.args.get("shotdir", ".")), snap_name]
	print("[SHOT] %s err=%d" % [path, img.save_png(path)])


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 30.0)
	if not ok:
		finish()
		return
	var client := other_player()
	await wait(3.0)
	aim_at(client.global_position + Vector3(0, 1.3, 0))
	await wait(1.0)
	await _snap("h1_teammate_in_view")
	signal_peers("S1")
	await wait_signal("S2_done", 60.0)
	await wait(1.0)
	player.srv_take_damage(999)
	await wait(1.2)
	await _snap("h2_downed_self")
	signal_peers("S3")
	await wait_signal("S3_done", 40.0)
	player.srv_restore(player.global_position, false)
	await wait(1.0)
	finish()
