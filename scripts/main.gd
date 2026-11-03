extends Node
## Scene root. Wires lobby/game flow, the two spawners and the code-built screens together.
##
## Scene layout (scenes/main.tscn): World{Level, Players, Enemies, Fx, PlayerSpawner, EnemySpawner, WaveManager},
## MenuCam, UI. Everything exists on every peer from boot, so RPC/sync node paths always resolve; players
## and zombies are the only things created at runtime, and only by the host (MultiplayerSpawner replicates).

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ZOMBIE_SCENE := preload("res://scenes/enemy/zombie.tscn")
const END_SCREEN_DELAY := 2.5

var menu: MainMenu
var lobby: LobbyScreen
var hud: Hud
var pause: PauseMenu
var end: EndScreen
var cards: CardScreen
var _cards_hidden := false
var _cards_delay := 0.0 ## seconds before freshly dealt cards open (so nobody picks one with a stray click)
const CARDS_DELAY := 2.5

var _pause_open := false
var _end_timer := 0.0
var _end_shown := false
var _orbit := 0.0

@onready var level: SaloonLevel = $World/Level
@onready var players_node: Node3D = $World/Players
@onready var enemies_node: Node3D = $World/Enemies
@onready var player_spawner: MultiplayerSpawner = $World/PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $World/EnemySpawner
@onready var wave_manager: WaveManager = $World/WaveManager
@onready var menu_cam: Camera3D = $MenuCam
@onready var ui_layer: CanvasLayer = $UI


func _ready() -> void:
	for pair in [["weapon_3", KEY_3], ["weapon_4", KEY_4], ["weapon_5", KEY_5], ["weapon_6", KEY_6], ["weapon_7", KEY_7], ["weapon_8", KEY_8], ["weapon_9", KEY_9],
			["ready", KEY_ENTER], ["cards", KEY_TAB]]: # registered here so project.godot does not need to change
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var ev := InputEventKey.new()
			ev.physical_keycode = pair[1]
			InputMap.action_add_event(pair[0], ev)
	if not InputMap.has_action("ads"):
		InputMap.add_action("ads")
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("ads", rmb)
	var saved := UiKit.load_settings() # volume and mouse sensitivity survive closing the game
	Net.sens_scale = float(saved.get_value("audio", "sensitivity", 1.0))
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(saved.get_value("audio", "master", 1.0)), 0.0001, 1.0)))
	Fx.world = $World/Fx
	Net.players_root = players_node
	player_spawner.spawn_function = _spawn_player
	enemy_spawner.spawn_function = _spawn_enemy
	_build_ui()
	Net.phase_changed.connect(_on_phase_changed)
	Net.join_failed.connect(func(reason: String) -> void: menu.set_status(reason))
	Net.disconnected.connect(func(reason: String) -> void:
		if reason != "":
			menu.set_status(reason))
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.game_started.connect(_on_game_started)
	_refresh_ui()
	if not OS.get_cmdline_user_args().is_empty():
		var h := DevHarness.new()
		h.name = "DevHarness"
		add_child(h)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.theme = UiKit.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)
	hud = Hud.new()
	hud.name = "Hud"
	root.add_child(hud)
	hud.bind(wave_manager)
	menu = MainMenu.new()
	menu.name = "MainMenu"
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	lobby = LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(lobby)
	pause = PauseMenu.new()
	pause.name = "Pause"
	pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause)
	end = EndScreen.new()
	end.name = "End"
	end.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(end)
	cards = CardScreen.new()
	cards.name = "Cards"
	cards.visible = false
	root.add_child(cards)
	cards.pick_requested.connect(wave_manager.request_pick)
	cards.ready_requested.connect(wave_manager.press_ready)
	wave_manager.offers_changed.connect(_on_offers_changed)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	menu.solo_requested.connect(_on_solo_requested)
	menu.steam_host_requested.connect(Net.steam.host)
	menu.steam_join_requested.connect(Net.steam.join)
	menu.steam_refresh_requested.connect(Net.steam.refresh_list)
	lobby.start_requested.connect(Net.start_game)
	lobby.leave_requested.connect(Net.leave.bind(""))
	pause.resume_requested.connect(_set_paused.bind(false))
	pause.leave_requested.connect(Net.leave.bind(""))
	end.restart_requested.connect(_on_restart_requested)
	end.lobby_requested.connect(Net.return_to_lobby)
	end.leave_requested.connect(Net.leave.bind(""))


# --- menu actions ---------------------------------------------------------------------------------------

func _on_host_requested(player_name: String, port: int) -> void:
	Net.bind_ip = "*"
	if Net.host_game(port, player_name) != OK:
		menu.set_status("Could not host on port %d (already in use?)" % port)
		return
	lobby.port = port
	Net.try_upnp(port)


func _on_join_requested(player_name: String, address: String, port: int) -> void:
	if Net.join_game(address, port, player_name) != OK:
		menu.set_status("Invalid address.")


func _on_solo_requested(player_name: String) -> void:
	Net.bind_ip = "127.0.0.1"
	for attempt in 8:
		var port := randi_range(20000, 60000)
		if Net.host_game(port, player_name) == OK:
			lobby.port = port
			Net.start_game()
			return
	menu.set_status("Could not start a local game.")


func _on_restart_requested() -> void:
	if Net.is_host():
		wave_manager.restart_run()


