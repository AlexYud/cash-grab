extends BotScenario
## M3a client side: lives through being downed, revived, dragged and eliminated, asserting what it feels.


func run() -> void:
	var ok := await wait_until(func() -> bool: return other_player() != null, 20.0)
	report("client: host's player exists", ok)
	if not ok:
		finish()
		return
	var host := other_player()

	# --- D ---
	if not await wait_signal("D_start", 30.0):
		report("client: D_start barrier", false)
		finish()
		return
	var down := await wait_until(func() -> bool: return player.status == Player.Status.DOWNED, 3.0)
	report("D: client sees itself downed", down)
	var max_speed := 0.0
	player.input.move = Vector2(0, -1)
	for i in 90:
		max_speed = maxf(max_speed, Vector2(player.velocity.x, player.velocity.z).length())
		await get_tree().physics_frame
	player.input.move = Vector2.ZERO
	report("D: downed players only crawl", max_speed > 0.5 and max_speed <= GameConfig.CRAWL_SPEED + 0.3, "max=%.2f" % max_speed)
	player.input.weapon_slot = 1
	await wait(0.6)
	report("D: downed players are stuck with the pistol", player.weapons.current == 0)
	var ammo := player.weapons.ammo[0]
	aim_at(host.global_position)
	await fire()
	await wait(0.4)
	report("D: downed players can still fire", player.weapons.ammo[0] == ammo - 1, "ammo %d -> %d" % [ammo, player.weapons.ammo[0]])
	var up := await wait_until(func() -> bool: return player.status == Player.Status.ALIVE, 20.0)
	report("D: client sees itself revived, never 'alive with 0 hp'", up and player.hp == GameConfig.REVIVE_HP, "hp=%d" % player.hp)
	await wait_signal("D_done", 10.0)

	# --- G ---
	if not await wait_signal("G_start", 30.0):
		report("client: G_start barrier", false)
		finish()
		return
	await wait_until(func() -> bool: return player.status == Player.Status.DOWNED, 3.0)
	var start := player.global_position
	await wait_until(func() -> bool: return host.grabbing == player.peer_id, 10.0)
	await wait(5.0)
	report("G: client was dragged (own, authoritative position)", player.global_position.distance_to(start) > 4.0, "moved=%.1f" % player.global_position.distance_to(start))

	# --- B ---
	if not await wait_signal("B_start", 30.0):
		report("client: B_start barrier", false)
		finish()
		return
	var elim := await wait_until(func() -> bool: return player.status == Player.Status.ELIMINATED, 25.0)
	report("B: client sees itself eliminated", elim)
	var back := await wait_until(func() -> bool: return player.status == Player.Status.ALIVE, 10.0)
	report("B: client is back after the wave clears", back and player.hp == GameConfig.PLAYER_MAX_HP, "hp=%d" % player.hp)
	await wait_signal("M3A_done", 10.0)
	finish()
