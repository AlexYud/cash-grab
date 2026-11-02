extends BotScenario
## M4b listener: counts and inspects the voice packets that reach it.


func _listen(seconds: float) -> int:
	var p0 := int(Voice.stats["packets_in"])
	await wait(seconds)
	return int(Voice.stats["packets_in"]) - p0


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("listener: speaker's player exists", ok)
	if not ok:
		finish()
		return

	await wait_signal("V1_start", 30.0)
	var n := await _listen(2.5)
	report("V1: voice packets arrive while the players are close", n >= 30, "packets=%d (2.5 s, ~25/s expected)" % n)
	report("V1: the 440 Hz tone survives encode/relay/decode", absf(float(Voice.stats["last_hz"]) - 440.0) < 60.0, "hz=%.0f" % float(Voice.stats["last_hz"]))
	report("V1: signal level is sane", float(Voice.stats["last_rms"]) > 0.05, "rms=%.2f" % float(Voice.stats["last_rms"]))
	report("V1: no malformed packets", int(Voice.stats["bad"]) == 0)
	signal_peers("V1_done")

	await wait_signal("V2_start", 30.0)
	await wait(0.6)
	n = await _listen(2.5)
	report("V2: nothing reaches a listener beyond hearing range (host culls)", n <= 3, "packets=%d" % n)
	signal_peers("V2_done")

	await wait_signal("V3_start", 30.0)
	await wait(0.4)
	n = await _listen(2.5)
	report("V3: voice resumes when they are close again", n >= 30, "packets=%d" % n)
	signal_peers("V3_done")
	await wait_signal("M4B_done", 15.0)
	finish()
