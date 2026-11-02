class_name SteamLobby
extends Node
## Optional Steam transport: lobbies + Steam relay networking (no IPs, no port forwarding).
## Created and owned by Net. Everything is called dynamically, so the project runs fine without the addons
## (addons/godotsteam + addons/steam-multiplayer-peer); `available` just stays false and `status` says why.
##
## Uses Valve's shared test App ID 480 ("Spacewar"), so it works without publishing anything. Lobbies are tagged
## with GAME_KEY so the lobby list only shows CashGrab games.

signal status_changed
signal lobbies_listed(list: Array)

const APP_ID := 480
const GAME_KEY := "cashgrab"
const LOBBY_PUBLIC := 2
const DISTANCE_WORLDWIDE := 3

var available := false
var status := "Steam: not checked yet"
var lobby_id := 0
var persona := ""

var _steam: Object = null
var _embedded := false
var _mode := ""
var _peer_methods: Array = []


func _ready() -> void:
	_init_steam()


func _process(_delta: float) -> void:
	if available and not _embedded and _steam.has_method("run_callbacks"):
		_steam.run_callbacks()


func _set_status(s: String) -> void:
	status = s
	print("[STEAM] ", s)
	status_changed.emit()


func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		_set_status("Steam unavailable: GodotSteam addon is not loaded (addons/godotsteam).")
		return
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		_set_status("Steam unavailable: SteamMultiplayerPeer addon is not loaded (addons/steam-multiplayer-peer).")
		return
	_steam = Engine.get_singleton("Steam")
	_peer_api() # prints the peer's methods once, handy if joining misbehaves
	var result: Variant = null
	var used := ""
	for fn in ["steamInitEx", "steamInit"]:
		if _steam.has_method(fn):
			used = fn
			result = _steam.callv(fn, _init_args(fn))
			break
	if used == "":
		_set_status("Steam unavailable: this GodotSteam build has no steamInit method.")
		return
	var ok := false
	var why := ""
	if result is Dictionary:
		ok = int(result.get("status", 1)) == 0
		why = str(result.get("verbal", result))
	elif result is bool:
		ok = result
		why = "init returned false"
	else:
		ok = result == null or int(result) == 0
	if not ok:
		_set_status("Steam unavailable: %s. Is the Steam client running and logged in?" % why)
		return
	available = true
	for pair in [["lobby_created", "_on_lobby_created"], ["lobby_joined", "_on_lobby_joined"], ["lobby_match_list", "_on_match_list"], ["join_requested", "_on_join_requested"]]:
		if _steam.has_signal(pair[0]):
			_steam.connect(pair[0], Callable(self, pair[1]))
		else:
			push_warning("SteamLobby: signal %s not found in this GodotSteam build" % pair[0])
	if _steam.has_method("getPersonaName"):
		persona = str(_steam.getPersonaName())
	_set_status("Steam ready%s" % ((" as " + persona) if persona != "" else ""))


## Builds the argument list from the method's own parameter names, so it works across GodotSteam versions.
func _init_args(fn: String) -> Array:
	var args: Array = []
	for m in _steam.get_method_list():
		if m["name"] != fn:
			continue
		for a in m["args"]:
			var n := String(a["name"]).to_lower()
			if n.contains("app"):
				args.append(APP_ID)
			elif n.contains("embed"):
				args.append(true)
				_embedded = true
			elif n.contains("retrieve"):
				args.append(false)
			else:
				break
		break
	return args


# --- hosting ---------------------------------------------------------------------------------------

func host(player_name: String) -> void:
	if not _ready_check():
		return
	Net.local_name = player_name
	_mode = "host"
	_set_status("Creating Steam lobby...")
	if not _peer_api().has("create_host") and _peer_api().has("create_lobby"):
		# GodotSteam's own peer owns the lobby: it creates it and tells us the id through a signal
		var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
		peer.connect("lobby_created", func(result: int, id: int) -> void:
			if result != 1:
				_fail("Steam could not create a lobby (code %d)." % result)
				return
			_finish_host(peer, id))
		var e: int = peer.create_lobby(LOBBY_PUBLIC, Net.MAX_PLAYERS)
		if e != OK:
			_fail("Could not create the Steam lobby (error %d)." % e)
		return
	_steam.createLobby(LOBBY_PUBLIC, Net.MAX_PLAYERS)


