class_name MainMenu
extends CenterContainer

signal host_requested(player_name: String, port: int)
signal join_requested(player_name: String, address: String, port: int)
signal solo_requested(player_name: String)
signal steam_host_requested(player_name: String)
signal steam_join_requested(player_name: String, lobby_id: int)
signal steam_refresh_requested

var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var status: Label
var steam_label: Label
var lobby_list: VBoxContainer
var id_edit: LineEdit


func _ready() -> void:
	var cfg := UiKit.load_settings()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := UiKit.margin(box, 26)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	panel.add_child(scroll)

	box.add_child(UiKit.label("CASH GRAB", 54, UiKit.ACCENT))
	box.add_child(UiKit.label("Co-op wave survival  -  prototype 0.1", 18, UiKit.DIM))
	box.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_child(UiKit.label("Name", 20, UiKit.DIM))
	name_edit = LineEdit.new()
	name_edit.text = cfg.get_value("menu", "name", "Player%d" % (randi() % 90 + 10))
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	row.add_child(UiKit.label("Port", 20, UiKit.DIM))
	port_edit = LineEdit.new()
	port_edit.text = str(cfg.get_value("menu", "port", Net.DEFAULT_PORT))
	port_edit.custom_minimum_size = Vector2(100, 0)
	row.add_child(port_edit)
	box.add_child(row)

	var solo := UiKit.button("Play solo")
	solo.pressed.connect(func() -> void:
		_save()
		solo_requested.emit(name_edit.text))
	box.add_child(solo)

	box.add_child(HSeparator.new())
	var host := UiKit.button("Host a game  (friends join your IP)")
	host.pressed.connect(func() -> void:
		_save()
		host_requested.emit(name_edit.text, _port()))
	box.add_child(host)

	var jrow := HBoxContainer.new()
	addr_edit = LineEdit.new()
	addr_edit.placeholder_text = "Host IP address"
	addr_edit.text = cfg.get_value("menu", "address", "127.0.0.1")
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(addr_edit)
	var join := UiKit.button("Join")
	join.custom_minimum_size = Vector2(120, 42)
	join.pressed.connect(func() -> void:
		_save()
		set_status("Connecting...", UiKit.DIM)
		join_requested.emit(name_edit.text, addr_edit.text.strip_edges(), _port()))
	jrow.add_child(join)
	box.add_child(jrow)

	# --- Steam: no IPs or port forwarding (needs the Steam client running; see README) ---
	box.add_child(HSeparator.new())
	box.add_child(UiKit.label("Play over Steam (no IP / port forwarding)", 20, UiKit.ACCENT))
	steam_label = UiKit.label(Net.steam.status, 15, UiKit.DIM)
	steam_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steam_label.custom_minimum_size = Vector2(480, 0)
	box.add_child(steam_label)
	var srow := HBoxContainer.new()
	var steam_host := UiKit.button("Host on Steam")
	steam_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	steam_host.pressed.connect(func() -> void:
		_save()
		steam_host_requested.emit(name_edit.text))
	srow.add_child(steam_host)
	var refresh := UiKit.button("Find lobbies")
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.pressed.connect(func() -> void: steam_refresh_requested.emit())
	srow.add_child(refresh)
	box.add_child(srow)
	lobby_list = VBoxContainer.new()
	box.add_child(lobby_list)
	var idrow := HBoxContainer.new()
	id_edit = LineEdit.new()
	id_edit.placeholder_text = "or paste a lobby ID"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	idrow.add_child(id_edit)
	var idjoin := UiKit.button("Join by ID")
	idjoin.pressed.connect(func() -> void:
		_save()
		set_status("Joining...", UiKit.DIM)
		steam_join_requested.emit(name_edit.text, id_edit.text.strip_edges().to_int()))
	idrow.add_child(idjoin)
	box.add_child(idrow)
	Net.steam.status_changed.connect(func() -> void: steam_label.text = Net.steam.status)
	Net.steam.lobbies_listed.connect(_show_lobbies)

	status = UiKit.label("", 18, UiKit.BAD)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(480, 28)
	box.add_child(status)

	var quit := UiKit.button("Quit")
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func _show_lobbies(list: Array) -> void:
	for c in lobby_list.get_children():
		c.queue_free()
	for l in list:
		var b := UiKit.button("Join %s's game  (%d/%d)" % [l["name"] if l["name"] != "" else "unnamed", l["players"], Net.MAX_PLAYERS])
		var id: int = l["id"]
		b.pressed.connect(func() -> void:
			_save()
			set_status("Joining...", UiKit.DIM)
			steam_join_requested.emit(name_edit.text, id))
		lobby_list.add_child(b)


func set_status(text: String, color: Color = UiKit.BAD) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


func _port() -> int:
	var p := port_edit.text.to_int()
	return p if p > 0 and p < 65536 else Net.DEFAULT_PORT


func _save() -> void:
	var cfg := UiKit.load_settings()
	cfg.set_value("menu", "name", name_edit.text)
	cfg.set_value("menu", "address", addr_edit.text)
	cfg.set_value("menu", "port", _port())
	cfg.save(UiKit.SETTINGS_PATH)
