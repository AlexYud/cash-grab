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
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	menu.solo_requested.connect(_on_solo_requested)
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
	if phase == Net.Phase.MENU:
		_free_children(players_node)
		_free_children(enemies_node)
	elif phase == Net.Phase.LOBBY and Net.is_host():
		_free_children(players_node) # host frees -> spawner despawns on every client
		_free_children(enemies_node)
	_refresh_ui()


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
	Net.ui_blocking = not playing or _pause_open or end.visible
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
	# end-of-run screen
	if Net.phase == Net.Phase.PLAYING:
		var over := wave_manager.state == WaveManager.State.VICTORY or wave_manager.state == WaveManager.State.GAME_OVER
		if over and not _end_shown:
			_end_timer += delta
			if _end_timer >= END_SCREEN_DELAY:
				_end_shown = true
				end.show_result(wave_manager.state == WaveManager.State.VICTORY, wave_manager.wave, wave_manager.total_waves)
				_refresh_ui()
		elif not over:
			_end_timer = 0.0
			if _end_shown:
				_end_shown = false
				_refresh_ui()
