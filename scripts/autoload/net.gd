extends Node
## Connection handling, lobby roster and the high-level game phase.
##
## Listen-server model: one player hosts (peer id 1), up to three join. Everything with gameplay
## consequences is decided on the host; this node only knows who is connected and what phase we are in.

signal phase_changed(phase: int)
signal roster_changed
signal join_failed(reason: String)
signal disconnected(reason: String)
signal peer_joined(peer_id: int) ## host only: a client finished registering
signal peer_left(peer_id: int) ## host only
signal game_started ## host only: lobby -> playing

enum Phase { MENU, LOBBY, PLAYING }

const DEFAULT_PORT := 24567
const MAX_PLAYERS := 4
const PROTOCOL := 1
const PLAYER_COLORS: Array[Color] = [
	Color(0.88, 0.27, 0.22),
	Color(0.27, 0.52, 0.95),
	Color(0.96, 0.78, 0.2),
	Color(0.7, 0.42, 0.9),
]

var phase: int = Phase.MENU
var roster: Dictionary = {} ## peer id (int) -> {"name": String, "color": int}
var local_name := "Player"
var bind_ip := "*" ## "127.0.0.1" keeps automated tests off the firewall prompt
var players_root: Node = null ## Main/World/Players, set by Main
var local_player: Player = null ## set by the local Player node itself
var ui_blocking := false ## true while a menu has the mouse; the player stops reading input
var sens_scale := 1.0 ## mouse sensitivity multiplier from the pause menu
var debug_bleed_time := -1.0 ## tests: override GameConfig.BLEED_OUT_TIME when > 0
var debug_god := false ## tests: players take no damage (lets bots finish stability soaks)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- helpers ---------------------------------------------------------------------------------

func is_host() -> bool:
	return multiplayer.is_server()


## Peer id of whoever is executing an RPC; our own id when called as a plain function.
func sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else multiplayer.get_unique_id()


func get_player(peer_id: int) -> Player:
	if not is_instance_valid(players_root):
		return null
	return players_root.get_node_or_null(str(peer_id)) as Player


func all_players() -> Array[Player]:
	var out: Array[Player] = []
	if not is_instance_valid(players_root):
		return out
	for c in players_root.get_children():
		if c is Player and not c.is_queued_for_deletion():
			out.append(c)
	return out


func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		out.append(a)
	return out


# --- host / join / leave ---------------------------------------------------------------------

func host_game(port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	if bind_ip != "*":
		peer.set_bind_ip(bind_ip)
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	roster = {1: {"name": player_name, "color": 0}}
	_set_phase(Phase.LOBBY)
	roster_changed.emit()
	return OK


func join_game(address: String, port: int, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	local_name = player_name
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer == peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
			leave("")
			join_failed.emit("Can't reach %s:%d. Check the IP and port, that the host opened UDP %d (port forwarding / UPnP / VPN), and the host's firewall." % [address, port, port]))
	return OK


# --- UPnP: ask the router to open the port (works on many home routers, not behind CGNAT) ---------------

signal upnp_changed
var upnp_status := ""
var _upnp: UPNP = null
var _upnp_port := 0
var _upnp_thread: Thread = null


func try_upnp(port: int) -> void:
	if _upnp_thread != null or DisplayServer.get_name() == "headless":
		return
	upnp_status = "Opening port %d with UPnP..." % port
	upnp_changed.emit()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work.bind(port))


func _upnp_work(port: int) -> void:
	var u := UPNP.new()
	var msg := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() != null and u.get_gateway().is_valid_gateway():
		if u.add_port_mapping(port, port, "CashGrab", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS:
			msg = "Port opened. Friends outside your network join: %s : %d" % [u.query_external_address(), port]
		else:
			msg = "UPnP found your router but it refused to open the port. Forward UDP %d manually or use a VPN (Tailscale/ZeroTier)." % port
	else:
		msg = "No UPnP router found. Forward UDP %d manually or use a VPN (Tailscale/ZeroTier)." % port
	_upnp_done.call_deferred(u, msg, port)


func _upnp_done(u: UPNP, msg: String, port: int) -> void:
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	_upnp = u
	_upnp_port = port
	upnp_status = msg
	upnp_changed.emit()


func _close_upnp() -> void:
	if _upnp != null and _upnp_port > 0:
		_upnp.delete_port_mapping(_upnp_port, "UDP")
	_upnp = null
	upnp_status = ""


func leave(reason: String = "") -> void:
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_close_upnp()
	roster.clear()
	local_player = null
	ui_blocking = false
	_set_phase(Phase.MENU)
	disconnected.emit(reason)


func start_game() -> void:
	if not is_host() or phase != Phase.LOBBY:
		return
	_set_phase(Phase.PLAYING)
	_broadcast_roster()
	game_started.emit()


func return_to_lobby() -> void:
	if not is_host() or phase != Phase.PLAYING:
		return
	_set_phase(Phase.LOBBY)
	_broadcast_roster()


func _set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(p)


## Sends the roster to every registered client that is still properly connected. (A plain rpc() also targets
## peers that are halfway through disconnecting, which makes ENet log an error when several players quit at once.)
func _broadcast_roster() -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	for id in roster.keys():
		if id == 1:
			continue
		if enet != null:
			var pp := enet.get_peer(id)
			if pp == null or pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
				continue
		cl_roster.rpc_id(id, roster, phase)
	roster_changed.emit()


# --- connection callbacks --------------------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass # wait for srv_register; an unregistered peer is not part of the roster


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not roster.has(id):
		return
	roster.erase(id)
	peer_left.emit(id)
	_broadcast_roster()


func _on_connected_to_server() -> void:
	srv_register.rpc_id(1, local_name, PROTOCOL)


func _on_connection_failed() -> void:
	leave("")
	join_failed.emit("Could not reach the host. Check the address, port and firewall.")


func _on_server_disconnected() -> void:
	leave("The host closed the game.")


# --- RPCs ------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_register(player_name: String, protocol: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		return
	if protocol != PROTOCOL:
		_reject(id, "Version mismatch: both players need the same build.")
		return
	if roster.size() >= MAX_PLAYERS:
		_reject(id, "The game is full.")
		return
	var used: Array = []
	for r in roster.values():
		used.append(r["color"])
	var color := 0
	while used.has(color):
		color += 1
	var clean := player_name.strip_edges().left(16)
	roster[id] = {"name": clean if clean != "" else "Player%d" % id, "color": color}
	_broadcast_roster()
	peer_joined.emit(id)


func _reject(id: int, reason: String) -> void:
	cl_rejected.rpc_id(id, reason)
	await get_tree().create_timer(0.3).timeout
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		peer.disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func cl_rejected(reason: String) -> void:
	leave("")
	join_failed.emit(reason)


@rpc("authority", "call_remote", "reliable")
func cl_roster(new_roster: Dictionary, new_phase: int) -> void:
	roster = new_roster
	roster_changed.emit()
	if new_phase != phase:
		_set_phase(new_phase)
