extends BotScenario
## Two-window visual check, client side: how a remote teammate looks (name tag, colour, shove ragdoll, grab
## line, downed pose and the revive prompt).


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
	var host := other_player()
	await wait(3.0)
	aim_at(host.global_position + Vector3(0, 1.3, 0))
	await wait(1.0)
	await _snap("c1_teammate_in_view")
	await wait_signal("S1", 40.0)

	await walk_to(host.global_position + Vector3(0, 0, 1.8), 0.3, 8.0)
	aim_at(host.global_position + Vector3(0, 1.2, 0))
	await wait(0.5)
	await shove()
	await wait(0.3)
	await _snap("c2_teammate_ragdoll")
	await wait(3.0)

	await walk_to(host.global_position + Vector3(0, 0, 2.2), 0.3, 6.0)
	aim_at(host.global_position + Vector3(0, 1.0, 0))
	await wait(0.4)
	player.input.grab_held = true
	await wait(1.2)
	await _snap("c3_grab_line")
	player.input.grab_held = false
	signal_peers("S2_done")

	await wait_signal("S3", 40.0)
	await walk_to(host.global_position + Vector3(0, 0, 1.7), 0.4, 6.0)
	aim_at(host.global_position + Vector3(0, 0.3, 0))
	await wait(0.8)
	await _snap("c4_downed_teammate")
	player.input.interact_held = true
	await wait(1.6)
	await _snap("c5_reviving")
	player.input.interact_held = false
	signal_peers("S3_done")
	await wait(0.5)
	finish()
