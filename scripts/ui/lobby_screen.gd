class_name LobbyScreen
extends CenterContainer

signal start_requested
signal leave_requested

var port := Net.DEFAULT_PORT
var _rows: VBoxContainer
var _info: Label
var _start: Button
var _copy: Button
var _hint: Label


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(UiKit.margin(box, 26))
	box.add_child(UiKit.label("LOBBY", 44, UiKit.ACCENT))
	_info = UiKit.label("", 18, UiKit.DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(460, 0) # a wrapping label needs a width or it wraps per character
	box.add_child(_info)
	box.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	box.add_child(_rows)
	box.add_child(HSeparator.new())
	_hint = UiKit.label("", 18, UiKit.DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(460, 0)
	box.add_child(_hint)
	_copy = UiKit.button("Copy lobby ID")
	_copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(str(Net.steam.lobby_id))
		_copy.text = "Copied! Paste it to your friend")
	box.add_child(_copy)
	_start = UiKit.button("Start game")
	_start.pressed.connect(func() -> void: start_requested.emit())
	box.add_child(_start)
	var leave := UiKit.button("Leave")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave)
	Net.roster_changed.connect(refresh)
	Net.upnp_changed.connect(refresh)
	visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _rows == null:
		return
	_copy.visible = Net.steam.lobby_id != 0 and Net.is_host()
	if not _copy.visible:
		_copy.text = "Copy lobby ID"
	for c in _rows.get_children():
		c.queue_free()
	var ids := Net.roster.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = Net.roster[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(18, 18)
		sw.color = Net.PLAYER_COLORS[int(info["color"]) % Net.PLAYER_COLORS.size()]
		row.add_child(sw)
		var suffix := "  (host)" if id == 1 else ""
		suffix += "  (you)" if id == multiplayer.get_unique_id() else ""
		row.add_child(UiKit.label(str(info["name"]) + suffix, 22))
		_rows.add_child(row)
	var slots := Net.MAX_PLAYERS - ids.size()
	for i in slots:
		_rows.add_child(UiKit.label("   - open slot -", 20, UiKit.DIM.darkened(0.3)))
	if Net.steam.lobby_id != 0 and Net.is_host():
		_info.text = "Hosting on Steam. Friends use \"Find lobbies\" in the main menu, or paste this lobby ID:\n%d" % Net.steam.lobby_id
		_start.visible = true
		_hint.text = "Start whenever everyone is in. Players can also join while a run is in progress."
	elif Net.is_host():
		var ips := ", ".join(Net.local_addresses())
		_info.text = "You are hosting on port %d.\nSame network: %s\nOver the internet: %s" % [port, ips if ips != "" else "your IP", Net.upnp_status if Net.upnp_status != "" else "forward UDP %d on your router, or use a VPN" % port]
		_start.visible = true
		_hint.text = "Start whenever everyone is in. Players can also join while a run is in progress."
	else:
		_info.text = "Connected to the host."
		_start.visible = false
		_hint.text = "Waiting for the host to start the game..."
