extends BotScenario
## M4b host: the speaker. Runs with --voice-test-tone, so the "microphone" is a 440 Hz tone and the whole
## encode -> network -> relay -> decode path can be tested headless. Moves players apart to test range culling.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("host: listener present", ok)
	if not ok:
		finish()
		return
	var client := other_player()
	await wait(2.0)

	signal_peers("V1_start")
	await wait_signal("V1_done", 30.0)

	player._apply_teleport(Vector3(-24, 0.1, 0))
	client.cl_teleport.rpc_id(client.peer_id, Vector3(24, 0.1, 0))
	await wait(1.2)
	report("host: players are now far outside hearing range", player.global_position.distance_to(client.global_position) > Voice.HEAR_RANGE + 10.0, "d=%.0f" % player.global_position.distance_to(client.global_position))
	signal_peers("V2_start")
	await wait_signal("V2_done", 30.0)

	player._apply_teleport(Vector3(0, 0.1, 0))
	client.cl_teleport.rpc_id(client.peer_id, Vector3(3, 0.1, 0))
	await wait(1.2)
	signal_peers("V3_start")
	await wait_signal("V3_done", 30.0)

	report("host: sent voice packets", int(Voice.stats["packets_out"]) > 100, "out=%d" % int(Voice.stats["packets_out"]))
	signal_peers("M4B_done")
	await wait(0.5)
	finish()
