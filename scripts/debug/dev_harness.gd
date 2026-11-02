class_name DevHarness
extends Node
## Command-line automation for development and the headless tests in tests/. Created by Main only when user
## args are present (everything after `--`), so a normal launch never sees it.
##
##   --host[=PORT]  --join=IP[:PORT]  --solo      connect / start without clicking the menu
##   --name=NAME  --bind=IP                       player name; bind address (127.0.0.1 avoids firewall prompts)
##   --autostart=N                                host starts the game once N players are in the lobby
##   --bot=SCRIPT                                 drive the local player with tests/bots/SCRIPT.gd
##   --quit-after=SECONDS                         hard stop (exit code 1 if any test failed)
##   --shot=PATH[,DELAY]                          save a screenshot once the local player exists (needs a window)
##   --voice-test-tone                            send a 440 Hz tone instead of the microphone
##   --hold-waves                                 host: freeze the wave timer so a bot can stage its own scenario
##   --bleed-time=S                               shorten the downed bleed-out timer
##   --god                                        players take no damage (soak tests with unskilled bots)
##   --time-scale=N                               run the simulation N times faster (soak tests)

var args := {}
var passes := 0
var fails := 0
var signals_seen := {}

var _bot_name := ""
var _bot: Node = null
var _autostart := 0
var _started := false
var _t := 0.0
var _shot_path := ""
var _shot_delay := 2.0
var _shot_done := false
var _finished := false


func _ready() -> void:
	args = _parse(OS.get_cmdline_user_args())
	Net.bind_ip = str(args.get("bind", "*"))
	var pname := str(args.get("name", "Bot%d" % randi_range(10, 99)))
	if args.has("voice-test-tone"):
		Voice.test_tone = true
	if args.has("host"):
		var port := int(args["host"]) if str(args["host"]) != "" else Net.DEFAULT_PORT
		print("[HARNESS] host port=%d err=%d" % [port, Net.host_game(port, pname)])
	elif args.has("join"):
		var parts := str(args["join"]).split(":")
		var port := int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT
		print("[HARNESS] join %s:%d err=%d" % [parts[0], port, Net.join_game(parts[0], port, pname)])
	elif args.has("solo"):
		Net.bind_ip = "127.0.0.1"
		var port := randi_range(20000, 60000)
		print("[HARNESS] solo port=%d err=%d" % [port, Net.host_game(port, pname)])
		Net.start_game()
	_autostart = int(args.get("autostart", 0))
	_bot_name = str(args.get("bot", ""))
	if args.has("time-scale"):
		Engine.time_scale = float(args["time-scale"])
		Engine.max_physics_steps_per_frame = 16
	if args.has("god"):
		Net.debug_god = true
	if args.has("bleed-time"):
		Net.debug_bleed_time = float(args["bleed-time"])
	if args.has("hold-waves"):
		var wm := get_parent().get_node("World/WaveManager") as WaveManager
		wm.hold = true
	if args.has("quit-after"):
		get_tree().create_timer(float(args["quit-after"])).timeout.connect(func() -> void:
			print("[HARNESS] quit-after reached")
			finish())
	if args.has("expect-join-fail"):
		# a client that must be refused: passes when the join fails, fails if it ever reaches a lobby/game
		Net.join_failed.connect(func(reason: String) -> void:
			report("a full game turns the fifth player away", true, reason)
			finish())
		get_tree().create_timer(45.0).timeout.connect(func() -> void:
			report("a full game turns the fifth player away", false, "still waiting after 45 s, phase=%d" % Net.phase)
			finish())
	if args.has("shot"):
		var s := str(args["shot"]).split(",")
		_shot_path = s[0]
		if s.size() > 1:
			_shot_delay = float(s[1])
	Net.disconnected.connect(func(reason: String) -> void: print("[HARNESS] disconnected: '%s'" % reason))


func _process(delta: float) -> void:
	_t += delta
	if _autostart > 0 and not _started and Net.is_host() and Net.phase == Net.Phase.LOBBY and Net.roster.size() >= _autostart:
		_started = true
		print("[HARNESS] starting game with %d players" % Net.roster.size())
		Net.start_game()
	if _bot == null and _bot_name != "" and Net.local_player != null:
		_attach_bot()
	if _shot_path != "" and not _shot_done and (Net.local_player != null or args.has("shot-any")):
		_shot_delay -= delta
		if _shot_delay <= 0.0:
			_shot_done = true
			var img := get_viewport().get_texture().get_image()
			print("[HARNESS] screenshot %s err=%d size=%s" % [_shot_path, img.save_png(_shot_path), img.get_size()])
			if not args.has("quit-after") and _bot_name == "":
				finish()


func _attach_bot() -> void:
	var script := load("res://tests/bots/%s.gd" % _bot_name) as GDScript
	if script == null:
		print("[HARNESS] cannot load bot '%s'" % _bot_name)
		fails += 1
		finish()
		return
	_bot = script.new()
	_bot.name = "Bot"
	add_child(_bot)
	_bot.attach(self, Net.local_player)
	Net.local_player.bot_controlled = true
	print("[HARNESS] bot '%s' attached to %s" % [_bot_name, Net.local_player.name])
	_bot.run()


## Test barriers: bots in different processes use these to agree on "phase X has started".
func send_signal(tag: String) -> void:
	signals_seen[tag] = true
	if not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		test_signal.rpc(tag)


@rpc("any_peer", "call_remote", "reliable")
func test_signal(tag: String) -> void:
	signals_seen[tag] = true


func report(test: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[TEST] %s %s%s" % ["PASS" if ok else "FAIL", test, ("  (" + detail + ")") if detail != "" else ""])


func finish() -> void:
	if _finished:
		return
	_finished = true
	print("[HARNESS] done passes=%d fails=%d" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _parse(list: PackedStringArray) -> Dictionary:
	var d := {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		d[kv[0]] = kv[1] if kv.size() > 1 else ""
	return d