# --- game flow ----------------------------------------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if phase != Net.Phase.PLAYING:
		_pause_open = false
		_end_shown = false
	if phase != Net.Phase.PLAYING:
		for p in players_node.get_children():
			if p is Player:
				p.stop_net_sync()
	if phase == Net.Phase.MENU:
		_free_children(players_node)
		_free_children(enemies_node)
	elif phase == Net.Phase.LOBBY and Net.is_host():
		_free_players_soon()
	_refresh_ui()


## Back in the lobby: give the clients a moment to hear about it (and stop streaming positions) before the host frees
## the players, which makes the spawner despawn them everywhere.
func _free_players_soon() -> void:
	_free_children(enemies_node)
	await get_tree().create_timer(0.35).timeout
	if Net.phase == Net.Phase.LOBBY: # not already started again
		_free_children(players_node)


func _on_game_started() -> void:
	level.bake_navigation()
	var slot := 0
	for id in Net.roster.keys():
		spawn_player(id, slot)
		slot += 1
	wave_manager.start_run()


func _on_peer_joined(peer: int) -> void:
	if Net.phase == Net.Phase.PLAYING:
		spawn_player(peer, players_node.get_child_count())


func _on_peer_left(peer: int) -> void:
	var n := players_node.get_node_or_null(str(peer))
	if n != null:
		n.queue_free()


func spawn_player(peer: int, slot: int) -> void:
	if players_node.has_node(str(peer)) or not Net.roster.has(peer):
		return
	var xf := level.player_spawn(slot)
	player_spawner.spawn({
		"peer": peer,
		"name": Net.roster[peer]["name"],
		"color": Net.roster[peer]["color"],
		"pos": xf.origin,
		"yaw": xf.basis.get_euler().y,
	})


func _spawn_player(data: Dictionary) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.setup(data)
	return p


func _spawn_enemy(data: Dictionary) -> Node:
	var z: Zombie = ZOMBIE_SCENE.instantiate()
	z.setup(data)
	return z


func _free_children(n: Node) -> void:
	for c in n.get_children():
		c.free()


# --- UI state ---------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and Net.phase == Net.Phase.PLAYING:
		_set_paused(not _pause_open)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ready") and Net.phase == Net.Phase.PLAYING and not _pause_open and wave_manager.state == WaveManager.State.BREAK \
			and Net.local_player != null:
		wave_manager.press_ready(not wave_manager.is_ready(Net.local_player.peer_id))
		Sfx.play(&"ready", -4.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cards") and Net.phase == Net.Phase.PLAYING and not _pause_open and not wave_manager.my_offers.is_empty():
		_cards_delay = 0.0
		_cards_hidden = not _cards_hidden # Tab: put the cards away to walk around, bring them back to choose
		_refresh_ui()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Net.phase == Net.Phase.PLAYING and not Net.ui_blocking \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED # capture was lost (alt-tab): a click takes it back


func _set_paused(v: bool) -> void:
	_pause_open = v
	_refresh_ui()


func _refresh_ui() -> void:
	var playing := Net.phase == Net.Phase.PLAYING
	menu.visible = Net.phase == Net.Phase.MENU
	lobby.visible = Net.phase == Net.Phase.LOBBY
	hud.visible = playing and not _pause_open
	pause.visible = playing and _pause_open
	end.visible = playing and _end_shown and not _pause_open
	cards.visible = _cards_wanted()
	Net.ui_blocking = not playing or _pause_open or end.visible or cards.visible
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Net.ui_blocking else Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# backdrop camera orbits the saloon whenever there is no local player camera
	if Net.local_player == null:
		_orbit += delta * 0.12
		menu_cam.global_position = Vector3(sin(_orbit) * 26.0, 9.0, 5.0 + cos(_orbit) * 26.0)
		menu_cam.look_at(Vector3(0, 1.5, 4.0))
		if not menu_cam.current:
			menu_cam.make_current()
	_update_cards()
	# end-of-run screen
	if Net.phase == Net.Phase.PLAYING:
		var over := wave_manager.state == WaveManager.State.VICTORY or wave_manager.state == WaveManager.State.GAME_OVER
		if over and not _end_shown:
			_end_timer += delta
			if _end_timer >= END_SCREEN_DELAY:
				_end_shown = true
				end.show_result(wave_manager.state == WaveManager.State.VICTORY, wave_manager.wave)
				_refresh_ui()
		elif not over:
			_end_timer = 0.0
			if _end_shown:
				_end_shown = false
				_refresh_ui()


# --- reward cards + ready ---------------------------------------------------------------------------------

func _cards_wanted() -> bool:
	return Net.phase == Net.Phase.PLAYING and not _pause_open and not end.visible and not _cards_hidden and _cards_delay <= 0.0 \
			and wave_manager.state == WaveManager.State.BREAK and not wave_manager.my_offers.is_empty()


func _on_offers_changed() -> void:
	_cards_hidden = false
	_cards_delay = CARDS_DELAY if not wave_manager.my_offers.is_empty() else 0.0 # let the kill-clicking stop first
	if not wave_manager.my_offers.is_empty() and Net.local_player != null:
		cards.show_offers(wave_manager.my_offers, Net.local_player.weapons)
		Sfx.play(&"card", -4.0)
	_refresh_ui()


func _update_cards() -> void:
	_cards_delay = maxf(_cards_delay - get_process_delta_time(), 0.0)
	if cards.visible != _cards_wanted():
		_refresh_ui()
	if not cards.visible or Net.local_player == null:
		return
	var waiting: Array = []
	for p in Net.all_players():
		if not wave_manager.is_ready(p.peer_id):
			waiting.append(p.player_name)
	cards.refresh([], waiting, wave_manager.is_ready(Net.local_player.peer_id))
