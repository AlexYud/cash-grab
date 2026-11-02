extends BotScenario
## M4c host: four players are in; a fifth tries to join and must be turned away without disturbing anyone.


func run() -> void:
	var full := await wait_until(func() -> bool: return Net.all_players().size() == Net.MAX_PLAYERS, 30.0)
	report("host: four players in the game", full)
	await wait(22.0) # the fifth client connects after ~8 s and gets refused/timed out
	report("host: still exactly four players after a fifth tried to join", Net.roster.size() == 4 and Net.all_players().size() == 4, "roster=%d players=%d" % [Net.roster.size(), Net.all_players().size()])
	signal_peers("M4C_done")
	await wait(0.5)
	finish()
