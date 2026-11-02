extends BotScenario
## M4c: one of the three clients that fill the lobby. Verifies the roster it sees, then idles.


func run() -> void:
	var full := await wait_until(func() -> bool: return Net.all_players().size() == Net.MAX_PLAYERS, 30.0)
	report("%s sees all four players" % player.player_name, full)
	var colors := {}
	for r in Net.roster.values():
		colors[r["color"]] = true
	report("%s: four distinct colours in the roster" % player.player_name, colors.size() == 4, "colors=%d" % colors.size())
	await wait_signal("M4C_done", 60.0)
	finish()
