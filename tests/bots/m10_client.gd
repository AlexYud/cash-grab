extends BotScenario
## M10 client: sees the crawler on the ceiling, upside down, from its own point of view.


func _crawler() -> Zombie:
	for z in enemies():
		if z.kind == Zombie.Kind.CRAWLER:
			return z
	return null


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	await wait_signal("C_start", 120.0)
	await wait_until(func() -> bool: return _crawler() != null, 5.0)
	var crawler := _crawler()
	report("C: the client sees the crawler", crawler != null)
	await wait_signal("C_ceiling", 30.0)
	if crawler != null and is_instance_valid(crawler):
		var up := await wait_until(func() -> bool: return is_instance_valid(crawler) and crawler.state == Zombie.State.CEILING, 3.0)
		report("C: the client sees it on the ceiling", up and crawler.global_position.y > 3.0, "y=%.2f" % crawler.global_position.y)
		report("C: ...upside down", absf(absf(crawler.puppet.rotation.z) - PI) < 0.5, "roll=%.2f" % crawler.puppet.rotation.z)
	await wait_signal("M10_done", 60.0)
	finish()