## Names of the methods the installed SteamMultiplayerPeer has (also printed once for diagnosis).
func _peer_api() -> Array:
	if _peer_methods.is_empty():
		for m in ClassDB.class_get_method_list("SteamMultiplayerPeer", true):
			_peer_methods.append(String(m["name"]))
		print("[STEAM] SteamMultiplayerPeer methods: ", _peer_methods)
	return _peer_methods


func _finish_host(peer: MultiplayerPeer, id: int) -> void:
	lobby_id = id
	_steam.setLobbyData(id, "game", GAME_KEY)
	_steam.setLobbyData(id, "name", Net.local_name)
	Net.adopt_host_peer(peer, Net.local_name)
	_set_status("Hosting on Steam. Lobby ID: %d" % id)


func _on_lobby_created(connect_result: int, id: int) -> void:
	if _mode != "host":
		return
	if connect_result != 1:
		_fail("Steam could not create a lobby (code %d)." % connect_result)
		return
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_host(0)
	if err != OK:
		_fail("Could not start Steam networking (error %d)." % err)
		return
	_finish_host(peer, id)


# --- joining ---------------------------------------------------------------------------------------

func join(id: int, player_name: String) -> void:
	if not _ready_check():
		return
	Net.local_name = player_name
	if not _peer_api().has("create_client") and _peer_api().has("connect_lobby"):
		var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
		var e: int = peer.connect_lobby(id)
		if e != OK:
			_fail("Could not join that lobby (error %d)." % e)
			return
		lobby_id = id
		Net.adopt_client_peer(peer, player_name)
		_set_status("Connecting to the host through Steam...")
		return
	_mode = "join"
	_set_status("Joining Steam lobby %d..." % id)
	_steam.joinLobby(id)
	get_tree().create_timer(20.0).timeout.connect(func() -> void:
		if _mode == "join" and Net.phase == Net.Phase.MENU:
			_mode = ""
			_fail("Timed out joining the Steam lobby. Is the host still in the lobby?"))


func _on_join_requested(id: int, _friend: int) -> void: # accepted a Steam invite
	if Net.phase == Net.Phase.MENU:
		join(id, Net.local_name)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if _mode != "join":
		return
	if response != 1:
		_mode = ""
		_fail("Could not join that lobby (Steam response %d). It may be full or closed." % response)
		return
	lobby_id = id
	var owner_id: int = _steam.getLobbyOwner(id)
	var peer: MultiplayerPeer = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = peer.create_client(owner_id, 0)
	if err != OK:
		_mode = ""
		_fail("Could not connect through Steam (error %d)." % err)
		return
	_mode = ""
	Net.adopt_client_peer(peer, Net.local_name)
	_set_status("Connecting to the host through Steam...")


# --- lobby list ------------------------------------------------------------------------------------

func refresh_list() -> void:
	if not _ready_check():
		return
	_set_status("Searching for CashGrab lobbies...")
	if _steam.has_method("addRequestLobbyListStringFilter"):
		_steam.addRequestLobbyListStringFilter("game", GAME_KEY, 0)
	if _steam.has_method("addRequestLobbyListDistanceFilter"):
		_steam.addRequestLobbyListDistanceFilter(DISTANCE_WORLDWIDE)
	_steam.requestLobbyList()


func _on_match_list(lobbies: Array) -> void:
	var out: Array = []
	for id in lobbies:
		out.append({
			"id": int(id),
			"name": str(_steam.getLobbyData(id, "name")),
			"players": int(_steam.getNumLobbyMembers(id)),
		})
	_set_status("Found %d lobb%s." % [out.size(), "y" if out.size() == 1 else "ies"])
	lobbies_listed.emit(out)


# --- misc ------------------------------------------------------------------------------------------

func leave() -> void:
	_mode = ""
	if available and lobby_id != 0:
		_steam.leaveLobby(lobby_id)
	lobby_id = 0


func _ready_check() -> bool:
	if available:
		return true
	_fail(status)
	return false


func _fail(msg: String) -> void:
	_set_status(msg)
	Net.join_failed.emit(msg)
